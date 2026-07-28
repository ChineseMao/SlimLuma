import Foundation
import SlimLumaKit

/// Watches user-selected folders with stable snapshots.
///
/// A file is reported only after its size and modification date remain stable
/// across the configured number of polls. This prevents the compression queue
/// from reading a large video or PDF while another app is still copying it.
actor FolderWatchService {
    struct Configuration: Sendable {
        var folders: [URL]
        var scansSubdirectories: Bool
        var pollingInterval: Duration
        var requiredStableSnapshots: Int
        var importsExistingFiles: Bool
        var ignoredFilenameSuffixes: [String]
        var ignoredDirectories: [URL]

        init(
            folders: [URL],
            scansSubdirectories: Bool = true,
            pollingInterval: Duration = .seconds(2),
            requiredStableSnapshots: Int = 2,
            importsExistingFiles: Bool = false,
            ignoredFilenameSuffixes: [String] = ["-slim"],
            ignoredDirectories: [URL] = []
        ) {
            self.folders = folders
            self.scansSubdirectories = scansSubdirectories
            self.pollingInterval = pollingInterval
            self.requiredStableSnapshots = max(2, requiredStableSnapshots)
            self.importsExistingFiles = importsExistingFiles
            self.ignoredFilenameSuffixes = ignoredFilenameSuffixes
            self.ignoredDirectories = ignoredDirectories
        }
    }

    struct WatchIssue: Sendable, Equatable, Identifiable {
        let folder: URL
        let message: String

        var id: String {
            folder.standardizedFileURL.path + "\u{0}" + message
        }
    }

    typealias NewFilesHandler = @Sendable ([URL]) async -> Void
    typealias IssueHandler = @Sendable ([WatchIssue]) async -> Void

    private struct Fingerprint: Sendable, Equatable {
        let byteCount: Int64
        let modificationDate: Date
    }

    private struct Candidate: Sendable {
        let identity: String
        let url: URL
        let fingerprint: Fingerprint
    }

    private struct PendingCandidate: Sendable {
        var candidate: Candidate
        var stableSnapshotCount: Int
    }

    private final class SecurityScopeLease: @unchecked Sendable {
        let url: URL
        private let isActive: Bool

        init(url: URL) {
            self.url = url
            isActive = url.startAccessingSecurityScopedResource()
        }

        deinit {
            if isActive {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    private var configuration: Configuration?
    private var knownIdentities = Set<String>()
    private var pendingCandidates: [String: PendingCandidate] = [:]
    private var watchTask: Task<Void, Never>?
    private var deliveryTask: Task<Void, Never>?
    private var issueDeliveryTask: Task<Void, Never>?
    private var securityScopeLeases: [SecurityScopeLease] = []
    private var onNewFiles: NewFilesHandler?
    private var onIssues: IssueHandler?
    private var lastIssues: [WatchIssue] = []

    var isWatching: Bool {
        watchTask != nil
    }

    /// Starts a new watch session. Calling this again replaces the prior session.
    ///
    /// The event handler should enqueue URLs quickly and return; compression can
    /// continue independently after the URLs have been handed off.
    func start(
        configuration requestedConfiguration: Configuration,
        onNewFiles: @escaping NewFilesHandler,
        onIssues: IssueHandler? = nil
    ) {
        stop()

        let normalizedConfiguration = normalize(requestedConfiguration)
        configuration = normalizedConfiguration
        self.onNewFiles = onNewFiles
        self.onIssues = onIssues
        securityScopeLeases = normalizedConfiguration.folders.map(
            SecurityScopeLease.init(url:)
        )

        let initialScan = scan(using: normalizedConfiguration)
        if normalizedConfiguration.importsExistingFiles {
            pendingCandidates = Dictionary(
                uniqueKeysWithValues: initialScan.candidates.map {
                    (
                        $0.identity,
                        PendingCandidate(candidate: $0, stableSnapshotCount: 1)
                    )
                }
            )
        } else {
            knownIdentities = Set(initialScan.candidates.map(\.identity))
        }
        deliverIssues(initialScan.issues)

        watchTask = Task { [weak self] in
            guard let self else { return }
            await self.runWatchLoop()
        }
    }

    /// Stops polling, cancels queued deliveries, and releases security scopes.
    func stop() {
        watchTask?.cancel()
        watchTask = nil
        deliveryTask?.cancel()
        deliveryTask = nil
        issueDeliveryTask?.cancel()
        issueDeliveryTask = nil
        configuration = nil
        knownIdentities.removeAll()
        pendingCandidates.removeAll()
        onNewFiles = nil
        onIssues = nil
        lastIssues.removeAll()
        securityScopeLeases.removeAll()
    }

    private func runWatchLoop() async {
        while !Task.isCancelled {
            guard let configuration else { return }
            do {
                try await Task.sleep(for: configuration.pollingInterval)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            poll(using: configuration)
        }
    }

    private func poll(using configuration: Configuration) {
        let scanResult = scan(using: configuration)
        let currentIdentities = Set(scanResult.candidates.map(\.identity))

        // Files that disappear before becoming stable are not imported.
        pendingCandidates = pendingCandidates.filter {
            currentIdentities.contains($0.key)
        }

        var readyURLs: [URL] = []
        for candidate in scanResult.candidates {
            guard !knownIdentities.contains(candidate.identity) else { continue }

            if var pending = pendingCandidates[candidate.identity] {
                if pending.candidate.fingerprint == candidate.fingerprint {
                    pending.stableSnapshotCount += 1
                } else {
                    pending.candidate = candidate
                    pending.stableSnapshotCount = 1
                }

                if pending.stableSnapshotCount >= configuration.requiredStableSnapshots {
                    knownIdentities.insert(candidate.identity)
                    pendingCandidates.removeValue(forKey: candidate.identity)
                    readyURLs.append(candidate.url)
                } else {
                    pendingCandidates[candidate.identity] = pending
                }
            } else {
                pendingCandidates[candidate.identity] = PendingCandidate(
                    candidate: candidate,
                    stableSnapshotCount: 1
                )
            }
        }

        deliverNewFiles(readyURLs)
        deliverIssues(scanResult.issues)
    }

    private func deliverNewFiles(_ urls: [URL]) {
        guard !urls.isEmpty, let onNewFiles else { return }
        let sortedURLs = urls.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
        let previousDelivery = deliveryTask
        deliveryTask = Task {
            await previousDelivery?.value
            guard !Task.isCancelled else { return }
            await onNewFiles(sortedURLs)
        }
    }

    private func deliverIssues(_ issues: [WatchIssue]) {
        let sortedIssues = issues.sorted {
            if $0.folder.path == $1.folder.path {
                return $0.message < $1.message
            }
            return $0.folder.path < $1.folder.path
        }
        guard sortedIssues != lastIssues else { return }
        lastIssues = sortedIssues
        guard let onIssues else { return }

        issueDeliveryTask?.cancel()
        issueDeliveryTask = Task {
            guard !Task.isCancelled else { return }
            // An empty array explicitly tells the UI that prior issues resolved.
            await onIssues(sortedIssues)
        }
    }

    private func normalize(_ configuration: Configuration) -> Configuration {
        var normalized = configuration
        var seenPaths = Set<String>()
        normalized.folders = configuration.folders.compactMap { url in
            let normalizedURL = url.standardizedFileURL
            guard seenPaths.insert(normalizedURL.path).inserted else { return nil }
            return normalizedURL
        }
        normalized.ignoredDirectories = configuration.ignoredDirectories.map {
            $0.standardizedFileURL
        }
        normalized.ignoredFilenameSuffixes = configuration.ignoredFilenameSuffixes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        normalized.requiredStableSnapshots = max(
            2,
            configuration.requiredStableSnapshots
        )
        if normalized.pollingInterval < .milliseconds(250) {
            normalized.pollingInterval = .milliseconds(250)
        }
        return normalized
    }

    private func scan(
        using configuration: Configuration
    ) -> (candidates: [Candidate], issues: [WatchIssue]) {
        var candidatesByIdentity: [String: Candidate] = [:]
        var issues: [WatchIssue] = []

        for folder in configuration.folders {
            let values: URLResourceValues
            do {
                values = try folder.resourceValues(
                    forKeys: [.isDirectoryKey, .isReadableKey]
                )
            } catch {
                issues.append(
                    WatchIssue(folder: folder, message: error.localizedDescription)
                )
                continue
            }

            guard values.isDirectory == true,
                  values.isReadable != false else {
                issues.append(
                    WatchIssue(folder: folder, message: "文件夹不存在或无法读取。")
                )
                continue
            }

            let urls: [URL]
            do {
                urls = try mediaURLs(in: folder, recursively: configuration.scansSubdirectories)
            } catch {
                issues.append(
                    WatchIssue(folder: folder, message: error.localizedDescription)
                )
                continue
            }

            for url in urls {
                guard !isIgnored(url, using: configuration),
                      let candidate = candidate(for: url) else {
                    continue
                }
                candidatesByIdentity[candidate.identity] = candidate
            }
        }

        return (Array(candidatesByIdentity.values), issues)
    }

    private func mediaURLs(in folder: URL, recursively: Bool) throws -> [URL] {
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isDirectoryKey,
            .isHiddenKey,
            .isSymbolicLinkKey,
            .fileResourceIdentifierKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]

        if !recursively {
            return try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )
        }

        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }
        return enumerator.compactMap { $0 as? URL }
    }

    private func candidate(for url: URL) -> Candidate? {
        guard MediaKind.detect(url: url) != .unknown else { return nil }

        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isHiddenKey,
            .isSymbolicLinkKey,
            .fileResourceIdentifierKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isRegularFile == true,
              values.isHidden != true,
              values.isSymbolicLink != true,
              let byteCount = values.fileSize,
              let modificationDate = values.contentModificationDate else {
            return nil
        }

        let normalizedURL = url.standardizedFileURL
        let identity: String
        if let resourceIdentifier = values.fileResourceIdentifier {
            identity = "resource:\(String(describing: resourceIdentifier))"
        } else {
            identity = "path:\(normalizedURL.path)"
        }

        return Candidate(
            identity: identity,
            url: normalizedURL,
            fingerprint: Fingerprint(
                byteCount: Int64(byteCount),
                modificationDate: modificationDate
            )
        )
    }

    private func isIgnored(_ url: URL, using configuration: Configuration) -> Bool {
        let normalizedPath = url.standardizedFileURL.path
        for ignoredDirectory in configuration.ignoredDirectories {
            let directoryPath = ignoredDirectory.standardizedFileURL.path
            if normalizedPath == directoryPath
                || normalizedPath.hasPrefix(directoryPath + "/") {
                return true
            }
        }

        let stem = url.deletingPathExtension().lastPathComponent
        return configuration.ignoredFilenameSuffixes.contains { suffix in
            let escapedSuffix = NSRegularExpression.escapedPattern(for: suffix)
            return stem.range(
                of: "\(escapedSuffix)(?:-[0-9]+)?$",
                options: [.regularExpression, .caseInsensitive]
            ) != nil
        }
    }

    deinit {
        watchTask?.cancel()
        deliveryTask?.cancel()
        issueDeliveryTask?.cancel()
    }
}

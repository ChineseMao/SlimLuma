import Darwin
import Foundation

@_silgen_name("flock")
func slimLumaFlock(
    _ descriptor: Int32,
    _ operation: Int32
) -> Int32

public final class TemporaryWorkspaceLease: @unchecked Sendable {
    public let outputURL: URL

    private let workspaceURL: URL
    private let stateLock = NSLock()
    private var lockDescriptor: Int32?

    fileprivate init(
        workspaceURL: URL,
        outputURL: URL,
        lockDescriptor: Int32
    ) {
        self.workspaceURL = workspaceURL
        self.outputURL = outputURL
        self.lockDescriptor = lockDescriptor
    }

    public func remove() throws {
        guard let descriptor = takeLockDescriptor() else {
            return
        }
        defer {
            _ = slimLumaFlock(descriptor, LOCK_UN)
            _ = Darwin.close(descriptor)
        }
        try FileManager.default.removeItem(at: workspaceURL)
    }

    deinit {
        guard let descriptor = takeLockDescriptor() else {
            return
        }
        _ = slimLumaFlock(descriptor, LOCK_UN)
        _ = Darwin.close(descriptor)
    }

    private func takeLockDescriptor() -> Int32? {
        stateLock.lock()
        defer { stateLock.unlock() }
        let descriptor = lockDescriptor
        lockDescriptor = nil
        return descriptor
    }
}

public struct OutputPlanner: Sendable {
    private static let temporaryRootName = "SlimLuma"
    private static let workspacePrefix = "work-"
    private static let workspaceLockName = ".workspace.lock"
    private static let workspaceLockMagic = Data(
        "SlimLuma workspace lock v1\n".utf8
    )
    private static let staleWorkspaceAge: TimeInterval = 0

    public init() {}

    public func destinationURL(
        for inputURL: URL,
        kind: MediaKind,
        settings: CompressionSettings
    ) throws -> URL {
        let directory: URL
        switch settings.output.location {
        case .alongsideOriginal:
            directory = inputURL.deletingLastPathComponent()
        case .customDirectory:
            guard let path = settings.output.customDirectoryPath, !path.isEmpty else {
                throw CompressionError.invalidSettings("请选择输出文件夹")
            }
            directory = URL(fileURLWithPath: path, isDirectory: true)
        }

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let outputExtension = fileExtension(
            inputURL: inputURL,
            kind: kind,
            settings: settings
        )
        let suffix = sanitizedFilenameSuffix(settings.output.filenameSuffix)
        let baseName = inputURL.deletingPathExtension().lastPathComponent + suffix
        let initialURL = directory
            .appendingPathComponent(baseName)
            .appendingPathExtension(outputExtension)

        return uniqueURL(startingAt: initialURL, avoiding: inputURL)
    }

    public func temporaryWorkspace(
        for inputURL: URL,
        kind: MediaKind,
        settings: CompressionSettings
    ) throws -> TemporaryWorkspaceLease {
        removeStaleTemporaryWorkspaces()
        let root = try secureTemporaryRoot()
        let temporaryDirectory = root.appendingPathComponent(
            "\(Self.workspacePrefix)\(UUID().uuidString)",
            isDirectory: true
        )
        try createPrivateDirectory(at: temporaryDirectory)

        do {
            let lockDescriptor = try createAndLockWorkspaceMarker(
                in: temporaryDirectory
            )
            let outputURL = temporaryDirectory
                .appendingPathComponent("output")
                .appendingPathExtension(
                    fileExtension(
                        inputURL: inputURL,
                        kind: kind,
                        settings: settings
                    )
                )
            return TemporaryWorkspaceLease(
                workspaceURL: temporaryDirectory,
                outputURL: outputURL,
                lockDescriptor: lockDescriptor
            )
        } catch {
            try? FileManager.default.removeItem(at: temporaryDirectory)
            throw error
        }
    }

    func removeStaleTemporaryWorkspaces(
        now: Date = Date(),
        maximumAge: TimeInterval = Self.staleWorkspaceAge
    ) {
        guard let root = try? secureTemporaryRoot(),
              let children = try? FileManager.default.contentsOfDirectory(
                  at: root,
                  includingPropertiesForKeys: [
                      .contentModificationDateKey,
                      .isDirectoryKey,
                      .isSymbolicLinkKey
                  ],
                  options: [.skipsHiddenFiles]
              ) else {
            return
        }

        let cutoff = now.addingTimeInterval(-maximumAge)
        for child in children
        where isOwnedWorkspaceName(child.lastPathComponent) {
            guard let values = try? child.resourceValues(forKeys: [
                .contentModificationDateKey,
                .isDirectoryKey,
                .isSymbolicLinkKey
            ]),
            values.isDirectory == true,
            values.isSymbolicLink != true,
            let modifiedAt = values.contentModificationDate,
            modifiedAt < cutoff else {
                continue
            }
            removeWorkspaceIfInactiveAndOwned(child)
        }
    }

    private func createAndLockWorkspaceMarker(
        in workspaceURL: URL
    ) throws -> Int32 {
        let lockURL = workspaceURL.appendingPathComponent(
            Self.workspaceLockName,
            isDirectory: false
        )
        let descriptor = Darwin.open(
            lockURL.path,
            O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard descriptor >= 0 else {
            throw CompressionError.outputInvalid(
                "无法创建 SlimLuma 临时工作区锁"
            )
        }

        var shouldClose = true
        defer {
            if shouldClose {
                _ = Darwin.close(descriptor)
            }
        }

        guard slimLumaFlock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw CompressionError.outputInvalid(
                "无法占用 SlimLuma 临时工作区"
            )
        }
        let written = Self.workspaceLockMagic.withUnsafeBytes { bytes in
            Darwin.write(descriptor, bytes.baseAddress, bytes.count)
        }
        guard written == Self.workspaceLockMagic.count,
              Darwin.fsync(descriptor) == 0 else {
            _ = slimLumaFlock(descriptor, LOCK_UN)
            throw CompressionError.outputInvalid(
                "无法初始化 SlimLuma 临时工作区锁"
            )
        }

        shouldClose = false
        return descriptor
    }

    private func removeWorkspaceIfInactiveAndOwned(_ workspaceURL: URL) {
        let lockURL = workspaceURL.appendingPathComponent(
            Self.workspaceLockName,
            isDirectory: false
        )
        let descriptor = Darwin.open(
            lockURL.path,
            O_RDWR | O_CLOEXEC | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            return
        }
        defer { _ = Darwin.close(descriptor) }

        var fileStatus = stat()
        guard Darwin.fstat(descriptor, &fileStatus) == 0,
              (fileStatus.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              fileStatus.st_uid == Darwin.getuid(),
              workspaceMarkerMatches(descriptor),
              slimLumaFlock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            return
        }
        defer { _ = slimLumaFlock(descriptor, LOCK_UN) }

        try? FileManager.default.removeItem(at: workspaceURL)
    }

    private func workspaceMarkerMatches(_ descriptor: Int32) -> Bool {
        var buffer = [UInt8](
            repeating: 0,
            count: Self.workspaceLockMagic.count
        )
        let bytesRead = buffer.withUnsafeMutableBytes { bytes in
            Darwin.pread(
                descriptor,
                bytes.baseAddress,
                bytes.count,
                0
            )
        }
        return bytesRead == Self.workspaceLockMagic.count
            && Data(buffer) == Self.workspaceLockMagic
    }

    private func isOwnedWorkspaceName(_ name: String) -> Bool {
        guard name.hasPrefix(Self.workspacePrefix) else {
            return false
        }
        let identifier = String(name.dropFirst(Self.workspacePrefix.count))
        return UUID(uuidString: identifier) != nil
    }

    private func secureTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(Self.temporaryRootName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let values = try root.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey
        ])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw CompressionError.outputInvalid(
                "SlimLuma 临时工作区不是安全目录"
            )
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: root.path
        )
        return root
    }

    private func createPrivateDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: url.path
        )
    }

    private func fileExtension(
        inputURL: URL,
        kind: MediaKind,
        settings: CompressionSettings
    ) -> String {
        switch kind {
        case .image:
            return settings.image.format.fileExtension ?? inputURL.pathExtension.lowercased()
        case .video:
            return settings.video.codec.defaultExtension
        case .pdf:
            return "pdf"
        case .unknown:
            return inputURL.pathExtension.lowercased()
        }
    }

    public func sanitizedFilenameSuffix(_ suffix: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\")
        let parts = suffix.components(separatedBy: invalidCharacters)
        let safe = parts.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return safe.isEmpty ? "-slim" : safe
    }

    private func uniqueURL(startingAt initialURL: URL, avoiding inputURL: URL) -> URL {
        let inputPath = inputURL.standardizedFileURL.path
        if !FileManager.default.fileExists(atPath: initialURL.path),
           initialURL.standardizedFileURL.path != inputPath {
            return initialURL
        }

        let directory = initialURL.deletingLastPathComponent()
        let fileExtension = initialURL.pathExtension
        let baseName = initialURL.deletingPathExtension().lastPathComponent

        for index in 2...10_000 {
            let candidate = directory
                .appendingPathComponent("\(baseName)-\(index)")
                .appendingPathExtension(fileExtension)
            if !FileManager.default.fileExists(atPath: candidate.path),
               candidate.standardizedFileURL.path != inputPath {
                return candidate
            }
        }

        return directory
            .appendingPathComponent("\(baseName)-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
    }
}

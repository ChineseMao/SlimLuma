import AppKit
import Foundation
import ImageIO
import SlimLumaKit

/// Copies supported pasteboard content into an app-owned import batch.
///
/// Callers should enqueue the returned URLs instead of the original pasteboard
/// URLs. This keeps compression from ever writing beside or replacing a source
/// that was pasted from another application.
actor ClipboardImportService {
    struct ImportResult: Sendable {
        let importedURLs: [URL]
        let skippedItemNames: [String]
        let batchDirectory: URL
    }

    enum ImportError: LocalizedError, Sendable {
        case pasteboardIsEmpty
        case noSupportedContent([String])
        case invalidImageData
        case applicationSupportUnavailable
        case unsafeImportDirectory

        var errorDescription: String? {
            switch self {
            case .pasteboardIsEmpty:
                return "剪贴板中没有可导入的文件或图片。"
            case .noSupportedContent(let names):
                if names.isEmpty {
                    return "剪贴板内容不是 SlimLuma 支持的图片、视频或 PDF。"
                }
                return "剪贴板中的这些项目不受支持：\(L10n.list(names))"
            case .invalidImageData:
                return "剪贴板图片数据已损坏或无法读取。"
            case .applicationSupportUnavailable:
                return "无法访问 SlimLuma 的应用支持目录。"
            case .unsafeImportDirectory:
                return "SlimLuma 的导入暂存目录不安全或不可用。"
            }
        }
    }

    private enum PasteboardPayload: Sendable {
        case file(URL)
        case image(data: Data, fileExtension: String)
    }

    private let importRootOverride: URL?

    init(importRoot: URL? = nil) {
        importRootOverride = importRoot
    }

    /// Imports all supported content currently present on the general pasteboard.
    ///
    /// File URLs are coordinated and copied without modifying their source.
    /// Bitmap pasteboard content is stored as PNG when available, otherwise TIFF.
    func importFromGeneralPasteboard() async throws -> ImportResult {
        let payloads = await MainActor.run {
            Self.snapshotGeneralPasteboard()
        }
        guard !payloads.isEmpty else {
            throw ImportError.pasteboardIsEmpty
        }

        return try importPayloads(payloads)
    }

    /// Copies file URLs received from App Intents or other external entry points
    /// into the same app-owned import area used for clipboard content.
    func importFiles(_ urls: [URL]) throws -> ImportResult {
        try importPayloads(urls.map(PasteboardPayload.file))
    }

    /// Removes one incomplete app-owned batch.
    ///
    /// This is intentionally limited to a direct child of the dedicated import
    /// root. Completed batches are retained because the default output policy
    /// may place compressed results beside these app-owned source copies.
    func discardBatch(_ batchDirectory: URL) throws {
        let root = try importRoot().standardizedFileURL
        let batch = batchDirectory.standardizedFileURL
        guard isDirectChild(batch, of: root) else {
            return
        }
        guard FileManager.default.fileExists(atPath: batch.path) else {
            return
        }

        let values = try batch.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard values.isDirectory == true,
              values.isSymbolicLink != true else {
            return
        }
        try FileManager.default.removeItem(at: batch)
    }

    private func importPayloads(
        _ payloads: [PasteboardPayload]
    ) throws -> ImportResult {
        try Task.checkCancellation()
        let root = try importRoot()
        let batchDirectory = root
            .appendingPathComponent(Self.batchName(), isDirectory: true)
        try prepareDirectory(batchDirectory)

        var importedURLs: [URL] = []
        var skippedItemNames: [String] = []

        do {
            for payload in payloads {
                try Task.checkCancellation()
                switch payload {
                case .file(let sourceURL):
                    guard MediaKind.detect(url: sourceURL) != .unknown else {
                        skippedItemNames.append(sourceURL.lastPathComponent)
                        continue
                    }
                    guard try isSafeRegularFile(sourceURL) else {
                        skippedItemNames.append(sourceURL.lastPathComponent)
                        continue
                    }

                    let destination = uniqueDestination(
                        in: batchDirectory,
                        preferredName: safeFilename(sourceURL.lastPathComponent)
                    )
                    try coordinatedCopy(from: sourceURL, to: destination)
                    try Task.checkCancellation()
                    importedURLs.append(destination)

                case .image(let data, let fileExtension):
                    guard Self.isValidImageData(data) else {
                        throw ImportError.invalidImageData
                    }
                    let destination = uniqueDestination(
                        in: batchDirectory,
                        preferredName: L10n.text(
                            "剪贴板图片.\(fileExtension)"
                        )
                    )
                    try data.write(to: destination, options: [.atomic])
                    try Task.checkCancellation()
                    importedURLs.append(destination)
                }
            }
            try Task.checkCancellation()
        } catch {
            // A partial batch must never be handed to the compression queue.
            try? FileManager.default.removeItem(at: batchDirectory)
            throw error
        }

        guard !importedURLs.isEmpty else {
            try? FileManager.default.removeItem(at: batchDirectory)
            throw ImportError.noSupportedContent(skippedItemNames)
        }

        return ImportResult(
            importedURLs: importedURLs,
            skippedItemNames: skippedItemNames,
            batchDirectory: batchDirectory
        )
    }

    @MainActor
    private static func snapshotGeneralPasteboard() -> [PasteboardPayload] {
        let pasteboard = NSPasteboard.general
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]

        let fileURLs = (pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL]) ?? []

        // Finder also publishes a TIFF preview for copied image files. Prefer
        // the actual file URLs so the same item is not imported twice.
        if !fileURLs.isEmpty {
            var seenPaths = Set<String>()
            return fileURLs.compactMap { url in
                let path = url.standardizedFileURL.path
                guard seenPaths.insert(path).inserted else { return nil }
                return .file(url)
            }
        }

        if let pngData = pasteboard.data(forType: .png) {
            return [.image(data: pngData, fileExtension: "png")]
        }
        if let tiffData = pasteboard.data(forType: .tiff) {
            return [.image(data: tiffData, fileExtension: "tiff")]
        }
        return []
    }

    nonisolated private static func isValidImageData(_ data: Data) -> Bool {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return false
        }
        return CGImageSourceGetCount(source) > 0
    }

    private func importRoot() throws -> URL {
        let root: URL
        if let importRootOverride {
            root = importRootOverride.standardizedFileURL
        } else {
            root = try Self.defaultImportRoot()
        }

        if FileManager.default.fileExists(atPath: root.path) {
            let values = try root.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            guard values.isDirectory == true,
                  values.isSymbolicLink != true else {
                throw ImportError.unsafeImportDirectory
            }
        }
        return root
    }

    nonisolated static func defaultImportRoot() throws -> URL {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw ImportError.applicationSupportUnavailable
        }
        return applicationSupport
            .appendingPathComponent("SlimLuma", isDirectory: true)
            .appendingPathComponent("Imports", isDirectory: true)
            .appendingPathComponent("Clipboard", isDirectory: true)
    }

    private func prepareDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        try? FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: directory.path
        )
        var mutableDirectory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutableDirectory.setResourceValues(values)
    }

    private func isSafeRegularFile(_ url: URL) throws -> Bool {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let values = try url.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isHiddenKey]
        )
        return values.isRegularFile == true
            && values.isSymbolicLink != true
            && values.isHidden != true
            && FileManager.default.isReadableFile(atPath: url.path)
    }

    private func coordinatedCopy(from sourceURL: URL, to destinationURL: URL) throws {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var operationError: Error?
        coordinator.coordinate(
            readingItemAt: sourceURL,
            options: .withoutChanges,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                try FileManager.default.copyItem(
                    at: coordinatedURL,
                    to: destinationURL
                )
            } catch {
                operationError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let operationError {
            throw operationError
        }
    }

    private func uniqueDestination(in directory: URL, preferredName: String) -> URL {
        let preferredURL = directory.appendingPathComponent(preferredName)
        guard FileManager.default.fileExists(atPath: preferredURL.path) else {
            return preferredURL
        }

        let fileExtension = preferredURL.pathExtension
        let stem = preferredURL.deletingPathExtension().lastPathComponent
        for index in 2...10_000 {
            var candidate = directory.appendingPathComponent("\(stem)-\(index)")
            if !fileExtension.isEmpty {
                candidate.appendPathExtension(fileExtension)
            }
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        var fallback = directory
            .appendingPathComponent("\(stem)-\(UUID().uuidString)")
        if !fileExtension.isEmpty {
            fallback.appendPathExtension(fileExtension)
        }
        return fallback
    }

    private func safeFilename(_ candidate: String) -> String {
        let source = candidate as NSString
        let originalStem = source.deletingPathExtension
        let originalExtension = source.pathExtension
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "-_ "))

        let sanitizedScalars = originalStem.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(String(scalar)) : "-"
        }
        var stem = String(sanitizedScalars)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        stem = String(stem.prefix(120))
        if stem.isEmpty || stem == "." || stem == ".." {
            stem = L10n.text("剪贴板文件")
        }

        let safeExtension = originalExtension
            .lowercased()
            .filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return safeExtension.isEmpty ? stem : "\(stem).\(safeExtension)"
    }

    private func isDirectChild(_ child: URL, of parent: URL) -> Bool {
        child.deletingLastPathComponent().standardizedFileURL.path
            == parent.standardizedFileURL.path
    }

    nonisolated private static func batchName() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return "\(timestamp)-\(UUID().uuidString)"
    }
}

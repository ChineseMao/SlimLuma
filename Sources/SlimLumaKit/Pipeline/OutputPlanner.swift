import Foundation

public struct OutputPlanner: Sendable {
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

    public func temporaryURL(
        for inputURL: URL,
        kind: MediaKind,
        settings: CompressionSettings
    ) throws -> URL {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SlimLuma", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )

        return temporaryDirectory
            .appendingPathComponent("output")
            .appendingPathExtension(
                fileExtension(inputURL: inputURL, kind: kind, settings: settings)
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

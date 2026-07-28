import AppIntents
import AppKit
import Foundation
import UniformTypeIdentifiers

@available(macOS 15.0, *)
struct AddMediaToSlimLumaIntent: AppIntent {
    static let title: LocalizedStringResource = "添加到 SlimLuma 压缩队列"
    static let description = IntentDescription(
        "把图片、视频或 PDF 交给 SlimLuma，并可在文件就绪后自动开始压缩。"
    )
    static var openAppWhenRun: Bool { true }

    @available(macOS 26.0, *)
    static var supportedModes: IntentModes {
        [.foreground(.immediate)]
    }

    @Parameter(
        title: "文件",
        supportedContentTypes: [
            UTType.image,
            UTType.movie,
            UTType.pdf
        ]
    )
    var files: [IntentFile]

    @Parameter(title: "自动开始压缩", default: false)
    var startsCompression: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("把 \(\.$files) 添加到 SlimLuma")
    }

    func perform() async throws -> some IntentResult {
        guard !files.isEmpty else {
            throw SlimLumaIntentError.noFiles
        }
        try Task.checkCancellation()

        let imported: ClipboardImportService.ImportResult
        let importer = ClipboardImportService()
        do {
            imported = try await importIntentFiles(
                files,
                at: 0,
                materializedURLs: [],
                importer: importer
            )
        } catch {
            throw SlimLumaIntentError.importFailed(error.localizedDescription)
        }

        do {
            try Task.checkCancellation()
            _ = try AppIntentImportInbox.enqueue(
                importedURLs: imported.importedURLs,
                batchDirectory: imported.batchDirectory,
                startsCompression: startsCompression
            )
        } catch {
            try? await importer.discardBatch(imported.batchDirectory)
            throw SlimLumaIntentError.importFailed(error.localizedDescription)
        }

        await MainActor.run {
            let delegate = NSApplication.shared.delegate
                as? SlimLumaApplicationDelegate
            delegate?.handlePendingAppIntentImports()
        }

        // The app itself is the visible completion state. Returning a dialog
        // here can leave Shortcuts waiting for a presentation host while the
        // app is launching without a window.
        return .result()
    }

    private func importIntentFiles(
        _ intentFiles: [IntentFile],
        at index: Int,
        materializedURLs: [URL],
        importer: ClipboardImportService
    ) async throws -> ClipboardImportService.ImportResult {
        try Task.checkCancellation()
        guard index < intentFiles.count else {
            return try await importer.importFiles(materializedURLs)
        }

        let intentFile = intentFiles[index]
        guard let contentType = intentFile.type
            ?? intentFile.availableContentTypes.first else {
            throw SlimLumaIntentError.unknownFileType(intentFile.filename)
        }

        return try await intentFile.withFile(
            contentType: contentType,
            allowOpenInPlace: true
        ) { fileURL, _ in
            try Task.checkCancellation()
            return try await importIntentFiles(
                intentFiles,
                at: index + 1,
                materializedURLs: materializedURLs + [fileURL],
                importer: importer
            )
        }
    }
}

@available(macOS 15.0, *)
struct SlimLumaAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddMediaToSlimLumaIntent(),
            phrases: [
                "用 \(.applicationName) 压缩文件",
                "添加文件到 \(.applicationName)"
            ],
            shortTitle: "添加到压缩队列",
            systemImageName: "arrow.down.right.and.arrow.up.left"
        )
    }

    static var shortcutTileColor: ShortcutTileColor {
        .purple
    }
}

@available(macOS 15.0, *)
private enum SlimLumaIntentError: LocalizedError {
    case noFiles
    case importFailed(String)
    case unknownFileType(String)

    var errorDescription: String? {
        switch self {
        case .noFiles:
            L10n.text("没有收到可压缩的文件。")
        case .importFailed(let message):
            L10n.text("无法导入文件：\(message)")
        case .unknownFileType(let filename):
            L10n.text("无法识别“\(filename)”的文件类型。")
        }
    }
}

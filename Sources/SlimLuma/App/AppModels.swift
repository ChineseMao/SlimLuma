import Foundation
import SlimLumaKit

enum AppSection: String, CaseIterable, Identifiable {
    case compress
    case automations
    case presets
    case history
    case principles
    case engines

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compress: "媒体压缩"
        case .automations: "自动化"
        case .presets: "预设"
        case .history: "历史记录"
        case .principles: "功能与原理"
        case .engines: "引擎与设置"
        }
    }

    var symbolName: String {
        switch self {
        case .compress: "arrow.down.right.and.arrow.up.left"
        case .automations: "folder.badge.gearshape"
        case .presets: "square.stack.3d.up"
        case .history: "clock.arrow.circlepath"
        case .principles: "book.closed"
        case .engines: "gearshape.2"
        }
    }
}

enum QueueItemStatus: Equatable, Sendable {
    case waiting
    case processing
    case completed
    case skipped
    case failed(String)
    case cancelled

    var displayName: String {
        switch self {
        case .waiting: "等待中"
        case .processing: "压缩中"
        case .completed: "已完成"
        case .skipped: "未生成"
        case .failed: "失败"
        case .cancelled: "已取消"
        }
    }

    var symbolName: String {
        switch self {
        case .waiting: "circle"
        case .processing: "progress.indicator"
        case .completed: "checkmark.circle.fill"
        case .skipped: "equal.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle"
        }
    }
}

struct AutomationSettings: Codable, Equatable, Sendable {
    var watchedFolderPaths: [String] = []
    var scansSubdirectories = true
    var importsExistingFiles = false
    var folderWatchEnabled = false
    var autoStartsFolderCompression = true
    var autoStartsClipboardCompression = false
}

struct CompressionQueueItem: Identifiable, Sendable {
    let id: UUID
    let inputURL: URL
    let mediaKind: MediaKind
    let originalBytes: Int64
    var status: QueueItemStatus
    var outputURL: URL?
    var outputBytes: Int64?
    var engineName: String?
    var detailMessage: String?
    var settingsOverride: CompressionSettings?
    /// Kept only in memory for the lifetime of this queue item. Passwords are
    /// never written to presets, history or UserDefaults.
    var pdfPassword: String?
    var progressFraction: Double
    var progressStage: String?
    var estimatedRemainingSeconds: TimeInterval?

    init(url: URL) {
        id = UUID()
        inputURL = url
        mediaKind = MediaKind.detect(url: url)
        let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        originalBytes = Int64(size ?? 0)
        status = .waiting
        settingsOverride = nil
        pdfPassword = nil
        progressFraction = 0
        progressStage = nil
        estimatedRemainingSeconds = nil
    }

    var savedBytes: Int64 {
        max(0, originalBytes - (outputBytes ?? originalBytes))
    }
}

struct HistoryEntry: Codable, Identifiable {
    let id: UUID
    let completedAt: Date
    let inputPath: String
    let outputPath: String?
    let mediaKind: MediaKind
    let engineName: String
    let originalBytes: Int64
    let outputBytes: Int64?
    let duration: TimeInterval
    let wasSkipped: Bool
    let warning: String?
    let failureMessage: String?

    init(result: CompressionResult) {
        id = UUID()
        completedAt = Date()
        inputPath = result.inputURL.path
        outputPath = result.outputURL?.path
        mediaKind = result.mediaKind
        engineName = result.engineName
        originalBytes = result.originalBytes
        outputBytes = result.outputBytes
        duration = result.duration
        wasSkipped = result.skippedBecauseLarger
        warning = result.warning
        failureMessage = nil
    }

    init(item: CompressionQueueItem, failureMessage: String) {
        id = UUID()
        completedAt = Date()
        inputPath = item.inputURL.path
        outputPath = nil
        mediaKind = item.mediaKind
        engineName = item.engineName ?? "未完成"
        originalBytes = item.originalBytes
        outputBytes = nil
        duration = 0
        wasSkipped = false
        warning = nil
        self.failureMessage = failureMessage
    }

    var inputURL: URL { URL(fileURLWithPath: inputPath) }
    var outputURL: URL? { outputPath.map { URL(fileURLWithPath: $0) } }
    var savedBytes: Int64 { max(0, originalBytes - (outputBytes ?? originalBytes)) }
    var sizeDeltaBytes: Int64? {
        outputBytes.map { $0 - originalBytes }
    }
}

enum JobFailureKind: Equatable, Sendable {
    case cancelled
    case outputValidation
    case missingTool(ToolKind)
    case other
}

struct JobOutcome: Sendable {
    let itemID: UUID
    let result: CompressionResult?
    let errorMessage: String?
    let failureKind: JobFailureKind?

    var recoveryTool: ToolKind? {
        guard case .missingTool(let tool) = failureKind else { return nil }
        return tool
    }

    static func success(itemID: UUID, result: CompressionResult) -> JobOutcome {
        JobOutcome(
            itemID: itemID,
            result: result,
            errorMessage: nil,
            failureKind: nil
        )
    }

    static func failure(itemID: UUID, error: Error) -> JobOutcome {
        let failureKind: JobFailureKind
        let errorMessage: String
        if error is CancellationError {
            failureKind = .cancelled
            errorMessage = CompressionError.cancelled.localizedDescription
        } else if let compressionError = error as? CompressionError {
            if compressionError.isCancellation {
                failureKind = .cancelled
            } else if let tool = compressionError.recoveryTool {
                failureKind = .missingTool(tool)
            } else if compressionError.isOutputValidationFailure {
                failureKind = .outputValidation
            } else {
                failureKind = .other
            }
            errorMessage = compressionError.localizedDescription
        } else {
            failureKind = .other
            errorMessage = error.localizedDescription
        }

        return JobOutcome(
            itemID: itemID,
            result: nil,
            errorMessage: errorMessage,
            failureKind: failureKind
        )
    }
}

enum EngineInstallationPhase: Equatable {
    case idle
    case awaitingHomebrew(toolNames: [String])
    case installing(toolNames: [String])
    case succeeded(message: String, log: String)
    case failed(message: String, log: String)

    var isInstalling: Bool {
        if case .installing = self { return true }
        return false
    }

    var isAwaitingHomebrew: Bool {
        if case .awaitingHomebrew = self { return true }
        return false
    }
}

struct AppNotice: Identifiable, Equatable {
    enum Recovery: Equatable {
        case dismiss
        case openEngines
        case openHomebrew
        case install(ToolKind)
    }

    let id = UUID()
    let title: String
    let message: String
    let recovery: Recovery
}

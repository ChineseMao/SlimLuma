import Foundation
import UniformTypeIdentifiers

public enum MediaKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case image
    case video
    case pdf
    case unknown

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .image: "图片"
        case .video: "视频"
        case .pdf: "PDF"
        case .unknown: "不支持"
        }
    }

    public var symbolName: String {
        switch self {
        case .image: "photo"
        case .video: "film"
        case .pdf: "doc.richtext"
        case .unknown: "questionmark.square.dashed"
        }
    }

    public static func detect(url: URL) -> MediaKind {
        let extensionName = url.pathExtension.lowercased()

        if extensionName == "pdf" {
            return .pdf
        }

        if imageExtensions.contains(extensionName) {
            return .image
        }

        if videoExtensions.contains(extensionName) {
            return .video
        }

        if let type = UTType(filenameExtension: extensionName) {
            if type.conforms(to: .image) { return .image }
            if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
            if type.conforms(to: .pdf) { return .pdf }
        }

        return .unknown
    }

    public static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "tif", "tiff", "bmp",
        "webp", "avif", "heic", "heif", "jp2"
    ]

    public static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mkv", "webm", "avi", "mts",
        "m2ts", "mpg", "mpeg", "3gp", "flv", "wmv"
    ]
}

public enum ImageOutputFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case keep
    case jpeg
    case png
    case webp
    case avif
    case heic

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .keep: "保持原格式"
        case .jpeg: "JPEG"
        case .png: "PNG"
        case .webp: "WebP"
        case .avif: "AVIF"
        case .heic: "HEIC"
        }
    }

    public var fileExtension: String? {
        switch self {
        case .keep: nil
        case .jpeg: "jpg"
        case .png: "png"
        case .webp: "webp"
        case .avif: "avif"
        case .heic: "heic"
        }
    }
}

public enum MetadataPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    case keepAll
    case removePrivate
    case removeAll

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .keepAll: "全部保留"
        case .removePrivate: "移除定位和拍摄信息"
        case .removeAll: "全部移除"
        }
    }
}

public enum VideoCodec: String, Codable, CaseIterable, Identifiable, Sendable {
    case h264
    case hevc
    case av1

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .h264: "H.264（兼容性最好）"
        case .hevc: "HEVC / H.265（更小）"
        case .av1: "AV1（最小但较慢）"
        }
    }

    public var defaultExtension: String {
        switch self {
        case .h264, .hevc: "mp4"
        case .av1: "mkv"
        }
    }
}

public enum VideoSpeed: String, Codable, CaseIterable, Identifiable, Sendable {
    case fastest
    case fast
    case balanced
    case small
    case smallest

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fastest: "最快"
        case .fast: "较快"
        case .balanced: "平衡"
        case .small: "更小"
        case .smallest: "最小"
        }
    }

    public var ffmpegPreset: String {
        switch self {
        case .fastest: "ultrafast"
        case .fast: "veryfast"
        case .balanced: "medium"
        case .small: "slow"
        case .smallest: "veryslow"
        }
    }
}

public enum PDFCompressionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case lossless
    case balanced
    case compact
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .lossless: "无损整理"
        case .balanced: "均衡"
        case .compact: "极致压缩"
        case .custom: "自定义"
        }
    }
}

public enum PDFEnginePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case qpdf
    case ghostscript

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .automatic: "自动选择"
        case .qpdf: "qpdf（无损优化）"
        case .ghostscript: "Ghostscript（强力压缩）"
        }
    }
}

public enum OutputLocation: String, Codable, CaseIterable, Identifiable, Sendable {
    case alongsideOriginal
    case customDirectory

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .alongsideOriginal: "原文件旁"
        case .customDirectory: "指定文件夹"
        }
    }
}

public struct ImageCompressionSettings: Codable, Equatable, Sendable {
    public var format: ImageOutputFormat
    public var quality: Int
    public var lossless: Bool
    /// Optional hard ceiling for the generated file. The coordinator refines
    /// quality and dimensions with ImageMagick until the closest safe result
    /// at or below this value is found.
    public var targetSizeBytes: Int64?
    public var maxWidth: Int?
    public var maxHeight: Int?
    public var metadata: MetadataPolicy
    public var preserveColorProfile: Bool
    public var effort: Int

    public init(
        format: ImageOutputFormat = .keep,
        quality: Int = 82,
        lossless: Bool = false,
        targetSizeBytes: Int64? = nil,
        maxWidth: Int? = nil,
        maxHeight: Int? = nil,
        metadata: MetadataPolicy = .removePrivate,
        preserveColorProfile: Bool = true,
        effort: Int = 6
    ) {
        self.format = format
        self.quality = quality
        self.lossless = lossless
        self.targetSizeBytes = targetSizeBytes.flatMap { $0 > 0 ? $0 : nil }
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.metadata = metadata
        self.preserveColorProfile = preserveColorProfile
        self.effort = effort
    }
}

public struct VideoCompressionSettings: Codable, Equatable, Sendable {
    public var codec: VideoCodec
    public var quality: Int
    /// Optional target for two-pass software encoding. Target-size encoding
    /// intentionally avoids hardware encoders, whose output size is less
    /// deterministic.
    public var targetSizeBytes: Int64?
    public var speed: VideoSpeed
    public var hardwareAcceleration: Bool
    public var maxWidth: Int?
    public var maxHeight: Int?
    public var frameRate: Int?
    public var audioBitrate: Int
    public var removeMetadata: Bool
    public var preserveChapters: Bool

    public init(
        codec: VideoCodec = .h264,
        quality: Int = 72,
        targetSizeBytes: Int64? = nil,
        speed: VideoSpeed = .balanced,
        hardwareAcceleration: Bool = true,
        maxWidth: Int? = nil,
        maxHeight: Int? = 1080,
        frameRate: Int? = nil,
        audioBitrate: Int = 128,
        removeMetadata: Bool = true,
        preserveChapters: Bool = true
    ) {
        self.codec = codec
        self.quality = quality
        self.targetSizeBytes = targetSizeBytes.flatMap { $0 > 0 ? $0 : nil }
        self.speed = speed
        self.hardwareAcceleration = hardwareAcceleration
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.frameRate = frameRate
        self.audioBitrate = audioBitrate
        self.removeMetadata = removeMetadata
        self.preserveChapters = preserveChapters
    }

    private enum CodingKeys: String, CodingKey {
        case codec
        case quality
        case targetSizeBytes
        case speed
        case hardwareAcceleration
        case maxWidth
        case maxHeight
        case frameRate
        case audioBitrate
        case removeMetadata
        case preserveChapters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        codec = try container.decode(VideoCodec.self, forKey: .codec)
        quality = try container.decode(Int.self, forKey: .quality)
        targetSizeBytes = try container.decodeIfPresent(
            Int64.self,
            forKey: .targetSizeBytes
        ).flatMap { $0 > 0 ? $0 : nil }
        speed = try container.decode(VideoSpeed.self, forKey: .speed)
        hardwareAcceleration = try container.decode(
            Bool.self,
            forKey: .hardwareAcceleration
        )
        maxWidth = try container.decodeIfPresent(Int.self, forKey: .maxWidth)
        maxHeight = try container.decodeIfPresent(Int.self, forKey: .maxHeight)
        frameRate = try container.decodeIfPresent(Int.self, forKey: .frameRate)
        audioBitrate = try container.decode(Int.self, forKey: .audioBitrate)
        removeMetadata = try container.decode(
            Bool.self,
            forKey: .removeMetadata
        )
        preserveChapters = try container.decodeIfPresent(
            Bool.self,
            forKey: .preserveChapters
        ) ?? true
    }
}

public struct PDFCompressionSettings: Codable, Equatable, Sendable {
    public var mode: PDFCompressionMode
    public var engine: PDFEnginePreference
    public var imageQuality: Int
    public var imageDPI: Int
    public var grayscale: Bool
    public var linearizeForWeb: Bool
    public var preserveForms: Bool

    public init(
        mode: PDFCompressionMode = .balanced,
        engine: PDFEnginePreference = .automatic,
        imageQuality: Int = 78,
        imageDPI: Int = 150,
        grayscale: Bool = false,
        linearizeForWeb: Bool = true,
        preserveForms: Bool = true
    ) {
        self.mode = mode
        self.engine = engine
        self.imageQuality = imageQuality
        self.imageDPI = imageDPI
        self.grayscale = grayscale
        self.linearizeForWeb = linearizeForWeb
        self.preserveForms = preserveForms
    }
}

public struct OutputSettings: Codable, Equatable, Sendable {
    public var location: OutputLocation
    public var customDirectoryPath: String?
    public var filenameSuffix: String
    public var keepLargerFiles: Bool
    public var preserveModificationDate: Bool

    public init(
        location: OutputLocation = .alongsideOriginal,
        customDirectoryPath: String? = nil,
        filenameSuffix: String = "-slim",
        keepLargerFiles: Bool = false,
        preserveModificationDate: Bool = true
    ) {
        self.location = location
        self.customDirectoryPath = customDirectoryPath
        self.filenameSuffix = filenameSuffix
        self.keepLargerFiles = keepLargerFiles
        self.preserveModificationDate = preserveModificationDate
    }
}

public struct CompressionSettings: Codable, Equatable, Sendable {
    public var image: ImageCompressionSettings
    public var video: VideoCompressionSettings
    public var pdf: PDFCompressionSettings
    public var output: OutputSettings
    public var maxConcurrentJobs: Int

    public init(
        image: ImageCompressionSettings = .init(),
        video: VideoCompressionSettings = .init(),
        pdf: PDFCompressionSettings = .init(),
        output: OutputSettings = .init(),
        maxConcurrentJobs: Int = 2
    ) {
        self.image = image
        self.video = video
        self.pdf = pdf
        self.output = output
        self.maxConcurrentJobs = max(1, min(maxConcurrentJobs, 6))
    }

    public static let `default` = CompressionSettings()
}

public struct CompressionProgress: Equatable, Sendable {
    public let fractionCompleted: Double
    public let stage: String
    public let estimatedRemainingSeconds: TimeInterval?

    public init(
        fractionCompleted: Double,
        stage: String,
        estimatedRemainingSeconds: TimeInterval? = nil
    ) {
        self.fractionCompleted = min(max(fractionCompleted, 0), 1)
        self.stage = stage
        self.estimatedRemainingSeconds = estimatedRemainingSeconds
    }
}

public enum CompressionEngineID: String, Codable, Equatable, Sendable {
    case imageMagick
    case macOSImageIO
    case ffmpeg
    case qpdf
    case ghostscript
    case ghostscriptWithQPDF
    case macOSPDFKit
    case unknown

    fileprivate static func legacyValue(for engineName: String) -> Self {
        switch engineName {
        case ToolKind.imageMagick.displayName:
            .imageMagick
        case ToolKind.sips.displayName:
            .macOSImageIO
        case ToolKind.ffmpeg.displayName:
            .ffmpeg
        case ToolKind.qpdf.displayName:
            .qpdf
        case ToolKind.ghostscript.displayName:
            .ghostscript
        case "\(ToolKind.ghostscript.displayName) + \(ToolKind.qpdf.displayName)":
            .ghostscriptWithQPDF
        case "macOS PDFKit":
            .macOSPDFKit
        default:
            .unknown
        }
    }
}

public struct CompressionResult: Codable, Equatable, Sendable {
    public let inputURL: URL
    public let outputURL: URL?
    public let mediaKind: MediaKind
    /// Stable machine-readable identity. `engineName` remains presentation-only.
    public let engineID: CompressionEngineID
    public let engineName: String
    public let originalBytes: Int64
    public let outputBytes: Int64?
    public let duration: TimeInterval
    public let skippedBecauseLarger: Bool
    public let warning: String?

    public init(
        inputURL: URL,
        outputURL: URL?,
        mediaKind: MediaKind,
        engineName: String,
        engineID: CompressionEngineID? = nil,
        originalBytes: Int64,
        outputBytes: Int64?,
        duration: TimeInterval,
        skippedBecauseLarger: Bool,
        warning: String? = nil
    ) {
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.mediaKind = mediaKind
        self.engineID = engineID ?? .legacyValue(for: engineName)
        self.engineName = engineName
        self.originalBytes = originalBytes
        self.outputBytes = outputBytes
        self.duration = duration
        self.skippedBecauseLarger = skippedBecauseLarger
        self.warning = warning
    }

    private enum CodingKeys: String, CodingKey {
        case inputURL
        case outputURL
        case mediaKind
        case engineID
        case engineName
        case originalBytes
        case outputBytes
        case duration
        case skippedBecauseLarger
        case warning
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputURL = try container.decode(URL.self, forKey: .inputURL)
        outputURL = try container.decodeIfPresent(URL.self, forKey: .outputURL)
        mediaKind = try container.decode(MediaKind.self, forKey: .mediaKind)
        engineName = try container.decode(String.self, forKey: .engineName)
        engineID = try container.decodeIfPresent(
            CompressionEngineID.self,
            forKey: .engineID
        ) ?? .legacyValue(for: engineName)
        originalBytes = try container.decode(Int64.self, forKey: .originalBytes)
        outputBytes = try container.decodeIfPresent(
            Int64.self,
            forKey: .outputBytes
        )
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        skippedBecauseLarger = try container.decode(
            Bool.self,
            forKey: .skippedBecauseLarger
        )
        warning = try container.decodeIfPresent(String.self, forKey: .warning)
    }

    public var savedBytes: Int64 {
        max(0, originalBytes - (outputBytes ?? originalBytes))
    }

    public var savingFraction: Double {
        guard originalBytes > 0 else { return 0 }
        return Double(savedBytes) / Double(originalBytes)
    }

    public var sizeDeltaBytes: Int64? {
        outputBytes.map { $0 - originalBytes }
    }

    public var isLargerThanOriginal: Bool {
        guard let sizeDeltaBytes else { return false }
        return sizeDeltaBytes > 0
    }

    public var isNotSmallerThanOriginal: Bool {
        guard let sizeDeltaBytes else { return false }
        return sizeDeltaBytes >= 0
    }
}

public enum CompressionError: LocalizedError, Equatable, Sendable {
    case unsupportedFile(String)
    case missingTool(
        name: String,
        installCommand: String,
        tool: ToolKind? = nil
    )
    case settingsRequireTool(
        name: String,
        installCommand: String,
        message: String,
        tool: ToolKind? = nil
    )
    case invalidSettings(String)
    case processFailed(tool: String, exitCode: Int32, message: String)
    case outputMissing
    case outputInvalid(String)
    case cancelled

    public var recoveryTool: ToolKind? {
        switch self {
        case .missingTool(_, _, let tool),
             .settingsRequireTool(_, _, _, let tool):
            tool
        default:
            nil
        }
    }

    public var isCancellation: Bool {
        if case .cancelled = self { return true }
        return false
    }

    public var isOutputValidationFailure: Bool {
        if case .outputInvalid = self { return true }
        if case .outputMissing = self { return true }
        return false
    }

    public var errorDescription: String? {
        switch self {
        case .unsupportedFile(let name):
            "不支持文件“\(name)”的格式"
        case .missingTool(let name, let command, _):
            "缺少 \(name)。请先运行：\(command)"
        case .settingsRequireTool(let name, let command, let message, _):
            "\(message) 请安装 \(name) 后重试：\(command)"
        case .invalidSettings(let message):
            message
        case .processFailed(let tool, let exitCode, let message):
            "\(tool) 执行失败（\(exitCode)）：\(message)"
        case .outputMissing:
            "压缩引擎没有生成输出文件"
        case .outputInvalid(let message):
            "输出文件验证失败：\(message)"
        case .cancelled:
            "任务已取消"
        }
    }
}

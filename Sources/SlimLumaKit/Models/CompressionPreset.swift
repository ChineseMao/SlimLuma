import Foundation

public struct PresetExchangeDocument: Codable, Equatable, Sendable {
    public let formatVersion: Int
    public let exportedBy: String
    public let presets: [CompressionPreset]

    public init(presets: [CompressionPreset]) {
        formatVersion = 1
        exportedBy = "SlimLuma"
        self.presets = presets
    }
}

public struct CompressionPreset: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var summary: String
    public var symbolName: String
    public var settings: CompressionSettings
    public var isBuiltIn: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        summary: String,
        symbolName: String,
        settings: CompressionSettings,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.symbolName = symbolName
        self.settings = settings
        self.isBuiltIn = isBuiltIn
    }

    public static let builtIns: [CompressionPreset] = [
        CompressionPreset(
            name: "日常均衡",
            summary: "质量与体积平衡，适合大多数文件",
            symbolName: "slider.horizontal.3",
            settings: .default,
            isBuiltIn: true
        ),
        CompressionPreset(
            name: "网页发布",
            summary: "WebP、H.264 1080p、PDF 快速打开",
            symbolName: "globe",
            settings: CompressionSettings(
                image: ImageCompressionSettings(
                    format: .webp,
                    quality: 80,
                    maxWidth: 2560,
                    maxHeight: 2560,
                    metadata: .removeAll
                ),
                video: VideoCompressionSettings(
                    codec: .h264,
                    quality: 70,
                    speed: .balanced,
                    hardwareAcceleration: true,
                    maxWidth: 1920,
                    maxHeight: 1080,
                    frameRate: 30,
                    audioBitrate: 128
                ),
                pdf: PDFCompressionSettings(
                    mode: .balanced,
                    imageQuality: 76,
                    imageDPI: 144,
                    linearizeForWeb: true
                )
            ),
            isBuiltIn: true
        ),
        CompressionPreset(
            name: "高质量归档",
            summary: "保留更多细节和元数据，使用高质量编码",
            symbolName: "archivebox",
            settings: CompressionSettings(
                image: ImageCompressionSettings(
                    format: .keep,
                    quality: 96,
                    lossless: false,
                    metadata: .keepAll,
                    effort: 8
                ),
                video: VideoCompressionSettings(
                    codec: .hevc,
                    quality: 88,
                    speed: .small,
                    hardwareAcceleration: false,
                    maxWidth: nil,
                    maxHeight: nil,
                    audioBitrate: 256,
                    removeMetadata: false
                ),
                pdf: PDFCompressionSettings(
                    mode: .lossless,
                    engine: .qpdf,
                    imageQuality: 92,
                    imageDPI: 300,
                    linearizeForWeb: false
                ),
                output: OutputSettings(filenameSuffix: "-archive", keepLargerFiles: true)
            ),
            isBuiltIn: true
        ),
        CompressionPreset(
            name: "极致瘦身",
            summary: "优先最小体积，适合分享和临时传输",
            symbolName: "arrow.down.right.and.arrow.up.left",
            settings: CompressionSettings(
                image: ImageCompressionSettings(
                    format: .avif,
                    quality: 58,
                    maxWidth: 1920,
                    maxHeight: 1920,
                    metadata: .removeAll,
                    preserveColorProfile: false,
                    effort: 8
                ),
                video: VideoCompressionSettings(
                    codec: .hevc,
                    quality: 58,
                    speed: .small,
                    hardwareAcceleration: false,
                    maxWidth: 1280,
                    maxHeight: 720,
                    frameRate: 30,
                    audioBitrate: 96
                ),
                pdf: PDFCompressionSettings(
                    mode: .compact,
                    engine: .automatic,
                    imageQuality: 55,
                    imageDPI: 96,
                    linearizeForWeb: true
                ),
                output: OutputSettings(filenameSuffix: "-tiny")
            ),
            isBuiltIn: true
        ),
        CompressionPreset(
            name: "隐私分享",
            summary: "清理图片和视频元数据，使用兼容格式",
            symbolName: "hand.raised",
            settings: CompressionSettings(
                image: ImageCompressionSettings(
                    format: .jpeg,
                    quality: 84,
                    maxWidth: 2560,
                    maxHeight: 2560,
                    metadata: .removeAll
                ),
                video: VideoCompressionSettings(
                    codec: .h264,
                    quality: 74,
                    speed: .fast,
                    hardwareAcceleration: true,
                    maxWidth: 1920,
                    maxHeight: 1080,
                    frameRate: 30,
                    audioBitrate: 128,
                    removeMetadata: true
                ),
                pdf: PDFCompressionSettings(
                    mode: .balanced,
                    imageQuality: 80,
                    imageDPI: 150
                ),
                output: OutputSettings(filenameSuffix: "-share")
            ),
            isBuiltIn: true
        )
    ]
}

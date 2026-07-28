import Foundation

public enum ToolKind: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case imageMagick
    case ffmpeg
    case qpdf
    case ghostscript
    case sips

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .imageMagick: "ImageMagick"
        case .ffmpeg: "FFmpeg"
        case .qpdf: "qpdf"
        case .ghostscript: "Ghostscript"
        case .sips: "macOS ImageIO"
        }
    }

    public var executableNames: [String] {
        switch self {
        case .imageMagick: ["magick"]
        case .ffmpeg: ["ffmpeg"]
        case .qpdf: ["qpdf"]
        case .ghostscript: ["gs"]
        case .sips: ["sips"]
        }
    }

    public var installCommand: String {
        let brew = Self.preferredBrewExecutable
        guard let formulaName else { return "macOS 已内置，无需安装" }
        return "\(brew) install \(formulaName)"
    }

    public var reinstallCommand: String {
        let brew = Self.preferredBrewExecutable
        guard let formulaName else { return "macOS 已内置，无需安装" }
        return "\(brew) reinstall \(formulaName)"
    }

    public var formulaName: String? {
        switch self {
        case .imageMagick: "imagemagick"
        case .ffmpeg: "ffmpeg"
        case .qpdf: "qpdf"
        case .ghostscript: "ghostscript"
        case .sips: nil
        }
    }

    public var isRecommended: Bool {
        self != .sips
    }

    public var installationNote: String {
        switch self {
        case .imageMagick:
            "补齐 WebP、AVIF、GIF 与高级图片优化能力"
        case .ffmpeg:
            "提供视频转码、硬件加速与音频处理"
        case .qpdf:
            "提供 PDF 无损整理、对象流优化与网页线性化"
        case .ghostscript:
            "为图片型 PDF 提供真正的降采样压缩；通过 Homebrew 独立安装"
        case .sips:
            "macOS 系统内置"
        }
    }

    public var purpose: String {
        switch self {
        case .imageMagick: "图片专业处理（基础设置可使用 macOS 后备）"
        case .ffmpeg: "视频压缩和转码"
        case .qpdf: "PDF 无损结构与网页优化（缺失时使用 PDFKit 后备）"
        case .ghostscript: "图片型 PDF 降采样与深度压缩"
        case .sips: "ImageMagick 缺失时的受限图片基础处理"
        }
    }

    private static var preferredBrewExecutable: String {
        if FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/brew") {
            return "/opt/homebrew/bin/brew"
        }
        if FileManager.default.isExecutableFile(atPath: "/usr/local/bin/brew") {
            return "/usr/local/bin/brew"
        }
        return "brew"
    }
}

public struct ToolAvailability: Identifiable, Sendable {
    public let kind: ToolKind
    public let executableURL: URL?
    public let missingCompanionExecutableName: String?

    public var id: String { kind.id }
    public var isAvailable: Bool {
        executableURL != nil && missingCompanionExecutableName == nil
    }

    public var recoveryCommand: String {
        missingCompanionExecutableName == nil
            ? kind.installCommand
            : kind.reinstallCommand
    }
}

public struct ToolRegistry: Sendable {
    private let searchDirectoryOverride: [URL]?

    public init(searchDirectories: [URL]? = nil) {
        searchDirectoryOverride = searchDirectories
    }

    public func locate(_ kind: ToolKind) -> URL? {
        for executableName in kind.executableNames {
            for directory in searchDirectories {
                let candidate = directory.appendingPathComponent(executableName)
                if FileManager.default.isExecutableFile(atPath: candidate.path) {
                    return candidate.resolvingSymlinksInPath()
                }
            }
        }
        return nil
    }

    public func availability() -> [ToolAvailability] {
        ToolKind.allCases.map { kind in
            let executableURL = locate(kind)
            let missingCompanionExecutableName: String?
            if
                kind == .ffmpeg,
                executableURL != nil,
                locateFFprobe(companionTo: executableURL) == nil
            {
                missingCompanionExecutableName = "ffprobe"
            } else {
                missingCompanionExecutableName = nil
            }
            return ToolAvailability(
                kind: kind,
                executableURL: executableURL,
                missingCompanionExecutableName:
                    missingCompanionExecutableName
            )
        }
    }

    public func homebrewInstallArguments(for kind: ToolKind) -> [String]? {
        guard let formulaName = kind.formulaName else { return nil }
        let needsCompanionRepair =
            kind == .ffmpeg
                && locate(.ffmpeg) != nil
                && locateFFprobe() == nil
        return [
            needsCompanionRepair ? "reinstall" : "install",
            formulaName
        ]
    }

    public func locateFFprobe(companionTo ffmpegURL: URL? = nil) -> URL? {
        guard let ffmpegURL = ffmpegURL ?? locate(.ffmpeg) else {
            return nil
        }

        let resolvedFFmpeg = ffmpegURL.resolvingSymlinksInPath()
        let candidates = [
            resolvedFFmpeg
                .deletingLastPathComponent()
                .appendingPathComponent("ffprobe"),
            ffmpegURL
                .deletingLastPathComponent()
                .appendingPathComponent("ffprobe")
        ]

        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }?.resolvingSymlinksInPath()
    }

    public func homebrewURL() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew"
        ]
        return candidates
            .first(where: FileManager.default.isExecutableFile(atPath:))
            .map { URL(fileURLWithPath: $0) }
    }

    private var searchDirectories: [URL] {
        if let searchDirectoryOverride {
            return searchDirectoryOverride
        }

        var paths: [String] = []

        if let bundledTools = Bundle.main.resourceURL?.appendingPathComponent("Tools").path {
            paths.append(bundledTools)
        }

        #if arch(arm64)
        paths.append("/opt/homebrew/bin")
        #elseif arch(x86_64)
        paths.append("/usr/local/bin")
        #endif

        if let environmentPath = ProcessInfo.processInfo.environment["PATH"] {
            paths.append(contentsOf: environmentPath.split(separator: ":").map(String.init))
        }

        paths.append(contentsOf: [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/opt/local/bin",
            "/usr/bin",
            "/bin"
        ])

        var seen = Set<String>()
        return paths.compactMap { path in
            guard !path.isEmpty, seen.insert(path).inserted else { return nil }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
    }
}

import Foundation
import ImageIO

struct ImageMagickCommandBuilder {
    static func arguments(
        input: URL,
        output: URL,
        settings: ImageCompressionSettings,
        restoredICCProfileURL: URL? = nil,
        scalePercent: Int? = nil
    ) -> [String] {
        var arguments = [input.path, "-auto-orient"]

        if let resize = resizeGeometry(width: settings.maxWidth, height: settings.maxHeight) {
            arguments += ["-resize", resize]
        }
        if let scalePercent, scalePercent > 0, scalePercent < 100 {
            arguments += ["-resize", "\(scalePercent)%"]
        }

        switch settings.metadata {
        case .keepAll:
            break
        case .removePrivate:
            arguments += ["+profile", "exif", "+profile", "xmp", "+profile", "iptc"]
        case .removeAll:
            arguments += ["-strip"]
            if let restoredICCProfileURL {
                arguments += ["-profile", restoredICCProfileURL.path]
            }
        }

        if settings.lossless {
            arguments += ["-quality", "100"]
            switch output.pathExtension.lowercased() {
            case "webp":
                arguments += ["-define", "webp:lossless=true", "-define", "webp:method=\(settings.effort)"]
            case "png":
                arguments += ["-define", "png:compression-level=9"]
            default:
                break
            }
        } else {
            arguments += ["-quality", "\(settings.quality)"]
            switch output.pathExtension.lowercased() {
            case "webp":
                arguments += ["-define", "webp:method=\(settings.effort)"]
            case "avif":
                arguments += ["-define", "heic:speed=\(max(0, 9 - settings.effort))"]
            case "png":
                arguments += ["-define", "png:compression-level=9"]
            default:
                break
            }
        }

        arguments.append(output.path)
        return arguments
    }

    private static func resizeGeometry(width: Int?, height: Int?) -> String? {
        let validWidth = width.flatMap { $0 > 0 ? $0 : nil }
        let validHeight = height.flatMap { $0 > 0 ? $0 : nil }

        switch (validWidth, validHeight) {
        case let (.some(width), .some(height)):
            return "\(width)x\(height)>"
        case let (.some(width), .none):
            return "\(width)x>"
        case let (.none, .some(height)):
            return "x\(height)>"
        case (.none, .none):
            return nil
        }
    }
}

struct SipsCommandBuilder {
    static func arguments(
        input: URL,
        output: URL,
        settings: ImageCompressionSettings
    ) throws -> [String] {
        let outputExtension = output.pathExtension.lowercased()
        let format: String
        switch outputExtension {
        case "jpg", "jpeg": format = "jpeg"
        case "png": format = "png"
        case "heic", "heif": format = "heic"
        case "tif", "tiff": format = "tiff"
        case "bmp": format = "bmp"
        case "jp2": format = "jp2"
        case "avif": format = "avif"
        default:
            throw CompressionError.missingTool(
                name: ToolKind.imageMagick.displayName,
                installCommand: ToolKind.imageMagick.installCommand,
                tool: .imageMagick
            )
        }

        var arguments = ["--setProperty", "format", format]

        switch format {
        case "png":
            arguments += ["--setProperty", "formatOptions", "best"]
        case "tiff":
            arguments += ["--setProperty", "formatOptions", "lzw"]
        case "bmp":
            break
        default:
            arguments += [
                "--setProperty",
                "formatOptions",
                "\(max(0, min(100, settings.quality)))"
            ]
        }

        if let target = try targetPixelSize(input: input, settings: settings) {
            arguments += [
                "--resampleHeightWidth",
                "\(target.height)",
                "\(target.width)"
            ]
        }

        arguments += ["--out", output.path, input.path]
        return arguments
    }

    private static func targetPixelSize(
        input: URL,
        settings: ImageCompressionSettings
    ) throws -> (width: Int, height: Int)? {
        let maximumWidth = settings.maxWidth.flatMap { $0 > 0 ? $0 : nil }
        let maximumHeight = settings.maxHeight.flatMap { $0 > 0 ? $0 : nil }
        guard maximumWidth != nil || maximumHeight != nil else { return nil }

        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(
                  source,
                  0,
                  nil
              ) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?
                  .intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?
                  .intValue,
              width > 0,
              height > 0 else {
            throw CompressionError.outputInvalid(
                "无法读取图片像素尺寸，未执行系统图片后备处理"
            )
        }

        let widthScale = maximumWidth.map {
            Double($0) / Double(width)
        } ?? 1
        let heightScale = maximumHeight.map {
            Double($0) / Double(height)
        } ?? 1
        let scale = min(1, widthScale, heightScale)
        guard scale < 1 else { return nil }

        return (
            width: max(1, Int((Double(width) * scale).rounded())),
            height: max(1, Int((Double(height) * scale).rounded()))
        )
    }
}

struct FFmpegCommandBuilder {
    static func arguments(
        input: URL,
        output: URL,
        settings: VideoCompressionSettings,
        av1Encoder: FFmpegAV1Encoder? = nil
    ) throws -> [String] {
        var arguments = [
            "-hide_banner",
            "-nostdin",
            "-y",
            "-i", input.path,
            "-map", "0:v:0",
            "-map", "0:a?",
            "-map", "0:s?"
        ]

        arguments += metadataAndChapterArguments(settings: settings)

        if let scaleFilter = scaleFilter(width: settings.maxWidth, height: settings.maxHeight) {
            arguments += ["-vf", scaleFilter]
        }

        if let frameRate = settings.frameRate, frameRate > 0 {
            arguments += ["-r", "\(frameRate)"]
        }

        arguments += try codecArguments(
            settings: settings,
            av1Encoder: av1Encoder
        )
        arguments += ["-c:a", "aac", "-b:a", "\(settings.audioBitrate)k"]

        if output.pathExtension.lowercased() == "mp4" {
            arguments += [
                "-c:s", "mov_text",
                "-movflags", "+faststart",
                "-tag:v", settings.codec == .hevc ? "hvc1" : "avc1"
            ]
        } else {
            arguments += ["-c:s", "copy"]
        }

        arguments += ["-progress", "pipe:1", "-nostats", output.path]
        return arguments
    }

    static func targetArguments(
        input: URL,
        output: URL,
        settings: VideoCompressionSettings,
        durationSeconds: Double,
        audioTrackCount: Int,
        passlogURL: URL
    ) throws -> [[String]] {
        guard settings.codec != .av1 else {
            throw CompressionError.invalidSettings(
                "目标大小暂不支持 AV1。请改用 H.264 或 HEVC，以便执行稳定的两遍编码。"
            )
        }
        guard let targetSizeBytes = settings.targetSizeBytes,
              targetSizeBytes >= 128 * 1_024,
              durationSeconds.isFinite,
              durationSeconds > 0 else {
            throw CompressionError.invalidSettings(
                "视频目标大小过小或视频时长无效，无法计算安全码率"
            )
        }

        let audioKilobitsPerSecond = max(0, audioTrackCount)
            * max(0, settings.audioBitrate)
        // Reserve 5% for the container, subtitle tracks and timing metadata.
        let totalKilobitsPerSecond =
            Double(targetSizeBytes) * 8 * 0.95 / durationSeconds / 1_000
        let videoKilobitsPerSecond = Int(
            floor(totalKilobitsPerSecond - Double(audioKilobitsPerSecond))
        )
        guard videoKilobitsPerSecond >= 100 else {
            throw CompressionError.invalidSettings(
                "目标大小不足以容纳当前时长和音频。请增大目标，或降低音频码率。"
            )
        }

        var firstPass = [
            "-hide_banner",
            "-nostdin",
            "-y",
            "-i", input.path,
            "-map", "0:v:0"
        ]
        firstPass += transformArguments(settings: settings)
        firstPass += targetCodecArguments(
            settings: settings,
            videoKilobitsPerSecond: videoKilobitsPerSecond
        )
        firstPass += [
            "-pass", "1",
            "-passlogfile", passlogURL.path,
            "-an",
            "-sn",
            "-f", "null",
            "-progress", "pipe:1",
            "-nostats",
            "/dev/null"
        ]

        var secondPass = [
            "-hide_banner",
            "-nostdin",
            "-y",
            "-i", input.path,
            "-map", "0:v:0",
            "-map", "0:a?",
            "-map", "0:s?"
        ]
        secondPass += metadataAndChapterArguments(settings: settings)
        secondPass += transformArguments(settings: settings)
        secondPass += targetCodecArguments(
            settings: settings,
            videoKilobitsPerSecond: videoKilobitsPerSecond
        )
        secondPass += [
            "-pass", "2",
            "-passlogfile", passlogURL.path,
            "-c:a", "aac",
            "-b:a", "\(settings.audioBitrate)k"
        ]
        secondPass += subtitleAndContainerArguments(
            output: output,
            settings: settings
        )
        secondPass += [
            "-progress", "pipe:1",
            "-nostats",
            output.path
        ]
        return [firstPass, secondPass]
    }

    private static func metadataAndChapterArguments(
        settings: VideoCompressionSettings
    ) -> [String] {
        var arguments: [String] = []
        if settings.removeMetadata {
            arguments += ["-map_metadata", "-1"]
        }
        arguments += [
            "-map_chapters",
            settings.preserveChapters ? "0" : "-1"
        ]
        return arguments
    }

    private static func transformArguments(
        settings: VideoCompressionSettings
    ) -> [String] {
        var arguments: [String] = []
        if let scaleFilter = scaleFilter(
            width: settings.maxWidth,
            height: settings.maxHeight
        ) {
            arguments += ["-vf", scaleFilter]
        }
        if let frameRate = settings.frameRate, frameRate > 0 {
            arguments += ["-r", "\(frameRate)"]
        }
        return arguments
    }

    private static func targetCodecArguments(
        settings: VideoCompressionSettings,
        videoKilobitsPerSecond: Int
    ) -> [String] {
        let encoder = settings.codec == .h264 ? "libx264" : "libx265"
        return [
            "-c:v", encoder,
            "-b:v", "\(videoKilobitsPerSecond)k",
            "-maxrate", "\(videoKilobitsPerSecond)k",
            "-bufsize", "\(videoKilobitsPerSecond * 2)k",
            "-preset", settings.speed.ffmpegPreset
        ]
    }

    private static func subtitleAndContainerArguments(
        output: URL,
        settings: VideoCompressionSettings
    ) -> [String] {
        if output.pathExtension.lowercased() == "mp4" {
            return [
                "-c:s", "mov_text",
                "-movflags", "+faststart",
                "-tag:v", settings.codec == .hevc ? "hvc1" : "avc1"
            ]
        }
        return ["-c:s", "copy"]
    }

    private static func codecArguments(
        settings: VideoCompressionSettings,
        av1Encoder: FFmpegAV1Encoder?
    ) throws -> [String] {
        if settings.hardwareAcceleration, settings.codec != .av1 {
            let encoder = settings.codec == .h264 ? "h264_videotoolbox" : "hevc_videotoolbox"
            return [
                "-c:v", encoder,
                "-q:v", "\(settings.quality)",
                "-allow_sw", "1"
            ]
        }

        let crf: Int
        let encoder: String
        switch settings.codec {
        case .h264:
            encoder = "libx264"
            crf = qualityToCRF(settings.quality, minimum: 16, maximum: 32)
        case .hevc:
            encoder = "libx265"
            crf = qualityToCRF(settings.quality, minimum: 19, maximum: 36)
        case .av1:
            guard let av1Encoder else {
                throw CompressionError.invalidSettings(
                    "尚未确认当前 FFmpeg 的 AV1 编码能力，任务未开始"
                )
            }
            encoder = av1Encoder.rawValue
            crf = qualityToCRF(settings.quality, minimum: 22, maximum: 45)
        }

        var arguments = ["-c:v", encoder, "-crf", "\(crf)", "-b:v", "0"]
        if let av1Encoder, settings.codec == .av1 {
            arguments += av1Encoder.speedArguments(for: settings.speed)
        } else {
            arguments += ["-preset", settings.speed.ffmpegPreset]
        }
        return arguments
    }

    private static func qualityToCRF(_ quality: Int, minimum: Int, maximum: Int) -> Int {
        let clampedQuality = max(0, min(100, quality))
        let range = Double(maximum - minimum)
        return Int((Double(maximum) - Double(clampedQuality) / 100 * range).rounded())
    }

    private static func scaleFilter(width: Int?, height: Int?) -> String? {
        let width = width.flatMap { $0 > 0 ? $0 : nil }
        let height = height.flatMap { $0 > 0 ? $0 : nil }

        guard width != nil || height != nil else { return nil }
        let targetWidth = width.map(String.init) ?? "iw"
        let targetHeight = height.map(String.init) ?? "ih"
        return "scale=w=min(iw\\,\(targetWidth)):h=min(ih\\,\(targetHeight)):force_original_aspect_ratio=decrease,scale=w=trunc(iw/2)*2:h=trunc(ih/2)*2"
    }
}

struct QPDFCommandBuilder {
    static func decryptArguments(
        input: URL,
        output: URL,
        passwordFile: URL
    ) -> [String] {
        [
            input.path,
            "--password-file=\(passwordFile.path)",
            "--decrypt",
            output.path
        ]
    }

    static func repairArguments(
        input: URL,
        output: URL
    ) -> [String] {
        [
            input.path,
            output.path
        ]
    }

    static func linearizeArguments(
        input: URL,
        output: URL
    ) -> [String] {
        [
            input.path,
            output.path,
            "--linearize"
        ]
    }

    static func arguments(
        input: URL,
        output: URL,
        settings: PDFCompressionSettings
    ) -> [String] {
        var arguments = [
            input.path,
            output.path,
            "--compress-streams=y",
            "--decode-level=generalized",
            "--recompress-flate",
            "--compression-level=9",
            "--object-streams=generate"
        ]

        if settings.mode != .lossless {
            arguments += [
                "--optimize-images",
                "--jpeg-quality=\(settings.imageQuality)",
                "--oi-min-width=256",
                "--oi-min-height=256"
            ]
        }

        if settings.linearizeForWeb {
            arguments.append("--linearize")
        }

        return arguments
    }
}

struct GhostscriptCommandBuilder {
    static func arguments(
        input: URL,
        output: URL,
        settings: PDFCompressionSettings,
        linearizeInGhostscript: Bool = true
    ) -> [String] {
        let profile: String
        switch settings.mode {
        case .lossless: profile = "/prepress"
        case .balanced: profile = "/ebook"
        case .compact: profile = "/screen"
        case .custom: profile = "/default"
        }

        var arguments = [
            "-sDEVICE=pdfwrite",
            "-dCompatibilityLevel=1.6",
            "-dNOPAUSE",
            "-dBATCH",
            "-dSAFER",
            "-dQUIET",
            "-dDetectDuplicateImages=true",
            "-dCompressFonts=true",
            "-dSubsetFonts=true",
            "-dPDFSETTINGS=\(profile)"
        ]

        if settings.mode != .lossless {
            arguments += [
                "-dColorImageResolution=\(settings.imageDPI)",
                "-dGrayImageResolution=\(settings.imageDPI)",
                "-dMonoImageResolution=\(max(settings.imageDPI, 300))",
                "-dJPEGQ=\(settings.imageQuality)"
            ]

            if settings.grayscale {
                arguments += [
                    "-sColorConversionStrategy=Gray",
                    "-dProcessColorModel=/DeviceGray"
                ]
            }
        }

        if settings.preserveForms {
            arguments.append("-dPreserveAnnots=true")
        }

        if settings.linearizeForWeb, linearizeInGhostscript {
            arguments.append("-dFastWebView=true")
        }

        arguments += ["-sOutputFile=\(output.path)", input.path]
        return arguments
    }
}

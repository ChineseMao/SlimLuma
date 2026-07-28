import AVFoundation
import Foundation

struct VideoIntegritySnapshot: Equatable, Sendable {
    let durationSeconds: Double
    let videoTrackCount: Int
    let audioTrackCount: Int
    let subtitleTrackCount: Int
    let chapterCount: Int
    let hasHDRVideo: Bool
    let audioLanguages: [String]
    let subtitleLanguages: [String]
    let defaultAudioTrackCount: Int
    let forcedSubtitleTrackCount: Int
    let subtitlePacketCount: Int?
    let isPlayable: Bool
    let systemPreviewPlayable: Bool?

    init(
        durationSeconds: Double,
        videoTrackCount: Int,
        audioTrackCount: Int,
        subtitleTrackCount: Int,
        chapterCount: Int = 0,
        hasHDRVideo: Bool = false,
        audioLanguages: [String] = [],
        subtitleLanguages: [String] = [],
        defaultAudioTrackCount: Int = 0,
        forcedSubtitleTrackCount: Int = 0,
        subtitlePacketCount: Int? = nil,
        isPlayable: Bool,
        systemPreviewPlayable: Bool? = nil
    ) {
        self.durationSeconds = durationSeconds
        self.videoTrackCount = videoTrackCount
        self.audioTrackCount = audioTrackCount
        self.subtitleTrackCount = subtitleTrackCount
        self.chapterCount = chapterCount
        self.hasHDRVideo = hasHDRVideo
        self.audioLanguages = audioLanguages
        self.subtitleLanguages = subtitleLanguages
        self.defaultAudioTrackCount = defaultAudioTrackCount
        self.forcedSubtitleTrackCount = forcedSubtitleTrackCount
        self.subtitlePacketCount = subtitlePacketCount
        self.isPlayable = isPlayable
        self.systemPreviewPlayable = systemPreviewPlayable
    }
}

enum VideoIntegrityRiskCode: String, Equatable, Sendable {
    case videoTrackRemoved
    case audioTrackRemoved
    case subtitleTrackRemoved
    case chaptersRemoved
    case hdrRemoved
    case trackLanguageChanged
    case defaultAudioDispositionRemoved
    case forcedSubtitleDispositionRemoved
    case subtitlePayloadRemoved
    case durationChanged
    case outputNotPlayable
}

struct VideoIntegrityRisk: Equatable, Sendable {
    let code: VideoIntegrityRiskCode
    let message: String
}

struct VideoIntegrityReport: Equatable, Sendable {
    let original: VideoIntegritySnapshot
    let compressed: VideoIntegritySnapshot
    let risks: [VideoIntegrityRisk]

    var hasCriticalRisk: Bool {
        !risks.isEmpty
    }

    var summary: String {
        risks.map(\.message).joined(separator: "；")
    }
}

struct VideoIntegrityExpectations: Equatable, Sendable {
    var preserveChapters = true
}

struct FFprobeSnapshotParser {
    static func parse(
        _ data: Data,
        filename: String
    ) throws -> VideoIntegritySnapshot {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw VideoIntegrityInspectionError.invalidResponse(
                filename,
                error.localizedDescription
            )
        }

        guard let root = object as? [String: Any] else {
            throw VideoIntegrityInspectionError.invalidResponse(
                filename,
                "ffprobe 没有返回 JSON 对象"
            )
        }

        let streams = root["streams"] as? [[String: Any]] ?? []
        let format = root["format"] as? [String: Any]
        let formatDuration = doubleValue(format?["duration"])
        let streamDuration = streams
            .compactMap { doubleValue($0["duration"]) }
            .max()
        guard let durationSeconds = formatDuration ?? streamDuration,
              durationSeconds.isFinite,
              durationSeconds > 0 else {
            throw VideoIntegrityInspectionError.invalidDuration(filename)
        }

        let videoTrackCount = streams.count {
            ($0["codec_type"] as? String) == "video"
        }
        let audioTrackCount = streams.count {
            ($0["codec_type"] as? String) == "audio"
        }
        let subtitleTrackCount = streams.count {
            ($0["codec_type"] as? String) == "subtitle"
        }
        let chapters = root["chapters"] as? [[String: Any]] ?? []
        let audioStreams = streams.filter {
            ($0["codec_type"] as? String) == "audio"
        }
        let subtitleStreams = streams.filter {
            ($0["codec_type"] as? String) == "subtitle"
        }
        let audioLanguages = audioStreams.compactMap(language).sorted()
        let subtitleLanguages = subtitleStreams.compactMap(language).sorted()
        let defaultAudioTrackCount = audioStreams.count {
            dispositionFlag("default", in: $0)
        }
        let forcedSubtitleTrackCount = subtitleStreams.count {
            dispositionFlag("forced", in: $0)
        }
        let subtitlePacketCounts = subtitleStreams.compactMap {
            integerValue($0["nb_read_packets"])
        }
        let subtitlePacketCount = subtitlePacketCounts.isEmpty
            ? nil
            : subtitlePacketCounts.reduce(0, +)
        let hasHDRVideo = streams.contains { stream in
            guard (stream["codec_type"] as? String) == "video" else {
                return false
            }
            let transfer = (stream["color_transfer"] as? String)?
                .lowercased()
            let primaries = (stream["color_primaries"] as? String)?
                .lowercased()
            return ["smpte2084", "arib-std-b67"].contains(transfer)
                || (primaries == "bt2020" && transfer != nil)
        }

        return VideoIntegritySnapshot(
            durationSeconds: durationSeconds,
            videoTrackCount: videoTrackCount,
            audioTrackCount: audioTrackCount,
            subtitleTrackCount: subtitleTrackCount,
            chapterCount: chapters.count,
            hasHDRVideo: hasHDRVideo,
            audioLanguages: audioLanguages,
            subtitleLanguages: subtitleLanguages,
            defaultAudioTrackCount: defaultAudioTrackCount,
            forcedSubtitleTrackCount: forcedSubtitleTrackCount,
            subtitlePacketCount: subtitlePacketCount,
            isPlayable: videoTrackCount > 0
        )
    }

    private static func language(_ stream: [String: Any]) -> String? {
        let tags = stream["tags"] as? [String: Any]
        guard let value = tags?["language"] as? String else { return nil }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.isEmpty || normalized == "und" ? nil : normalized
    }

    private static func dispositionFlag(
        _ key: String,
        in stream: [String: Any]
    ) -> Bool {
        let disposition = stream["disposition"] as? [String: Any]
        return integerValue(disposition?[key]) == 1
    }

    private static func integerValue(_ value: Any?) -> Int? {
        switch value {
        case let value as Int:
            return value
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            return Int(value)
        default:
            return nil
        }
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let value as Double:
            return value
        case let value as NSNumber:
            return value.doubleValue
        case let value as String:
            return Double(value)
        default:
            return nil
        }
    }
}

struct VideoIntegrityChecker: Sendable {
    private let ffprobeURL: URL?
    private let runner: ProcessRunner

    init(
        ffprobeURL: URL? = nil,
        runner: ProcessRunner = ProcessRunner()
    ) {
        self.ffprobeURL = ffprobeURL
        self.runner = runner
    }

    func inspect(_ url: URL) async throws -> VideoIntegritySnapshot {
        guard let ffprobeURL else {
            throw VideoIntegrityInspectionError.ffprobeUnavailable
        }

        try Task.checkCancellation()
        let result = try await runner.run(
            executableURL: ffprobeURL,
            arguments: [
                "-v", "error",
                "-count_packets",
                "-show_entries",
                "format=duration:chapter=id,start_time,end_time:"
                    + "stream=codec_type,duration,color_transfer,"
                    + "color_primaries,nb_read_packets:"
                    + "stream_tags=language:"
                    + "stream_disposition=default,forced",
                "-of", "json",
                url.path
            ]
        )
        try Task.checkCancellation()

        guard result.exitCode == 0 else {
            let diagnostic = result.standardError
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw VideoIntegrityInspectionError.ffprobeFailed(
                url.lastPathComponent,
                diagnostic.isEmpty
                    ? "文件结构无法读取"
                    : String(diagnostic.suffix(1_500))
            )
        }

        var snapshot = try FFprobeSnapshotParser.parse(
            Data(result.standardOutput.utf8),
            filename: url.lastPathComponent
        )
        try Task.checkCancellation()

        // AVFoundation is only a macOS preview-compatibility signal. Matroska
        // and WebM can be valid FFmpeg inputs even when Quick Look cannot open
        // them, so this value must never reject an otherwise valid file.
        let asset = AVURLAsset(url: url)
        let systemPreviewPlayable = try? await asset.load(.isPlayable)
        try Task.checkCancellation()
        snapshot = VideoIntegritySnapshot(
            durationSeconds: snapshot.durationSeconds,
            videoTrackCount: snapshot.videoTrackCount,
            audioTrackCount: snapshot.audioTrackCount,
            subtitleTrackCount: snapshot.subtitleTrackCount,
            chapterCount: snapshot.chapterCount,
            hasHDRVideo: snapshot.hasHDRVideo,
            audioLanguages: snapshot.audioLanguages,
            subtitleLanguages: snapshot.subtitleLanguages,
            defaultAudioTrackCount: snapshot.defaultAudioTrackCount,
            forcedSubtitleTrackCount: snapshot.forcedSubtitleTrackCount,
            subtitlePacketCount: snapshot.subtitlePacketCount,
            isPlayable: snapshot.isPlayable,
            systemPreviewPlayable: systemPreviewPlayable
        )
        return snapshot
    }

    func compare(
        originalURL: URL,
        compressedURL: URL,
        expectations: VideoIntegrityExpectations = .init()
    ) async throws -> VideoIntegrityReport {
        let original = try await inspect(originalURL)
        try Task.checkCancellation()
        let compressed = try await inspect(compressedURL)
        try Task.checkCancellation()
        return compare(
            original: original,
            compressed: compressed,
            expectations: expectations
        )
    }

    func compare(
        original: VideoIntegritySnapshot,
        compressed: VideoIntegritySnapshot,
        expectations: VideoIntegrityExpectations = .init()
    ) -> VideoIntegrityReport {
        var risks: [VideoIntegrityRisk] = []

        if !compressed.isPlayable {
            risks.append(
                VideoIntegrityRisk(
                    code: .outputNotPlayable,
                    message: "压缩结果无法由 FFmpeg 读取，输出已丢弃"
                )
            )
        }
        if original.videoTrackCount > 0,
           compressed.videoTrackCount < original.videoTrackCount {
            risks.append(
                VideoIntegrityRisk(
                    code: .videoTrackRemoved,
                    message:
                        "视频轨道从 \(original.videoTrackCount) 条变为 "
                        + "\(compressed.videoTrackCount) 条，输出已丢弃"
                )
            )
        }
        if original.audioTrackCount > 0,
           compressed.audioTrackCount < original.audioTrackCount {
            risks.append(
                VideoIntegrityRisk(
                    code: .audioTrackRemoved,
                    message:
                        "音频轨道从 \(original.audioTrackCount) 条变为 "
                        + "\(compressed.audioTrackCount) 条，输出已丢弃"
                )
            )
        }
        if original.subtitleTrackCount > 0,
           compressed.subtitleTrackCount < original.subtitleTrackCount {
            risks.append(
                VideoIntegrityRisk(
                    code: .subtitleTrackRemoved,
                    message:
                        "字幕轨道从 \(original.subtitleTrackCount) 条变为 "
                        + "\(compressed.subtitleTrackCount) 条，输出已丢弃"
                )
            )
        }
        if expectations.preserveChapters,
           original.chapterCount > 0,
           compressed.chapterCount < original.chapterCount {
            risks.append(
                VideoIntegrityRisk(
                    code: .chaptersRemoved,
                    message:
                        "章节从 \(original.chapterCount) 个变为 "
                        + "\(compressed.chapterCount) 个，输出已丢弃"
                )
            )
        }
        if original.hasHDRVideo, !compressed.hasHDRVideo {
            risks.append(
                VideoIntegrityRisk(
                    code: .hdrRemoved,
                    message: "压缩结果丢失了 HDR 色彩标记，输出已丢弃"
                )
            )
        }
        if original.audioLanguages != compressed.audioLanguages
            || original.subtitleLanguages != compressed.subtitleLanguages {
            risks.append(
                VideoIntegrityRisk(
                    code: .trackLanguageChanged,
                    message: "音轨或字幕语言标记发生变化，输出已丢弃"
                )
            )
        }
        if compressed.defaultAudioTrackCount
            < original.defaultAudioTrackCount {
            risks.append(
                VideoIntegrityRisk(
                    code: .defaultAudioDispositionRemoved,
                    message: "默认音轨标记丢失，输出已丢弃"
                )
            )
        }
        if compressed.forcedSubtitleTrackCount
            < original.forcedSubtitleTrackCount {
            risks.append(
                VideoIntegrityRisk(
                    code: .forcedSubtitleDispositionRemoved,
                    message: "强制字幕标记丢失，输出已丢弃"
                )
            )
        }
        if let originalPackets = original.subtitlePacketCount,
           originalPackets > 0,
           compressed.subtitlePacketCount == 0 {
            risks.append(
                VideoIntegrityRisk(
                    code: .subtitlePayloadRemoved,
                    message: "字幕轨道仍存在，但字幕内容为空，输出已丢弃"
                )
            )
        }

        let durationDifference = abs(
            original.durationSeconds - compressed.durationSeconds
        )
        let durationTolerance = max(0.5, original.durationSeconds * 0.01)
        if durationDifference > durationTolerance {
            risks.append(
                VideoIntegrityRisk(
                    code: .durationChanged,
                    message: String(
                        format: "视频时长从 %.2f 秒变为 %.2f 秒，输出已丢弃",
                        original.durationSeconds,
                        compressed.durationSeconds
                    )
                )
            )
        }

        return VideoIntegrityReport(
            original: original,
            compressed: compressed,
            risks: risks
        )
    }
}

private enum VideoIntegrityInspectionError: LocalizedError {
    case ffprobeUnavailable
    case ffprobeFailed(String, String)
    case invalidResponse(String, String)
    case invalidDuration(String)

    var errorDescription: String? {
        switch self {
        case .ffprobeUnavailable:
            "当前 FFmpeg 安装缺少配套的 ffprobe，无法验证视频完整性"
        case .ffprobeFailed(let filename, let diagnostic):
            "ffprobe 无法读取视频“\(filename)”：\(diagnostic)"
        case .invalidResponse(let filename, let diagnostic):
            "ffprobe 无法解析视频“\(filename)”：\(diagnostic)"
        case .invalidDuration(let filename):
            "视频“\(filename)”没有可读取的有效时长"
        }
    }
}

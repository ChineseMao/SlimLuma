import Foundation

enum FFmpegAV1Encoder: String, Equatable, Sendable {
    case svtAV1 = "libsvtav1"
    case libaomAV1 = "libaom-av1"

    func speedArguments(for speed: VideoSpeed) -> [String] {
        switch self {
        case .svtAV1:
            let preset: Int
            switch speed {
            case .fastest: preset = 12
            case .fast: preset = 10
            case .balanced: preset = 8
            case .small: preset = 6
            case .smallest: preset = 4
            }
            return ["-preset", "\(preset)"]

        case .libaomAV1:
            let cpuUsed: Int
            switch speed {
            case .fastest: cpuUsed = 8
            case .fast: cpuUsed = 7
            case .balanced: cpuUsed = 6
            case .small: cpuUsed = 4
            case .smallest: cpuUsed = 2
            }
            return ["-cpu-used", "\(cpuUsed)"]
        }
    }
}

struct FFmpegCapabilities: Equatable, Sendable {
    let videoEncoders: Set<String>

    var preferredAV1Encoder: FFmpegAV1Encoder? {
        if videoEncoders.contains(FFmpegAV1Encoder.svtAV1.rawValue) {
            return .svtAV1
        }
        if videoEncoders.contains(FFmpegAV1Encoder.libaomAV1.rawValue) {
            return .libaomAV1
        }
        return nil
    }

    func requireAV1Encoder() throws -> FFmpegAV1Encoder {
        guard let preferredAV1Encoder else {
            throw CompressionError.invalidSettings(
                "当前 FFmpeg 不包含可用的 AV1 编码器（需要 libsvtav1 或 "
                    + "libaom-av1）。请更新或重新安装 FFmpeg，"
                    + "也可以先改用 H.264 或 HEVC。"
            )
        }
        return preferredAV1Encoder
    }

    static func parse(_ output: String) -> FFmpegCapabilities {
        var encoders = Set<String>()

        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2 else { continue }

            let flags = fields[0]
            guard flags.count == 6, flags.first == "V" else { continue }
            encoders.insert(String(fields[1]))
        }

        return FFmpegCapabilities(videoEncoders: encoders)
    }
}

struct FFmpegCapabilityInspector: Sendable {
    private let runner: ProcessRunner

    init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    func inspect(executableURL: URL) async throws -> FFmpegCapabilities {
        try Task.checkCancellation()
        let result = try await runner.run(
            executableURL: executableURL,
            arguments: ["-hide_banner", "-encoders"]
        )
        try Task.checkCancellation()

        guard result.exitCode == 0 else {
            let diagnostic = result.standardError
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw CompressionError.processFailed(
                tool: "FFmpeg（编码能力检查）",
                exitCode: result.exitCode,
                message: diagnostic.isEmpty
                    ? "无法读取当前 FFmpeg 的编码器列表"
                    : String(diagnostic.suffix(1_500))
            )
        }

        return FFmpegCapabilities.parse(
            result.standardOutput + "\n" + result.standardError
        )
    }
}

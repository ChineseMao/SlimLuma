import ArgumentParser
import Foundation
import SlimLumaKit

/// Standalone command-line entry point. The file intentionally avoids the
/// special `main.swift` name so SwiftPM can build it for multiple architectures.
@main
struct SlimLumaCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "slimluma",
        abstract:
            "Local-first image, video and PDF compression powered by SlimLuma.",
        version: "0.2.0",
        subcommands: [Compress.self, Engines.self],
        defaultSubcommand: Compress.self
    )
}

private enum CLIImageFormat: String, ExpressibleByArgument, CaseIterable {
    case keep
    case jpeg
    case png
    case webp
    case avif
    case heic
}

private enum CLIVideoCodec: String, ExpressibleByArgument, CaseIterable {
    case h264
    case hevc
    case av1
}

private enum CLIPDFMode: String, ExpressibleByArgument, CaseIterable {
    case lossless
    case balanced
    case compact
    case custom
}

private struct Compress: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Compress one or more files without launching the app."
    )

    @Argument(help: "Image, video or PDF files to compress.")
    var files: [String] = []

    @Option(
        name: [.customShort("o"), .customLong("output-directory")],
        help: "Write results to this directory."
    )
    var outputDirectory: String?

    @Option(help: "Load the first preset from a SlimLuma preset JSON file.")
    var presetFile: String?

    @Option(help: "Image output format: keep, jpeg, png, webp, avif or heic.")
    var imageFormat: CLIImageFormat?

    @Option(help: "Video codec: h264, hevc or av1.")
    var videoCodec: CLIVideoCodec?

    @Option(help: "PDF mode: lossless, balanced, compact or custom.")
    var pdfMode: CLIPDFMode?

    @Option(help: "Image/video quality from 1 to 100.")
    var quality: Int?

    @Option(help: "Target size in MB for images and videos.")
    var targetSizeMB: Double?

    @Option(help: "Read the PDF password from the first line of this file.")
    var pdfPasswordFile: String?

    @Option(help: "Filename suffix for generated files.")
    var suffix = "-slim"

    @Flag(help: "Use lossless image encoding where the format supports it.")
    var lossless = false

    @Flag(help: "Keep results that are not smaller than the source.")
    var keepLarger = false

    @Flag(help: "Print machine-readable JSON results.")
    var json = false

    @Flag(help: "Validate arguments and print the plan without writing files.")
    var dryRun = false

    mutating func validate() throws {
        guard !files.isEmpty else {
            throw ValidationError("Provide at least one input file.")
        }
        if let quality, !(1...100).contains(quality) {
            throw ValidationError("--quality must be between 1 and 100.")
        }
        if let targetSizeMB, targetSizeMB <= 0 {
            throw ValidationError("--target-size-mb must be greater than zero.")
        }
        if targetSizeMB != nil, videoCodec == .av1 {
            throw ValidationError(
                "Target-size video encoding supports h264 and hevc, not av1."
            )
        }
    }

    mutating func run() async throws {
        var settings = try loadedSettings()
        applyOverrides(to: &settings)
        let inputURLs = files.map {
            URL(fileURLWithPath: $0).standardizedFileURL
        }
        for url in inputURLs {
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ValidationError("Input does not exist: \(url.path)")
            }
            guard MediaKind.detect(url: url) != .unknown else {
                throw ValidationError(
                    "Unsupported input format: \(url.lastPathComponent)"
                )
            }
        }

        if dryRun {
            try printPlan(inputs: inputURLs, settings: settings)
            return
        }

        let pdfPassword = try readPDFPassword()
        let coordinator = CompressionCoordinator()
        var results: [CompressionResult] = []
        var failures: [String] = []
        let outputsJSON = json

        for (index, inputURL) in inputURLs.enumerated() {
            do {
                let result = try await coordinator.compress(
                    inputURL: inputURL,
                    settings: settings,
                    pdfPassword: pdfPassword,
                    progressHandler: { progress in
                        guard !outputsJSON else { return }
                        let percent = Int(
                            (progress.fractionCompleted * 100).rounded()
                        )
                        writeStandardError(
                            "\r[\(index + 1)/\(inputURLs.count)] "
                                + "\(percent)% \(progress.stage)      "
                        )
                    }
                )
                if !json {
                    writeStandardError("\n")
                }
                results.append(result)
            } catch {
                if !json {
                    writeStandardError("\n")
                }
                failures.append(
                    "\(inputURL.lastPathComponent): "
                        + error.localizedDescription
                )
            }
        }

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(results)
            print(String(decoding: data, as: UTF8.self))
        } else {
            for result in results {
                if let outputURL = result.outputURL {
                    print(
                        "\(result.inputURL.lastPathComponent) -> "
                            + "\(outputURL.path) "
                            + "(\(result.originalBytes) -> "
                            + "\(result.outputBytes ?? 0) bytes)"
                    )
                } else {
                    print(
                        "\(result.inputURL.lastPathComponent): "
                            + (result.warning ?? "no output generated")
                    )
                }
            }
        }

        if !failures.isEmpty {
            for failure in failures {
                writeStandardError("error: \(failure)\n")
            }
            throw ExitCode.failure
        }
    }

    private func loadedSettings() throws -> CompressionSettings {
        guard let presetFile else { return .default }
        let url = URL(fileURLWithPath: presetFile)
        let data = try Data(contentsOf: url)
        let document = try JSONDecoder().decode(
            PresetExchangeDocument.self,
            from: data
        )
        guard document.formatVersion == 1,
              document.exportedBy == "SlimLuma",
              let preset = document.presets.first else {
            throw ValidationError("Unsupported or empty SlimLuma preset file.")
        }
        return preset.settings
    }

    private func applyOverrides(to settings: inout CompressionSettings) {
        if let imageFormat {
            settings.image.format = ImageOutputFormat(
                rawValue: imageFormat.rawValue
            ) ?? .keep
        }
        if let videoCodec {
            settings.video.codec = VideoCodec(
                rawValue: videoCodec.rawValue
            ) ?? .h264
        }
        if let pdfMode {
            settings.pdf.mode = PDFCompressionMode(
                rawValue: pdfMode.rawValue
            ) ?? .balanced
        }
        if let quality {
            settings.image.quality = quality
            settings.video.quality = quality
        }
        if let targetSizeMB {
            let target = Int64((targetSizeMB * 1_048_576).rounded())
            settings.image.targetSizeBytes = target
            settings.video.targetSizeBytes = target
        }
        settings.image.lossless = lossless
        settings.output.filenameSuffix = suffix
        settings.output.keepLargerFiles = keepLarger
        if let outputDirectory {
            settings.output.location = .customDirectory
            settings.output.customDirectoryPath = URL(
                fileURLWithPath: outputDirectory
            ).standardizedFileURL.path
        }
    }

    private func readPDFPassword() throws -> String? {
        guard let pdfPasswordFile else { return nil }
        let data = try Data(
            contentsOf: URL(fileURLWithPath: pdfPasswordFile)
        )
        guard data.count <= 64 * 1_024,
              let text = String(data: data, encoding: .utf8) else {
            throw ValidationError("The PDF password file is invalid.")
        }
        return text.split(
            omittingEmptySubsequences: false,
            whereSeparator: \.isNewline
        ).first.map(String.init)
    }

    private func printPlan(
        inputs: [URL],
        settings: CompressionSettings
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let payload = DryRunPlan(
            inputs: inputs.map(\.path),
            settings: settings
        )
        print(String(decoding: try encoder.encode(payload), as: UTF8.self))
    }
}

private struct Engines: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show compression engine availability and repair commands."
    )

    @Flag(help: "Print machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let availability = ToolRegistry().availability()
        if json {
            let rows = availability.map {
                EngineStatus(
                    id: $0.kind.rawValue,
                    name: $0.kind.displayName,
                    available: $0.isAvailable,
                    executable: $0.executableURL?.path,
                    recoveryCommand:
                        $0.isAvailable ? nil : $0.recoveryCommand
                )
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(
                String(
                    decoding: try encoder.encode(rows),
                    as: UTF8.self
                )
            )
            return
        }

        for tool in availability {
            let state = tool.isAvailable ? "ready" : "missing"
            print("\(tool.kind.displayName): \(state)")
            if !tool.isAvailable {
                print("  repair: \(tool.recoveryCommand)")
            }
        }
    }
}

private struct DryRunPlan: Codable {
    let inputs: [String]
    let settings: CompressionSettings
}

private struct EngineStatus: Codable {
    let id: String
    let name: String
    let available: Bool
    let executable: String?
    let recoveryCommand: String?
}

private func writeStandardError(_ text: String) {
    FileHandle.standardError.write(Data(text.utf8))
}

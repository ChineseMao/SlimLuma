import CoreGraphics
import Foundation
import ImageIO
import PDFKit
@testable import SlimLumaKit
import UniformTypeIdentifiers
import XCTest

final class EngineIntegrationTests: XCTestCase {
    func testAvailableImageEngineProducesValidatedJPEG() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("source.jpg")
        try makeJPEG(at: input)

        var settings = CompressionSettings.default
        settings.image.format = .jpeg
        settings.image.quality = 68
        settings.image.preserveColorProfile = false
        settings.output.location = .customDirectory
        settings.output.customDirectoryPath = directory.path
        settings.output.keepLargerFiles = true

        let result = try await CompressionCoordinator().compress(
            inputURL: input,
            settings: settings
        )

        XCTAssertTrue(["ImageMagick", "macOS ImageIO"].contains(result.engineName))
        XCTAssertEqual(result.outputURL?.pathExtension, "jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputURL?.path ?? ""))
        XCTAssertGreaterThan(result.outputBytes ?? 0, 0)
    }

    func testSystemImageFallbackProducesValidatedJPEGWithoutImageMagick() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("system-fallback.jpg")
        try makeJPEG(at: input)

        var settings = CompressionSettings.default
        settings.image.format = .jpeg
        settings.image.quality = 68
        settings.image.preserveColorProfile = false
        settings.output.location = .customDirectory
        settings.output.customDirectoryPath = directory.path
        settings.output.keepLargerFiles = true

        let systemOnlyRegistry = ToolRegistry(
            searchDirectories: [
                URL(fileURLWithPath: "/usr/bin", isDirectory: true),
                URL(fileURLWithPath: "/bin", isDirectory: true)
            ]
        )
        let result = try await CompressionCoordinator(
            registry: systemOnlyRegistry
        ).compress(
            inputURL: input,
            settings: settings
        )

        XCTAssertEqual(result.engineID, .macOSImageIO)
        XCTAssertEqual(result.outputURL?.pathExtension, "jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputURL?.path ?? ""))
        XCTAssertGreaterThan(result.outputBytes ?? 0, 0)
    }

    func testImageMagickProducesValidatedWebP() async throws {
        let registry = ToolRegistry()
        guard registry.locate(.imageMagick) != nil else {
            throw XCTSkip("ImageMagick is not installed")
        }

        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("gradient.jpg")
        try makeJPEG(at: input)

        var settings = CompressionSettings.default
        settings.image.format = .webp
        settings.image.quality = 72
        settings.output.location = .customDirectory
        settings.output.customDirectoryPath = directory.path
        settings.output.keepLargerFiles = true

        let result = try await CompressionCoordinator().compress(
            inputURL: input,
            settings: settings
        )

        XCTAssertEqual(result.engineName, "ImageMagick")
        XCTAssertEqual(result.outputURL?.pathExtension, "webp")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputURL?.path ?? ""))
        XCTAssertGreaterThan(result.outputBytes ?? 0, 0)
    }

    func testImageMagickRemovesAllMetadataWhilePreservingICC() async throws {
        let registry = ToolRegistry()
        guard let imageMagick = registry.locate(.imageMagick) else {
            throw XCTSkip("ImageMagick is not installed")
        }
        let profileURL = URL(
            fileURLWithPath:
                "/System/Library/ColorSync/Profiles/AdobeRGB1998.icc"
        )
        guard FileManager.default.fileExists(atPath: profileURL.path) else {
            throw XCTSkip("The Adobe RGB test profile is unavailable")
        }

        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("metadata-source.jpg")

        let fixture = try await ProcessRunner().run(
            executableURL: imageMagick,
            arguments: [
                "-size", "96x64",
                "gradient:#123456-#fedcba",
                "-profile", profileURL.path,
                "-set", "comment", "SlimLuma sensitive metadata fixture",
                input.path
            ]
        )
        XCTAssertEqual(fixture.exitCode, 0, fixture.standardError)

        var settings = CompressionSettings.default
        settings.image.format = .keep
        settings.image.quality = 88
        settings.image.metadata = .removeAll
        settings.image.preserveColorProfile = true
        settings.output.location = .customDirectory
        settings.output.customDirectoryPath = directory.path
        settings.output.keepLargerFiles = true

        let result = try await CompressionCoordinator().compress(
            inputURL: input,
            settings: settings
        )
        let output = try XCTUnwrap(result.outputURL)

        let inspection = try await ProcessRunner().run(
            executableURL: imageMagick,
            arguments: [
                "identify",
                "-quiet",
                "-format",
                "%[profiles]|%[comment]",
                output.path
            ]
        )
        XCTAssertEqual(inspection.exitCode, 0, inspection.standardError)
        XCTAssertTrue(
            inspection.standardOutput.lowercased().contains("icc"),
            inspection.standardOutput
        )
        XCTAssertFalse(
            inspection.standardOutput.contains(
                "SlimLuma sensitive metadata fixture"
            ),
            inspection.standardOutput
        )
    }

    func testFFmpegProducesValidatedMP4() async throws {
        let registry = ToolRegistry()
        guard let ffmpeg = registry.locate(.ffmpeg) else {
            throw XCTSkip("FFmpeg is not installed")
        }

        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("sample.mov")

        let fixtureResult = try await ProcessRunner().run(
            executableURL: ffmpeg,
            arguments: [
                "-hide_banner", "-nostdin", "-y",
                "-f", "lavfi",
                "-i", "testsrc=size=640x360:rate=24",
                "-t", "1",
                "-c:v", "libx264",
                "-pix_fmt", "yuv420p",
                input.path
            ]
        )
        XCTAssertEqual(fixtureResult.exitCode, 0, fixtureResult.standardError)

        var settings = CompressionSettings.default
        settings.video.codec = .h264
        settings.video.hardwareAcceleration = false
        settings.video.maxWidth = 320
        settings.video.maxHeight = 180
        settings.output.location = .customDirectory
        settings.output.customDirectoryPath = directory.path
        settings.output.keepLargerFiles = true

        let result = try await CompressionCoordinator().compress(
            inputURL: input,
            settings: settings
        )

        XCTAssertEqual(result.engineName, "FFmpeg")
        XCTAssertEqual(result.outputURL?.pathExtension, "mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputURL?.path ?? ""))
        XCTAssertGreaterThan(result.outputBytes ?? 0, 0)
    }

    func testFFmpegCompressesH264MKVWithAudioAndSubtitleEndToEnd() async throws {
        let registry = ToolRegistry()
        guard let ffmpeg = registry.locate(.ffmpeg) else {
            throw XCTSkip("FFmpeg is not installed")
        }
        guard let ffprobe = registry.locateFFprobe(companionTo: ffmpeg) else {
            throw XCTSkip("This FFmpeg installation does not include ffprobe")
        }
        let capabilities = try await FFmpegCapabilityInspector().inspect(
            executableURL: ffmpeg
        )
        guard capabilities.videoEncoders.contains("libx264") else {
            throw XCTSkip("This FFmpeg installation does not include libx264")
        }

        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("h264-source.mkv")
        try await makeMatroskaFixture(at: input, ffmpeg: ffmpeg)

        var settings = CompressionSettings.default
        settings.video.codec = .h264
        settings.video.hardwareAcceleration = false
        settings.video.maxWidth = nil
        settings.video.maxHeight = nil
        settings.output.location = .customDirectory
        settings.output.customDirectoryPath = directory.path
        settings.output.keepLargerFiles = true

        let result = try await CompressionCoordinator().compress(
            inputURL: input,
            settings: settings
        )
        let output = try XCTUnwrap(result.outputURL)
        let report = try await VideoIntegrityChecker(
            ffprobeURL: ffprobe
        ).compare(
            originalURL: input,
            compressedURL: output
        )

        XCTAssertEqual(result.engineName, "FFmpeg")
        XCTAssertEqual(output.pathExtension, "mp4")
        XCTAssertFalse(report.hasCriticalRisk, report.summary)
        XCTAssertEqual(report.original.subtitleTrackCount, 1)
        XCTAssertEqual(report.compressed.subtitleTrackCount, 1)
    }

    func testFFmpegProducesValidatedAV1MKVWhenEncoderIsAvailable() async throws {
        let registry = ToolRegistry()
        guard let ffmpeg = registry.locate(.ffmpeg) else {
            throw XCTSkip("FFmpeg is not installed")
        }
        guard let ffprobe = registry.locateFFprobe(companionTo: ffmpeg) else {
            throw XCTSkip("This FFmpeg installation does not include ffprobe")
        }
        let capabilities = try await FFmpegCapabilityInspector().inspect(
            executableURL: ffmpeg
        )
        guard capabilities.preferredAV1Encoder != nil else {
            throw XCTSkip(
                "FFmpeg has neither libsvtav1 nor libaom-av1; "
                    + "AV1 selection is covered by unit tests"
            )
        }
        guard capabilities.videoEncoders.contains("libx264") else {
            throw XCTSkip("This FFmpeg installation does not include libx264 for the fixture")
        }

        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("av1-source.mkv")
        try await makeMatroskaFixture(at: input, ffmpeg: ffmpeg)

        var settings = CompressionSettings.default
        settings.video.codec = .av1
        settings.video.speed = .fastest
        settings.video.hardwareAcceleration = false
        settings.video.maxWidth = nil
        settings.video.maxHeight = nil
        settings.output.location = .customDirectory
        settings.output.customDirectoryPath = directory.path
        settings.output.keepLargerFiles = true

        let result = try await CompressionCoordinator().compress(
            inputURL: input,
            settings: settings
        )
        let output = try XCTUnwrap(result.outputURL)
        let report = try await VideoIntegrityChecker(
            ffprobeURL: ffprobe
        ).compare(
            originalURL: input,
            compressedURL: output
        )
        let codecProbe = try await ProcessRunner().run(
            executableURL: ffprobe,
            arguments: [
                "-v", "error",
                "-select_streams", "v:0",
                "-show_entries", "stream=codec_name",
                "-of", "default=noprint_wrappers=1:nokey=1",
                output.path
            ]
        )

        XCTAssertEqual(result.engineName, "FFmpeg")
        XCTAssertEqual(output.pathExtension, "mkv")
        XCTAssertFalse(report.hasCriticalRisk, report.summary)
        XCTAssertEqual(report.compressed.subtitleTrackCount, 1)
        XCTAssertEqual(codecProbe.exitCode, 0, codecProbe.standardError)
        XCTAssertEqual(
            codecProbe.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines),
            "av1"
        )
    }

    func testQPDFProducesValidatedPDF() async throws {
        let registry = ToolRegistry()
        guard registry.locate(.qpdf) != nil else {
            throw XCTSkip("qpdf is not installed")
        }

        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("sample.pdf")
        try makePDF(at: input)

        var settings = CompressionSettings.default
        settings.pdf.engine = .qpdf
        settings.pdf.mode = .lossless
        settings.output.location = .customDirectory
        settings.output.customDirectoryPath = directory.path
        settings.output.keepLargerFiles = true

        let result = try await CompressionCoordinator().compress(
            inputURL: input,
            settings: settings
        )

        XCTAssertEqual(result.engineName, "qpdf")
        XCTAssertEqual(result.outputURL?.pathExtension, "pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputURL?.path ?? ""))
        XCTAssertGreaterThan(result.outputBytes ?? 0, 0)
    }

    func testAutomaticPDFEngineAlwaysHasValidatedFallback() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("automatic.pdf")
        try makePDF(at: input)

        var settings = CompressionSettings.default
        settings.pdf.engine = .automatic
        settings.pdf.mode = .balanced
        settings.output.location = .customDirectory
        settings.output.customDirectoryPath = directory.path
        settings.output.keepLargerFiles = true

        let result = try await CompressionCoordinator().compress(
            inputURL: input,
            settings: settings
        )

        XCTAssertTrue(
            ["qpdf", "Ghostscript", "Ghostscript + qpdf", "macOS PDFKit"]
                .contains(result.engineName)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputURL?.path ?? ""))
        XCTAssertGreaterThan(result.outputBytes ?? 0, 0)
    }

    func testGhostscriptQPDFPipelinePreservesOutlineAndLinearizes() async throws {
        let registry = ToolRegistry()
        guard registry.locate(.ghostscript) != nil,
              registry.locate(.qpdf) != nil else {
            throw XCTSkip("Ghostscript and qpdf are both required")
        }

        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("outlined.pdf")
        try makePDF(at: input)
        try addOutline(to: input)

        var settings = CompressionSettings.default
        settings.pdf.engine = .ghostscript
        settings.pdf.mode = .compact
        settings.pdf.imageQuality = 55
        settings.pdf.imageDPI = 96
        settings.pdf.linearizeForWeb = true
        settings.output.location = .customDirectory
        settings.output.customDirectoryPath = directory.path
        settings.output.keepLargerFiles = true

        let result = try await CompressionCoordinator().compress(
            inputURL: input,
            settings: settings
        )

        let output = try XCTUnwrap(result.outputURL)
        let report = try PDFIntegrityChecker().compare(
            originalURL: input,
            compressedURL: output,
            expectations: PDFIntegrityExpectations(requireLinearization: true)
        )
        XCTAssertEqual(result.engineName, "Ghostscript + qpdf")
        XCTAssertFalse(report.hasCriticalRisk, "\(report.risks)")
        XCTAssertEqual(report.original.outlineCount, 1)
        XCTAssertEqual(report.compressed.outlineCount, 1)
        XCTAssertTrue(report.compressed.isLinearized)
    }

    func testImageTargetSizeProducesAValidatedResultAtOrBelowTarget() async throws {
        let registry = ToolRegistry()
        guard registry.locate(.imageMagick) != nil else {
            throw XCTSkip("ImageMagick is not installed")
        }

        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("target-source.jpg")
        try makeJPEG(at: input)
        let targetBytes: Int64 = 24 * 1_024

        var settings = CompressionSettings.default
        settings.image.format = .jpeg
        settings.image.quality = 92
        settings.image.targetSizeBytes = targetBytes
        settings.output.location = .customDirectory
        settings.output.customDirectoryPath = directory.path
        settings.output.keepLargerFiles = true

        let result = try await CompressionCoordinator().compress(
            inputURL: input,
            settings: settings
        )
        let output = try XCTUnwrap(result.outputURL)

        XCTAssertLessThanOrEqual(result.outputBytes ?? .max, targetBytes)
        XCTAssertNoThrow(try ImageIntegrityChecker().inspect(output))
    }

    func testVideoTargetSizeUsesTwoPassEncodingAndReportsProgress() async throws {
        let registry = ToolRegistry()
        guard let ffmpeg = registry.locate(.ffmpeg) else {
            throw XCTSkip("FFmpeg is not installed")
        }
        let capabilities = try await FFmpegCapabilityInspector().inspect(
            executableURL: ffmpeg
        )
        guard capabilities.videoEncoders.contains("libx264") else {
            throw XCTSkip("This FFmpeg installation does not include libx264")
        }

        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("target-video.mkv")
        try await makeMatroskaFixture(at: input, ffmpeg: ffmpeg)
        let targetBytes: Int64 = 256 * 1_024
        let progress = LockedProgressValues()

        var settings = CompressionSettings.default
        settings.video.codec = .h264
        settings.video.targetSizeBytes = targetBytes
        settings.video.hardwareAcceleration = true
        settings.video.audioBitrate = 64
        settings.video.maxWidth = nil
        settings.video.maxHeight = nil
        settings.output.location = .customDirectory
        settings.output.customDirectoryPath = directory.path
        settings.output.keepLargerFiles = true

        let result = try await CompressionCoordinator().compress(
            inputURL: input,
            settings: settings,
            progressHandler: { progress.append($0.fractionCompleted) }
        )

        XCTAssertNotNil(result.outputURL)
        XCTAssertLessThanOrEqual(
            result.outputBytes ?? .max,
            Int64(Double(targetBytes) * 1.05)
        )
        XCTAssertTrue(
            result.warning?.contains("两遍软件编码") == true,
            result.warning ?? ""
        )
        XCTAssertTrue(progress.values.contains { $0 > 0 && $0 < 1 })
        XCTAssertEqual(progress.values.last, 1)
    }

    func testEncryptedPDFIsUnlockedTemporarilyAndReencrypted() async throws {
        let registry = ToolRegistry()
        guard let qpdf = registry.locate(.qpdf) else {
            throw XCTSkip("qpdf is not installed")
        }

        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let plain = directory.appendingPathComponent("plain.pdf")
        let encrypted = directory.appendingPathComponent("encrypted.pdf")
        let argumentsFile = directory.appendingPathComponent("encrypt.args")
        let password = "SlimLuma-test-password"
        try makePDF(at: plain)
        try Data(
            [
                plain.path,
                "--encrypt",
                "--user-password=\(password)",
                "--owner-password=SlimLuma-test-owner-password",
                "--bits=256",
                "--",
                encrypted.path
            ]
            .joined(separator: "\n")
            .appending("\n")
            .utf8
        ).write(to: argumentsFile)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: argumentsFile.path
        )
        let encryption = try await ProcessRunner().run(
            executableURL: qpdf,
            arguments: ["@\(argumentsFile.path)"]
        )
        XCTAssertEqual(encryption.exitCode, 0, encryption.standardError)

        var settings = CompressionSettings.default
        settings.pdf.engine = .qpdf
        settings.pdf.mode = .lossless
        settings.pdf.linearizeForWeb = true
        settings.output.location = .customDirectory
        settings.output.customDirectoryPath = directory.path
        settings.output.keepLargerFiles = true

        let result = try await CompressionCoordinator().compress(
            inputURL: encrypted,
            settings: settings,
            pdfPassword: password
        )
        let output = try XCTUnwrap(result.outputURL)
        let snapshot = try PDFIntegrityChecker().inspect(
            output,
            password: password
        )

        XCTAssertTrue(snapshot.isEncrypted)
        XCTAssertFalse(snapshot.isLocked)
        XCTAssertEqual(snapshot.pageCount, 3)
        XCTAssertTrue(snapshot.isLinearized)
        XCTAssertTrue(
            result.warning?.contains("保留原 PDF 加密策略") == true,
            result.warning ?? ""
        )
    }

    func testExternalPDFFixtureWhenProvided() async throws {
        guard let path = ProcessInfo.processInfo.environment[
            "SLIMLUMA_REAL_PDF"
        ] else {
            throw XCTSkip("Set SLIMLUMA_REAL_PDF to run a local document check")
        }
        let input = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: input.path) else {
            throw XCTSkip("SLIMLUMA_REAL_PDF does not exist")
        }

        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var settings = CompressionSettings.default
        settings.pdf.engine = .ghostscript
        settings.pdf.mode = .compact
        settings.pdf.imageQuality = 41
        settings.pdf.imageDPI = 150
        settings.pdf.linearizeForWeb = true
        settings.output.location = .customDirectory
        settings.output.customDirectoryPath = directory.path
        settings.output.keepLargerFiles = true

        let result = try await CompressionCoordinator().compress(
            inputURL: input,
            settings: settings
        )
        let output = try XCTUnwrap(result.outputURL)
        let report = try PDFIntegrityChecker().compare(
            originalURL: input,
            compressedURL: output,
            expectations: PDFIntegrityExpectations(requireLinearization: true)
        )

        XCTAssertFalse(report.hasCriticalRisk, "\(report.risks)")
        XCTAssertTrue(report.compressed.isLinearized)
        print(
            "REAL_PDF_RESULT bytes=\(result.originalBytes)->\(result.outputBytes ?? 0) "
                + "pages=\(report.original.pageCount)->\(report.compressed.pageCount) "
                + "outlines=\(report.original.outlineCount)->\(report.compressed.outlineCount)"
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SlimLumaIntegration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func makeJPEG(at url: URL) throws {
        let width = 1_200
        let height = 800
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TestFixtureError.creationFailed
        }

        for row in 0..<80 {
            let fraction = CGFloat(row) / 79
            context.setFillColor(
                red: 0.2 + fraction * 0.6,
                green: 0.75 - fraction * 0.4,
                blue: 0.9,
                alpha: 1
            )
            context.fill(
                CGRect(
                    x: 0,
                    y: CGFloat(row) * 10,
                    width: CGFloat(width),
                    height: 11
                )
            )
        }

        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                  url as CFURL,
                  UTType.jpeg.identifier as CFString,
                  1,
                  nil
              ) else {
            throw TestFixtureError.creationFailed
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.96] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw TestFixtureError.creationFailed
        }
    }

    private func makeMatroskaFixture(
        at url: URL,
        ffmpeg: URL
    ) async throws {
        let subtitleURL = url
            .deletingPathExtension()
            .appendingPathExtension("srt")
        try Data(
            """
            1
            00:00:00,100 --> 00:00:00,900
            SlimLuma subtitle integrity fixture

            """.utf8
        ).write(to: subtitleURL)

        let result = try await ProcessRunner().run(
            executableURL: ffmpeg,
            arguments: [
                "-hide_banner", "-nostdin", "-y",
                "-f", "lavfi",
                "-i", "testsrc=size=320x180:rate=24",
                "-f", "lavfi",
                "-i", "sine=frequency=880:sample_rate=48000",
                "-f", "srt",
                "-i", subtitleURL.path,
                "-t", "1.25",
                "-map", "0:v:0",
                "-map", "1:a:0",
                "-map", "2:s:0",
                "-c:v", "libx264",
                "-pix_fmt", "yuv420p",
                "-c:a", "aac",
                "-c:s", "srt",
                url.path
            ]
        )
        XCTAssertEqual(result.exitCode, 0, result.standardError)
    }

    private func makePDF(at url: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw TestFixtureError.creationFailed
        }

        for page in 0..<3 {
            context.beginPDFPage(nil)
            context.setFillColor(
                red: 0.2,
                green: CGFloat(page + 1) * 0.18,
                blue: 0.75,
                alpha: 1
            )
            for index in 0..<120 {
                let x = CGFloat((index * 47) % 560)
                let y = CGFloat((index * 79) % 730)
                context.fillEllipse(
                    in: CGRect(x: x, y: y, width: 28, height: 28)
                )
            }
            context.endPDFPage()
        }
        context.closePDF()
    }

    private func addOutline(to url: URL) throws {
        guard let document = PDFDocument(url: url),
              let firstPage = document.page(at: 0) else {
            throw TestFixtureError.creationFailed
        }
        let root = PDFOutline()
        let child = PDFOutline()
        child.label = "第一页"
        child.destination = PDFDestination(
            page: firstPage,
            at: CGPoint(x: 0, y: firstPage.bounds(for: .mediaBox).height)
        )
        root.insertChild(child, at: 0)
        document.outlineRoot = root
        guard document.write(to: url) else {
            throw TestFixtureError.creationFailed
        }
    }
}

private final class LockedProgressValues: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Double] = []

    var values: [Double] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: Double) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}

private enum TestFixtureError: Error {
    case creationFailed
}

import CoreGraphics
import Foundation
import ImageIO
@testable import SlimLumaKit
import UniformTypeIdentifiers
import XCTest

final class AnimatedImageIntegrityTests: XCTestCase {
    func testInspectorCountsAndDecodesEveryFrameInRealGIF() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let animatedGIF = directory.appendingPathComponent("animated.gif")
        try makeGIF(at: animatedGIF, frameCount: 4)

        let snapshot = try ImageIntegrityChecker().inspect(animatedGIF)

        XCTAssertEqual(snapshot.frameCount, 4)
        XCTAssertTrue(snapshot.isAnimated)
    }

    func testSourceAwareValidationRejectsAnimationCollapsedToOneFrame() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.gif")
        let output = directory.appendingPathComponent("output.gif")
        try makeGIF(at: source, frameCount: 4)
        try makeGIF(at: output, frameCount: 1)

        do {
            try await FileValidator.validate(
                url: output,
                kind: .image,
                sourceURL: source
            )
            XCTFail("A multi-frame source must not silently become a still image")
        } catch CompressionError.outputInvalid(let message) {
            XCTAssertTrue(message.contains("4"), message)
            XCTAssertTrue(message.contains("1"), message)
            XCTAssertTrue(message.contains("动画"), message)
        }
    }

    func testSourceAwareValidationRejectsPartialFrameLoss() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.gif")
        let output = directory.appendingPathComponent("output.gif")
        try makeGIF(at: source, frameCount: 5)
        try makeGIF(at: output, frameCount: 3)

        do {
            try await FileValidator.validate(
                url: output,
                kind: .image,
                sourceURL: source
            )
            XCTFail("Dropping animation frames must fail output validation")
        } catch CompressionError.outputInvalid(let message) {
            XCTAssertTrue(message.contains("5"), message)
            XCTAssertTrue(message.contains("3"), message)
        }
    }

    func testSourceAwareValidationAcceptsPreservedAnimation() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.gif")
        let output = directory.appendingPathComponent("output.gif")
        try makeGIF(at: source, frameCount: 3)
        try makeGIF(at: output, frameCount: 3)

        try await FileValidator.validate(
            url: output,
            kind: .image,
            sourceURL: source
        )
    }

    func testComparisonRejectsPerFrameTimingChangesWhenTotalDurationMatches() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.gif")
        let output = directory.appendingPathComponent("output.gif")
        try makeGIF(
            at: source,
            frameDurations: [0.10, 0.20, 0.30],
            loopCount: 0
        )
        try makeGIF(
            at: output,
            frameDurations: [0.30, 0.20, 0.10],
            loopCount: 0
        )

        let report = try ImageIntegrityChecker().compare(
            originalURL: source,
            compressedURL: output
        )

        XCTAssertEqual(
            report.original.frameDurations.compactMap { $0 }.reduce(0, +),
            report.compressed.frameDurations.compactMap { $0 }.reduce(0, +),
            accuracy: 0.001
        )
        XCTAssertTrue(
            report.risks.contains { $0.code == .animationTimingChanged },
            report.summary
        )
    }

    func testComparisonRejectsMissingFrameTimingMetadata() {
        let report = ImageIntegrityChecker().compare(
            original: ImageIntegritySnapshot(
                frameCount: 3,
                frameDurations: [0.10, 0.20, 0.30],
                loopCount: 0
            ),
            compressed: ImageIntegritySnapshot(
                frameCount: 3,
                frameDurations: [0.10, nil, 0.30],
                loopCount: 0
            )
        )

        XCTAssertTrue(
            report.risks.contains { $0.code == .animationTimingChanged },
            report.summary
        )
    }

    func testComparisonRejectsMissingLoopMetadata() {
        let durations: [Double?] = [0.10, 0.20, 0.30]
        let report = ImageIntegrityChecker().compare(
            original: ImageIntegritySnapshot(
                frameCount: 3,
                frameDurations: durations,
                loopCount: 3
            ),
            compressed: ImageIntegritySnapshot(
                frameCount: 3,
                frameDurations: durations,
                loopCount: nil
            )
        )

        XCTAssertTrue(
            report.risks.contains { $0.code == .animationLoopChanged },
            report.summary
        )
    }

    func testImageMagickKeepFormatPreservesRealGIFFrames() async throws {
        let registry = ToolRegistry()
        guard let imageMagick = registry.locate(.imageMagick) else {
            throw XCTSkip("ImageMagick is not installed")
        }

        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.gif")
        let output = directory.appendingPathComponent("output.gif")
        try makeGIF(at: source, frameCount: 3)

        let process = try await ProcessRunner().run(
            executableURL: imageMagick,
            arguments: ImageMagickCommandBuilder.arguments(
                input: source,
                output: output,
                settings: ImageCompressionSettings(
                    format: .keep,
                    quality: 76,
                    maxWidth: 80,
                    maxHeight: 80
                )
            )
        )
        XCTAssertEqual(process.exitCode, 0, process.standardError)

        let report = try ImageIntegrityChecker().compare(
            originalURL: source,
            compressedURL: output
        )
        XCTAssertFalse(report.hasCriticalRisk, report.summary)
        XCTAssertEqual(report.original.frameCount, 3)
        XCTAssertEqual(report.compressed.frameCount, 3)
    }

    func testImageMagickWebPPreservesGIFAnimationTiming() async throws {
        let registry = ToolRegistry()
        guard let imageMagick = registry.locate(.imageMagick) else {
            throw XCTSkip("ImageMagick is not installed")
        }

        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.gif")
        let output = directory.appendingPathComponent("output.webp")
        try makeGIF(at: source, frameCount: 3)

        let process = try await ProcessRunner().run(
            executableURL: imageMagick,
            arguments: ImageMagickCommandBuilder.arguments(
                input: source,
                output: output,
                settings: ImageCompressionSettings(
                    format: .webp,
                    quality: 76,
                    maxWidth: 80,
                    maxHeight: 80
                )
            )
        )
        XCTAssertEqual(process.exitCode, 0, process.standardError)

        let report = try ImageIntegrityChecker().compare(
            originalURL: source,
            compressedURL: output
        )
        XCTAssertFalse(report.hasCriticalRisk, report.summary)
        XCTAssertEqual(report.original.frameCount, 3)
        XCTAssertEqual(report.compressed.frameCount, 3)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SlimLumaAnimatedImageTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func makeGIF(at url: URL, frameCount: Int) throws {
        try makeGIF(
            at: url,
            frameDurations: (0..<frameCount).map {
                0.08 + Double($0) * 0.03
            },
            loopCount: 0
        )
    }

    private func makeGIF(
        at url: URL,
        frameDurations: [Double?],
        loopCount: Int?
    ) throws {
        guard !frameDurations.isEmpty,
              let destination = CGImageDestinationCreateWithURL(
                  url as CFURL,
                  UTType.gif.identifier as CFString,
                  frameDurations.count,
                  nil
              ) else {
            throw FixtureError.creationFailed
        }

        if let loopCount {
            CGImageDestinationSetProperties(
                destination,
                [
                    kCGImagePropertyGIFDictionary: [
                        kCGImagePropertyGIFLoopCount: loopCount
                    ]
                ] as CFDictionary
            )
        }

        for (index, duration) in frameDurations.enumerated() {
            guard let image = makeFrame(index: index) else {
                throw FixtureError.creationFailed
            }
            let frameProperties: CFDictionary?
            if let duration {
                frameProperties = [
                    kCGImagePropertyGIFDictionary: [
                        kCGImagePropertyGIFDelayTime: duration
                    ]
                ] as CFDictionary
            } else {
                frameProperties = nil
            }
            CGImageDestinationAddImage(
                destination,
                image,
                frameProperties
            )
        }

        guard CGImageDestinationFinalize(destination) else {
            throw FixtureError.creationFailed
        }
    }

    private func makeFrame(index: Int) -> CGImage? {
        let width = 96
        let height = 64
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let palette: [(CGFloat, CGFloat, CGFloat)] = [
            (0.95, 0.18, 0.32),
            (0.20, 0.78, 0.35),
            (0.04, 0.52, 0.95),
            (1.00, 0.62, 0.04),
            (0.69, 0.32, 0.87)
        ]
        let color = palette[index % palette.count]
        context.setFillColor(
            red: color.0,
            green: color.1,
            blue: color.2,
            alpha: 1
        )
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(gray: 1, alpha: 0.85)
        context.fill(
            CGRect(
                x: 8 + index * 7,
                y: 14,
                width: 20,
                height: 36
            )
        )
        return context.makeImage()
    }
}

private enum FixtureError: Error {
    case creationFailed
}

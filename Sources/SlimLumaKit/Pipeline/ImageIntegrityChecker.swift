import Foundation
import ImageIO

struct ImageIntegritySnapshot: Equatable, Sendable {
    let frameCount: Int
    let frameDurations: [Double?]
    let loopCount: Int?

    var isAnimated: Bool {
        frameCount > 1
    }
}

enum ImageIntegrityRiskCode: String, Equatable, Sendable {
    case animationRemoved
    case frameCountChanged
    case animationTimingChanged
    case animationLoopChanged
}

struct ImageIntegrityRisk: Equatable, Sendable {
    let code: ImageIntegrityRiskCode
    let message: String
}

struct ImageIntegrityReport: Equatable, Sendable {
    let original: ImageIntegritySnapshot
    let compressed: ImageIntegritySnapshot
    let risks: [ImageIntegrityRisk]

    var hasCriticalRisk: Bool {
        !risks.isEmpty
    }

    var summary: String {
        risks.map(\.message).joined(separator: "；")
    }
}

struct ImageIntegrityChecker {
    func inspect(_ url: URL) throws -> ImageIntegritySnapshot {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageIntegrityInspectionError.cannotOpen(url.lastPathComponent)
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else {
            throw ImageIntegrityInspectionError.noFrames(url.lastPathComponent)
        }

        let decodeOptions = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary
        for frameIndex in 0..<frameCount {
            guard CGImageSourceCreateImageAtIndex(
                source,
                frameIndex,
                decodeOptions
            ) != nil else {
                throw ImageIntegrityInspectionError.undecodableFrame(
                    filename: url.lastPathComponent,
                    frameNumber: frameIndex + 1,
                    frameCount: frameCount
                )
            }
        }

        let containerProperties = CGImageSourceCopyProperties(source, nil)
            as? [CFString: Any]
        let loopCount = animationLoopCount(in: containerProperties)
        let frameDurations = (0..<frameCount).map { frameIndex in
            let properties = CGImageSourceCopyPropertiesAtIndex(
                source,
                frameIndex,
                nil
            ) as? [CFString: Any]
            return animationDuration(in: properties)
        }

        return ImageIntegritySnapshot(
            frameCount: frameCount,
            frameDurations: frameDurations,
            loopCount: loopCount
        )
    }

    func compare(
        originalURL: URL,
        compressedURL: URL
    ) throws -> ImageIntegrityReport {
        let original = try inspect(originalURL)
        let compressed = try inspect(compressedURL)
        return compare(original: original, compressed: compressed)
    }

    func compare(
        original: ImageIntegritySnapshot,
        compressed: ImageIntegritySnapshot
    ) -> ImageIntegrityReport {
        var risks: [ImageIntegrityRisk] = []

        if original.isAnimated, compressed.frameCount != original.frameCount {
            let code: ImageIntegrityRiskCode =
                compressed.frameCount == 1
                    ? .animationRemoved
                    : .frameCountChanged
            risks.append(
                ImageIntegrityRisk(
                    code: code,
                    message:
                        "动画图片帧数从 \(original.frameCount) 帧变为 "
                        + "\(compressed.frameCount) 帧，输出已丢弃"
                )
            )
        }

        if original.isAnimated,
           compressed.frameCount == original.frameCount,
           animationTimingChanged(original: original, compressed: compressed) {
            risks.append(
                ImageIntegrityRisk(
                    code: .animationTimingChanged,
                    message: "动画图片的播放时序发生变化，输出已丢弃"
                )
            )
        }

        if original.isAnimated,
           let originalLoopCount = original.loopCount,
           compressed.loopCount != originalLoopCount {
            let message: String
            if let compressedLoopCount = compressed.loopCount {
                message =
                    "动画图片循环次数从 \(originalLoopCount) 变为 "
                    + "\(compressedLoopCount)，输出已丢弃"
            } else {
                message =
                    "动画图片循环设置（原为 \(originalLoopCount)）"
                    + "已丢失，输出已丢弃"
            }
            risks.append(
                ImageIntegrityRisk(
                    code: .animationLoopChanged,
                    message: message
                )
            )
        }

        return ImageIntegrityReport(
            original: original,
            compressed: compressed,
            risks: risks
        )
    }

    private func animationDuration(
        in properties: [CFString: Any]?
    ) -> Double? {
        guard let properties else { return nil }
        if let gif = properties[kCGImagePropertyGIFDictionary]
            as? [CFString: Any] {
            return number(
                gif[kCGImagePropertyGIFUnclampedDelayTime]
                    ?? gif[kCGImagePropertyGIFDelayTime]
            )
        }
        if let webP = properties[kCGImagePropertyWebPDictionary]
            as? [CFString: Any] {
            return number(webP[kCGImagePropertyWebPDelayTime])
        }
        return nil
    }

    private func animationLoopCount(
        in properties: [CFString: Any]?
    ) -> Int? {
        guard let properties else { return nil }
        if let gif = properties[kCGImagePropertyGIFDictionary]
            as? [CFString: Any] {
            return integer(gif[kCGImagePropertyGIFLoopCount])
        }
        if let webP = properties[kCGImagePropertyWebPDictionary]
            as? [CFString: Any] {
            return integer(webP[kCGImagePropertyWebPLoopCount])
        }
        return nil
    }

    private func animationTimingChanged(
        original: ImageIntegritySnapshot,
        compressed: ImageIntegritySnapshot
    ) -> Bool {
        guard original.frameDurations.count == original.frameCount else {
            return false
        }
        let originalDurations = original.frameDurations.compactMap { $0 }
        guard originalDurations.count == original.frameCount else {
            return false
        }

        guard compressed.frameDurations.count == compressed.frameCount else {
            return true
        }
        let compressedDurations = compressed.frameDurations.compactMap { $0 }
        guard compressedDurations.count == compressed.frameCount else {
            return true
        }

        return zip(originalDurations, compressedDurations).contains {
            originalDuration,
            compressedDuration in
            let tolerance = max(0.02, abs(originalDuration) * 0.05)
            return abs(originalDuration - compressedDuration) > tolerance
        }
    }

    private func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private func integer(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }
}

private enum ImageIntegrityInspectionError: LocalizedError {
    case cannotOpen(String)
    case noFrames(String)
    case undecodableFrame(filename: String, frameNumber: Int, frameCount: Int)

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let filename):
            "无法读取图片“\(filename)”"
        case .noFrames(let filename):
            "图片“\(filename)”不包含可读取画面"
        case .undecodableFrame(let filename, let frameNumber, let frameCount):
            "图片“\(filename)”第 \(frameNumber)/\(frameCount) 帧无法解码"
        }
    }
}

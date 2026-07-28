import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    fputs("Usage: swift generate-icon.swift <output-iconset>\n", stderr)
    exit(2)
}

let outputDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

struct IconSize {
    let points: Int
    let scale: Int

    var pixels: Int { points * scale }
    var filename: String {
        scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    }
}

let iconSizes = [
    IconSize(points: 16, scale: 1),
    IconSize(points: 16, scale: 2),
    IconSize(points: 32, scale: 1),
    IconSize(points: 32, scale: 2),
    IconSize(points: 128, scale: 1),
    IconSize(points: 128, scale: 2),
    IconSize(points: 256, scale: 1),
    IconSize(points: 256, scale: 2),
    IconSize(points: 512, scale: 1),
    IconSize(points: 512, scale: 2)
]

func makeIcon(pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "SlimLumaIcon", code: 1)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    defer { NSGraphicsContext.restoreGraphicsState() }

    let context = graphicsContext.cgContext
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let inset = CGFloat(pixels) * 0.055
    let rect = CGRect(x: inset, y: inset, width: CGFloat(pixels) - inset * 2, height: CGFloat(pixels) - inset * 2)
    let radius = CGFloat(pixels) * 0.225
    let path = CGPath(
        roundedRect: rect,
        cornerWidth: radius,
        cornerHeight: radius,
        transform: nil
    )

    context.saveGState()
    context.addPath(path)
    context.clip()
    let colors = [
        NSColor(red: 0.35, green: 0.31, blue: 0.92, alpha: 1).cgColor,
        NSColor(red: 0.08, green: 0.75, blue: 0.68, alpha: 1).cgColor
    ] as CFArray
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: colors,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: inset, y: CGFloat(pixels) - inset),
        end: CGPoint(x: CGFloat(pixels) - inset, y: inset),
        options: []
    )
    context.restoreGState()

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -CGFloat(pixels) * 0.018),
        blur: CGFloat(pixels) * 0.032,
        color: NSColor.black.withAlphaComponent(0.22).cgColor
    )

    let lineWidth = max(2, CGFloat(pixels) * 0.065)
    let center = CGFloat(pixels) / 2
    let outer = CGFloat(pixels) * 0.285
    let inner = CGFloat(pixels) * 0.075
    let head = CGFloat(pixels) * 0.095

    context.setStrokeColor(NSColor.white.cgColor)
    context.setLineWidth(lineWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    context.move(to: CGPoint(x: center - outer, y: center + outer))
    context.addLine(to: CGPoint(x: center - inner, y: center + inner))
    context.move(to: CGPoint(x: center - inner - head, y: center + inner))
    context.addLine(to: CGPoint(x: center - inner, y: center + inner))
    context.addLine(to: CGPoint(x: center - inner, y: center + inner + head))

    context.move(to: CGPoint(x: center + outer, y: center - outer))
    context.addLine(to: CGPoint(x: center + inner, y: center - inner))
    context.move(to: CGPoint(x: center + inner + head, y: center - inner))
    context.addLine(to: CGPoint(x: center + inner, y: center - inner))
    context.addLine(to: CGPoint(x: center + inner, y: center - inner - head))
    context.strokePath()
    context.restoreGState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "SlimLumaIcon", code: 2)
    }
    return png
}

for size in iconSizes {
    let data = try makeIcon(pixels: size.pixels)
    try data.write(to: outputDirectory.appendingPathComponent(size.filename))
}

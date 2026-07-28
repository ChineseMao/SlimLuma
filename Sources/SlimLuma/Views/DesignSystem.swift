import SwiftUI

enum SlimLumaStyle {
    static let accent = Color(red: 0.38, green: 0.34, blue: 0.92)
    static let secondaryAccent = Color(red: 0.10, green: 0.72, blue: 0.68)
    static let success = adaptiveColor(
        light: NSColor(srgbRed: 0.06, green: 0.43, blue: 0.24, alpha: 1),
        dark: NSColor(srgbRed: 0.30, green: 0.86, blue: 0.58, alpha: 1)
    )
    static let warning = adaptiveColor(
        light: NSColor(srgbRed: 0.58, green: 0.29, blue: 0.02, alpha: 1),
        dark: NSColor(srgbRed: 1.00, green: 0.70, blue: 0.34, alpha: 1)
    )
    static let interactiveSurface = Color(nsColor: .textBackgroundColor)
    static let settingsCanvas = Color(nsColor: .underPageBackgroundColor).opacity(0.28)
    static let controlBorder = Color.primary.opacity(0.13)

    private static func adaptiveColor(
        light: NSColor,
        dark: NSColor
    ) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? dark
                    : light
            }
        )
    }
}

struct BrandMark: View {
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [SlimLumaStyle.accent, SlimLumaStyle.secondaryAccent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.system(size: size * 0.44, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: SlimLumaStyle.accent.opacity(0.25), radius: 8, y: 4)
        .accessibilityHidden(true)
    }
}

struct PanelCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.035), radius: 8, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }
}

struct MetricPill: View {
    let title: String
    let value: String
    var tint: Color = SlimLumaStyle.accent

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(L10n.text(title))
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.callout)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(tint.opacity(0.09), in: Capsule())
    }
}

extension Int64 {
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

extension Double {
    var formattedDuration: String {
        if self < 1 {
            return String(
                format: L10n.text("%.1f 秒"),
                locale: .current,
                self
            )
        }
        if self < 60 {
            return String(
                format: L10n.text("%.0f 秒"),
                locale: .current,
                self
            )
        }
        return String(
            format: L10n.text("%.1f 分钟"),
            locale: .current,
            self / 60
        )
    }
}

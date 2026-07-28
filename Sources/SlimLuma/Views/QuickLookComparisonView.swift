import QuickLookUI
import SwiftUI

/// A sheet-ready side-by-side preview of the source and compressed files.
struct QuickLookComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showsMissingOutputAlert = false

    let originalURL: URL
    let outputURL: URL

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                QuickLookComparisonPane(
                    title: "原文件",
                    url: originalURL,
                    tint: .secondary
                )

                Divider()

                QuickLookComparisonPane(
                    title: "压缩后",
                    url: outputURL,
                    tint: SlimLumaStyle.secondaryAccent
                )
            }

            Divider()

            comparisonFooter
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(.bar)
        }
        .frame(minWidth: 820, minHeight: 560)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("压缩前后文件对比")
        .onExitCommand {
            dismiss()
        }
        .alert(
            "结果文件不可用",
            isPresented: $showsMissingOutputAlert
        ) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("“\(outputURL.lastPathComponent)”已被移动或删除。")
        }
    }

    private var comparisonFooter: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                fileSummary
                    .frame(
                        minWidth: 320,
                        maxWidth: .infinity,
                        alignment: .leading
                    )
                footerActions
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: 8) {
                fileSummary
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    footerActions
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
    }

    private var fileSummary: some View {
        HStack(spacing: 12) {
            Label(originalURL.lastPathComponent, systemImage: "doc")
                .lineLimit(1)
                .truncationMode(.middle)
            Image(systemName: "arrow.forward")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Label(L10n.text(outputSummary), systemImage: "arrow.down.circle.fill")
                .foregroundStyle(outputSummaryTint)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var footerActions: some View {
        HStack(spacing: 10) {
            Button("在 Finder 中显示") {
                guard outputExists else {
                    showsMissingOutputAlert = true
                    return
                }
                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
            }

            Button("关闭") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("comparison.close")
            .accessibilityHint("关闭压缩前后文件对比")
        }
    }

    private var outputExists: Bool {
        FileManager.default.fileExists(atPath: outputURL.path)
    }

    private var outputSummary: String {
        guard let originalBytes = byteCount(at: originalURL),
              let outputBytes = byteCount(at: outputURL) else {
            return outputURL.lastPathComponent
        }
        guard originalBytes > 0 else {
            return outputURL.lastPathComponent
        }
        if outputBytes < originalBytes {
            let reduction = 1 - Double(outputBytes) / Double(originalBytes)
            return "\(outputURL.lastPathComponent) · 小 \(reduction.formatted(.percent.precision(.fractionLength(0))))"
        }
        if outputBytes > originalBytes {
            let increase = Double(outputBytes) / Double(originalBytes) - 1
            return "\(outputURL.lastPathComponent) · 大 \(increase.formatted(.percent.precision(.fractionLength(0))))"
        }
        return "\(outputURL.lastPathComponent) · 大小相同"
    }

    private var outputSummaryTint: Color {
        guard let originalBytes = byteCount(at: originalURL),
              let outputBytes = byteCount(at: outputURL) else {
            return .secondary
        }
        return outputBytes < originalBytes ? SlimLumaStyle.success : SlimLumaStyle.warning
    }

    private func byteCount(at url: URL) -> Int64? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return nil
        }
        return Int64(size)
    }
}

private struct QuickLookComparisonPane: View {
    let title: String
    let url: URL
    let tint: Color

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(L10n.text(title))
                    .font(.headline)
                Text(url.lastPathComponent)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            if FileManager.default.fileExists(atPath: url.path) {
                QuickLookPreview(url: url)
                    .accessibilityLabel(
                        Text(
                            L10n.text(title)
                                + L10n.labelSeparator()
                                + url.lastPathComponent
                        )
                    )
            } else {
                ContentUnavailableView(
                    "文件不可用",
                    systemImage: "doc.badge.ellipsis",
                    description: Text("文件可能已移动或删除。")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let preview = QLPreviewView(frame: .zero, style: .normal)
        preview?.autostarts = true
        preview?.shouldCloseWithWindow = false
        preview?.previewItem = url as NSURL
        return preview ?? QLPreviewView(frame: .zero)!
    }

    func updateNSView(_ preview: QLPreviewView, context: Context) {
        let currentURL = (preview.previewItem as? NSURL) as URL?
        if currentURL?.standardizedFileURL != url.standardizedFileURL {
            preview.previewItem = url as NSURL
            preview.refreshPreviewItem()
        }
    }

    static func dismantleNSView(_ preview: QLPreviewView, coordinator: ()) {
        preview.previewItem = nil
    }
}

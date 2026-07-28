import SlimLumaKit
import SwiftUI

struct CompressorView: View {
    @EnvironmentObject private var appState: AppState
    @State private var comparison: FileComparison?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            HSplitView {
                queuePane
                    .frame(minWidth: 420, idealWidth: 570)

                CompressionSettingsView()
                    .frame(minWidth: 360, idealWidth: 430, maxWidth: 520)
            }

            Divider()
            actionBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $comparison) { comparison in
            QuickLookComparisonView(
                originalURL: comparison.originalURL,
                outputURL: comparison.outputURL
            )
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("媒体压缩")
                    .font(.title2.weight(.semibold))
                Text("图片、视频和 PDF 使用独立专业引擎处理")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !appState.queue.isEmpty {
                MetricPill(title: "文件", value: "\(appState.queue.count)")
                MetricPill(
                    title: "原始",
                    value: appState.totalOriginalBytes.formattedBytes,
                    tint: SlimLumaStyle.secondaryAccent
                )
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var queuePane: some View {
        if appState.queue.isEmpty {
            EmptyDropView()
                .padding(24)
        } else {
            VStack(spacing: 0) {
                QueueActionsBar()
                    .padding(12)

                List(selection: $appState.selectedItemID) {
                    ForEach(appState.queue) { item in
                        QueueRow(item: item) {
                            guard let outputURL = item.outputURL else { return }
                            guard appState.validateResultFile(outputURL) else {
                                return
                            }
                            comparison = FileComparison(
                                originalURL: item.inputURL,
                                outputURL: outputURL
                            )
                        }
                            .tag(item.id)
                            .contextMenu {
                                if let outputURL = item.outputURL {
                                    Button("对比压缩前后") {
                                        guard appState.validateResultFile(outputURL) else {
                                            return
                                        }
                                        comparison = FileComparison(
                                            originalURL: item.inputURL,
                                            outputURL: outputURL
                                        )
                                    }
                                    Button("在 Finder 中显示") {
                                        appState.reveal(url: outputURL)
                                    }
                                    Button("打开结果") {
                                        appState.open(url: outputURL)
                                    }
                                    Divider()
                                }
                                if item.settingsOverride == nil {
                                    Button("为此文件使用独立设置") {
                                        appState.applyCurrentSettings(
                                            to: item.id
                                        )
                                    }
                                } else {
                                    Button("用当前设置更新独立设置") {
                                        appState.applyCurrentSettings(
                                            to: item.id
                                        )
                                    }
                                    Button("恢复使用全局设置") {
                                        appState.clearSettingsOverride(
                                            for: item.id
                                        )
                                    }
                                }
                                Divider()
                                Button("移除") {
                                    appState.removeItem(id: item.id)
                                }
                                .disabled(appState.isProcessing)
                            }
                    }
                    .onDelete { offsets in
                        guard !appState.isProcessing else { return }
                        for offset in offsets.sorted(by: >) {
                            appState.removeItem(id: appState.queue[offset].id)
                        }
                    }
                }
                .listStyle(.inset)
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard !urls.isEmpty else { return false }
                appState.addURLs(urls)
                return true
            } isTargeted: { targeted in
                appState.isDropTargeted = targeted
            }
        }
    }

    private var actionBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                actionStatus
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 12)
                actionControls
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: 10) {
                actionStatus
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    actionControls
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(.bar)
    }

    @ViewBuilder
    private var actionStatus: some View {
        if appState.isProcessing {
            HStack(spacing: 8) {
                ProgressView(value: overallProgress)
                    .frame(width: 110)
                    .accessibilityLabel("批量压缩进度")
                    .accessibilityValue(
                        "\(Int((overallProgress * 100).rounded()))%"
                    )
                Text(
                    appState.isPaused
                        ? "任务已暂停"
                        : activeProgressSummary
                )
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else if finishedCount > 0 {
            BatchResultSummary(
                completed: completedCount - retainedNotSmallerCount,
                retainedNotSmaller: retainedNotSmallerCount,
                skipped: skippedCount,
                failed: failedCount
            )
        } else {
            HStack(spacing: 8) {
                Image(systemName: "shield.checkered")
                    .foregroundStyle(SlimLumaStyle.secondaryAccent)
                Text("原文件不会被覆盖")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionControls: some View {
        HStack(spacing: 10) {
            if finishedCount > 0, !appState.isProcessing {
                Button("重新处理") {
                    appState.resetFinishedItems()
                    appState.startProcessing()
                }
            }

            if appState.isProcessing {
                Button {
                    if appState.isPaused {
                        appState.resumeProcessing()
                    } else {
                        appState.pauseProcessing()
                    }
                } label: {
                    Label(
                        appState.isPaused ? "继续" : "暂停",
                        systemImage:
                            appState.isPaused
                            ? "play.fill"
                            : "pause.fill"
                    )
                }
                .buttonStyle(.bordered)

                Button("取消全部", role: .destructive) {
                    appState.cancelProcessing()
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    appState.startProcessing()
                } label: {
                    Label("开始压缩", systemImage: "play.fill")
                        .frame(minWidth: 100)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!appState.canStart)
            }
        }
    }

    private var completedCount: Int {
        appState.queue.filter { $0.status == .completed }.count
    }

    private var skippedCount: Int {
        appState.queue.filter { $0.status == .skipped }.count
    }

    private var failedCount: Int {
        appState.queue.filter {
            if case .failed = $0.status { return true }
            return false
        }.count
    }

    private var finishedCount: Int {
        completedCount + skippedCount + failedCount
    }

    private var retainedNotSmallerCount: Int {
        appState.queue.filter { item in
            guard item.status == .completed,
                  let outputBytes = item.outputBytes else {
                return false
            }
            return outputBytes >= item.originalBytes
        }.count
    }

    private var overallProgress: Double {
        guard !appState.queue.isEmpty else { return 0 }
        let total = appState.queue.reduce(0.0) { partial, item in
            switch item.status {
            case .completed, .skipped, .failed, .cancelled:
                partial + 1
            case .processing:
                partial + item.progressFraction
            case .waiting:
                partial
            }
        }
        return min(max(total / Double(appState.queue.count), 0), 1)
    }

    private var activeProgressSummary: String {
        let active = appState.queue.filter { $0.status == .processing }
        let stage = active.compactMap(\.progressStage).first
            ?? L10n.text("正在处理任务")
        let eta = active.compactMap(\.estimatedRemainingSeconds).max()
        guard let eta, eta.isFinite, eta > 1 else {
            return stage
        }
        return "\(stage) · 约 \(formattedDuration(eta))"
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let rounded = max(1, Int(seconds.rounded()))
        if rounded < 60 {
            return "\(rounded) 秒"
        }
        let minutes = rounded / 60
        let remainder = rounded % 60
        return remainder == 0
            ? "\(minutes) 分钟"
            : "\(minutes) 分 \(remainder) 秒"
    }
}

private struct EmptyDropView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                SlimLumaStyle.accent.opacity(0.16),
                                SlimLumaStyle.secondaryAccent.opacity(0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 116, height: 116)

                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [SlimLumaStyle.accent, SlimLumaStyle.secondaryAccent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 7) {
                Text("把文件拖到这里")
                    .font(.title2.weight(.semibold))
                Text("支持常见图片、视频和 PDF，也可以拖入整个文件夹")
                    .foregroundStyle(.secondary)
            }

            importActions

            if appState.isImportingClipboard {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("正在导入剪贴板")
                    Text(
                        L10n.text(
                            appState.isCancellingClipboardImport
                                ? "正在取消剪贴板导入…"
                                : "正在复制剪贴板文件…"
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Button("取消") {
                        appState.cancelClipboardImport()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(appState.isCancellingClipboardImport)
                }
            }

            if appState.isDiscoveringFiles {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("正在扫描文件")
                    Text("正在扫描文件…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("取消") {
                        appState.cancelFileDiscovery()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            HStack(spacing: 18) {
                Label("JPEG · PNG · WebP · AVIF", systemImage: "photo")
                Label("MP4 · MOV · MKV", systemImage: "film")
                Label("PDF", systemImage: "doc.richtext")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    appState.isDropTargeted
                        ? SlimLumaStyle.accent.opacity(0.10)
                        : Color(nsColor: .controlBackgroundColor)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    appState.isDropTargeted
                        ? SlimLumaStyle.accent
                        : Color.primary.opacity(0.12),
                    style: StrokeStyle(lineWidth: 2, dash: [9, 7])
                )
        )
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            appState.addURLs(urls)
            return true
        } isTargeted: { targeted in
            appState.isDropTargeted = targeted
        }
    }

    private var importActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                chooseFilesButton
                scanFolderButton
                importClipboardButton
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(spacing: 8) {
                chooseFilesButton
                scanFolderButton
                importClipboardButton
            }
        }
    }

    private var chooseFilesButton: some View {
        Button {
            appState.chooseFiles()
        } label: {
            Label("选择文件", systemImage: "plus")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background(
                    RoundedRectangle(
                        cornerRadius: 8,
                        style: .continuous
                    )
                    .fill(SlimLumaStyle.accent)
                )
        }
        .buttonStyle(.plain)
        .help("选择一个或多个图片、视频或 PDF")
    }

    private var scanFolderButton: some View {
        Button("扫描文件夹") { appState.chooseFolder() }
            .buttonStyle(.bordered)
            .controlSize(.large)
    }

    private var importClipboardButton: some View {
        Button("导入剪贴板") { appState.importFromClipboard() }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(appState.isImportingClipboard)
    }
}

private struct QueueActionsBar: View {
    @EnvironmentObject private var appState: AppState
    @State private var confirmsClearQueue = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                queueIdentity
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                HStack(spacing: 10) {
                    activityControls
                    queueManagementControls
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: 10) {
                queueIdentity
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        activityControls
                            .fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 8)
                        queueManagementControls
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        activityControls
                        queueManagementControls
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(
                    appState.isDropTargeted
                        ? SlimLumaStyle.accent.opacity(0.13)
                        : SlimLumaStyle.interactiveSurface
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(
                    appState.isDropTargeted
                        ? SlimLumaStyle.accent
                        : SlimLumaStyle.controlBorder
                )
        )
        .confirmationDialog(
            "清空当前队列？",
            isPresented: $confirmsClearQueue
        ) {
            Button("清空队列", role: .destructive) {
                appState.clearQueue()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会移除队列项目并停止当前导入或扫描，不会删除原文件或已生成结果。")
        }
    }

    private var queueIdentity: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.full")
                .foregroundStyle(SlimLumaStyle.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(
                    L10n.text(
                        appState.isDropTargeted ? "松开即可加入队列" : "文件队列"
                    )
                )
                .font(.callout)
                .fontWeight(.medium)
                Text("\(appState.queue.count) 个文件，可继续拖入")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var activityControls: some View {
        HStack(spacing: 8) {
            if appState.isImportingClipboard {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在导入剪贴板")
                Button(
                    L10n.text(
                        appState.isCancellingClipboardImport
                            ? "正在取消…"
                            : "取消导入"
                    )
                ) {
                    appState.cancelClipboardImport()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(appState.isCancellingClipboardImport)
            }

            if appState.isDiscoveringFiles {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在扫描文件")
                Button("取消扫描") {
                    appState.cancelFileDiscovery()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var queueManagementControls: some View {
        HStack(spacing: 10) {
            Menu {
                Button("选择文件…") {
                    appState.chooseFiles()
                }
                Button("扫描文件夹…") {
                    appState.chooseFolder()
                }
                Divider()
                Button("导入剪贴板") {
                    appState.importFromClipboard()
                }
                .disabled(appState.isImportingClipboard)
            } label: {
                Label("添加…", systemImage: "plus")
            }
            .menuStyle(.button)
            .controlSize(.regular)
            .help("向当前压缩队列添加文件或文件夹")

            Button {
                confirmsClearQueue = true
            } label: {
                Label("清空队列", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(appState.isProcessing)
            .help("移除当前压缩队列中的全部文件")
        }
    }
}

private struct QueueRow: View {
    let item: CompressionQueueItem
    let onCompare: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(kindTint.opacity(0.12))
                Image(systemName: item.mediaKind.symbolName)
                    .foregroundStyle(kindTint)
                    .font(.system(size: 17, weight: .medium))
            }
            .frame(width: 38, height: 38)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.inputURL.lastPathComponent)
                    .lineLimit(1)
                    .fontWeight(.medium)

                HStack(spacing: 6) {
                    Text(L10n.text(item.mediaKind.displayName))
                    Text("·")
                        .accessibilityHidden(true)
                    Text(item.originalBytes.formattedBytes)
                    if let outputBytes = item.outputBytes {
                        Image(systemName: "arrow.forward")
                            .accessibilityHidden(true)
                        Text(outputBytes.formattedBytes)
                            .foregroundStyle(outputSizeTint)
                    }
                    if item.settingsOverride != nil {
                        Label("独立设置", systemImage: "slider.horizontal.3")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(SlimLumaStyle.accent)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let engineName = item.engineName {
                    Text("使用 \(engineName)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if item.status == .processing,
                   let progressStage = item.progressStage {
                    HStack(spacing: 6) {
                        Text(L10n.text(progressStage))
                        Text(
                            "\(Int((item.progressFraction * 100).rounded()))%"
                        )
                        .monospacedDigit()
                        if let eta = item.estimatedRemainingSeconds,
                           eta.isFinite,
                           eta > 1 {
                            Text("·")
                            Text("约 \(shortDuration(eta))")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                if let detailMessage = item.detailMessage {
                    Text(L10n.text(detailMessage))
                        .font(.caption2)
                        .foregroundStyle(detailColor)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            if item.outputURL != nil, outputExists {
                Button(action: onCompare) {
                    Image(systemName: "rectangle.split.2x1")
                }
                .buttonStyle(.borderless)
                .help("对比压缩前后")
                .accessibilityLabel(
                    Text(
                        L10n.text(
                            "对比 \(item.inputURL.lastPathComponent) 压缩前后"
                        )
                    )
                )
                .accessibilityHint("打开原文件与压缩结果的并排预览")
            } else if item.outputURL != nil {
                Label("结果不可用", systemImage: "doc.badge.ellipsis")
                    .font(.caption)
                    .foregroundStyle(SlimLumaStyle.warning)
            }

            status
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private var status: some View {
        switch item.status {
        case .processing:
            ProgressView(value: item.progressFraction)
                .frame(width: 44)
                .controlSize(.small)
                .accessibilityLabel(
                    Text(
                        L10n.text(
                            "\(item.inputURL.lastPathComponent) 正在压缩"
                        )
                    )
                )
        default:
            HStack(spacing: 5) {
                Image(systemName: item.status.symbolName)
                    .accessibilityHidden(true)
                Text(L10n.text(item.status.displayName))
                    .font(.caption)
            }
            .foregroundStyle(statusTint)
            .help(L10n.text(item.status.displayName))
        }
    }

    private var kindTint: Color {
        switch item.mediaKind {
        case .image: SlimLumaStyle.accent
        case .video: Color.pink
        case .pdf: Color.orange
        case .unknown: Color.gray
        }
    }

    private func shortDuration(_ seconds: TimeInterval) -> String {
        let rounded = max(1, Int(seconds.rounded()))
        if rounded < 60 {
            return "\(rounded) 秒"
        }
        return "\(rounded / 60) 分钟"
    }

    private var statusTint: Color {
        switch item.status {
        case .completed: SlimLumaStyle.success
        case .skipped: SlimLumaStyle.warning
        case .failed: Color.red
        case .cancelled: Color.secondary
        default: Color.secondary
        }
    }

    private var detailColor: Color {
        switch item.status {
        case .failed:
            .red
        case .skipped, .completed:
            SlimLumaStyle.warning
        default:
            .secondary
        }
    }

    private var outputSizeTint: Color {
        guard let outputBytes = item.outputBytes else {
            return .secondary
        }
        return outputBytes < item.originalBytes
            ? SlimLumaStyle.success
            : SlimLumaStyle.warning
    }

    private var outputExists: Bool {
        guard let outputURL = item.outputURL else { return false }
        return FileManager.default.fileExists(atPath: outputURL.path)
    }
}

private struct FileComparison: Identifiable {
    let id = UUID()
    let originalURL: URL
    let outputURL: URL
}

private struct BatchResultSummary: View {
    let completed: Int
    let retainedNotSmaller: Int
    let skipped: Int
    let failed: Int

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                summaryLabels
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: 6) {
                summaryLabels
            }
        }
        .font(.callout.weight(.medium))
    }

    @ViewBuilder
    private var summaryLabels: some View {
        if completed > 0 {
            Label("\(completed) 个已生成", systemImage: "checkmark.circle.fill")
                .foregroundStyle(SlimLumaStyle.success)
        }
        if retainedNotSmaller > 0 {
            Label(
                "\(retainedNotSmaller) 个未变小但已保留",
                systemImage: "arrow.up.right.circle.fill"
            )
            .foregroundStyle(SlimLumaStyle.warning)
        }
        if skipped > 0 {
            Label("\(skipped) 个未生成", systemImage: "equal.circle.fill")
                .foregroundStyle(SlimLumaStyle.warning)
        }
        if failed > 0 {
            Label("\(failed) 个失败", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }
}

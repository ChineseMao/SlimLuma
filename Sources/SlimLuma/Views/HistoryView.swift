import SlimLumaKit
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var confirmsClear = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if appState.history.isEmpty {
                ContentUnavailableView {
                    Label("还没有压缩记录", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("完成的任务会记录引擎、体积变化和输出位置")
                } actions: {
                    Button("开始添加文件") {
                        appState.section = .compress
                        appState.chooseFiles()
                    }
                }
            } else {
                List {
                    ForEach(groupedDates, id: \.date) { group in
                        Section(group.title) {
                            ForEach(group.entries) { entry in
                                HistoryRow(entry: entry)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog(
            "清空所有历史记录？",
            isPresented: $confirmsClear
        ) {
            Button("清空历史", role: .destructive) {
                appState.clearHistory()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只会删除记录，不会删除已生成的文件。")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("历史记录")
                    .font(.title2.weight(.semibold))
                Text("最多保留最近 500 条，本地存储")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !appState.history.isEmpty {
                MetricPill(
                    title: "累计节省",
                    value: totalSaved.formattedBytes,
                    tint: SlimLumaStyle.success
                )
                Button("清空") {
                    confirmsClear = true
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var totalSaved: Int64 {
        appState.history.reduce(0) { $0 + $1.savedBytes }
    }

    private var groupedDates: [HistoryDateGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: appState.history) {
            calendar.startOfDay(for: $0.completedAt)
        }
        return grouped
            .map { date, entries in
                HistoryDateGroup(
                    date: date,
                    title: date.formatted(
                        .dateTime.year().month(.wide).day()
                    ),
                    entries: entries.sorted { $0.completedAt > $1.completedAt }
                )
            }
            .sorted { $0.date > $1.date }
    }
}

private struct HistoryDateGroup {
    let date: Date
    let title: String
    let entries: [HistoryEntry]
}

private struct HistoryRow: View {
    @EnvironmentObject private var appState: AppState
    @State private var showsComparison = false
    let entry: HistoryEntry

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(SlimLumaStyle.accent.opacity(0.10))
                Image(systemName: entry.mediaKind.symbolName)
                    .foregroundStyle(SlimLumaStyle.accent)
            }
            .frame(width: 38, height: 38)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.inputURL.lastPathComponent)
                    .fontWeight(.medium)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(entry.completedAt.formatted(date: .omitted, time: .shortened))
                    Text("·")
                        .accessibilityHidden(true)
                    Text(L10n.text(entry.engineName))
                    if entry.failureMessage == nil {
                        Text("·")
                            .accessibilityHidden(true)
                        Text(entry.duration.formattedDuration)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let detailMessage = entry.failureMessage ?? entry.warning {
                    Text(L10n.text(detailMessage))
                        .font(.caption2)
                        .foregroundStyle(entry.failureMessage == nil
                                         ? SlimLumaStyle.warning
                                         : Color.red)
                        .lineLimit(2)
                }

                if entry.outputURL != nil, !outputExists {
                    Label(
                        "结果已移动或删除",
                        systemImage: "doc.badge.ellipsis"
                    )
                    .font(.caption2)
                    .foregroundStyle(SlimLumaStyle.warning)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                if entry.failureMessage != nil {
                    Text("失败")
                        .foregroundStyle(.red)
                } else if entry.wasSkipped {
                    Text("未生成")
                        .foregroundStyle(SlimLumaStyle.warning)
                } else if let sizeDelta = entry.sizeDeltaBytes,
                          sizeDelta > 0 {
                    Text("增大 \(sizeDelta.formattedBytes)")
                        .foregroundStyle(SlimLumaStyle.warning)
                } else if entry.sizeDeltaBytes == 0 {
                    Text("大小不变")
                        .foregroundStyle(SlimLumaStyle.warning)
                } else {
                    Text("节省 \(entry.savedBytes.formattedBytes)")
                        .foregroundStyle(SlimLumaStyle.success)
                }
                Text(entry.originalBytes.formattedBytes)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .font(.callout.weight(.medium))

            Menu {
                if let outputURL = entry.outputURL {
                    Button("对比压缩前后") {
                        guard appState.validateResultFile(outputURL) else {
                            return
                        }
                        showsComparison = true
                    }
                    Button("打开结果") { appState.open(url: outputURL) }
                    Button("在 Finder 中显示") { appState.reveal(url: outputURL) }
                    Button("复制路径") { appState.copyToPasteboard(outputURL.path) }
                    Divider()
                }

                Button("重新加入压缩队列") {
                    appState.requeueOriginal(url: entry.inputURL)
                }
                Button("在 Finder 中显示原文件") {
                    appState.revealOriginal(url: entry.inputURL)
                }
                Button("复制原文件路径") {
                    appState.copyToPasteboard(entry.inputURL.path)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 32, height: 32)
            .accessibilityLabel(
                Text(
                    L10n.text(
                        "\(entry.inputURL.lastPathComponent) 的更多操作"
                    )
                )
            )
            .accessibilityHint("重新加入队列，或打开结果和 Finder 操作")
        }
        .padding(.vertical, 5)
        .sheet(isPresented: $showsComparison) {
            if let outputURL = entry.outputURL {
                QuickLookComparisonView(
                    originalURL: entry.inputURL,
                    outputURL: outputURL
                )
            }
        }
    }

    private var outputExists: Bool {
        guard let outputURL = entry.outputURL else { return false }
        return FileManager.default.fileExists(atPath: outputURL.path)
    }
}

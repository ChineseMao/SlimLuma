import AppKit
import SwiftUI

struct AutomationsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                pageHeader
                clipboardCard
                folderWatchCard
                finderCard
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var pageHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("自动化")
                    .font(.title2.weight(.semibold))
                Text("从剪贴板、监控文件夹和 Finder 直接进入压缩队列")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if appState.isFolderWatching {
                MetricPill(
                    title: "文件夹监控",
                    value: folderWatchStatus.value,
                    tint: folderWatchStatus.tint
                )
            }
        }
    }

    private var folderWatchStatus: (value: String, tint: Color) {
        guard !appState.folderWatchIssues.isEmpty else {
            return ("运行中", SlimLumaStyle.success)
        }
        if appState.folderWatchIssues.count
            >= appState.automationSettings.watchedFolderPaths.count {
            return ("需要处理", SlimLumaStyle.warning)
        }
        return ("部分失效", SlimLumaStyle.warning)
    }

    private var clipboardCard: some View {
        PanelCard {
            HStack(alignment: .top, spacing: 16) {
                featureIcon("doc.on.clipboard", tint: SlimLumaStyle.accent)

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("剪贴板导入")
                            .font(.headline)
                        Text("支持 Finder 复制的文件，以及其他 app 复制的 PNG / TIFF 图片。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Toggle(
                        "导入后自动开始压缩",
                        isOn: $appState.automationSettings
                            .autoStartsClipboardCompression
                    )

                    Button {
                        if appState.isImportingClipboard {
                            appState.cancelClipboardImport()
                        } else {
                            appState.importFromClipboard()
                        }
                    } label: {
                        if appState.isImportingClipboard {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(
                                    L10n.text(
                                        appState.isCancellingClipboardImport
                                            ? "正在取消…"
                                            : "取消导入"
                                    )
                                )
                            }
                        } else {
                            Label("导入当前剪贴板", systemImage: "plus.square.on.square")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.isCancellingClipboardImport)
                }

                Spacer()
            }
        }
    }

    private var folderWatchCard: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .top, spacing: 16) {
                    featureIcon(
                        "folder.badge.gearshape",
                        tint: SlimLumaStyle.secondaryAccent
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("文件夹监控")
                            .font(.headline)
                        Text("新文件连续两次检测稳定后才加入队列，避免读取仍在复制的大文件。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle(
                        "启用",
                        isOn: Binding(
                            get: { appState.automationSettings.folderWatchEnabled },
                            set: { appState.setFolderWatchEnabled($0) }
                        )
                    )
                    .toggleStyle(.switch)
                }

                Divider()

                if appState.automationSettings.watchedFolderPaths.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.badge.plus")
                            .foregroundStyle(SlimLumaStyle.secondaryAccent)
                        Text("还没有监控文件夹")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("添加文件夹…") {
                            appState.chooseWatchFolders()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                } else {
                    VStack(spacing: 8) {
                        ForEach(
                            appState.automationSettings.watchedFolderPaths,
                            id: \.self
                        ) { path in
                            watchedFolderRow(path)
                        }
                    }

                    HStack {
                        Button {
                            appState.chooseWatchFolders()
                        } label: {
                            Label("添加文件夹…", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Toggle(
                        "包含子文件夹",
                        isOn: watchOptionBinding(
                            \.scansSubdirectories
                        )
                    )
                    Toggle(
                        "启动监控时导入已有文件",
                        isOn: watchOptionBinding(
                            \.importsExistingFiles
                        )
                    )
                    Toggle(
                        "发现新文件后自动开始压缩",
                        isOn: watchOptionBinding(
                            \.autoStartsFolderCompression,
                            restartsWatcher: false
                        )
                    )
                }

                if !appState.folderWatchIssues.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(appState.folderWatchIssues) { issue in
                            Label {
                                Text(
                                    verbatim:
                                        issue.folder.lastPathComponent
                                        + L10n.labelSeparator()
                                        + L10n.text(issue.message)
                                )
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                            }
                                .font(.caption)
                                .foregroundStyle(SlimLumaStyle.warning)
                        }
                    }
                }
            }
        }
    }

    private var finderCard: some View {
        PanelCard {
            HStack(alignment: .top, spacing: 16) {
                featureIcon("finder", tint: Color.blue)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Finder 与快捷指令")
                        .font(.headline)
                    Text("在 Finder 选中文件后，可直接用“打开方式 → SlimLuma”发送到压缩队列。"
                        + "macOS 15 及以上还会在快捷指令中提供"
                        + "“添加到 SlimLuma 压缩队列”原生动作。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("若想使用“服务 → 添加到 SlimLuma 压缩队列”，"
                        + "请先在“系统设置 → 键盘 → 键盘快捷键 → 服务”中启用一次。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        openServicesSettings()
                    } label: {
                        Label("打开服务设置…", systemImage: "gearshape")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("打开系统设置中的键盘设置，以启用 SlimLuma Finder 服务")
                }

                Spacer()
            }
        }
    }

    private func watchedFolderRow(_ path: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .foregroundStyle(SlimLumaStyle.secondaryAccent)
            Text(path)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                appState.removeWatchFolder(path: path)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("停止监控此文件夹")
            .accessibilityLabel(
                Text(
                    L10n.text(
                        "停止监控 \(URL(fileURLWithPath: path).lastPathComponent)"
                    )
                )
            )
            .accessibilityHint("从自动监控列表移除此文件夹")
            .frame(width: 32, height: 32)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            SlimLumaStyle.interactiveSurface,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(SlimLumaStyle.controlBorder)
        )
    }

    private func watchOptionBinding(
        _ keyPath: WritableKeyPath<AutomationSettings, Bool>,
        restartsWatcher: Bool = true
    ) -> Binding<Bool> {
        Binding(
            get: { appState.automationSettings[keyPath: keyPath] },
            set: { value in
                appState.automationSettings[keyPath: keyPath] = value
                if restartsWatcher {
                    appState.updateFolderWatchOptions()
                }
            }
        )
    }

    private func featureIcon(_ symbol: String, tint: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.12))
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
        }
        .frame(width: 48, height: 48)
    }

    private func openServicesSettings() {
        let settingsURLs = [
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.keyboard"
        ]

        for rawURL in settingsURLs {
            guard let url = URL(string: rawURL) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }

        appState.notice = AppNotice(
            title: "无法打开系统设置",
            message: "请手动打开“系统设置 → 键盘 → 键盘快捷键 → 服务”，"
                + "然后启用“添加到 SlimLuma 压缩队列”。",
            recovery: .dismiss
        )
    }
}

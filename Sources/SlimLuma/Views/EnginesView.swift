import SlimLumaKit
import SwiftUI

struct EnginesView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("引擎与设置")
                            .font(.title2.weight(.semibold))
                        Text("一次补齐专业引擎，之后由 SlimLuma 自动选择")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        appState.refreshTools()
                    } label: {
                        Label("重新检测", systemImage: "arrow.clockwise")
                    }
                }

                engineOverview
                installationStatus

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(appState.toolAvailability.filter { $0.kind != .sips }) { tool in
                        ToolRow(tool: tool)
                    }
                }

                PanelCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("并行与资源", systemImage: "cpu")
                            .font(.headline)
                            .foregroundStyle(SlimLumaStyle.accent)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("同时处理任务")
                                Text("视频和 AVIF 较耗资源，16 GB 内存建议 1–2 个")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Stepper(
                                "\(appState.settings.maxConcurrentJobs) 个",
                                value: $appState.settings.maxConcurrentJobs,
                                in: 1...6
                            )
                            .frame(width: 110)
                            .disabled(appState.isProcessing)
                            .accessibilityLabel("同时处理任务")
                            .accessibilityValue(
                                "\(appState.settings.maxConcurrentJobs) 个"
                            )
                        }
                    }
                }

                PanelCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("许可说明", systemImage: "checkmark.seal")
                            .font(.headline)
                            .foregroundStyle(SlimLumaStyle.accent)
                        Text("ImageMagick 采用宽松许可；qpdf 是 Apache‑2.0；FFmpeg 的具体许可取决于构建参数。Ghostscript 为 AGPL/商业双许可。SlimLuma 不捆绑这些二进制；只有你点击安装时，才会通过 Homebrew 独立安装。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) {
                                licenseLinks
                            }
                            .fixedSize(horizontal: true, vertical: false)

                            VStack(alignment: .leading, spacing: 6) {
                                licenseLinks
                            }
                        }
                        .font(.caption)
                    }
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            appState.refreshTools()
        }
    }

    @ViewBuilder
    private var licenseLinks: some View {
        Link(
            "ImageMagick 许可",
            destination: URL(string: "https://imagemagick.org/license/")!
        )
        Link(
            "FFmpeg 许可",
            destination: URL(
                string: "https://github.com/FFmpeg/FFmpeg/blob/master/LICENSE.md"
            )!
        )
        Link(
            "qpdf 文档",
            destination: URL(string: "https://qpdf.readthedocs.io/")!
        )
        Link(
            "Ghostscript 许可",
            destination: URL(string: "https://ghostscript.com/licensing/")!
        )
    }

    private var engineOverview: some View {
        PanelCard {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(overviewTint.opacity(0.12))
                    Image(systemName: appState.missingRecommendedTools.isEmpty
                          ? "checkmark.seal.fill"
                          : "shippingbox.and.arrow.backward.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(overviewTint)
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        L10n.text(
                            appState.missingRecommendedTools.isEmpty
                                ? "专业引擎已就绪"
                                : "还有 \(appState.missingRecommendedTools.count) 个引擎可补齐"
                        )
                    )
                        .font(.headline)
                    Text(
                        L10n.text(
                            appState.missingRecommendedTools.isEmpty
                                ? "图片、视频与 PDF 都会使用对应的专业处理链"
                                : "建议一次安装，尤其是 Ghostscript：图片型 PDF 的体积下降主要依赖它"
                        )
                    )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                if !appState.missingRecommendedTools.isEmpty {
                    Button {
                        appState.installRecommendedTools()
                    } label: {
                        Label(
                            ToolRegistry().homebrewURL() == nil
                                ? "安装 Homebrew 与推荐引擎"
                                : "一键补齐推荐引擎",
                            systemImage: "arrow.down.circle.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(
                        appState.engineInstallation.isInstalling
                            || appState.engineInstallation.isAwaitingHomebrew
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var installationStatus: some View {
        switch appState.engineInstallation {
        case .idle:
            EmptyView()
        case .awaitingHomebrew(let toolNames):
            PanelCard {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("正在等待 Homebrew 安装完成")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("等待 Homebrew，检测到后自动继续")
                            .fontWeight(.semibold)
                        Text(L10n.list(toolNames))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("再次打开官网") {
                        appState.openHomebrewWebsite()
                    }
                    Button("取消") {
                        appState.cancelEngineInstallation()
                    }
                }
            }
        case .installing(let toolNames):
            PanelCard {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("正在安装压缩引擎")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("正在通过 Homebrew 安装")
                            .fontWeight(.semibold)
                        Text(L10n.list(toolNames))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("取消") {
                        appState.cancelEngineInstallation()
                    }
                }
            }
        case .succeeded(let message, let log):
            InstallationResultCard(
                title: message,
                log: log,
                color: SlimLumaStyle.success,
                symbol: "checkmark.circle.fill"
            )
        case .failed(let message, let log):
            InstallationResultCard(
                title: message,
                log: log,
                color: .red,
                symbol: "exclamationmark.triangle.fill"
            )
        }
    }

    private var overviewTint: Color {
        appState.missingRecommendedTools.isEmpty
            ? SlimLumaStyle.success
            : SlimLumaStyle.accent
    }
}

private struct ToolRow: View {
    @EnvironmentObject private var appState: AppState
    let tool: ToolAvailability

    var body: some View {
        PanelCard {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(statusColor.opacity(0.11))
                    Image(systemName: tool.isAvailable ? "checkmark.circle.fill" : "wrench.and.screwdriver")
                        .font(.title2)
                        .foregroundStyle(statusColor)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(L10n.text(tool.kind.displayName))
                            .font(.headline)
                        Text(
                            L10n.text(
                                tool.isAvailable
                                    ? "可用"
                                    : tool.missingCompanionExecutableName == nil
                                        ? "未安装"
                                        : "部分失效"
                            )
                        )
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(statusColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(statusColor.opacity(0.10), in: Capsule())
                    }
                    Text(L10n.text(tool.kind.purpose))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if tool.missingCompanionExecutableName != nil {
                        Text(L10n.text("缺少 ffprobe"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(SlimLumaStyle.warning)
                    }
                    if let path = tool.executableURL?.path {
                        Text(path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer()

                if !tool.isAvailable {
                    HStack(spacing: 8) {
                        Button {
                            appState.installTool(tool.kind)
                        } label: {
                            Label("安装", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.bordered)
                        .disabled(
                            appState.engineInstallation.isInstalling
                                || appState.engineInstallation.isAwaitingHomebrew
                        )

                        Menu {
                            Button("复制安装命令") {
                                appState.copyToPasteboard(tool.recoveryCommand)
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 32, height: 32)
                        .accessibilityLabel(
                            Text(
                                L10n.text(
                                    "\(tool.kind.displayName) 的更多操作"
                                )
                            )
                        )
                    }
                }
            }
        }
    }

    private var statusColor: Color {
        tool.isAvailable ? SlimLumaStyle.success : SlimLumaStyle.warning
    }
}

private struct InstallationResultCard: View {
    let title: String
    let log: String
    let color: Color
    let symbol: String

    var body: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(L10n.text(title), systemImage: symbol)
                    .font(.headline)
                    .foregroundStyle(color)
                if !log.isEmpty {
                    DisclosureGroup("查看安装日志") {
                        ScrollView(.horizontal) {
                            Text(log)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 6)
                        }
                        .frame(maxHeight: 160)
                    }
                    .font(.callout)
                }
            }
        }
    }
}

struct PreferencesView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            Form {
                if appState.isProcessing {
                    Label(
                        "当前批次已锁定任务设置",
                        systemImage: "lock.fill"
                    )
                    .foregroundStyle(.secondary)
                }

                Section("任务") {
                    Stepper(
                        "同时处理 \(appState.settings.maxConcurrentJobs) 个任务",
                        value: $appState.settings.maxConcurrentJobs,
                        in: 1...6
                    )
                    Toggle(
                        "保留没有变小的结果",
                        isOn: $appState.settings.output.keepLargerFiles
                    )
                    Toggle(
                        "保留原修改时间",
                        isOn: $appState.settings.output.preserveModificationDate
                    )
                }
                .disabled(appState.isProcessing)

                Section("安全") {
                    Label("默认生成新文件，不覆盖原文件", systemImage: "checkmark.shield")
                    Label("所有处理均在本机完成", systemImage: "lock")
                }
            }
            .formStyle(.grouped)
            .padding()
            .tabItem {
                Label("通用", systemImage: "gearshape")
            }

            VStack(spacing: 12) {
                ForEach(appState.toolAvailability.filter { $0.kind != .sips }) { tool in
                    HStack {
                        Image(systemName: tool.isAvailable ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(tool.isAvailable ? SlimLumaStyle.success : SlimLumaStyle.warning)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading) {
                            Text(L10n.text(tool.kind.displayName))
                            Text(tool.executableURL?.path ?? tool.kind.installCommand)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        Text(preferencesAccessibilityLabel(for: tool))
                    )
                }
                Spacer()
                Button("重新检测") { appState.refreshTools() }
            }
            .padding(24)
            .tabItem {
                Label("压缩引擎", systemImage: "gearshape.2")
            }
        }
    }

    private func preferencesAccessibilityLabel(
        for tool: ToolAvailability
    ) -> String {
        let status: String
        if tool.isAvailable {
            status = L10n.text("可用")
        } else if let companion = tool.missingCompanionExecutableName {
            status = L10n.text("部分失效")
                + L10n.labelSeparator()
                + L10n.text("缺少 \(companion)")
        } else {
            status = L10n.text("未安装")
        }

        let location = tool.executableURL?.path ?? tool.recoveryCommand
        return L10n.text(tool.kind.displayName)
            + L10n.labelSeparator()
            + status
            + L10n.labelSeparator()
            + location
    }
}

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            sidebar
                .environment(
                    \.layoutDirection,
                    contentLayoutDirection
                )
        } detail: {
            detail
                .environment(
                    \.layoutDirection,
                    contentLayoutDirection
                )
        }
        .navigationSplitViewStyle(.balanced)
        .tint(SlimLumaStyle.accent)
        .alert(item: $appState.notice) { notice in
            switch notice.recovery {
            case .dismiss:
                Alert(
                    title: Text(L10n.text(notice.title)),
                    message: Text(L10n.text(notice.message)),
                    dismissButton: .default(Text("知道了"))
                )
            case .openEngines:
                Alert(
                    title: Text(L10n.text(notice.title)),
                    message: Text(L10n.text(notice.message)),
                    primaryButton: .default(Text("查看引擎")) {
                        appState.section = .engines
                    },
                    secondaryButton: .cancel(Text("稍后"))
                )
            case .openHomebrew:
                Alert(
                    title: Text(L10n.text(notice.title)),
                    message: Text(L10n.text(notice.message)),
                    primaryButton: .default(Text("打开 brew.sh")) {
                        appState.openHomebrewWebsite()
                    },
                    secondaryButton: .cancel(Text("稍后"))
                )
            case .install(let tool):
                Alert(
                    title: Text(L10n.text(notice.title)),
                    message: Text(L10n.text(notice.message)),
                    primaryButton: .default(Text("一键安装")) {
                        appState.section = .engines
                        appState.installTool(tool)
                    },
                    secondaryButton: .cancel(Text("稍后"))
                )
            }
        }
        .overlay(alignment: .bottom) {
            if let message = appState.transientStatusMessage {
                Label(L10n.text(message), systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.primary.opacity(0.10))
                    )
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
                    .padding(.bottom, 22)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(
            .easeInOut(duration: 0.18),
            value: appState.transientStatusMessage
        )
    }

    private var contentLayoutDirection: LayoutDirection {
        L10n.usesRightToLeftLayout ? .rightToLeft : .leftToRight
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                BrandMark(size: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text("SlimLuma")
                        .font(.headline)
                    Text("本地媒体瘦身工具")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)

            List(selection: $appState.section) {
                Section("工作区") {
                    sidebarItem(.compress, badge: appState.queue.isEmpty ? nil : "\(appState.queue.count)")
                    sidebarItem(.automations)
                    sidebarItem(.presets)
                    sidebarItem(.history, badge: appState.history.isEmpty ? nil : "\(appState.history.count)")
                }

                Section("系统") {
                    sidebarItem(.engines)
                }

                Section("了解") {
                    sidebarItem(.principles)
                }
            }
            .listStyle(.sidebar)

            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(SlimLumaStyle.success)
                VStack(alignment: .leading, spacing: 1) {
                    Text("100% 本地处理")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("文件不会上传")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
    }

    @ViewBuilder
    private func sidebarItem(_ section: AppSection, badge: String? = nil) -> some View {
        Label {
            HStack {
                Text(L10n.text(section.title))
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
        } icon: {
            Image(systemName: section.symbolName)
        }
        .tag(section)
    }

    @ViewBuilder
    private var detail: some View {
        switch appState.section {
        case .compress:
            CompressorView()
        case .automations:
            AutomationsView()
        case .presets:
            PresetsView()
        case .history:
            HistoryView()
        case .principles:
            PrinciplesView()
        case .engines:
            EnginesView()
        }
    }
}

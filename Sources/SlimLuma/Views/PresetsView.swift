import SlimLumaKit
import SwiftUI

struct PresetsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var presetName = ""

    private let columns = [
        GridItem(.adaptive(minimum: 250, maximum: 360), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                pageHeader

                if appState.isProcessing {
                    Label(
                        "当前批次已锁定设置；完成或取消后可保存、应用预设",
                        systemImage: "lock.fill"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }

                PanelCard {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.square.dashed")
                            .font(.title2)
                            .foregroundStyle(SlimLumaStyle.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("保存当前设置")
                                .fontWeight(.semibold)
                            Text("把当前压缩参数保存为可重复使用的预设")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        TextField("预设名称", text: $presetName)
                            .frame(width: 180)
                            .onSubmit(savePreset)
                        Button("保存") {
                            savePreset()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            appState.isProcessing
                                || presetName
                                    .trimmingCharacters(in: .whitespaces)
                                    .isEmpty
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("内置预设")
                        .font(.headline)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        ForEach(CompressionPreset.builtIns) { preset in
                            PresetCard(preset: preset)
                        }
                    }
                }

                if !appState.customPresets.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("我的预设")
                            .font(.headline)
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                            ForEach(appState.customPresets) { preset in
                                PresetCard(preset: preset)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var pageHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("压缩预设")
                    .font(.title2.weight(.semibold))
                Text("一键切换常见场景，也可以导入、导出自己的组合")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                appState.importPresets()
            } label: {
                Label("导入预设…", systemImage: "square.and.arrow.down")
            }
            .disabled(appState.isProcessing)

            if !appState.customPresets.isEmpty {
                Button {
                    appState.exportAllCustomPresets()
                } label: {
                    Label("导出全部…", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private func savePreset() {
        guard !appState.isProcessing else { return }
        appState.saveCurrentPreset(named: presetName)
        presetName = ""
    }
}

private struct PresetCard: View {
    @EnvironmentObject private var appState: AppState
    @State private var confirmsDelete = false
    let preset: CompressionPreset

    var body: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(SlimLumaStyle.accent.opacity(0.11))
                        Image(systemName: preset.symbolName)
                            .foregroundStyle(SlimLumaStyle.accent)
                            .font(.title3)
                    }
                    .frame(width: 42, height: 42)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(preset.isBuiltIn ? L10n.text(preset.name) : preset.name)
                            .font(.headline)
                        Text(L10n.text(preset.isBuiltIn ? "内置" : "自定义"))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }

                Text(
                    preset.isBuiltIn || preset.summary == "自定义参数"
                        ? L10n.text(preset.summary)
                        : preset.summary
                )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    SettingChip(preset.settings.image.format.displayName)
                    SettingChip(preset.settings.video.codec.rawValue.uppercased())
                    SettingChip(preset.settings.pdf.mode.displayName)
                }

                HStack {
                    Button("应用预设") {
                        appState.applyPreset(preset)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.isProcessing)
                    .help(
                        L10n.text(
                            appState.isProcessing
                                ? "当前批次完成或取消后可应用预设"
                                : "应用这组压缩设置"
                        )
                    )

                    Spacer()

                    Button {
                        appState.exportPreset(preset)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderless)
                    .help("导出预设")
                    .accessibilityLabel(
                        Text(L10n.text("导出 \(preset.name)"))
                    )

                    if !preset.isBuiltIn {
                        Button(role: .destructive) {
                            confirmsDelete = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("删除自定义预设")
                        .accessibilityLabel(
                            Text(L10n.text("删除 \(preset.name)"))
                        )
                    }
                }
            }
        }
        .confirmationDialog(
            "删除“\(preset.name)”？",
            isPresented: $confirmsDelete
        ) {
            Button("删除预设", role: .destructive) {
                appState.deletePreset(preset)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只会删除这个自定义预设，不会更改当前压缩设置。")
        }
    }
}

private struct SettingChip: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(L10n.text(text))
            .font(.caption2)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
    }
}

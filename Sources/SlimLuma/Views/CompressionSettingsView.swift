import SlimLumaKit
import SwiftUI

struct CompressionSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedKind: MediaKind = .image

    var body: some View {
        VStack(spacing: 0) {
            settingsHeader

            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    if appState.isProcessing {
                        Label(
                            "当前批次已锁定设置；完成或取消后可修改",
                            systemImage: "lock.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 2)
                    }

                    Group {
                        switch selectedKind {
                        case .image:
                            ImageSettingsPanel()
                        case .video:
                            VideoSettingsPanel()
                        case .pdf:
                            PDFSettingsPanel()
                        case .unknown:
                            EmptyView()
                        }

                        OutputSettingsPanel()
                    }
                    .disabled(appState.isProcessing)
                }
                .padding(16)
            }
            .background(SlimLumaStyle.settingsCanvas)
        }
        .background(SlimLumaStyle.interactiveSurface)
        .onAppear { synchronizeSelectedKind() }
        .onChange(of: appState.selectedItemID) { _, _ in
            synchronizeSelectedKind()
        }
    }

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                settingsHeaderCopy
                Spacer()
                presetsMenu
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("媒体类型")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                MediaKindSelector(selection: $selectedKind)
            }

            if let selectedItem = appState.selectedQueueItem {
                HStack(spacing: 10) {
                    selectedItemIcon
                    selectedItemCopy(selectedItem)
                    Spacer(minLength: 6)
                    selectedItemActions(selectedItem)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(SlimLumaStyle.accent.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(SlimLumaStyle.accent.opacity(0.18))
                )
            }
        }
        .padding(16)
        .background(SlimLumaStyle.interactiveSurface)
    }

    private var settingsHeaderCopy: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("压缩设置")
                .font(.headline)
            Text("选择媒体类型后调整对应参数")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var presetsMenu: some View {
        Menu {
            ForEach(appState.allPresets) { preset in
                Button(
                    preset.isBuiltIn
                        ? L10n.text(preset.name)
                        : preset.name
                ) {
                    appState.applyPreset(preset)
                }
            }
        } label: {
            Label("应用预设", systemImage: "square.stack.3d.up")
        }
        .menuStyle(.button)
        .controlSize(.regular)
        .help("把预设参数应用到当前压缩任务")
        .disabled(appState.isProcessing)
    }

    private var selectedItemIcon: some View {
        Image(systemName: "doc.badge.gearshape")
            .foregroundStyle(SlimLumaStyle.accent)
            .accessibilityHidden(true)
    }

    private func selectedItemCopy(
        _ selectedItem: CompressionQueueItem
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(selectedItem.inputURL.lastPathComponent)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            Text(
                selectedItem.settingsOverride == nil
                    ? "此文件当前使用下方全局设置"
                    : "此文件已保存独立设置；下方仍编辑全局设置"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func selectedItemActions(
        _ selectedItem: CompressionQueueItem
    ) -> some View {
        if selectedItem.settingsOverride == nil {
            Button("复制给此文件") {
                appState.applyCurrentSettings(
                    to: selectedItem.id
                )
            }
        } else {
            Button("用下方设置更新") {
                appState.applyCurrentSettings(
                    to: selectedItem.id
                )
            }
            Button("恢复全局") {
                appState.clearSettingsOverride(
                    for: selectedItem.id
                )
            }
        }
    }

    private func synchronizeSelectedKind() {
        guard let selectedID = appState.selectedItemID,
              let item = appState.queue.first(where: { $0.id == selectedID }),
              item.mediaKind != .unknown else {
            return
        }
        selectedKind = item.mediaKind
    }
}

private struct MediaKindSelector: View {
    @Binding var selection: MediaKind

    var body: some View {
        HStack(spacing: 8) {
            kindButton(.image)
            kindButton(.video)
            kindButton(.pdf)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("压缩设置媒体类型")
    }

    private func kindButton(_ kind: MediaKind) -> some View {
        let isSelected = selection == kind

        return Button {
            selection = kind
        } label: {
            HStack(spacing: 7) {
                Image(systemName: kind.symbolName)
                Text(L10n.text(kind.displayName))
                    .fontWeight(.medium)
                Spacer(minLength: 4)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
            }
            .font(.callout)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? SlimLumaStyle.accent : SlimLumaStyle.interactiveSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isSelected
                        ? SlimLumaStyle.accent
                        : SlimLumaStyle.controlBorder,
                    lineWidth: isSelected ? 0 : 1
                )
        )
        .shadow(
            color: isSelected ? SlimLumaStyle.accent.opacity(0.18) : .clear,
            radius: 4,
            y: 2
        )
        .accessibilityValue(isSelected ? "已选择" : "未选择")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ImageSettingsPanel: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        SettingsCard(title: "图片", symbol: "photo") {
            AdaptivePickerRow(
                title: "输出格式",
                controlMinWidth: 170,
                controlIdealWidth: 210,
                controlMaxWidth: 280
            ) {
                Picker("输出格式", selection: $appState.settings.image.format) {
                    ForEach(ImageOutputFormat.allCases) { format in
                        Text(L10n.text(format.displayName)).tag(format)
                    }
                }
                .labelsHidden()
            }

            if !appState.settings.image.lossless {
                QualityControl(
                    title: "质量",
                    value: $appState.settings.image.quality,
                    range: 1...100,
                    lowLabel: "更小",
                    highLabel: "更清晰"
                )
            }

            Toggle(
                "无损模式",
                isOn: $appState.settings.image.lossless
            )
            .disabled(
                !canEnableLossless
                    || appState.settings.image.targetSizeBytes != nil
            )
            .help(L10n.text(losslessHelp))

            TargetSizeEditor(
                title: "目标文件大小",
                value: $appState.settings.image.targetSizeBytes,
                defaultMegabytes: 1,
                minimumBytes: 16 * 1_024
            )

            if appState.settings.image.targetSizeBytes != nil {
                Label(
                    "SlimLuma 会逐级调整质量；必要时缩小尺寸，以得到不超过目标的最清晰安全结果。目标大小需要 ImageMagick。",
                    systemImage: "scope"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            if appState.settings.image.format == .keep,
               appState.settings.image.lossless {
                Label(
                    "保持原格式时，仅 PNG、WebP、GIF、TIFF、BMP 和 JPEG 2000 可无损重写；JPEG、HEIC 与 AVIF 会在开始前拦截。",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } else if !canEnableLossless {
                Text("当前格式没有可靠的无损编码；请选择 PNG 或 WebP。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            OptionalDimensionEditor(
                title: "限制宽度",
                value: $appState.settings.image.maxWidth,
                defaultValue: 2560,
                range: 64...32_768
            )
            OptionalDimensionEditor(
                title: "限制高度",
                value: $appState.settings.image.maxHeight,
                defaultValue: 2560,
                range: 64...32_768
            )

            Divider()

            AdaptivePickerRow(
                title: "元数据",
                controlMinWidth: 210,
                controlIdealWidth: 240,
                controlMaxWidth: 300
            ) {
                Picker("元数据", selection: $appState.settings.image.metadata) {
                    ForEach(MetadataPolicy.allCases) { policy in
                        Text(L10n.text(policy.displayName)).tag(policy)
                    }
                }
                .labelsHidden()
            }

            Toggle(
                "保留 ICC 色彩配置",
                isOn: $appState.settings.image.preserveColorProfile
            )

            HStack {
                Text("压缩强度")
                Spacer()
                effortStepper
            }
            .disabled(!canCustomizeEffort)
            .help(L10n.text(effortHelp))

            if let effortAvailabilityMessage {
                Label(L10n.text(effortAvailabilityMessage), systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear(perform: normalizeLosslessSelection)
        .onChange(of: appState.settings.image.format) { _, _ in
            normalizeLosslessSelection()
        }
        .onChange(of: appState.settings.image.targetSizeBytes) { _, target in
            if target != nil {
                appState.settings.image.lossless = false
            }
        }
    }

    private var effortStepper: some View {
        Stepper(
            "\(appState.settings.image.effort)",
            value: $appState.settings.image.effort,
            in: 1...9
        )
        .frame(width: 100)
        .accessibilityLabel("压缩强度")
        .accessibilityValue("\(appState.settings.image.effort)")
    }

    private var canEnableLossless: Bool {
        switch appState.settings.image.format {
        case .keep, .png, .webp:
            true
        case .jpeg, .avif, .heic:
            false
        }
    }

    private var losslessHelp: String {
        switch appState.settings.image.format {
        case .png, .webp:
            "使用该格式的无损编码"
        case .keep:
            "仅在原格式支持可靠无损重写时生效"
        case .jpeg, .avif, .heic:
            "当前格式不能保证逐像素无损，请改用 PNG 或 WebP"
        }
    }

    private var canCustomizeEffort: Bool {
        switch appState.settings.image.format {
        case .webp, .avif, .keep:
            true
        case .jpeg, .png, .heic:
            false
        }
    }

    private var effortHelp: String {
        switch appState.settings.image.format {
        case .webp:
            "数值越高，WebP 编码越慢，通常可以获得更小文件"
        case .avif:
            "数值越高，AVIF 编码越慢，通常可以获得更小文件"
        case .keep:
            "仅队列中原格式为 WebP 或 AVIF 的图片会使用该设置"
        case .jpeg, .png, .heic:
            "压缩强度仅供 WebP 和 AVIF 编码使用"
        }
    }

    private var effortAvailabilityMessage: String? {
        switch appState.settings.image.format {
        case .webp, .avif:
            nil
        case .keep:
            "保持原格式时，压缩强度只影响原格式为 WebP 或 AVIF 的图片；其他图片会忽略此项。"
        case .jpeg, .png, .heic:
            "压缩强度仅用于 WebP 与 AVIF；当前输出格式不使用此设置。"
        }
    }

    private func normalizeLosslessSelection() {
        if !canEnableLossless {
            appState.settings.image.lossless = false
        }
    }
}

private struct VideoSettingsPanel: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        SettingsCard(title: "视频", symbol: "film") {
            AdaptivePickerRow(
                title: "编码格式",
                controlMinWidth: 225,
                controlIdealWidth: 260,
                controlMaxWidth: 320
            ) {
                Picker("编码格式", selection: $appState.settings.video.codec) {
                    ForEach(VideoCodec.allCases) { codec in
                        Text(L10n.text(codec.displayName)).tag(codec)
                    }
                }
                .labelsHidden()
            }

            TargetSizeEditor(
                title: "目标文件大小",
                value: $appState.settings.video.targetSizeBytes,
                defaultMegabytes: 25,
                minimumBytes: 128 * 1_024
            )
            .disabled(appState.settings.video.codec == .av1)

            if appState.settings.video.targetSizeBytes == nil {
                QualityControl(
                    title: "画面质量",
                    value: $appState.settings.video.quality,
                    range: 1...100,
                    lowLabel: "更小",
                    highLabel: "更清晰"
                )
            } else {
                Label(
                    "目标大小会使用两遍软件编码，自动计算视频码率；画面质量与硬件加速暂不参与本次任务。",
                    systemImage: "scope"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            AdaptivePickerRow(
                title: "编码速度",
                controlMinWidth: 150,
                controlIdealWidth: 190,
                controlMaxWidth: 260
            ) {
                Picker("编码速度", selection: $appState.settings.video.speed) {
                    ForEach(VideoSpeed.allCases) { speed in
                        Text(L10n.text(speed.displayName)).tag(speed)
                    }
                }
                .labelsHidden()
            }
            .disabled(
                appState.settings.video.hardwareAcceleration
                    && appState.settings.video.codec != .av1
            )

            Toggle(
                "使用 Apple 硬件加速",
                isOn: $appState.settings.video.hardwareAcceleration
            )
            .disabled(
                appState.settings.video.codec == .av1
                    || appState.settings.video.targetSizeBytes != nil
            )
            .help(
                L10n.text(
                    appState.settings.video.codec == .av1
                        ? "AV1 使用软件编码，编码速度设置仍可调整"
                        : "速度更快、功耗更低；软件编码通常能得到更小文件"
                )
            )

            Divider()

            OptionalDimensionEditor(
                title: "限制宽度",
                value: $appState.settings.video.maxWidth,
                defaultValue: 1920,
                range: 160...7680
            )
            OptionalDimensionEditor(
                title: "限制高度",
                value: $appState.settings.video.maxHeight,
                defaultValue: 1080,
                range: 120...4320
            )
            OptionalDimensionEditor(
                title: "限制帧率",
                value: $appState.settings.video.frameRate,
                defaultValue: 30,
                range: 1...240,
                unit: "fps"
            )

            AdaptivePickerRow(
                title: "音频码率",
                controlMinWidth: 120,
                controlIdealWidth: 120,
                controlMaxWidth: 160
            ) {
                Picker("音频码率", selection: $appState.settings.video.audioBitrate) {
                    Text("64 kbps").tag(64)
                    Text("96 kbps").tag(96)
                    Text("128 kbps").tag(128)
                    Text("192 kbps").tag(192)
                    Text("256 kbps").tag(256)
                    Text("320 kbps").tag(320)
                }
                .labelsHidden()
            }

            Toggle("移除拍摄元数据", isOn: $appState.settings.video.removeMetadata)
            Toggle("保留章节", isOn: $appState.settings.video.preserveChapters)

            Label(
                "输出会校验时长、音轨、字幕内容、语言与默认/强制标记、章节和 HDR 色彩标记；关键语义丢失时会自动丢弃结果。",
                systemImage: "checkmark.shield.fill"
            )
            .font(.caption)
            .foregroundStyle(SlimLumaStyle.success)
            .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear(perform: normalizeAV1Selection)
        .onChange(of: appState.settings.video.codec) { _, _ in
            normalizeAV1Selection()
        }
        .onChange(of: appState.settings.video.targetSizeBytes) { _, _ in
            normalizeAV1Selection()
        }
    }

    private func normalizeAV1Selection() {
        if !appState.isProcessing,
           appState.settings.video.codec == .av1 {
            appState.settings.video.hardwareAcceleration = false
            appState.settings.video.targetSizeBytes = nil
        } else if appState.settings.video.targetSizeBytes != nil {
            appState.settings.video.hardwareAcceleration = false
        }
    }
}

private struct PDFSettingsPanel: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        SettingsCard(title: "PDF", symbol: "doc.richtext") {
            if let selectedItem = appState.selectedQueueItem,
               selectedItem.mediaKind == .pdf {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("加密 PDF 密码", systemImage: "lock")
                        Spacer()
                        pdfPasswordField(selectedItem)
                    }
                    Text("密码仅保存在当前队列的内存中，不会写入历史、预设或日志；输出会恢复原 PDF 的加密策略。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(SlimLumaStyle.interactiveSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(SlimLumaStyle.controlBorder)
                )
            }

            AdaptivePickerRow(
                title: "压缩策略",
                controlMinWidth: 170,
                controlIdealWidth: 210,
                controlMaxWidth: 280
            ) {
                Picker("压缩策略", selection: $appState.settings.pdf.mode) {
                    ForEach(PDFCompressionMode.allCases) { mode in
                        Text(L10n.text(mode.displayName)).tag(mode)
                    }
                }
                .labelsHidden()
            }

            AdaptivePickerRow(
                title: "处理引擎",
                controlMinWidth: 210,
                controlIdealWidth: 240,
                controlMaxWidth: 300
            ) {
                Picker("处理引擎", selection: $appState.settings.pdf.engine) {
                    ForEach(PDFEnginePreference.allCases) { engine in
                        Text(L10n.text(engine.displayName)).tag(engine)
                    }
                }
                .labelsHidden()
            }

            PDFEngineReadiness()

            QualityControl(
                title: "图片质量",
                value: $appState.settings.pdf.imageQuality,
                range: 20...100,
                lowLabel: "更小",
                highLabel: "更清晰"
            )
            .disabled(!usesPDFImageQuality)
            .help(L10n.text(pdfImageQualityHelp))

            if appState.settings.pdf.imageQuality < 50,
               usesPDFImageQuality {
                Label(
                    "当前质量低于 50，细字、线稿和渐变可能出现明显失真。",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(SlimLumaStyle.warning)
            }

            AdaptivePickerRow(
                title: "图片分辨率",
                controlMinWidth: 110,
                controlIdealWidth: 110,
                controlMaxWidth: 160
            ) {
                Picker("图片分辨率", selection: $appState.settings.pdf.imageDPI) {
                    Text("72 dpi").tag(72)
                    Text("96 dpi").tag(96)
                    Text("144 dpi").tag(144)
                    Text("150 dpi").tag(150)
                    Text("200 dpi").tag(200)
                    Text("300 dpi").tag(300)
                }
                .labelsHidden()
            }
            .disabled(!usesGhostscriptImageControls)
            .help(L10n.text(ghostscriptImageControlsHelp))

            Toggle("转为灰度", isOn: $appState.settings.pdf.grayscale)
                .disabled(!usesGhostscriptImageControls)
                .help(L10n.text(ghostscriptImageControlsHelp))

            if let ghostscriptImageControlsMessage {
                Label(L10n.text(ghostscriptImageControlsMessage), systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle("为网页快速打开优化", isOn: $appState.settings.pdf.linearizeForWeb)

            Label(
                "完整性保护已开启：页数变化，书签、链接或批注、表单、签名字段数量减少，或可搜索文本大幅下降时，不会保留输出。",
                systemImage: "checkmark.shield.fill"
            )
            .font(.caption)
            .foregroundStyle(SlimLumaStyle.success)
            .fixedSize(horizontal: false, vertical: true)

            if appState.settings.pdf.engine == .ghostscript ||
                appState.settings.pdf.mode == .compact {
                Label(
                    "强力压缩会重写 PDF；检测到数字签名时会停止处理，避免生成看似有效的失签文件。",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(SlimLumaStyle.warning)
            }
        }
    }

    private func pdfPasswordField(
        _ selectedItem: CompressionQueueItem
    ) -> some View {
        SecureField(
            "未加密可留空",
            text: Binding(
                get: { selectedItem.pdfPassword ?? "" },
                set: {
                    appState.updatePDFPassword(
                        for: selectedItem.id,
                        password: $0
                    )
                }
            )
        )
        .textFieldStyle(.roundedBorder)
        .frame(width: 170)
    }

    private var hasQPDF: Bool {
        appState.isToolAvailable(.qpdf)
    }

    private var hasGhostscript: Bool {
        appState.isToolAvailable(.ghostscript)
    }

    private enum ActivePDFBackend {
        case ghostscript
        case qpdf
        case pdfKit
        case unavailable
    }

    private var activeBackend: ActivePDFBackend {
        switch appState.settings.pdf.engine {
        case .ghostscript:
            return hasGhostscript ? .ghostscript : .unavailable
        case .qpdf:
            return hasQPDF ? .qpdf : .unavailable
        case .automatic:
            if appState.settings.pdf.mode != .lossless, hasGhostscript {
                return .ghostscript
            }
            if hasQPDF {
                return .qpdf
            }
            return .pdfKit
        }
    }

    private var usesPDFImageQuality: Bool {
        switch activeBackend {
        case .ghostscript:
            return appState.settings.pdf.mode != .lossless
        case .qpdf:
            return appState.settings.pdf.mode != .lossless
        case .pdfKit, .unavailable:
            return false
        }
    }

    /// Mirrors the coordinator's engine route so controls never imply that
    /// qpdf or PDFKit can apply Ghostscript-only image transformations.
    private var usesGhostscriptImageControls: Bool {
        activeBackend == .ghostscript
            && appState.settings.pdf.mode != .lossless
    }

    private var pdfImageQualityHelp: String {
        switch activeBackend {
        case .ghostscript where appState.settings.pdf.mode != .lossless:
            return "由 Ghostscript 应用到 PDF 内的图片"
        case .ghostscript:
            return "“无损整理”不会应用图片质量、降采样或灰度转换"
        case .qpdf where appState.settings.pdf.mode != .lossless:
            return "由 qpdf 用于重新编码符合条件的 PDF 内嵌图片；不会改变图片分辨率"
        case .qpdf:
            return "“无损整理”不会重新编码 PDF 内嵌图片"
        case .pdfKit:
            return "PDFKit 后备只执行无损重写，不使用图片质量"
        case .unavailable:
            return "所选 PDF 引擎尚未安装"
        }
    }

    private var ghostscriptImageControlsHelp: String {
        usesGhostscriptImageControls
            ? "由 Ghostscript 应用到 PDF 内的图片"
            : "图片质量、分辨率和灰度转换仅在实际使用 Ghostscript 时生效"
    }

    private var ghostscriptImageControlsMessage: String? {
        guard !usesGhostscriptImageControls else {
            return nil
        }

        if appState.settings.pdf.mode == .lossless {
            if activeBackend == .pdfKit {
                return "未检测到 qpdf，“无损整理”将使用 PDFKit 后备；图片重编码、分辨率与灰度设置不参与处理。"
            }
            return "“无损整理”不会重新编码图片，也不会应用分辨率或灰度设置。"
        }

        switch appState.settings.pdf.engine {
        case .qpdf:
            if appState.settings.pdf.mode == .lossless {
                return "已选择 qpdf 的“无损整理”：不会重新编码图片，也不会应用分辨率或灰度设置。"
            }
            return "已选择 qpdf：图片质量会用于重新编码符合条件的内嵌图片；分辨率与灰度设置不生效。"

        case .ghostscript:
            return "Ghostscript 尚未安装；安装完成后，图片质量、分辨率与灰度设置才可用。"

        case .automatic:
            if appState.settings.pdf.mode == .lossless, hasQPDF {
                return "“无损整理”当前会使用 qpdf；图片质量、分辨率与灰度设置不会参与处理。"
            }
            if hasQPDF {
                return "未检测到 Ghostscript，自动模式将使用 qpdf；图片质量可用，分辨率与灰度设置不生效。"
            }
            return "未检测到 Ghostscript，自动模式将使用 PDFKit 后备；图片质量、分辨率与灰度设置不会参与处理。"
        }
    }
}

private struct PDFEngineReadiness: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            readinessIcon
            readinessCopy
            Spacer(minLength: 6)
            if !isReady {
                installButton
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill((isReady ? SlimLumaStyle.success : SlimLumaStyle.warning).opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    (isReady ? SlimLumaStyle.success : SlimLumaStyle.warning).opacity(0.20)
                )
        )
    }

    private var readinessIcon: some View {
        Image(
            systemName: isReady
                ? "checkmark.circle.fill"
                : "exclamationmark.triangle.fill"
        )
        .foregroundStyle(
            isReady ? SlimLumaStyle.success : SlimLumaStyle.warning
        )
        .padding(.top, 1)
        .accessibilityHidden(true)
    }

    private var readinessCopy: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n.text(title))
                .font(.callout.weight(.semibold))
            Text(L10n.text(message))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var installButton: some View {
        Button(L10n.text(installButtonTitle)) {
            if missingTools.count > 1 {
                appState.installPDFTools()
            } else if let tool = missingTools.first {
                appState.installTool(tool)
            }
            appState.section = .engines
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(appState.engineInstallation.isInstalling)
    }

    private var requiredTools: [ToolKind] {
        switch appState.settings.pdf.engine {
        case .qpdf:
            [.qpdf]
        case .ghostscript:
            [.ghostscript, .qpdf]
        case .automatic:
            appState.settings.pdf.mode == .lossless
                ? [.qpdf]
                : [.ghostscript, .qpdf]
        }
    }

    private var isReady: Bool {
        missingTools.isEmpty
    }

    private var missingTools: [ToolKind] {
        requiredTools.filter { !appState.isToolAvailable($0) }
    }

    private var hasQPDF: Bool {
        appState.isToolAvailable(.qpdf)
    }

    private var hasGhostscript: Bool {
        appState.isToolAvailable(.ghostscript)
    }

    private var installButtonTitle: String {
        if missingTools.count > 1 {
            return "一键补齐 PDF 引擎"
        }
        guard let tool = missingTools.first else {
            return "引擎已就绪"
        }
        return "安装 \(tool.displayName)"
    }

    private var title: String {
        switch appState.settings.pdf.engine {
        case .qpdf:
            return hasQPDF ? "qpdf 无损优化已就绪" : "需要安装 qpdf"
        case .ghostscript:
            guard hasGhostscript else { return "需要安装 Ghostscript" }
            return hasQPDF
                ? "完整 PDF 压缩链路已就绪"
                : "Ghostscript 可用，结构保护可补强"
        case .automatic:
            if appState.settings.pdf.mode == .lossless {
                return hasQPDF
                    ? "无损 PDF 优化已就绪"
                    : "当前将使用 PDFKit 后备"
            }
            if hasGhostscript, hasQPDF {
                return "完整 PDF 压缩链路已就绪"
            }
            if hasGhostscript {
                return "Ghostscript 可用，建议补装 qpdf"
            }
            if hasQPDF {
                return "当前将使用 qpdf 有限优化"
            }
            return "当前将使用 PDFKit 后备"
        }
    }

    private var message: String {
        let linearizes = appState.settings.pdf.linearizeForWeb

        switch appState.settings.pdf.engine {
        case .qpdf:
            guard hasQPDF else {
                return "你已显式选择 qpdf；SlimLuma 不会静默改用其他引擎，安装后即可重试。"
            }
            return linearizes
                ? "qpdf 会优化对象流、图片编码和网页快速打开结构。"
                : "qpdf 会优化对象流与图片编码；网页快速打开当前已关闭。"

        case .ghostscript:
            guard hasGhostscript else {
                return "你已显式选择 Ghostscript；SlimLuma 不会改用 qpdf 或 PDFKit，安装后即可重试。"
            }
            if hasQPDF {
                return linearizes
                    ? "qpdf 先修复结构，Ghostscript 压缩图片，qpdf 再做网页优化，最后执行完整性检查。"
                    : "qpdf 先修复结构，Ghostscript 压缩图片，最后执行完整性检查；网页快速打开已关闭。"
            }
            return linearizes
                ? "Ghostscript 会直接压缩并尝试网页快速打开；补装 qpdf 后可增加压缩前结构修复。"
                : "Ghostscript 会直接压缩并执行完整性检查；补装 qpdf 后可增加压缩前结构修复。"

        case .automatic:
            if appState.settings.pdf.mode == .lossless {
                if hasQPDF {
                    return linearizes
                        ? "qpdf 会无损整理对象流并生成网页快速打开结构。"
                        : "qpdf 会无损整理对象流；网页快速打开当前已关闭。"
                }
                return linearizes
                    ? "PDFKit 只做无损重写，不能生成网页快速打开结构；补装 qpdf 后该设置才会生效。"
                    : "PDFKit 会做系统级无损重写，压缩效果通常有限。"
            }
            if hasGhostscript, hasQPDF {
                return linearizes
                    ? "qpdf 先修复结构，Ghostscript 压缩图片，qpdf 再做网页优化，最后执行完整性检查。"
                    : "qpdf 先修复结构，Ghostscript 压缩图片，最后执行完整性检查；网页快速打开已关闭。"
            }
            if hasGhostscript {
                return linearizes
                    ? "Ghostscript 会直接压缩并尝试网页快速打开；补装 qpdf 后可增加结构修复。"
                    : "Ghostscript 会直接压缩并执行完整性检查；补装 qpdf 后可增加结构修复。"
            }
            if hasQPDF {
                return linearizes
                    ? "qpdf 会优化结构和图片编码并生成网页快速打开结构，但不会降低图片分辨率。"
                    : "qpdf 会优化结构和图片编码，但不会降低图片分辨率。"
            }
            return linearizes
                ? "PDFKit 只做无损重写，不能生成网页快速打开结构；一键补齐引擎后可获得实际压缩。"
                : "PDFKit 只做系统级无损重写；一键补齐引擎后可获得实际压缩。"
        }
    }
}

private struct OutputSettingsPanel: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        SettingsCard(title: "输出", symbol: "folder") {
            ViewThatFits(in: .horizontal) {
                Picker(
                    "保存到",
                    selection: $appState.settings.output.location
                ) {
                    outputLocationOptions
                }
                .pickerStyle(.segmented)
                .fixedSize(horizontal: true, vertical: false)

                Picker(
                    "保存到",
                    selection: $appState.settings.output.location
                ) {
                    outputLocationOptions
                }
                .pickerStyle(.menu)
            }

            if appState.settings.output.location == .customDirectory {
                HStack {
                    outputFolderIcon
                    outputFolderPath
                    Spacer()
                    chooseOutputFolderButton
                }

                if let issue = appState.outputSettingsIssue {
                    Label(L10n.text(issue), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(SlimLumaStyle.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("output.directory.issue")
                }
            }

            HStack {
                Text("文件名后缀")
                Spacer()
                filenameSuffixField
            }

            Toggle(
                "保留没有变小的结果",
                isOn: $appState.settings.output.keepLargerFiles
            )
            Toggle(
                "保留 Finder 中的原修改时间",
                isOn: $appState.settings.output.preserveModificationDate
            )

            Label("始终生成新文件，不会覆盖原件", systemImage: "checkmark.shield")
                .font(.caption)
                .foregroundStyle(SlimLumaStyle.success)
        }
    }

    private var outputFolderIcon: some View {
        Image(systemName: "folder")
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }

    private var outputFolderPath: some View {
        Text(
            appState.settings.output.customDirectoryPath
                ?? L10n.text("尚未选择")
        )
        .font(.caption)
        .lineLimit(1)
        .truncationMode(.middle)
    }

    private var chooseOutputFolderButton: some View {
        Button("选择…") { appState.chooseOutputFolder() }
    }

    private var filenameSuffixField: some View {
        TextField(
            "文件名后缀",
            text: $appState.settings.output.filenameSuffix,
            prompt: Text("-slim")
        )
        .multilineTextAlignment(.trailing)
        .frame(width: 130)
    }

    private var outputLocationOptions: some View {
        ForEach(OutputLocation.allCases) { location in
            Text(L10n.text(location.displayName)).tag(location)
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(L10n.text(title), systemImage: symbol)
                    .font(.headline)
                    .foregroundStyle(SlimLumaStyle.accent)
                content
            }
        }
    }
}

private struct AdaptivePickerRow<Control: View>: View {
    let title: String
    let controlMinWidth: CGFloat
    let controlIdealWidth: CGFloat
    let controlMaxWidth: CGFloat
    @ViewBuilder let control: () -> Control

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                horizontalLabel
                Spacer(minLength: 12)
                horizontalControl
            }

            VStack(alignment: .leading, spacing: 6) {
                visibleLabel
                control()
                    .accessibilityLabel(Text(L10n.text(title)))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var horizontalLabel: some View {
        visibleLabel
            .fixedSize(horizontal: true, vertical: false)
    }

    private var horizontalControl: some View {
        control()
            .accessibilityLabel(Text(L10n.text(title)))
            .frame(
                minWidth: controlMinWidth,
                idealWidth: controlIdealWidth,
                maxWidth: controlMaxWidth
            )
    }

    private var visibleLabel: some View {
        Text(L10n.text(title))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
    }
}

private struct QualityControl: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let lowLabel: String
    let highLabel: String

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(L10n.text(title))
                Spacer()
                qualityValue
            }
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
            .accessibilityLabel(Text(L10n.text(title)))
            .accessibilityValue("\(value)")
            HStack {
                Text(L10n.text(lowLabel))
                Spacer()
                Text(L10n.text(highLabel))
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }

    private var qualityValue: some View {
        Text("\(value)")
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }
}

private struct TargetSizeEditor: View {
    let title: String
    @Binding var value: Int64?
    let defaultMegabytes: Double
    let minimumBytes: Int64

    var body: some View {
        HStack(spacing: 10) {
            targetToggle
            Spacer()
            if value != nil {
                valueField
                valueUnit
            }
        }
    }

    private var targetToggle: some View {
        Toggle(
            L10n.text(title),
            isOn: Binding(
                get: { value != nil },
                set: { enabled in
                    value = enabled
                        ? Int64(defaultMegabytes * 1_048_576)
                        : nil
                }
            )
        )
    }

    private var valueField: some View {
        TextField(
            L10n.text(title),
            value: Binding(
                get: {
                    Double(value ?? minimumBytes) / 1_048_576
                },
                set: { megabytes in
                    let bytes = Int64(
                        (max(0.01, megabytes) * 1_048_576)
                            .rounded()
                    )
                    value = max(minimumBytes, bytes)
                }
            ),
            format: .number.precision(
                .fractionLength(0...2)
            )
        )
        .multilineTextAlignment(.trailing)
        .frame(width: 76)
        .accessibilityLabel(Text(L10n.text(title)))
    }

    private var valueUnit: some View {
        Text("MB")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private struct OptionalDimensionEditor: View {
    let title: String
    @Binding var value: Int?
    let defaultValue: Int
    let range: ClosedRange<Int>
    var unit: String = "px"

    var body: some View {
        HStack {
            dimensionToggle
            Spacer()
            if value != nil {
                dimensionField
                dimensionUnit
            }
        }
    }

    private var dimensionToggle: some View {
        Toggle(
            L10n.text(title),
            isOn: Binding(
                get: { value != nil },
                set: { enabled in value = enabled ? defaultValue : nil }
            )
        )
    }

    private var dimensionField: some View {
        TextField(
            L10n.text(title),
            value: Binding(
                get: { value ?? defaultValue },
                set: {
                    value = max(
                        range.lowerBound,
                        min(range.upperBound, $0)
                    )
                }
            ),
            format: .number
        )
        .multilineTextAlignment(.trailing)
        .frame(width: 72)
        .accessibilityLabel(Text(L10n.text(title)))
        .accessibilityValue("\(value ?? defaultValue) \(unit)")
    }

    private var dimensionUnit: some View {
        Text(unit)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

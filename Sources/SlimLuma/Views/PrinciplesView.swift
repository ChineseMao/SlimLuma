import SwiftUI
import SlimLumaKit

struct PrinciplesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTopic: PrincipleTopic = .overview

    private let topAnchor = "principles-top"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Color.clear
                        .frame(height: 0)
                        .id(topAnchor)

                    pageHeader
                    topicPicker
                    topicIntroduction

                    if selectedTopic == .overview {
                        overviewContent
                    } else {
                        topicSections
                    }

                    if selectedTopic == .automation {
                        engineSection
                    }
                }
                .frame(maxWidth: 1060, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .onChange(of: selectedTopic) { _, _ in
                proxy.scrollTo(topAnchor, anchor: .top)
            }
        }
        .navigationTitle("功能与原理")
        .onAppear {
            appState.refreshTools()
        }
    }

    private var pageHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) {
                headerCopy
                Spacer(minLength: 20)
                implementationBadge
            }

            VStack(alignment: .leading, spacing: 12) {
                headerCopy
                implementationBadge
            }
        }
    }

    private var headerCopy: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("功能与实现原理")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("知道 SlimLuma 能改变什么、为什么能变小，以及什么时候会停止。")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var implementationBadge: some View {
        Label("基于当前版本的真实处理链路", systemImage: "checkmark.seal.fill")
            .font(.callout.weight(.semibold))
            .foregroundStyle(SlimLumaStyle.success)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(SlimLumaStyle.success.opacity(0.10), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(SlimLumaStyle.success.opacity(0.22))
            )
    }

    private var topicPicker: some View {
        ViewThatFits(in: .horizontal) {
            Picker("原理主题", selection: $selectedTopic) {
                topicOptions
            }
            .pickerStyle(.segmented)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("选择功能与原理主题")

            HStack {
                Text("原理主题")
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("原理主题", selection: $selectedTopic) {
                    topicOptions
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityLabel("选择功能与原理主题")
            }
        }
    }

    private var topicOptions: some View {
        ForEach(PrincipleTopic.allCases) { topic in
            Label(L10n.text(topic.title), systemImage: topic.symbolName)
                .tag(topic)
        }
    }

    private var topicIntroduction: some View {
        PanelCard {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    topicIcon
                    topicCopy
                    Spacer(minLength: 20)
                    if selectedTopic != .overview {
                        topicCount
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
                        topicIcon
                        topicCopy
                    }
                    if selectedTopic != .overview {
                        topicCount
                    }
                }
            }
        }
    }

    private var topicIcon: some View {
        Image(systemName: selectedTopic.symbolName)
            .font(.system(size: 25, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 52, height: 52)
            .background(
                LinearGradient(
                    colors: [
                        topicTint,
                        topicTint.opacity(0.72)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    private var topicCopy: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(
                L10n.text(
                    selectedTopic == .overview
                        ? "SlimLuma 是本机压缩工作流，也是结果守门员"
                        : selectedTopic.title
                )
            )
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text(L10n.text(selectedTopic.subtitle))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var topicCount: some View {
        Text("\(PrinciplesCatalog.sections(for: selectedTopic).count) 个说明章节")
            .font(.caption.weight(.medium))
            .foregroundStyle(topicTint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(topicTint.opacity(0.09), in: Capsule())
    }

    @ViewBuilder
    private var overviewContent: some View {
        workflowSection
        capabilitySection

        ForEach(PrinciplesCatalog.sections(for: .overview)) { section in
            PrincipleSectionCard(section: section)
        }
    }

    private var workflowSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading(
                title: "从导入到结果的闭环",
                subtitle: "原件从不进入覆盖写入路径；每一步失败都保留可解释的状态。"
            )
            PrincipleWorkflow(steps: PrinciplesCatalog.processSteps)
        }
    }

    private var capabilitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading(
                title: "按能力继续了解",
                subtitle: "每张卡片都是可操作的主题入口，不是灰色提示区域。"
            )

            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 270), spacing: 12)
                ],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(PrinciplesCatalog.capabilities) { capability in
                    PrincipleCapabilityButton(
                        capability: capability,
                        tint: tint(for: capability.topic)
                    ) {
                        selectedTopic = capability.topic
                    }
                }
            }
        }
    }

    private var topicSections: some View {
        ForEach(PrinciplesCatalog.sections(for: selectedTopic)) { section in
            PrincipleSectionCard(section: section)
        }
    }

    private var engineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 16) {
                    engineSectionHeading
                    Spacer(minLength: 20)
                    enginesButton
                }

                VStack(alignment: .leading, spacing: 12) {
                    engineSectionHeading
                    enginesButton
                }
            }

            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 330), spacing: 12)
                ],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(PrinciplesCatalog.engines) { engine in
                    PrincipleEngineCard(
                        engine: engine,
                        status: engineStatus(for: engine)
                    )
                }
            }

            PanelCard {
                HStack(alignment: .top, spacing: 12) {
                    thirdPartyBoundaryIcon
                    thirdPartyBoundaryCopy
                }
            }
        }
    }

    private var engineSectionHeading: some View {
        sectionHeading(
            title: "引擎分工与当前状态",
            subtitle: "状态来自本机实时检测；系统内置与独立安装会明确区分。"
        )
    }

    private var thirdPartyBoundaryIcon: some View {
        Image(systemName: "doc.text")
            .font(.title3)
            .foregroundStyle(SlimLumaStyle.accent)
            .frame(width: 28)
            .accessibilityHidden(true)
    }

    private var thirdPartyBoundaryCopy: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("第三方许可与安装边界")
                .font(.headline)
            Text("ImageMagick 使用宽松许可，qpdf 使用 Apache-2.0；Ghostscript 为 AGPL/商业双许可，FFmpeg 的许可和编码能力取决于具体构建。SlimLuma 当前不捆绑这些二进制，引擎通过 Homebrew 独立安装。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var enginesButton: some View {
        Button {
            appState.section = .engines
        } label: {
            Label("前往引擎与设置", systemImage: "arrow.forward.circle.fill")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityHint("打开引擎检测、安装和应用设置")
    }

    private func sectionHeading(
        title: String,
        subtitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n.text(title))
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text(L10n.text(subtitle))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var topicTint: Color {
        tint(for: selectedTopic)
    }

    private func tint(for topic: PrincipleTopic) -> Color {
        switch topic {
        case .overview:
            SlimLumaStyle.accent
        case .images:
            Color(red: 0.72, green: 0.30, blue: 0.64)
        case .video:
            Color(red: 0.18, green: 0.47, blue: 0.88)
        case .pdf:
            Color(red: 0.87, green: 0.30, blue: 0.25)
        case .validation:
            SlimLumaStyle.success
        case .automation:
            SlimLumaStyle.secondaryAccent
        }
    }

    private func engineStatus(
        for engine: PrincipleEngine
    ) -> PrincipleEngineStatus {
        switch engine.runtime {
        case .system:
            return PrincipleEngineStatus(
                title: "系统内置",
                symbolName: "checkmark.seal.fill",
                tint: SlimLumaStyle.success
            )
        case .tool(let kind):
            if appState.isToolAvailable(kind) {
                return PrincipleEngineStatus(
                    title: "已安装",
                    symbolName: "checkmark.circle.fill",
                    tint: SlimLumaStyle.success
                )
            }
            return PrincipleEngineStatus(
                title: "未安装",
                symbolName: "arrow.down.circle",
                tint: SlimLumaStyle.warning
            )
        case .ffmpegWithProbe:
            let availability = appState.toolAvailability.first {
                $0.kind == .ffmpeg
            }
            if availability?.isAvailable == true {
                return PrincipleEngineStatus(
                    title: "已安装",
                    symbolName: "checkmark.circle.fill",
                    tint: SlimLumaStyle.success
                )
            }
            if availability?.missingCompanionExecutableName != nil {
                return PrincipleEngineStatus(
                    title: "缺少 ffprobe",
                    symbolName: "exclamationmark.triangle.fill",
                    tint: SlimLumaStyle.warning
                )
            }
            return PrincipleEngineStatus(
                title: "未安装",
                symbolName: "arrow.down.circle",
                tint: SlimLumaStyle.warning
            )
        }
    }
}

private struct PrincipleWorkflow: View {
    let steps: [PrincipleProcessStep]

    var body: some View {
        PanelCard {
            ViewThatFits(in: .horizontal) {
                horizontalFlow
                verticalFlow
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityDescription))
    }

    private var horizontalFlow: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                PrincipleFlowStep(step: step, isCompact: true)
                    .frame(maxWidth: .infinity)

                if index < steps.count - 1 {
                    Image(systemName: "chevron.forward")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                        .padding(.top, 18)
                        .accessibilityHidden(true)
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var verticalFlow: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                PrincipleFlowStep(step: step, isCompact: false)

                if index < steps.count - 1 {
                    Rectangle()
                        .fill(SlimLumaStyle.accent.opacity(0.20))
                        .frame(width: 2, height: 18)
                        .padding(.leading, 17)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var accessibilityDescription: String {
        steps.map { step in
            let title = L10n.text(step.title)
            let detail = L10n.text(step.detail)
            return L10n.text(
                "第 \(step.number) 步，\(title)。\(detail)"
            )
        }
        .joined(separator: " ")
    }
}

private struct PrincipleFlowStep: View {
    let step: PrincipleProcessStep
    let isCompact: Bool

    var body: some View {
        Group {
            if isCompact {
                VStack(alignment: .leading, spacing: 8) {
                    number
                    copy
                }
                .frame(width: 150, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    number
                    copy
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityDescription))
    }

    private var number: some View {
        Text("\(step.number)")
            .font(.callout.bold())
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(
                SlimLumaStyle.accent,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n.text(step.title))
                .font(.callout.bold())
            Text(L10n.text(step.detail))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accessibilityDescription: String {
        let title = L10n.text(step.title)
        let detail = L10n.text(step.detail)
        return L10n.text(
            "第 \(step.number) 步，\(title)。\(detail)"
        )
    }
}

private struct PrincipleCapabilityButton: View {
    let capability: PrincipleCapability
    let tint: Color
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 13) {
                capabilityIcon
                capabilityCopy
                Spacer(minLength: 8)
                capabilityChevron
            }
            .padding(15)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        isHovering
                            ? tint.opacity(0.09)
                            : SlimLumaStyle.interactiveSurface
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        tint.opacity(isHovering ? 0.46 : 0.24),
                        lineWidth: isHovering ? 1.5 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(
            Text(
                L10n.text(capability.title)
                    + L10n.labelSeparator()
                    + L10n.text(capability.detail)
            )
        )
        .accessibilityHint(
            Text(
                L10n.text(
                    "打开\(L10n.text(capability.topic.title))原理"
                )
            )
        )
    }

    private var capabilityIcon: some View {
        Image(systemName: capability.symbolName)
            .font(.title3.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 38, height: 38)
            .background(
                tint.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .accessibilityHidden(true)
    }

    private var capabilityCopy: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.text(capability.title))
                .font(.headline)
                .foregroundStyle(.primary)
            Text(L10n.text(capability.detail))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var capabilityChevron: some View {
        Image(systemName: "chevron.forward")
        .font(.caption.bold())
        .foregroundStyle(tint)
        .padding(.top, 4)
        .accessibilityHidden(true)
    }
}

private struct PrincipleSectionCard: View {
    let section: PrincipleSection

    var body: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    sectionIcon
                    sectionCopy
                }

                Divider()

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(section.facts.enumerated()), id: \.element.id) { index, fact in
                        PrincipleFactRow(fact: fact, tint: sectionTint)

                        if index < section.facts.count - 1 {
                            Divider()
                                .padding(.leading, 38)
                                .padding(.vertical, 11)
                        }
                    }
                }
            }
        }
    }

    private var sectionIcon: some View {
        Image(systemName: sectionSymbol)
            .font(.title3.weight(.semibold))
            .foregroundStyle(sectionTint)
            .frame(width: 38, height: 38)
            .background(
                sectionTint.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .accessibilityHidden(true)
    }

    private var sectionCopy: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.text(section.title))
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            Text(L10n.text(section.summary))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sectionTint: Color {
        switch section.kind {
        case .capability:
            SlimLumaStyle.accent
        case .implementation:
            SlimLumaStyle.secondaryAccent
        case .validation:
            SlimLumaStyle.success
        case .boundary:
            SlimLumaStyle.warning
        }
    }

    private var sectionSymbol: String {
        switch section.kind {
        case .capability: "sparkles.rectangle.stack"
        case .implementation: "gearshape.2"
        case .validation: "checkmark.shield"
        case .boundary: "exclamationmark.triangle"
        }
    }
}

private struct PrincipleFactRow: View {
    let fact: PrincipleFact
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            factIcon
            factCopy
        }
        .accessibilityElement(children: .combine)
    }

    private var factIcon: some View {
        Image(systemName: fact.symbolName)
            .font(.callout.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 26, height: 26)
            .background(
                tint.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .accessibilityHidden(true)
    }

    private var factCopy: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n.text(fact.title))
                .font(.callout.bold())
            Text(L10n.text(fact.detail))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

private struct PrincipleEngineStatus {
    let title: String
    let symbolName: String
    let tint: Color
}

private struct PrincipleEngineCard: View {
    let engine: PrincipleEngine
    let status: PrincipleEngineStatus

    var body: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    engineName
                    Spacer()
                    engineStatusLabel
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("核心职责")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(L10n.text(engine.responsibility))
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("缺失时")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(L10n.text(engine.missingBehavior))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityDescription))
    }

    private var accessibilityDescription: String {
        let serves = L10n.text(engine.serves)
        let statusTitle = L10n.text(status.title)
        let responsibility = L10n.text(engine.responsibility)
        let missingBehavior = L10n.text(engine.missingBehavior)
        let source =
            "\(engine.name)，服务 \(serves)，\(statusTitle)。核心职责：\(responsibility) 缺失时：\(missingBehavior)"
        return L10n.text(source)
    }

    private var engineName: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(engine.name)
                .font(.headline)
            Text(L10n.text(engine.serves))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var engineStatusLabel: some View {
        Label(L10n.text(status.title), systemImage: status.symbolName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(status.tint.opacity(0.10), in: Capsule())
    }
}

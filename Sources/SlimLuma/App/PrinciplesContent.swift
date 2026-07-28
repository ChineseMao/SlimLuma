import Foundation
import SlimLumaKit

enum PrincipleTopic: String, CaseIterable, Identifiable {
    case overview
    case images
    case video
    case pdf
    case validation
    case automation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "总览"
        case .images: "图片与动画"
        case .video: "视频"
        case .pdf: "PDF"
        case .validation: "安全验收"
        case .automation: "自动化与引擎"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .images: "photo.on.rectangle.angled"
        case .video: "film.stack"
        case .pdf: "doc.richtext"
        case .validation: "shield.checkered"
        case .automation: "gearshape.2"
        }
    }

    var subtitle: String {
        switch self {
        case .overview:
            "SlimLuma 如何把专业压缩引擎组织成一条安全、可解释的本机工作流。"
        case .images:
            "格式转换、质量、尺寸、元数据、色彩配置与动画时序是怎样处理的。"
        case .video:
            "FFmpeg 如何选择编码器、保留媒体轨道，并用 ffprobe 验收结果。"
        case .pdf:
            "qpdf、Ghostscript 与 PDFKit 如何分工，以及每种路线真正能改变什么。"
        case .validation:
            "结果为什么先写临时文件，哪些完整性问题会阻止它进入最终目录。"
        case .automation:
            "Finder、剪贴板、文件夹监控、快捷指令、一键安装与本地数据的边界。"
        }
    }
}

enum PrincipleSectionKind: String {
    case capability
    case implementation
    case validation
    case boundary
}

struct PrincipleFact: Identifiable {
    let title: String
    let detail: String
    let symbolName: String

    var id: String { title }
}

struct PrincipleSection: Identifiable {
    let title: String
    let summary: String
    let kind: PrincipleSectionKind
    let facts: [PrincipleFact]

    var id: String { title }
}

struct PrincipleProcessStep: Identifiable {
    let number: Int
    let title: String
    let detail: String

    var id: Int { number }
}

struct PrincipleCapability: Identifiable {
    let topic: PrincipleTopic
    let title: String
    let detail: String
    let symbolName: String

    var id: String { topic.id }
}

enum PrincipleEngineRuntime {
    case tool(ToolKind)
    case ffmpegWithProbe
    case system
}

struct PrincipleEngine: Identifiable {
    let id: String
    let name: String
    let serves: String
    let responsibility: String
    let missingBehavior: String
    let runtime: PrincipleEngineRuntime
}

enum PrinciplesCatalog {
    static let processSteps: [PrincipleProcessStep] = [
        PrincipleProcessStep(
            number: 1,
            title: "导入与识别",
            detail: "接收文件、文件夹、拖放或自动化来源，识别媒体类型并按标准化路径去重。"
        ),
        PrincipleProcessStep(
            number: 2,
            title: "冻结设置并选路",
            detail: "批次开始时保存设置快照，再检查格式、参数与本机引擎能否兑现。"
        ),
        PrincipleProcessStep(
            number: 3,
            title: "生成临时结果",
            detail: "专业引擎只写入目标目录中的 .slimluma 隐藏临时文件，不直接碰原件。"
        ),
        PrincipleProcessStep(
            number: 4,
            title: "重新打开并验收",
            detail: "按图片、视频或 PDF 的完整性规则重新读取，发现关键退化就拒绝输出。"
        ),
        PrincipleProcessStep(
            number: 5,
            title: "体积策略与落盘",
            detail: "默认丢弃没有变小的结果；通过后原子移动到唯一新文件名并写入本地历史。"
        )
    ]

    static let capabilities: [PrincipleCapability] = [
        PrincipleCapability(
            topic: .images,
            title: "图片与动画",
            detail: "转换格式、缩小尺寸、控制画质和元数据，并检查多帧结构与播放时序。",
            symbolName: "photo.on.rectangle.angled"
        ),
        PrincipleCapability(
            topic: .video,
            title: "视频",
            detail: "H.264、HEVC、AV1 转码，尺寸和音频控制，以及轨道与时长验收。",
            symbolName: "film.stack"
        ),
        PrincipleCapability(
            topic: .pdf,
            title: "PDF",
            detail: "结构整理、图片降采样、灰度与网页线性化，并保护关键文档结构。",
            symbolName: "doc.richtext"
        ),
        PrincipleCapability(
            topic: .validation,
            title: "结果守门",
            detail: "隐藏临时输出、类型完整性检查、体积策略和永不覆盖原件的安全落盘。",
            symbolName: "shield.checkered"
        ),
        PrincipleCapability(
            topic: .automation,
            title: "macOS 自动化",
            detail: "剪贴板、Finder、文件夹监控与快捷指令把文件送入同一条压缩链路。",
            symbolName: "folder.badge.gearshape"
        )
    ]

    static let engines: [PrincipleEngine] = [
        PrincipleEngine(
            id: "imagemagick",
            name: "ImageMagick",
            serves: "图片",
            responsibility: "格式转换、画质、尺寸、元数据、ICC 色彩配置与专业图片格式。",
            missingBehavior: "只有基础设置可由受限的 macOS 图片后备完成；其余任务会明确提示安装。",
            runtime: .tool(.imageMagick)
        ),
        PrincipleEngine(
            id: "ffmpeg",
            name: "FFmpeg + ffprobe",
            serves: "视频",
            responsibility: "FFmpeg 负责转码与音频处理；ffprobe 负责输入和输出的媒体结构检查。",
            missingBehavior: "两者缺一都不能安全执行视频任务，不会静默换成能力不足的系统方案。",
            runtime: .ffmpegWithProbe
        ),
        PrincipleEngine(
            id: "qpdf",
            name: "qpdf",
            serves: "PDF",
            responsibility: "结构预处理、对象流和 Flate 优化、部分图片重编码以及网页线性化。",
            missingBehavior: "自动模式继续评估 Ghostscript 或有限 PDFKit；显式选择 qpdf 时直接报错。",
            runtime: .tool(.qpdf)
        ),
        PrincipleEngine(
            id: "ghostscript",
            name: "Ghostscript",
            serves: "PDF",
            responsibility: "重写 PDF，并为图片型文档执行质量、DPI、灰度和深度压缩。",
            missingBehavior: "自动模式退到 qpdf 或有限 PDFKit；显式选择 Ghostscript 时直接报错。",
            runtime: .tool(.ghostscript)
        ),
        PrincipleEngine(
            id: "pdfkit",
            name: "PDFKit",
            serves: "PDF 后备与验收",
            responsibility: "在没有专业 PDF 引擎时做有限系统重写，并读取关键文档结构用于比较。",
            missingBehavior: "macOS 系统内置；它不提供图片降采样，也不能生成网页线性化。",
            runtime: .system
        ),
        PrincipleEngine(
            id: "apple-frameworks",
            name: "ImageIO / AVFoundation",
            serves: "结果验收",
            responsibility: "ImageIO 重新解码图片和动画；AVFoundation只提供系统预览兼容性信号。",
            missingBehavior: "macOS 系统内置；视频有效性仍以 ffprobe 为准，不能用 Quick Look 能否预览代替。",
            runtime: .system
        )
    ]

    static func sections(for topic: PrincipleTopic) -> [PrincipleSection] {
        switch topic {
        case .overview:
            overviewSections
        case .images:
            imageSections
        case .video:
            videoSections
        case .pdf:
            pdfSections
        case .validation:
            validationSections
        case .automation:
            automationSections
        }
    }

    private static let overviewSections: [PrincipleSection] = [
        PrincipleSection(
            title: "SlimLuma 真正负责什么",
            summary: "它不是另一套自研编解码器，而是把成熟引擎组织成一条可控的本机处理流水线。",
            kind: .implementation,
            facts: [
                PrincipleFact(
                    title: "工作流层",
                    detail: "负责导入、参数管理、批量调度、取消、临时输出、完整性检查、安全命名和历史记录。",
                    symbolName: "point.3.connected.trianglepath.dotted"
                ),
                PrincipleFact(
                    title: "专业处理层",
                    detail: "ImageMagick、FFmpeg、qpdf、Ghostscript 和 macOS 系统框架负责实际编解码或文档重写。",
                    symbolName: "shippingbox"
                ),
                PrincipleFact(
                    title: "进程边界",
                    detail: "文件路径和参数作为独立参数交给 Process，不拼接为 Shell 命令；任务取消时会终止受管理的子进程。",
                    symbolName: "terminal"
                )
            ]
        ),
        PrincipleSection(
            title: "丰富功能如何保持一致",
            summary: "无论文件来自哪里，最终都进入同一个队列和同一套安全规则。",
            kind: .capability,
            facts: [
                PrincipleFact(
                    title: "混合批量",
                    detail: "图片、视频和 PDF 可以混合加入；队列允许 1–6 个并发任务，开始时冻结整批设置。",
                    symbolName: "square.stack.3d.up"
                ),
                PrincipleFact(
                    title: "预设与输出",
                    detail: "内置和自定义预设统一保存图片、视频、PDF 与输出规则；可输出到原件旁或指定目录。",
                    symbolName: "slider.horizontal.3"
                ),
                PrincipleFact(
                    title: "结果闭环",
                    detail: "完成后可定位结果、重新加入原文件、查看体积变化、复制路径或用 Quick Look 并排对比。",
                    symbolName: "arrow.left.and.right"
                )
            ]
        ),
        PrincipleSection(
            title: "正确理解“成功”",
            summary: "界面不会把未达到体积目标、降级或安全风险包装成普通成功。",
            kind: .boundary,
            facts: [
                PrincipleFact(
                    title: "验证通过不是 100% 等价",
                    detail: "它只表示当前自动检查项没有发现关键退化，不代表像素、听感、版式或交互语义完全相同。",
                    symbolName: "exclamationmark.shield"
                ),
                PrincipleFact(
                    title: "未生成不等于失败",
                    detail: "结果有效但没有比原件更小时，默认会删除临时结果并显示“未生成”；也可显式保留并收到警告。",
                    symbolName: "equal.circle"
                ),
                PrincipleFact(
                    title: "当前进度粒度",
                    detail: "应用展示每个文件的等待、处理中和结果状态，不宣称拥有编码器内部的逐帧百分比进度；队列本身不跨重启保存。",
                    symbolName: "list.bullet.rectangle"
                )
            ]
        )
    ]

    private static let imageSections: [PrincipleSection] = [
        PrincipleSection(
            title: "可以调整什么",
            summary: "图片设置覆盖格式、质量、尺寸、无损路径、元数据、色彩配置和编码强度。",
            kind: .capability,
            facts: [
                PrincipleFact(
                    title: "输入与输出格式",
                    detail: "可识别 JPEG、PNG、GIF、TIFF、BMP、WebP、AVIF、HEIC/HEIF、JPEG 2000；输出可保持格式或转换为 JPEG、PNG、WebP、AVIF、HEIC。",
                    symbolName: "photo.stack"
                ),
                PrincipleFact(
                    title: "尺寸与画质",
                    detail: "最大宽高保持比例且只缩小不放大；质量参数控制有损编码，WebP/AVIF 还可调整编码强度。",
                    symbolName: "aspectratio"
                ),
                PrincipleFact(
                    title: "元数据与 ICC",
                    detail: "可保留全部、移除私人资料或移除全部；在“全部移除但保留 ICC”时会先提取色彩配置、清理后再恢复。",
                    symbolName: "paintpalette"
                )
            ]
        ),
        PrincipleSection(
            title: "引擎怎样执行",
            summary: "优先用 ImageMagick 完成专业处理；系统后备只接受自己确实能兑现的设置。",
            kind: .implementation,
            facts: [
                PrincipleFact(
                    title: "ImageMagick 主路线",
                    detail: "先纠正方向，再按比例缩小、重编码和处理 profile；PNG、WebP 与 AVIF 的设置会映射为对应引擎参数。",
                    symbolName: "wand.and.stars"
                ),
                PrincipleFact(
                    title: "图片为什么会变小",
                    detail: "缩小尺寸会减少像素数量；有损编码会用质量参数舍弃不敏感的细节；更高效的格式、无损数据流重排和移除元数据也能降低占用。",
                    symbolName: "arrow.down.right"
                ),
                PrincipleFact(
                    title: "受限的 macOS 后备",
                    detail: "ImageMagick 缺失时，只在 sips 能完成当前基础格式、质量和尺寸要求时继续；高级格式、动画或精细元数据要求会被拦截。",
                    symbolName: "macwindow"
                ),
                PrincipleFact(
                    title: "无损的真实含义",
                    detail: "PNG、WebP 和部分保持原格式可走无损编码；JPEG、HEIC、AVIF 会在执行前拒绝“无损”。缩放、自动旋转或清理元数据仍会改变文件。",
                    symbolName: "arrow.triangle.2.circlepath"
                )
            ]
        ),
        PrincipleSection(
            title: "动画如何验收",
            summary: "动画图片不是只看第一帧；输出会被逐帧重新打开。",
            kind: .validation,
            facts: [
                PrincipleFact(
                    title: "安全转换范围",
                    detail: "检测到多帧输入时，只开放保持原格式或转 WebP，避免转成 JPEG、PNG、AVIF、HEIC 时静默丢失动画。",
                    symbolName: "rectangle.stack"
                ),
                PrincipleFact(
                    title: "帧与时序",
                    detail: "检查全部帧都能解码、帧数不变；GIF/WebP 还逐帧比较播放时长，容差为 20 毫秒或原帧时长 5% 中较大者。",
                    symbolName: "timer"
                ),
                PrincipleFact(
                    title: "循环设置",
                    detail: "原动画存在循环元数据而输出缺失，或可读取的循环次数发生变化时，临时结果不会落盘。",
                    symbolName: "repeat"
                )
            ]
        ),
        PrincipleSection(
            title: "当前边界",
            summary: "结构安全检查不能替代专业的主观画质评审。",
            kind: .boundary,
            facts: [
                PrincipleFact(
                    title: "不做像素级画质评分",
                    detail: "当前不计算 SSIM、色差、清晰度或人眼主观评分；重要作品仍应使用前后对比检查。",
                    symbolName: "eye.trianglebadge.exclamationmark"
                ),
                PrincipleFact(
                    title: "能力取决于本机构建",
                    detail: "扩展名被识别不代表当前 ImageMagick 一定包含对应 delegate；实际解码和编码失败会如实显示。",
                    symbolName: "puzzlepiece.extension"
                ),
                PrincipleFact(
                    title: "元数据不是取证擦除",
                    detail: "“移除私人资料”会移除 EXIF、XMP、IPTC profile，但不会识别画面中的人脸、地址或文字；重编码也可能重写技术元数据。",
                    symbolName: "person.crop.rectangle.badge.xmark"
                )
            ]
        )
    ]

    private static let videoSections: [PrincipleSection] = [
        PrincipleSection(
            title: "编码与设置能力",
            summary: "视频压缩以 FFmpeg 为核心，面向常见容器和现代编码格式。",
            kind: .capability,
            facts: [
                PrincipleFact(
                    title: "常见输入",
                    detail: "识别 MP4、MOV、M4V、MKV、WebM、AVI、MTS/M2TS、MPEG、3GP、FLV、WMV 等扩展名。",
                    symbolName: "play.rectangle.on.rectangle"
                ),
                PrincipleFact(
                    title: "三种视频编码",
                    detail: "可选 H.264、HEVC/H.265 与 AV1，并可调画质、速度、最大尺寸、帧率、音频码率和元数据清理。",
                    symbolName: "video"
                ),
                PrincipleFact(
                    title: "速度与体积",
                    detail: "软件编码通常越慢越有机会得到更小结果；VideoToolbox 更偏向速度、能耗和实时吞吐。",
                    symbolName: "gauge.with.dots.needle.67percent"
                )
            ]
        ),
        PrincipleSection(
            title: "实际编码路线",
            summary: "编码器和参数会根据用户设置以及当前 FFmpeg 构建动态确定。",
            kind: .implementation,
            facts: [
                PrincipleFact(
                    title: "H.264 与 HEVC",
                    detail: "硬件选项请求 Apple VideoToolbox；软件路线使用 libx264 或 libx265 与 CRF。命令允许回退，因此不承诺每次一定由硬件完成。",
                    symbolName: "cpu"
                ),
                PrincipleFact(
                    title: "AV1",
                    detail: "运行前读取 FFmpeg 编码器列表，优先 libsvtav1，其次 libaom-av1；当前只做软件编码并输出 MKV。",
                    symbolName: "aqi.medium"
                ),
                PrincipleFact(
                    title: "视频为什么会变小",
                    detail: "现代编码器利用画面内和连续帧之间的重复信息；提高压缩强度、缩小分辨率或帧率、降低音频码率都会减少数据，但也会改变质量或流畅度。",
                    symbolName: "arrow.down.right"
                ),
                PrincipleFact(
                    title: "容器与媒体流",
                    detail: "画面缩放保持比例、不放大并对齐偶数尺寸；音频转 AAC，MP4 字幕转 mov_text，MKV 字幕尽量复制，MP4 开启 faststart。",
                    symbolName: "shippingbox.and.arrow.backward"
                )
            ]
        ),
        PrincipleSection(
            title: "ffprobe 结果验收",
            summary: "视频任务同时需要 FFmpeg 和配套 ffprobe；后者不是可选的装饰。",
            kind: .validation,
            facts: [
                PrincipleFact(
                    title: "重新探测",
                    detail: "输入和输出都由 ffprobe 读取，比较视频、音频、字幕轨道、章节、语言与默认/强制标记、字幕包数量和 HDR 色彩标记。",
                    symbolName: "waveform.path.ecg.rectangle"
                ),
                PrincipleFact(
                    title: "时长容差",
                    detail: "输出时长与原件差异超过 0.5 秒或原时长 1% 中较大者时，会被判为完整性风险。",
                    symbolName: "clock.badge.exclamationmark"
                ),
                PrincipleFact(
                    title: "系统预览只是信号",
                    detail: "AVFoundation 只记录 macOS 是否容易预览；MKV/WebM 即使 Quick Look 不支持，也可能是有效视频，不会因此被误删。",
                    symbolName: "macwindow.badge.plus"
                )
            ]
        ),
        PrincipleSection(
            title: "当前边界",
            summary: "轨道数量与时长守门能发现明显结构回归，但不等于内容级质量分析。",
            kind: .boundary,
            facts: [
                PrincipleFact(
                    title: "第一条视频轨",
                    detail: "当前命令编码第一条视频轨并保留音频与字幕；多视频轨输入会因数量减少而被验收拦截，不会假装成功。",
                    symbolName: "rectangle.stack.badge.minus"
                ),
                PrincipleFact(
                    title: "未比较内容质量",
                    detail: "当前不逐帧比较画面，不评分音质、音画同步或逐条字幕时序；数据轨、封面和附件也不在保留范围。",
                    symbolName: "waveform.badge.exclamationmark"
                ),
                PrincipleFact(
                    title: "目标体积边界",
                    detail: "H.264 与 HEVC 可按目标大小执行两遍软件编码，并为音频、字幕和容器预留空间；AV1 与单独音频压缩暂不支持目标体积。",
                    symbolName: "target"
                )
            ]
        )
    ]

    private static let pdfSections: [PrincipleSection] = [
        PrincipleSection(
            title: "四种模式与实际能力",
            summary: "PDF 的“无损、均衡、极致、自定义”决定处理目标，但真正能力还取决于所选后端。",
            kind: .capability,
            facts: [
                PrincipleFact(
                    title: "无损整理",
                    detail: "自动模式优先 qpdf 整理对象和数据流，缺失时用 PDFKit 有限重写；它不主动降低图片质量，但不是字节级相同。",
                    symbolName: "arrow.triangle.2.circlepath.doc.on.clipboard"
                ),
                PrincipleFact(
                    title: "均衡与极致",
                    detail: "自动模式优先 Ghostscript，适合包含大量图片的文档；可改变图片质量、DPI、灰度和 PDFSETTINGS 档位。",
                    symbolName: "dial.medium"
                ),
                PrincipleFact(
                    title: "网页快速打开",
                    detail: "qpdf 可用时负责线性化；仅 Ghostscript 时由它尝试。PDFKit 明确不支持此能力，不能伪造成功。",
                    symbolName: "globe"
                )
            ]
        ),
        PrincipleSection(
            title: "自动与显式路由",
            summary: "“自动”按模式和本机能力组合引擎；显式选择则尊重用户决定，不会静默换路。",
            kind: .implementation,
            facts: [
                PrincipleFact(
                    title: "完整强力链路",
                    detail: "qpdf 结构预处理 → Ghostscript 重写和图片压缩 → 按需 qpdf 线性化 → PDFKit 完整性比较。",
                    symbolName: "arrow.forward.circle"
                ),
                PrincipleFact(
                    title: "PDF 为什么会变小",
                    detail: "qpdf 会重组对象流并重新压缩可压缩数据；Ghostscript 还能降低内嵌图片的像素密度、质量或色彩复杂度。文字型 PDF 通常收益较小，扫描件通常更明显。",
                    symbolName: "arrow.down.right"
                ),
                PrincipleFact(
                    title: "没有 Ghostscript",
                    detail: "自动非无损模式可退到 qpdf，后者能优化对象和部分内嵌图片编码，但不会按 DPI 降采样，也不会转灰度。",
                    symbolName: "arrow.down.right.circle"
                ),
                PrincipleFact(
                    title: "只有 PDFKit",
                    detail: "系统后备只做有限重写，通常压缩幅度有限；不会声称完成深度图片压缩或网页线性化。",
                    symbolName: "macwindow"
                ),
                PrincipleFact(
                    title: "显式引擎",
                    detail: "明确选择 qpdf 或 Ghostscript 而该引擎缺失时会直接报错并引导安装，不偷偷使用另一种结果语义。",
                    symbolName: "hand.raised"
                )
            ]
        ),
        PrincipleSection(
            title: "PDF 结构验收",
            summary: "输出会用 PDFKit 和文件结构检查器与原件比较，关键风险会阻止落盘。",
            kind: .validation,
            facts: [
                PrincipleFact(
                    title: "页面与导航结构",
                    detail: "比较页数、书签数量、非表单批注与链接数量；数量减少会被视为重要风险。",
                    symbolName: "list.bullet.rectangle.portrait"
                ),
                PrincipleFact(
                    title: "表单、签名与加密",
                    detail: "比较表单字段、PDFKit 可识别的签名字段和加密状态；检测到签名字段的重写结果会被拒绝。",
                    symbolName: "signature"
                ),
                PrincipleFact(
                    title: "文本与线性化",
                    detail: "检查可提取文本是否出现灾难性下降；用户要求网页快速打开时，还会验证文件确实带线性化标记。",
                    symbolName: "text.magnifyingglass"
                )
            ]
        ),
        PrincipleSection(
            title: "当前边界",
            summary: "PDF 是高度复杂的容器，结构数量检查不能证明全部语义和视觉效果相同。",
            kind: .boundary,
            facts: [
                PrincipleFact(
                    title: "不做页面渲染对比",
                    detail: "当前不比较字体替换、版式、图片清晰度、颜色、图层、标签结构、附件、JavaScript 或页面视觉等价。",
                    symbolName: "doc.text.magnifyingglass"
                ),
                PrincipleFact(
                    title: "签名不是可保留能力",
                    detail: "签名字段检测发生在输出验收阶段，且受 PDFKit 可识别范围限制；不能把任何 PDF 重写宣传为保留数字签名。",
                    symbolName: "exclamationmark.seal"
                ),
                PrincipleFact(
                    title: "“无损”不是不重写",
                    detail: "qpdf 会重写文件结构；显式 Ghostscript 的无损档位也仍会重写，只是省略自定义降采样、灰度与图片重编码参数。",
                    symbolName: "doc.badge.ellipsis"
                ),
                PrincipleFact(
                    title: "加密文档",
                    detail: "密码只驻留当前队列内存并通过权限受限的临时文件交给 qpdf；处理前解锁，完成后复制原加密策略并再次解锁验收，临时凭据随后清理。",
                    symbolName: "lock.doc"
                )
            ]
        )
    ]

    private static let validationSections: [PrincipleSection] = [
        PrincipleSection(
            title: "不覆盖原件",
            summary: "输出安全从命名和写入位置开始，而不是等引擎完成后再补救。",
            kind: .implementation,
            facts: [
                PrincipleFact(
                    title: "隐藏临时文件",
                    detail: "引擎先在最终目录写入 .slimluma-UUID 临时文件；不会把原件当作输出，也不直接写最终名称。",
                    symbolName: "eye.slash"
                ),
                PrincipleFact(
                    title: "唯一最终名称",
                    detail: "默认使用 -slim 后缀，遇到同名会继续编号；并发完成时由串行化的最终落盘逻辑再次确认目标没有冲突。",
                    symbolName: "doc.on.doc"
                ),
                PrincipleFact(
                    title: "原子完成",
                    detail: "只有通过验收的临时文件才移动到最终路径；失败、取消或安全拦截时会尝试清理临时结果。",
                    symbolName: "checkmark.shield"
                )
            ]
        ),
        PrincipleSection(
            title: "分类型的验收规则",
            summary: "通用检查确认文件存在、非空且是普通文件，再进入媒体专属比较。",
            kind: .validation,
            facts: [
                PrincipleFact(
                    title: "图片",
                    detail: "ImageIO 重新解码所有帧；动画还检查帧数、逐帧时长和可读取的循环设置。",
                    symbolName: "photo.badge.checkmark"
                ),
                PrincipleFact(
                    title: "视频",
                    detail: "ffprobe 检查可读性、时长以及视频、音频、字幕轨道数量；AVFoundation 不负责最终有效性裁决。",
                    symbolName: "play.rectangle.on.rectangle.circle"
                ),
                PrincipleFact(
                    title: "PDF",
                    detail: "比较页数、书签、批注、链接、表单、签名字段、加密、文本提取和要求的线性化标记。",
                    symbolName: "doc.text.magnifyingglass"
                )
            ]
        ),
        PrincipleSection(
            title: "体积与用户复核",
            summary: "结构安全和压缩收益是两个独立关口。",
            kind: .capability,
            facts: [
                PrincipleFact(
                    title: "默认只留更小结果",
                    detail: "验收通过但大小相同或更大时，默认删除临时文件并记录“未生成”，避免制造没有收益的副本。",
                    symbolName: "arrow.down.circle"
                ),
                PrincipleFact(
                    title: "允许保留更大结果",
                    detail: "用户可在输出设置中显式开启；结果会保留，但队列和历史都会标出增大或大小不变。",
                    symbolName: "exclamationmark.circle"
                ),
                PrincipleFact(
                    title: "Quick Look 前后对比",
                    detail: "并排预览用于用户检查重要文件，它不是像素差异、SSIM 或客观画质评分，预览能力也取决于 macOS。",
                    symbolName: "rectangle.split.2x1"
                )
            ]
        ),
        PrincipleSection(
            title: "安全承诺的边界",
            summary: "SlimLuma 会拦截已检测到的问题，但不会把有限检查描述成绝对保证。",
            kind: .boundary,
            facts: [
                PrincipleFact(
                    title: "尽力清理",
                    detail: "正常失败和取消会清理临时文件；进程崩溃、系统断电或文件系统异常时不能承诺绝无残留。",
                    symbolName: "bolt.trianglebadge.exclamationmark"
                ),
                PrincipleFact(
                    title: "修改时间",
                    detail: "保留 Finder 修改时间是尽力操作；时间属性写入失败不会让已经验证的压缩结果反过来失败。",
                    symbolName: "calendar.badge.clock"
                ),
                PrincipleFact(
                    title: "结构不等于感知质量",
                    detail: "图片不做像素质量评分，视频不做画面与音频内容比较，PDF 不做页面渲染等价验证。",
                    symbolName: "eye.trianglebadge.exclamationmark"
                )
            ]
        )
    ]

    private static let automationSections: [PrincipleSection] = [
        PrincipleSection(
            title: "同一条导入链路",
            summary: "自动化只负责把可控的本地文件加入队列，不另建一套绕过安全检查的压缩逻辑。",
            kind: .capability,
            facts: [
                PrincipleFact(
                    title: "剪贴板与 Finder",
                    detail: "可导入 Finder 复制的文件，以及 PNG/TIFF 位图；还支持“打开方式”和需要在系统设置中启用一次的 Finder 服务。",
                    symbolName: "doc.on.clipboard"
                ),
                PrincipleFact(
                    title: "文件夹监控",
                    detail: "每 2 秒轮询，文件大小和修改时间连续两个快照稳定后才加入；可递归、导入已有文件并自动开始。",
                    symbolName: "folder.badge.gearshape"
                ),
                PrincipleFact(
                    title: "快捷指令",
                    detail: "macOS 15+ 提供“添加到 SlimLuma 压缩队列”动作；原子 JSON 回执让稍后打开的 App 仍能恢复请求。",
                    symbolName: "square.stack.3d.up.badge.automatic"
                )
            ]
        ),
        PrincipleSection(
            title: "监控与回执防护",
            summary: "自动化输入会做路径归属、稳定性和防循环检查。",
            kind: .implementation,
            facts: [
                PrincipleFact(
                    title: "防止压缩自己的输出",
                    detail: "监控忽略隐藏文件、符号链接、自定义输出目录、当前输出后缀和旧版 -slim 后缀。",
                    symbolName: "arrow.triangle.2.circlepath.circle"
                ),
                PrincipleFact(
                    title: "安全的应用副本",
                    detail: "剪贴板和快捷指令输入先复制到 Application Support 的私有批次目录，避免临时来源在任务开始前失效。",
                    symbolName: "lock.square.stack"
                ),
                PrincipleFact(
                    title: "不信任任意回执路径",
                    detail: "批次目录、回执和文件都必须属于预期的直接子目录并拒绝符号链接；损坏或缺文件的回执会被隔离。",
                    symbolName: "checkmark.shield"
                )
            ]
        ),
        PrincipleSection(
            title: "一键安装如何工作",
            summary: "安装动作只在用户明确点击后发生，并复用系统上已经存在的 Homebrew。",
            kind: .implementation,
            facts: [
                PrincipleFact(
                    title: "发现本机工具",
                    detail: "依次检查 App 的 Tools 目录、Homebrew、PATH、MacPorts 与系统路径；FFmpeg 还会寻找同目录的 ffprobe。",
                    symbolName: "magnifyingglass"
                ),
                PrincipleFact(
                    title: "直接调用 Homebrew",
                    detail: "把 formula 名称作为独立参数交给 brew install，不经过 Shell；完成后重新扫描，命令成功但工具不可见仍判为未完成。",
                    symbolName: "shippingbox.fill"
                ),
                PrincipleFact(
                    title: "Homebrew 边界",
                    detail: "SlimLuma 不代替用户执行 Homebrew 自身的安装脚本；未检测到时打开 brew.sh 并持续检测，Homebrew 就绪后自动续装已选择的引擎。",
                    symbolName: "network"
                )
            ]
        ),
        PrincipleSection(
            title: "本地数据与隐私",
            summary: "媒体压缩不上传文件，但“本地处理”不等于完全不留下本地记录。",
            kind: .boundary,
            facts: [
                PrincipleFact(
                    title: "什么留在本机",
                    detail: "设置、预设和自动化配置保存在 UserDefaults；最多 500 条历史保存在 Application Support 的本地 JSON。",
                    symbolName: "internaldrive"
                ),
                PrincipleFact(
                    title: "导入副本会保留",
                    detail: "已完成的剪贴板或快捷指令批次当前可能保留在 Application Support，因为默认结果可能生成在副本旁；清空历史不会删除这些副本或结果。",
                    symbolName: "doc.on.doc.fill"
                ),
                PrincipleFact(
                    title: "什么时候会联网",
                    detail: "压缩过程不上传媒体文件。只有用户主动打开许可网站、brew.sh 或执行 Homebrew 安装时，浏览器或 Homebrew 才会访问网络。",
                    symbolName: "network.slash"
                ),
                PrincipleFact(
                    title: "不是加密保险箱",
                    detail: "历史路径和导入副本没有由 SlimLuma 额外加密，仍依赖 macOS 账户、文件权限和磁盘加密保护。",
                    symbolName: "lock.open.trianglebadge.exclamationmark"
                )
            ]
        ),
        PrincipleSection(
            title: "自动化当前边界",
            summary: "这些能力依赖 App 运行状态和对应的 macOS 系统入口。",
            kind: .boundary,
            facts: [
                PrincipleFact(
                    title: "不是后台守护进程",
                    detail: "文件夹监控是 App 内每 2 秒轮询，不是实时 FSEvents 服务；退出 SlimLuma 后不会继续监控。",
                    symbolName: "power"
                ),
                PrincipleFact(
                    title: "稳定快照不是内容证明",
                    detail: "连续两次大小和时间不变只能降低“文件仍在复制”的风险，真正的文件有效性仍由引擎和输出验收决定。",
                    symbolName: "clock.badge.questionmark"
                ),
                PrincipleFact(
                    title: "平台要求",
                    detail: "快捷指令动作要求 macOS 15+ 并会以前台方式打开 SlimLuma；Finder 服务需要用户在系统设置中启用一次。",
                    symbolName: "macbook"
                )
            ]
        )
    ]
}

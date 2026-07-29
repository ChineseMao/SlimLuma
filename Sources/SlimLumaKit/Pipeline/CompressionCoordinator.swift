import Darwin
import Foundation
import PDFKit

@_silgen_name("fcntl")
private func slimLumaFcntlGetPath(
    _ descriptor: Int32,
    _ command: Int32,
    _ buffer: UnsafeMutableRawPointer
) -> Int32

public final class CompressionCoordinator: @unchecked Sendable {
    private let registry: ToolRegistry
    private let runner: ProcessRunner
    private let outputPlanner: OutputPlanner
    private let outputFinalizer = OutputFinalizer()

    public init(
        registry: ToolRegistry = ToolRegistry(),
        runner: ProcessRunner = ProcessRunner(),
        outputPlanner: OutputPlanner = OutputPlanner()
    ) {
        self.registry = registry
        self.runner = runner
        self.outputPlanner = outputPlanner
        outputPlanner.removeStaleTemporaryWorkspaces()
    }

    public func compress(
        inputURL: URL,
        settings: CompressionSettings,
        pdfPassword: String? = nil,
        progressHandler: (@Sendable (CompressionProgress) -> Void)? = nil
    ) async throws -> CompressionResult {
        do {
            return try await performCompression(
                inputURL: inputURL,
                settings: settings,
                pdfPassword: pdfPassword,
                progressHandler: progressHandler
            )
        } catch is CancellationError {
            throw CompressionError.cancelled
        }
    }

    private func performCompression(
        inputURL: URL,
        settings: CompressionSettings,
        pdfPassword: String?,
        progressHandler: (@Sendable (CompressionProgress) -> Void)?
    ) async throws -> CompressionResult {
        try Task.checkCancellation()
        progressHandler?(
            CompressionProgress(
                fractionCompleted: 0.01,
                stage: "正在检查文件"
            )
        )

        let kind = MediaKind.detect(url: inputURL)
        guard kind != .unknown else {
            throw CompressionError.unsupportedFile(inputURL.lastPathComponent)
        }

        try validateInputCompatibility(
            inputURL: inputURL,
            kind: kind,
            settings: settings
        )
        if let pdfPassword,
           pdfPassword.contains(where: \.isNewline) {
            throw CompressionError.invalidSettings("PDF 密码不能包含换行符")
        }
        try Task.checkCancellation()

        let startedAt = Date()
        let imageRuntime: ImageRuntime?
        if kind == .image {
            imageRuntime = try await prepareImageRuntime(
                inputURL: inputURL,
                settings: settings.image
            )
        } else {
            imageRuntime = nil
        }
        try Task.checkCancellation()

        let videoRuntime: VideoRuntime?
        if kind == .video {
            videoRuntime = try await prepareVideoRuntime(
                inputURL: inputURL,
                settings: settings.video
            )
        } else {
            videoRuntime = nil
        }
        try Task.checkCancellation()

        let originalBytes = try fileSize(at: inputURL)
        try Task.checkCancellation()
        _ = try outputPlanner.destinationURL(
            for: inputURL,
            kind: kind,
            settings: settings
        )
        try Task.checkCancellation()
        let temporaryWorkspace = try outputPlanner.temporaryWorkspace(
            for: inputURL,
            kind: kind,
            settings: settings
        )
        let temporaryURL = temporaryWorkspace.outputURL

        defer {
            try? temporaryWorkspace.remove()
        }

        try Task.checkCancellation()
        let invocation = try makeInvocation(
            kind: kind,
            inputURL: inputURL,
            outputURL: temporaryURL,
            settings: settings,
            imageRuntime: imageRuntime,
            videoRuntime: videoRuntime,
            pdfPassword: pdfPassword
        )
        defer {
            for prefix in invocation.cleanupPrefixes {
                removeFiles(withPrefix: prefix)
            }
        }

        switch invocation.execution {
        case .processes(let processes):
            for (processIndex, process) in processes.enumerated() {
                try Task.checkCancellation()
                let processResult: ProcessResult
                let baseFraction = 0.08
                    + 0.70 * Double(processIndex)
                    / Double(max(processes.count, 1))
                let processSpan = 0.70 / Double(max(processes.count, 1))
                progressHandler?(
                    CompressionProgress(
                        fractionCompleted: baseFraction,
                        stage: process.progressStage
                    )
                )
                let progressAccumulator = process.progressDurationSeconds.map {
                    FFmpegProgressAccumulator(
                        durationSeconds: $0,
                        baseFraction: baseFraction,
                        span: processSpan,
                        stage: process.progressStage,
                        handler: progressHandler
                    )
                }
                do {
                    processResult = try await runner.run(
                        executableURL: process.executableURL,
                        arguments: process.arguments,
                        environment: process.environment,
                        onOutput: { event in
                            guard event.channel == .standardOutput else {
                                return
                            }
                            progressAccumulator?.consume(event.text)
                        }
                    )
                } catch is CancellationError {
                    throw CompressionError.cancelled
                } catch let error as CompressionError {
                    throw error
                } catch {
                    throw CompressionError.processFailed(
                        tool: process.toolName,
                        exitCode: -1,
                        message: error.localizedDescription
                    )
                }
                try Task.checkCancellation()

                guard process.acceptedExitCodes.contains(
                    processResult.exitCode
                ) else {
                    let diagnostic = conciseDiagnostic(
                        processResult.standardError.isEmpty
                            ? processResult.standardOutput
                            : processResult.standardError
                    )
                    throw CompressionError.processFailed(
                        tool: process.toolName,
                        exitCode: processResult.exitCode,
                        message: diagnostic
                    )
                }
                progressHandler?(
                    CompressionProgress(
                        fractionCompleted: baseFraction + processSpan,
                        stage: process.progressStage
                    )
                )
            }

        case .nativePDFKit:
            try Task.checkCancellation()
            try NativePDFOptimizer.rewrite(
                inputURL: inputURL,
                outputURL: temporaryURL
            )
            try Task.checkCancellation()
        }

        if kind == .pdf {
            for intermediateURL in invocation.intermediateURLs {
                try? FileManager.default.removeItem(at: intermediateURL)
            }
        }

        var refinementWarning: String?
        if kind == .image,
           settings.image.targetSizeBytes != nil,
           let imageRuntime {
            refinementWarning = try await refineImageToTarget(
                inputURL: inputURL,
                outputURL: temporaryURL,
                settings: settings.image,
                imageRuntime: imageRuntime,
                restoredICCProfileURL: invocation.intermediateURLs.first {
                    $0.pathExtension.lowercased() == "icc"
                },
                progressHandler: progressHandler
            )
        }

        try Task.checkCancellation()
        progressHandler?(
            CompressionProgress(
                fractionCompleted: 0.90,
                stage: "正在验证完整性"
            )
        )
        try await FileValidator.validate(
            url: temporaryURL,
            kind: kind,
            sourceURL: inputURL,
            ffprobeURL: videoRuntime?.ffprobeURL,
            processRunner: runner,
            videoExpectations: VideoIntegrityExpectations(
                preserveChapters: settings.video.preserveChapters
            ),
            pdfPassword: pdfPassword
        )
        try Task.checkCancellation()
        if kind == .pdf {
            try Task.checkCancellation()
            let report: PDFIntegrityReport
            do {
                report = try PDFIntegrityChecker().compare(
                    originalURL: inputURL,
                    compressedURL: temporaryURL,
                    expectations: PDFIntegrityExpectations(
                        requireLinearization:
                            settings.pdf.linearizeForWeb
                            && invocation.supportsLinearization
                    ),
                    password: pdfPassword
                )
            } catch {
                throw CompressionError.outputInvalid(
                    "无法完成 PDF 完整性检查：\(error.localizedDescription)"
                )
            }
            try Task.checkCancellation()
            if report.hasCriticalRisk {
                throw CompressionError.outputInvalid(
                    pdfIntegrityMessage(report)
                )
            }
        }
        try Task.checkCancellation()
        let outputBytes = try fileSize(at: temporaryURL)
        let elapsed = Date().timeIntervalSince(startedAt)
        let targetSizeWarning = targetSizeWarning(
            kind: kind,
            outputBytes: outputBytes,
            settings: settings
        )

        if outputBytes >= originalBytes, !settings.output.keepLargerFiles {
            try Task.checkCancellation()
            let skippedWarning: String
            if kind == .pdf, invocation.engineID == .macOSPDFKit {
                skippedWarning =
                    "PDFKit 只能做无损重写，这次结果没有变小，因此未生成文件。安装 Ghostscript 后重试可进行图片降采样。"
            } else {
                skippedWarning = "压缩结果没有变小，已按设置丢弃"
            }
            return CompressionResult(
                inputURL: inputURL,
                outputURL: nil,
                mediaKind: kind,
                engineName: invocation.engineName,
                engineID: invocation.engineID,
                originalBytes: originalBytes,
                outputBytes: nil,
                duration: elapsed,
                skippedBecauseLarger: true,
                warning: skippedWarning
            )
        }

        try Task.checkCancellation()
        progressHandler?(
            CompressionProgress(
                fractionCompleted: 0.97,
                stage: "正在保存结果"
            )
        )
        let finalURL = try await outputFinalizer.finalize(
            temporaryURL: temporaryURL,
            inputURL: inputURL,
            kind: kind,
            settings: settings,
            planner: outputPlanner
        )

        if settings.output.preserveModificationDate,
           let modificationDate = try? inputURL.resourceValues(
               forKeys: [.contentModificationDateKey]
           ).contentModificationDate {
            try? FileManager.default.setAttributes(
                [.modificationDate: modificationDate],
                ofItemAtPath: finalURL.path
            )
        }

        let retainedSizeWarning: String?
        if outputBytes > originalBytes {
            let increase = originalBytes > 0
                ? (Double(outputBytes - originalBytes) / Double(originalBytes)) * 100
                : 0
            retainedSizeWarning =
                "结果增大 \(String(format: "%.0f", increase))%，已按“保留没有变小的结果”设置保留"
        } else if outputBytes == originalBytes {
            retainedSizeWarning =
                "结果大小未减少，已按“保留没有变小的结果”设置保留"
        } else {
            retainedSizeWarning = nil
        }
        let resultWarning = [
            invocation.warning,
            refinementWarning,
            targetSizeWarning,
            retainedSizeWarning
        ]
            .compactMap { $0 }
            .joined(separator: "；")

        progressHandler?(
            CompressionProgress(
                fractionCompleted: 1,
                stage: "已完成",
                estimatedRemainingSeconds: 0
            )
        )
        return CompressionResult(
            inputURL: inputURL,
            outputURL: finalURL,
            mediaKind: kind,
            engineName: invocation.engineName,
            engineID: invocation.engineID,
            originalBytes: originalBytes,
            outputBytes: outputBytes,
            duration: elapsed,
            skippedBecauseLarger: false,
            warning: resultWarning.isEmpty ? nil : resultWarning
        )
    }

    public func cancelAll() async {
        await runner.cancelAll()
    }

    public func pauseAll() async {
        await runner.pauseAll()
    }

    public func resumeAll() async {
        await runner.resumeAll()
    }

    private func prepareVideoRuntime(
        inputURL: URL,
        settings: VideoCompressionSettings
    ) async throws -> VideoRuntime {
        try Task.checkCancellation()
        guard let ffmpegURL = registry.locate(.ffmpeg) else {
            throw CompressionError.missingTool(
                name: ToolKind.ffmpeg.displayName,
                installCommand: ToolKind.ffmpeg.installCommand,
                tool: .ffmpeg
            )
        }
        guard let ffprobeURL = registry.locateFFprobe(
            companionTo: ffmpegURL
        ) else {
            throw CompressionError.missingTool(
                name: "ffprobe（FFmpeg 视频检查组件）",
                installCommand: ToolKind.ffmpeg.reinstallCommand,
                tool: .ffmpeg
            )
        }

        let av1Encoder: FFmpegAV1Encoder?
        if settings.codec == .av1 {
            let capabilities = try await FFmpegCapabilityInspector(
                runner: runner
            ).inspect(executableURL: ffmpegURL)
            try Task.checkCancellation()
            av1Encoder = try capabilities.requireAV1Encoder()
        } else {
            av1Encoder = nil
        }

        let integritySnapshot = try await VideoIntegrityChecker(
            ffprobeURL: ffprobeURL,
            runner: runner
        ).inspect(inputURL)
        try Task.checkCancellation()
        return VideoRuntime(
            ffmpegURL: ffmpegURL,
            ffprobeURL: ffprobeURL,
            av1Encoder: av1Encoder,
            integritySnapshot: integritySnapshot
        )
    }

    private func prepareImageRuntime(
        inputURL: URL,
        settings: ImageCompressionSettings
    ) async throws -> ImageRuntime? {
        guard let executableURL = registry.locate(.imageMagick) else {
            return nil
        }

        guard settings.metadata == .removeAll,
              settings.preserveColorProfile else {
            return ImageRuntime(
                executableURL: executableURL,
                preservesEmbeddedICCWhileStripping: false
            )
        }

        let result: ProcessResult
        do {
            result = try await runner.run(
                executableURL: executableURL,
                arguments: [
                    "identify",
                    "-quiet",
                    "-format",
                    "%[profiles]",
                    inputURL.path
                ]
            )
        } catch is CancellationError {
            throw CompressionError.cancelled
        } catch {
            throw CompressionError.processFailed(
                tool: "\(ToolKind.imageMagick.displayName)（色彩配置检查）",
                exitCode: -1,
                message: error.localizedDescription
            )
        }

        guard result.exitCode == 0 else {
            throw CompressionError.processFailed(
                tool: "\(ToolKind.imageMagick.displayName)（色彩配置检查）",
                exitCode: result.exitCode,
                message: conciseDiagnostic(result.standardError)
            )
        }

        let profiles = result.standardOutput.lowercased()
        return ImageRuntime(
            executableURL: executableURL,
            preservesEmbeddedICCWhileStripping:
                profiles.contains("icc") || profiles.contains("icm")
        )
    }

    private func makeInvocation(
        kind: MediaKind,
        inputURL: URL,
        outputURL: URL,
        settings: CompressionSettings,
        imageRuntime: ImageRuntime?,
        videoRuntime: VideoRuntime?,
        pdfPassword: String?
    ) throws -> EngineInvocation {
        switch kind {
        case .image:
            if let imageRuntime {
                if imageRuntime.preservesEmbeddedICCWhileStripping {
                    let profileURL = intermediateImageProfileURL(
                        adjacentTo: outputURL
                    )
                    return EngineInvocation(
                        engineID: .imageMagick,
                        engineName: ToolKind.imageMagick.displayName,
                        processes: [
                            ProcessInvocation(
                                toolName:
                                    "\(ToolKind.imageMagick.displayName)（ICC 提取）",
                                executableURL: imageRuntime.executableURL,
                                arguments: [
                                    "\(inputURL.path)[0]",
                                    "icc:\(profileURL.path)"
                                ]
                            ),
                            ProcessInvocation(
                                toolName: ToolKind.imageMagick.displayName,
                                executableURL: imageRuntime.executableURL,
                                arguments: ImageMagickCommandBuilder.arguments(
                                    input: inputURL,
                                    output: outputURL,
                                    settings: settings.image,
                                    restoredICCProfileURL: profileURL
                                )
                            )
                        ],
                        intermediateURLs: [profileURL]
                    )
                }

                return EngineInvocation(
                    engineID: .imageMagick,
                    engineName: ToolKind.imageMagick.displayName,
                    executableURL: imageRuntime.executableURL,
                    arguments: ImageMagickCommandBuilder.arguments(
                        input: inputURL,
                        output: outputURL,
                        settings: settings.image
                    )
                )
            }

            if settings.image.targetSizeBytes != nil {
                throw CompressionError.settingsRequireTool(
                    name: ToolKind.imageMagick.displayName,
                    installCommand: ToolKind.imageMagick.installCommand,
                    message:
                        "图片目标大小需要多次编码和尺寸迭代，"
                        + "macOS 图片后备无法准确兑现。",
                    tool: .imageMagick
                )
            }
            guard let sips = registry.locate(.sips) else {
                throw CompressionError.missingTool(
                    name: ToolKind.imageMagick.displayName,
                    installCommand: ToolKind.imageMagick.installCommand,
                    tool: .imageMagick
                )
            }
            try validateSipsFallbackCompatibility(
                inputURL: inputURL,
                outputURL: outputURL,
                settings: settings.image
            )
            return EngineInvocation(
                engineID: .macOSImageIO,
                engineName: ToolKind.sips.displayName,
                executableURL: sips,
                arguments: try SipsCommandBuilder.arguments(
                    input: inputURL,
                    output: outputURL,
                    settings: settings.image
                ),
                warning:
                    "ImageMagick 未安装，已使用 macOS 图片后备完成格式、质量和尺寸处理。"
                    + "系统会重写部分技术元数据，且不提供 WebP/GIF 等专业编码能力。"
            )

        case .video:
            guard let videoRuntime else {
                throw CompressionError.invalidSettings(
                    "视频引擎能力尚未完成检查，任务未开始"
                )
            }
            if settings.video.targetSizeBytes != nil {
                let passlogURL = outputURL
                    .deletingLastPathComponent()
                    .appendingPathComponent(
                        ".slimluma-pass-\(UUID().uuidString)"
                    )
                let argumentSets = try FFmpegCommandBuilder.targetArguments(
                    input: inputURL,
                    output: outputURL,
                    settings: settings.video,
                    durationSeconds:
                        videoRuntime.integritySnapshot.durationSeconds,
                    audioTrackCount:
                        videoRuntime.integritySnapshot.audioTrackCount,
                    passlogURL: passlogURL
                )
                return EngineInvocation(
                    engineID: .ffmpeg,
                    engineName: ToolKind.ffmpeg.displayName,
                    processes: [
                        ProcessInvocation(
                            toolName: "\(ToolKind.ffmpeg.displayName)（第一遍分析）",
                            executableURL: videoRuntime.ffmpegURL,
                            arguments: argumentSets[0],
                            progressDurationSeconds:
                                videoRuntime.integritySnapshot.durationSeconds,
                            progressStage: "正在分析目标码率"
                        ),
                        ProcessInvocation(
                            toolName: "\(ToolKind.ffmpeg.displayName)（第二遍编码）",
                            executableURL: videoRuntime.ffmpegURL,
                            arguments: argumentSets[1],
                            progressDurationSeconds:
                                videoRuntime.integritySnapshot.durationSeconds,
                            progressStage: "正在按目标大小编码"
                        )
                    ],
                    intermediateURLs: [],
                    cleanupPrefixes: [passlogURL],
                    warning: settings.video.hardwareAcceleration
                        ? "目标大小使用两遍软件编码，已暂时停用硬件加速以提高体积准确性"
                        : nil
                )
            }
            return EngineInvocation(
                engineID: .ffmpeg,
                engineName: ToolKind.ffmpeg.displayName,
                executableURL: videoRuntime.ffmpegURL,
                arguments: try FFmpegCommandBuilder.arguments(
                    input: inputURL,
                    output: outputURL,
                    settings: settings.video,
                    av1Encoder: videoRuntime.av1Encoder
                ),
                progressDurationSeconds:
                    videoRuntime.integritySnapshot.durationSeconds,
                progressStage: "正在压缩视频"
            )

        case .pdf:
            return try makePDFInvocation(
                inputURL: inputURL,
                outputURL: outputURL,
                settings: settings.pdf,
                password: pdfPassword
            )

        case .unknown:
            throw CompressionError.unsupportedFile(inputURL.lastPathComponent)
        }
    }

    private func makePDFInvocation(
        inputURL: URL,
        outputURL: URL,
        settings: PDFCompressionSettings,
        password: String?
    ) throws -> EngineInvocation {
        if PDFDocument(url: inputURL)?.isEncrypted == true {
            guard let qpdf = registry.locate(.qpdf) else {
                throw CompressionError.settingsRequireTool(
                    name: ToolKind.qpdf.displayName,
                    installCommand: ToolKind.qpdf.installCommand,
                    message: "加密 PDF 需要 qpdf 才能安全解锁并在输出中恢复原加密策略。",
                    tool: .qpdf
                )
            }
            guard let password,
                  !password.isEmpty else {
                throw CompressionError.invalidSettings(
                    "“\(inputURL.lastPathComponent)”已加密。请在文件设置中输入 PDF 密码后重试。"
                )
            }

            let decryptedURL = intermediatePDFURL(
                adjacentTo: outputURL,
                label: "decrypted"
            )
            let plainOutputURL = intermediatePDFURL(
                adjacentTo: outputURL,
                label: "plain-result"
            )
            let passwordFileURL = secureTemporaryURL(
                adjacentTo: outputURL,
                label: "pdf-password"
            )
            let encryptionArgumentsURL = secureTemporaryURL(
                adjacentTo: outputURL,
                label: "pdf-encryption-arguments"
            )
            try writeSecureText("\(password)\n", to: passwordFileURL)

            let base = try makePDFInvocation(
                inputURL: decryptedURL,
                outputURL: plainOutputURL,
                settings: settings,
                password: nil
            )
            guard case .processes(let baseProcesses) = base.execution else {
                throw CompressionError.invalidSettings(
                    "加密 PDF 无法使用 PDFKit 后备链路"
                )
            }

            var encryptionArguments = [
                plainOutputURL.path,
                "--copy-encryption=\(inputURL.path)",
                "--encryption-file-password=\(password)"
            ]
            if settings.linearizeForWeb {
                encryptionArguments.append("--linearize")
            }
            encryptionArguments.append(outputURL.path)
            try writeSecureText(
                encryptionArguments.joined(separator: "\n") + "\n",
                to: encryptionArgumentsURL
            )

            let processes = [
                ProcessInvocation(
                    toolName: "\(ToolKind.qpdf.displayName)（安全解锁）",
                    executableURL: qpdf,
                    arguments: QPDFCommandBuilder.decryptArguments(
                        input: inputURL,
                        output: decryptedURL,
                        passwordFile: passwordFileURL
                    ),
                    acceptedExitCodes: [0, 3],
                    progressStage: "正在安全解锁 PDF"
                )
            ] + baseProcesses + [
                ProcessInvocation(
                    toolName: "\(ToolKind.qpdf.displayName)（恢复加密）",
                    executableURL: qpdf,
                    arguments: ["@\(encryptionArgumentsURL.path)"],
                    acceptedExitCodes: [0, 3],
                    progressStage: "正在恢复 PDF 加密"
                )
            ]
            return EngineInvocation(
                engineID: base.engineID,
                engineName: base.engineName,
                processes: processes,
                intermediateURLs: [
                    decryptedURL,
                    plainOutputURL,
                    passwordFileURL,
                    encryptionArgumentsURL
                ] + base.intermediateURLs,
                cleanupPrefixes: base.cleanupPrefixes,
                warning: [
                    base.warning,
                    "密码仅写入权限受限的临时文件，处理后已清除；输出保留原 PDF 加密策略"
                ]
                .compactMap { $0 }
                .joined(separator: "；"),
                supportsLinearization: base.supportsLinearization
            )
        }

        let qpdf = registry.locate(.qpdf)
        let ghostscript = registry.locate(.ghostscript)

        let shouldUseGhostscript: Bool
        switch settings.engine {
        case .ghostscript:
            shouldUseGhostscript = true
        case .qpdf:
            shouldUseGhostscript = false
        case .automatic:
            shouldUseGhostscript = settings.mode != .lossless && ghostscript != nil
        }

        if shouldUseGhostscript {
            guard let ghostscript else {
                throw CompressionError.missingTool(
                    name: ToolKind.ghostscript.displayName,
                    installCommand: ToolKind.ghostscript.installCommand,
                    tool: .ghostscript
                )
            }

            var processes: [ProcessInvocation] = []
            var intermediateURLs: [URL] = []
            var ghostscriptInputURL = inputURL

            if let qpdf {
                let repairedInputURL = intermediatePDFURL(
                    adjacentTo: outputURL,
                    label: "repaired"
                )
                intermediateURLs.append(repairedInputURL)
                processes.append(
                    ProcessInvocation(
                        toolName: "\(ToolKind.qpdf.displayName)（结构预检）",
                        executableURL: qpdf,
                        arguments: QPDFCommandBuilder.repairArguments(
                            input: inputURL,
                            output: repairedInputURL
                        ),
                        acceptedExitCodes: [0, 3]
                    )
                )
                ghostscriptInputURL = repairedInputURL
            }

            let ghostscriptOutputURL: URL
            if settings.linearizeForWeb, qpdf != nil {
                ghostscriptOutputURL = intermediatePDFURL(
                    adjacentTo: outputURL,
                    label: "compressed"
                )
                intermediateURLs.append(ghostscriptOutputURL)
            } else {
                ghostscriptOutputURL = outputURL
            }

            processes.append(
                ProcessInvocation(
                    toolName: ToolKind.ghostscript.displayName,
                    executableURL: ghostscript,
                    arguments: GhostscriptCommandBuilder.arguments(
                        input: ghostscriptInputURL,
                        output: ghostscriptOutputURL,
                        settings: settings,
                        linearizeInGhostscript: qpdf == nil
                    )
                )
            )

            if settings.linearizeForWeb, let qpdf {
                processes.append(
                    ProcessInvocation(
                        toolName: "\(ToolKind.qpdf.displayName)（网页优化）",
                        executableURL: qpdf,
                        arguments: QPDFCommandBuilder.linearizeArguments(
                            input: ghostscriptOutputURL,
                            output: outputURL
                        ),
                        acceptedExitCodes: [0, 3]
                    )
                )
            }

            let warning: String?
            if qpdf == nil {
                warning = settings.linearizeForWeb
                    ? "未安装 qpdf，已由 Ghostscript 执行网页快速打开；复杂 PDF 建议补装 qpdf 以获得更稳妥的结构修复"
                    : "未安装 qpdf，Ghostscript 已直接重写 PDF；数字签名会失效，请检查交互内容"
            } else {
                warning = nil
            }

            return EngineInvocation(
                engineID: qpdf == nil ? .ghostscript : .ghostscriptWithQPDF,
                engineName: qpdf == nil
                    ? ToolKind.ghostscript.displayName
                    : "\(ToolKind.ghostscript.displayName) + \(ToolKind.qpdf.displayName)",
                processes: processes,
                intermediateURLs: intermediateURLs,
                warning: warning
            )
        }

        if let qpdf {
            return EngineInvocation(
                engineID: .qpdf,
                engineName: ToolKind.qpdf.displayName,
                executableURL: qpdf,
                arguments: QPDFCommandBuilder.arguments(
                    input: inputURL,
                    output: outputURL,
                    settings: settings
                ),
                acceptedExitCodes: [0, 3],
                warning: settings.engine == .automatic && settings.mode != .lossless
                    ? "Ghostscript 未安装，已使用 qpdf 优化结构和图片编码；不会降低图片分辨率"
                    : nil
            )
        }

        if settings.engine == .automatic,
           settings.mode != .lossless,
           let ghostscript {
            return EngineInvocation(
                engineID: .ghostscript,
                engineName: ToolKind.ghostscript.displayName,
                executableURL: ghostscript,
                arguments: GhostscriptCommandBuilder.arguments(
                    input: inputURL,
                    output: outputURL,
                    settings: settings
                ),
                warning: "qpdf 未安装，已改用 Ghostscript；请检查 PDF 交互内容"
            )
        }

        if settings.engine == .automatic {
            let warning: String
            if settings.linearizeForWeb {
                warning =
                    "qpdf 和 Ghostscript 未安装，已使用 PDFKit 无损重写；"
                    + "PDFKit 不支持网页快速打开，本次未应用该选项。"
                    + "安装 qpdf 后可补齐线性化。"
            } else {
                warning =
                    "qpdf 和 Ghostscript 未安装，已使用 PDFKit 无损重写；"
                    + "压缩效果可能有限。"
            }
            return EngineInvocation(
                engineID: .macOSPDFKit,
                engineName: "macOS PDFKit",
                warning: warning,
                supportsLinearization: false
            )
        }

        throw CompressionError.missingTool(
            name: ToolKind.qpdf.displayName,
            installCommand: ToolKind.qpdf.installCommand,
            tool: .qpdf
        )
    }

    private func refineImageToTarget(
        inputURL: URL,
        outputURL: URL,
        settings: ImageCompressionSettings,
        imageRuntime: ImageRuntime,
        restoredICCProfileURL: URL?,
        progressHandler: (@Sendable (CompressionProgress) -> Void)?
    ) async throws -> String? {
        guard let targetSizeBytes = settings.targetSizeBytes else {
            return nil
        }
        guard targetSizeBytes >= 16 * 1_024 else {
            throw CompressionError.invalidSettings(
                "图片目标大小不能低于 16 KB"
            )
        }
        guard !settings.lossless else {
            throw CompressionError.invalidSettings(
                "目标大小需要允许有损编码或缩小尺寸，请先关闭图片“无损”"
            )
        }
        guard try fileSize(at: outputURL) > targetSizeBytes else {
            return nil
        }

        let requestedQuality = max(5, min(settings.quality, 100))
        let qualityCandidates = [
            requestedQuality, 75, 65, 55, 45, 35, 25, 16, 10
        ]
        .filter { $0 <= requestedQuality }
        .reduce(into: [Int]()) { values, value in
            if !values.contains(value) {
                values.append(value)
            }
        }
        let attempts = qualityCandidates.map { ($0, 100) }
            + [(16, 85), (14, 70), (12, 55), (10, 40)]

        var candidateURLs: [URL] = []
        var smallestCandidate: (url: URL, bytes: Int64)?
        var selectedCandidate: (url: URL, bytes: Int64)?
        defer {
            for candidateURL in candidateURLs where
                candidateURL != selectedCandidate?.url {
                try? FileManager.default.removeItem(at: candidateURL)
            }
        }

        for (index, attempt) in attempts.enumerated() {
            try Task.checkCancellation()
            let candidateURL = outputURL
                .deletingLastPathComponent()
                .appendingPathComponent(
                    ".slimluma-target-\(UUID().uuidString)"
                )
                .appendingPathExtension(outputURL.pathExtension)
            candidateURLs.append(candidateURL)
            var candidateSettings = settings
            candidateSettings.targetSizeBytes = nil
            candidateSettings.quality = attempt.0

            let result = try await runner.run(
                executableURL: imageRuntime.executableURL,
                arguments: ImageMagickCommandBuilder.arguments(
                    input: inputURL,
                    output: candidateURL,
                    settings: candidateSettings,
                    restoredICCProfileURL: restoredICCProfileURL,
                    scalePercent: attempt.1
                )
            )
            guard result.exitCode == 0 else {
                throw CompressionError.processFailed(
                    tool: "\(ToolKind.imageMagick.displayName)（目标大小）",
                    exitCode: result.exitCode,
                    message: conciseDiagnostic(
                        result.standardError.isEmpty
                            ? result.standardOutput
                            : result.standardError
                    )
                )
            }

            let candidateBytes = try fileSize(at: candidateURL)
            if smallestCandidate == nil
                || candidateBytes < smallestCandidate!.bytes {
                smallestCandidate = (candidateURL, candidateBytes)
            }
            progressHandler?(
                CompressionProgress(
                    fractionCompleted:
                        0.79 + 0.10 * Double(index + 1)
                        / Double(attempts.count),
                    stage: "正在匹配图片目标大小"
                )
            )
            if candidateBytes <= targetSizeBytes {
                selectedCandidate = (candidateURL, candidateBytes)
                break
            }
        }

        guard let finalCandidate = selectedCandidate ?? smallestCandidate else {
            throw CompressionError.outputMissing
        }
        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.moveItem(
            at: finalCandidate.url,
            to: outputURL
        )
        candidateURLs.removeAll { $0 == finalCandidate.url }

        guard finalCandidate.bytes > targetSizeBytes else {
            return nil
        }
        return "已使用最低质量并逐级缩小尺寸，但实际文件仍高于目标大小；已保留最接近的安全结果"
    }

    private func targetSizeWarning(
        kind: MediaKind,
        outputBytes: Int64,
        settings: CompressionSettings
    ) -> String? {
        guard kind == .video,
              let target = settings.video.targetSizeBytes,
              outputBytes > Int64(Double(target) * 1.05) else {
            return nil
        }
        let excess = Double(outputBytes - target) / Double(target) * 100
        return String(
            format:
                "受容器、字幕或码率波动影响，结果比目标大小高 %.0f%%",
            excess
        )
    }

    private func removeFiles(withPrefix prefix: URL) {
        let directory = prefix.deletingLastPathComponent()
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        for child in children where
            child.lastPathComponent.hasPrefix(prefix.lastPathComponent) {
            try? FileManager.default.removeItem(at: child)
        }
    }

    private func secureTemporaryURL(
        adjacentTo outputURL: URL,
        label: String
    ) -> URL {
        outputURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                ".slimluma-\(label)-\(UUID().uuidString)"
            )
            .appendingPathExtension("txt")
    }

    private func writeSecureText(_ text: String, to url: URL) throws {
        let created = FileManager.default.createFile(
            atPath: url.path,
            contents: Data(text.utf8),
            attributes: [.posixPermissions: 0o600]
        )
        guard created else {
            throw CompressionError.outputInvalid(
                "无法创建权限受限的 PDF 密码临时文件"
            )
        }
    }

    private func fileSize(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    private func conciseDiagnostic(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "没有可用的错误信息" }
        return String(trimmed.suffix(1_500))
    }

    private func validateInputCompatibility(
        inputURL: URL,
        kind: MediaKind,
        settings: CompressionSettings
    ) throws {
        guard kind == .image else { return }

        try validateLosslessImageCompatibility(
            inputURL: inputURL,
            settings: settings.image
        )

        let snapshot: ImageIntegritySnapshot
        do {
            snapshot = try ImageIntegrityChecker().inspect(inputURL)
        } catch {
            throw CompressionError.outputInvalid(error.localizedDescription)
        }
        guard snapshot.isAnimated else { return }

        switch settings.image.format {
        case .keep, .webp:
            return
        case .jpeg, .png, .avif, .heic:
            throw CompressionError.invalidSettings(
                "“\(inputURL.lastPathComponent)”是 \(snapshot.frameCount) 帧动画。"
                    + "当前动画仅支持保持原格式或转换为 WebP，以免拆帧或丢失播放时序。"
            )
        }
    }

    private func validateLosslessImageCompatibility(
        inputURL: URL,
        settings: ImageCompressionSettings
    ) throws {
        guard settings.lossless else { return }

        switch settings.format {
        case .png, .webp:
            return
        case .jpeg, .avif, .heic:
            throw CompressionError.invalidSettings(
                "当前输出格式不能保证逐像素无损。请改用 PNG、WebP，"
                    + "或关闭“无损”并使用高质量设置。"
            )
        case .keep:
            let losslessSourceExtensions: Set<String> = [
                "png", "webp", "gif", "tif", "tiff", "bmp", "jp2"
            ]
            guard losslessSourceExtensions.contains(
                inputURL.pathExtension.lowercased()
            ) else {
                throw CompressionError.invalidSettings(
                    "“\(inputURL.lastPathComponent)”的原格式不能保证逐像素无损重编码。"
                        + "请改用 PNG、WebP，或关闭“无损”并使用高质量设置。"
                )
            }
        }
    }

    private func validateSipsFallbackCompatibility(
        inputURL: URL,
        outputURL: URL,
        settings: ImageCompressionSettings
    ) throws {
        if settings.metadata != .removePrivate
            || settings.preserveColorProfile {
            throw CompressionError.settingsRequireTool(
                name: ToolKind.imageMagick.displayName,
                installCommand: ToolKind.imageMagick.installCommand,
                message:
                    "当前元数据或色彩配置要求无法由 macOS 图片后备准确兑现。"
                    + "任务已在写出前停止，原文件不会被修改。",
                tool: .imageMagick
            )
        }

        let outputExtension = outputURL.pathExtension.lowercased()
        if settings.lossless,
           !["png", "tif", "tiff", "bmp"].contains(outputExtension) {
            throw CompressionError.settingsRequireTool(
                name: ToolKind.imageMagick.displayName,
                installCommand: ToolKind.imageMagick.installCommand,
                message:
                    "“\(inputURL.lastPathComponent)”的无损设置需要专业图片编码器。"
                    + "macOS 图片后备不能保证该格式逐像素无损。",
                tool: .imageMagick
            )
        }

        if ["webp", "gif"].contains(outputExtension) {
            throw CompressionError.settingsRequireTool(
                name: ToolKind.imageMagick.displayName,
                installCommand: ToolKind.imageMagick.installCommand,
                message:
                    "当前输出格式需要 ImageMagick 才能安全保留格式与动画语义。",
                tool: .imageMagick
            )
        }
    }

    private func pdfIntegrityMessage(_ report: PDFIntegrityReport) -> String {
        report.risks.map { risk in
            if let original = risk.originalValue,
               let compressed = risk.compressedValue {
                return "\(risk.message)（\(original) → \(compressed)）"
            }
            return risk.message
        }
        .joined(separator: "；")
    }

    private func intermediatePDFURL(
        adjacentTo outputURL: URL,
        label: String
    ) -> URL {
        outputURL
            .deletingLastPathComponent()
            .appendingPathComponent(".slimluma-\(label)-\(UUID().uuidString)")
            .appendingPathExtension("pdf")
    }

    private func intermediateImageProfileURL(
        adjacentTo outputURL: URL
    ) -> URL {
        outputURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                ".slimluma-icc-\(UUID().uuidString)"
            )
            .appendingPathExtension("icc")
    }
}

private struct ImageRuntime {
    let executableURL: URL
    let preservesEmbeddedICCWhileStripping: Bool
}

private struct VideoRuntime {
    let ffmpegURL: URL
    let ffprobeURL: URL
    let av1Encoder: FFmpegAV1Encoder?
    let integritySnapshot: VideoIntegritySnapshot
}

private enum EngineExecution {
    case processes([ProcessInvocation])
    case nativePDFKit
}

private struct ProcessInvocation {
    let toolName: String
    let executableURL: URL
    let arguments: [String]
    let environment: [String: String]
    let acceptedExitCodes: Set<Int32>
    let progressDurationSeconds: Double?
    let progressStage: String

    init(
        toolName: String,
        executableURL: URL,
        arguments: [String],
        environment: [String: String] = [:],
        acceptedExitCodes: Set<Int32> = [0],
        progressDurationSeconds: Double? = nil,
        progressStage: String? = nil
    ) {
        self.toolName = toolName
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.acceptedExitCodes = acceptedExitCodes
        self.progressDurationSeconds = progressDurationSeconds
        self.progressStage = progressStage ?? "正在使用 \(toolName)"
    }
}

private struct EngineInvocation {
    let engineID: CompressionEngineID
    let engineName: String
    let execution: EngineExecution
    var intermediateURLs: [URL]
    var cleanupPrefixes: [URL]
    var warning: String?
    let supportsLinearization: Bool

    init(
        engineID: CompressionEngineID,
        engineName: String,
        executableURL: URL,
        arguments: [String],
        environment: [String: String] = [:],
        acceptedExitCodes: Set<Int32> = [0],
        progressDurationSeconds: Double? = nil,
        progressStage: String? = nil,
        warning: String? = nil,
        supportsLinearization: Bool = true
    ) {
        self.engineID = engineID
        self.engineName = engineName
        execution = .processes([
            ProcessInvocation(
                toolName: engineName,
                executableURL: executableURL,
                arguments: arguments,
                environment: environment,
                acceptedExitCodes: acceptedExitCodes,
                progressDurationSeconds: progressDurationSeconds,
                progressStage: progressStage
            )
        ])
        intermediateURLs = []
        cleanupPrefixes = []
        self.warning = warning
        self.supportsLinearization = supportsLinearization
    }

    init(
        engineID: CompressionEngineID,
        engineName: String,
        processes: [ProcessInvocation],
        intermediateURLs: [URL],
        cleanupPrefixes: [URL] = [],
        warning: String? = nil,
        supportsLinearization: Bool = true
    ) {
        self.engineID = engineID
        self.engineName = engineName
        execution = .processes(processes)
        self.intermediateURLs = intermediateURLs
        self.cleanupPrefixes = cleanupPrefixes
        self.warning = warning
        self.supportsLinearization = supportsLinearization
    }

    init(
        engineID: CompressionEngineID,
        engineName: String,
        warning: String?,
        supportsLinearization: Bool = false
    ) {
        self.engineID = engineID
        self.engineName = engineName
        execution = .nativePDFKit
        intermediateURLs = []
        cleanupPrefixes = []
        self.warning = warning
        self.supportsLinearization = supportsLinearization
    }
}

private final class FFmpegProgressAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private let durationSeconds: Double
    private let baseFraction: Double
    private let span: Double
    private let stage: String
    private let handler: (@Sendable (CompressionProgress) -> Void)?
    private let startedAt = Date()
    private var pendingText = ""

    init(
        durationSeconds: Double,
        baseFraction: Double,
        span: Double,
        stage: String,
        handler: (@Sendable (CompressionProgress) -> Void)?
    ) {
        self.durationSeconds = durationSeconds
        self.baseFraction = baseFraction
        self.span = span
        self.stage = stage
        self.handler = handler
    }

    func consume(_ text: String) {
        lock.lock()
        pendingText.append(text)
        let lines = pendingText.components(separatedBy: .newlines)
        pendingText = lines.last ?? ""
        let completeLines = lines.dropLast()
        let progressValues = completeLines.compactMap(parseSeconds)
        lock.unlock()

        for seconds in progressValues {
            let processFraction = min(max(seconds / durationSeconds, 0), 0.99)
            let elapsed = Date().timeIntervalSince(startedAt)
            let remaining = processFraction > 0.02
                ? max(0, elapsed / processFraction * (1 - processFraction))
                : nil
            handler?(
                CompressionProgress(
                    fractionCompleted:
                        baseFraction + span * processFraction,
                    stage: stage,
                    estimatedRemainingSeconds: remaining
                )
            )
        }
    }

    private func parseSeconds(_ line: String) -> Double? {
        if line.hasPrefix("out_time_us="),
           let microseconds = Double(line.dropFirst("out_time_us=".count)) {
            return microseconds / 1_000_000
        }
        // Older FFmpeg versions label this value "ms" while reporting
        // microseconds. This matches FFmpeg's progress protocol behavior.
        if line.hasPrefix("out_time_ms="),
           let microseconds = Double(line.dropFirst("out_time_ms=".count)) {
            return microseconds / 1_000_000
        }
        guard line.hasPrefix("out_time=") else { return nil }
        let value = line.dropFirst("out_time=".count)
        let components = value.split(separator: ":")
        guard components.count == 3,
              let hours = Double(components[0]),
              let minutes = Double(components[1]),
              let seconds = Double(components[2]) else {
            return nil
        }
        return hours * 3_600 + minutes * 60 + seconds
    }
}

actor OutputFinalizer {
    private static let stagingPrefix = ".slimluma-finalize-"
    private static let stagingSuffix = ".stage"
    private static let markerName = ".staging.lock"
    private static let payloadName = "payload"
    private static let markerMagic = Data(
        "SlimLuma finalization staging v1\n".utf8
    )
    private static let staleStagingAge: TimeInterval = 24 * 60 * 60

    func finalize(
        temporaryURL: URL,
        inputURL: URL,
        kind: MediaKind,
        settings: CompressionSettings,
        planner: OutputPlanner
    ) throws -> URL {
        try Task.checkCancellation()
        let finalURL = try planner.destinationURL(
            for: inputURL,
            kind: kind,
            settings: settings
        )
        try Task.checkCancellation()
        let finalDirectory = finalURL.deletingLastPathComponent()
        let directoryDescriptor = try openDirectory(finalDirectory)
        defer { _ = Darwin.close(directoryDescriptor) }
        removeStaleStagingFiles(
            in: finalDirectory,
            directoryDescriptor: directoryDescriptor
        )

        let stagingDirectoryName =
            "\(Self.stagingPrefix)\(UUID().uuidString)\(Self.stagingSuffix)"
        let stagingDirectoryDescriptor =
            try createPrivateStagingDirectory(
                named: stagingDirectoryName,
                parentDescriptor: directoryDescriptor
            )
        var markerDescriptor: Int32 = -1
        var stagingDescriptor: Int32 = -1
        var stagingEntryExists = false
        defer {
            if stagingDescriptor >= 0 {
                if stagingEntryExists {
                    _ = removeEntryIfMatches(
                        named: Self.payloadName,
                        directoryDescriptor: stagingDirectoryDescriptor,
                        descriptor: stagingDescriptor
                    )
                }
                _ = Darwin.close(stagingDescriptor)
            }
            if markerDescriptor >= 0 {
                _ = removeEntryIfMatches(
                    named: Self.markerName,
                    directoryDescriptor: stagingDirectoryDescriptor,
                    descriptor: markerDescriptor
                )
                _ = slimLumaFlock(markerDescriptor, LOCK_UN)
                _ = Darwin.close(markerDescriptor)
            }
            _ = synchronizeDirectoryIfSupported(
                stagingDirectoryDescriptor
            )
            _ = removeDirectoryIfMatches(
                named: stagingDirectoryName,
                parentDescriptor: directoryDescriptor,
                descriptor: stagingDirectoryDescriptor
            )
            _ = synchronizeDirectoryIfSupported(directoryDescriptor)
            _ = Darwin.close(stagingDirectoryDescriptor)
        }
        try synchronizeDirectory(directoryDescriptor)
        markerDescriptor = try createAndLockMarker(
            named: Self.markerName,
            directoryDescriptor: stagingDirectoryDescriptor
        )
        try synchronizeDirectory(stagingDirectoryDescriptor)
        stagingDescriptor = try createStagingFile(
            named: Self.payloadName,
            directoryDescriptor: stagingDirectoryDescriptor
        )
        stagingEntryExists = true
        try synchronizeDirectory(stagingDirectoryDescriptor)

        // The private workspace can live on a different volume from the
        // selected output directory. Copy into a locked hidden sibling first,
        // then use a same-directory rename so a failed or cancelled copy never
        // exposes a partial final file.
        let finalPermissions = try copyAndSynchronize(
            from: temporaryURL,
            to: stagingDescriptor
        )
        try synchronizeDirectory(directoryDescriptor)
        try Task.checkCancellation()

        guard entryMatches(
            named: Self.payloadName,
            directoryDescriptor: stagingDirectoryDescriptor,
            descriptor: stagingDescriptor
        ) else {
            throw CompressionError.outputInvalid(
                "输出目录中的暂存结果已被替换"
            )
        }
        let renameResult = Darwin.renameatx_np(
            stagingDirectoryDescriptor,
            Self.payloadName,
            directoryDescriptor,
            finalURL.lastPathComponent,
            UInt32(RENAME_EXCL)
        )
        guard renameResult == 0 else {
            throw CompressionError.outputInvalid(
                "无法原子保存最终结果"
            )
        }
        stagingEntryExists = false

        guard entryMatches(
            named: finalURL.lastPathComponent,
            directoryDescriptor: directoryDescriptor,
            descriptor: stagingDescriptor
        ) else {
            throw CompressionError.outputInvalid(
                "最终结果在保存时被替换"
            )
        }
        do {
            guard Darwin.fchmod(
                stagingDescriptor,
                finalPermissions
            ) == 0,
            Darwin.fsync(stagingDescriptor) == 0 else {
                throw CompressionError.outputInvalid(
                    "无法同步最终结果的权限"
                )
            }
            try synchronizeDirectory(directoryDescriptor)
        } catch {
            _ = removeEntryIfMatches(
                named: finalURL.lastPathComponent,
                directoryDescriptor: directoryDescriptor,
                descriptor: stagingDescriptor
            )
            _ = synchronizeDirectoryIfSupported(directoryDescriptor)
            throw error
        }
        try? FileManager.default.removeItem(at: temporaryURL)
        let currentDirectory = try currentDirectoryURL(
            directoryDescriptor,
            expectedURL: finalDirectory
        )
        return currentDirectory.appendingPathComponent(
            finalURL.lastPathComponent
        )
    }

    private func openDirectory(_ directory: URL) throws -> Int32 {
        let descriptor = Darwin.open(
            directory.path,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw CompressionError.outputInvalid(
                "无法打开输出目录以完成安全保存"
            )
        }
        return descriptor
    }

    private func createPrivateStagingDirectory(
        named name: String,
        parentDescriptor: Int32
    ) throws -> Int32 {
        guard Darwin.mkdirat(
            parentDescriptor,
            name,
            mode_t(0o700)
        ) == 0 else {
            throw CompressionError.outputInvalid(
                "无法在输出目录创建私有暂存目录"
            )
        }
        let descriptor = Darwin.openat(
            parentDescriptor,
            name,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            _ = Darwin.unlinkat(
                parentDescriptor,
                name,
                AT_REMOVEDIR
            )
            throw CompressionError.outputInvalid(
                "无法打开输出目录中的私有暂存目录"
            )
        }
        guard Darwin.fchmod(descriptor, mode_t(0o700)) == 0 else {
            _ = Darwin.close(descriptor)
            _ = Darwin.unlinkat(
                parentDescriptor,
                name,
                AT_REMOVEDIR
            )
            throw CompressionError.outputInvalid(
                "无法限制输出暂存目录权限"
            )
        }
        return descriptor
    }

    private func createAndLockMarker(
        named name: String,
        directoryDescriptor: Int32
    ) throws -> Int32 {
        let descriptor = Darwin.openat(
            directoryDescriptor,
            name,
            O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard descriptor >= 0 else {
            throw CompressionError.outputInvalid(
                "无法在输出目录创建安全暂存标记"
            )
        }
        var shouldRemove = true
        defer {
            if shouldRemove {
                _ = Darwin.unlinkat(directoryDescriptor, name, 0)
            }
        }
        guard slimLumaFlock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            _ = Darwin.close(descriptor)
            throw CompressionError.outputInvalid(
                "无法锁定输出目录的安全暂存标记"
            )
        }

        let written = Self.markerMagic.withUnsafeBytes { bytes in
            Darwin.write(descriptor, bytes.baseAddress, bytes.count)
        }
        guard written == Self.markerMagic.count,
              Darwin.fsync(descriptor) == 0 else {
            _ = slimLumaFlock(descriptor, LOCK_UN)
            _ = Darwin.close(descriptor)
            throw CompressionError.outputInvalid(
                "无法初始化输出目录的安全暂存标记"
            )
        }
        shouldRemove = false
        return descriptor
    }

    private func createStagingFile(
        named name: String,
        directoryDescriptor: Int32
    ) throws -> Int32 {
        let descriptor = Darwin.openat(
            directoryDescriptor,
            name,
            O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard descriptor >= 0 else {
            throw CompressionError.outputInvalid(
                "无法在输出目录创建安全暂存文件"
            )
        }
        return descriptor
    }

    private func copyAndSynchronize(
        from sourceURL: URL,
        to destinationDescriptor: Int32
    ) throws -> mode_t {
        let sourceDescriptor = Darwin.open(
            sourceURL.path,
            O_RDONLY | O_CLOEXEC | O_NOFOLLOW
        )
        guard sourceDescriptor >= 0 else {
            throw CompressionError.outputInvalid(
                "无法读取已通过验收的临时结果"
            )
        }
        defer { _ = Darwin.close(sourceDescriptor) }

        var sourceStatus = stat()
        guard Darwin.fstat(sourceDescriptor, &sourceStatus) == 0,
              (sourceStatus.st_mode & mode_t(S_IFMT))
                == mode_t(S_IFREG) else {
            throw CompressionError.outputInvalid(
                "已通过验收的临时结果不是普通文件"
            )
        }
        guard Darwin.fcopyfile(
            sourceDescriptor,
            destinationDescriptor,
            nil,
            copyfile_flags_t(COPYFILE_DATA)
        ) == 0 else {
            throw CompressionError.outputInvalid(
                "复制到输出磁盘失败"
            )
        }

        guard Darwin.fsync(destinationDescriptor) == 0 else {
            throw CompressionError.outputInvalid(
                "无法同步输出磁盘上的暂存结果"
            )
        }

        var destinationStatus = stat()
        guard Darwin.fstat(destinationDescriptor, &destinationStatus) == 0,
              destinationStatus.st_size == sourceStatus.st_size else {
            throw CompressionError.outputInvalid(
                "复制到输出磁盘时文件大小不一致"
            )
        }

        let requestedPermissions =
            sourceStatus.st_mode & mode_t(0o666)
        return requestedPermissions == 0
            ? mode_t(0o600)
            : requestedPermissions
    }

    private func synchronizeDirectory(_ descriptor: Int32) throws {
        guard Darwin.fsync(descriptor) == 0 else {
            let syncError = errno
            if syncError == EINVAL || syncError == ENOTSUP {
                return
            }
            throw CompressionError.outputInvalid(
                "无法同步输出目录"
            )
        }
    }

    private func synchronizeDirectoryIfSupported(
        _ descriptor: Int32
    ) -> Bool {
        do {
            try synchronizeDirectory(descriptor)
            return true
        } catch {
            return false
        }
    }

    private func removeStaleStagingFiles(
        in directory: URL,
        directoryDescriptor: Int32,
        now: Date = Date()
    ) {
        guard let children = try? FileManager.default.contentsOfDirectory(
            atPath: directory.path
        ) else {
            return
        }
        let cutoff = now.addingTimeInterval(-Self.staleStagingAge)
        for stagingDirectoryName in children {
            guard isStagingDirectoryName(stagingDirectoryName) else {
                continue
            }

            let stagingDirectoryDescriptor = Darwin.openat(
                directoryDescriptor,
                stagingDirectoryName,
                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
            )
            guard stagingDirectoryDescriptor >= 0 else {
                continue
            }
            defer { _ = Darwin.close(stagingDirectoryDescriptor) }

            var stagingDirectoryStatus = stat()
            guard Darwin.fstat(
                stagingDirectoryDescriptor,
                &stagingDirectoryStatus
            ) == 0,
            (stagingDirectoryStatus.st_mode & mode_t(S_IFMT))
                == mode_t(S_IFDIR),
            stagingDirectoryStatus.st_uid == Darwin.getuid(),
            modificationDate(stagingDirectoryStatus) < cutoff,
            entryMatches(
                named: stagingDirectoryName,
                directoryDescriptor: directoryDescriptor,
                descriptor: stagingDirectoryDescriptor
            ) else {
                continue
            }

            let markerDescriptor = Darwin.openat(
                stagingDirectoryDescriptor,
                Self.markerName,
                O_RDONLY | O_CLOEXEC | O_NOFOLLOW
            )
            guard markerDescriptor >= 0 else {
                continue
            }
            defer { _ = Darwin.close(markerDescriptor) }

            var markerStatus = stat()
            guard Darwin.fstat(
                markerDescriptor,
                &markerStatus
            ) == 0,
            (markerStatus.st_mode & mode_t(S_IFMT))
                == mode_t(S_IFREG),
            markerStatus.st_uid == Darwin.getuid(),
            markerMatches(markerDescriptor),
            slimLumaFlock(
                markerDescriptor,
                LOCK_EX | LOCK_NB
            ) == 0 else {
                continue
            }
            defer {
                _ = slimLumaFlock(markerDescriptor, LOCK_UN)
            }

            guard entryMatches(
                named: Self.markerName,
                directoryDescriptor: stagingDirectoryDescriptor,
                descriptor: markerDescriptor
            ),
            directoryHasOnlyOwnedStagingEntries(
                directory,
                stagingDirectoryName: stagingDirectoryName,
                stagingDirectoryDescriptor: stagingDirectoryDescriptor,
                parentDescriptor: directoryDescriptor
            ) else {
                continue
            }

            let payloadDescriptor = Darwin.openat(
                stagingDirectoryDescriptor,
                Self.payloadName,
                O_RDONLY | O_CLOEXEC | O_NOFOLLOW
            )
            if payloadDescriptor >= 0 {
                defer { _ = Darwin.close(payloadDescriptor) }
                var payloadStatus = stat()
                guard Darwin.fstat(
                    payloadDescriptor,
                    &payloadStatus
                ) == 0,
                (payloadStatus.st_mode & mode_t(S_IFMT))
                    == mode_t(S_IFREG),
                payloadStatus.st_uid == Darwin.getuid(),
                removeEntryIfMatches(
                    named: Self.payloadName,
                    directoryDescriptor: stagingDirectoryDescriptor,
                    descriptor: payloadDescriptor
                ) else {
                    continue
                }
            } else if errno != ENOENT {
                continue
            }

            guard removeEntryIfMatches(
                named: Self.markerName,
                directoryDescriptor: stagingDirectoryDescriptor,
                descriptor: markerDescriptor
            ) else {
                continue
            }
            _ = synchronizeDirectoryIfSupported(
                stagingDirectoryDescriptor
            )
            guard removeDirectoryIfMatches(
                named: stagingDirectoryName,
                parentDescriptor: directoryDescriptor,
                descriptor: stagingDirectoryDescriptor
            ) else {
                continue
            }
            _ = synchronizeDirectoryIfSupported(directoryDescriptor)
        }
    }

    private func isStagingDirectoryName(_ name: String) -> Bool {
        guard name.hasPrefix(Self.stagingPrefix),
              name.hasSuffix(Self.stagingSuffix) else {
            return false
        }
        let identifierStart = name.index(
            name.startIndex,
            offsetBy: Self.stagingPrefix.count
        )
        let identifierEnd = name.index(
            name.endIndex,
            offsetBy: -Self.stagingSuffix.count
        )
        let identifier = String(
            name[identifierStart..<identifierEnd]
        )
        return UUID(uuidString: identifier) != nil
    }

    private func directoryHasOnlyOwnedStagingEntries(
        _ parentDirectory: URL,
        stagingDirectoryName: String,
        stagingDirectoryDescriptor: Int32,
        parentDescriptor: Int32
    ) -> Bool {
        let stagingDirectoryURL = parentDirectory.appendingPathComponent(
            stagingDirectoryName,
            isDirectory: true
        )
        guard let names = try? FileManager.default.contentsOfDirectory(
            atPath: stagingDirectoryURL.path
        ),
        Set(names).isSubset(
            of: [Self.markerName, Self.payloadName]
        ),
        entryMatches(
            named: stagingDirectoryName,
            directoryDescriptor: parentDescriptor,
            descriptor: stagingDirectoryDescriptor
        ) else {
            return false
        }
        return true
    }

    private func markerMatches(_ descriptor: Int32) -> Bool {
        var markerStatus = stat()
        guard Darwin.fstat(descriptor, &markerStatus) == 0,
              markerStatus.st_size == off_t(Self.markerMagic.count) else {
            return false
        }
        var buffer = [UInt8](
            repeating: 0,
            count: Self.markerMagic.count
        )
        let bytesRead = buffer.withUnsafeMutableBytes { bytes in
            Darwin.pread(
                descriptor,
                bytes.baseAddress,
                bytes.count,
                0
            )
        }
        return bytesRead == Self.markerMagic.count
            && Data(buffer) == Self.markerMagic
    }

    private func modificationDate(_ status: stat) -> Date {
        Date(
            timeIntervalSince1970:
                TimeInterval(status.st_mtimespec.tv_sec)
                + TimeInterval(status.st_mtimespec.tv_nsec)
                    / 1_000_000_000
        )
    }

    private func currentDirectoryURL(
        _ descriptor: Int32,
        expectedURL: URL
    ) throws -> URL {
        var buffer = [CChar](
            repeating: 0,
            count: Int(MAXPATHLEN)
        )
        let result = buffer.withUnsafeMutableBufferPointer { pointer in
            guard let baseAddress = pointer.baseAddress else {
                return Int32(-1)
            }
            return slimLumaFcntlGetPath(
                descriptor,
                F_GETPATH,
                UnsafeMutableRawPointer(baseAddress)
            )
        }
        if result == 0 {
            return URL(
                fileURLWithPath: String(cString: buffer),
                isDirectory: true
            )
        }

        let expectedDescriptor = Darwin.open(
            expectedURL.path,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        if expectedDescriptor >= 0 {
            defer { _ = Darwin.close(expectedDescriptor) }
            if descriptorsMatch(
                descriptor,
                expectedDescriptor
            ) {
                return expectedURL
            }
        }
        throw CompressionError.outputInvalid(
            "输出目录在保存期间被移动，无法确认最终路径"
        )
    }

    private func descriptorsMatch(
        _ first: Int32,
        _ second: Int32
    ) -> Bool {
        var firstStatus = stat()
        var secondStatus = stat()
        guard Darwin.fstat(first, &firstStatus) == 0,
              Darwin.fstat(second, &secondStatus) == 0 else {
            return false
        }
        return firstStatus.st_dev == secondStatus.st_dev
            && firstStatus.st_ino == secondStatus.st_ino
            && (firstStatus.st_mode & mode_t(S_IFMT))
                == (secondStatus.st_mode & mode_t(S_IFMT))
    }

    private func entryMatches(
        named name: String,
        directoryDescriptor: Int32,
        descriptor: Int32
    ) -> Bool {
        var descriptorStatus = stat()
        var entryStatus = stat()
        guard Darwin.fstat(
            descriptor,
            &descriptorStatus
        ) == 0,
        Darwin.fstatat(
            directoryDescriptor,
            name,
            &entryStatus,
            AT_SYMLINK_NOFOLLOW
        ) == 0 else {
            return false
        }
        return descriptorStatus.st_dev == entryStatus.st_dev
            && descriptorStatus.st_ino == entryStatus.st_ino
            && (descriptorStatus.st_mode & mode_t(S_IFMT))
                == (entryStatus.st_mode & mode_t(S_IFMT))
    }

    @discardableResult
    private func removeDirectoryIfMatches(
        named name: String,
        parentDescriptor: Int32,
        descriptor: Int32
    ) -> Bool {
        guard entryMatches(
            named: name,
            directoryDescriptor: parentDescriptor,
            descriptor: descriptor
        ) else {
            return false
        }
        return Darwin.unlinkat(
            parentDescriptor,
            name,
            AT_REMOVEDIR
        ) == 0
    }

    @discardableResult
    private func removeEntryIfMatches(
        named name: String,
        directoryDescriptor: Int32,
        descriptor: Int32
    ) -> Bool {
        guard entryMatches(
            named: name,
            directoryDescriptor: directoryDescriptor,
            descriptor: descriptor
        ) else {
            return false
        }
        return Darwin.unlinkat(
            directoryDescriptor,
            name,
            0
        ) == 0
    }
}

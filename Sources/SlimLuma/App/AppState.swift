import AppKit
import Foundation
import SlimLumaKit
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    @Published var section: AppSection = .compress
    @Published var queue: [CompressionQueueItem] = []
    @Published var selectedItemID: UUID?
    @Published var settings: CompressionSettings {
        didSet {
            SettingsStore.save(settings)
            if automationSettings.folderWatchEnabled,
               Self.folderWatchOutputRulesChanged(
                   from: oldValue.output,
                   to: settings.output
               ) {
                // Refresh loop-prevention rules without treating files that
                // already exist in the watched folders as newly imported.
                startFolderWatching(importsExistingFiles: false)
            }
        }
    }
    @Published var automationSettings: AutomationSettings {
        didSet { AutomationSettingsStore.save(automationSettings) }
    }
    @Published var customPresets: [CompressionPreset]
    @Published var history: [HistoryEntry]
    @Published var toolAvailability: [ToolAvailability] = []
    @Published var isProcessing = false
    @Published private(set) var isPaused = false
    @Published var isDropTargeted = false
    @Published var notice: AppNotice?
    @Published private(set) var transientStatusMessage: String?
    @Published var engineInstallation: EngineInstallationPhase = .idle
    @Published private(set) var isImportingClipboard = false
    @Published private(set) var isCancellingClipboardImport = false
    @Published private(set) var isDiscoveringFiles = false
    @Published private(set) var isFolderWatching = false
    @Published private(set) var folderWatchIssues:
        [FolderWatchService.WatchIssue] = []

    private let coordinator = CompressionCoordinator()
    private let installerRunner = ProcessRunner()
    private let clipboardImportService = ClipboardImportService()
    private let folderWatchService = FolderWatchService()
    private var processingTask: Task<Void, Never>?
    private var installationTask: Task<Void, Never>?
    private var clipboardImportTask: Task<Void, Never>?
    private var fileDiscoveryTasks: [UUID: Task<Void, Never>] = [:]
    private var folderWatchControlTask: Task<Void, Never>?
    private var transientStatusTask: Task<Void, Never>?
    private var homebrewMonitorTask: Task<Void, Never>?
    private var pendingHomebrewInstallationKinds: [ToolKind] = []
    private var pendingAutomaticStart = false
    private var activeAppIntentRequestIDs = Set<UUID>()

    init() {
        settings = SettingsStore.load()
        automationSettings = AutomationSettingsStore.load()
        customPresets = PresetStore.load()
        history = HistoryStore.load()
        refreshTools()
        if automationSettings.folderWatchEnabled {
            startFolderWatching()
        }
    }

    var canStart: Bool {
        !isProcessing
            && processingTask == nil
            && hasProcessableItems
            && effectiveOutputSettingsIssue == nil
    }

    var hasActiveOperations: Bool {
        isProcessing
            || engineInstallation.isAwaitingHomebrew
            || isImportingClipboard
            || isDiscoveringFiles
            || engineInstallation.isInstalling
    }

    var outputSettingsIssue: String? {
        outputSettingsIssue(for: settings.output)
    }

    var effectiveOutputSettingsIssue: String? {
        if let outputSettingsIssue {
            return outputSettingsIssue
        }
        for item in queue {
            guard let override = item.settingsOverride,
                  let issue = outputSettingsIssue(for: override.output) else {
                continue
            }
            return "“\(item.inputURL.lastPathComponent)”的独立设置：\(issue)"
        }
        return nil
    }

    private func outputSettingsIssue(
        for output: OutputSettings
    ) -> String? {
        guard output.location == .customDirectory else {
            return nil
        }

        guard let rawPath = output.customDirectoryPath?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !rawPath.isEmpty else {
            return "请先选择输出文件夹。"
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: rawPath,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            return "输出文件夹已移动或不存在，请重新选择。"
        }

        guard FileManager.default.isWritableFile(atPath: rawPath) else {
            return "当前输出文件夹不可写，请选择其他文件夹。"
        }

        return nil
    }

    private var hasProcessableItems: Bool {
        queue.contains {
            if case .waiting = $0.status { return true }
            if case .failed = $0.status { return true }
            if case .cancelled = $0.status { return true }
            return false
        }
    }

    var totalOriginalBytes: Int64 {
        queue.reduce(0) { $0 + $1.originalBytes }
    }

    var totalOutputBytes: Int64 {
        queue.reduce(0) { partial, item in
            partial + (item.outputBytes ?? item.originalBytes)
        }
    }

    var allPresets: [CompressionPreset] {
        CompressionPreset.builtIns + customPresets
    }

    var selectedQueueItem: CompressionQueueItem? {
        guard let selectedItemID else { return nil }
        return queue.first { $0.id == selectedItemID }
    }

    var missingRecommendedTools: [ToolKind] {
        ToolKind.allCases.filter {
            $0.isRecommended && !isToolAvailable($0)
        }
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = L10n.text("选择要压缩的文件")
        panel.prompt = L10n.text("添加")
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.resolvesAliases = true
        panel.allowedContentTypes = (
            MediaKind.imageExtensions.union(MediaKind.videoExtensions)
                .compactMap { UTType(filenameExtension: $0) }
            + [.pdf]
        )
        guard panel.runModal() == .OK else { return }
        focusCompressionWorkspace()
        addURLs(panel.urls)
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = L10n.text("选择包含媒体文件的文件夹")
        panel.prompt = L10n.text("扫描文件夹")
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.resolvesAliases = true
        guard panel.runModal() == .OK else { return }
        focusCompressionWorkspace()
        addURLs(panel.urls)
    }

    func importFromClipboard() {
        guard !isImportingClipboard else { return }
        isImportingClipboard = true
        isCancellingClipboardImport = false

        clipboardImportTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isImportingClipboard = false
                self.isCancellingClipboardImport = false
                self.clipboardImportTask = nil
            }
            do {
                let result = try await clipboardImportService
                    .importFromGeneralPasteboard()
                try Task.checkCancellation()
                focusCompressionWorkspace()
                addURLs(
                    result.importedURLs,
                    startWhenReady: automationSettings
                        .autoStartsClipboardCompression
                ) { [weak self] discoveredURLs, wasCancelled in
                    guard let self else { return }
                    if wasCancelled || discoveredURLs.isEmpty {
                        Task {
                            do {
                                try await self.clipboardImportService
                                    .discardBatch(result.batchDirectory)
                            } catch {
                                self.notice = AppNotice(
                                    title: "导入已取消，暂存文件未清理",
                                    message: error.localizedDescription,
                                    recovery: .dismiss
                                )
                            }
                        }
                        if wasCancelled {
                            self.notice = AppNotice(
                                title: "已取消剪贴板导入",
                                message: "未完成的暂存文件已清理，不会加入压缩队列。",
                                recovery: .dismiss
                            )
                        }
                        return
                    }

                    let skippedMessage = result.skippedItemNames.isEmpty
                        ? ""
                        : "；跳过 \(result.skippedItemNames.count) 个不支持项目"
                    self.notice = AppNotice(
                        title: "已从剪贴板导入",
                        message: "已加入 \(discoveredURLs.count) 个文件\(skippedMessage)。"
                            + (self.automationSettings.autoStartsClipboardCompression
                                ? " 文件就绪后会自动开始压缩。"
                                : ""),
                        recovery: .dismiss
                    )
                }
            } catch {
                if Task.isCancelled {
                    notice = AppNotice(
                        title: "已取消剪贴板导入",
                        message: "未完成的暂存文件已清理。",
                        recovery: .dismiss
                    )
                    return
                }
                notice = AppNotice(
                    title: "无法导入剪贴板",
                    message: error.localizedDescription,
                    recovery: .dismiss
                )
            }
        }
    }

    func cancelClipboardImport() {
        guard isImportingClipboard,
              !isCancellingClipboardImport else {
            return
        }
        isCancellingClipboardImport = true
        clipboardImportTask?.cancel()
    }

    func chooseWatchFolders() {
        let panel = NSOpenPanel()
        panel.title = L10n.text("选择要自动监控的文件夹")
        panel.prompt = L10n.text("添加监控")
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.resolvesAliases = true
        guard panel.runModal() == .OK else { return }

        var paths = automationSettings.watchedFolderPaths
        for url in panel.urls {
            let path = url.standardizedFileURL.path
            if !paths.contains(path) {
                paths.append(path)
            }
        }
        automationSettings.watchedFolderPaths = paths
        if automationSettings.folderWatchEnabled {
            startFolderWatching()
        }
    }

    func removeWatchFolder(path: String) {
        automationSettings.watchedFolderPaths.removeAll { $0 == path }
        if automationSettings.watchedFolderPaths.isEmpty {
            setFolderWatchEnabled(false)
        } else if automationSettings.folderWatchEnabled {
            startFolderWatching(importsExistingFiles: false)
        }
    }

    func setFolderWatchEnabled(_ enabled: Bool) {
        automationSettings.folderWatchEnabled = enabled
        if enabled {
            startFolderWatching()
        } else {
            stopFolderWatching()
        }
    }

    func updateFolderWatchOptions() {
        guard automationSettings.folderWatchEnabled else { return }
        // A live option change must not make every existing file look new
        // again. The existing-file preference is applied on explicit start.
        startFolderWatching(importsExistingFiles: false)
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.title = L10n.text("选择输出文件夹")
        panel.prompt = L10n.text("选择")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.output.location = .customDirectory
        settings.output.customDirectoryPath = url.path
    }

    func addURLs(
        _ urls: [URL],
        startWhenReady: Bool = false,
        onDiscoveryFinished: (@MainActor @Sendable (
            _ discoveredURLs: [URL],
            _ wasCancelled: Bool
        ) -> Void)? = nil
    ) {
        guard !urls.isEmpty else { return }

        let requestID = UUID()
        isDiscoveringFiles = true
        fileDiscoveryTasks[requestID] = Task { [weak self] in
            let discovery = Task.detached(priority: .userInitiated) {
                Self.discoverSupportedFiles(from: urls)
            }
            let discovered = await withTaskCancellationHandler {
                await discovery.value
            } onCancel: {
                discovery.cancel()
            }

            guard let self else { return }
            guard !Task.isCancelled else {
                onDiscoveryFinished?([], true)
                self.finishFileDiscovery(requestID)
                return
            }

            self.addDiscoveredFiles(discovered, requestedURLs: urls)
            if startWhenReady, !discovered.isEmpty, self.hasProcessableItems {
                self.pendingAutomaticStart = true
                self.startAutomaticProcessingIfPossible()
            }
            onDiscoveryFinished?(discovered, false)
            self.finishFileDiscovery(requestID)
        }
    }

    func recoverPendingAppIntentImports() {
        let scanResult: AppIntentImportInbox.ScanResult
        do {
            scanResult = try AppIntentImportInbox.scanPendingRequests()
        } catch {
            notice = AppNotice(
                title: "无法恢复快捷指令导入",
                message: error.localizedDescription,
                recovery: .dismiss
            )
            return
        }

        if !scanResult.issues.isEmpty {
            notice = AppNotice(
                title: "部分快捷指令导入需要处理",
                message: scanResult.issues
                    .map(\.message)
                    .joined(separator: " "),
                recovery: .dismiss
            )
        }

        for pendingRequest in scanResult.pendingRequests
        where activeAppIntentRequestIDs.insert(pendingRequest.request.id).inserted {
            section = .compress
            addURLs(
                pendingRequest.fileURLs,
                startWhenReady: pendingRequest.request.startsCompression
            ) { [weak self] discoveredURLs, wasCancelled in
                guard let self else { return }
                self.activeAppIntentRequestIDs.remove(pendingRequest.request.id)
                guard !wasCancelled, !discoveredURLs.isEmpty else {
                    do {
                        try AppIntentImportInbox.consume(pendingRequest)
                        Task {
                            do {
                                try await self.clipboardImportService.discardBatch(
                                    pendingRequest.receiptURL
                                        .deletingLastPathComponent()
                                )
                            } catch {
                                self.notice = AppNotice(
                                    title: "快捷指令导入已取消，暂存文件未清理",
                                    message: error.localizedDescription,
                                    recovery: .dismiss
                                )
                            }
                        }
                    } catch {
                        self.notice = AppNotice(
                            title: "无法取消快捷指令导入",
                            message: error.localizedDescription,
                            recovery: .dismiss
                        )
                    }
                    return
                }

                do {
                    try AppIntentImportInbox.consume(pendingRequest)
                } catch {
                    self.notice = AppNotice(
                        title: "快捷指令文件已加入，回执未清理",
                        message: "文件已进入队列，但导入回执未能清理："
                            + error.localizedDescription,
                        recovery: .dismiss
                    )
                }
            }
        }
    }

    func cancelFileDiscovery() {
        fileDiscoveryTasks.values.forEach { $0.cancel() }
        fileDiscoveryTasks.removeAll()
        isDiscoveringFiles = false
    }

    func removeItem(id: UUID) {
        guard !isProcessing else { return }
        queue.removeAll { $0.id == id }
        if selectedItemID == id {
            selectedItemID = queue.first?.id
        }
    }

    func clearQueue() {
        guard !isProcessing else { return }
        cancelFileDiscovery()
        cancelClipboardImport()
        queue.removeAll()
        selectedItemID = nil
    }

    func resetFinishedItems() {
        guard !isProcessing else { return }
        for index in queue.indices {
            queue[index].status = .waiting
            queue[index].outputURL = nil
            queue[index].outputBytes = nil
            queue[index].engineName = nil
            queue[index].detailMessage = nil
            queue[index].progressFraction = 0
            queue[index].progressStage = nil
            queue[index].estimatedRemainingSeconds = nil
        }
    }

    func applyCurrentSettings(to itemID: UUID) {
        guard !isProcessing,
              let index = queue.firstIndex(where: { $0.id == itemID }) else {
            return
        }
        queue[index].settingsOverride = settings
        showTransientStatus("已为此文件保存独立设置")
    }

    func clearSettingsOverride(for itemID: UUID) {
        guard !isProcessing,
              let index = queue.firstIndex(where: { $0.id == itemID }) else {
            return
        }
        queue[index].settingsOverride = nil
        showTransientStatus("此文件已改用全局设置")
    }

    func updatePDFPassword(for itemID: UUID, password: String) {
        guard !isProcessing,
              let index = queue.firstIndex(where: { $0.id == itemID }),
              queue[index].mediaKind == .pdf else {
            return
        }
        queue[index].pdfPassword = password.isEmpty ? nil : password
    }

    func startProcessing() {
        if let outputSettingsIssue = effectiveOutputSettingsIssue {
            notice = AppNotice(
                title: "输出位置不可用",
                message: outputSettingsIssue,
                recovery: .dismiss
            )
            return
        }
        guard canStart else { return }
        pendingAutomaticStart = false
        notice = nil
        isPaused = false
        isProcessing = true
        processingTask = Task {
            await processQueue(includingFailuresAndCancellations: true)
        }
    }

    func cancelProcessing() {
        pendingAutomaticStart = false
        isPaused = false
        cancelFileDiscovery()
        cancelClipboardImport()
        processingTask?.cancel()
        Task { await coordinator.cancelAll() }
    }

    func pauseProcessing() {
        guard isProcessing, !isPaused else { return }
        isPaused = true
        Task { await coordinator.pauseAll() }
        announceAccessibility("压缩任务已暂停")
    }

    func resumeProcessing() {
        guard isProcessing, isPaused else { return }
        isPaused = false
        Task { await coordinator.resumeAll() }
        announceAccessibility("压缩任务已继续")
    }

    func cancelActiveOperationsForTermination() async {
        pendingAutomaticStart = false

        let processing = processingTask
        let installation = installationTask
        let clipboardImport = clipboardImportTask
        let discoveryTasks = Array(fileDiscoveryTasks.values)
        let watchControl = folderWatchControlTask

        processing?.cancel()
        installation?.cancel()
        homebrewMonitorTask?.cancel()
        clipboardImport?.cancel()
        discoveryTasks.forEach { $0.cancel() }
        watchControl?.cancel()

        await coordinator.cancelAll()
        await installerRunner.cancelAll()
        await folderWatchService.stop()

        await processing?.value
        await installation?.value
        await clipboardImport?.value
        for task in discoveryTasks {
            await task.value
        }
        await watchControl?.value

        fileDiscoveryTasks.removeAll()
        folderWatchControlTask = nil
        isDiscoveringFiles = false
        isFolderWatching = false
        isPaused = false
    }

    func applyPreset(_ preset: CompressionPreset) {
        guard !isProcessing else { return }
        settings = preset.settings
        section = .compress
    }

    func saveCurrentPreset(named name: String) {
        guard !isProcessing else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let preset = CompressionPreset(
            name: trimmed,
            summary: "自定义参数",
            symbolName: "slider.horizontal.2.square",
            settings: settings
        )
        customPresets.insert(preset, at: 0)
        PresetStore.save(customPresets)
    }

    func deletePreset(_ preset: CompressionPreset) {
        guard !preset.isBuiltIn else { return }
        customPresets.removeAll { $0.id == preset.id }
        PresetStore.save(customPresets)
    }

    func exportPreset(_ preset: CompressionPreset) {
        let panel = NSSavePanel()
        panel.title = L10n.text("导出压缩预设")
        panel.prompt = L10n.text("导出")
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue =
            preset.name.replacingOccurrences(of: "/", with: "-")
            + ".slimluma-preset.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let document = PresetExchangeDocument(presets: [preset])
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(document)
            try data.write(to: url, options: .atomic)
            showTransientStatus("预设已导出")
        } catch {
            notice = AppNotice(
                title: "无法导出预设",
                message: error.localizedDescription,
                recovery: .dismiss
            )
        }
    }

    func exportAllCustomPresets() {
        guard !customPresets.isEmpty else { return }
        let panel = NSSavePanel()
        panel.title = L10n.text("导出我的全部预设")
        panel.prompt = L10n.text("导出")
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "SlimLuma-Presets.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let document = PresetExchangeDocument(presets: customPresets)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(document).write(to: url, options: .atomic)
            showTransientStatus("全部自定义预设已导出")
        } catch {
            notice = AppNotice(
                title: "无法导出预设",
                message: error.localizedDescription,
                recovery: .dismiss
            )
        }
    }

    func importPresets() {
        guard !isProcessing else { return }
        let panel = NSOpenPanel()
        panel.title = L10n.text("导入压缩预设")
        panel.prompt = L10n.text("导入")
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) <= 1_048_576 else {
                throw CompressionError.invalidSettings(
                    "预设文件超过 1 MB，已拒绝导入"
                )
            }
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let document = try decoder.decode(
                PresetExchangeDocument.self,
                from: data
            )
            guard document.formatVersion == 1,
                  document.exportedBy == "SlimLuma",
                  !document.presets.isEmpty,
                  document.presets.count <= 100 else {
                throw CompressionError.invalidSettings(
                    "这不是受支持的 SlimLuma 预设文件"
                )
            }

            let imported = document.presets.map { preset in
                CompressionPreset(
                    name: String(preset.name.prefix(80)),
                    summary: String(preset.summary.prefix(240)),
                    symbolName: preset.symbolName,
                    settings: sanitizedImportedSettings(preset.settings),
                    isBuiltIn: false
                )
            }
            customPresets.insert(contentsOf: imported, at: 0)
            PresetStore.save(customPresets)
            showTransientStatus("已导入 \(imported.count) 个预设")
        } catch {
            notice = AppNotice(
                title: "无法导入预设",
                message: error.localizedDescription,
                recovery: .dismiss
            )
        }
    }

    func clearHistory() {
        history.removeAll()
        HistoryStore.clear()
    }

    private func sanitizedImportedSettings(
        _ imported: CompressionSettings
    ) -> CompressionSettings {
        var value = imported
        value.image.quality = max(1, min(value.image.quality, 100))
        value.image.effort = max(0, min(value.image.effort, 9))
        value.image.maxWidth = value.image.maxWidth.map {
            max(16, min($0, 100_000))
        }
        value.image.maxHeight = value.image.maxHeight.map {
            max(16, min($0, 100_000))
        }
        value.image.targetSizeBytes = value.image.targetSizeBytes.map {
            max(16 * 1_024, min($0, 1_000_000_000_000))
        }
        value.video.quality = max(1, min(value.video.quality, 100))
        value.video.audioBitrate = max(
            16,
            min(value.video.audioBitrate, 1_536)
        )
        value.video.maxWidth = value.video.maxWidth.map {
            max(16, min($0, 100_000))
        }
        value.video.maxHeight = value.video.maxHeight.map {
            max(16, min($0, 100_000))
        }
        value.video.frameRate = value.video.frameRate.map {
            max(1, min($0, 240))
        }
        value.video.targetSizeBytes = value.video.targetSizeBytes.map {
            max(128 * 1_024, min($0, 1_000_000_000_000))
        }
        value.pdf.imageQuality = max(1, min(value.pdf.imageQuality, 100))
        value.pdf.imageDPI = max(36, min(value.pdf.imageDPI, 1_200))
        value.maxConcurrentJobs = max(1, min(value.maxConcurrentJobs, 6))
        return value
    }

    func refreshTools() {
        toolAvailability = ToolRegistry().availability()
    }

    func isToolAvailable(_ kind: ToolKind) -> Bool {
        toolAvailability.first(where: { $0.kind == kind })?.isAvailable == true
    }

    func installTool(_ kind: ToolKind) {
        installTools([kind])
    }

    func installRecommendedTools() {
        installTools(missingRecommendedTools)
    }

    func installPDFTools() {
        installTools([.qpdf, .ghostscript])
    }

    func cancelEngineInstallation() {
        installationTask?.cancel()
        homebrewMonitorTask?.cancel()
        homebrewMonitorTask = nil
        pendingHomebrewInstallationKinds = []
        engineInstallation = .idle
        Task { await installerRunner.cancelAll() }
        announceAccessibility("正在取消引擎安装")
    }

    func openHomebrewWebsite() {
        guard let url = URL(string: "https://brew.sh/") else { return }
        NSWorkspace.shared.open(url)
    }

    func reveal(url: URL) {
        guard validateResultFile(url) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func revealOriginal(url: URL) {
        guard validateInputFile(url) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func requeueOriginal(url: URL) {
        guard validateInputFile(url) else { return }
        focusCompressionWorkspace()
        addURLs([url])
    }

    func open(url: URL) {
        guard validateResultFile(url) else { return }
        guard NSWorkspace.shared.open(url) else {
            notice = AppNotice(
                title: "无法打开结果",
                message: "macOS 没有找到可打开“\(url.lastPathComponent)”的应用。",
                recovery: .dismiss
            )
            return
        }
    }

    @discardableResult
    func validateResultFile(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            notice = AppNotice(
                title: "结果文件不可用",
                message: "“\(url.lastPathComponent)”已被移动或删除。你仍可从历史记录复制原路径。",
                recovery: .dismiss
            )
            return false
        }
        return true
    }

    @discardableResult
    func validateInputFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ), !isDirectory.boolValue else {
            notice = AppNotice(
                title: "原文件不可用",
                message: "“\(url.lastPathComponent)”已被移动或删除，无法重新加入队列。",
                recovery: .dismiss
            )
            return false
        }
        return true
    }

    func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(string, forType: .string) else {
            notice = AppNotice(
                title: "复制失败",
                message: "无法写入 macOS 剪贴板，请稍后重试。",
                recovery: .dismiss
            )
            return
        }
        showTransientStatus("已复制到剪贴板")
    }

    private func showTransientStatus(_ message: String) {
        transientStatusMessage = message
        announceAccessibility(message)
        transientStatusTask?.cancel()
        transientStatusTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.transientStatusMessage = nil
            self?.transientStatusTask = nil
        }
    }

    private func focusCompressionWorkspace() {
        section = .compress
        guard let mainWindow = NSApplication.shared.windows.first(
            where: { $0.title == "SlimLuma" }
        ) else {
            return
        }
        mainWindow.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func processQueue(
        includingFailuresAndCancellations: Bool
    ) async {
        let candidateIDs = PDFPasswordQueueLifecycle.candidateIDs(
            in: queue,
            includingFailuresAndCancellations:
                includingFailuresAndCancellations
        )
        let batchCandidateIDs = Set(candidateIDs)

        defer {
            let wasCancelled = Task.isCancelled
            isProcessing = false
            isPaused = false
            processingTask = nil
            for index in queue.indices {
                if batchCandidateIDs.contains(queue[index].id),
                   queue[index].status == .processing {
                    queue[index].status = .cancelled
                }
            }
            PDFPasswordQueueLifecycle.clearPasswords(
                for: batchCandidateIDs,
                in: &queue
            )
            startAutomaticProcessingIfPossible()
            announceAccessibility(
                wasCancelled ? "压缩任务已取消" : "本批压缩任务已完成"
            )
        }

        let settingsSnapshot = settings
        let concurrency = max(1, min(settings.maxConcurrentJobs, 6))
        var iterator = candidateIDs.makeIterator()

        await withTaskGroup(of: JobOutcome.self) { group in
            @MainActor
            func enqueue(_ itemID: UUID) {
                guard let index = queue.firstIndex(
                    where: { $0.id == itemID }
                ) else {
                    return
                }
                let inputURL = queue[index].inputURL
                let jobSettings =
                    queue[index].settingsOverride ?? settingsSnapshot
                queue[index].status = .processing
                queue[index].outputURL = nil
                queue[index].outputBytes = nil
                queue[index].engineName = nil
                queue[index].detailMessage = nil
                queue[index].progressFraction = 0
                queue[index].progressStage = "正在准备"
                queue[index].estimatedRemainingSeconds = nil
                let pdfPassword = PDFPasswordQueueLifecycle.takePassword(
                    for: itemID,
                    from: &queue
                )

                group.addTask { [coordinator] in
                    do {
                        let result = try await coordinator.compress(
                            inputURL: inputURL,
                            settings: jobSettings,
                            pdfPassword: pdfPassword,
                            progressHandler: { [weak self] progress in
                                Task { @MainActor [weak self] in
                                    self?.updateProgress(
                                        progress,
                                        for: itemID
                                    )
                                }
                            }
                        )
                        return .success(itemID: itemID, result: result)
                    } catch {
                        return .failure(itemID: itemID, error: error)
                    }
                }
            }

            for _ in 0..<concurrency {
                guard let item = iterator.next() else { break }
                enqueue(item)
            }

            while let outcome = await group.next() {
                apply(outcome)
                if Task.isCancelled {
                    group.cancelAll()
                } else if let next = iterator.next() {
                    enqueue(next)
                }
            }
        }
    }

    private func apply(_ outcome: JobOutcome) {
        guard let index = queue.firstIndex(where: { $0.id == outcome.itemID }) else { return }
        queue[index].pdfPassword = nil

        if let result = outcome.result {
            queue[index].status = result.skippedBecauseLarger ? .skipped : .completed
            queue[index].outputURL = result.outputURL
            queue[index].outputBytes = result.outputBytes
            queue[index].engineName = result.engineName
            queue[index].progressFraction = 1
            queue[index].progressStage = "已完成"
            queue[index].estimatedRemainingSeconds = 0
            if result.skippedBecauseLarger {
                if result.mediaKind == .pdf, result.engineID == .macOSPDFKit {
                    queue[index].detailMessage =
                        "未生成：PDFKit 无损重写后没有变小。安装 Ghostscript 后重试可获得实际压缩。"
                } else {
                    queue[index].detailMessage =
                        result.warning ?? "未生成：处理结果没有比原文件更小。"
                }
            } else {
                queue[index].detailMessage = result.warning
            }
            history.insert(HistoryEntry(result: result), at: 0)
            HistoryStore.save(history)
        } else {
            let message = outcome.errorMessage ?? "未知错误"
            queue[index].status = outcome.failureKind == .cancelled
                ? .cancelled
                : .failed(message)
            queue[index].detailMessage = message
            queue[index].progressStage = outcome.failureKind == .cancelled
                ? "已取消"
                : "未完成"
            queue[index].estimatedRemainingSeconds = nil

            guard queue[index].status != .cancelled else { return }
            history.insert(
                HistoryEntry(item: queue[index], failureMessage: message),
                at: 0
            )
            HistoryStore.save(history)

            if let recoveryTool = outcome.recoveryTool {
                notice = AppNotice(
                    title: "缺少 \(recoveryTool.displayName)",
                    message: "任务没有开始。可以直接安装所需引擎，安装完成后回到队列重试。",
                    recovery: .install(recoveryTool)
                )
            } else {
                let wasSafetyRejection =
                    outcome.failureKind == .outputValidation
                notice = AppNotice(
                    title: wasSafetyRejection ? "输出已被安全拦截" : "压缩未完成",
                    message: message,
                    recovery: .dismiss
                )
            }
        }
    }

    private func updateProgress(
        _ progress: CompressionProgress,
        for itemID: UUID
    ) {
        guard let index = queue.firstIndex(where: { $0.id == itemID }),
              queue[index].status == .processing else {
            return
        }
        queue[index].progressFraction = progress.fractionCompleted
        queue[index].progressStage = progress.stage
        queue[index].estimatedRemainingSeconds =
            progress.estimatedRemainingSeconds
    }

    private func addDiscoveredFiles(
        _ urls: [URL],
        requestedURLs: [URL]
    ) {
        let existingPaths = Set(queue.map { $0.inputURL.standardizedFileURL.path })
        let newItems = urls
            .filter { !existingPaths.contains($0.standardizedFileURL.path) }
            .map(CompressionQueueItem.init)
        queue.append(contentsOf: newItems)
        if selectedItemID == nil {
            selectedItemID = queue.first?.id
        }
        if newItems.isEmpty {
            if urls.isEmpty {
                notice = AppNotice(
                    title: "未发现可压缩文件",
                    message: requestedURLs.count == 1
                        ? "所选内容中没有受支持的图片、视频或 PDF。"
                        : "这些内容中没有受支持的图片、视频或 PDF。",
                    recovery: .dismiss
                )
            } else {
                notice = AppNotice(
                    title: "文件已在队列中",
                    message: "发现的受支持文件都已添加，无需重复加入。",
                    recovery: .dismiss
                )
            }
        }
    }

    private func finishFileDiscovery(_ requestID: UUID) {
        fileDiscoveryTasks.removeValue(forKey: requestID)
        isDiscoveringFiles = !fileDiscoveryTasks.isEmpty
    }

    private func startFolderWatching(importsExistingFiles: Bool? = nil) {
        folderWatchControlTask?.cancel()

        let folders = automationSettings.watchedFolderPaths.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        guard !folders.isEmpty else {
            automationSettings.folderWatchEnabled = false
            isFolderWatching = false
            notice = AppNotice(
                title: "先添加监控文件夹",
                message: "选择一个或多个文件夹后，SlimLuma 才能自动发现新文件。",
                recovery: .dismiss
            )
            return
        }

        var ignoredDirectories: [URL] = []
        if settings.output.location == .customDirectory,
           let path = settings.output.customDirectoryPath,
           !path.isEmpty {
            ignoredDirectories.append(
                URL(fileURLWithPath: path, isDirectory: true)
            )
        }
        let suffixes = Set(
            [
                OutputPlanner().sanitizedFilenameSuffix(
                    settings.output.filenameSuffix
                ),
                "-slim"
            ]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

        let configuration = FolderWatchService.Configuration(
            folders: folders,
            scansSubdirectories: automationSettings.scansSubdirectories,
            pollingInterval: .seconds(2),
            requiredStableSnapshots: 2,
            importsExistingFiles: importsExistingFiles
                ?? automationSettings.importsExistingFiles,
            ignoredFilenameSuffixes: Array(suffixes),
            ignoredDirectories: ignoredDirectories
        )

        isFolderWatching = false
        folderWatchControlTask = Task { [weak self] in
            guard let self else { return }
            await folderWatchService.start(
                configuration: configuration,
                onNewFiles: { [weak self] urls in
                    await self?.receiveWatchedFiles(urls)
                },
                onIssues: { [weak self] issues in
                    await self?.receiveWatchIssues(issues)
                }
            )
            guard !Task.isCancelled else { return }
            isFolderWatching = true
        }
    }

    private func stopFolderWatching() {
        folderWatchControlTask?.cancel()
        folderWatchControlTask = nil
        isFolderWatching = false
        folderWatchIssues = []
        Task { await folderWatchService.stop() }
    }

    private func receiveWatchedFiles(_ urls: [URL]) {
        guard automationSettings.folderWatchEnabled else { return }
        addURLs(
            urls,
            startWhenReady: automationSettings.autoStartsFolderCompression
        )
    }

    private func receiveWatchIssues(
        _ issues: [FolderWatchService.WatchIssue]
    ) {
        folderWatchIssues = issues
    }

    private func installTools(_ requestedKinds: [ToolKind]) {
        guard !engineInstallation.isInstalling else { return }

        let kinds = requestedKinds.filter {
            $0.formulaName != nil && !isToolAvailable($0)
        }
        guard !kinds.isEmpty else {
            engineInstallation = .succeeded(
                message: "所选引擎已经可用",
                log: ""
            )
            return
        }

        guard ToolRegistry().homebrewURL() != nil else {
            pendingHomebrewInstallationKinds = kinds
            engineInstallation = .awaitingHomebrew(
                toolNames: kinds.map(\.displayName)
            )
            notice = AppNotice(
                title: "需要先安装 Homebrew",
                message: "已打开 Homebrew 官方网站。完成 Homebrew 安装后，SlimLuma 会自动检测并继续安装所选引擎，无需再次点击。",
                recovery: .openHomebrew
            )
            openHomebrewWebsite()
            monitorForHomebrew()
            return
        }

        pendingHomebrewInstallationKinds = []
        homebrewMonitorTask?.cancel()
        homebrewMonitorTask = nil
        engineInstallation = .installing(
            toolNames: kinds.map(\.displayName)
        )
        installationTask = Task { [weak self] in
            guard let self else { return }
            await self.performInstallation(kinds)
        }
    }

    private func monitorForHomebrew() {
        homebrewMonitorTask?.cancel()
        homebrewMonitorTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                if ToolRegistry().homebrewURL() != nil {
                    let pendingKinds = self.pendingHomebrewInstallationKinds
                    self.pendingHomebrewInstallationKinds = []
                    self.homebrewMonitorTask = nil
                    self.notice = nil
                    self.installTools(pendingKinds)
                    return
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func performInstallation(_ kinds: [ToolKind]) async {
        defer { installationTask = nil }

        guard let brewURL = ToolRegistry().homebrewURL() else {
            engineInstallation = .failed(
                message: "未检测到 Homebrew",
                log: "请先从 https://brew.sh 安装 Homebrew。"
            )
            return
        }

        do {
            var logSections: [String] = []
            for kind in kinds {
                try Task.checkCancellation()
                guard
                    let arguments = ToolRegistry()
                        .homebrewInstallArguments(for: kind)
                else {
                    continue
                }
                let result = try await installerRunner.run(
                    executableURL: brewURL,
                    arguments: arguments,
                    environment: [
                        "HOMEBREW_NO_ENV_HINTS": "1",
                        "HOMEBREW_NO_INSTALL_CLEANUP": "1",
                        "HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK": "1"
                    ]
                )
                logSections.append(
                    "$ \(brewURL.path) \(arguments.joined(separator: " "))\n"
                        + installationLog(
                            standardOutput: result.standardOutput,
                            standardError: result.standardError
                        )
                )
                guard result.exitCode == 0 else {
                    engineInstallation = .failed(
                        message: "Homebrew 安装失败（\(result.exitCode)）",
                        log: logSections.joined(separator: "\n\n")
                    )
                    return
                }
            }
            let log = logSections.joined(separator: "\n\n")

            refreshTools()
            let unavailable = kinds.filter { !isToolAvailable($0) }
            if unavailable.isEmpty {
                engineInstallation = .succeeded(
                    message: "已安装 \(L10n.list(kinds.map(\.displayName)))",
                    log: log
                )
                announceAccessibility("压缩引擎安装完成")
            } else {
                engineInstallation = .failed(
                    message: "安装命令已结束，但仍未检测到 \(L10n.list(unavailable.map(\.displayName)))",
                    log: log
                )
                announceAccessibility("引擎安装未完成")
            }
        } catch is CancellationError {
            engineInstallation = .idle
        } catch let error as CompressionError where error.isCancellation {
            engineInstallation = .idle
        } catch {
            if Task.isCancelled {
                engineInstallation = .idle
            } else {
                engineInstallation = .failed(
                    message: "安装没有完成",
                    log: error.localizedDescription
                )
                announceAccessibility("引擎安装未完成")
            }
        }
    }

    private func announceAccessibility(_ message: String) {
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: L10n.text(message),
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }

    private func installationLog(
        standardOutput: String,
        standardError: String
    ) -> String {
        let combined = [standardOutput, standardError]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if combined.isEmpty {
            return L10n.text("Homebrew 没有返回日志。")
        }
        return String(combined.suffix(12_000))
    }

    private func startAutomaticProcessingIfPossible() {
        guard pendingAutomaticStart,
              !isProcessing,
              processingTask == nil else {
            return
        }
        if let outputSettingsIssue = effectiveOutputSettingsIssue {
            pendingAutomaticStart = false
            notice = AppNotice(
                title: "输出位置不可用",
                message: outputSettingsIssue,
                recovery: .dismiss
            )
            return
        }
        guard queue.contains(where: { $0.status == .waiting }) else {
            pendingAutomaticStart = false
            return
        }
        pendingAutomaticStart = false
        notice = nil
        isProcessing = true
        processingTask = Task {
            await processQueue(includingFailuresAndCancellations: false)
        }
    }

    private static func folderWatchOutputRulesChanged(
        from oldValue: OutputSettings,
        to newValue: OutputSettings
    ) -> Bool {
        oldValue.location != newValue.location
            || oldValue.customDirectoryPath != newValue.customDirectoryPath
            || oldValue.filenameSuffix != newValue.filenameSuffix
    }

    nonisolated private static func discoverSupportedFiles(from urls: [URL]) -> [URL] {
        var discovered: [URL] = []
        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isDirectoryKey,
            .isHiddenKey
        ]

        for url in urls {
            guard !Task.isCancelled else { break }
            let values = try? url.resourceValues(forKeys: resourceKeys)
            if values?.isRegularFile == true {
                if MediaKind.detect(url: url) != .unknown {
                    discovered.append(url)
                }
                continue
            }

            guard values?.isDirectory == true,
                  let enumerator = FileManager.default.enumerator(
                      at: url,
                      includingPropertiesForKeys: Array(resourceKeys),
                      options: [.skipsHiddenFiles, .skipsPackageDescendants]
                  ) else {
                continue
            }

            for case let childURL as URL in enumerator {
                guard !Task.isCancelled else { break }
                let childValues = try? childURL.resourceValues(forKeys: resourceKeys)
                guard childValues?.isRegularFile == true,
                      childValues?.isHidden != true,
                      MediaKind.detect(url: childURL) != .unknown else {
                    continue
                }
                discovered.append(childURL)
            }
        }

        var seen = Set<String>()
        return discovered
            .filter { seen.insert($0.standardizedFileURL.path).inserted }
            .sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
    }
}

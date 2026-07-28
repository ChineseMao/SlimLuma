import AppKit
import Foundation

/// Bridges Finder's Open With and Services entry points into the app's queue.
///
/// Finder can launch the process before SwiftUI has created the first window, so
/// incoming URLs are retained until `SlimLumaApp` attaches its `AppState`.
@MainActor
final class SlimLumaApplicationDelegate: NSObject, NSApplicationDelegate {
    private weak var appState: AppState?
    private var pendingURLs: [URL] = []
    private var pendingStartWhenReady = false
    private var recentlyRoutedPaths: [String: Date] = [:]
    private var terminationCleanupInProgress = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.servicesProvider = self

        // Refresh the Services registry so development builds and newly moved
        // app bundles do not require a logout before Finder discovers the item.
        NSUpdateDynamicServices()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        appState?.recoverPendingAppIntentImports()
        showMainWindowIfAvailable()
    }

    func connect(to appState: AppState) {
        self.appState = appState
        appState.recoverPendingAppIntentImports()
        guard !pendingURLs.isEmpty else { return }

        let urls = pendingURLs
        let startWhenReady = pendingStartWhenReady
        pendingURLs.removeAll()
        pendingStartWhenReady = false
        importIntoQueue(urls, startWhenReady: startWhenReady)
    }

    func handleOpenURL(_ url: URL) {
        importIntoQueue([url])
    }

    func handleImportedURLs(
        _ urls: [URL],
        startWhenReady: Bool = false
    ) {
        importIntoQueue(urls, startWhenReady: startWhenReady)
    }

    func handlePendingAppIntentImports() {
        appState?.recoverPendingAppIntentImports()
        showMainWindowIfAvailable()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// Handles document URLs delivered for the `CFBundleDocumentTypes` declared
    /// by SlimLuma, including Finder's Open With action.
    func application(_ application: NSApplication, open urls: [URL]) {
        importIntoQueue(urls)
    }

    /// Kept as a compatibility fallback for systems that deliver file paths
    /// through the older application delegate callback.
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map(URL.init(fileURLWithPath:))
        importIntoQueue(urls)
        sender.reply(toOpenOrPrint: urls.isEmpty ? .failure : .success)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            showMainWindowIfAvailable()
        }
        return true
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        if terminationCleanupInProgress {
            return .terminateLater
        }
        guard let appState, appState.hasActiveOperations else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text("仍有任务正在进行")
        alert.informativeText = L10n.text(
            "退出会取消压缩、导入、扫描或引擎安装。已完成的输出不会被删除。"
        )
        alert.addButton(withTitle: L10n.text("继续使用"))
        alert.addButton(withTitle: L10n.text("取消任务并退出"))
        alert.buttons[0].keyEquivalent = "\u{1b}"
        alert.buttons[1].hasDestructiveAction = true

        guard alert.runModal() == .alertSecondButtonReturn else {
            return .terminateCancel
        }

        terminationCleanupInProgress = true
        Task {
            await appState.cancelActiveOperationsForTermination()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Implements the `importMedia:userData:error:` selector advertised by the
    /// app bundle's `NSServices` entry.
    @objc(importMedia:userData:error:)
    func importMedia(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) ?? []
        let urls = objects.compactMap { object -> URL? in
            if let url = object as? URL {
                return url
            }
            if let url = object as? NSURL {
                return url as URL
            }
            return nil
        }

        guard !urls.isEmpty else {
            error.pointee = L10n.text(
                "SlimLuma 没有收到可读取的文件。"
            ) as NSString
            return
        }

        importIntoQueue(urls)
    }

    private func importIntoQueue(
        _ urls: [URL],
        startWhenReady: Bool = false
    ) {
        let normalizedURLs = normalizedFileURLs(urls)
        guard !normalizedURLs.isEmpty else { return }

        guard let appState else {
            pendingURLs = normalizedFileURLs(pendingURLs + normalizedURLs)
            pendingStartWhenReady = pendingStartWhenReady || startWhenReady
            return
        }

        // A document-open event can be observed by both AppKit's delegate and
        // SwiftUI's onOpenURL hook. Collapse that short-lived duplicate while
        // preserving AppState's normal duplicate feedback for later user actions.
        let now = Date()
        recentlyRoutedPaths = recentlyRoutedPaths.filter {
            now.timeIntervalSince($0.value) < 2
        }
        let unroutedURLs = normalizedURLs.filter { url in
            recentlyRoutedPaths.updateValue(now, forKey: url.path) == nil
        }
        guard !unroutedURLs.isEmpty else { return }

        appState.section = .compress
        appState.addURLs(unroutedURLs, startWhenReady: startWhenReady)
        showMainWindowIfAvailable()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func showMainWindowIfAvailable() {
        guard let mainWindow = NSApplication.shared.windows.first(
            where: { $0.title == "SlimLuma" }
        ) else {
            return
        }
        mainWindow.makeKeyAndOrderFront(nil)
    }

    private func normalizedFileURLs(_ urls: [URL]) -> [URL] {
        var seenPaths = Set<String>()
        return urls.compactMap { url in
            guard url.isFileURL else { return nil }
            let normalizedURL = url.standardizedFileURL
            guard seenPaths.insert(normalizedURL.path).inserted else {
                return nil
            }
            return normalizedURL
        }
    }
}

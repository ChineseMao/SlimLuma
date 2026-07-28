import SlimLumaKit
import SwiftUI

@main
struct SlimLumaApp: App {
    @NSApplicationDelegateAdaptor(SlimLumaApplicationDelegate.self)
    private var applicationDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        Window("SlimLuma", id: "main") {
            RootView()
                .environmentObject(appState)
                .frame(minWidth: 1_080, minHeight: 700)
                .onAppear {
                    applicationDelegate.connect(to: appState)
                }
                .onOpenURL { url in
                    applicationDelegate.handleOpenURL(url)
                }
        }
        .defaultSize(width: 1_280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("添加文件…") {
                    appState.chooseFiles()
                }
                .keyboardShortcut("o")

                Button("添加文件夹…") {
                    appState.chooseFolder()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }

            CommandMenu("任务") {
                Button("开始压缩") {
                    appState.startProcessing()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(
                    appState.section != .compress || !appState.canStart
                )

                Button("取消全部") {
                    appState.cancelProcessing()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!appState.isProcessing)
            }
        }

        Settings {
            PreferencesView()
                .environmentObject(appState)
                .frame(
                    minWidth: 620,
                    idealWidth: 720,
                    minHeight: 560,
                    idealHeight: 650
                )
        }
    }
}

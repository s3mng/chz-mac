import AppKit
import SwiftUI

@main
struct CrackerApp: App {
    @State private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Cracker", id: "main") {
            HomeView(model: model)
                .preferredColorScheme(.dark)
                .onAppear { appDelegate.model = model }
                .onChange(of: model.hasActiveTransfer) { _, _ in
                    appDelegate.model = model
                }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 440, height: 720)

        Settings {
            SettingsView(model: model)
                .preferredColorScheme(.dark)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model?.hasActiveTransfer == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "다운로드가 아직 남았어요"
        alert.informativeText = "지금 종료하면 진행 중인 작업이 멈춥니다. 라이브는 여기까지 저장됩니다."
        alert.addButton(withTitle: "종료")
        alert.addButton(withTitle: "계속 받기")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }
}

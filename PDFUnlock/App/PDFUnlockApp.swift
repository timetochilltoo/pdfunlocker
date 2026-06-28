import SwiftUI

@main
struct PDFUnlockApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup("PDF Unlock") {
            ContentView()
                .environment(appState)
                .environment(appState.settings)
                .frame(minWidth: 720, minHeight: 480)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .commands {
            AppCommands(appState: appState)
        }

        Settings {
            SettingsView()
                .environment(appState.settings)
                .frame(width: 520, height: 480)
        }
    }
}
import SwiftUI
import UniformTypeIdentifiers

struct AppCommands: Commands {
    let appState: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Files…") {
                appState.requestAddFiles()
            }
            .keyboardShortcut("o", modifiers: [.command])
        }

        CommandMenu("Mode") {
            ForEach(AppMode.allCases) { mode in
                Button(mode.title) {
                    appState.mode = mode
                }
                .keyboardShortcut(mode == .unlock ? .init("1", modifiers: [.command]) : .init("2", modifiers: [.command]))
            }
        }
    }
}
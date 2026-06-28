import SwiftUI

/// Thin wrapper around a Picker styled as a segmented control.
struct ModeSelector: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var bindable = appState
        Picker("Mode", selection: $bindable.mode) {
            ForEach(AppMode.allCases) { mode in
                Label(mode.title, systemImage: mode.systemImage).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 200)
    }
}

/// Visual separator used at the top of the content area; the picker
/// itself lives in the toolbar.
struct ModeBar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack {
            ModeSelector()
            Spacer()
        }
    }
}
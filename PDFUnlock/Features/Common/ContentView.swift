import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var fileImporterShown = false

    var body: some View {
        @Bindable var bindable = appState

        VStack(spacing: 0) {
            ZStack {
                switch bindable.mode {
                case .unlock:
                    UnlockView()
                        .transition(.opacity)
                case .convert:
                    ConvertView()
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar { topToolbar }
        .animation(.easeInOut(duration: 0.15), value: bindable.mode)
        .onChange(of: appState.addFilesRequestToken) { _, _ in
            fileImporterShown = true
        }
        .fileImporter(
            isPresented: $fileImporterShown,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
    }

    @ToolbarContentBuilder
    private var topToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            ModeSelector()
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                appState.requestAddFiles()
            } label: {
                Label("Add Files", systemImage: "plus")
            }
            .help("Add PDF files to the queue")

            runButton
        }
    }

    @ViewBuilder
    private var runButton: some View {
        switch appState.mode {
        case .unlock:
            if appState.isUnlockRunning {
                Button(role: .destructive) {
                    appState.cancelUnlock()
                } label: {
                    Label("Cancel", systemImage: "stop.fill")
                }
                .help("Cancel running unlocks")
            } else {
                Button {
                    appState.runAllUnlock()
                } label: {
                    Label("Run All", systemImage: "play.fill")
                }
                .disabled(!appState.hasUnlockWork)
                .help("Unlock all queued PDFs that are ready or have a password")
            }
        case .convert:
            // Wired up in M1.5 (Convert module not yet implemented)
            Button {
                // No-op until M1.5
            } label: {
                Label("Run All", systemImage: "play.fill")
            }
            .disabled(true)
            .help("Convert mode lands in M1.5")
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        guard !pdfs.isEmpty else { return }
        switch appState.mode {
        case .unlock:
            appState.addUnlockJobs(from: pdfs)
        case .convert:
            appState.addConvertJobs(from: pdfs)
        }
    }
}
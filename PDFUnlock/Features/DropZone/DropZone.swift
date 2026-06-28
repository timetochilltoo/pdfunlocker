import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// Generic drop zone used by both modes. Shows a prompt + secondary text
/// when empty, and renders the queue's content when populated.
struct DropZone<Content: View>: View {
    @Environment(AppState.self) private var appState
    let prompt: String
    let secondary: String
    @ViewBuilder let content: () -> Content

    @State private var isTargeted = false

    var body: some View {
        ZStack {
            background

            if hasJobs {
                content()
                    .padding(12)
            } else {
                emptyState
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
    }

    private var hasJobs: Bool {
        switch appState.mode {
        case .unlock: return !appState.unlockJobs.isEmpty
        case .convert: return !appState.convertJobs.isEmpty
        }
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(
                isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: [6])
            )
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .padding(12)
            .animation(.easeInOut(duration: 0.12), value: isTargeted)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text(prompt)
                .font(.title2)
                .foregroundStyle(.primary)
            Text(secondary)
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Choose Files…") {
                appState.requestAddFiles()
            }
            .controlSize(.large)
            .keyboardShortcut("o", modifiers: [.command])
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let box = LockedBox<[URL]>([])
        let group = DispatchGroup()

        for provider in providers {
            guard provider.canLoadObject(ofClass: URL.self) else { continue }
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.pathExtension.lowercased() == "pdf" {
                    box.mutate { $0.append(url) }
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let urls = box.read { $0 }
            guard !urls.isEmpty else { return }
            switch appState.mode {
            case .unlock:
                appState.addUnlockJobs(from: urls)
            case .convert:
                appState.addConvertJobs(from: urls)
            }
        }

        return true
    }
}

/// Sendable wrapper around `NSLock` for sharing mutable state across
/// concurrency domains in Swift 6 strict-concurrency code.
private final class LockedBox<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ initial: Value) { self.value = initial }

    func mutate(_ body: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        body(&value)
    }

    func read<R>(_ body: (Value) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(value)
    }
}
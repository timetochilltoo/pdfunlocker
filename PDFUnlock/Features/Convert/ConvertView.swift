import SwiftUI
import AppKit

struct ConvertView: View {
    @Environment(AppState.self) private var appState
    @State private var enabledFormats: Set<ConvertFormat> = [.txt, .png]
    @State private var includeMarkdown: Bool = true
    @State private var dpi: Int = 150
    @State private var pageRangeText: String = ""

    private var viewModel: ConvertViewModel { appState.convertVM }

    var body: some View {
        @Bindable var bindable = appState

        VStack(spacing: 0) {
            optionsBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)

            Divider()

            DropZone(
                prompt: "Drop PDFs to convert",
                secondary: "Output stays on this Mac."
            ) {
                convertQueue
            }
        }
        .onAppear {
            viewModel.inspectAll(bindable.convertJobs)
            // Hydrate UI from settings
            includeMarkdown = bindable.settings.defaultMarkdown
            dpi = bindable.settings.defaultPNGDPI
        }
        .onChange(of: bindable.convertJobs.count) { _, _ in
            viewModel.inspectAll(bindable.convertJobs)
        }
        .onChange(of: includeMarkdown) { _, newValue in
            bindable.settings.defaultMarkdown = newValue
            syncFormats()
        }
        .onChange(of: dpi) { _, newValue in
            bindable.settings.defaultPNGDPI = newValue
        }
    }

    @ViewBuilder
    private var optionsBar: some View {
        HStack(spacing: 16) {
            formatPicker
            Spacer()
            pageRangeField
            dpiPicker
        }
    }

    @ViewBuilder
    private var formatPicker: some View {
        HStack(spacing: 8) {
            Text("Output:")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(isOn: Binding(
                get: { enabledFormats.contains(.txt) },
                set: { isOn in
                    if isOn { enabledFormats.insert(.txt) } else { enabledFormats.remove(.txt) }
                    syncFormats()
                }
            )) {
                Text("TXT").font(.caption)
            }
            .toggleStyle(.checkbox)

            Toggle(isOn: Binding(
                get: { enabledFormats.contains(.png) },
                set: { isOn in
                    if isOn { enabledFormats.insert(.png) } else { enabledFormats.remove(.png) }
                    syncFormats()
                }
            )) {
                Text("PNG").font(.caption)
            }
            .toggleStyle(.checkbox)

            Toggle(isOn: $includeMarkdown) {
                HStack(spacing: 4) {
                    Text("Markdown").font(.caption)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .help("Experimental — best-effort heuristics. Complex layouts may degrade.")
                }
            }
            .toggleStyle(.checkbox)
        }
    }

    @ViewBuilder
    private var dpiPicker: some View {
        HStack(spacing: 4) {
            Text("DPI:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("", selection: $dpi) {
                Text("72").tag(72)
                Text("150").tag(150)
                Text("300").tag(300)
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
            .disabled(!enabledFormats.contains(.png))
            .opacity(enabledFormats.contains(.png) ? 1.0 : 0.4)
        }
    }

    @ViewBuilder
    private var pageRangeField: some View {
        HStack(spacing: 4) {
            Text("Pages:")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("all", text: $pageRangeText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
                .help("e.g. '1-5' or '1,3,5-7'. Leave empty for all pages.")
        }
    }

    @ViewBuilder
    private var convertQueue: some View {
        if appState.convertJobs.isEmpty {
            EmptyView()
        } else {
            List {
                ForEach(appState.convertJobs) { job in
                    ConvertJobRow(
                        job: job,
                        onReveal: { revealOutputs(of: job) },
                        onRetry: {
                            job.errorMessage = nil
                            viewModel.run(job, settings: appState.settings)
                        },
                        onRemove: {
                            var jobs = appState.convertJobs
                            viewModel.remove(job, from: &jobs)
                            appState.convertJobs = jobs
                        }
                    )
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
        }
    }

    private func syncFormats() {
        // Mirror global toggles into job.formats. Per-job overrides land in M3.
        for job in appState.convertJobs {
            var formats: Set<ConvertFormat> = []
            if enabledFormats.contains(.txt) { formats.insert(.txt) }
            if enabledFormats.contains(.png) { formats.insert(.png) }
            if includeMarkdown { formats.insert(.md) }
            job.formats = formats.isEmpty ? [.txt] : formats
        }
    }

    private func revealOutputs(of job: ConvertJob) {
        var urls: [URL] = []
        for url in job.outputs.values { urls.append(url) }
        if !urls.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }
}

// MARK: - Row

struct ConvertJobRow: View {
    @Bindable var job: ConvertJob
    let onReveal: () -> Void
    let onRetry: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(job.fileName)
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        Text(job.humanFileSize)
                        Text("·")
                        Text(formatsLabel)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                statusBadge
                actions
            }

            if job.status == .running {
                ProgressView(value: job.progress)
                    .progressViewStyle(.linear)
            }

            if let error = job.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    private var formatsLabel: String {
        let names = job.formats
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.displayName)
        return names.isEmpty ? "TXT" : names.joined(separator: " · ")
    }

    @ViewBuilder
    private var statusBadge: some View {
        Text(job.status.displayLabel)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(badgeColor.opacity(0.18)))
            .foregroundStyle(badgeColor)
    }

    private var badgeColor: Color {
        switch job.status {
        case .queued,
             .inspecting:           return .secondary
        case .ready:                return .blue
        case .running:              return .blue
        case .succeeded:            return .green
        case .partialSuccess:       return .orange
        case .skipped:              return .secondary
        case .failed:               return .red
        case .cancelled:            return .secondary
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 4) {
            switch job.status {
            case .succeeded, .partialSuccess:
                Button("Reveal", systemImage: "magnifyingglass") { onReveal() }
                    .buttonStyle(.borderless)
                    .help("Reveal outputs in Finder")
            case .failed:
                Button("Retry", systemImage: "arrow.clockwise") { onRetry() }
                    .buttonStyle(.borderless)
                    .help("Retry conversion")
            default:
                EmptyView()
            }
            Menu {
                Button("Remove", systemImage: "minus.circle", role: .destructive) {
                    onRemove()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 22)
        }
    }
}
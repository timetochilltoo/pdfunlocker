import SwiftUI
import AppKit

struct UnlockView: View {
    @Environment(AppState.self) private var appState
    @State private var sharedPassword: String = ""
    @State private var showSharedPassword: Bool = false

    private var viewModel: UnlockViewModel { appState.unlockVM }

    var body: some View {
        @Bindable var bindable = appState

        VStack(spacing: 0) {
            DropZone(
                prompt: "Drop PDFs to unlock",
                secondary: "Files stay on this Mac."
            ) {
                unlockQueue
            }
        }
        .onAppear {
            viewModel.inspectAll(bindable.unlockJobs)
        }
        .onChange(of: bindable.unlockJobs.count) { _, _ in
            viewModel.inspectAll(bindable.unlockJobs)
        }
        .onChange(of: viewModel.runFinishedToken) { _, _ in
            // Hook for future post-run UI (e.g. notification).
        }
    }

    @ViewBuilder
    private var unlockQueue: some View {
        VStack(spacing: 0) {
            PreflightSummary(jobs: appState.unlockJobs)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            if needsSharedPassword {
                SharedPasswordBar(
                    sharedPassword: $sharedPassword,
                    showPassword: $showSharedPassword,
                    apply: {
                        viewModel.applySharedPassword(sharedPassword, to: appState.unlockJobs)
                    },
                    clear: {
                        sharedPassword = ""
                        viewModel.clearSharedPassword(from: appState.unlockJobs)
                    }
                )
                .padding(.horizontal, 12)
                .padding(.top, 6)
            }

            List {
                ForEach(appState.unlockJobs) { job in
                    UnlockJobRow(
                        job: job,
                        onReveal: { reveal(job.outputURL) },
                        onRetry: {
                            job.errorMessage = nil
                            viewModel.run(job, settings: appState.settings)
                        },
                        onRemove: {
                            var jobs = appState.unlockJobs
                            viewModel.remove(job, from: &jobs)
                            appState.unlockJobs = jobs
                        }
                    )
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
        }
    }

    private var needsSharedPassword: Bool {
        appState.unlockJobs.contains { $0.inspection?.encryption == .userPassword }
    }

    private func reveal(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

// MARK: - Row

struct UnlockJobRow: View {
    @Bindable var job: UnlockJob
    let onReveal: () -> Void
    let onRetry: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(job.fileName)
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        Text(job.humanFileSize)
                        Text("·")
                        Text(protectionLabel)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                statusBadge

                actions
            }

            if needsPasswordField {
                passwordField
            }

            if job.status == .running {
                ProgressView(value: job.progress)
                    .progressViewStyle(.linear)
            }

            if let error = job.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    private var encryptionKind: PDFInspection.EncryptionKind {
        job.inspection?.encryption ?? .none
    }

    private var iconName: String {
        switch encryptionKind {
        case .none:           return "doc"
        case .ownerOnly:      return "lock.doc"
        case .userPassword:   return "lock.doc.fill"
        case .certificate,
             .unsupported:    return "exclamationmark.triangle"
        }
    }

    private var iconColor: Color {
        switch encryptionKind {
        case .none:           return .secondary
        case .ownerOnly,
             .userPassword:   return .orange
        case .certificate,
             .unsupported:    return .red
        }
    }

    private var protectionLabel: String {
        switch encryptionKind {
        case .none:           return job.inspection == nil ? "Inspecting…" : "No encryption"
        case .ownerOnly:      return "Owner restrictions"
        case .userPassword:   return "Open password"
        case .certificate:    return "Certificate encryption"
        case .unsupported:    return "Unsupported encryption"
        }
    }

    private var needsPasswordField: Bool {
        job.inspection?.encryption == .userPassword
            && (job.status == .needsPassword || job.status == .ready)
    }

    @ViewBuilder
    private var statusBadge: some View {
        Text(job.status.displayLabel)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(badgeColor.opacity(0.18))
            )
            .foregroundStyle(badgeColor)
    }

    private var badgeColor: Color {
        switch job.status {
        case .queued,
             .inspecting:           return .secondary
        case .needsPassword,
             .ready:                return .orange
        case .running:              return .blue
        case .succeeded:            return .green
        case .skipped:              return .secondary
        case .failed:               return .red
        case .cancelled:            return .secondary
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 4) {
            switch job.status {
            case .succeeded:
                Button("Reveal", systemImage: "magnifyingglass") { onReveal() }
                    .buttonStyle(.borderless)
                    .help("Reveal in Finder")
            case .failed:
                Button("Retry", systemImage: "arrow.clockwise") { onRetry() }
                    .buttonStyle(.borderless)
                    .help("Retry unlock")
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

    @ViewBuilder
    private var passwordField: some View {
        HStack(spacing: 6) {
            Image(systemName: "key")
                .foregroundStyle(.secondary)
            SecureField("Password", text: $job.password)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
            if job.status == .needsPassword && !job.password.isEmpty {
                Text("Press Run to apply")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Preflight summary

struct PreflightSummary: View {
    let jobs: [UnlockJob]

    var body: some View {
        if jobs.count <= 1 { EmptyView() } else {
            HStack(spacing: 16) {
                summaryChip("Total", count: jobs.count, color: .secondary)
                summaryChip("Ready", count: readyCount, color: .orange)
                summaryChip("Needs pass", count: needsPassCount, color: .orange)
                summaryChip("Skipped", count: skippedCount, color: .secondary)
                summaryChip("Failed", count: failedCount, color: .red)
                Spacer()
            }
            .font(.caption)
        }
    }

    private var readyCount: Int { jobs.filter { $0.status == .ready }.count }
    private var needsPassCount: Int { jobs.filter { $0.status == .needsPassword }.count }
    private var skippedCount: Int { jobs.filter { $0.status == .skipped }.count }
    private var failedCount: Int { jobs.filter { $0.status == .failed }.count }

    private func summaryChip(_ title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(title): \(count)")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Shared password bar

struct SharedPasswordBar: View {
    @Binding var sharedPassword: String
    @Binding var showPassword: Bool
    let apply: () -> Void
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "key.fill")
                .foregroundStyle(.orange)
            if showPassword {
                TextField("Shared password", text: $sharedPassword)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
            } else {
                SecureField("Shared password", text: $sharedPassword)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
            }
            Button {
                showPassword.toggle()
            } label: {
                Image(systemName: showPassword ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .help(showPassword ? "Hide password" : "Show password")

            Button("Apply to all") { apply() }
                .disabled(sharedPassword.isEmpty)

            Button("Clear", role: .destructive) { clear() }
                .disabled(sharedPassword.isEmpty)
        }
    }
}
import SwiftUI

struct ConvertView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        DropZone(
            prompt: "Drop PDFs to convert",
            secondary: "Output stays on this Mac."
        ) {
            ConvertQueueList(jobs: appState.convertJobs)
        }
    }
}

struct ConvertQueueList: View {
    let jobs: [ConvertJob]

    var body: some View {
        if jobs.isEmpty {
            EmptyView()
        } else {
            List(jobs) { job in
                HStack {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.secondary)
                    Text(job.inputURL.lastPathComponent)
                    Spacer()
                    Text(job.status.displayLabel)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .padding(.vertical, 2)
            }
            .listStyle(.inset)
        }
    }
}
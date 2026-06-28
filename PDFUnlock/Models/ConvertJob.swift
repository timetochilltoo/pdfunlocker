import Foundation

/// One PDF in the convert queue. Fleshed out in M1.5.
@Observable
public final class ConvertJob: Identifiable, @unchecked Sendable {
    public let id: UUID
    public let inputURL: URL

    public var formats: Set<ConvertFormat>
    public var outputDirectory: URL
    public var pageRange: PageRange?
    public var status: ConvertStatus
    public var progress: Double
    public var errorMessage: String?
    public var outputs: [ConvertFormat: URL]

    public init(
        id: UUID = UUID(),
        inputURL: URL,
        formats: Set<ConvertFormat> = [.txt],
        outputDirectory: URL,
        pageRange: PageRange? = nil,
        status: ConvertStatus = .queued,
        progress: Double = 0,
        errorMessage: String? = nil,
        outputs: [ConvertFormat: URL] = [:]
    ) {
        self.id = id
        self.inputURL = inputURL
        self.formats = formats
        self.outputDirectory = outputDirectory
        self.pageRange = pageRange
        self.status = status
        self.progress = progress
        self.errorMessage = errorMessage
        self.outputs = outputs
    }

    public var fileName: String { inputURL.lastPathComponent }

    /// Mirrors UnlockJob's `humanFileSize` so the UI can render a
    /// consistent size column.
    public var humanFileSize: String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: inputURL.path)
        let bytes = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

public enum ConvertStatus: Equatable, Sendable {
    case queued
    case inspecting
    case ready
    case running
    case succeeded
    case partialSuccess
    case skipped
    case failed
    case cancelled

    public var displayLabel: String {
        switch self {
        case .queued: return "Queued"
        case .inspecting: return "Inspecting…"
        case .ready: return "Ready"
        case .running: return "Running…"
        case .succeeded: return "Done"
        case .partialSuccess: return "Partial"
        case .skipped: return "Skipped"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}
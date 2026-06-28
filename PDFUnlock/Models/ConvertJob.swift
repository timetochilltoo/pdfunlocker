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
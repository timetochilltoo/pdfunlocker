import Foundation

/// One PDF in the unlock queue. Full status and behavior is fleshed out
/// in M1; M0 only needs the shape so the SwiftUI list can render.
@Observable
public final class UnlockJob: Identifiable, @unchecked Sendable {
    public let id: UUID
    public let inputURL: URL
    public let fileSize: Int64

    public var outputURL: URL?
    public var inspection: PDFInspection?
    public var password: String
    public var status: UnlockStatus
    public var progress: Double
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        inputURL: URL,
        fileSize: Int64? = nil,
        outputURL: URL? = nil,
        inspection: PDFInspection? = nil,
        password: String = "",
        status: UnlockStatus = .queued,
        progress: Double = 0,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.inputURL = inputURL
        if let fileSize {
            self.fileSize = fileSize
        } else {
            let attrs = try? FileManager.default.attributesOfItem(atPath: inputURL.path)
            self.fileSize = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        }
        self.outputURL = outputURL
        self.inspection = inspection
        self.password = password
        self.status = status
        self.progress = progress
        self.errorMessage = errorMessage
    }

    public var fileName: String { inputURL.lastPathComponent }

    public var humanFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}
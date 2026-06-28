import Foundation
import PDFKit

/// Wraps PDFKit inspection. Pure function — no shared mutable state.
public struct PDFInspector: Sendable {

    public init() {}

    /// Inspect a PDF on disk. Returns `PDFInspection.unknown` on hard
    /// failures (file missing, corrupt) so callers can render a row.
    public func inspect(_ url: URL) -> PDFInspection {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .unknown
        }
        guard let doc = PDFDocument(url: url) else {
            return PDFInspection(
                pageCount: 0,
                encryption: .unsupported,
                hasTextLayer: false,
                isCorrupt: true
            )
        }

        let pageCount = doc.pageCount
        let textSample = (0..<min(pageCount, 3))
            .compactMap { doc.page(at: $0)?.string }
            .joined(separator: "\n")
        let hasTextLayer = !textSample.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let encryption: PDFInspection.EncryptionKind
        if !doc.isEncrypted {
            encryption = .none
        } else if doc.isLocked {
            encryption = .userPassword
        } else {
            encryption = .ownerOnly
        }

        return PDFInspection(
            pageCount: pageCount,
            encryption: encryption,
            hasTextLayer: hasTextLayer,
            isCorrupt: false
        )
    }

    /// Attempt to open a PDF with a candidate password. Returns the
    /// opened document on success, or `nil` if the password is wrong
    /// or the PDF uses unsupported encryption.
    ///
    /// For owner-restricted PDFs (encrypted but not locked) the document
    /// is returned as-is even with no password — PDFKit can read and
    /// re-write them without unlocking.
    public func open(url: URL, password: String?) -> PDFDocument? {
        guard let doc = PDFDocument(url: url) else { return nil }
        if !doc.isEncrypted { return doc }
        if !doc.isLocked { return doc }  // owner-only restrictions
        guard let password, !password.isEmpty else { return nil }
        return doc.unlock(withPassword: password) ? doc : nil
    }
}
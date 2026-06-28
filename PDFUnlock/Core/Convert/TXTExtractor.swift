import Foundation
import PDFKit

/// Extracts plain text from a PDF. Page boundaries are marked with the
/// form-feed character (`\f`) so downstream tools can re-split pages.
///
/// PDFKit's `PDFDocument.string` returns concatenated text without
/// reliable structure — it's fine for text-layer PDFs (the common case)
/// but returns empty for scanned PDFs with no OCR layer.
public struct TXTExtractor: Sendable {

    public init() {}

    public struct Result: Sendable {
        public let text: String
        public let pagesExtracted: Int
        public let pagesTotal: Int
        public let hadNoTextLayer: Bool
    }

    /// Extract text from `document`, optionally restricted to `pageRange`.
    public func extract(
        document: PDFDocument,
        pageRange: PageRange?
    ) -> Result {
        let total = document.pageCount
        var parts: [String] = []
        var pagesExtracted = 0

        for i in 0..<total {
            guard pageRange?.contains(i + 1) ?? true else { continue }
            guard let page = document.page(at: i) else { continue }
            let raw = page.string ?? ""
            // Normalize line endings, trim trailing whitespace per page,
            // and append a form-feed so downstream tools can split pages.
            let normalized = raw
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append(normalized)
            if !normalized.isEmpty { pagesExtracted += 1 }
        }

        let text = parts.joined(separator: "\n\u{0C}\n")
        let hadNoTextLayer = pagesExtracted == 0
        return Result(
            text: text,
            pagesExtracted: pagesExtracted,
            pagesTotal: total,
            hadNoTextLayer: hadNoTextLayer
        )
    }
}
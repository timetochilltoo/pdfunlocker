import Foundation
import PDFKit

/// Post-write verification. Reopens the output PDF and confirms it's
/// valid, unlocked, and matches the source page count.
public struct Verifier: Sendable {

    public init() {}

    public enum Verdict: Equatable, Sendable {
        case ok(pageCount: Int)
        case invalid
        case stillLocked
        case pageCountMismatch(expected: Int, actual: Int)
        case empty
    }

    public func verify(
        outputURL: URL,
        expectedPageCount: Int?
    ) -> Verdict {
        let attrs = try? FileManager.default.attributesOfItem(atPath: outputURL.path)
        let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        if size == 0 { return .empty }

        guard let doc = PDFDocument(url: outputURL) else { return .invalid }
        if doc.isLocked { return .stillLocked }
        let pageCount = doc.pageCount
        if let expected = expectedPageCount, expected > 0, expected != pageCount {
            return .pageCountMismatch(expected: expected, actual: pageCount)
        }
        return .ok(pageCount: pageCount)
    }
}
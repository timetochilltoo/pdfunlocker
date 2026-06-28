import Foundation
import PDFKit

/// Heuristic PDF → Markdown converter. **Experimental.**
///
/// This is best-effort. PDFKit gives us per-page text but loses most
/// structure info (font sizes, exact positions, columns). The heuristics
/// here are intentionally conservative:
///
/// - Lines that look like headings (short, mixed case, not ending in
///   punctuation) are upgraded to `#`/`##` headings based on
///   capitalization patterns.
/// - Lines starting with `- ` or `* ` become unordered list items.
/// - Lines starting with `<digits>. ` become ordered list items.
/// - Blank lines separate paragraphs.
/// - Pages are separated by `\n---\n` (horizontal rule).
///
/// If heuristics fail badly (e.g. no detectable structure across a 10+
/// page document), the entire output is replaced with a single fenced
/// code block containing the raw extracted text.
///
/// **Known limitations:** tables, multi-column layouts, sidebars, and
/// footnotes are not handled well. Use TXT for high-fidelity text
/// extraction and Markdown only when you need a quick-and-dirty
/// conversion of a simple document.
public struct MarkdownExporter: Sendable {

    public init() {}

    public enum Outcome: Sendable, Equatable {
        case heuristic
        case fallbackToRawText(reason: String)
    }

    public struct Result: Sendable {
        public let markdown: String
        public let outcome: Outcome
        public let pagesTotal: Int
    }

    /// Convert `document` to Markdown, restricted to `pageRange`.
    public func convert(
        document: PDFDocument,
        pageRange: PageRange?
    ) -> Result {
        let total = document.pageCount
        var pageTexts: [String] = []
        for i in 0..<total {
            guard pageRange?.contains(i + 1) ?? true else { continue }
            guard let page = document.page(at: i) else { continue }
            let text = (page.string ?? "")
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            pageTexts.append(text)
        }

        let joined = pageTexts.joined(separator: "\n\u{0C}\n")
        let (markdown, outcome) = renderHeuristic(joined: joined, pagesTotal: total)
        return Result(markdown: markdown, outcome: outcome, pagesTotal: total)
    }

    /// Try heuristics first; if they don't produce structure, fall back
    /// to a fenced code block with the raw text.
    private func renderHeuristic(joined: String, pagesTotal: Int) -> (String, Outcome) {
        // Split into page blocks by form feed.
        let pageBlocks = joined.components(separatedBy: "\u{0C}")

        var renderedPages: [String] = []
        var totalHeadings = 0
        var totalListItems = 0

        for pageText in pageBlocks {
            let (rendered, headings, listItems) = renderPage(pageText)
            renderedPages.append(rendered)
            totalHeadings += headings
            totalListItems += listItems
        }

        let markdown = renderedPages.joined(separator: "\n\n---\n\n")

        // Fallback condition: large multi-page doc with no detected structure.
        if pagesTotal >= 10 && totalHeadings == 0 && totalListItems == 0 {
            let fallback = "```\n\(joined)\n```\n"
            return (fallback, .fallbackToRawText(
                reason: "No detectable structure across \(pagesTotal) pages; emitting raw text."
            ))
        }

        return (markdown, .heuristic)
    }

    /// Render a single page of text. Returns the markdown plus counts
    /// of headings and list items (for fallback decision).
    private func renderPage(_ pageText: String) -> (String, headings: Int, listItems: Int) {
        var out: [String] = []
        var headings = 0
        var listItems = 0

        let lines = pageText.components(separatedBy: "\n")

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else {
                out.append("")  // paragraph break
                continue
            }

            // Unordered list: "- foo" or "* foo"
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                out.append(line)
                listItems += 1
                continue
            }

            // Ordered list: "1. foo" / "12. foo"
            if let dotIdx = line.firstIndex(of: "."),
               line.distance(from: line.startIndex, to: dotIdx) <= 4,
               line[..<dotIdx].allSatisfy(\.isNumber) {
                out.append(line)
                listItems += 1
                continue
            }

            // Heading heuristic: short line (<= 80 chars), no ending
            // punctuation other than `?`/`!`, and either Title Case or
            // ALL CAPS.
            if line.count <= 80,
               !line.hasSuffix(".") && !line.hasSuffix(","),
               !line.hasSuffix(";") && !line.hasSuffix(":"),
               isLikelyHeading(line) {
                let level = line == line.uppercased() ? 1 : 2
                out.append(String(repeating: "#", count: level) + " " + line)
                headings += 1
                continue
            }

            // Default: paragraph line.
            out.append(line)
        }

        // Collapse 3+ blank lines down to 2 (paragraph spacing).
        let collapsed = collapseBlankLines(out)
        return (collapsed.joined(separator: "\n"), headings, listItems)
    }

    private func isLikelyHeading(_ line: String) -> Bool {
        let words = line.split(separator: " ")
        guard !words.isEmpty, words.count <= 12 else { return false }
        // Title Case: most words start with an uppercase letter.
        let titleCased = words.dropFirst().filter { word in
            guard let first = word.first else { return false }
            return first.isUppercase
        }
        let titleCaseRatio = Double(titleCased.count) / Double(words.count - 1)
        let isTitleCase = titleCaseRatio >= 0.6
        let isAllCaps = line == line.uppercased() && line.contains { $0.isLetter }
        return isTitleCase || isAllCaps
    }

    private func collapseBlankLines(_ lines: [String]) -> [String] {
        var result: [String] = []
        var blankRun = 0
        for line in lines {
            if line.isEmpty {
                blankRun += 1
                if blankRun <= 1 {
                    result.append(line)
                }
            } else {
                blankRun = 0
                result.append(line)
            }
        }
        return result
    }
}
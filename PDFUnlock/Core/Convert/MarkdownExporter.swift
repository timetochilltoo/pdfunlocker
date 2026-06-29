import Foundation
import PDFKit

/// Heuristic PDF → Markdown converter. **Experimental.**
///
/// PDFKit's `page.string` gives us per-page text without position info
/// (no font sizes, no exact coordinates). So this heuristic is
/// intentionally conservative — it works well on text-heavy structured
/// documents (titles, section headers, short labels) and degrades on
/// complex layouts (tables, multi-column, sidebars).
///
/// Heuristics, in order:
/// - **Page separator**: `---` horizontal rule between pages.
/// - **Markdown literals** (preserve as-is): lines starting with `#`,
///   `>`, `- `, `* `, digit+`.`, or `|` (table row).
/// - **Numbered list items**: lines starting with `<digit>. ` or `<digit>) `.
/// - **Bullet list items**: lines starting with `- ` or `* ` (already handled
///   by markdown-literal pass, kept for clarity).
/// - **Metadata**: lines matching `^<Word>: <value>$` (e.g. `Generated: ...`)
///   rendered as italic body text.
/// - **Headings**: short lines (<= 80 chars) that are Title Case OR ALL
///   CAPS, no sentence-ending punctuation, no leading bullet/number.
///   `H1` for ALL CAPS or <= 3 words, `H2` otherwise.
/// - **Paragraphs**: everything else; consecutive non-blank lines that
///   don't end in sentence punctuation are joined.
/// - **Fallback**: if a 10+ page document produces zero headings and
///   zero list items, the entire output is replaced with a fenced code
///   block of the raw extracted text.
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

    // MARK: - Rendering

    private func renderHeuristic(joined: String, pagesTotal: Int) -> (String, Outcome) {
        let pageBlocks = joined.components(separatedBy: "\u{0C}")
        var renderedPages: [String] = []
        var totalHeadings = 0
        var totalListItems = 0
        var totalLiterals = 0

        for pageText in pageBlocks {
            let (rendered, h, l, lit) = renderPage(pageText)
            renderedPages.append(rendered)
            totalHeadings += h
            totalListItems += l
            totalLiterals += lit
        }

        let markdown = renderedPages.joined(separator: "\n\n---\n\n")

        // Fallback condition: large multi-page doc with no detected structure.
        if pagesTotal >= 10 && totalHeadings == 0 && totalListItems == 0 && totalLiterals == 0 {
            let fallback = "```\n\(joined)\n```\n"
            return (fallback, .fallbackToRawText(
                reason: "No detectable structure across \(pagesTotal) pages; emitting raw text."
            ))
        }

        return (markdown, .heuristic)
    }

    /// Render a single page of text. Returns the markdown plus counts.
    private func renderPage(_ pageText: String) -> (String, headings: Int, listItems: Int, literals: Int) {
        let lines = pageText.components(separatedBy: "\n")

        // Phase 1: classify each non-blank line.
        var classified: [(text: String, kind: LineKind)] = []
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else {
                classified.append((text: "", kind: .blank))
                continue
            }
            classified.append((text: line, kind: classify(line: line)))
        }

        // Phase 2: join consecutive paragraph lines that don't end in
        // sentence-ending punctuation into single paragraphs.
        let joined = joinParagraphs(classified)

        // Phase 3: render with blank-line separation between blocks.
        var out: [String] = []
        var headings = 0
        var listItems = 0
        var literals = 0

        for (text, kind) in joined {
            switch kind {
            case .blank:
                out.append("")
            case .literal:
                out.append(text)
                literals += 1
            case .listItem:
                out.append(text)
                listItems += 1
            case .metadata:
                out.append("*" + text + "*")
            case .heading(let level):
                out.append(String(repeating: "#", count: level) + " " + text)
                headings += 1
            case .paragraph:
                out.append(text)
            }
        }

        // Collapse 3+ blank lines down to 2 (paragraph spacing).
        let collapsed = collapseBlankLines(out)
        return (collapsed.joined(separator: "\n"), headings, listItems, literals)
    }

    // MARK: - Classification

    private enum LineKind: Equatable {
        case blank
        case literal       // preserve as-is
        case listItem
        case metadata      // "Key: Value" → italic
        case heading(Int)  // level 1 or 2
        case paragraph
    }

    private func classify(line: String) -> LineKind {
        // Markdown literals: lines starting with #, >, -, *, digit. or |
        // These were likely typed as markdown in the source document.
        if isMarkdownLiteral(line) {
            return .literal
        }

        // Numbered list: "1. foo" or "1) foo" — only when it's a leading digit
        // followed by . or ), then a space. Allow trailing whitespace
        // handling is implicit via the trim above.
        if isNumberedList(line) {
            return .listItem
        }

        // Metadata: "Key: Value" where Key is a single short word (no spaces).
        // E.g. "Generated: 2026-06-25 17:29" → italic.
        if isMetadata(line) {
            return .metadata
        }

        // Headings: short, Title Case or ALL CAPS, no sentence-ending punctuation.
        if let level = headingLevel(line) {
            return .heading(level)
        }

        return .paragraph
    }

    private func isMarkdownLiteral(_ line: String) -> Bool {
        // Lines that look like markdown the user typed into the source.
        if line.hasPrefix("#") { return true }       // headings/literal # at start
        if line.hasPrefix("> ") { return true }     // blockquote
        if line.hasPrefix("- ") { return true }     // bullet list
        if line.hasPrefix("* ") { return true }     // bullet list (alt)
        if line.hasPrefix("|") && line.hasSuffix("|") { return true }  // table row
        if line.hasPrefix("---") && line.allSatisfy({ $0 == "-" || $0 == " " }) { return true }  // hr / table sep
        return false
    }

    private func isNumberedList(_ line: String) -> Bool {
        // Match "<digits>. " or "<digits>) " at the start, where the
        // digit run is 1-3 chars (avoids matching "1.5" sentence starts
        // and URLs that happen to start with digits).
        var idx = line.startIndex
        var digitCount = 0
        while idx < line.endIndex, line[idx].isNumber, digitCount < 3 {
            line.formIndex(after: &idx)
            digitCount += 1
        }
        guard digitCount >= 1, idx < line.endIndex else { return false }
        let next = line[idx]
        guard next == "." || next == ")" else { return false }
        let afterMarker = line.index(after: idx)
        guard afterMarker < line.endIndex else { return false }
        return line[afterMarker] == " "
    }

    private func isMetadata(_ line: String) -> Bool {
        // "Word: rest" where Word has no spaces and rest is non-empty.
        // Examples: "Generated: 2026-06-25 17:29", "Date: 2024-01-01",
        // "Author: John Doe". Excludes "https://example.com" (colon mid-uri).
        guard let colonIdx = line.firstIndex(of: ":") else { return false }
        let key = line[line.startIndex..<colonIdx]
        guard !key.isEmpty,
              !key.contains(" "),
              key.count <= 20,
              key.first?.isLetter == true
        else { return false }
        // Reject URLs (colon mid-string after scheme)
        if key.lowercased().contains("http") { return false }
        let value = line[line.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return false }
        return true
    }

    /// Returns the heading level (1 or 2) if the line should be a
    /// heading, nil otherwise.
    private func headingLevel(_ line: String) -> Int? {
        // Constraints: short, no sentence-ending punctuation, looks like
        // a heading per isLikelyHeading.
        guard line.count <= 80 else { return nil }
        // Disallow common sentence-ending punctuation.
        let disallowEndings: Set<Character> = [".", ",", ";", ":", "?", "!"]
        if let last = line.last, disallowEndings.contains(last) { return nil }
        // Disallow lines starting with a digit (numbered lists handled
        // above; avoids treating "2024 Annual Report" as a heading).
        if line.first?.isNumber == true { return nil }
        // Disallow line containing "@" or starting with "(" (parenthetical).
        if line.contains("@") { return nil }
        if line.hasPrefix("(") { return nil }

        let words = line.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return nil }

        // ALL CAPS detection (with at least one letter): always a heading.
        let hasLetter = words.contains { $0.contains { $0.isLetter } }
        let isAllCaps = hasLetter && line == line.uppercased()
        if isAllCaps { return 1 }

        // Title Case detection.
        let titleWordCount = words.count
        // For 1-word lines: just check the first letter is uppercase.
        // For multi-word lines: at least 60% of words (excluding the first)
        // start with an uppercase letter.
        let isTitleCase: Bool
        if titleWordCount == 1 {
            isTitleCase = line.first?.isUppercase == true
        } else {
            let tailTitle = words.dropFirst().filter { word in
                // Strip leading punctuation before checking case.
                let cleaned = word.drop { !$0.isLetter }
                guard let firstLetter = cleaned.first else { return false }
                return firstLetter.isUppercase
            }
            let ratio = Double(tailTitle.count) / Double(words.count - 1)
            isTitleCase = ratio >= 0.6
        }
        if !isTitleCase { return nil }

        // Shorter headings get H1, longer ones get H2.
        return titleWordCount <= 3 ? 1 : 2
    }

    // MARK: - Paragraph joining

    /// Joins consecutive paragraph lines that don't end in sentence-
    /// ending punctuation. This handles cases where PDFKit emits one
    /// line per visual line (not per paragraph), so we need to
    /// reassemble.
    private func joinParagraphs(
        _ classified: [(text: String, kind: LineKind)]
    ) -> [(text: String, kind: LineKind)] {
        let sentenceEnd: Set<Character> = [".", "!", "?", ":", ";"]
        var result: [(text: String, kind: LineKind)] = []
        var pending: [String] = []
        var pendingKind: LineKind? = nil

        func flush() {
            guard !pending.isEmpty else { return }
            result.append((text: pending.joined(separator: " "), kind: pendingKind ?? .paragraph))
            pending.removeAll()
            pendingKind = nil
        }

        for (text, kind) in classified {
            switch kind {
            case .blank:
                flush()
                result.append((text: "", kind: .blank))
            case .literal, .listItem, .metadata, .heading:
                flush()
                result.append((text: text, kind: kind))
            case .paragraph:
                let lastChar = text.last
                let endsWithSentence = lastChar.map { sentenceEnd.contains($0) } ?? false
                if !pending.isEmpty, kind == pendingKind, !endsWithSentence {
                    pending.append(text)
                } else {
                    flush()
                    pending.append(text)
                    pendingKind = kind
                }
            }
        }
        flush()
        return result
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
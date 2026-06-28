import Foundation
import PDFKit

/// Orchestrates a single convert operation: opens PDF (via PDFKit),
/// dispatches to per-format extractors, writes outputs atomically.
///
/// Mirrors `PDFUnlocker`'s API shape. Like `PDFUnlocker`, it's a
/// `Sendable struct` with no mutable state — safe to call from any
/// actor.
public struct PDFConverter: Sendable {

    public struct Options: Sendable {
        public var formats: Set<ConvertFormat>
        public var pageRange: PageRange?
        public var pngDPI: Int

        public init(
            formats: Set<ConvertFormat> = [.txt],
            pageRange: PageRange? = nil,
            pngDPI: Int = 150
        ) {
            self.formats = formats
            self.pageRange = pageRange
            self.pngDPI = pngDPI
        }
    }

    private let inspector: PDFInspector
    private let naming: FileNaming
    private let txtExtractor: TXTExtractor
    private let pngExporter: PNGExporter
    private let mdExporter: MarkdownExporter

    public init(
        inspector: PDFInspector = PDFInspector(),
        naming: FileNaming = FileNaming(suffix: "-converted"),
        txtExtractor: TXTExtractor = TXTExtractor(),
        pngExporter: PNGExporter = PNGExporter(),
        mdExporter: MarkdownExporter = MarkdownExporter()
    ) {
        self.inspector = inspector
        self.naming = naming
        self.txtExtractor = txtExtractor
        self.pngExporter = pngExporter
        self.mdExporter = mdExporter
    }

    /// Per-format output URLs keyed by format. PNG outputs are
    /// represented as `[folderURL]` (the folder containing the pages).
    public struct Output: Sendable, Equatable {
        public var txt: URL?
        public var md: URL?
        public var pngFolder: URL?
    }

    /// Per-job result with all format outputs and a status per format.
    public struct ConvertResult: Sendable {
        public let output: Output
        public let mdOutcome: MarkdownExporter.Outcome?
        public let hadNoTextLayer: Bool
    }

    /// Convert `input` per `options`. Writes outputs to `outputDirectory`
    /// using the configured suffix. Returns the written paths.
    public func convert(
        input: URL,
        outputDirectory: URL,
        options: Options
    ) async throws -> ConvertResult {
        try Task.checkCancellation()

        guard FileManager.default.fileExists(atPath: input.path) else {
            throw ConvertError.fileNotFound(path: input.path)
        }

        guard let doc = PDFDocument(url: input) else {
            throw ConvertError.corruptPDF
        }

        if doc.isLocked {
            throw ConvertError.encryptedNeedsUnlock
        }

        try Task.checkCancellation()

        var output = Output()
        var mdOutcome: MarkdownExporter.Outcome?
        var hadNoTextLayer = false
        var failures: [(ConvertFormat, String)] = []

        // TXT
        if options.formats.contains(.txt) {
            do {
                let url = outputDirectory.appendingPathComponent(
                    naming.defaultOutput(for: input, target: .convert).lastPathComponent
                ).replacingExtension(with: "txt")
                let result = txtExtractor.extract(document: doc, pageRange: options.pageRange)
                try writeText(result.text, to: url)
                output.txt = url
                if result.hadNoTextLayer { hadNoTextLayer = true }
            } catch {
                failures.append((.txt, error.localizedDescription))
            }
        }

        try Task.checkCancellation()

        // MD
        if options.formats.contains(.md) {
            do {
                let url = outputDirectory.appendingPathComponent(
                    naming.defaultOutput(for: input, target: .convert).lastPathComponent
                ).replacingExtension(with: "md")
                let result = mdExporter.convert(document: doc, pageRange: options.pageRange)
                try writeText(result.markdown, to: url)
                output.md = url
                mdOutcome = result.outcome
                if case .fallbackToRawText = result.outcome {
                    hadNoTextLayer = true
                }
            } catch {
                failures.append((.md, error.localizedDescription))
            }
        }

        try Task.checkCancellation()

        // PNG
        if options.formats.contains(.png) {
            do {
                let stem = naming.defaultOutput(for: input, target: .convert).deletingPathExtension().lastPathComponent
                let folder = outputDirectory.appendingPathComponent("\(stem)-images", isDirectory: true)
                _ = try pngExporter.export(
                    document: doc,
                    to: folder,
                    pageRange: options.pageRange,
                    dpi: options.pngDPI
                )
                output.pngFolder = folder
            } catch {
                failures.append((.png, error.localizedDescription))
            }
        }

        // If every requested format failed, surface a generic error.
        if output.txt == nil && output.md == nil && output.pngFolder == nil {
            let summary = failures.map { "\($0.0.displayName): \($0.1)" }.joined(separator: "; ")
            throw ConvertError.allFormatsFailed(detail: summary)
        }

        return ConvertResult(
            output: output,
            mdOutcome: mdOutcome,
            hadNoTextLayer: hadNoTextLayer
        )
    }

    private func writeText(_ text: String, to url: URL) throws {
        // UTF-8, no BOM. Atomic write via Data.
        guard let data = text.data(using: .utf8) else {
            throw ConvertError.encodingFailed
        }
        try data.write(to: url, options: .atomic)
    }
}

/// URL replacement helper (URL doesn't have `.replacingExtension` on iOS 14+? It does on macOS 13+).
private extension URL {
    func replacingExtension(with ext: String) -> URL {
        deletingPathExtension().appendingPathExtension(ext)
    }
}

public enum ConvertError: LocalizedError, Sendable, Equatable {
    case fileNotFound(path: String)
    case corruptPDF
    case encryptedNeedsUnlock
    case encodingFailed
    case allFormatsFailed(detail: String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound:        return "The PDF could not be found."
        case .corruptPDF:          return "This file could not be opened as a valid PDF."
        case .encryptedNeedsUnlock:
            return "This PDF is encrypted. Unlock it first (or use Unlock mode)."
        case .encodingFailed:      return "Could not encode the converted text as UTF-8."
        case .allFormatsFailed:    return "All requested conversion formats failed."
        }
    }
}
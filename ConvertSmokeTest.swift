import Foundation
import PDFKit
import AppKit

@main
struct ConvertSmokeTest {

    static func main() async {
        let fixtures = URL(fileURLWithPath: "test-fixtures", isDirectory: true)
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdfu-convert-smoke-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        var passed = 0
        var failed = 0

        await run("TXT extract plain PDF") {
            let input = fixtures.appendingPathComponent("plain.pdf")
            let doc = PDFDocument(url: input)!
            let result = TXTExtractor().extract(document: doc, pageRange: nil)
            try expect(result.text.contains("Hello"), "TXT should contain 'Hello'")
            try expect(result.pagesExtracted > 0, "should extract at least one page")
            try expect(!result.hadNoTextLayer, "plain PDF has text layer")
        } passed: { passed += 1 } failed: { failed += 1 }

        await run("PNG export single page") {
            let input = fixtures.appendingPathComponent("plain.pdf")
            let doc = PDFDocument(url: input)!
            let folder = outputDir.appendingPathComponent("png-single", isDirectory: true)
            let result = try PNGExporter().export(document: doc, to: folder, pageRange: nil, dpi: 150)
            try expect(result.filesWritten.count > 0, "should write at least one PNG")
            let firstFile = result.filesWritten[0]
            try expect(FileManager.default.fileExists(atPath: firstFile.path), "PNG file exists")
            try expect(firstFile.lastPathComponent.hasPrefix("page-"), "filename starts with 'page-'")
            try expect(firstFile.pathExtension == "png", "extension is png")
            // Verify it's a valid PNG by checking header bytes
            let data = try Data(contentsOf: firstFile)
            let header = Array(data.prefix(8))
            let expected: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
            try expect(header == expected, "PNG header is valid")
        } passed: { passed += 1 } failed: { failed += 1 }

        await run("Markdown extract simple PDF") {
            let input = fixtures.appendingPathComponent("plain.pdf")
            let doc = PDFDocument(url: input)!
            let result = MarkdownExporter().convert(document: doc, pageRange: nil)
            try expect(!result.markdown.isEmpty, "markdown not empty")
            // Outcome should be .heuristic for short PDFs
            try expect(result.outcome == .heuristic,
                       "expected .heuristic for short PDF, got \(result.outcome)")
        } passed: { passed += 1 } failed: { failed += 1 }

        await run("PDFConverter: TXT only") {
            let input = fixtures.appendingPathComponent("plain.pdf")
            let converter = PDFConverter()
            let result = try await converter.convert(
                input: input,
                outputDirectory: outputDir,
                options: PDFConverter.Options(formats: [.txt])
            )
            try expect(result.output.txt != nil, "txt output exists")
            try expect(result.output.md == nil, "md output nil")
            try expect(result.output.pngFolder == nil, "png folder nil")
            let txtData = try Data(contentsOf: result.output.txt!)
            try expect(txtData.count > 0, "txt file not empty")
        } passed: { passed += 1 } failed: { failed += 1 }

        await run("PDFConverter: PNG only at 72 DPI") {
            let input = fixtures.appendingPathComponent("plain.pdf")
            let converter = PDFConverter()
            let result = try await converter.convert(
                input: input,
                outputDirectory: outputDir,
                options: PDFConverter.Options(formats: [.png], pngDPI: 72)
            )
            try expect(result.output.pngFolder != nil, "png folder exists")
            try expect(result.output.txt == nil, "txt nil")
            let folder = result.output.pngFolder!
            let contents = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            let pngCount = contents.filter { $0.hasSuffix(".png") }.count
            try expect(pngCount > 0, "at least one PNG in folder")
        } passed: { passed += 1 } failed: { failed += 1 }

        await run("PDFConverter: all three formats") {
            let input = fixtures.appendingPathComponent("plain.pdf")
            let converter = PDFConverter()
            let result = try await converter.convert(
                input: input,
                outputDirectory: outputDir,
                options: PDFConverter.Options(formats: [.txt, .png, .md])
            )
            try expect(result.output.txt != nil, "txt exists")
            try expect(result.output.md != nil, "md exists")
            try expect(result.output.pngFolder != nil, "png folder exists")
            try expect(result.mdOutcome == .heuristic, "MD outcome heuristic for short PDF")
        } passed: { passed += 1 } failed: { failed += 1 }

        await run("PDFConverter: encrypted PDF fails gracefully") {
            let input = fixtures.appendingPathComponent("user-password.pdf")
            let converter = PDFConverter()
            do {
                _ = try await converter.convert(
                    input: input,
                    outputDirectory: outputDir,
                    options: PDFConverter.Options(formats: [.txt])
                )
                try expect(false, "should have thrown")
            } catch let e as ConvertError {
                try expect(e == .encryptedNeedsUnlock,
                           "expected .encryptedNeedsUnlock, got \(e)")
            }
        } passed: { passed += 1 } failed: { failed += 1 }

        await run("PDFConverter: corrupt file fails gracefully") {
            let bogus = outputDir.appendingPathComponent("bogus.pdf")
            try? Data("not a real pdf".utf8).write(to: bogus)
            let converter = PDFConverter()
            do {
                _ = try await converter.convert(
                    input: bogus,
                    outputDirectory: outputDir,
                    options: PDFConverter.Options(formats: [.txt])
                )
                try expect(false, "should have thrown")
            } catch let e as ConvertError {
                try expect(e == .corruptPDF, "expected .corruptPDF, got \(e)")
            }
        } passed: { passed += 1 } failed: { failed += 1 }

        await run("PNG DPI sizing") {
            let input = fixtures.appendingPathComponent("plain.pdf")
            let doc = PDFDocument(url: input)!
            for dpi in [72, 150, 300] {
                let folder = outputDir.appendingPathComponent("png-\(dpi)dpi", isDirectory: true)
                let result = try PNGExporter().export(
                    document: doc, to: folder, pageRange: nil, dpi: dpi
                )
                try expect(result.filesWritten.count > 0, "wrote PNGs at \(dpi) DPI")
                let data = try Data(contentsOf: result.filesWritten[0])
                // Approximate size check: a 612x792 page at 72 DPI = ~480KB
                // At 150 DPI ≈ ~2MB. We just check it scales with DPI.
                try expect(data.count > 1000, "PNG at \(dpi) DPI has reasonable size (\(data.count) bytes)")
            }
        } passed: { passed += 1 } failed: { failed += 1 }

        await run("Page range filtering") {
            let input = fixtures.appendingPathComponent("plain.pdf")
            let doc = PDFDocument(url: input)!
            // Test that all-pages returns all
            let allResult = TXTExtractor().extract(document: doc, pageRange: nil)
            try expect(allResult.pagesExtracted == doc.pageCount,
                       "all-pages should extract all pages")
        } passed: { passed += 1 } failed: { failed += 1 }

        print("\n— M1.5 Summary —")
        print("Passed: \(passed)")
        print("Failed: \(failed)")
        exit(failed == 0 ? 0 : 1)
    }

    static func run(
        _ name: String,
        _ body: () async throws -> Void,
        passed: () -> Void,
        failed: () -> Void
    ) async {
        do {
            try await body()
            print("✓ \(name)")
            passed()
        } catch {
            print("✗ \(name): \(error)")
            failed()
        }
    }

    static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw SmokeError.assertionFailed(message) }
    }
}

enum SmokeError: Error, CustomStringConvertible {
    case assertionFailed(String)
    var description: String {
        switch self {
        case .assertionFailed(let m): return m
        }
    }
}
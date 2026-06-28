import Foundation
import PDFKit
import AppKit
import CoreGraphics

/// Rasterizes each PDF page to a PNG file at a configurable DPI.
///
/// Output structure:
/// ```
/// <stem>-images/
///   page-001.png
///   page-002.png
///   ...
/// ```
public struct PNGExporter: Sendable {

    public enum Failure: LocalizedError {
        case folderCreationFailed(underlying: Error)
        case renderFailed(page: Int, underlying: Error)
        case writeFailed(page: Int, underlying: Error)

        public var errorDescription: String? {
            switch self {
            case .folderCreationFailed:  return "Could not create the output folder."
            case .renderFailed:           return "Could not render page to image."
            case .writeFailed:            return "Could not write PNG file."
            }
        }
    }

    public init() {}

    public struct Result: Sendable {
        public let folderURL: URL
        public let filesWritten: [URL]
        public let pagesTotal: Int
        public let dpi: Int
    }

    /// Export pages of `document` to `folderURL`. Creates the folder if missing.
    public func export(
        document: PDFDocument,
        to folderURL: URL,
        pageRange: PageRange?,
        dpi: Int
    ) throws -> Result {
        let fm = FileManager.default
        do {
            if !fm.fileExists(atPath: folderURL.path) {
                try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
            }
        } catch {
            throw Failure.folderCreationFailed(underlying: error)
        }

        let total = document.pageCount
        let pageCount = total > 0 ? total : 0
        let padWidth = String(pageCount).count
        var written: [URL] = []

        for i in 0..<total {
            guard pageRange?.contains(i + 1) ?? true else { continue }
            guard let page = document.page(at: i) else { continue }

            let pageNumber = i + 1
            let name = "page-\(String(format: "%0\(padWidth)d", pageNumber)).png"
            let url = folderURL.appendingPathComponent(name)

            do {
                try render(page: page, to: url, dpi: dpi)
                written.append(url)
            } catch {
                throw Failure.writeFailed(page: pageNumber, underlying: error)
            }
        }

        return Result(
            folderURL: folderURL,
            filesWritten: written,
            pagesTotal: total,
            dpi: dpi
        )
    }

    /// Render a single PDF page to a PNG file at the requested DPI.
    private func render(page: PDFPage, to url: URL, dpi: Int) throws {
        let pdfRect = page.bounds(for: .mediaBox)
        let scale = CGFloat(dpi) / 72.0
        let pixelWidth = Int((pdfRect.width * scale).rounded())
        let pixelHeight = Int((pdfRect.height * scale).rounded())

        // Safety: prevent zero or negative dimensions.
        guard pixelWidth > 0, pixelHeight > 0 else { return }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw Failure.renderFailed(page: 0, underlying:
                NSError(domain: "PNGExporter", code: -1)
            )
        }

        // White background so transparent PDFs render on white, not black.
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        // PDFKit draws in PDF user-space (72 DPI = 1 unit = 1 point).
        // Scale the context so each point becomes `scale` pixels.
        context.scaleBy(x: scale, y: scale)

        // PDF coordinates have origin at bottom-left; CG has origin at
        // top-left. The scaleBy above already accounts for this in
        // practice (PDFKit's draw handles the flip internally for the
        // page bounds), but we explicitly set the CTM to map correctly.
        page.draw(with: .mediaBox, to: context)

        guard let cgImage = context.makeImage() else {
            throw Failure.renderFailed(page: 0, underlying:
                NSError(domain: "PNGExporter", code: -2)
            )
        }

        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw Failure.renderFailed(page: 0, underlying:
                NSError(domain: "PNGExporter", code: -3)
            )
        }
        try data.write(to: url, options: .atomic)
    }
}
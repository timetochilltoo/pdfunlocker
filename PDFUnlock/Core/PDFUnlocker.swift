import Foundation
import PDFKit

/// Orchestrates a single unlock: PDFKit (with optional password) →
/// qpdf fallback → atomic write → verification.
public struct PDFUnlocker: Sendable {

    public struct Options: Sendable {
        public var overwriteExisting: Bool
        public var preserveMetadata: Bool
        public var useQPDFFallback: Bool

        public init(
            overwriteExisting: Bool = false,
            preserveMetadata: Bool = true,
            useQPDFFallback: Bool = true
        ) {
            self.overwriteExisting = overwriteExisting
            self.preserveMetadata = preserveMetadata
            self.useQPDFFallback = useQPDFFallback
        }
    }

    private let inspector: PDFInspector
    private let verifier: Verifier
    private let naming: FileNaming
    private let qpdf: QPDFRunner

    public init(
        inspector: PDFInspector = PDFInspector(),
        verifier: Verifier = Verifier(),
        naming: FileNaming = FileNaming(suffix: "-unlocked"),
        qpdf: QPDFRunner = QPDFRunner()
    ) {
        self.inspector = inspector
        self.verifier = verifier
        self.naming = naming
        self.qpdf = qpdf
    }

    /// Inspect a PDF and produce an inspection record.
    public func inspect(_ input: URL) -> PDFInspection {
        inspector.inspect(input)
    }

    /// Unlock a single PDF. Throws `UnlockError` on failure.
    /// Cancellation propagates as `.cancelled`.
    ///
    /// Strategy:
    /// 1. For `.ownerOnly` encryption, prefer qpdf — PDFKit re-saves
    ///    preserve the restriction flags, which is useless to the user.
    /// 2. For other encryption kinds, try PDFKit first.
    /// 3. On PDFKit failure that is likely recoverable (corrupt /
    ///    unsupported / verification failed), try qpdf `--decrypt`.
    /// 4. On user-input failures (wrong password, missing password),
    ///    surface the PDFKit error directly — qpdf won't help.
    public func unlock(
        input: URL,
        output: URL,
        password: String?,
        options: Options = Options()
    ) async throws -> UnlockResult {
        try Task.checkCancellation()

        guard FileManager.default.fileExists(atPath: input.path) else {
            throw UnlockError.fileNotFound(path: input.path)
        }

        let inspection = inspector.inspect(input)
        try Task.checkCancellation()

        // Owner-restricted PDFs: PDFKit re-saves preserve the flags.
        // Go straight to qpdf for a truly unrestricted output.
        if inspection.encryption == .ownerOnly,
           options.useQPDFFallback {
            return try await unlockWithQPDF(
                input: input,
                output: output,
                password: password
            )
        }

        // Try PDFKit first for everything else.
        do {
            return try await unlockWithPDFKit(
                inspection: inspection,
                input: input,
                output: output,
                password: password
            )
        } catch let pdfKitError as UnlockError {
            // Surface user-error cases directly — qpdf won't help.
            switch pdfKitError {
            case .wrongPassword,
                 .missingPassword,
                 .fileNotFound,
                 .permissionDenied,
                 .cancelled,
                 .qpdfUnavailable,
                 .verificationFailed:
                // verificationFailed: PDFKit might still be right that the
                // output is bad, but qpdf can produce a cleaner output.
                if case .verificationFailed = pdfKitError, options.useQPDFFallback {
                    break
                }
                throw pdfKitError
            case .corruptPDF, .unsupportedEncryption:
                // Fall through to qpdf.
                break
            default:
                throw pdfKitError
            }

            guard options.useQPDFFallback else {
                throw pdfKitError
            }
            return try await unlockWithQPDF(
                input: input,
                output: output,
                password: password,
                originalError: pdfKitError
            )
        }
    }

    // MARK: - PDFKit path

    private func unlockWithPDFKit(
        inspection: PDFInspection,
        input: URL,
        output: URL,
        password: String?
    ) async throws -> UnlockResult {
        guard !inspection.isCorrupt else { throw UnlockError.corruptPDF }
        if inspection.encryption == .unsupported {
            throw UnlockError.unsupportedEncryption(
                detail: "PDFKit does not recognise this encryption."
            )
        }
        if inspection.encryption == .userPassword,
           (password ?? "").isEmpty {
            throw UnlockError.missingPassword
        }

        guard let doc = inspector.open(url: input, password: password) else {
            if inspection.encryption == .userPassword {
                throw UnlockError.wrongPassword
            }
            throw UnlockError.corruptPDF
        }

        try Task.checkCancellation()
        return try await writePDFKit(doc: doc, to: output, expectedPageCount: inspection.pageCount)
    }

    private func writePDFKit(
        doc: PDFDocument,
        to outputURL: URL,
        expectedPageCount: Int
    ) async throws -> UnlockResult {
        try Task.checkCancellation()

        let dir = outputURL.deletingLastPathComponent()
        let tempURL = dir.appendingPathComponent(".pdfu-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let writeOK = doc.write(to: tempURL)
        guard writeOK else {
            throw UnlockError.writeFailed(
                underlying: "PDFKit refused to write to \(tempURL.lastPathComponent)."
            )
        }

        switch verifier.verify(outputURL: tempURL, expectedPageCount: expectedPageCount) {
        case .ok:
            break
        case .invalid:
            throw UnlockError.verificationFailed(reason: "Output is not a valid PDF.")
        case .stillLocked:
            throw UnlockError.verificationFailed(
                reason: "Output still requires a password to open."
            )
        case .pageCountMismatch(let expected, let actual):
            throw UnlockError.verificationFailed(
                reason: "Page count mismatch (expected \(expected), got \(actual))."
            )
        case .empty:
            throw UnlockError.verificationFailed(reason: "Output file is empty.")
        }

        try moveIntoPlace(tempURL: tempURL, outputURL: outputURL)

        try Task.checkCancellation()

        return UnlockResult(
            outputURL: outputURL,
            pageCount: expectedPageCount,
            verifiedAt: Date()
        )
    }

    // MARK: - qpdf path

    private func unlockWithQPDF(
        input: URL,
        output: URL,
        password: String?,
        originalError: UnlockError? = nil
    ) async throws -> UnlockResult {
        let inspection = inspector.inspect(input)

        // Write to a temp file first, verify, then move into place.
        let dir = output.deletingLastPathComponent()
        let tempURL = dir.appendingPathComponent(".pdfu-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            try await qpdf.decrypt(input: input, output: tempURL, password: password)
        } catch let qpdfError as UnlockError {
            // If qpdf also fails, surface the most actionable error.
            // Prefer qpdf's error (usually more accurate), unless it's
            // qpdfUnavailable (then surface the original if available).
            if case .qpdfUnavailable = qpdfError { throw originalError ?? qpdfError }
            throw qpdfError
        }

        // Verify the qpdf output.
        let expected = inspection.pageCount > 0 ? inspection.pageCount : nil
        switch verifier.verify(outputURL: tempURL, expectedPageCount: expected) {
        case .ok(let pageCount):
            try moveIntoPlace(tempURL: tempURL, outputURL: output)
            return UnlockResult(outputURL: output, pageCount: pageCount, verifiedAt: Date())
        case .invalid:
            throw UnlockError.verificationFailed(reason: "qpdf output is not a valid PDF.")
        case .stillLocked:
            throw UnlockError.wrongPassword
        case .pageCountMismatch(let expected, let actual):
            throw UnlockError.verificationFailed(
                reason: "qpdf output page count mismatch (expected \(expected), got \(actual))."
            )
        case .empty:
            throw UnlockError.verificationFailed(reason: "qpdf output is empty.")
        }
    }

    // MARK: - Shared helpers

    private func moveIntoPlace(tempURL: URL, outputURL: URL) throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            _ = try FileManager.default.replaceItemAt(outputURL, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: outputURL)
        }
    }
}
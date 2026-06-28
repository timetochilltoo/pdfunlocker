import Foundation

/// Wrapper around the bundled `qpdf` binary. Locates it via
/// `Bundle.main` (Resources/qpdf), executes it via `Process`, and maps
/// stderr / exit codes back to typed `UnlockError`s.
public struct QPDFRunner: Sendable {

    public init() {}

    // MARK: - Locate

    /// Returns the URL of the bundled qpdf binary, or `nil` if missing.
    /// Synchronous and cheap — just a bundle lookup.
    public func locateQPDF() -> URL? {
        // Bundle.main when running inside the app
        if let url = Bundle.main.url(forResource: "qpdf", withExtension: nil),
           FileManager.default.isExecutableFile(atPath: url.path) {
            return url
        }
        // For tests / out-of-bundle contexts (where Bundle.main is the
        // test runner, not the app): look in the source tree.
        let sourceCandidate = URL(fileURLWithPath: "PDFUnlock/Resources/qpdf")
        if FileManager.default.isExecutableFile(atPath: sourceCandidate.path) {
            return sourceCandidate
        }
        return nil
    }

    // MARK: - Decrypt

    /// Run `qpdf --decrypt` against an input file. On success, `output`
    /// contains the decrypted PDF. On failure, throws a typed error.
    ///
    /// Cancellation: `Task.checkCancellation` is polled between phases.
    public func decrypt(
        input: URL,
        output: URL,
        password: String?
    ) async throws {
        try Task.checkCancellation()
        guard let qpdf = locateQPDF() else {
            throw UnlockError.qpdfUnavailable
        }
        guard FileManager.default.fileExists(atPath: input.path) else {
            throw UnlockError.fileNotFound(path: input.path)
        }

        try await Task.detached(priority: .userInitiated) {
            try Self.runQPDF(qpdf: qpdf, input: input, output: output, password: password)
        }.value
    }

    /// Run `qpdf --decrypt` synchronously. Caller wraps in `Task.detached`.
    private static func runQPDF(
        qpdf: URL,
        input: URL,
        output: URL,
        password: String?
    ) throws {
        let process = Process()
        process.executableURL = qpdf
        process.arguments = arguments(input: input, output: output, password: password)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // `Process` is not Sendable; we keep it inside this detached
        // task so it never crosses an actor boundary.

        try process.run()

        // Read pipes fully to avoid blocking on full buffer.
        _ = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            return
        }

        let stderr = String(data: errData, encoding: .utf8) ?? ""
        throw mapQPDFError(stderr: stderr, exitCode: process.terminationStatus)
    }

    /// Build the argument vector. Empty / nil password is supported
    /// (qpdf uses an empty user password when none supplied).
    private static func arguments(
        input: URL,
        output: URL,
        password: String?
    ) -> [String] {
        var args = ["--decrypt"]
        // Always pass --password, even if empty, so qpdf's CLI parsing
        // is unambiguous.
        let pw = password ?? ""
        args.append("--password=\(pw)")
        args.append(input.path)
        args.append(output.path)
        return args
    }

    /// Map qpdf exit codes and stderr to typed errors.
    /// Reference: qpdf returns 0 on success, 2 on usage errors, 3 on
    /// I/O errors, and various other codes for runtime failures.
    static func mapQPDFError(stderr: String, exitCode: Int32) -> UnlockError {
        let lower = stderr.lowercased()

        if lower.contains("invalid password") || lower.contains("password incorrect") {
            return .wrongPassword
        }
        if lower.contains("supplied password") && lower.contains("user password") {
            return .wrongPassword
        }
        if lower.contains("file is damaged") || lower.contains("could not parse") {
            return .corruptPDF
        }
        if lower.contains("unsupported") || lower.contains("not supported") {
            return .unsupportedEncryption(detail: stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if lower.contains("encrypted") && lower.contains("drm") {
            return .drmProtected
        }
        if lower.contains("permission") || lower.contains("denied") {
            return .permissionDenied(path: "qpdf target")
        }
        if lower.contains("disk full") || lower.contains("no space") {
            return .diskFull
        }
        if lower.contains("password") {
            return .wrongPassword
        }

        // Generic fallback
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = trimmed.isEmpty ? "qpdf exit \(exitCode)" : trimmed
        return .writeFailed(underlying: detail)
    }
}
// Standalone smoke test for M1 Core modules.
// Compile: swiftc -parse-as-library SmokeTest.swift Core/*.swift Models/*.swift Settings/*.swift
// Or run: xcodebuild ... && run the binary
//
// This file is meant to be run from the project root and exercises the
// inspect → unlock → verify pipeline against real PDFs.

import Foundation
import PDFKit

@main
struct SmokeTest {

    static func main() async {
        let fixtures = URL(fileURLWithPath: "test-fixtures", isDirectory: true)
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdfu-smoke-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        var passed = 0
        var failed = 0

        // Test 1: Inspect plain PDF
        await run("Inspect plain PDF") {
            let inspection = PDFInspector().inspect(fixtures.appendingPathComponent("plain.pdf"))
            try expect(inspection.encryption == .none, "expected .none, got \(inspection.encryption)")
            try expect(!inspection.isCorrupt, "should not be corrupt")
            try expect(inspection.pageCount > 0, "should have pages")
        } passed: { passed += 1 } failed: { failed += 1 }

        // Test 2: Inspect owner-restricted PDF
        await run("Inspect owner-restricted PDF") {
            let inspection = PDFInspector().inspect(fixtures.appendingPathComponent("owner-restricted.pdf"))
            try expect(inspection.encryption == .ownerOnly, "expected .ownerOnly, got \(inspection.encryption)")
        } passed: { passed += 1 } failed: { failed += 1 }

        // Test 3: Inspect user-password PDF
        await run("Inspect user-password PDF") {
            let inspection = PDFInspector().inspect(fixtures.appendingPathComponent("user-password.pdf"))
            try expect(inspection.encryption == .userPassword, "expected .userPassword, got \(inspection.encryption)")
        } passed: { passed += 1 } failed: { failed += 1 }

        // Test 4: Unlock user-password PDF with correct password
        await run("Unlock user-password PDF (correct password)") {
            let input = fixtures.appendingPathComponent("user-password.pdf")
            let output = outputDir.appendingPathComponent("user-password-unlocked.pdf")
            let result = try await PDFUnlocker().unlock(input: input, output: output, password: "openpass")
            try expect(FileManager.default.fileExists(atPath: result.outputURL.path), "output should exist")
            try expect(PDFInspector().open(url: result.outputURL, password: nil) != nil, "output should open without password")
        } passed: { passed += 1 } failed: { failed += 1 }

        // Test 5: Unlock with wrong password fails
        await run("Unlock with wrong password fails") {
            let input = fixtures.appendingPathComponent("user-password.pdf")
            let output = outputDir.appendingPathComponent("should-not-exist.pdf")
            do {
                _ = try await PDFUnlocker().unlock(input: input, output: output, password: "wrong")
                try expect(false, "should have thrown")
            } catch let e as UnlockError {
                switch e {
                case .wrongPassword, .verificationFailed: break
                default: try expect(false, "wrong error: \(e)")
                }
            }
            try expect(!FileManager.default.fileExists(atPath: output.path), "output should not exist")
        } passed: { passed += 1 } failed: { failed += 1 }

        // Test 6: Unlock with missing password fails
        await run("Unlock with missing password fails") {
            let input = fixtures.appendingPathComponent("user-password.pdf")
            let output = outputDir.appendingPathComponent("should-not-exist.pdf")
            do {
                _ = try await PDFUnlocker().unlock(input: input, output: output, password: nil)
                try expect(false, "should have thrown")
            } catch let e as UnlockError {
                switch e {
                case .missingPassword, .wrongPassword: break
                default: try expect(false, "wrong error: \(e)")
                }
            }
        } passed: { passed += 1 } failed: { failed += 1 }

        // Test 7: Unlock corrupt file
        await run("Unlock corrupt file fails") {
            let bogus = outputDir.appendingPathComponent("bogus.pdf")
            try Data("not a real pdf".utf8).write(to: bogus)
            let output = outputDir.appendingPathComponent("output.pdf")
            do {
                _ = try await PDFUnlocker().unlock(input: bogus, output: output, password: nil)
                try expect(false, "should have thrown")
            } catch let e as UnlockError {
                // Accept any failure category from PDFKit or qpdf —
                // both should reject garbage input.
                switch e {
                case .corruptPDF, .unsupportedEncryption, .writeFailed, .verificationFailed:
                    break
                default:
                    try expect(false, "unexpected error type: \(e)")
                }
            }
        } passed: { passed += 1 } failed: { failed += 1 }

        // Test 8: Owner-restricted PDF unlocks without password
        await run("Unlock owner-restricted PDF (no password needed)") {
            // macOS 26 PDFKit rejects 40-bit encrypted PDFs as "corrupt";
            // the 128-bit fixture opens cleanly.
            let input = fixtures.appendingPathComponent("owner-restricted-128.pdf")
            let output = outputDir.appendingPathComponent("owner-unlocked.pdf")
            let result = try await PDFUnlocker().unlock(input: input, output: output, password: nil)
            try expect(FileManager.default.fileExists(atPath: result.outputURL.path), "output should exist")
        } passed: { passed += 1 } failed: { failed += 1 }

        // M2: qpdf fallback tests
        // Test 9: qpdf fallback handles 40-bit encrypted PDF
        await run("Unlock 40-bit encrypted PDF via qpdf fallback") {
            let input = fixtures.appendingPathComponent("weak-40bit.pdf")
            let output = outputDir.appendingPathComponent("weak-40bit-unlocked.pdf")
            let result = try await PDFUnlocker().unlock(
                input: input,
                output: output,
                password: "secret123"
            )
            try expect(FileManager.default.fileExists(atPath: result.outputURL.path), "output should exist")
            try expect(PDFInspector().open(url: result.outputURL, password: nil) != nil, "output should open without password")
        } passed: { passed += 1 } failed: { failed += 1 }

        // Test 10: qpdf fallback rejects wrong password
        await run("Unlock 40-bit PDF with wrong password via qpdf fails") {
            let input = fixtures.appendingPathComponent("weak-40bit.pdf")
            let output = outputDir.appendingPathComponent("should-not-exist.pdf")
            do {
                _ = try await PDFUnlocker().unlock(input: input, output: output, password: "wrongguess")
                try expect(false, "should have thrown")
            } catch let e as UnlockError {
                switch e {
                case .wrongPassword: break
                default: try expect(false, "expected .wrongPassword, got \(e)")
                }
            }
            try expect(!FileManager.default.fileExists(atPath: output.path), "output should not exist")
        } passed: { passed += 1 } failed: { failed += 1 }

        // Test 11: qpdf strips restrictions from 40-bit encrypted PDF
        await run("qpdf strips encryption from 40-bit PDF (output is fully clean)") {
            // 40-bit encryption is rejected by PDFKit, so this test
            // exercises the qpdf path. The output should be fully clean.
            let input = fixtures.appendingPathComponent("weak-40bit.pdf")
            let output = outputDir.appendingPathComponent("weak-40bit-clean.pdf")
            let result = try await PDFUnlocker().unlock(
                input: input,
                output: output,
                password: "secret123"
            )
            try expect(PDFInspector().open(url: result.outputURL, password: nil) != nil, "output opens without password")
            let postInspection = PDFInspector().inspect(result.outputURL)
            try expect(postInspection.encryption == .none, "expected .none after qpdf, got \(postInspection.encryption)")
        } passed: { passed += 1 } failed: { failed += 1 }

        print("\n— Summary —")
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
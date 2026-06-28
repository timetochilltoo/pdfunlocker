import Foundation
import PDFKit

@main
struct VerboseUnlock {
    static func main() async {
        let input = URL(fileURLWithPath: "/Users/patrickshi/Downloads/Test PDF.pdf")
        let outputDir = URL(fileURLWithPath: "/Users/patrickshi/Minimax Coding/PDF Unlocker/test-fixtures")

        print("Input: \(input.path)")
        print("Output dir: \(outputDir.path)")
        print("Input exists: \(FileManager.default.fileExists(atPath: input.path))")
        print("Input size: \((try? FileManager.default.attributesOfItem(atPath: input.path))?[.size] ?? 0)")
        print("")

        // Inspect input
        let inspector = PDFInspector()
        let inspection = inspector.inspect(input)
        print("=== INPUT INSPECTION ===")
        print("  encryption: \(inspection.encryption)")
        print("  pageCount: \(inspection.pageCount)")
        print("  hasTextLayer: \(inspection.hasTextLayer)")
        print("  isCorrupt: \(inspection.isCorrupt)")
        print("")

        // Output with timestamp
        let ts = Int(Date().timeIntervalSince1970)
        let output = outputDir.appendingPathComponent("TestPDF-unlocked-\(ts).pdf")
        print("Output: \(output.path)")
        print("")

        // Try unlock
        print("=== UNLOCK ===")
        do {
            let unlocker = PDFUnlocker()
            let result = try await unlocker.unlock(
                input: input,
                output: output,
                password: nil
            )
            print("✓ Unlock succeeded")
            print("  outputURL: \(result.outputURL.path)")
            print("  pageCount: \(result.pageCount)")
            print("  verifiedAt: \(result.verifiedAt)")
            print("")

            // Verify the output
            print("=== OUTPUT VERIFICATION ===")
            print("  Output exists: \(FileManager.default.fileExists(atPath: result.outputURL.path))")
            print("  Output size: \((try? FileManager.default.attributesOfItem(atPath: result.outputURL.path))?[.size] ?? 0)")

            // Re-inspect the output
            let postInspection = inspector.inspect(result.outputURL)
            print("  Output inspection:")
            print("    encryption: \(postInspection.encryption)")
            print("    pageCount: \(postInspection.pageCount)")
            print("    hasTextLayer: \(postInspection.hasTextLayer)")
            print("    isCorrupt: \(postInspection.isCorrupt)")
            print("")

            // Open without password
            let canOpen = inspector.open(url: result.outputURL, password: nil) != nil
            print("  Opens without password: \(canOpen)")
            print("")

            // Use qpdf to verify too
            print("=== QPDF VERIFICATION ===")
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/qpdf")
            task.arguments = ["--show-encryption", result.outputURL.path]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            try task.run()
            task.waitUntilExit()
            let qpdfOut = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            print(qpdfOut)

            // Also show original for comparison
            print("=== QPDF ON ORIGINAL (for comparison) ===")
            let task2 = Process()
            task2.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/qpdf")
            task2.arguments = ["--show-encryption", input.path]
            let pipe2 = Pipe()
            task2.standardOutput = pipe2
            task2.standardError = pipe2
            try task2.run()
            task2.waitUntilExit()
            let qpdfOut2 = String(data: pipe2.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            print(qpdfOut2)

        } catch let e as UnlockError {
            print("✗ Unlock failed: \(e)")
            print("  description: \(e.errorDescription ?? "nil")")
        } catch {
            print("✗ Unexpected error: \(error)")
        }
    }
}
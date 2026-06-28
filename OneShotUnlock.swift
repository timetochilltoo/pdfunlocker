import Foundation
import PDFKit

@main
struct OneShotUnlock {
    static func main() async {
        let input = URL(fileURLWithPath: "/Users/patrickshi/Downloads/Test PDF.pdf")
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdfu-oneshot-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let output = outputDir.appendingPathComponent("Test PDF-unlocked.pdf")

        print("Input: \(input.path)")
        print("Output: \(output.path)")

        // Inspect first
        let inspection = PDFInspector().inspect(input)
        print("Inspection: encryption=\(inspection.encryption), pages=\(inspection.pageCount), textLayer=\(inspection.hasTextLayer)")

        // Try unlock
        do {
            let result = try await PDFUnlocker().unlock(input: input, output: output, password: nil)
            print("✓ Unlocked: \(result.outputURL.path)")
            print("  Page count: \(result.pageCount)")

            // Verify the output has no print restriction
            let postInspection = PDFInspector().inspect(result.outputURL)
            print("  Post-unlock encryption: \(postInspection.encryption)")

            // Show output file size and PDFKit can open it
            let attrs = try? FileManager.default.attributesOfItem(atPath: result.outputURL.path)
            let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
            print("  Output size: \(size) bytes")
            print("  Opens without password: \(PDFInspector().open(url: result.outputURL, password: nil) != nil)")

            // Move to Downloads so user can find it (with timestamp to
            // avoid colliding with any existing file).
            let ts = Int(Date().timeIntervalSince1970)
            let userOutput = input.deletingLastPathComponent()
                .appendingPathComponent("Test PDF-unlocked-\(ts).pdf")
            try? FileManager.default.removeItem(at: userOutput)
            try FileManager.default.copyItem(at: result.outputURL, to: userOutput)
            print("  Saved to: \(userOutput.path)")
        } catch let e as UnlockError {
            print("✗ Unlock failed: \(e)")
            print("  description: \(e.errorDescription ?? "nil")")
            exit(1)
        } catch {
            print("✗ Unexpected error: \(error)")
            exit(1)
        }
    }
}
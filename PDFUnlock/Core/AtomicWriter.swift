import Foundation

/// Atomic write pattern: temp file → caller validates → atomic move into
/// place. The temp file is removed on any failure.
public struct AtomicWriter: Sendable {

    public enum Failure: LocalizedError {
        case tempWriteFailed(underlying: Error)
        case moveFailed(underlying: Error)
        case sourceMissing

        public var errorDescription: String? {
            switch self {
            case .tempWriteFailed:  return "Could not write temporary file."
            case .moveFailed:       return "Could not replace the target file."
            case .sourceMissing:    return "Temporary file was missing before move."
            }
        }
    }

    public let outputURL: URL

    public init(outputURL: URL) {
        self.outputURL = outputURL
    }

    /// Writes `data` to a temp file in the destination directory,
    /// calls `validate` on it, then atomically renames into place.
    /// Throws on any failure (temp file is cleaned up first).
    public func write(
        _ data: Data,
        validate: (URL) throws -> Void
    ) throws {
        let dir = outputURL.deletingLastPathComponent()
        let tempURL = dir.appendingPathComponent(".tmp-\(UUID().uuidString)")
        do {
            try data.write(to: tempURL, options: .atomic)
            try validate(tempURL)
            // Replace if exists; create otherwise.
            if FileManager.default.fileExists(atPath: outputURL.path) {
                _ = try FileManager.default.replaceItemAt(outputURL, withItemAt: tempURL)
            } else {
                try FileManager.default.moveItem(at: tempURL, to: outputURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }

    /// Writes by copying an existing source file (e.g. PDFKit output),
    /// then validating and moving into place.
    public func writeByCopying(
        from sourceURL: URL,
        validate: (URL) throws -> Void
    ) throws {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw Failure.sourceMissing
        }
        let dir = outputURL.deletingLastPathComponent()
        let tempURL = dir.appendingPathComponent(".tmp-\(UUID().uuidString)")
        do {
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try FileManager.default.removeItem(at: tempURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: tempURL)
            try validate(tempURL)
            if FileManager.default.fileExists(atPath: outputURL.path) {
                _ = try FileManager.default.replaceItemAt(outputURL, withItemAt: tempURL)
            } else {
                try FileManager.default.moveItem(at: tempURL, to: outputURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }
}
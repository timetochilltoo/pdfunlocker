import Foundation

/// Output filename + collision policy. Pure logic, easy to unit-test.
public struct FileNaming: Sendable {

    public enum SuffixTarget: Sendable { case unlock, convert }

    public let suffix: String

    public init(suffix: String) {
        self.suffix = suffix
    }

    /// Build the default output URL for an input PDF and target mode.
    public func defaultOutput(for input: URL, target: SuffixTarget) -> URL {
        let dir = input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent
        let ext = target == .unlock ? "pdf" : input.pathExtension
        let candidate = dir.appendingPathComponent("\(base)\(suffix).\(ext)")
        return candidate
    }

    /// Resolve a candidate output URL according to the user's collision
    /// preference. For `.keepBoth` (default), appends `-2`, `-3`, etc.
    /// until a free slot is found. For `.overwrite`, returns the
    /// candidate unchanged. `.ask` is reserved for future use; treated
    /// as `.keepBoth` for now.
    public func resolveCollision(
        candidate: URL,
        behavior: AppSettings.CollisionBehavior
    ) throws -> URL {
        switch behavior {
        case .overwrite:
            return candidate
        case .ask, .keepBoth:
            return nextAvailable(candidate)
        }
    }

    /// Walk `-2`, `-3`, ... until we find a URL that does not exist.
    private func nextAvailable(_ candidate: URL) -> URL {
        let fm = FileManager.default
        if !fm.fileExists(atPath: candidate.path) { return candidate }

        let dir = candidate.deletingLastPathComponent()
        let baseNoExt = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        let hasExt = !ext.isEmpty

        for n in 2...9_999 {
            let name = hasExt
                ? "\(baseNoExt)-\(n).\(ext)"
                : "\(baseNoExt)-\(n)"
            let next = dir.appendingPathComponent(name)
            if !fm.fileExists(atPath: next.path) { return next }
        }
        // Extremely unlikely fallback: return candidate (will overwrite)
        return candidate
    }

    /// Output filename(s) for a convert job. Returns a map from format
    /// to its final URL(s).
    public func convertOutputs(
        for input: URL,
        formats: Set<ConvertFormat>,
        pageRange: PageRange?
    ) -> [ConvertFormat: [URL]] {
        var result: [ConvertFormat: [URL]] = [:]
        let dir = input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent

        for format in formats {
            switch format {
            case .txt:
                let url = dir.appendingPathComponent("\(base)\(suffix).txt")
                result[.txt] = [url]
            case .md:
                let url = dir.appendingPathComponent("\(base)\(suffix).md")
                result[.md] = [url]
            case .png:
                let folder = dir.appendingPathComponent("\(base)\(suffix)-images", isDirectory: true)
                // Page names are determined at run time once page count is known.
                // Return a single placeholder; the converter fills in real names.
                let placeholder = folder.appendingPathComponent("page-001.png")
                result[.png] = [folder, placeholder]
            }
        }
        return result
    }
}
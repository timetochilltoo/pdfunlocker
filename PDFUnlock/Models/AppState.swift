import Foundation
import Observation

/// Shared state across the SwiftUI tree. Owns the active mode, the
/// unlock/convert queues, the view models, and the file-picker request
/// flag used by `AppCommands` to trigger the system NSOpenPanel.
@Observable
@MainActor
public final class AppState {
    public var mode: AppMode
    public var settings: AppSettings

    public var unlockJobs: [UnlockJob]
    public var convertJobs: [ConvertJob]

    public var unlockVM: UnlockViewModel
    public var convertVM: ConvertViewModel

    /// Toggled by `AppCommands`; views observe and trigger `NSOpenPanel`.
    public var addFilesRequestToken: Int

    public init(
        mode: AppMode = .unlock,
        settings: AppSettings = AppSettings(),
        unlockJobs: [UnlockJob] = [],
        convertJobs: [ConvertJob] = [],
        unlockVM: UnlockViewModel = UnlockViewModel(),
        convertVM: ConvertViewModel = ConvertViewModel(),
        addFilesRequestToken: Int = 0
    ) {
        self.mode = mode
        self.settings = settings
        self.unlockJobs = unlockJobs
        self.convertJobs = convertJobs
        self.unlockVM = unlockVM
        self.convertVM = convertVM
        self.addFilesRequestToken = addFilesRequestToken
    }

    public func requestAddFiles() {
        addFilesRequestToken &+= 1
    }

    public func addUnlockJobs(from urls: [URL]) {
        let existing = Set(unlockJobs.map(\.inputURL))
        let fresh = urls.filter { !existing.contains($0) }
        let new = fresh.map { UnlockJob(inputURL: $0) }
        guard !new.isEmpty else { return }
        unlockJobs.append(contentsOf: new)
    }

    public func addConvertJobs(from urls: [URL]) {
        let existing = Set(convertJobs.map(\.inputURL))
        let fresh = urls.filter { !existing.contains($0) }
        let new = fresh.map { url -> ConvertJob in
            ConvertJob(
                inputURL: url,
                outputDirectory: Self.outputDirectory(for: url, settings: settings)
            )
        }
        guard !new.isEmpty else { return }
        convertJobs.append(contentsOf: new)
    }

    /// Resolve the output directory for a convert job based on user
    /// settings. `sameFolder` (default) puts outputs next to the source.
    /// `customFolder` uses the configured custom folder, falling back to
    /// Downloads if none is set.
    private static func outputDirectory(for inputURL: URL, settings: AppSettings) -> URL {
        switch settings.outputLocation {
        case .sameFolder:
            return inputURL.deletingLastPathComponent()
        case .customFolder:
            return settings.customOutputFolder
                ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
        }
    }

    public func runAllUnlock() {
        unlockVM.runAll(unlockJobs, settings: settings)
    }

    public func cancelUnlock() {
        unlockVM.cancelAll()
    }

    public var isUnlockRunning: Bool {
        unlockJobs.contains { $0.status == .running || $0.status == .inspecting }
    }

    public var hasUnlockWork: Bool {
        unlockJobs.contains {
            switch $0.status {
            case .ready, .needsPassword, .failed: return true
            default: return false
            }
        }
    }

    public func runAllConvert() {
        convertVM.runAll(convertJobs, settings: settings)
    }

    public func cancelConvert() {
        convertVM.cancelAll()
    }

    public var isConvertRunning: Bool {
        convertJobs.contains { $0.status == .running || $0.status == .inspecting }
    }

    public var hasConvertWork: Bool {
        convertJobs.contains {
            switch $0.status {
            case .ready, .failed: return true
            default: return false
            }
        }
    }
}
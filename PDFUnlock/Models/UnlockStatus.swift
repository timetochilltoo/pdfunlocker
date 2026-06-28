import Foundation

public enum UnlockStatus: Equatable, Sendable {
    case queued
    case inspecting
    case needsPassword
    case ready
    case running
    case succeeded
    case skipped
    case failed
    case cancelled

    public var displayLabel: String {
        switch self {
        case .queued: return "Queued"
        case .inspecting: return "Inspecting…"
        case .needsPassword: return "Needs password"
        case .ready: return "Ready"
        case .running: return "Running…"
        case .succeeded: return "Unlocked"
        case .skipped: return "Skipped"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}
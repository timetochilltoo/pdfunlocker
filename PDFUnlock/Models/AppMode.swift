import Foundation

/// Top-level mode selector for the app. The toolbar segmented control
/// drives this enum; views read it to render Unlock or Convert UI.
public enum AppMode: String, CaseIterable, Identifiable, Sendable {
    case unlock
    case convert

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .unlock: return "Unlock"
        case .convert: return "Convert"
        }
    }

    public var systemImage: String {
        switch self {
        case .unlock: return "lock.open"
        case .convert: return "doc.text"
        }
    }
}
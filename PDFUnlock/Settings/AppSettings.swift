import Foundation
import Observation

/// User-tunable settings backed by `UserDefaults`. Observable so SwiftUI
/// can react to changes (e.g. default DPI toggle, suffix change).
@Observable
public final class AppSettings: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Output

    public enum OutputLocation: String, CaseIterable, Identifiable, Sendable {
        case sameFolder
        case customFolder
        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .sameFolder: return "Same folder as input"
            case .customFolder: return "Custom folder"
            }
        }
    }

    public enum CollisionBehavior: String, CaseIterable, Identifiable, Sendable {
        case keepBoth
        case ask
        case overwrite
        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .keepBoth: return "Keep both"
            case .ask: return "Ask each time"
            case .overwrite: return "Overwrite"
            }
        }
    }

    // MARK: - Storage keys

    private enum Key {
        static let outputLocation = "outputLocation"
        static let customOutputFolder = "customOutputFolder"
        static let unlockSuffix = "unlockSuffix"
        static let convertSuffix = "convertSuffix"
        static let collisionBehavior = "collisionBehavior"
        static let includeSubfolders = "includeSubfolders"

        static let defaultPNGDPI = "defaultPNGDPI"
        static let defaultMarkdown = "defaultMarkdown"

        static let recoveryMaxAttempts = "recoveryMaxAttempts"
        static let recoveryMaxSeconds = "recoveryMaxSeconds"
        static let recoveryMutations = "recoveryMutations"

        static let concurrency = "concurrency"
    }

    // MARK: - Output

    public var outputLocation: OutputLocation {
        get { OutputLocation(rawValue: defaults.string(forKey: Key.outputLocation) ?? "") ?? .sameFolder }
        set { defaults.set(newValue.rawValue, forKey: Key.outputLocation) }
    }

    public var customOutputFolder: URL? {
        get {
            guard let path = defaults.string(forKey: Key.customOutputFolder) else { return nil }
            return URL(fileURLWithPath: path)
        }
        set { defaults.set(newValue?.path, forKey: Key.customOutputFolder) }
    }

    public var unlockSuffix: String {
        get { defaults.string(forKey: Key.unlockSuffix) ?? "-unlocked" }
        set { defaults.set(newValue, forKey: Key.unlockSuffix) }
    }

    public var convertSuffix: String {
        get { defaults.string(forKey: Key.convertSuffix) ?? "-converted" }
        set { defaults.set(newValue, forKey: Key.convertSuffix) }
    }

    public var collisionBehavior: CollisionBehavior {
        get { CollisionBehavior(rawValue: defaults.string(forKey: Key.collisionBehavior) ?? "") ?? .keepBoth }
        set { defaults.set(newValue.rawValue, forKey: Key.collisionBehavior) }
    }

    public var includeSubfolders: Bool {
        get { defaults.bool(forKey: Key.includeSubfolders) }
        set { defaults.set(newValue, forKey: Key.includeSubfolders) }
    }

    // MARK: - Convert defaults

    public var defaultPNGDPI: Int {
        get {
            let v = defaults.integer(forKey: Key.defaultPNGDPI)
            return v == 0 ? 150 : v
        }
        set { defaults.set(newValue, forKey: Key.defaultPNGDPI) }
    }

    public var defaultMarkdown: Bool {
        get {
            defaults.object(forKey: Key.defaultMarkdown) as? Bool ?? true
        }
        set { defaults.set(newValue, forKey: Key.defaultMarkdown) }
    }

    // MARK: - Recovery defaults

    public var recoveryMaxAttempts: Int {
        get {
            let v = defaults.integer(forKey: Key.recoveryMaxAttempts)
            return v == 0 ? 10_000 : v
        }
        set { defaults.set(min(max(newValue, 1), 1_000_000), forKey: Key.recoveryMaxAttempts) }
    }

    public var recoveryMaxSeconds: Int {
        get {
            let v = defaults.integer(forKey: Key.recoveryMaxSeconds)
            return v == 0 ? 60 : v
        }
        set { defaults.set(min(max(newValue, 1), 600), forKey: Key.recoveryMaxSeconds) }
    }

    public var recoveryMutations: Bool {
        get {
            defaults.object(forKey: Key.recoveryMutations) as? Bool ?? true
        }
        set { defaults.set(newValue, forKey: Key.recoveryMutations) }
    }

    // MARK: - Concurrency

    public var concurrency: Int {
        get {
            let v = defaults.integer(forKey: Key.concurrency)
            return v == 0 ? 2 : v
        }
        set { defaults.set(min(max(newValue, 1), 4), forKey: Key.concurrency) }
    }
}
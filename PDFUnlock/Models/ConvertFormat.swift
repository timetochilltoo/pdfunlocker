import Foundation

public enum ConvertFormat: String, CaseIterable, Identifiable, Sendable {
    case txt
    case png
    case md

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .txt: return "TXT"
        case .png: return "PNG"
        case .md: return "Markdown"
        }
    }

    public var fileExtension: String {
        switch self {
        case .txt: return "txt"
        case .png: return "png"
        case .md: return "md"
        }
    }

    public var isExperimental: Bool {
        self == .md
    }

    public var defaultDPI: Int { 150 }
}

/// 1-based page range. Stored as a sorted, de-duplicated set.
public struct PageRange: Equatable, Hashable, Sendable {
    public let pages: [Int]

    public init(pages: [Int]) {
        let sorted = Array(Set(pages.filter { $0 > 0 })).sorted()
        self.pages = sorted
    }

    public static let all = PageRange(pages: [])

    public var isAll: Bool { pages.isEmpty }

    public func contains(_ page: Int) -> Bool {
        isAll || pages.contains(page)
    }
}
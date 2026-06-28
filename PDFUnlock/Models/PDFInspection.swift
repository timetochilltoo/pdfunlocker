import Foundation

/// Lightweight inspection of a PDF. Real detection logic is added in M1.
public struct PDFInspection: Equatable, Sendable {
    public enum EncryptionKind: Equatable, Sendable {
        case none
        case ownerOnly
        case userPassword
        case certificate
        case unsupported
    }

    public let pageCount: Int
    public let encryption: EncryptionKind
    public let hasTextLayer: Bool
    public let isCorrupt: Bool

    public init(
        pageCount: Int,
        encryption: EncryptionKind,
        hasTextLayer: Bool,
        isCorrupt: Bool
    ) {
        self.pageCount = pageCount
        self.encryption = encryption
        self.hasTextLayer = hasTextLayer
        self.isCorrupt = isCorrupt
    }

    public static let unknown = PDFInspection(
        pageCount: 0,
        encryption: .none,
        hasTextLayer: false,
        isCorrupt: true
    )
}
import Foundation

/// Typed errors for the unlock pipeline. User-facing messages live in
/// `errorDescription` and are surfaced directly in the UI.
public enum UnlockError: LocalizedError, Sendable, Equatable {
    case fileNotFound(path: String)
    case notReadable(path: String)
    case corruptPDF
    case unsupportedEncryption(detail: String)
    case drmProtected
    case certificateEncrypted
    case wrongPassword
    case missingPassword
    case outputExistsNotOverwriting(url: URL)
    case writeFailed(underlying: String)
    case diskFull
    case permissionDenied(path: String)
    case verificationFailed(reason: String)
    case qpdfUnavailable
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .fileNotFound:           return "The PDF could not be found."
        case .notReadable:            return "PDF Unlock does not have permission to read this PDF."
        case .corruptPDF:             return "This file could not be opened as a valid PDF."
        case .unsupportedEncryption:  return "This PDF uses encryption this app cannot unlock."
        case .drmProtected:           return "This file appears to use DRM, which PDF Unlock does not remove."
        case .certificateEncrypted:   return "This PDF uses certificate encryption, which PDF Unlock does not handle."
        case .wrongPassword:          return "That password did not unlock this PDF."
        case .missingPassword:        return "This PDF needs a password before it can be unlocked."
        case .outputExistsNotOverwriting: return "A file with this name already exists."
        case .writeFailed:            return "The unlocked PDF could not be saved."
        case .diskFull:               return "There is not enough disk space to save the unlocked PDF."
        case .permissionDenied:       return "PDF Unlock does not have permission to write to this location."
        case .verificationFailed:     return "The unlocked file could not be verified, so it was not saved as complete."
        case .qpdfUnavailable:        return "The fallback unlock engine is unavailable. Reinstall the app."
        case .cancelled:              return "The unlock was cancelled."
        }
    }
}

/// Result of a successful unlock.
public struct UnlockResult: Sendable, Equatable {
    public let outputURL: URL
    public let pageCount: Int
    public let verifiedAt: Date

    public init(outputURL: URL, pageCount: Int, verifiedAt: Date) {
        self.outputURL = outputURL
        self.pageCount = pageCount
        self.verifiedAt = verifiedAt
    }
}
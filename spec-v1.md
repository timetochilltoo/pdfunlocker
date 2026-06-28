# PDF Unlock — Practical v1 Specification

**Status:** Draft v1.0  
**Platform:** macOS 26 Tahoe 26.5.1+  
**Language:** Swift 6  
**UI Framework:** SwiftUI  
**Distribution:** Direct download, Developer ID signed and notarized  
**Privacy Model:** Local-only, no network, no analytics

---

## 1. Overview

### 1.1 Purpose

PDF Unlock is a native macOS utility for creating unlocked copies of PDF files that the user owns or has the right to modify.

The app supports:

- Unlocking PDFs that require a known open password.
- Removing owner/permissions restrictions where technically possible.
- Batch processing multiple PDFs.
- Saving clean output files without modifying originals by default.

The app does not upload files, contact a server, collect analytics, or attempt to crack unknown passwords.

### 1.2 Core Value Proposition

Drop locked PDFs, enter the password if needed, and get unlocked copies that stay entirely on this Mac.

### 1.3 Design Principles

1. **Local-only:** no network calls, no telemetry, no cloud processing.
2. **Honest limits:** if a password is unknown or encryption is unsupported, the app says so clearly.
3. **Batch-friendly:** users can process many PDFs without babysitting each file.
4. **Safe by default:** originals are preserved unless overwrite is explicitly enabled.
5. **Native macOS feel:** SwiftUI, toolbar, drag and drop, Finder reveal, Quick Look preview if simple.
6. **Small v1:** ship the reliable core first; keep extensions and power-user tools for later.

### 1.4 Target Users

- Office workers handling client PDFs.
- Researchers with legitimately accessible but restricted papers.
- Admins cleaning up batches of generated documents.
- Mac users who want a private, no-upload PDF workflow.

### 1.5 Non-Goals for v1

- Password cracking, brute force, dictionary attacks, or DRM removal.
- PDF editing, annotation, page management, OCR, or conversion.
- iOS, iPadOS, visionOS, or web versions.
- Finder extension, Quick Action, menu bar utility, or CLI helper.
- Persistent job history.
- Cloud sync or account system.
- Mac App Store release.

---

## 2. Functional Scope

### 2.1 v1 Must-Have Features

| ID | Feature | Priority |
|---|---|---|
| F1 | Drag and drop PDF files onto the app window | P0 |
| F2 | Choose PDFs using a native file picker | P0 |
| F3 | Add multiple PDFs to a batch queue | P0 |
| F4 | Detect whether each PDF is unlocked, open-password protected, owner-restricted, or unsupported | P0 |
| F5 | Prompt for known open passwords using secure input | P0 |
| F6 | Remove open password protection when the correct password is supplied | P0 |
| F7 | Remove owner/permissions restrictions where PDFKit or qpdf can do so | P0 |
| F8 | Write unlocked output files atomically | P0 |
| F9 | Preserve original files by default | P0 |
| F10 | Show per-file status, progress, and errors | P0 |
| F11 | Provide clear retry behavior for wrong passwords | P0 |
| F12 | Reveal successful output in Finder | P1 |
| F13 | Let user select output folder and filename suffix | P1 |
| F14 | Code sign, harden, and notarize for direct distribution | P0 |
| F15 | Preflight summary before unlocking large batches | P1 |
| F16 | Session-only shared password helper | P1 |
| F17 | Verify unlocked output before marking success | P0 |
| F18 | Export a redacted failure report for support/debugging | P2 |

### 2.2 Deferred Features

These should not block v1:

- Finder context menu / Quick Action.
- CLI companion.
- Menu bar drop utility.
- Persistent history database.
- SwiftData-backed job archive.
- Mac App Store variant.
- Automatic updater.
- Localization beyond English.
- Advanced preview/editor UI.
- Password memory or Keychain integration.

### 2.3 Recommended Additions

These additions are worth including because they improve trust, reduce user mistakes, or make batch work smoother without changing the core product.

#### A. Preflight Summary

Before unlocking a batch, the app should show a compact summary:

- Number of PDFs added.
- Number already unlocked.
- Number requiring a password.
- Number with owner restrictions only.
- Number likely unsupported.
- Estimated output location.

This helps users catch mistakes before processing a large folder of files.

#### B. Session-Only Shared Password

Many batch PDFs use the same open password. The app should allow:

- Enter password once.
- Apply it to all files that need a password.
- Keep it in memory only for the current session.
- Clear it automatically after the batch finishes or the app quits.

This is not persistent password saving and does not use Keychain in v1.

#### C. Output Verification

After writing an unlocked file, the app should reopen the output and verify:

- It is a valid PDF.
- It can be opened without an open password.
- It has the expected page count.
- It is not zero bytes or obviously truncated.

Only verified files should be marked as successful.

#### D. Redacted Failure Report

For failed files, users should be able to copy or export a redacted diagnostic report containing:

- App version.
- macOS version.
- PDF size and page count if readable.
- Detected encryption type if available.
- Unlock path used: PDFKit or qpdf.
- Error category and sanitized error message.

The report must not include passwords, full file contents, or PDF text.

#### E. Drag Folder as Convenience Input

Folder processing can be useful, but should stay conservative in v1:

- Accept a dropped folder.
- Scan only the top level by default.
- Offer an optional "Include subfolders" checkbox.
- Skip hidden files.
- Do not follow symlinks.

This is simpler than a full folder-processing system but very helpful for real users.

---

## 3. User Workflow

### 3.1 Basic Flow

1. User opens PDF Unlock.
2. User drops one or more PDFs into the window, or chooses files with the file picker.
3. App analyzes each file.
4. App shows a preflight summary for the queue.
5. Files that need an open password show an inline password field.
6. User may enter one session-only shared password and apply it to all password-required files.
7. User chooses output behavior:
   - Same folder with suffix, default: `-unlocked`.
   - Custom output folder.
8. User clicks **Unlock All**.
9. App processes the queue locally.
10. App verifies each output before marking it successful.
11. Each row shows success, failure, or skipped state.
12. User can reveal successful outputs in Finder.

### 3.2 Output Rules

Default output:

```text
Original: report.pdf
Output:   report-unlocked.pdf
```

If the output filename already exists:

1. Keep both using `-2`, `-3`, etc.
2. Allow overwrite only if the user explicitly changes the setting.

Original files are never modified in the default mode.

### 3.3 Batch Behavior

- The app processes multiple files without blocking the UI.
- Default concurrency should be conservative: 2 files at a time.
- Users can cancel the remaining queue.
- Completed files remain completed when later files fail.
- A failed file can be retried after entering a new password.
- A shared session password can be applied to all files that need a password.
- Shared session passwords are cleared after completion, cancellation, or app quit.

### 3.4 Folder Input

v1 may support dropped folders as a convenience, but folder behavior should be deliberately limited:

- Top-level scan by default.
- Optional "Include subfolders" checkbox.
- Hidden files skipped.
- Symlinks ignored.
- Non-PDF files skipped silently.
- The preflight summary should show how many PDFs were found.

---

## 4. Unlocking Behavior

### 4.1 Supported Cases

| PDF Case | Expected Behavior |
|---|---|
| Not encrypted | Mark as "No password needed"; do not write output by default |
| Open-password protected | Require user password; write unlocked copy on success |
| Owner/permissions restricted only | Attempt to write unrestricted copy |
| Both open password and owner restrictions | Require open password; write unrestricted copy if possible |
| Wrong password | Show inline error and allow retry |
| Certificate-based encryption | Show unsupported error |
| Adobe DRM or non-standard DRM | Show unsupported error |
| Corrupt PDF | Show invalid/corrupt PDF error |
| Digitally signed PDF | Warn that unlocking may invalidate signatures |

### 4.2 Technical Strategy

The app uses a two-layer unlock strategy:

1. **Primary path: PDFKit**
   - Use `PDFDocument` for inspection, opening, and simple re-saving.
   - Use `unlock(withPassword:)` when an open password is required.
   - Attempt to write a new unencrypted copy.

2. **Fallback path: bundled qpdf**
   - If PDFKit cannot handle a valid PDF, use a bundled universal `qpdf` binary.
   - Run `qpdf --decrypt` through `Process`.
   - Pass passwords carefully and never log them.
   - Surface qpdf errors as user-readable app errors.

This combination keeps the app native for common cases while making it more robust for real-world PDFs.

### 4.3 Important Caveat

PDFKit does not expose every detail of PDF encryption and permissions. The app should not promise universal unlocking. It should promise best-effort unlocking for standard password-based PDF protection, with clear failure messages for unsupported files.

---

## 5. User Interface

### 5.1 Main Window

Single-window SwiftUI app:

```text
┌──────────────────────────────────────────────────────────┐
│ Toolbar:  Add Files   Unlock All   Cancel   Settings     │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  Empty state: Drop PDFs here                             │
│                                                          │
│  Or queue table once files are added:                    │
│                                                          │
│  File name        Protection       Status        Action   │
│  report.pdf       Open password    Needs pass    [____]   │
│  invoice.pdf      Owner locked     Ready         Unlock   │
│  notes.pdf        None             Skipped       -        │
│                                                          │
├──────────────────────────────────────────────────────────┤
│ Output: Same folder   Suffix: -unlocked                  │
└──────────────────────────────────────────────────────────┘
```

### 5.2 Required UI States

Each file row should show:

- File name.
- File size.
- Protection type.
- Status.
- Password field when needed.
- Progress while running.
- Error text when failed.
- Reveal output action when successful.

### 5.3 Preflight Panel

When the queue contains more than one file, the app should show a compact preflight panel before unlocking:

- Total PDFs.
- Ready to unlock.
- Needs password.
- Already unlocked.
- Unsupported or unreadable.
- Output destination.

The panel should not block quick single-file workflows.

### 5.4 Empty State

The empty state should be simple:

- Large PDF/drop icon.
- Text: "Drop PDFs to unlock"
- Secondary text: "Files stay on this Mac."
- Buttons: **Choose Files...**

### 5.5 Settings for v1

Keep settings small:

- Output location:
  - Same folder.
  - Custom folder.
- Filename suffix, default `-unlocked`.
- Existing file behavior:
  - Keep both, default.
  - Ask.
  - Overwrite.
- Concurrency:
  - 1 to 4 files at a time.
- Folder input:
  - Include subfolders, default off.

No password saving in v1.

---

## 6. Architecture

### 6.1 Stack

| Layer | Technology |
|---|---|
| UI | SwiftUI |
| State | Observation / `@Observable` |
| PDF primary engine | PDFKit |
| PDF fallback engine | Bundled `qpdf` |
| File access | Security-scoped URLs where needed |
| Concurrency | Swift Concurrency |
| Logging | `os.Logger` |
| Persistence | `UserDefaults` only for settings |
| Distribution | Developer ID, Hardened Runtime, notarization |

### 6.2 Project Layout

```text
PDFUnlock/
├── App/
│   ├── PDFUnlockApp.swift
│   └── Commands.swift
├── Features/
│   ├── Queue/
│   ├── DropZone/
│   └── Settings/
├── Core/
│   ├── PDFUnlocker.swift
│   ├── PDFInspector.swift
│   ├── QPDFRunner.swift
│   ├── FileNaming.swift
│   ├── AtomicWriter.swift
│   └── UnlockError.swift
├── Models/
│   ├── UnlockJob.swift
│   ├── UnlockStatus.swift
│   └── PDFInspection.swift
├── Resources/
│   ├── qpdf
│   └── Assets.xcassets
└── PDFUnlock.entitlements
```

### 6.3 Core API

```swift
public struct PDFUnlocker: Sendable {
    public struct Options: Sendable {
        public var overwriteExisting: Bool
        public var preserveMetadata: Bool
        public var useQPDFFallback: Bool
    }

    public func inspect(_ input: URL) async throws -> PDFInspection

    public func unlock(
        input: URL,
        output: URL,
        password: String?,
        options: Options
    ) async throws -> UnlockResult
}
```

### 6.4 Job Model

```swift
@Observable
final class UnlockJob: Identifiable {
    let id: UUID
    let inputURL: URL
    var outputURL: URL?
    var inspection: PDFInspection?
    var password: String
    var status: UnlockStatus
    var progress: Double
    var errorMessage: String?
}
```

### 6.5 Status Model

```swift
enum UnlockStatus: Equatable {
    case queued
    case inspecting
    case needsPassword
    case ready
    case running
    case succeeded
    case skipped
    case failed
    case cancelled
}
```

---

## 7. Security and Privacy

### 7.1 Privacy Requirements

- No network entitlement.
- No analytics.
- No crash reporting uploads.
- No password persistence.
- No passwords in logs.
- No indexing of PDF contents.
- All processing happens locally.

### 7.2 Password Handling

- Passwords are entered through `SecureField`.
- Passwords are held in memory only as long as the job requires them.
- Password strings should be cleared from job state after completion or cancellation.
- Logs must never include password values or command strings containing passwords.

### 7.3 qpdf Handling

Because qpdf is bundled:

- Ship a universal binary for Apple Silicon and Intel if Intel support remains required.
- Include qpdf license notices.
- Code sign the qpdf binary.
- Ensure Hardened Runtime allows the bundled executable to run.
- Do not require Homebrew or external installation.

---

## 8. File Safety

### 8.1 Atomic Writes

All output writes must use this pattern:

1. Create a temporary file in the destination folder.
2. Write unlocked output to the temporary file.
3. Validate that the output can be opened as a PDF.
4. Rename or replace atomically.
5. Remove temporary file on failure.

### 8.2 Output Verification

Before a job is marked successful, the app must verify the finished file:

1. Reopen the output file.
2. Confirm it is a valid PDF.
3. Confirm it does not require an open password.
4. Confirm the page count matches the source when the source page count is known.
5. Confirm file size is greater than zero.

### 8.3 Original File Protection

- Default behavior never modifies the original.
- Overwrite behavior, if enabled, must first write a valid temporary output.
- If replacement fails, preserve the original and show an error.

---

## 9. Error Handling

### 9.1 Error Categories

| Error | User Message |
|---|---|
| Wrong password | "That password did not unlock this PDF." |
| Missing password | "This PDF needs a password before it can be unlocked." |
| Unsupported encryption | "This PDF uses encryption this app cannot unlock." |
| DRM protected | "This file appears to use DRM, which PDF Unlock does not remove." |
| Corrupt PDF | "This file could not be opened as a valid PDF." |
| Output exists | "A file with this name already exists." |
| Write failed | "The unlocked PDF could not be saved." |
| Disk full | "There is not enough disk space to save the unlocked PDF." |
| Permission denied | "PDF Unlock does not have permission to read or write this location." |
| qpdf missing/damaged | "The fallback unlock engine is unavailable. Reinstall the app." |
| Verification failed | "The unlocked file could not be verified, so it was not saved as complete." |

### 9.2 UI Rules

- Prefer inline row errors over modal alerts.
- Use modals only for destructive choices or digital-signature warnings.
- Failed files should not stop the entire batch unless the error affects the output folder globally.
- Users should be able to retry failed files.
- Failed files should offer "Copy Report" with a redacted diagnostic summary.

---

## 10. Testing Strategy

### 10.1 Required Test Fixtures

The test corpus should include:

- Unencrypted PDF.
- Open-password PDF.
- Owner-restricted PDF.
- PDF with both open password and restrictions.
- Wrong-password scenario.
- RC4 40-bit legacy PDF.
- AES-128 PDF.
- AES-256 PDF.
- Corrupt PDF.
- Truncated PDF.
- PDF with annotations.
- PDF with forms.
- PDF with bookmarks.
- PDF with digital signature.
- Large scanned PDF.
- Folder containing mixed PDFs and non-PDF files.
- Folder containing hidden files and symlinks.

### 10.2 Unit Tests

Cover:

- File inspection.
- Output filename generation.
- Existing-file collision handling.
- Atomic write success and failure.
- PDFKit unlock path.
- qpdf fallback path.
- Error mapping.
- Output verification.
- Redacted failure report generation.
- Shared session password clearing.

### 10.3 UI Tests

Cover:

- Drop/add file.
- Enter password.
- Unlock one file.
- Unlock batch.
- Wrong password retry.
- Output conflict behavior.
- Cancel batch.
- Preflight summary before batch unlock.
- Drop folder with and without subfolders enabled.

### 10.4 Manual QA

Before release:

- Test on a clean macOS Tahoe install.
- Test without network access.
- Test notarized build, not only debug build.
- Test app moved to `/Applications`.
- Test qpdf execution inside the signed app bundle.

---

## 11. Performance Targets

These are targets, not hard promises:

| Case | Target |
|---|---|
| Small PDF under 10 MB | Under 1 second |
| Medium PDF under 100 MB | Under 5 seconds |
| Batch of 50 small PDFs | Under 60 seconds |
| App launch | Under 2 seconds |
| UI responsiveness | No blocking during processing |

For very large files, the app should remain responsive and show progress or an active running state.

---

## 12. Distribution

### 12.1 v1 Channel

Direct download only:

- `.dmg` or `.zip`.
- Developer ID signed.
- Hardened Runtime enabled.
- Notarized and stapled.

### 12.2 Entitlements

```text
com.apple.security.app-sandbox = optional for direct v1
com.apple.security.files.user-selected.read-write = YES if sandboxed
com.apple.security.network.client = NO
```

### 12.3 Release Checklist

- App binary signed.
- qpdf binary signed.
- Hardened Runtime enabled.
- qpdf license included.
- Notarization passes.
- App runs after download on a clean Mac.
- No network entitlement present.
- Privacy statement included in app and download page.

---

## 13. Milestones

### M0 — Skeleton

- SwiftUI app shell.
- Drop zone.
- Queue model.
- Settings model.
- Basic file picker.

### M1 — Core Unlock

- PDF inspection.
- Known-password unlock with PDFKit.
- Owner-restriction removal where PDFKit succeeds.
- Atomic output writing.
- Output verification.
- Basic row statuses.

### M2 — qpdf Fallback

- Bundle qpdf.
- Add signed `QPDFRunner`.
- Fallback when PDFKit fails.
- Map qpdf errors to app errors.
- Add qpdf-specific tests.

### M3 — Batch and Polish

- Batch queue.
- Limited concurrency.
- Preflight summary.
- Session-only shared password.
- Conservative folder input.
- Retry failed files.
- Cancel remaining work.
- Finder reveal.
- Settings window.
- Redacted failure reports.

### M4 — Release

- App icon.
- Hardened Runtime.
- Code signing.
- Notarization.
- Clean-machine QA.
- Direct download package.

Expected v1 timeline: 3 to 5 weeks for a focused build.

---

## 14. Post-v1 Roadmap

Consider only after v1 is stable:

- Finder Quick Action.
- Finder context menu.
- CLI helper.
- Menu bar drop utility.
- Persistent history.
- Mac App Store variant.
- Sparkle updater.
- Localization.
- Keychain-based optional password memory.
- Advanced preview pane.

---

## 15. Open Questions

1. Should direct v1 be sandboxed, or only hardened and notarized?
2. Should Intel Macs be supported, or Apple Silicon only?
3. Should unencrypted PDFs be skipped by default or copied with the suffix?
4. Should overwrite mode exist in v1, or be deferred?
5. What is the final product name and bundle identifier?
6. Is qpdf licensing acceptable for the intended distribution model?

---

## 16. Summary

This v1 keeps the app focused: drag in PDFs, unlock with known passwords, remove standard restrictions where possible, process batches locally, write safe output files, and ship as a notarized Mac app.

The strongest version combines Minimax's product clarity with Deepseek's practical qpdf fallback. The result is smaller, more honest, and more buildable.

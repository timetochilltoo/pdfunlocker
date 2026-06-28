# PDF Unlock — v2 Specification

**Status:** Draft v2.0 (design doc — see [README.md](README.md) for current build state)  
**Date:** 2026-06-25  
**Platform:** macOS 26 Tahoe 26.5.1+  
**Language:** Swift 6  
**UI Framework:** SwiftUI  
**Distribution:** Direct download, Developer ID signed and notarized  
**Privacy Model:** Local-only, no network, no analytics  
**Working Folder:** `/Users/patrickshi/Minimax Coding/PDF Unlocker/`

> **Note on status:** This spec is the **forward-looking design**. Current build state — what's done, what's pending, how to build — lives in [README.md](README.md). Milestones §13 below lists the planned order; the README's "What's done" table shows actual completion.

---

## Changelog from v1

- **NEW — Two top-level modes:** A segmented control in the toolbar switches between **Unlock** mode and **Convert** mode. The two workflows are independent, so users who only need conversion never see unlock UI, and vice versa.
- **NEW — Convert mode:** PDF → TXT, PDF → PNG (per page), and PDF → Markdown (experimental, best-effort).
- **NEW — Bounded dictionary/wordlist recovery:** A scoped, opt-in recovery aid for forgotten passwords on the user's own documents. Local wordlists only, with hard attempt/time caps and clear UI feedback.
- **UPDATED — Non-goals:** Removed "PDF conversion" (now in scope). Added "unbounded password cracking".
- **UPDATED — Functional scope:** Added F19–F33.
- **UPDATED — Architecture:** Added `Convert/` and `Recovery/` modules.
- **PRESERVED — Everything else:** Atomic writes, output verification, batch behavior, privacy guarantees, distribution model. The original `spec-v1.md` is kept in this folder for reference.

---

## 1. Overview

### 1.1 Purpose

PDF Unlock v2 is a native macOS utility with two clearly separated modes:

1. **Unlock mode** — creates unlocked copies of PDF files that the user owns or has the right to modify, including a scoped recovery aid for forgotten passwords.
2. **Convert mode** — produces TXT, PNG, or Markdown output from PDFs the user supplies, locally, with no upload.

The app never contacts a server, never collects analytics, never attempts unbounded password cracking.

### 1.2 Core Value Proposition

Pick a mode — **Unlock** or **Convert** — drop in PDFs, and the app handles it cleanly, locally, and honestly. If the app can't do it (unknown password, DRM, corrupt file, encrypted PDF), it says so explicitly instead of silently failing.

### 1.3 Design Principles

1. **Local-only:** no network calls, no telemetry, no cloud processing.
2. **Honest limits:** if a password is unknown and recovery fails, the app says so clearly.
3. **Two clear modes:** Unlock and Convert are first-class, switchable from a single segmented control.
4. **Bounded recovery:** password recovery is opt-in, local, capped, and not a general-purpose cracker.
5. **Safe by default:** originals are preserved; output writes are atomic; outputs are verified before being marked successful.
6. **Native macOS feel:** SwiftUI, toolbar, drag and drop, Finder reveal, Quick Look preview where simple.
7. **Small v2:** ship the reliable core first; keep extensions and power-user tools for later.
8. **Everything in one folder:** all working files (specs, project source, fixtures, scripts) live inside `PDF Unlocker/`. No scattered paths.

### 1.4 Target Users

- Office workers handling client PDFs.
- Researchers with legitimately accessible but restricted papers.
- Admins cleaning up batches of generated documents.
- Mac users who want a private, no-upload PDF workflow.
- Users who want to extract text or images from PDFs without uploading to a web service.
- Users who forgot a password on a document they own and need a bounded recovery aid.

### 1.5 Non-Goals for v2

- Unbounded password cracking, GPU brute force, or rainbow tables.
- DRM removal beyond what PDFKit and qpdf support natively.
- PDF editing, annotation, page management, OCR.
- iOS, iPadOS, visionOS, or web versions.
- Finder extension, Quick Action, menu bar utility, or CLI helper.
- Persistent job history.
- Cloud sync or account system.
- Mac App Store release.
- DOCX/HTML conversion (deferred to v3).

---

## 2. Functional Scope

### 2.1 v2 Must-Have Features

| ID     | Feature                                                                    | Priority |
| ------ | -------------------------------------------------------------------------- | -------- |
| F1     | Drag and drop PDF files onto the app window                                | P0       |
| F2     | Choose PDFs using a native file picker                                     | P0       |
| F3     | Add multiple PDFs to a batch queue                                         | P0       |
| F4     | Detect whether each PDF is unlocked, open-password protected, owner-restricted, or unsupported | P0       |
| F5     | Prompt for known open passwords using secure input                         | P0       |
| F6     | Remove open password protection when the correct password is supplied      | P0       |
| F7     | Remove owner/permissions restrictions where PDFKit or qpdf can do so        | P0       |
| F8     | Write unlocked output files atomically                                     | P0       |
| F9     | Preserve original files by default                                         | P0       |
| F10    | Show per-file status, progress, and errors                                 | P0       |
| F11    | Provide clear retry behavior for wrong passwords                           | P0       |
| F12    | Reveal successful output in Finder                                         | P1       |
| F13    | Let user select output folder and filename suffix                          | P1       |
| F14    | Code sign, harden, and notarize for direct distribution                    | P0       |
| F15    | Preflight summary before unlocking large batches                           | P1       |
| F16    | Session-only shared password helper                                        | P1       |
| F17    | Verify unlocked output before marking success                              | P0       |
| F18    | Export a redacted failure report for support/debugging                     | P2       |
| **F19** | **Mode selector: Unlock vs Convert in toolbar**                        | **P0**   |
| **F20** | **Convert mode: PDF → TXT**                                            | **P0**   |
| **F21** | **Convert mode: PDF → PNG (per page, configurable DPI)**               | **P0**   |
| **F22** | **Convert mode: PDF → Markdown (experimental, best-effort)**           | **P1**   |
| **F23** | **Convert mode: pick output formats (multi-select)**                   | **P0**   |
| **F24** | **Convert mode: page range selection (all / custom)**                  | **P1**   |
| **F25** | **Convert mode: PNG DPI setting (72 / 150 / 300)**                    | **P1**   |
| **F26** | **Convert mode: atomic writes and verification**                       | **P0**   |
| **F27** | **Dictionary/wordlist recovery: opt-in button per file**               | **P1**   |
| **F28** | **Recovery: bundled common-passwords wordlist**                        | **P1**   |
| **F29** | **Recovery: user-supplied custom wordlist file**                       | **P1**   |
| **F30** | **Recovery: hard caps (max attempts, max seconds)**                    | **P0**   |
| **F31** | **Recovery: progress UI (attempts/sec, ETA, cancel)**                  | **P0**   |
| **F32** | **Recovery: pattern mutations (capitalize, append year/digit)**         | **P1**   |
| **F33** | **Recovery: never log candidate passwords**                            | **P0**   |

### 2.2 Deferred Features (v3+)

- DOCX, HTML, RTF conversion.
- Finder Quick Action / context menu.
- CLI companion.
- Menu bar drop utility.
- Persistent history database.
- SwiftData-backed job archive.
- Mac App Store variant.
- Automatic updater.
- Localization beyond English.
- Advanced preview/editor UI.
- Keychain-based optional password memory.
- OCR layer for scanned PDFs.

### 2.3 Recommended Additions (carried from v1)

These still apply; see v1 §2.3 for full detail:

- **A. Preflight Summary** (now also shows conversion estimates per file).
- **B. Session-Only Shared Password** (unchanged).
- **C. Output Verification** (extended to convert outputs).
- **D. Redacted Failure Report** (extended to include convert and recovery failures).
- **E. Drag Folder as Convenience Input** (now applies to both modes).

---

## 3. User Workflow

### 3.1 Mode Selection (NEW)

The app opens in **Unlock mode** by default. A segmented control in the toolbar switches between modes:

```text
┌──────────────────────────────────────────────────────────┐
│ Toolbar: [Unlock | Convert]   Add Files   Run   Settings │
└──────────────────────────────────────────────────────────┘
```

The mode is session-only and resets to **Unlock** on app relaunch.

### 3.2 Unlock Mode Flow

Carried from v1 with one addition (recovery):

1. User opens PDF Unlock.
2. User drops one or more PDFs into the window, or chooses files with the file picker.
3. App analyzes each file.
4. App shows a preflight summary for the queue.
5. Files that need an open password show an inline password field.
6. User may enter one session-only shared password and apply it to all password-required files.
7. **For any file marked "needs password", user can click "Try recovery" to launch the bounded wordlist attack.**
8. User chooses output behavior (same folder with `-unlocked` suffix, or custom folder).
9. User clicks **Run**.
10. App processes the queue locally.
11. App verifies each output before marking it successful.
12. Each row shows success, failure, or skipped state.
13. User can reveal successful outputs in Finder.

### 3.3 Convert Mode Flow (NEW)

1. User switches to **Convert** mode.
2. User drops one or more PDFs into the window, or chooses files with the file picker.
3. App analyzes each file: page count, estimated text density, encryption status.
4. User picks output formats (multi-select: TXT, PNG, Markdown). At least one required.
5. User configures options:
   - TXT: page range (default all).
   - PNG: DPI (default 150; choices 72, 150, 300), page range (default all).
   - Markdown: page range (default all), experimental toggle (default on with warning).
6. User chooses output location (same folder with suffix, or custom folder).
7. App shows a preflight panel:
   - Total PDFs.
   - Per-format output preview.
   - Warnings for encrypted or scanned PDFs (Markdown/TXT may be empty).
8. User clicks **Run**.
9. App processes each file, writing TXT/PNG/MD outputs atomically.
10. Each row shows success/failure state with output paths.
11. User can reveal outputs in Finder.

### 3.4 Output Rules (mostly unchanged)

Default suffix: `-unlocked` (unlock mode) or `-converted` (convert mode). Per-format suffixes for convert:

```text
Original: report.pdf
TXT:      report-converted.txt
PNG:      report-converted-images/page-001.png, ...
MD:       report-converted.md
```

Collision behavior unchanged: `-2`, `-3`, etc. by default; overwrite only if user enables it.

### 3.5 Batch Behavior (unchanged)

- Multiple files processed without blocking UI.
- Default concurrency: 2 files at a time.
- Users can cancel the remaining queue.
- Completed files remain completed when later files fail.
- Failed files can be retried with a new password.

### 3.6 Folder Input (unchanged)

Same conservative defaults: top-level scan, optional subfolders, skip hidden files, ignore symlinks, silently skip non-PDFs.

### 3.7 Recovery Flow Detail (NEW)

When user clicks **Try recovery** on a file in Unlock mode:

1. App shows recovery options dialog:
   - Use bundled common-passwords wordlist (recommended).
   - Choose custom wordlist file.
   - Set max attempts (default 10,000; cap 1,000,000).
   - Set max time in seconds (default 60; cap 600).
   - Enable pattern mutations (default on).
2. User clicks **Start recovery**.
3. Row shows progress: `attempts: 1,234 / 10,000 · 412/s · ETA 21s`.
4. **Cancel** button always available.
5. On match: row transitions to "Password found (preview only — enter to confirm)". The found password is shown masked (`••••••`) with a **Reveal** button, and the user must explicitly confirm before the unlock proceeds. This prevents silent unlocks and gives the user a chance to verify the candidate.
6. On cap reached: row shows "Recovery exhausted. Try a different wordlist."
7. On cancel: row returns to "Needs password" state.

---

## 4. Unlocking Behavior

### 4.1 Supported Cases (unchanged)

| PDF Case                                  | Expected Behavior                                       |
| ----------------------------------------- | ------------------------------------------------------- |
| Not encrypted                             | Mark as "No password needed"; do not write output by default |
| Open-password protected                   | Require user password; write unlocked copy on success   |
| Owner/permissions restricted only         | Attempt to write unrestricted copy                      |
| Both open password and owner restrictions | Require open password; write unrestricted copy if possible |
| Wrong password                            | Show inline error and allow retry                       |
| Certificate-based encryption              | Show unsupported error                                  |
| Adobe DRM or non-standard DRM             | Show unsupported error                                  |
| Corrupt PDF                               | Show invalid/corrupt PDF error                          |
| Digitally signed PDF                      | Warn that unlocking may invalidate signatures          |

### 4.2 Technical Strategy (unchanged)

Two-layer unlock:

1. **Primary: PDFKit** — `PDFDocument.unlock(withPassword:)`, re-save.
2. **Fallback: bundled qpdf** — `qpdf --decrypt`, run via `Process`.

### 4.3 Dictionary/Wordlist Recovery (NEW)

**Scope:** local-only, opt-in, bounded. Not a general cracker.

**Wordlist sources:**

- **Bundled:** `Resources/wordlists/common.txt` — top ~50,000 common passwords (curated, no leaked breach dumps).
- **User-supplied:** any plain-text file the user picks, one candidate per line.

**Pattern mutations (optional):**

- Capitalize first letter.
- All-caps.
- Append 2-digit year (00–30).
- Append 4-digit year (1990–2030).
- Append 1–3 digit number.
- Append common suffixes (`!`, `?`, `.`, `#`).

These are run on each base word and combined multiplicatively only when the resulting set stays under the cap. Mutations are off by default for performance.

**Hard caps:**

| Cap                | Default  | Maximum allowed |
| ------------------ | -------- | --------------- |
| Max attempts       | 10,000   | 1,000,000       |
| Max time (seconds) | 60       | 600             |
| Concurrency        | 1 file   | 1 file          |

**PDF compatibility:** recovery only attempts against PDFs that PDFKit can open with a candidate password. PDFs that PDFKit reports as unsupported encryption are skipped (no qpdf fallback for recovery in v2).

**Logging rules:**

- Never log candidate passwords.
- Never log wordlist contents.
- Log only: counts, rates, timing, final result category.

**Confirmation requirement:** On a match, the user must confirm before the unlock proceeds. No silent unlocks from recovery.

### 4.4 Important Caveat (updated)

PDFKit does not expose every detail of PDF encryption and permissions. The app does not promise universal unlocking. Recovery is best-effort against local wordlists and bounded by configurable caps — it is not a guarantee.

---

## 4.5 Convert Behavior (NEW)

### 4.5.1 Supported Output Formats

| Format    | Status      | What it produces                                       |
| --------- | ----------- | ------------------------------------------------------ |
| **TXT**   | Stable      | Plain text, layout-aware via `pdftotext -layout` fallback |
| **PNG**   | Stable      | One PNG per page, configurable DPI                     |
| **MD**    | Experimental | Heuristic Markdown, may not handle complex layouts   |

### 4.5.2 TXT Output

- Single file: `name-converted.txt`.
- Encoding: UTF-8, no BOM.
- Page boundaries marked with form feed (`\f`) between pages.
- Source: PDFKit `pdfDocument.string` per page, with `\n` normalization.
- Fallback: shell out to bundled `pdftotext -layout` when PDFKit returns empty/garbled output.

### 4.5.3 PNG Output

- One folder: `name-converted-images/`.
- One file per page: `page-001.png`, `page-002.png`, ... zero-padded.
- DPI choices: 72, 150, 300. Default 150.
- Source: PDFKit page → `NSImage` → PNG via `NSBitmapImageRep`.
- Fallback: bundled `pdftoppm` (from poppler) for higher performance on large PDFs.

### 4.5.4 Markdown Output (Experimental)

- Single file: `name-converted.md`.
- Heuristics:
  - Lines with significantly larger font on a page → `# Heading`, `## Heading`, etc.
  - Short uppercase lines → potential headings.
  - Numbered list patterns → ordered lists.
  - `- ` / `* ` bullets → unordered lists.
  - Blank lines preserved as paragraph breaks.
  - Tables and multi-column layouts: best-effort, often degraded.
- UI label: "Markdown (Experimental)" — must show experimental badge.
- If heuristics fail badly (no headings detected on a 10+ page PDF), app falls back to a single fenced code block with the raw extracted text, with a warning in the row status.

### 4.5.5 Page Range Selection

- Default: all pages.
- Custom: `1-5`, `1,3,5-7`. Validated before run.

### 4.5.6 Convert Caveats

- Scanned PDFs without an OCR layer produce empty/garbled TXT/MD output. App shows a warning in the preflight panel.
- Encrypted PDFs must be unlocked first (or run via Unlock mode then re-add the output).
- Complex layouts degrade Markdown quality.

---

## 5. User Interface

### 5.1 Mode Selector Toolbar (NEW)

```text
┌────────────────────────────────────────────────────────────────────┐
│ [ Unlock | Convert ]   Add Files   Run All   Cancel   Settings     │
└────────────────────────────────────────────────────────────────────┘
```

The mode selector is leftmost in the toolbar and persists for the current session.

### 5.2 Unlock Mode UI

Same as v1 §5.1 with these additions:

- Each row with `needsPassword` status has a **Try recovery** button next to the password field.
- Recovery progress replaces the password field while running: `attempts / cap · rate · ETA`.
- On match, password field shows masked password with **Use this password** button.

### 5.3 Convert Mode UI (NEW)

```text
┌────────────────────────────────────────────────────────────────────┐
│ [ Unlock | Convert ]   Add Files   Run All   Cancel   Settings     │
├────────────────────────────────────────────────────────────────────┤
│  Output formats:  [✓] TXT  [✓] PNG (150 DPI ▾)  [⚠] Markdown      │
│  Page range:      [All ▾]                                        │
│  Markdown:        Experimental — best-effort, complex layouts may degrade │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  File          Pages  Status        Output                        │
│  report.pdf    24     Ready         report-converted.txt           │
│                              +      report-converted-images/       │
│                              +      report-converted.md            │
│  scan.pdf      10     Warning       ⚠ No OCR — text may be empty  │
│  locked.pdf    8      Skipped       Encrypted — unlock first       │
│                                                                    │
├────────────────────────────────────────────────────────────────────┤
│ Output: Same folder · Suffix: -converted                            │
└────────────────────────────────────────────────────────────────────┘
```

### 5.4 Empty States

- **Unlock mode empty:** "Drop PDFs to unlock. Files stay on this Mac."
- **Convert mode empty:** "Drop PDFs to convert. Output stays on this Mac."

### 5.5 Settings (extended)

Carries v1 settings and adds:

- **Recovery defaults:**
  - Default max attempts (default 10,000).
  - Default max time (default 60s).
  - Default enable mutations (default on).
- **Convert defaults:**
  - Default PNG DPI (default 150).
  - Default enable Markdown (default on, with experimental warning).
- **Existing output behavior:** Keep both / Ask / Overwrite.

---

## 6. Architecture

### 6.1 Stack (extended)

| Layer               | Technology                       |
| ------------------- | -------------------------------- |
| UI                  | SwiftUI                          |
| State               | Observation / `@Observable`      |
| PDF primary engine  | PDFKit                           |
| PDF fallback engine | Bundled `qpdf`                   |
| Text extract        | PDFKit + bundled `pdftotext`     |
| Image export        | PDFKit + bundled `pdftoppm`      |
| Recovery engine     | Local wordlist + custom mutator  |
| File access         | Security-scoped URLs where needed|
| Concurrency         | Swift Concurrency                |
| Logging             | `os.Logger`                      |
| Persistence         | `UserDefaults` for settings only |
| Distribution        | Developer ID, Hardened Runtime, notarization |

### 6.2 Project Layout (extended)

```text
PDFUnlock/
├── App/
│   ├── PDFUnlockApp.swift
│   └── Commands.swift
├── Features/
│   ├── Unlock/
│   │   ├── UnlockView.swift
│   │   ├── UnlockViewModel.swift
│   │   └── RecoveryDialog.swift
│   ├── Convert/
│   │   ├── ConvertView.swift
│   │   ├── ConvertViewModel.swift
│   │   └── FormatPicker.swift
│   ├── Queue/
│   ├── DropZone/
│   ├── Settings/
│   └── Common/
│       ├── ModeSelector.swift
│       └── PreflightPanel.swift
├── Core/
│   ├── PDFUnlocker.swift
│   ├── PDFInspector.swift
│   ├── QPDFRunner.swift
│   ├── FileNaming.swift
│   ├── AtomicWriter.swift
│   ├── UnlockError.swift
│   ├── Convert/
│   │   ├── TXTExtractor.swift
│   │   ├── PNGExporter.swift
│   │   └── MarkdownExporter.swift
│   └── Recovery/
│       ├── WordlistRecovery.swift
│       ├── PatternMutator.swift
│       └── WordlistLoader.swift
├── Models/
│   ├── UnlockJob.swift
│   ├── UnlockStatus.swift
│   ├── PDFInspection.swift
│   ├── ConvertJob.swift
│   ├── ConvertStatus.swift
│   ├── ConvertFormat.swift
│   └── AppMode.swift
├── Resources/
│   ├── qpdf
│   ├── pdftotext
│   ├── pdftoppm
│   ├── wordlists/
│   │   └── common.txt
│   └── Assets.xcassets
└── PDFUnlock.entitlements
```

### 6.3 Core API (extended)

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

public struct PDFConverter: Sendable {
    public struct Options: Sendable {
        public var formats: Set<ConvertFormat>
        public var pageRange: PageRange?
        public var pngDPI: Int
    }

    public func convert(
        input: URL,
        outputDirectory: URL,
        options: Options
    ) async throws -> ConvertResult
}

public struct WordlistRecovery: Sendable {
    public struct Config: Sendable {
        public var maxAttempts: Int
        public var maxSeconds: Int
        public var enableMutations: Bool
        public var customWordlistURL: URL?
    }

    public func attemptRecovery(
        pdfURL: URL,
        config: Config,
        progress: @escaping @Sendable (RecoveryProgress) -> Void
    ) async throws -> RecoveryOutcome
}
```

### 6.4 Mode and Job Models (new)

```swift
enum AppMode: String, CaseIterable {
    case unlock
    case convert
}

@Observable
final class ConvertJob: Identifiable {
    let id: UUID
    let inputURL: URL
    var formats: Set<ConvertFormat>
    var outputDirectory: URL
    var pageRange: PageRange?
    var status: ConvertStatus
    var progress: Double
    var errorMessage: String?
    var outputs: [ConvertFormat: URL]
}
```

### 6.5 Status Models (new)

```swift
enum ConvertStatus: Equatable {
    case queued
    case inspecting
    case ready
    case running
    case succeeded
    case partialSuccess   // some formats OK, others failed
    case skipped
    case failed
    case cancelled
}

enum RecoveryOutcome: Equatable {
    case matched(password: String, attempts: Int)
    case exhausted(attempts: Int)
    case cancelled
    case unsupportedEncryption
}

struct RecoveryProgress: Sendable {
    let attempts: Int
    let cap: Int
    let ratePerSecond: Double
    let estimatedSecondsRemaining: Int
}
```

---

## 7. Security and Privacy

### 7.1 Privacy Requirements (unchanged)

- No network entitlement.
- No analytics.
- No crash reporting uploads.
- No password persistence.
- No passwords in logs.
- **No candidate passwords in recovery logs.**
- No indexing of PDF contents.
- All processing happens locally.

### 7.2 Password Handling (extended)

- Passwords entered via `SecureField`.
- Recovery-matched passwords are shown masked by default with explicit reveal.
- After unlock, the password is cleared from the job's in-memory state.
- After batch completion, cancellation, or app quit, all session passwords (manual and recovered) are cleared.

### 7.3 Bundled Binary Handling (extended)

- Bundle `qpdf`, `pdftotext`, `pdftoppm` as signed universal binaries.
- Code sign each helper.
- Hardened Runtime allows execution.
- Include license notices for qpdf (Apache 2.0) and poppler (GPLv2).
- Wordlist file `common.txt` ships in `Resources/wordlists/`, not bundled inside any binary.

---

## 8. File Safety (extended)

### 8.1 Atomic Writes (unchanged rule)

Same pattern for unlock and convert outputs: temp file → write → validate → atomic rename → cleanup on failure.

### 8.2 Output Verification (extended)

- **Unlock:** same as v1.
- **Convert TXT:** reopen output, confirm non-empty (unless source had no text layer), confirm UTF-8 decodable.
- **Convert PNG:** confirm each PNG decodes as a valid image with expected dimensions.
- **Convert Markdown:** confirm file decodes as UTF-8 and contains at least the expected page separator count.

### 8.3 Original File Protection (unchanged)

Convert mode never modifies the input PDF.

---

## 9. Error Handling (extended)

### 9.1 New Error Categories

| Error                       | User Message                                            |
| --------------------------- | ------------------------------------------------------- |
| Wordlist not found          | "The wordlist file could not be loaded."                |
| Wordlist empty              | "The wordlist contains no candidates."                  |
| Recovery exhausted          | "Recovery ran through all candidates without a match."  |
| Recovery cancelled          | "Recovery was cancelled."                               |
| Recovery unsupported        | "This PDF uses encryption that recovery cannot try."    |
| Convert no OCR layer        | "This PDF appears to be a scan with no text layer. Output may be empty." |
| Markdown generation failed  | "Markdown conversion couldn't produce useful output. Saved as raw text instead." |
| Page range invalid          | "The page range is not valid for this PDF."             |

### 9.2 UI Rules (unchanged)

Inline row errors preferred. Modals only for destructive choices and signature warnings. Failed files offer "Copy Report" with redacted diagnostic.

---

## 10. Testing Strategy (extended)

### 10.1 New Required Test Fixtures

- Markdown-friendly PDF (with headings, lists).
- Scanned PDF without OCR layer.
- PNG convert target (multi-page, mixed sizes).
- Password-protected PDF with a password that appears in the bundled common wordlist.
- Password-protected PDF with a custom wordlist match.

### 10.2 New Unit Tests

- TXT extraction on standard PDF.
- TXT extraction fallback to `pdftotext` when PDFKit returns empty.
- PNG export at 72/150/300 DPI.
- Markdown export headings detection.
- Markdown fallback to fenced code block.
- Page range parsing and validation.
- Wordlist loader for bundled and custom lists.
- Pattern mutator output size estimation under cap.
- Recovery cap (attempts) enforcement.
- Recovery cap (time) enforcement.
- Recovery cancel mid-run.
- Recovery returns `unsupportedEncryption` for non-PDFKit-openable PDFs.
- Recovery never logs candidate passwords (log capture assertion).

### 10.3 New UI Tests

- Switch between Unlock and Convert modes.
- Convert single PDF to TXT only.
- Convert single PDF to all three formats.
- PNG DPI selection.
- Page range custom input.
- Recovery: start, cancel, match, confirm.
- Recovery cap reached message.
- Convert preflight warning for scanned PDF.

### 10.4 Manual QA additions

- Confirm recovery progress UI updates without blocking main thread.
- Confirm cancellation cleans up running recovery state.
- Confirm bundled wordlist loads correctly inside signed app bundle.

---

## 11. Performance Targets (extended)

| Case                                   | Target           |
| -------------------------------------- | ---------------- |
| Small PDF unlock (< 10 MB)             | Under 1 second   |
| Medium PDF unlock (< 100 MB)           | Under 5 seconds  |
| TXT convert 100-page PDF               | Under 3 seconds  |
| PNG convert 100-page PDF at 150 DPI    | Under 30 seconds |
| Markdown convert 100-page PDF          | Under 5 seconds  |
| Recovery 10,000 candidates             | Under 60 seconds |
| Batch of 50 small PDFs (any mode)      | Under 60 seconds |
| App launch                             | Under 2 seconds  |
| UI responsiveness                      | No blocking during processing |

---

## 12. Distribution (unchanged)

Direct download only: `.dmg` or `.zip`, Developer ID signed, Hardened Runtime, notarized and stapled.

### 12.1 Updated Release Checklist

- App binary signed.
- All bundled helpers (`qpdf`, `pdftotext`, `pdftoppm`) signed.
- Bundled wordlist file verified intact inside app bundle.
- Hardened Runtime enabled.
- License notices for qpdf and poppler included.
- Notarization passes.
- App runs on clean Mac after download.
- No network entitlement present.
- Privacy statement included in app and download page.
- Recovery defaults documented in privacy statement ("recovery is local, bounded, no network").

---

## 13. Milestones (extended)

### M0 — Skeleton

- SwiftUI app shell.
- Mode selector toolbar.
- Drop zone.
- Queue models (unlock + convert).
- Settings model.
- File picker.

### M1 — Core Unlock (carried from v1)

- PDF inspection.
- Known-password unlock with PDFKit.
- Owner-restriction removal where PDFKit succeeds.
- Atomic output writing.
- Output verification.
- Row statuses.

### M1.5 — Core Convert (NEW)

- Convert view shell.
- TXT extraction (PDFKit + `pdftotext` fallback).
- PNG export at configurable DPI.
- Markdown export (experimental, with fallback).
- Page range support.
- Convert preflight panel.

### M2 — qpdf Fallback (carried)

- Bundle `qpdf`.
- Signed `QPDFRunner`.
- Fallback when PDFKit fails.
- Error mapping.
- Tests.

**Implementation note (post-build, 2026-06-26):** For `.ownerOnly` PDFs, the PDFKit path was found to silently preserve the print=none flag in the re-saved output (verified via `cupsfilter` — output was a 1KB error message vs 32KB valid PostScript for the unlocked version). The unlocker now routes `.ownerOnly` straight to qpdf from the start (PDFKit is only used for plain PDFs and user-password PDFs). `UnlockViewModel` explicitly sets `useQPDFFallback: true` to make the intent visible. See `PDFUnlock/Core/PDFUnlocker.swift` §unlock and `PDFUnlock/Features/Unlock/UnlockViewModel.swift` for the wiring.

### M2.5 — Recovery (NEW)

- Wordlist loader (bundled + custom).
- Pattern mutator.
- Recovery engine with caps.
- Recovery UI (progress, cancel, confirm).
- Settings entries.

### M3 — Batch and Polish (carried + extended)

- Batch queue (both modes).
- Limited concurrency.
- Preflight summary (both modes).
- Session-only shared password.
- Conservative folder input.
- Retry failed files.
- Cancel remaining work.
- Finder reveal.
- Settings window.
- Redacted failure reports (extended to convert and recovery).

### M4 — Release

- App icon.
- Hardened Runtime.
- Code signing.
- Notarization.
- Clean-machine QA.
- Direct download package.

**Implementation note (post-build, 2026-06-26):** Debug-only ad-hoc signing is in place (`codesign --sign -`). The bundled `qpdf` binary and `libqpdf.30.3.2.dylib` are also ad-hoc signed; `install_name_tool` was used to embed `@loader_path/libqpdf.30.dylib` in the qpdf executable so the dylib resolves at runtime. Notarization and Developer ID signing remain pending.

Expected v2 timeline: 4 to 6 weeks for a focused build.

---

## 14. Post-v2 Roadmap (extended)

- DOCX, HTML, RTF conversion.
- OCR layer for scanned PDFs.
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
- Wordlist editor / generator.

---

## 15. Open Questions (carried + new)

1. Direct v2 sandboxed, or only hardened and notarized?
2. Intel Mac support, or Apple Silicon only?
3. Unencrypted PDFs in unlock mode: skipped by default or copied with suffix?
4. Overwrite mode in v2, or deferred?
5. Final product name and bundle identifier?
6. qpdf + poppler licensing acceptable for direct distribution?
7. **Bundled wordlist size: 10k, 50k, or 100k entries?** (size affects app download size)
8. **Should Markdown be opt-in per run, or always available behind an experimental badge?**
9. **Recovery: should we ship NO bundled wordlist (user must always supply), to keep the app footprint small and the position maximally honest?**

---

## 16. Summary

PDF Unlock v2 keeps everything good from v1 and adds two carefully scoped capabilities:

1. **A Convert mode** for local PDF → TXT / PNG / Markdown, with Markdown flagged experimental.
2. **Bounded dictionary/wordlist recovery** for forgotten passwords on the user's own documents, with hard caps, masked previews, and explicit confirmation.

The app stays local-only, honest about limits, safe by default, and ships through the same notarized direct-download pipeline. Everything lives in `PDF Unlocker/` — no scattered working directories.
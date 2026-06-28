# PDF Unlock — Handoff Documentation

**Purpose:** this document lets a fresh agent or session continue the project without prior context. Read it top to bottom before doing anything. If you only have time to read one section, read **§11 Bugs already fixed** and **§13 Things NOT to do** — those prevent the most painful regressions.

---

## 1. TL;DR

A native macOS 26 / Swift 6 / SwiftUI app for unlocking and converting PDF files locally. Two toolbar modes: **Unlock** (M0/M1/M2 done) and **Convert** (UI shell only, Run-All disabled). Bundled `qpdf 12.3.2` for fallback on PDFs that PDFKit can't handle cleanly. **11/11 smoke tests passing** against real PDFs (plain, owner-restricted 40/128-bit, user-password 256-bit, corrupt).

Working folder: `/Users/patrickshi/Minimax Coding/PDF Unlocker/`. Always work inside this folder.

---

## 2. The user

**Patrick** (`/Users/patrickshi/`). Hong Kong-based (UTC+8). Galaxy S24 Ultra + Fold 6. Comfortable with technical depth (asked about server-vs-direct, RE approach, etc.).

**Work style — non-negotiable:**
- Wants detailed specs and logic breakdowns before implementation. Don't dive into code without a plan he can review.
- Explicitly wants confirmation before cutting scope or features. **Do not silently simplify.** Always confirm scope with him first.
- He has explicitly said: "do not assume / do not silently simplify."
- He's fine with you making progress, but if you make a non-obvious decision, explain the why.

**Communication style:**
- He's concise. Match his energy — don't pad responses.
- He uses both English and Chinese context but prefers English for technical docs.
- When something fails, he wants honest assessment ("did X fail?" gets answered "yes, here's why and what I'm doing"), not reassuring but vague answers.
- He asks "what's done / what's not" frequently — keep milestone status easy to find (it's in `README.md`).

**Other context:** his user profile lives at `/Users/patrickshi/.mavis/` (managed by the Mavis runtime). Don't write to it directly unless asked — but DO read it for hints if you need context.

---

## 3. Project origin

Patrick asked: "Can I build an app that bypasses restriction on PDF printing and save?" → led to a conversation about legal limits, technical options (PDFKit vs qpdf), and his actual use case (unlock his own document he forgot the password to). The outcome:

- v1 spec was drafted by Codex (an AI agent), giving us `spec-v1.md` (kept as reference, not the active spec).
- v2 spec (`spec-v2.md`) was written by Mavis (this agent) and adds Convert mode + dictionary recovery on top of v1's unlock scope.
- Implementation has been iterative: spec first, then milestones M0 → M1 → M2. M1.5/M2.5/M3/M4 are pending.

---

## 4. Current build state

| Milestone | Status | Notes |
|---|---|---|
| **M0** — Skeleton (SwiftUI shell, mode selector, drop zone, queue, settings) | ✅ Done | App launches, navigates between Unlock and Convert views, accepts drag-drop and ⌘O file picker. |
| **M1** — Core Unlock (PDFKit inspect/unlock, atomic write, verifier) | ✅ Done | PDFKit path works for plain PDFs and user-password PDFs. |
| **M2** — qpdf fallback (bundled binary, error mapping) | ✅ Done | Bundled qpdf + libqpdf.dylib. Owner-restricted PDFs route straight to qpdf. 40-bit / weak encryption handled via qpdf. |
| **M1.5** — Convert mode (TXT, PNG, Markdown) | ⏳ Pending | ConvertView shell exists, formats enum exists, but Run All is disabled. PDFConverter and the three extractors are not implemented. |
| **M2.5** — Dictionary/wordlist recovery | ⏳ Pending | Spec in `spec-v2.md` §4.3. Zero code. |
| **M3** — Batch polish | ⏳ Partial | Concurrency setting exists, basic retry-on-fail exists, but folder input, redacted failure reports, and most polish are pending. |
| **M4** — Release (Developer ID signing, notarization, DMG) | ⏳ Pending | App is **ad-hoc signed** for local dev only. macOS Gatekeeper will warn on first launch. |

**Smoke tests:** 11/11 passing. Compile and run via `swiftc SmokeTest.swift ... PDFUnlock/Core/*.swift ...`. See `README.md` for the exact command.

---

## 5. Architecture (code-level)

### Source tree (what's actually there)

```
PDFUnlock/
├── App/
│   ├── PDFUnlockApp.swift          @main entry. Owns AppState, wires WindowGroup + Settings scene.
│   └── Commands.swift              Menu bar: Add Files (⌘O), mode switchers (⌘1, ⌘2).
├── Features/
│   ├── Common/
│   │   ├── ContentView.swift       Root router: switches between Unlock/Convert views. Owns the fileImporter.
│   │   └── ModeSelector.swift      Segmented control. ModeBar (unused leftover) at bottom of file — delete if touching.
│   ├── Unlock/
│   │   ├── UnlockView.swift        Queue list, preflight summary, shared password bar, row rendering, retry/reveal/remove actions.
│   │   └── UnlockViewModel.swift   Queue orchestration: inspectAll, runAll (bounded concurrency), cancelAll, applySharedPassword, clearSharedPassword, remove.
│   ├── Convert/
│   │   ├── ConvertView.swift       Stub UI shell. Mirror of UnlockView structure but no logic.
│   │   └── ConvertViewModel.swift  Stub class. ConvertVM.runAll is called from ContentView toolbar but is a no-op until M1.5.
│   ├── DropZone/
│   │   └── DropZone.swift          Generic reusable drag-and-drop. Used by both modes. Has a private LockedBox helper for Swift 6 Sendable-safe collection.
│   └── Settings/
│       └── SettingsView.swift      Settings window content (Cmd+,). Form-based, all backed by AppSettings.
├── Core/
│   ├── UnlockError.swift           13 typed errors. errorDescription drives UI messages. Keep in sync with §9.1 of spec-v2.md.
│   ├── PDFInspector.swift          PDFKit inspection. Returns PDFInspection (encryption kind, page count, text layer, corrupt flag). Also provides open(url:password:) for the unlock path.
│   ├── FileNaming.swift            Suffix logic + collision resolution (-2, -3, etc.). Pure functions, easy to unit test.
│   ├── AtomicWriter.swift          Generic temp-file → validate → rename. Currently unused (PDFUnlocker writes via PDFKit directly + manual temp pattern).
│   ├── Verifier.swift              Post-write verification: ok(pageCount), invalid, stillLocked, pageCountMismatch, empty.
│   ├── PDFUnlocker.swift           The main orchestrator. Routes owner-only → qpdf; other → PDFKit first, qpdf on failure.
│   └── QPDFRunner.swift            Wraps the bundled qpdf binary. Process spawn in Task.detached. stderr → typed error mapping.
├── Models/
│   ├── AppMode.swift               enum unlock / convert. Toolbar segmented control binds to this.
│   ├── AppState.swift              @Observable @MainActor root state. Owns mode, settings, unlock/convert queues, both view models. Has runAllUnlock / cancelUnlock / isUnlockRunning / hasUnlockWork helpers.
│   ├── UnlockJob.swift             @Observable. Has inputURL, fileSize, outputURL, inspection, password, status, progress, errorMessage.
│   ├── UnlockStatus.swift          enum. Display labels in displayLabel.
│   ├── ConvertJob.swift            @Observable. Same shape as UnlockJob but for convert. Includes ConvertStatus.
│   ├── ConvertStatus.swift         enum. Note: .partialSuccess exists but is unused until M1.5.
│   ├── ConvertFormat.swift         enum txt/png/md. isExperimental = true for md. PageRange struct lives here too.
│   └── PDFInspection.swift         struct: pageCount, EncryptionKind (none/ownerOnly/userPassword/certificate/unsupported), hasTextLayer, isCorrupt.
├── Settings/
│   └── AppSettings.swift           @Observable. UserDefaults-backed. Properties: outputLocation, customOutputFolder, unlockSuffix, convertSuffix, collisionBehavior, includeSubfolders, defaultPNGDPI, defaultMarkdown, recoveryMaxAttempts, recoveryMaxSeconds, recoveryMutations, concurrency.
└── Resources/
    ├── Assets.xcassets/            App icon placeholder (Contents.json only, no images).
    ├── qpdf                        arm64 Mach-O executable, ad-hoc signed, install_name_tool'd to look for libqpdf in its own dir.
    ├── libqpdf.30.dylib            Unversioned alias name that qpdf actually looks up at runtime. Ad-hoc signed.
    ├── libqpdf.30.3.2.dylib        Versioned dylib (the actual file).
    └── qpdf.LICENSE                GPL-2.0-or-later notice.
```

### Key types and their invariants

- **`AppMode`** is the source of truth for which view is shown. The toolbar segmented control binds to `AppState.mode`. When changing mode, all UI flows through this single switch.
- **`AppState`** is `@MainActor` and `@Observable`. Mutations happen on the main actor. Background work uses `Task.detached`.
- **`UnlockJob` / `ConvertJob`** are `@Observable` but marked `@unchecked Sendable` because their mutations are coordinated by view models running on `@MainActor`. Don't pass these across actor boundaries without wrapping in a `Task { @MainActor in ... }`.
- **`PDFUnlocker`** is a `Sendable struct` with no mutable state. Safe to share.
- **`QPDFRunner`** is also a `Sendable struct`. The `Process` it spawns lives entirely inside a `Task.detached` closure.
- **`AppSettings`** is `@Observable @unchecked Sendable`. Read/write from anywhere; UserDefaults handles concurrency.

### The unlock pipeline (read this before changing it)

1. User adds a file → DropZone / fileImporter calls `appState.addUnlockJobs(from:)`.
2. UnlockView appears with the new job. `viewModel.inspectAll(jobs)` runs in the background.
3. PDFInspector.inspect() returns a PDFInspection → job.inspection is set.
4. Job transitions to `.ready` (owner-only) or `.needsPassword` (user password) or `.failed` (corrupt/unsupported) or `.skipped` (no encryption).
5. User enters password (if needed) → job.password is set.
6. User clicks Run All → `appState.runAllUnlock()` → viewModel.runAll().
7. For each eligible job, in a TaskGroup with concurrency cap, runOne() is called.
8. runOne calls `PDFUnlocker.unlock(input, output, password, options)`.
9. PDFUnlocker:
   - If `.ownerOnly` → straight to `unlockWithQPDF()` (PDFKit's path silently preserves print=none on owner-restricted PDFs — verified).
   - Else, try `unlockWithPDFKit()`.
   - On PDFKit failure that's recoverable (`.corruptPDF`, `.unsupportedEncryption`, `.verificationFailed`) and `options.useQPDFFallback == true`, try `unlockWithQPDF()`.
   - On user-input failures (`.wrongPassword`, `.missingPassword`, `.permissionDenied`, `.cancelled`), surface the PDFKit error directly — qpdf won't help.
10. Both paths write to a temp file via `defer { removeItem(tempURL) }`, call `Verifier.verify()`, then `moveIntoPlace()`.
11. Result sets job.outputURL, job.status = `.succeeded`, job.password = "" (cleared from memory).

### Error type → UI behavior mapping

Look at `UnlockError.errorDescription` for user-facing messages. Don't change them without updating §9.1 of `spec-v2.md`.

### Settings persistence

`AppSettings` writes through to `UserDefaults` on every property access (get/set). No debouncing — these are infrequent user actions. The UserDefaults keys are private string constants in `AppSettings.Key`.

---

## 6. Critical design decisions (the ones you might second-guess)

### 6.1 "owner-only PDFs route straight to qpdf"

**The bug this prevents:** macOS 26 PDFKit, when re-saving a 128-bit AES owner-restricted PDF via `PDFDocument.write(to:)`, silently preserves the `print=none` flag in the output. The output is "unlocked" in the sense that no password is needed to open it, but the print restriction is still active. This was proven by converting the output to PostScript: 1.2KB error message ("cannot be printed because of incorrect permissions") vs 32KB valid PostScript for the unlocked version.

**The fix:** `PDFUnlocker.unlock()` checks for `.ownerOnly` encryption up front and routes directly to `unlockWithQPDF()`. PDFKit is only used for plain PDFs and user-password PDFs.

**Why not "PDFKit first, qpdf on verify-fail":** because PDFKit "succeeds" on owner-restricted PDFs — it returns success and a valid PDF. The verification step (`Verifier.verify`) only checks for "still locked" / "page count mismatch" / "empty". It doesn't know about per-permission flags. So PDFKit path would always pass verification and we'd never fall through to qpdf.

**If you change this,** verify with this exact test: `qpdf --show-encryption output.pdf` should report "File is not encrypted" for owner-restricted inputs. And `cupsfilter -i application/pdf -m application/postscript output.pdf` should produce >20KB of valid PostScript, not a 1KB error message.

### 6.2 "UnlockViewModel explicitly sets `useQPDFFallback: true`"

The default in `PDFUnlocker.Options(useQPDFFallback: true)` is `true`, but the view model explicitly passes `true` rather than relying on the default. This makes the intent visible in code review and prevents future "PDFKit-only mode for testing" changes from accidentally disabling qpdf. Don't "simplify" this back to the default — the explicitness is load-bearing.

### 6.3 "qpdf bundled as a separate process, not statically linked"

We use `Process()` to launch `Resources/qpdf` as a child process. This keeps the licensing story clean (qpdf is GPL, our app code is not — but a process boundary means qpdf's GPL doesn't impose on us). If you ever switch to in-process qpdf via `libqpdf.a` or a Swift wrapper, you re-open the GPL question.

### 6.4 "Smoke tests are a `swiftc` binary, not an Xcode test target"

`xcodegen` has a quirk where `bundle.unit-test` targets that depend on an `application` target produce `Multiple commands produce '.../PDFUnlock.swiftmodule/...'` errors. We hit this in M1. The standalone `swiftc SmokeTest.swift ...` binary is faster to compile and avoids the quirk. **Do not add an XCTest target unless you've also fixed the underlying xcodegen issue.**

### 6.5 "Post-build script via xcodegen was abandoned"

We tried adding `postBuildScripts` to `project.yml` to auto-copy the built .app to `debug/`. It caused `cp` failures on Xcode's parallel build phases ("Contents/MacOS: No such file or directory"). Replaced with a standalone `scripts/copy_to_debug.sh` that the user runs manually after each Xcode build. **If you re-attempt this**, use a script-based build phase that runs after `.app` itself is finalized, and test on a clean DerivedData first.

### 6.6 "Project layout follows §6.2 of spec-v2.md"

The spec-v2 §6.2 layout was written before any code existed. We've filled in `App/`, `Features/`, `Core/`, `Models/`, `Settings/`. The `Convert/` and `Recovery/` subdirectories from §6.2 are deferred to M1.5 and M2.5 respectively — don't preemptively create them.

### 6.7 "Bundle ID is `com.MiniMax.PDFUnlock` (placeholder)"

The user's product name and bundle ID are open questions in spec-v2 §15. Change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` before any kind of distribution. The user's preference isn't recorded; ask.

---

## 7. Build & run

### First time on a new machine

```bash
# Install xcodegen and qpdf (Homebrew)
brew install xcodegen qpdf

# Generate Xcode project from project.yml
cd "/Users/patrickshi/Minimax Coding/PDF Unlocker"
xcodegen generate

# Open in Xcode
open PDFUnlock.xcodeproj
# Then ⌘R to build and run.
```

### Iterative development

```bash
# In Xcode: ⌘B (build), ⌘R (run).
# After each build, refresh the debug/ copy:
./scripts/copy_to_debug.sh

# Or build + refresh + launch in one go:
./scripts/copy_to_debug.sh --launch
```

### Build from CLI only

```bash
cd "/Users/patrickshi/Minimax Coding/PDF Unlocker"
xcodebuild -project PDFUnlock.xcodeproj \
           -scheme PDFUnlock \
           -configuration Debug \
           -destination 'platform=macOS' \
           build
```

### The `.app` lives in two places

1. **Xcode's DerivedData** (canonical): `~/Library/Developer/Xcode/DerivedData/PDFUnlock-bazwuvhkbkcdxrhdnilfbcudxstm/Build/Products/Debug/PDFUnlock.app`
2. **`debug/PDFUnlock.app`** (user-friendly copy, refreshed by `copy_to_debug.sh`)

Use #2 for daily testing. Use #1 if you need to introspect what Xcode actually built.

---

## 8. Testing

### Smoke tests (recommended)

```bash
cd "/Users/patrickshi/Minimax Coding/PDF Unlocker"
swiftc -parse-as-library \
       -framework PDFKit -framework AppKit \
       -o smoke-test \
       SmokeTest.swift \
       PDFUnlock/Core/*.swift \
       PDFUnlock/Models/PDFInspection.swift \
       PDFUnlock/Models/AppMode.swift \
       PDFUnlock/Models/ConvertFormat.swift \
       PDFUnlock/Settings/AppSettings.swift
./smoke-test
```

Expected: `Passed: 11 / Failed: 0`.

### Test fixtures (in `test-fixtures/`)

- `plain.pdf` — no encryption, plain text
- `owner-restricted.pdf` — 40-bit RC4 owner-only (PDFKit rejects as "corrupt"; qpdf handles)
- `owner-restricted-128.pdf` — 128-bit AES owner-only (PDFKit opens, but writes preserve restriction; qpdf strips)
- `user-password.pdf` — 256-bit AES user password "openpass"
- `weak-40bit.pdf` — 40-bit user password "secret123" (PDFKit rejects, qpdf handles)

### CLI tools (also in root)

- `oneshot-unlock` — unlock a single file. Source: `OneShotUnlock.swift`. Pass input path as argv[1].
- `verbose-unlock` — unlock + detailed verification of the output. Source: `VerboseUnlock.swift`.
- `smoke-test` — the smoke test runner.

These are convenient for one-off testing without launching the GUI.

### Manual UI testing

Drop each fixture PDF onto the running app, click Run All, verify:
- `plain.pdf` → "Skipped" (no encryption to remove)
- `owner-restricted.pdf` → "Unlocked" badge
- `owner-restricted-128.pdf` → "Unlocked" badge
- `user-password.pdf` → "Needs password" badge; enter `openpass`, click Run → "Unlocked"
- `weak-40bit.pdf` → "Needs password"; enter `secret123`, click Run → "Unlocked"

For each "Unlocked" output, verify with: `qpdf --show-encryption output.pdf` → should report `File is not encrypted`. And `cupsfilter -i application/pdf -m application/postscript output.pdf` should produce >20KB valid PostScript.

---

## 9. Known gotchas

These will burn you if you don't know about them.

### 9.1 macOS 26 PDFKit silently preserves owner-restriction flags

See §6.1. The re-saved PDF looks "unlocked" but isn't. Always verify with `qpdf --show-encryption` or `cupsfilter`, not just `PDFDocument.isEncrypted`.

### 9.2 macOS 26 PDFKit rejects 40-bit encryption as "corrupt"

`PDFDocument(url:)` returns nil for 40-bit RC4 PDFs. Don't try to handle this gracefully in PDFKit — there's no graceful handling. Route to qpdf.

### 9.3 Homebrew qpdf links `@rpath/libqpdf.30.dylib` — won't resolve when bundled

Three steps to fix: (1) copy both versioned and unversioned dylibs into Resources, (2) `install_name_tool -change @rpath/libqpdf.30.dylib @loader_path/libqpdf.30.dylib Resources/qpdf`, (3) re-sign with `codesign --force --sign -`. See `README.md` §"Why the bundled qpdf needs an unversioned dylib alias" for the full story.

### 9.4 Xcode Test targets conflict with app targets in xcodegen

Don't add `bundle.unit-test` to `project.yml` without first solving the swiftmodule-duplication error. We worked around with a standalone `swiftc` binary. See §6.4.

### 9.5 Process is not Sendable in Swift 6

When wrapping Process in a Sendable struct, the closure passed to `Task.detached` must capture the Process locally — it must not cross an actor boundary. Pattern:

```swift
public func run() async throws {
    try await Task.detached(priority: .userInitiated) {
        let process = Process()  // local to this closure
        // ... configure, run, waitUntilExit ...
        // process goes out of scope here; safe.
    }.value
}
```

For collecting output, always drain pipes BEFORE `waitUntilExit()` to avoid blocking on a 64KB buffer.

### 9.6 @Observable types crossing actor boundaries need @unchecked Sendable

`UnlockJob` and `ConvertJob` are `@unchecked Sendable`. Mutations happen on `@MainActor` via the view models, and we never pass them across actor boundaries without an explicit `@MainActor in` block. If you add a new model that needs cross-actor sharing, follow the same pattern.

### 9.7 The path has a space in it

`/Users/patrickshi/Minimax Coding/PDF Unlocker/` — note the space. Always quote paths in shell scripts (`"$PROJECT_ROOT"`). The DerivedData path also has UUIDs and dashes but no spaces; only the project folder has the space.

### 9.8 Swift 6 strict concurrency checker doesn't understand raw `NSLock`

If you need to share mutable state across actor boundaries in Swift 6 strict-concurrency mode, the checker won't accept raw `NSLock`. Wrap in a class with `@unchecked Sendable`:

```swift
final class LockedBox<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()
    init(_ v: Value) { value = v }
    func mutate(_ body: (inout Value) -> Void) { lock.lock(); defer { lock.unlock() }; body(&value) }
    func read<R>(_ body: (Value) -> R) -> R { lock.lock(); defer { lock.unlock() }; return body(value) }
}
```

There's already a `LockedBox` in `PDFUnlock/Features/DropZone/DropZone.swift` (private). If you need it elsewhere, extract it to a shared `Core/LockedBox.swift`.

### 9.9 `outputFiles` in xcodegen post-build scripts is finicky

We tried this and it broke. Use a standalone `scripts/copy_to_debug.sh` instead.

### 9.10 macOS Gatekeeper warning on debug/ copy

The `debug/PDFUnlock.app` is ad-hoc signed, not Developer ID. On first launch, macOS will say "this app is from an unidentified developer." User needs to right-click → Open → confirm. This is expected for local dev. Don't try to "fix" it without going through Developer ID + notarization (M4).

---

## 10. Recent changes (chronological, so context isn't lost)

1. **2026-06-25** — Initial conversation about PDF restrictions. Established scope: own docs only, flag-stripping is fine.
2. **2026-06-25** — Codex wrote `spec-v1.md`. Mavis reviewed and wrote `spec-v2.md` adding Convert mode + dictionary recovery.
3. **2026-06-25** — M0: SwiftUI shell, mode selector, drop zone, queue models, settings. xcodegen-based project.
4. **2026-06-26** — M1: Core Unlock with PDFKit. Smoke tests 8/8.
5. **2026-06-26** — M2: qpdf fallback. Bundled qpdf + libqpdf.dylib with install_name_tool fix. Smoke tests 11/11.
6. **2026-06-26** — **BUG**: macOS 26 PDFKit silently preserves owner-restriction flags. Fixed by routing `.ownerOnly` straight to qpdf. Verified via `cupsfilter` (1.2KB error vs 32KB valid PostScript).
7. **2026-06-26** — **BUG**: `UnlockViewModel` had `useQPDFFallback: false` hardcoded. Fixed by setting it to `true` explicitly. Without this fix, the GUI always used PDFKit-only path even though the binary worked.
8. **2026-06-29** — User requested `debug/` folder for easy app launch. Post-build script approach failed (`cp` errors on Xcode parallel builds). Replaced with standalone `scripts/copy_to_debug.sh`.
9. **2026-06-29** — Wrote `README.md` (was missing) and updated `spec-v2.md` with status pointers + M2/M4 implementation notes.

---

## 11. Bugs already fixed (DO NOT re-introduce)

If a future change touches any of these areas, double-check it doesn't regress.

| Bug | Where it lives | How it was fixed | How to verify |
|---|---|---|---|
| macOS 26 PDFKit silently preserves owner-restriction flags | `PDFUnlocker.swift` §unlock — early return on `.ownerOnly` routes to qpdf | Run `owner-restricted-128.pdf` through the app. Output's `qpdf --show-encryption` should say "File is not encrypted". |
| GUI app used PDFKit-only path despite qpdf being available | `UnlockViewModel.swift` `runAll` and `run` — both pass `useQPDFFallback: true` | Same as above. If you see the GUI producing a still-restricted output, this is the first place to check. |
| 40-bit encryption rejected as "corrupt" by PDFKit | `PDFUnlocker.swift` falls back to qpdf on `.corruptPDF` | Run `weak-40bit.pdf` (40-bit user password). Should unlock via qpdf. |
| Wrong password doesn't fall back to qpdf | `PDFUnlocker.swift` `unlock` switch on PDFKit error — `.wrongPassword` throws immediately, qpdf not tried | Enter wrong password for any password-protected PDF. Should get "That password did not unlock this PDF." not a qpdf error. |
| Owner-restricted PDFs without password tried to unlock with empty password | `PDFInspector.open()` returns the doc without trying `unlock(withPassword: "")` for `!isLocked` (owner-only) | Run `owner-restricted-128.pdf`. Should succeed without prompting for password. |
| Swift 6 strict concurrency warning on `var urls` mutated in concurrent DispatchGroup | `DropZone.swift` uses a `LockedBox` to safely collect from concurrent closures | Build clean with no warnings. |
| xcodegen test target conflicts with app target | Abandoned XCTest target in favor of `swiftc` smoke binary | Smoke test runs in ~3s via `swiftc` command in README. |

---

## 12. Roadmap (next milestones, in order)

### M1.5 — Convert mode (~3 days focused work)

**Goal:** Implement PDF → TXT, PNG, Markdown conversion. Run-All in Convert mode works.

**Scope:**
- `Core/Convert/TXTExtractor.swift` — PDFKit `pdfDocument.string` per page, `\f` separators between pages.
- `Core/Convert/PNGExporter.swift` — PDFKit page → NSImage → PNG via NSBitmapImageRep. DPI selector: 72/150/300.
- `Core/Convert/MarkdownExporter.swift` — Heuristic from extracted text. UI must show "Experimental" badge. Fallback to fenced code block if heuristics fail (10+ pages, no headings detected).
- `Core/PDFConverter.swift` — Public API like `PDFUnlocker`. Options: formats (Set<ConvertFormat>), pageRange (PageRange?), pngDPI (Int). Returns ConvertResult.
- Wire `ConvertViewModel.runAll()` to call `PDFConverter.convert()` per job.
- Enable Run All button in ContentView (currently disabled for Convert mode).
- Update ConvertJob.status transitions: .inspecting → .ready → .running → .succeeded / .partialSuccess / .failed.

**Out of scope:**
- OCR for scanned PDFs (deferred to v3).
- DOCX / HTML / RTF (deferred to v3).

**Test fixtures needed:** markdown-friendly PDF (headings + lists), scanned PDF without OCR (for the warning UI).

### M2.5 — Dictionary/wordlist recovery (~3 days)

**Goal:** User can opt in to a bounded wordlist attack on a password-protected PDF.

**Scope (per spec §4.3):**
- `Core/Recovery/WordlistLoader.swift` — Load `Resources/wordlists/common.txt` (50k entries) or user-supplied file.
- `Core/Recovery/PatternMutator.swift` — Capitalize, append year/digit/symbol.
- `Core/Recovery/WordlistRecovery.swift` — Run with hard caps (10k attempts / 60s default, 1M / 600s max). Progress callback. Cancellation.
- UnlockView row: "Try recovery" button next to password field. Recovery progress replaces password field.
- On match: show masked password with Reveal button. User must explicitly confirm before unlock proceeds (no silent unlocks).
- Settings entries: recoveryMaxAttempts, recoveryMaxSeconds, recoveryMutations.

**Critical:** never log candidate passwords. Log only counts, rates, timing, result category.

**Wordlist sourcing decision (open question per spec §15):**
- Option A: bundle a 50k-entry curated common-passwords list. App size +~500KB.
- Option B: no bundled list, user always supplies. Smaller app, more honest.
- Patrick hasn't decided. **Ask before bundling.** If A, source the list carefully (no leaked breach dumps; curate from publicly known common-password lists).

### M3 — Batch & polish (~2 days)

- Folder drag (top-level scan, optional subfolders, skip hidden, ignore symlinks).
- Redacted failure reports (Copy Report button per failed row).
- Retry-failed UI (already half-done — Retry button exists per row).
- Finder reveal (button exists, should work).
- Settings persistence review (UserDefaults keys are all there; verify they round-trip correctly).

### M4 — Release (~2 days)

- **App icon** — currently placeholder (Assets.xcassets/AppIcon.appiconset has Contents.json only).
- **Developer ID signing** — replace `CODE_SIGN_IDENTITY: "-"` with the user's actual Developer ID. Need to ask Patrick for the team ID and signing identity.
- **Notarization** — `xcrun notarytool submit ...`. Need Apple ID credentials.
- **DMG packaging** — `create-dmg` or a custom script.
- **Privacy statement** — both in-app and on download page. Required by spec §12.
- **Clean-machine QA** — test on a Mac that doesn't have Xcode dev certs.

**Estimate to v2.0 ship:** ~10 days focused work.

---

## 13. Things NOT to do (explicit guardrails)

These are mistakes that have already happened or are easy to make.

1. **Do not** route `.ownerOnly` PDFs through PDFKit's `doc.write(to:)`. It silently preserves restrictions. Always go to qpdf.
2. **Do not** set `useQPDFFallback: false` in `UnlockViewModel`. The `true` value is load-bearing — without it the GUI always uses the PDFKit path and produces restricted outputs.
3. **Do not** add an XCTest target to `project.yml`. The xcodegen quirk breaks builds. Use the standalone `swiftc` smoke test instead.
4. **Do not** add a `postBuildScripts` block to `project.yml` to auto-copy to `debug/`. We tried; it broke. Use `scripts/copy_to_debug.sh` after each build.
5. **Do not** delete the `libqpdf.30.dylib` alias. It's the name qpdf actually looks up at runtime. The versioned `libqpdf.30.3.2.dylib` is the actual content, but qpdf's hardcoded `LC_LOAD_DYLIB` reference is to the unversioned name.
6. **Do not** skip the `install_name_tool` step when re-bundling qpdf. If you ever upgrade qpdf (e.g., to 12.4.0), re-run: `install_name_tool -change @rpath/libqpdf.30.dylib @loader_path/libqpdf.30.dylib Resources/qpdf` and re-sign.
7. **Do not** log candidate passwords from recovery. Even at debug level. Use `Logger.error("Recovery attempt \(attempts)")` not `Logger.error("Tried \(candidate) — failed")`.
8. **Do not** change the file structure in a way that breaks `xcodegen`. The project is regenerated from `project.yml`, so any new file should be auto-picked-up. If you add a new top-level folder inside `PDFUnlock/`, xcodegen will see it. If you add files OUTSIDE `PDFUnlock/`, you need a new `sources:` entry.
9. **Do not** silently simplify scope. Patrick has explicitly said: "do not assume / do not silently simplify. Always confirm scope with him first." If you're tempted to cut a feature, ask first.
10. **Do not** introduce a `.xcconfig` file without telling Patrick. He prefers the project.yml-driven approach and the simpler the better.
11. **Do not** mark anything as "production-ready" or "release" until M4 is done and Developer ID signing + notarization are in place.
12. **Do not** make assumptions about the user's bundle ID or product name. The spec calls these out as open questions (spec §15). Ask.

---

## 14. External dependencies and why

| Dependency | Why | Version | License |
|---|---|---|---|
| **Xcode 26.5+** | Required for macOS 26 SDK and Swift 6.3. | 26.5 | Apple EULA |
| **Swift 6.0** | Required for `Observation` framework and strict concurrency. Toolchain comes with Xcode 26.5. | 6.0 | Apple |
| **xcodegen 2.45+** | Declarative Xcode project generation. Avoids hand-editing pbxproj. | 2.45.4 | MIT |
| **qpdf 12.3.2** | PDF encryption/removal engine. macOS 26 PDFKit is broken for owner-restricted and weak-encrypted PDFs; qpdf handles both correctly. | 12.3.2 | GPL-2.0-or-later |
| **poppler-utils** (NOT yet bundled) | For future M1.5 fallback in TXT/PNG extraction. Not in current build. | n/a | GPL-2.0 |

**Why poppler when PDFKit has the same features?** PDFKit returns empty/garbled text for some PDFs (especially scanned, forms-heavy, or non-standard encodings). `pdftotext -layout` and `pdftoppm` give reliable fallback. Only needed in M1.5.

**Why GPL qpdf + GPL poppler in a non-GPL app?** Because we use `Process()` to invoke them as separate programs, the GPL on the libraries doesn't reach our code. The GPL's "convey" / "propagate" clauses apply to derivative works / linked code, not to orchestrating a separate process. If we ever statically linked qpdf or poppler, we'd need to re-evaluate.

**What we DON'T depend on:**
- No Swift Package Manager dependencies (none yet).
- No CocoaPods / Carthage.
- No third-party Swift libraries.
- No analytics SDKs (privacy: local-only).

---

## 15. Communication style when working with Patrick

- **Be direct.** "I did X. It worked / didn't work. Here's what I'm doing next."
- **Lead with the conclusion.** If you're answering a question, give the answer first, evidence after.
- **Don't pad.** Match his brevity. If you can say it in one sentence, do.
- **Honest about uncertainty.** "I'm leaning towards X because Y. Can you confirm?" is better than "I'll do X" when you're guessing.
- **Show your work on non-obvious decisions.** If you make a design choice (e.g., "I routed owner-only to qpdf instead of fallback-on-failure"), explain why in a code comment AND in the user-facing response.
- **When something fails, say so.** Don't bury a build failure under a wall of "good news" — he'd rather hear the bad news up front.
- **Use checklists for multi-step work.** He likes TodoWrite / task lists visible.
- **When in doubt, ask.** His profile says: "explicitly wants me to ask in detail before cutting features or making scope decisions."

---

## 16. Files of interest (quick navigation)

If you need to find something fast:

| Looking for... | Look here |
|---|---|
| What does the app do? | `README.md` |
| What was the design intent? | `spec-v2.md` |
| What's the unlock pipeline? | `PDFUnlock/Core/PDFUnlocker.swift` |
| What's in the UI? | `PDFUnlock/Features/Unlock/UnlockView.swift`, `Convert/ConvertView.swift` |
| How does the queue work? | `PDFUnlock/Features/Unlock/UnlockViewModel.swift` |
| Why does qpdf get bundled? | `README.md` §"Key implementation notes" + `spec-v2.md` §4.3 |
| How to build? | `README.md` §"Build" |
| How to run smoke tests? | `README.md` §"Run the smoke tests" + §8 of this doc |
| Where's the qpdf binary? | `PDFUnlock/Resources/qpdf` (also bundled in built `.app`) |
| What user-facing errors exist? | `PDFUnlock/Core/UnlockError.swift` |
| Settings storage keys | `PDFUnlock/Settings/AppSettings.swift` §Key enum |

---

## 17. End-of-session checklist

Before you stop working on this project (for handoff, break, or end of context window):

- [ ] All changes are saved and the project builds clean (`xcodebuild ... build` succeeds with no warnings).
- [ ] Smoke tests pass (`./smoke-test` → `Passed: 11 / Failed: 0`).
- [ ] `debug/PDFUnlock.app` is refreshed to match the current source (`./scripts/copy_to_debug.sh`).
- [ ] Any new files are added to the appropriate section of `README.md` (project layout) and `spec-v2.md` (if architectural).
- [ ] If you introduced a new bug fix, document it in §11 of this handoff doc.
- [ ] If you added a new gotcha, document it in §9 of this handoff doc.
- [ ] If you completed a milestone, update the status table in `README.md` §"What's done".
- [ ] If you made a non-obvious design decision, add a comment in the relevant code AND consider adding it to §6 of this handoff doc.

The single most important handoff action: **update §11 ("Bugs already fixed")** with anything new. The next agent will read that section to know what NOT to touch.

---

## 18. Final note

If you're reading this fresh: welcome. The codebase is small (~24 Swift files, ~1500 LOC) and well-organized. The hard parts (PDFKit quirks, qpdf bundling, Swift 6 concurrency) have all been worked through. The remaining milestones (M1.5 Convert, M2.5 Recovery, M3 Polish, M4 Release) are mostly straightforward — they're feature work, not research.

The biggest risk is regressing the bugs we already fixed. **§11 is your friend.** Read it before changing anything that touches `PDFUnlocker.swift`, `UnlockViewModel.swift`, or `Resources/qpdf`.

Patrick is patient with iteration as long as you're transparent about progress and don't silently break things. When in doubt, ask. He's not going to be annoyed by a question; he will be annoyed by a hidden regression.
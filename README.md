# PDF Unlock

A native macOS utility for unlocking and converting PDF files — fully local, no upload, no analytics.

## What's done

| Milestone | Status | Notes |
|---|---|---|
| **M0** — Skeleton (SwiftUI shell, mode selector, drop zone, queue, settings) | ✅ Complete | See `PDFUnlock/App/`, `Features/`, `Models/`, `Settings/`. |
| **M1** — Core Unlock (PDFKit inspect/unlock, atomic write, verifier) | ✅ Complete | `PDFUnlock/Core/PDFUnlocker.swift`, `PDFUnlocker.swift`, etc. |
| **M2** — qpdf fallback (bundled binary, error mapping) | ✅ Complete | `PDFUnlock/Resources/qpdf`, `PDFUnlock/Core/QPDFRunner.swift`. |
| **M1.5** — Convert mode (TXT, PNG, Markdown) | ✅ Complete | `PDFConverter` + 3 extractors. UI: format picker (TXT/PNG/MD), DPI (72/150/300), page range input. PNG and TXT verified end-to-end. |
| **M2.5** — Dictionary/wordlist recovery | ⏳ Pending | Spec in `spec-v2.md` §4.3. Not started. |
| **M3** — Batch polish (folder input, redacted reports, retry) | ⏳ Pending | Single-file flow works; batch is partial (concurrency 2 in settings). |
| **M4** — Release (signing, notarization, DMG) | ⏳ Pending | App is **ad-hoc signed** for local dev; not Developer ID signed or notarized yet. |

**11/11 unlock smoke tests + 10/10 convert smoke tests passing** (21/21 total) against real PDFs (plain, owner-restricted, 40-bit, 128-bit AES, 256-bit AES, corrupt).

## Quick start

```bash
# 1. Open the project
open "PDFUnlock.xcodeproj"

# 2. In Xcode, ⌘B to build
# 3. The built .app is at DerivedData; copy it to debug/ for easy access:
./scripts/copy_to_debug.sh

# 4. Launch:
open "debug/PDFUnlock.app"
# or:
./scripts/copy_to_debug.sh --launch   # refresh + launch in one step
```

After any subsequent Xcode build, run `./scripts/copy_to_debug.sh` to refresh.

## Project layout

```
PDF Unlocker/
├── README.md                            ← this file
├── spec-v1.md                           ← original Codex spec (kept as reference)
├── spec-v2.md                           ← design spec (forward-looking)
├── project.yml                          ← xcodegen project config
├── PDFUnlock.xcodeproj                  ← Xcode project (regenerated from project.yml)
├── PDFUnlock/                           ← source root
│   ├── App/                             ← @main entry, menu commands
│   ├── Features/                        ← SwiftUI views
│   │   ├── Unlock/                      ← unlock queue, row UI, view model
│   │   ├── Convert/                     ← convert mode (UI shell only)
│   │   ├── DropZone/                    ← reusable drag-and-drop
│   │   ├── Settings/                    ← settings window
│   │   └── Common/                      ← mode selector, root content view
│   ├── Core/                            ← business logic (PDFUnlock, QPDFRunner, etc.)
│   ├── Models/                          ← @Observable models, status enums
│   ├── Settings/                        ← AppSettings (UserDefaults-backed)
│   └── Resources/
│       ├── Assets.xcassets/             ← app icon placeholder
│       ├── qpdf                         ← bundled qpdf 12.3.2 (arm64)
│       ├── libqpdf.30.dylib             ← unversioned (qpdf looks for this)
│       ├── libqpdf.30.3.2.dylib         ← versioned
│       └── qpdf.LICENSE                 ← GPL-2.0-or-later notice
├── debug/
│   └── PDFUnlock.app                    ← built .app, refreshed by copy_to_debug.sh
├── scripts/
│   └── copy_to_debug.sh                 ← refresh debug/ after Xcode build
├── test-fixtures/                       ← PDFs used by smoke tests
│   ├── plain.pdf
│   ├── owner-restricted.pdf             ← 40-bit (PDFKit rejects → qpdf)
│   ├── owner-restricted-128.pdf         ← 128-bit AES (PDFKit OK → qpdf for full strip)
│   ├── user-password.pdf                ← 256-bit AES
│   └── weak-40bit.pdf                   ← 40-bit user-password (PDFKit rejects → qpdf)
├── SmokeTest.swift                      ← standalone smoke test (no XCTest target)
├── OneShotUnlock.swift                  ← CLI: unlock a single file via argv
├── VerboseUnlock.swift                  ← CLI: unlock + detailed verification
├── smoke-test                           ← compiled smoke test binary
├── oneshot-unlock                       ← compiled one-shot binary
└── verbose-unlock                       ← compiled verbose binary
```

## Build

```bash
# Generate Xcode project from project.yml
xcodegen generate

# Build via xcodebuild
xcodebuild -project PDFUnlock.xcodeproj \
           -scheme PDFUnlock \
           -configuration Debug \
           -destination 'platform=macOS' \
           build

# Or in Xcode: open PDFUnlock.xcodeproj, ⌘B, ⌘R
```

## Run the smoke tests

```bash
# Compile + run the unlock smoke test (no Xcode test target — see notes below)
swiftc -parse-as-library \
       -framework PDFKit -framework AppKit \
       -o smoke-test \
       SmokeTest.swift \
       PDFUnlock/Core/*.swift \
       PDFUnlock/Core/Convert/*.swift \
       PDFUnlock/Models/PDFInspection.swift \
       PDFUnlock/Models/AppMode.swift \
       PDFUnlock/Models/ConvertFormat.swift \
       PDFUnlock/Models/ConvertJob.swift \
       PDFUnlock/Settings/AppSettings.swift
./smoke-test

# Compile + run the convert smoke test
swiftc -parse-as-library \
       -framework PDFKit -framework AppKit \
       -o convert-smoke-test \
       ConvertSmokeTest.swift \
       PDFUnlock/Core/*.swift \
       PDFUnlock/Core/Convert/*.swift \
       PDFUnlock/Models/PDFInspection.swift \
       PDFUnlock/Models/AppMode.swift \
       PDFUnlock/Models/ConvertFormat.swift \
       PDFUnlock/Models/ConvertJob.swift \
       PDFUnlock/Settings/AppSettings.swift
./convert-smoke-test
```

Expected output:
- `./smoke-test` → `Passed: 11 / Failed: 0`
- `./convert-smoke-test` → `Passed: 10 / Failed: 0`

### Why no Xcode test target?

`xcodegen` has a known quirk where `bundle.unit-test` targets that depend on an `application` target produce duplicate swiftmodule build errors (`Multiple commands produce '.../PDFUnlock.swiftmodule/...'`). Workarounds exist but aren't worth the complexity for a single-developer project. The standalone `swiftc` smoke test is faster to run and easier to maintain.

## Key implementation notes

### Why qpdf is bundled as a fallback

macOS 26 PDFKit silently preserves owner-restriction flags when re-saving a PDF. So `PDFDocument.write(to:)` succeeds, but the output is still flagged `print=none` — useless to the user. `qpdf --decrypt` strips both encryption and flags in one pass.

The unlock flow:
1. Inspect with `PDFInspector` (PDFKit-backed).
2. If `.ownerOnly` → straight to `qpdf --decrypt` (PDFKit path is known to be useless).
3. Otherwise → try PDFKit first; on `.corruptPDF` / `.unsupportedEncryption` / `.verificationFailed`, fall back to `qpdf`.
4. `.wrongPassword` / `.missingPassword` skip fallback (user input, qpdf can't help).

### Why the bundled qpdf needs an unversioned dylib alias

Homebrew's qpdf is a Mach-O executable that links `@rpath/libqpdf.30.dylib`. When copied to `Resources/qpdf`, that rpath doesn't resolve. Three steps fix it:

1. Copy both `libqpdf.30.3.2.dylib` (versioned) and `libqpdf.30.dylib` (unversioned) — the unversioned one is what qpdf looks up.
2. `install_name_tool -change @rpath/libqpdf.30.dylib @loader_path/libqpdf.30.dylib Resources/qpdf` — embeds a direct lookup in the executable's own directory.
3. `codesign --force --sign -` both files — the rpath change invalidates the signature.

For distribution, replace the ad-hoc `-` sign with a Developer ID identity.

### Why `UnlockViewModel` sets `useQPDFFallback: true`

The default in `PDFUnlocker.Options` is `true`. The view model explicitly opts in (rather than relying on the default) so the intent is visible in code review. If you ever want a "PDFKit-only" mode for testing, change this one line.

## Known limitations

1. **Recovery (forgotten passwords) is not implemented.** The spec is in `spec-v2.md` §4.3; code is not started.
2. **Poppler fallback for convert is not bundled.** PDFKit handles most PDFs but returns empty for scanned PDFs without an OCR layer, and heuristic Markdown degrades on complex layouts. Bundling `pdftotext` and `pdftoppm` would give more reliable fallbacks — deferred to a future pass.
3. **Markdown conversion is best-effort.** PDFKit loses structure info (font sizes, exact positions, columns). The heuristic in `MarkdownExporter` upgrades short/title-cased lines to headings and recognizes `-` / `*` / `digit.` list markers, but tables, multi-column layouts, and footnotes degrade. For high-fidelity text use TXT; for layout-faithful output, use a layout-aware tool. The converter falls back to a fenced code block of raw text if no structure is detected on a 10+ page doc.
4. **Bundle ID is a placeholder** (`com.MiniMax.PDFUnlock`). Change it before distribution.
5. **App is ad-hoc signed**, not Developer ID. macOS Gatekeeper will warn on first launch of the debug/ copy.
6. **arm64 only.** No Intel build. Edit `project.yml` to add an `x86_64` slice if needed.
7. **English only.** Localization not implemented.

## Debug folder convention

The `debug/` folder is a stable, predictable location for the latest built `.app`. It's not used by Xcode's build pipeline — it's manually refreshed via `scripts/copy_to_debug.sh` after each build. Reasons:

- Xcode's default output lives at `~/Library/Developer/Xcode/DerivedData/...`, which is a long path that changes between machines and Xcode cleanups.
- A `xcodegen` `postBuildScripts` block was tried first but had path-resolution issues with `$EXECUTABLE_FOLDER_PATH` and Xcode's parallel build phases; the standalone script is more reliable.

To refresh after every build, you can add this to your shell config or as a build phase later. For now, run `./scripts/copy_to_debug.sh` manually.

## Roadmap (next)

1. **M2.5 — Recovery** (~3 days). Bundled common-passwords wordlist, custom wordlist picker, opt-in per file, masked confirmation, hard caps.
2. **M3 — Batch polish** (~2 days). Folder drag, redacted failure reports, retry-failed UI, per-job format overrides.
3. **M4 — Release** (~2 days). Developer ID signing, notarization, DMG packaging.

Total estimate to v2.0 ship: ~7 days focused work.

## License

App code: TBD (you haven't picked one yet — recommend MIT or Apache 2.0 for permissive, or GPLv3 if you want copyleft).

Bundled `qpdf`: GPL-2.0-or-later (see `PDFUnlock/Resources/qpdf.LICENSE`). The GPL on qpdf does **not** impose GPL on the host app — it's a separate program invoked via `Process()`, not statically linked. If you ever switch to in-process qpdf (static libqpdf.a or Swift wrapper), that re-opens the licensing question.
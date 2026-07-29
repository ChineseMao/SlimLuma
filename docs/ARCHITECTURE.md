# SlimLuma architecture

## Product boundary

SlimLuma is a local-first macOS batch compression workbench. It owns file
selection, settings, scheduling, safety checks, output naming and history.
Mature external engines own the compression algorithms.

The first complete journey is:

1. Add files or recursively scan folders.
2. Detect image, video and PDF inputs.
3. Apply a built-in or custom preset.
4. Run up to six isolated engine processes.
5. Re-open every generated file and compare it with the input.
6. Keep a new output only after validation and only when it is smaller, unless
   the user opts into larger results.
7. Store a local history entry and reveal the result in Finder.

## Modules

`SlimLumaKit` has no UI state. Its boundaries are:

- `Models`: value types for requests, presets and results.
- `ToolRegistry`: deterministic discovery of Homebrew, MacPorts, system and
  future app-bundled engines.
- `CommandBuilders`: pure translation from typed settings to process
  arguments. No shell command interpolation is used.
- `ProcessRunner`: asynchronous process lifecycle, bounded output capture and
  cancellation.
- `CompressionCoordinator`: engine selection, temporary output, validation and
  final move.

`SlimLuma` owns:

- SwiftUI navigation and adaptive macOS controls.
- queue state and bounded task-group scheduling;
- settings and custom presets in `UserDefaults`;
- up to 500 history entries in Application Support.

## Engine selection

- Images: ImageMagick first; macOS `sips` is a limited fallback.
- Video: FFmpeg. VideoToolbox can be selected for fast H.264/HEVC encoding.
- PDF: lossless mode prefers qpdf. Balanced, custom and compact modes prefer
  Ghostscript because image-heavy documents need actual image downsampling.
  Automatic mode falls back to qpdf and then a safe PDFKit rewrite, with an
  explicit capability warning when only a limited fallback is available.

Engine installation is an explicit user action. The app invokes an already
installed Homebrew executable directly with formula arguments, never through a
shell, then re-runs discovery and keeps a bounded local installation log.

The adapters are intentionally replaceable. Bundled or XPC-isolated engines can
be added later without changing request models or the UI.

## Safety invariants

- Original inputs are read-only.
- Engine arguments are passed directly to `Process`; no shell evaluates paths.
- Engine output is written inside an app-owned `0700` temporary workspace.
  Each active workspace holds a file lock so stale cleanup cannot remove a
  long-running job.
- Images, videos and PDFs are reopened with ImageIO, AVFoundation or PDFKit.
- Animated image frame counts are compared before finalization.
- Video duration and audio/video/subtitle track counts are compared before
  finalization.
- PDF page count, outlines, annotations, form/signature fields, encryption,
  extractable text and requested linearization are compared before finalization.
- Only an accepted output is copied into a locked `0700` staging directory on
  the destination volume. SlimLuma synchronizes the marker, directory entry,
  and payload; rechecks size and inode identity; then performs an exclusive
  atomic rename to the final unique path.
- Existing output names are never overwritten.
- Failed and cancelled jobs remove their private workspace and owned
  destination staging directory. Later jobs reclaim only stale directories
  with SlimLuma's marker magic and an acquirable lock.

## Automation and desktop integration

- Clipboard imports are copied into an app-owned Application Support batch.
- Folder watches wait for stable file snapshots and ignore SlimLuma outputs.
- Finder Services and Open With events converge on the same deduplicated queue.
- A macOS 15+ App Intent accepts files from Shortcuts and uses that same router.
- Quick Look provides source/output comparison without uploading content.

## Known boundaries

- Progress is per-file rather than codec-level percentage.
- Signed PDFs are rejected before finalization because rewriting invalidates the
  existing signature.
- Target-size iteration and audio-specific flows remain future surfaces.

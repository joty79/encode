# Media Info inspector

Read-only stream/container facts and optional bounded packet timing diagnostics.
Requires PowerShell 7 and `ffprobe` on PATH. The existing Media Tools > MediaInfo
Explorer command already uses `pwsh`; no menu registration update is needed.
Terminal presentation uses the installed canonical `.agent-shared/templates/PS_UI_Blueprint.psm1`
for input, resize, synchronized redraw and host restoration. It does not change
persistent terminal settings. The header uses an emoji when Unicode is enabled;
`POWERSHELL_TUI_ASCII=1` selects the shared text fallback.

## Use

```powershell
pwsh -NoExit -NoProfile -ExecutionPolicy Bypass -File "D:\Users\joty79\scripts\encode\Video\inspector\inspect.ps1" "E:\Beautiful_Girl_on_the_Beach.mp4"
```

The default probe reads stream/container metadata. Folder inputs retain recursive
metadata inspection; a failed file is reported and remaining files continue.
Explicit file inputs can also report audio-only media. All video, audio,
subtitle, data and attachment streams are retained, rather than just first tracks.

The initial **Overview** is a quick everyday media summary: container, duration,
size, video codec/profile, resolution, FPS, bit depth, scan and bitrate; audio
codec, channels, sample rate, bitrate and language; embedded subtitle tracks.
Video, audio and subtitle sections have distinct accents. Missing audio/subtitles
are explicit. There are no Smart Cut verdicts or diagnostic checklists here.
Exact rates, clocks, colour fields and probe internals remain in details/exports.
Interactive mode redraws one screen; it does not append a fresh report
after each action. The shared renderer restores the previous terminal on exit.

| Key (no Enter required) | Action |
| --- | --- |
| **1–6**, **Left/Right**, **Tab** | Overview, Video, Timing, Tracks, File, Smart Cut |
| **V**, **S** | Video details / Overview aliases |
| **A** | Optional Smart Cut format hints |
| **Up/Down**, **PgUp/PgDn**, **Home/End** | Scroll within the current page; header/controls stay visible |
| **F** | File chooser; arrows + Enter open a file, Esc cancels |
| **[ / ]** | Previous/next video stream for Video/Timing and packet samples |
| **D** | Optional timing sample; enter the start timestamp; open Timing results |
| **C** | Copy the current page (the everyday summary from Overview) |
| **R** | Copy the complete technical report for development/troubleshooting |
| **J**, **T** | Export complete JSON/text to a new filename |
| **Esc** | Cancel a dialog; return from details to overview; exit from overview |
| **Q** | Exit the inspector |

Letter shortcuts work with English or Greek keyboard layout (for example D/δ).
Text-entry dialogs preserve the actual typed characters, including Greek filenames.
Enter is used only to submit text or select a file from the chooser. Export refuses
existing files. Esc also cancels a running probe; failed/cancelled probes remain in
report failures. Detailed pages group fields by subject. Raw arguments, tool
provenance and complete analysis boundaries remain in the full report, accessible
with R or JSON/text export. Timing sampling never replaces the casual overview.

## Plain-language Smart Cut explanations

The versioned checks describe **custom-2026-09-26.1 H.264 Main/High reordered
repair and HEVC Main/Main 10 repair**. They do not detect the installed build or
declare general Avidemux import, playback, ordinary Copy or other repair paths
unsupported. Other codecs are explicitly unassessed; Avidemux has additional paths.

- **A repair limitation was found:** reported format conflicts with a checked
  repair requirement, such as H.264 10-bit, interlacing, HDR, non-square pixels,
  side data, multiple video tracks or the required MP4/MKV source extension.
- **Needs a closer look:** missing metadata, differing rates, probe diagnostics
  or measured timestamp anomalies need investigation. This is not a rejection.
- **No common format restriction found:** no checked restriction was found;
  the file and selected cuts have **not** been approved.

Page **6 Smart Cut** is optional and shows format hints and their reasons.
It has one concise scope note; the full report owns detailed limitations/evidence.
The inspector does not load a project, parse true IDR/reference dependencies,
inspect parameter changes throughout the stream, or verify audio/export sync.
Timing findings apply only to actual sampled coverage. A malformed excluded area
may not affect a selection; Avidemux must inspect its whole dependency windows.
No conversion or repair runs automatically.

The rule source is the custom Avidemux `Q_smartCutReordered.h`,
`Q_smartCutHevc.h`, `docs/smart-cut-reordered.md` and `docs/smart-cut-hevc.md`,
reviewed on 2026-09-26. Update the versioned explanations when those gates change.

Automation uses streaming output with `-NonInteractive` **after the script path**:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "D:\Users\joty79\scripts\encode\Video\inspector\inspect.ps1" "E:\Beautiful_Girl_on_the_Beach.mp4" -NonInteractive -Deep -StartSeconds 0 -MaxPackets 5000 -TimeoutSeconds 30 -JsonPath "$env:TEMP\beach-report.json" -TextPath "$env:TEMP\beach-report.txt"
```

| Option | Default | Meaning |
| --- | --- | --- |
| `-Paths` | required | Literal file/folder paths; positional paths remain supported |
| `-Deep` | off | Explicit packet sample; requires exactly one file, never a folder |
| `-StartSeconds` | 0 | Requested source timestamp in seconds; seek may land earlier |
| `-StreamIndex` | first non-cover video | Absolute stream index for `-Deep` |
| `-MaxPackets` | 5000 | Per sample cap, 10–20000 packets |
| `-TimeoutSeconds` | 30 | Per ffprobe process wall-time limit, 1–120 seconds; version query has 10 seconds |
| `-JsonPath`, `-TextPath` | none | New UTF-8 output files; never overwrite existing content |
| `-NonInteractive` | off | No action prompt; also automatic for redirected console input |

Metadata parsing may inspect initial packets to identify streams, but there is no
whole-file frame count, decode or packet scan by default. The sample uses
`-read_intervals START%+#COUNT -show_packets` on one selected video stream.
Progress reports elapsed time and the time limit. Timeout/cancellation kills the
child process and discards partial probe output. There is no duration-based sample
promise: low-frame-rate media can cover more source time within the same packet cap.

## Interpretation and report schema (version 1)

- `tool`: resolved ffprobe executable/version and PowerShell version;
  `inspectorVersion`, `generatedUtc`, `scope`, `interpretation` identify this report.
- `files[]`: full path, byte size, modification time (identity hints, not a content
  hash); `provenance` includes ffprobe argument array, exit status and stderr.
- `format`: container/brands, start/duration, reported aggregate bitrate and a
  separately labelled size/duration estimate. Neither is substituted for video bitrate.
- `streams[]`: exact ffprobe field names and null for unreported values; all tracks,
  codec/tag, profile/raw codec-specific level, dimensions/SAR/DAR, pixel format,
  scan, color range/primaries/transfer/matrix, reported side data/HDR, timestamps,
  duration/frame count, B-frame hint, audio parameters, language/disposition.
  `nominalFps` / `averageFps` retain `raw` rationals plus numerator, denominator,
  readable decimal and status. Narrow chroma/bit-depth derivation from standard
  planar YUV names is labelled; unknown formats stay unknown.
- `samples[]`: requested interval, packet/time limits, absolute stream index,
  actual measurement timestamp, argument array, exit status/stderr, elapsed time
  and `measured` results. PTS ticks remain exact strings in coverage/examples;
  scaled seconds are derived from `time_base`. Includes actual PTS coverage,
  interval statistics/common deltas, missing/duplicate/tiny PTS, nominal deviations,
  DTS order, key-flag spacing, first/last tiny-interval extent, and up to 20 examples.
  Text shows only five examples. No default raw packet dump.
- `diagnosis`: additive schema-1 field in JSON exports with rule version, scope,
  status, findings (reason, next step and evidence) and explicit unchecked areas.
  It is refreshed at export so new samples are included. Complete text/clipboard
  reports contain the same explanations before the raw diagnostic sections.
- `failures[]`: path/stage/error; one or more failures produce a nonzero process
  exit with `pwsh -File`. `-NoExit` intentionally leaves the interactive shell open.

CFR/VFR remains **Not analyzed** in the metadata section: equal or different FPS
rationals do not prove timestamp cadence. Unknown field order is not progressive
or interlaced. `nb_frames` is reported, not independently counted. Compression
density and the legacy personal bitrate policy only use reported video bitrate;
they are subjective heuristics, not image-quality or compatibility evidence.

Samples sort integer packet PTS into presentation order before comparing deltas;
backwards PTS in packet order can be normal B-frame reordering. The diagnostic
nominal-deviation tolerance is `max(1.01 time-base ticks, 1% nominal interval)`;
tiny positive intervals are below 1% nominal. These are descriptive thresholds,
**not Avidemux support gates**. With missing nominal FPS, related metrics are null.
Partial reorder groups at sample edges can create apparent gaps. Empty/one-PTS
samples explicitly provide insufficient timing evidence. Packets need not map
one-to-one to decoded frames, and K flags do not prove IDR, closed GOP, recovery
points or safe cuts. Frame-level HDR, dependency windows, full-file CFR/integrity
and Avidemux eligibility remain unestablished.

Generic facts/report schema belong here. Authoritative import, preview, Copy and
Smart Cut decisions belong to the actual Avidemux build and selected ranges.
This tool does not open project scripts, modify timestamps/media, or change gates.

## Verification

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "D:\Users\joty79\scripts\encode\tests\Test-MediaInspector.ps1"
```

The suite creates its own temporary fixtures and retains reports/logs at the
printed path: CFR with B-frames, irregular PTS, no audio, two audio tracks plus
subtitle, Unicode/spaces/brackets/ampersand/apostrophe paths, missing fields and
invalid rationals, mixed-folder errors, invalid stream, export collision/source
preservation and process timeout. Requires the existing FFmpeg with libx264.

`tests/Test-MediaInspectorUi.ps1` exercises direct-key navigation and generates ANSI
frames for all six pages at narrow/wide viewport sizes. Replay its printed manifest
with `tests/Test-InspectorUiReplay.py MANIFEST.json [PREVIEW.png]` using Python with
the canonical TUI suite's cached `pyte`/`wcwidth` wheels on `PYTHONPATH`; Pillow is
needed only for optional preview output. The replay keeps one live virtual screen
through resize/page transitions and rejects wrapping, scrolling, duplicate headers
and stale frames. This complements interactive PowerShell checks; it is not a
pixel-perfect Windows Terminal font/emoji screenshot.

Version 2.0 (2026-09-26): replaces guessed CFR/scan/bitrate indications, reports all
streams, adds exact FPS/time metadata, evidence-based packet samples and in-program
copy/export. Main repository docs/changelog are being edited by another task;
this inspector-local document owns the feature description for this change.

Version 2.1 (2026-09-26): separates the human-facing terminal overview from the
complete diagnostic report, adds Details/Overview actions, aligned responsive
fields, readable units, visual hierarchy and distinct timing status colors.
JSON schema and copied/exported information remain unchanged.

Version 2.2 (2026-09-26): persistent screen with immediate action keys, six designed
detail tabs, internal scrolling, file/stream navigation and contextual dialogs.
Uses the canonical shared renderer rather than growing the terminal scrollback.

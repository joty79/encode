# Video Tool Inventory

## Purpose

This is the operational map for the `Video` folder. Start with the dated snapshot below to distinguish script behavior, current menu registration, and unfinished acceptance work. Older runtime evidence is preserved afterwards; it does not prove the current Explorer layout or launcher behavior.

## Repair workflow update — 2026-09-05

Start with [Repair-Video.md](Repair-Video.md) for a symptom-to-script guide,
interactive usage, supported repair routes, current menu placement and playback
limitations. `Repair-Video.ps1` is a new **terminal-only experimental router**:
it distinguishes malformed AAC headers from a proven displaced-data/duplicate-index
H.264 case before choosing a repair. Unknown corruption and timeline gaps remain
manual review. It uses `Repair-DamagedVideo.ps1` as the bounded-cut backend.

Both real `E:\1.mp4` / `E:\2.mp4` samples passed the router's output probe,
full decode and timeline gates. Eighteen router and 44 backend assertions passed
in PowerShell 7 and 5.1. These are automated checks; Avidemux import/playback
was not verified because Computer Use was stopped. Ask before future GUI control.

`Recover-IncompleteMp4` is already in the organized `.mp4` cascade; “incomplete”
describes its supported input, not an empty implementation. `Detect-BadCuts`
has terminal progress, not live video playback, and its 80 ms alignment tolerance
is not a frame-exact editing guarantee. `Repair-DamagedVideo` remains a prototype,
now also preserving source video timescale/audio rate/channels across patches.

The fresh read-only menu audit still matches the `.mp4` Media Tools tree but
reports 3 missing/mismatched folder roots, 9 legacy live roots and 18 catalog
hive-policy mismatches. No menu installation or new verbs were applied.

## Current Snapshot — 2026-09-03

Audited checkout: `D:\Users\joty79\scripts\encode`, commit `f4d3ee1`.
The file-menu integration now uses the generated **Media Tools** cascade from
`config\MediaTools-Menu.json` and `Video\Media-Tools.reg`. Most companion `.reg`
files have become comment-only retirement notices. Their presence does not mean
there is still a separate direct menu to install.

The read-only live audit found all **32 file-extension cascade roots matching
their complete expected Registry trees**. The selected-folder and folder-background
production roots are missing; older folder/desktop entries remain installed.
This explains why file and folder menus do not consistently reflect the same
generation of the project. Current Explorer rendering/click behavior was not
retested in this audit.

### What each Video tool is for

In this table, **registered** means current Registry evidence, not a fresh
Explorer click test. Historical tests remain historical unless explicitly dated
as today's checks below.

| Script | Use | Current access | Evidence / remaining work |
| --- | --- | --- | --- |
| `video_encode.ps1` | H.264 encoding, including the established interlaced-video path | File cascade registered; intended folder cascade missing | Historical real encode evidence; automatic NVENC/x264 changes are in the September 2 commit and were not rerun in this audit |
| `add_to_queue.ps1` | Add videos for later encoding | File cascade registered; intended folder cascade missing | Historical silent-launch and queue evidence; current Explorer launcher acceptance remains |
| `run_queue.ps1` | Process queued videos | Intended folder-background cascade missing; older queue menu remains | Historical success/failure-retention evidence; align and test current menu entry |
| `inspector\inspect.ps1` | Read metadata and report media characteristics | `MediaInfo` file action registered; intended folder cascade missing | Historical runtime evidence; metadata inspection is not a packet/full-decode integrity check |
| `RemuxToMP4.ps1` | Convert an MKV container to MP4 with supported streams | `.mkv` cascade registered | Historical real remux and source/collision safety tests; not a generic corrupt-payload repair |
| `Merge-MP4-SRT.ps1` | Merge video and matching subtitles into MKV | `.mp4` cascade registered | Historical real stream/output and safety tests |
| `convert_webp_smart.ps1` | Convert supported static/animated images | Image cascades registered; intended folder cascade missing | Historical real conversion, timing, and safety tests |
| `Repair-TsTimestampRemux.ps1` | Analyze TS timestamps or remux TS without re-encoding | `.ts` cascade registered; old folder entries remain | Historical synthetic repair tests and real clean-TS analysis; representative broken-TS acceptance still pending |
| `join-wmv-smart.ps1` | Join related WMV files using ASFBin | `.wmv` cascade registered | Historical synthetic join passed; irregular real WMV remains the decisive test |
| `Recover-IncompleteMp4.ps1` | Recover a specific truncated Microsoft H.264 recording without its final MP4 index | `.mp4` cascade registered | Historical real recovery evidence; narrow format/layout scope, audio and launcher limits documented in `Incomplete-MP4-Recovery.md` |
| `Verify-VideoIntegrity.ps1` | Packet/container corruption and timeline-gap scan | Terminal-only; absent from menu manifest | 14 assertions pass in both shells; main repaired/cut return timeline-review exit `3`; does not decode every frame or establish lip-sync |
| `Detect-BadCuts.ps1` | Check proposed cut alignment, or perform full decode diagnostics | Terminal-only; absent from menu manifest | Passed today's 13 regression assertions; scene changes alone are not proof of damage |
| `Repair-Mp4DisguisedTs.ps1` | Remux a file named `.mp4` whose actual container is MPEG-TS | Terminal-only; absent from menu manifest | Historical 25 real assertions in both shells; rejects an ordinary MP4 container |
| `Repair-DamagedVideo.ps1` | Detect bad H.264 packet ranges, drop damaged ranges, flag remaining timeline issues | Prototype, terminal-only | 44 assertions pass in both shells. Real output passes full decode/payload checks, but user confirms freezes/desync; new timeline scan flags them. Pre-hardening comparison remains; see `Damaged-Video-Repair.md` |

### Checks performed today

- `tools\Test-EncodeEnvironment.ps1`: `READY`, exit `0`. This checks dependency
  availability and FFmpeg response, not a fresh QTGMC/NVENC encode.
- `tests\Test-VerifyVideoIntegrityReal.ps1`: initially 6 assertions; after timeline diagnostics, 14 passed in both shells.
- `tests\Test-DetectBadCutsReal.ps1`: 13 assertions passed, exit `0`.
- `tests\Test-RepairDamagedVideoPrototype.ps1`: initial 30 assertions passed;
  after the real-file repair fixes, 40 passed; after timeline diagnostics, 44 passed in both PowerShell 7 and 5.1.
- The cut-diagnostic suite ran in PowerShell 7 only in this audit.
- `Verify-VideoIntegrity.ps1` on
  `D:\Users\joty79\Desktop\test fix\1.mp4`: 30,838 corruption diagnostic messages
  (`Invalid NAL unit size` / `missing picture`), exit `2`, 2.29 seconds.
  The count is messages, not distinct damaged frames. Metadata-only ffprobe
  returned exit `0`. The source was not modified. A subsequent authorized repair
  produced `1_smart_repaired.mp4`, duration 01:13:28.595533, with clean full decode
  and identical retained compressed payloads; details are in `Damaged-Video-Repair.md`.

### Menu audit findings

`tools\Test-EncodeContextMenus.ps1` scanned 22 `.reg` files and compared 35
expected logical roots with 41 live roots. Its ordinary exit `0` means the audit
ran; it does not mean the findings are clean. Use the findings or `-Strict` when
an automated gate is needed.

- **3 missing definitions / 3 tree mismatches:** production
  `Directory\shell\MediaTools`, production
  `Directory\Background\shell\MediaTools`, and the remaining direct
  `audio\run_audio_queue.reg` definition for `RunAudioQueue`.
- **9 live roots without a current `.reg` owner:** older folder/background TS
  and no-audio verbs plus folder/desktop preview roots. This is evidence of
  deployment drift, not authorization to delete them.
- **18 catalog hive-policy mismatches:** the catalog still declares a hive
  policy for retired comment-only `.reg` artifacts, which now contain no keys.
- **1 ambiguous HKCR definition:** the remaining direct audio queue artifact.
- No broken referenced repository targets, duplicate source roots, uncataloged
  artifacts, or catalog definition-count mismatches were found.

For fresh detailed JSON/Markdown evidence, run the auditor with
`-OutputDirectory` pointing to a chosen report directory. No Registry changes
were made during this audit. Earlier claims below or in older acceptance docs
that all definitions are installed are historical and are superseded by this
snapshot for the current checkout/machine.

## Historical Installed and Verified Menus — August 2026

The following legacy Registry groups were manually imported and runtime-verified on 2026-08-25. They are not yet managed by an installer or uninstaller.

| Workflow | Code and integration | Current evidence |
| --- | --- | --- |
| Direct H.264 encode | `video_encode.ps1`, `video_encode.reg`, `Avidemux-Profiles\` | Auto-probes functional NVENC and otherwise uses x264 CRF 19/fast; real BFF MPEG-2 through QTGMC/NVENC and synthetic progressive x264 H.264/AAC outputs passed full decode; reusable Avidemux x264/NVENC profiles also passed real encodes |
| Add to video queue | `add_to_queue.ps1`, `silent_runner.vbs`, `add_to_queue.reg` | Real silent `wscript` launch queued a temporary sample |
| Run video queue | `run_queue.ps1`, `run_queue.reg` | Successful QTGMC batch cleared the entry; invalid media returned nonzero and remained queued |
| Media metadata Inspector | `inspector\inspect.ps1`, `inspector\inspect.reg`, `inspector\lib\Metrics.ps1`, `Policy.ps1`, `render.ps1` | Valid MPG and TS rendering; invalid input returns nonzero; mixed folder continues after failure; `.ts` menu added |
| Remux MKV to MP4 | `RemuxToMP4.ps1`, `RemuxToMP4.reg` | Real AAC stream-copy and PCM-to-AAC tests; source preserved; existing output unchanged; invalid input leaves no partial MP4 |
| Merge matching MP4 + SRT | `Merge-MP4-SRT.ps1`, `Merge-MP4-SRT.reg` | Real video+subtitle MKV validation; sources preserved; existing output unchanged; missing/invalid input leaves no partial MKV |
| Convert WebP/AVIF/HEIC/HEIF | `convert_webp_smart.ps1`, `convert_webp_smart.reg` | 25 real assertions in both shells under Limited policy; five Registry commands imported and read back; static/animated timing and output validation verified |
| TS timestamp analysis/remux | `Repair-TsTimestampRemux.ps1`, `.reg`, `lib\TsSourceCleanup.ps1` | Clean B-frame and deliberately broken-timeline TS classification; single/folder repair; source, collision, partial-output and unique-move safety; six Registry entries read back |
| Join related WMV files | `join-wmv-smart.ps1`, `join-wmv-smart.reg` | ASFBin remains the chosen backend. The menu is `.wmv`-only; collisions, missing ASFBin, exit failures and invalid output are guarded. A real ASFBin synthetic join produced WMV2/WMA2 ASF with clean full decode; an irregular user WMV remains the important real-world test. |

## Supported Terminal-Only Workflows

| Workflow | Artifact | Current evidence |
| --- | --- | --- |
| Repair `.mp4` filename containing MPEG-TS | `Repair-Mp4DisguisedTs.ps1` | 25 real assertions in both shells: normal MP4 no-op, disguised-TS repair, video/audio validation, custom output, source/collision preservation, and invalid/missing input cleanup |
| Fast packet/container integrity scan | `Verify-VideoIntegrity.ps1` | Real healthy H.264 MP4 returns success; deliberately corrupt NAL length returns nonzero even when FFmpeg itself exits zero; explicitly not a full decode |
| Copy-cut alignment / full decode diagnostic | `Detect-BadCuts.ps1` | 13 real mode assertions plus focused failures in both shells: aligned/misaligned/invalid cuts, healthy full decode, and corrupt NAL diagnostics; scene transitions are explicitly informational |

## Diagnostics and Prototypes — Do Not Install Yet

| Artifact | Classification | Reason |
| --- | --- | --- |
| `Repair-DamagedVideo.ps1` | Characterized prototype | The hardened version remains active and 30 synthetic safety assertions pass in both PowerShell hosts. Promotion requires a side-by-side real broken-video and visual comparison with the preserved pre-edit script from commit `5c202ba`; exact archive/tag references are recorded in `Damaged-Video-Repair.md`. |
| `Damaged-Video-Repair.md` | Prototype documentation | Owns the limits and evidence for the damaged-H.264 experiment |

## Support Files — Not Standalone Tools

| Artifact | Owner/use |
| --- | --- |
| `lib\TsSourceCleanup.ps1` | Shared source-deletion guard used by TS timestamp remux |
| `video_encode_changelog.md` | Historical video encoder notes |
| `Avidemux-Profiles\` | Reusable Avidemux 2.8.1 x264 CRF 19/fast and NVENC QP 22/P5-equivalent profiles |
| `CHANGELOG.md` | Historical queue notes |
| `Explorer-MultiSelectLimit.reg` | Per-user Explorer multi-selection limit (`MultipleInvokePromptMinimum=100`); applies to Windows 11 but is not a media command |
| `icons.code-workspace` | Editor workspace artifact; not an installable tool |

## Inert Inspector Scaffolding

These tracked files are currently zero bytes and are not loaded by `inspect.ps1`:

- `inspector\config\policy.psd1`
- `inspector\lib\Flags.ps1`
- `inspector\lib\Probe.ps1`
- `inspector\Readme.md`

They have been empty since the repository's initial commit, have no references, and
perform no runtime role. Preserve them as inert historical scaffolding for now;
populate or remove them only during the Inspector/context-menu redesign.

## Dependency Snapshot — 2026-08-25

| Dependency | Current state |
| --- | --- |
| PowerShell 7 / Windows Terminal | Available |
| FFmpeg / ffprobe 9.0 | Available on `PATH` |
| AviSynth+ 3.7.5 / QTGMC / FFMS2 | Restored and runtime-verified |
| ASFBin | v1.8.3.934 (2012) at `C:\Program Files\CutAssist\asfbin\asfbin.exe`; unsigned, not on `PATH`, license decision pending |
| MKVToolNix | v101.0 x64 installed at `C:\Program Files\MKVToolNix`; signed CLI tools verified; not on `PATH` |
| ImageMagick | v7.1.2-30 Q16-HDRI x64 installed and added to machine `PATH`; bundled Limited policy active and verified |

### MKVToolNix Recovery Evidence

- Official version: 101.0 x64, released 2026-08-24.
- Installer: `D:\Programs\Video\mkvtoolnix-64-bit-101.0-setup.exe`, 34,075,944 bytes.
- SHA-256: `2A170A71DA6D1AECAF513C88CA7DA38F8C9877790674C4DF667A7C28D52DD418`; matched the official `.sha256` file.
- Authenticode: `Valid`; signer `LINET Services GmbH`.
- Install path: `C:\Program Files\MKVToolNix`.
- Runtime: `mkvmerge v101.0 ('Time To Turn') 64-bit`, exit code `0`; `mkvmerge`, `mkvextract`, `mkvinfo`, and `mkvpropedit` files are present and signed.
- The user completed the interactive installer/legal choices. The older preserved v88 installer remains in `D:\Programs\Video` but was not used.
- `gMKVExtractGUI` is an optional manual GUI in `D:\Programs\Video`; no repository script references or requires it.

### WMV Join Review Evidence

- The Registry entry is installed only for `.wmv`; the former `HKEY_CLASSES_ROOT\*` registration is absent.
- The script no longer passes ASFBin `-y`, refuses an existing `_joined.wmv`, verifies ASFBin's exit code and output with ffprobe, and no longer shadows PowerShell's `$input`/`$args` automatic variables. Its filename auto-matching still requires human confirmation and remains a real-world watch point.
- Installed ASFBin reports v1.8.3.934, was built in 2012, is not Authenticode-signed, and its bundled documentation states that it is free for non-commercial use while the executable help says evaluation use. No terms were accepted or interpreted by the agent.
- A real ASFBin invocation joined two synthetic WMV2/WMA2 files into a 2.153-second ASF/WMV with both streams and a clean FFmpeg full decode. The sources were preserved and the temporary fixture was removed after verification.
- FFmpeg stream-copy remains only an optional ordinary-file alternative; it is not treated as equivalent to ASFBin for irregular or damaged ASF behavior.

### ImageMagick and Smart Image Conversion Evidence

- Official installer: `D:\Programs\Video\ImageMagick-7.1.2-30-Q16-HDRI-x64-dll.exe`, 24,180,688 bytes.
- SHA-256: `345B11696BCAD86DE188CE2FD94DCC1EEEACABC981BBE8752FA029B9B5F4A10D`.
- Authenticode: `Valid`; signer `ImageMagick Studio LLC`.
- Install path/runtime: `C:\Program Files\ImageMagick-7.1.2-Q16-HDRI\magick.exe`, v7.1.2-30; machine `PATH` contains the application directory.
- Delegate checks confirm WebP read/write, AVIF read/write, and HEIC/HEIF read support. The user completed the interactive installer/legal choices.
- The installed Open policy was backed up to `D:\Programs\Video\ImageMagick-policy-open-installed-7.1.2-30.xml`. The bundled official Limited policy is active; its SHA-256 exactly matches the bundled source (`A8F9E5D4E234EFE511732B6D771E4915A27522AC1AE1E6DD5F345763EAAD1E0C`). The script also enforces focused thread, memory, map, disk, and time limits.
- The rewritten workflow preserves static sources, refuses existing outputs, validates JPG/MP4 results, performs full decode validation for animation, and continues mixed-folder work while returning nonzero for any failure.
- A variable-delay two-frame WebP retained both frames and its 0.600-second timing when converted directly by FFmpeg instead of the legacy fixed-25-fps PNG extraction path.
- `tests\Test-ConvertSmartImageSafety.ps1` passes 25 real assertions under PowerShell 7 and Windows PowerShell 5.1, including after the Limited policy became active. All five reviewed Registry entries were imported and read back with valid icons, PowerShell 7 commands, and context-only pause behavior.

## Remaining Work

1. Reconcile the current menu manifest/catalog and folder/background deployment,
   preserving existing access until the intended replacements are accepted in
   Explorer. `docs\Context-Menu-Verification.md` retains earlier acceptance evidence.
2. Decide how the three supported terminal-only tools should be exposed for
   routine use. Keep prototype repair clearly identified if it is exposed later.
3. Visually review the repaired `test fix\1_smart_repaired.mp4`, especially the
   join at 01:09:17.429. Its full decode and retained-payload/timing checks passed.
   The pre-hardening comparison in `Damaged-Video-Repair.md` remains required
   before promoting this prototype more broadly.
4. Complete representative broken-TS, irregular-WMV, and remaining Explorer
   launcher tests. Mark completion per workflow rather than declaring the whole
   folder finished from synthetic tests or Registry presence alone.

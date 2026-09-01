# PowerShell Tool Guide and Regression Map

## Purpose

This is the short operational map for every PowerShell script in the repository.
Use it to remember what a script does, whether it is safe to expose to Explorer,
what changed during the large 2026-08-25/26 review, and where real-world testing is
still required.

The large change list shown by Codex corresponds to the exact Git range
`0f3bcf5^..4c7a110`: 28 files total, including 16 PowerShell scripts. A script
marked **unchanged in that goal** was not silently rewritten by that change set.

### Status vocabulary

| Status | Meaning |
| --- | --- |
| Installed / verified | Reviewed workflow whose Explorer integration is present and whose main behavior has runtime evidence. |
| Registry installed / visual pending | Registry and Shell visibility are present, but the real Explorer menu/click path still needs user-facing acceptance. |
| Terminal-only | Reviewed tool, deliberately not exposed through Explorer. |
| Prototype | Useful experiment; automated tests do not establish production or visual equivalence. |
| Legacy hold | Preserved for history but should not be installed or trusted as-is. |
| Pending review | Old workflow that has not yet received the same audit and real tests as the Video/subtitle slice. |
| Support only | Loaded by another script; not meant to be launched directly. |
| Test only | Synthetic/regression test; not a media tool. |

### The 16 PowerShell files changed in that goal

User/support code: `Video\Detect-BadCuts.ps1`,
`Video\Repair-DamagedVideo.ps1`, `Video\Repair-Mp4DisguisedTs.ps1`,
`Video\Repair-TsTimestampRemux.ps1`, `Video\Verify-VideoIntegrity.ps1`,
`subtitle\Convert-ToSrt.ps1`, `subtitle\Extract-MKV-Subtitle.ps1`,
`subtitle\lib\SubtitleNative.ps1`, and `tools\Test-EncodeEnvironment.ps1`.

Tests: `tests\Test-DetectBadCutsReal.ps1`,
`tests\Test-RepairDamagedVideoPrototype.ps1`,
`tests\Test-RepairMp4DisguisedTsSafety.ps1`,
`tests\Test-RepairTsTimestampRemuxSmoke.ps1`,
`tests\Test-SubtitleWorkflows.ps1`, `tests\Test-VerifyVideoIntegrityReal.ps1`,
and `tests\Test-VideoToolExitCodeReliability.ps1`.

## Highest regression risks

### `Video\Repair-DamagedVideo.ps1` — visual acceptance still missing

This is the hardest and most uncertain script. It was originally tuned through
repeated visual review of an old, long damaged `3.mp4`; that historical file is no
longer available. The current tests deliberately corrupt a synthetic H.264 packet
and prove range math, patch execution, collision safety, cleanup and full decode,
but **cannot prove that visible artifacts are found or removed as well as before**.

The hardened version remains active. The pre-edit comparison candidate is the same
file from commit `5c202ba`, preserved by Git tag
`repair-damaged-video-pre-hardening-2026-08-25` and local archive
`D:\Programs\Video\encode-Repair-DamagedVideo-pre-hardening-5c202ba.zip`.

Important behavior differences that require a real side-by-side test:

- the pre-edit version forced 50 fps/CFR, High profile and Level 5.2 in patch
  segments; the current version preserves source timing with VFR-capable output;
- the current version strictly accepts only MP4/MOV H.264 AVCC with four-byte NAL
  lengths instead of attempting other codecs/containers;
- audio is now optional, `libx264` is available as a test/fallback encoder, and
  quality maps to NVENC CQ or x264 CRF;
- sub-second range math and PowerShell property casts were corrected;
- existing/failing outputs are protected and the final result must pass stream
  probing and full decode.

When a real broken file appears, run old and new scripts only on copies with
different output paths. Record input hash, commands, detected ranges, removed
duration, both output hashes, full decode, seeking, audio continuity/sync and a
manual visual decision. The canonical checklist is in
`Video\Damaged-Video-Repair.md`.

### Other changed diagnostics

- `Video\Repair-TsTimestampRemux.ps1` received a substantial detector and output-
  safety change. Synthetic clean/broken TS coverage is strong, but new real
  broadcaster/capture samples should still be retained for comparison.
- `Video\Detect-BadCuts.ps1` intentionally stopped treating natural scene changes
  on non-keyframes as proof of bad edits. Requested copy-cut/keyframe alignment and
  decode errors are the authoritative results.
- Subtitle tools became stricter: ambiguous multiple tracks and image/OCR tracks
  now stop instead of guessing. This is intentional safety, but it can feel like a
  regression if the old workflow happened to accept such a file.

## Video tools

| Script | What it is for | Status and previous-goal change |
| --- | --- | --- |
| `Video\video_encode.ps1` | Main H.264 encoder. Reads media metadata, detects interlacing with FFmpeg `idet`, uses AviSynth+/QTGMC for TFF/BFF sources, supports resize/quality/GOP/encoder settings, and validates the output. | **Installed / verified.** Auto performs a real one-frame NVENC probe, keeps the established NVENC QP 22/P5 path when functional, and falls back to benchmarked x264 CRF 19/fast on systems without NVENC. The focused contract passes in PowerShell 7 and 5.1 and a real progressive x264 H.264/AAC smoke output passed full decode. |
| `Video\add_to_queue.ps1` | Silently adds a video file/folder to `Video\queue\queue.txt`, avoiding exact duplicates and file/folder overlap. | **Installed / verified. Unchanged in the pasted goal.** Still contains checkout-specific paths that belong in the future installer. |
| `Video\run_queue.ps1` | Interactive video queue manager and batch launcher for `video_encode.ps1`; retains failed entries and clears only successful work. | **Installed / verified. Unchanged in the pasted goal.** Failure retention was hardened earlier. |
| `Video\inspector\inspect.ps1` | Read-only recursive/single-file ffprobe inspector for resolution, bitrate, FPS mode, scan type, geometry, audio and policy output. | **Installed / verified. Unchanged in the pasted goal.** Earlier audit added `.ts`, reliable nonzero failures and mixed-folder continuation. |
| `Video\convert_webp_smart.ps1` | Converts static WebP/AVIF/HEIC/HEIF to validated JPG and animated inputs to timing-preserving MP4; supports single files or folders. | **Installed / verified. Unchanged in the pasted goal range** because its rewrite was the immediately preceding commit. Sources/collisions are protected and animation receives full-decode validation. |
| `Video\Merge-MP4-SRT.ps1` | Finds a same-basename `.srt` beside an MP4 and muxes both into MKV with MKVToolNix. | **Installed / verified. Unchanged in the pasted goal.** Refuses existing output and removes partial failures; real video+subtitle tests exist. |
| `Video\RemuxToMP4.ps1` | Remuxes MKV-like input to MP4 without video re-encode; keeps AAC-compatible audio or converts incompatible/PCM audio to AAC. | **Installed / verified. Unchanged in the pasted goal.** Source/collision/partial-output tests exist. |
| `Video\Repair-TsTimestampRemux.ps1` | Diagnoses TS PTS/DTS/cadence issues, optionally scans folders and moves hard-problem files, or performs TS→MKV→MP4 copy remux with optional `setts`. | **Installed / verified, changed substantially.** Normal H.264 B-frame PTS reordering is analyzed in presentation order while DTS remains in packet order; typed packet storage/native sorting reduced a 3.75 GiB full scan from 78.825 s to 5.856 s without sampling or rule changes. Folder analysis now uses 1–4 whole-file workers (default/max 4), retains filename-ordered output, isolates file failures and moves only after classification; eight warm-cache copied fixtures improved from 22.1 s sequential to 10.6 s at four workers. Added unique temp files, existing-output refusal, `-n`, partial cleanup, safe move collisions and parameter guards. Source deletion still requires explicit `-DeleteSource` plus clean verification. A real broken TS remains the regression gate. |
| `Video\Repair-Mp4DisguisedTs.ps1` | Detects a file named `.mp4` whose actual container is MPEG-TS and delegates to the TS remux workflow; real MP4 is a no-op. | **Terminal-only, changed slightly.** It now resolves the exact `pwsh` executable and requires custom outputs to use `.mp4`. Twenty-five real/synthetic assertions cover no-op, repair, collisions and invalid input. |
| `Video\Verify-VideoIntegrity.ps1` | Very fast FFmpeg copy-mode packet/container/NAL scan; it does not decode frames. | **Terminal-only, changed.** Warning detection no longer ignores every line containing `format`; detected corruption returns exit 2 even if FFmpeg exits 0, and the clean message no longer overclaims full health. Six real-fixture assertions exist. |
| `Video\Detect-BadCuts.ps1` | Mode 1 checks requested copy-cut timestamps against keyframes. Mode 2 performs full decode and reports decode errors plus informational scene transitions. | **Terminal-only, changed.** Added invariant time parsing, strict parameter validation and nonzero results for invalid/misaligned cuts or decode warnings. Scene transitions are no longer mislabeled as confirmed bad cuts. Thirteen real assertions exist. |
| `Video\Repair-DamagedVideo.ps1` | Detects invalid AVCC NAL lengths in H.264 MP4/MOV and rebuilds the file by copying clean regions, dropping damaged ranges and re-encoding only patch boundaries. | **Prototype, changed heavily.** See the mandatory visual-regression section above. Thirty synthetic safety assertions are not visual proof. |
| `Video\Recover-IncompleteMp4.ps1` | Self-contained PowerShell recovery of H.264 and experimental original AAC from supported incomplete MP4 layouts; currently the characterized Microsoft H.264 Encoder layout when a download ends inside `mdat` before `moov` is written. | **Terminal-only / real-media verified.** Its embedded compiled C# engine needs no Python. It always preserves source, refuses collisions and unknown/healthy layouts, strictly decodes recovered H.264, and reports reconstructed AAC as playback-review unless it is decoder-clean. The real 2.87 GB `1x.mp4` output exactly matched the independent prototype hash; `1x_recovered_av_test3.mp4` is the perceptual A/V baseline. |
| `Video\join-wmv-smart.ps1` | Proposes related numeric/A-B/token WMV files and joins the confirmed list with ASFBin to `<clicked-base>_joined.wmv`. | **Registry installed / visual and irregular-WMV test pending.** The menu is now `.wmv`-only; output collisions, missing ASFBin, nonzero exit and invalid output are guarded. A real ASFBin synthetic join preserved WMV2/WMA2 streams and passed full decode. ASFBin remains the chosen backend; FFmpeg is not treated as damaged-ASF-equivalent. |

## Video support scripts

| Script | What it is for | Status and previous-goal change |
| --- | --- | --- |
| `Video\inspector\lib\Metrics.ps1` | Pure compression-density calculation used by the Inspector. | **Support only; unchanged.** |
| `Video\inspector\lib\Policy.ps1` | Personal FPS buckets and bitrate quality/tier policy used by the Inspector. | **Support only; unchanged in the pasted goal.** Earlier parser compatibility adjustment only. |
| `Video\inspector\lib\render.ps1` | Console table/colour rendering functions for Inspector output. | **Support only; unchanged in the pasted goal.** Earlier parser compatibility adjustment only. |
| `Video\inspector\lib\Flags.ps1` | Empty historical placeholder; not loaded by Inspector. | **Inert scaffolding; unchanged.** Zero bytes. |
| `Video\inspector\lib\Probe.ps1` | Empty historical placeholder; not loaded by Inspector. | **Inert scaffolding; unchanged.** Zero bytes. |
| `Video\lib\TsSourceCleanup.ps1` | Enforces the TS source-deletion contract: preserve by default; delete only after explicit request, clean timestamps and successful verification. | **Support only; unchanged in the pasted goal.** Earlier focused safety tests cover it. |

## Subtitle tools

| Script | What it is for | Status and previous-goal change |
| --- | --- | --- |
| `subtitle\Convert-ToSrt.ps1` | Converts a subtitle such as VTT to validated SRT using the standalone official SeConv CLI. | **Installed / verified; new in the goal.** Preserves source, refuses existing SRT, converts in a unique temp directory, validates, then moves the result. |
| `subtitle\Extract-MKV-Subtitle.ps1` | Inspects an MKV, requires exactly one text subtitle track, and uses SeConv for a real conversion to SRT. | **Installed / verified; rewritten in the goal.** The old code could put ASS or binary bytes in a file named `.srt`; the new code refuses multiple/image tracks, collisions and invalid/partial outputs. |
| `subtitle\lib\SubtitleNative.ps1` | Shared command discovery, Windows argument quoting and stdout/stderr/exit capture for subtitle tools. | **Support only; new in the goal.** Not a standalone command. |

## Audio tools

These four scripts were **unchanged in the pasted goal** and remain the next major
legacy slice to characterize. Use copies until their overwrite and queue-failure
behavior receives the same treatment as the Video workflows.

| Script | What it is for | Current caution |
| --- | --- | --- |
| `audio\audio_encode.ps1` | Interactive or batch audio extraction/conversion from video/audio sources. Supports stream-copy extraction and AAC, MP3, WAV, FLAC, AC3 and Opus choices. | **Pending review.** Uses FFmpeg overwrite mode in conversion paths; output naming/validation and real codec cases need characterization. |
| `audio\add_to_audio_queue.ps1` | Adds supported audio/video files or folders to the audio queue with duplicate and parent/child suppression. | **Pending review.** Checkout-specific queue paths and silent error log remain. |
| `audio\run_audio_queue.ps1` | Interactive audio queue editor and batch launcher for `audio_encode.ps1`. | **Pending review.** Unlike the hardened video queue, its end-of-run cleanup should be checked against partial failures before relying on retry behavior. |
| `audio\Replace-Audio-MP4.ps1` | Selects a same-folder AAC file and creates a new MP4 with original video plus replacement AAC audio, with duration-choice prompts. | **Pending review.** Uses FFmpeg `-y`; collision policy, source/output validation, sync and duration behavior require real tests. |

## Icon tools

Both were **unchanged in the pasted goal** and are not yet characterized on this
Windows installation.

| Script | What it is for | Current caution |
| --- | --- | --- |
| `icons\convert_to_ico.ps1` | Uses ImageMagick to build a multi-size ICO (16–256 px) from PNG/JPG/BMP/WebP; refuses animated WebP. | **Pending review.** Uses a fixed `_ico_tmp` folder and does not yet have collision/failure regression coverage. |
| `icons\Extract-Exe-Icon.ps1` | Uses NirSoft IconsExtract to save the first embedded EXE icon beside the executable. | **Pending review.** Refuses an existing ICO and uses a unique temp folder, but the dependency and real extraction cases still need verification. |

## No-audio tool

| Script | What it is for | Status and previous-goal change |
| --- | --- | --- |
| `no_audio\Move-NoAudio.ps1` | Scans one folder and moves videos with no audio stream into `no_audio`. | **Safety-tested; unchanged in the pasted goal.** Earlier hardening ensures probe uncertainty/failure never means “no audio”, refuses destination collisions and preserves the source on move failure. |

## Environment tool

| Script | What it is for | Status and previous-goal change |
| --- | --- | --- |
| `tools\Test-EncodeEnvironment.ps1` | Non-mutating preflight for PowerShell, FFmpeg/AviSynth/QTGMC, MKVToolNix, ImageMagick and SeConv; supports table or JSON output. | **Support/diagnostic, changed slightly.** Added the standalone SeConv installation paths so the restored CLI is detected without adding it to `PATH`. |

## Test scripts — not user tools

| Test script | What it protects | Added/changed in the pasted goal? |
| --- | --- | --- |
| `tests\Move-NoAudio.FailureAndCollisionSafety.Tests.ps1` | Probe launch/nonzero/invalid output, valid audio/no-audio and destination collision behavior. | No; earlier test. |
| `tests\Test-ConvertSmartImageSafety.ps1` | Static/animated conversion, timing, validation, collisions, mixed folders and invalid inputs. | No; immediately preceding image-converter audit. |
| `tests\Test-DetectBadCutsReal.ps1` | Real aligned/misaligned/invalid cuts, healthy full decode and deliberately corrupt H.264 decode. | **New.** |
| `tests\Test-MergeMp4SrtSafety.ps1` | MP4+SRT→MKV tracks, source preservation, collision, missing SRT and invalid media. | No; earlier test. |
| `tests\Test-P1VideoEncodeQueueSafetyContract.ps1` | Encoder selection/arguments/NVENC-fallback, parser/metadata/child-exit contracts and video queue failed-item retention. | **Expanded** for automatic NVENC/x264 selection and portable batch settings. |
| `tests\Test-RemuxToMP4Safety.ps1` | AAC copy, PCM→AAC, source/collision safety and invalid/partial cleanup. | No; earlier test. |
| `tests\Test-RepairDamagedVideoPrototype.ps1` | Synthetic AVCC corruption detection, exact sub-second ranges, real patch path, collision/failure cleanup, video-only support and strict codec scope. | **New. Does not test visible artifacts.** |
| `tests\Test-RepairMp4DisguisedTsSafety.ps1` | Real-MP4 no-op, disguised-TS repair, audio/video validation, custom output, collisions and invalid inputs. | **New.** |
| `tests\Test-RecoverIncompleteMp4Safety.ps1` | Healthy/invalid/wrong-extension rejection, source hash/timestamp preservation, collision preservation and incompatible-switch rejection. | **New.** Real successful recovery is covered separately by the 2.87 GB `1x.mp4` acceptance run. |
| `tests\Test-RepairTsTimestampRemuxSafety.ps1` | Default source preservation and the explicit verified-deletion contract. | No; earlier test. |
| `tests\Test-RepairTsTimestampRemuxSmoke.ps1` | Clean B-frame TS classification, deliberately broken timestamps, problem-file move collision, single/folder remux, deletion and invalid input. | **New.** |
| `tests\Test-SubtitleWorkflows.ps1` | VTT→SRT, SRT/ASS-in-MKV conversion, source/collision safety and missing/invalid/no/multiple-track failures. | **New.** |
| `tests\Test-VerifyVideoIntegrityReal.ps1` | Healthy H.264 fast scan and a deliberately invalid NAL length that FFmpeg may warn about with exit 0. | **New.** |
| `tests\Test-VideoToolExitCodeReliability.ps1` | Failure/success exit-code contracts for Verify, Detect-BadCuts and Inspector. | **Expanded** for the changed diagnostics. |

## What the previous goal did not prove

- Passing PowerShell 7 and 5.1 tests proves the scripted contracts exercised by
  those fixtures, not visual quality for arbitrary real media.
- Full decode proves that a decoder can read the result without reported errors;
  it does not prove that frames look correct, that concealment did not hide damage,
  or that an editor behaves well when seeking.
- Synthetic TS samples do not represent every broadcaster, capture card, timestamp
  discontinuity or unusual stream layout.
- Audio and icon workflows were outside the large change set and remain mostly
  legacy rather than implicitly trusted.

## Recommended next real-media order

1. Do not change `Repair-DamagedVideo.ps1` again until a real visually broken H.264
   MP4/MOV is available for old/new side-by-side comparison.
2. Keep representative real TS problem files before moving or repairing them and
   record their hashes plus Avidemux/seek behavior.
3. Characterize the four audio scripts, especially overwrite, sync, partial failure
   and queue retention.
4. Characterize both icon scripts and their external dependencies.
5. Only after those slices, redesign the installer/context menus around the final
   supported set.

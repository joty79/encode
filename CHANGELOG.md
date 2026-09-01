# Changelog

All notable changes to this repo are recorded here.

## 2026-09-01

- Added x264 as a first-class choice to `Video\video_encode.ps1`. Auto now proves NVENC with an actual one-frame encode and falls back to x264 CRF 19/fast when NVIDIA encoding is unavailable, while preserving the existing NVENC QP 22/P5 behavior. Encoder choice and separate quality values persist in portable per-script batch settings with validation. The focused contract passes under PowerShell 7 and 5.1, and a real x264 H.264/AAC smoke output passed strict full decode.
- Added and installed reusable Avidemux 2.8.1 profiles for x264 CRF 19/fast and NVENC QP 22/P5-equivalent. Both performed real H.264 High + AAC MP4 encodes which passed strict full decode; Avidemux confirmed the x264 profile loaded with CRF 19, GOP 25 and 3 B-frames.

## 2026-08-29

- Replaced the hand-maintained four-target organized-menu prototype with a declarative preview manifest and generator. The generated explicit HKLM/HKCU cascade covers all 104 legacy target/verb mappings across 35 file/folder/background roots with zero omissions, extras or launcher-command mismatches, keeps `Queues` last, remains below the 15-child budget, and deletes/rebuilds only its own preview roots. The elevated import completed and the read-only audit found 139 source roots and 139 live roots with zero missing, unexpected, broken or exact-tree mismatches. Current direct verbs remain installed until real Explorer acceptance.
- Added a canonical 22-artifact context-menu catalog. Automated checks now reject uncataloged `.reg` files, missing catalog files, definition-count drift, hive-policy drift, duplicate catalog paths, missing launcher targets and exact live-tree differences. The only retained strict warning is the 93 legacy `HKEY_CLASSES_ROOT` definitions awaiting explicit-hive migration before a final installer.
- Added a non-mutating context-menu inventory auditor that compares every repository `.reg` logical tree with live HKLM/HKCU Encode-owned verbs, checks referenced launcher paths, and generates human-readable plus JSON evidence. The first exact-tree baseline found 108 source roots and 108 live roots with no missing, unexpected, broken, duplicate, or value/tree mismatch; 93 legacy HKCR definitions remain explicitly flagged for hive migration before a canonical installer.
- Converted `Video\Recover-IncompleteMp4.ps1` into one self-contained PowerShell file with an embedded compiled C# binary-recovery engine. Removed the Python/Miniconda dependency and separate Python support file. The full 2.87 GB `1x.mp4` run retained 19,428 video frames, 30,385 AAC frames, 497 fallback regions and strict-clean H.264; its 2,873,286,350-byte output had the exact same SHA-256 as the independently tested Python result.
- Added the classic `.mp4` Explorer action `Recover incomplete MP4`, launching the self-contained script in a persistent Windows Terminal tab. The initial per-user key passed Registry readback and Shell enumeration but failed the real visible Explorer test. The canonical artifact was corrected and elevated-imported into explicit machine-wide `SystemFileAssociations\.mp4`, with exact `HKLM`/merged-`HKCR` readback and Shell enumeration; the failed `HKCU` duplicate was removed. The user confirmed the corrected action is visible in the real Explorer menu; launcher acceptance remains pending.
- Copied the Avidemux ICO byte-for-byte into the repository as `.assets\avidemux.ico` and assigned it to the incomplete-MP4 Explorer verb, removing that menu's dependency on the personal Documents icon path. Registry readback passed; visual icon refresh remains user acceptance.

## 2026-08-28

- Added a source-preserving incomplete-MP4 recovery workflow whose first supported case is the characterized truncated `Microsoft H.264 Encoder V1.5.3` layout. It reconstructs Annex-B H.264 and experimental ADTS AAC from an `mdat` cut off before `moov`, refuses healthy/unknown inputs and collisions, remuxes without re-encoding, validates streams, strictly decodes recovered video and labels non-clean AAC for manual playback review. The real `1x.mp4` and user-confirmed `1x_recovered_av_test3.mp4` established the structural and perceptual A/V baseline.

## 2026-08-27

- Optimized the TS timestamp analyzer without changing its full-packet coverage or detection rules. Typed numeric packet storage and native array sorting replaced per-packet PowerShell objects plus `Sort-Object`: the current 243 MB `1.ts` improved from 4.061 s to 0.845 s, while a 3.75 GiB/767,217-packet `2.ts` improved from 78.825 s to 5.856 s. A two-file folder scan completed in 5.850 s. Focused TS safety, smoke and exit-code tests pass under PowerShell 7 and Windows PowerShell 5.1.
- Added bounded whole-file parallelism to TS folder analysis (`-ScanWorkers 1..4`, default/max 4) without changing packet coverage or classification rules. Eight clean copied fixtures totaling 15.91 GiB measured 21.920–22.322 s sequential, 14.460–14.678 s with two workers and 10.499–10.749 s with four; output remains filename-ordered, file failures are isolated, and moving occurs only after that file's completed classification. Also restored the streaming analyzer's actual Windows PowerShell 5.1 runtime compatibility.
- Unified the TS analysis context-menu label as `Analyze TS timestamps` for both `.ts` files and folders while keeping both folder and folder-background entries Shift-only.

## 2026-08-26

- Imported all 19 current Explorer `.reg` artifacts for an explicit Windows 11 discovery pass and added a durable visual verification matrix before menu organization. Moved the TS and subtitle file verbs to explicit machine-wide `SystemFileAssociations` after real Explorer evidence showed the former per-user entries were enumerated by Shell APIs but not rendered. Renamed the multi-selection tweak to `Explorer-MultiSelectLimit.reg`, removed its inert empty handler key, and installed `MultipleInvokePromptMinimum=100`.
- Restored the WMV join menu with ASFBin as the chosen backend and limited it to `.wmv`. The script now refuses existing outputs, avoids PowerShell automatic-variable collisions, validates ASFBin exit/output, and passed a real synthetic ASFBin join with WMV2 video, WMA2 audio and a clean full decode; an irregular user WMV remains the decisive regression test.
- Added a complete PowerShell tool and regression guide covering all 43 `.ps1` files. It separates user tools, support modules and tests; identifies the exact 16 PowerShell files changed in the large review; and records the remaining real-media/visual test gaps, especially the mandatory old/new damaged-video comparison.
- Restored the official standalone Subtitle Edit SeConv v5.1.0 x64 asset to `C:\Program Files\Subtitle Edit CLI`. The preserved ZIP exactly matches the size and SHA-256 published by the official GitHub release API; runtime, embedded product version, license, unsigned status, and the upstream `--version` banner inconsistency are recorded in `subtitle\README.md`.
- Replaced the hardcoded legacy VTT runner with a safe `Convert-ToSrt.ps1` workflow that resolves SeConv at its current installation path, preserves sources, refuses collisions, converts through a unique temporary directory, and validates the final SRT.
- Reworked MKV subtitle extraction to inspect tracks through MKVToolNix and perform a real SeConv text conversion. It now refuses multiple tracks, image/OCR tracks, invalid inputs, existing outputs, and partial results instead of potentially naming ASS or binary data `.srt`. Twenty-eight assertions pass in PowerShell 7 and 5.1; both reviewed Explorer actions were moved from machine-wide `HKCR` to per-user `HKCU\Software\Classes`, imported, and read back exactly.
- Kept the hardened damaged-video prototype as the active version while preserving the exact pre-edit `Repair-DamagedVideo.ps1` from commit `5c202ba` in a local hashed archive and pushed Git tag. Documented the mandatory future side-by-side test on a real broken video, including visual artifacts, detection ranges, audio sync, decode, seeking, and input/output hashes.

## 2026-08-25

- Restored AviSynth+ 3.7.5 x86/x64 on the current Windows 11 installation from a local installer whose size and SHA-256 matched the official GitHub release asset.
- Verified x86/x64 runtime DLLs and HKLM plugin registrations, achieved a clean `Test-EncodeEnvironment.ps1` result, and runtime-tested `BlankClip`, preserved FFMS2 `FFVideoSource`, the exact QTGMC recipe, and QTGMC-to-`h264_nvenc` MP4 encoding.
- Revalidated the preserved QTGMC hash manifest and complete `AviSynth+.rar` integrity after installation; the custom payload and safety archive remained unchanged.
- Completed the real-input recovery baseline with a bottom-field-first MPEG-2 sample through the restored Explorer context menu; verified progressive H.264/AAC output metadata, hashes, full error-strict decode, persisted settings, and user visual acceptance.
- Restored the video queue Explorer menus and runtime-verified the real silent-add-to-queue path, successful QTGMC batch encoding and queue cleanup, plus failed-item retention. Hardened invalid-video metadata probing so ffprobe failures stop with one focused error instead of cascading null and divide-by-zero errors.
- Reviewed and restored the read-only media Inspector, added `.ts` file/folder discovery and context-menu integration, and made failed or invalid ffprobe results return nonzero while mixed-folder inspection continues. Added a canonical Video tool inventory and deferred installer work until the Video context-menu set is fully reviewed.
- Reviewed and restored the MKV-to-MP4 remux menu; added explicit existing-output refusal, nonzero failure exits, partial-output cleanup, ffprobe validation, and context-only pause behavior. Real FFmpeg tests cover compatible AAC copy, PCM-to-AAC conversion, invalid input, and source/output preservation.
- Recovered signed MKVToolNix v101.0 from the official Windows release and reviewed/restored the matching MP4+SRT merge menu. The merge now enforces nonzero failures, existing-output preservation, partial cleanup, and validated video+subtitle tracks; real tests cover success, missing SRT, invalid video, and source preservation. The environment preflight now recognizes MKVToolNix at its standard path, and the Inspector helpers parse under both PowerShell 7 and Windows PowerShell 5.1.
- Audited the legacy WMV smart-join workflow without restoring its menu. Recorded its overbroad file association, overwrite/exit-validation defects, unsigned ASFBin dependency and license boundary; a synthetic FFmpeg 9 stream-copy join passed as a possible replacement for ordinary compatible WMV files, but specialized damaged-ASF behavior remains an explicit decision.
- Recovered signed ImageMagick v7.1.2-30 and rewrote/restored the smart WebP/AVIF/HEIC converter. Static images now produce validated JPGs; animations use direct FFmpeg VFR conversion with preserved timing and full-decode validation. Existing outputs and sources are preserved, batch failures return nonzero without stopping valid siblings, and 25 real assertions pass in PowerShell 7 and 5.1. Activated the verified bundled Limited security policy with an exact Open-policy backup, then imported and read back all five context-menu commands.
- Hardened and restored the TS timestamp/remux menu family. Repair now refuses existing outputs, uses collision-free temporary MKVs, and removes newly-created partial outputs on failure. Fixed a false-positive analyzer bug where normal H.264 B-frame PTS reordering was treated as corruption; DTS remains checked in packet order while PTS cadence is evaluated in presentation order. Real smoke coverage now proves clean-file non-movement, deliberately broken timeline detection/movement with collision safety, and single/folder repair; all six Registry entries were imported and read back.
- Characterized the terminal-only MP4-disguised-TS helper with 25 real assertions under both PowerShell hosts. It now resolves its child PowerShell host explicitly and rejects non-MP4 output names; normal MP4 is a byte-identical no-op, while actual MPEG-TS-in-MP4 repair preserves the source and validates the resulting MP4 video/audio streams, collisions, custom output, and failure cleanup.
- Characterized `Verify-VideoIntegrity.ps1` as a supported terminal-only fast packet/container diagnostic rather than a full decode. Detected corruption now returns nonzero even when FFmpeg reports warnings with exit zero. Real fixtures prove a healthy H.264 MP4 succeeds and a deliberately damaged NAL length is detected; focused exit-code coverage increased to 32 assertions.
- Characterized both `Detect-BadCuts.ps1` modes under real media and corrected their contracts. Requested copy-mode cuts now return nonzero for misaligned or invalid timestamps, while full decode returns nonzero for detected bitstream/decode warnings even when FFmpeg exits zero. Natural scene transitions on non-keyframes are now explicitly informational rather than mislabeled as bad edits. Thirteen real assertions cover aligned/misaligned cuts and healthy/corrupt decode; focused reliability coverage increased to 36 assertions.
- Characterized and hardened the saved damaged-H.264 repair prototype without promoting it to an installed tool. It now strictly accepts only MP4/MOV H.264 AVCC input, preserves source timing and optional audio, refuses collisions, removes failed partial outputs, and validates the final stream structure plus a full decode. Fixed sub-second timestamp corruption caused by PowerShell integer overload selection; 30 synthetic assertions exercise exact range detection, a real patch repair, failure cleanup, and both PowerShell hosts.
- Completed classification of every PowerShell workflow in the `Video` folder. The unsafe legacy WMV/ASFBin join is now an explicit preserved-but-unsupported hold pending a real use case and license decision; four zero-byte Inspector files are confirmed unreferenced scaffolding dating from the initial commit. Neither is installed or exposed through Explorer.

## 2026-08-24

- Hardened `Video\Repair-TsTimestampRemux.ps1` source cleanup: source `.ts` files are now preserved by default, deletion requires explicit `-DeleteSource`, and deletion is blocked unless both timestamp checks and FFmpeg verification complete cleanly. `-DeleteSource -NoVerify` is rejected before processing.
- Added focused source-cleanup contract tests and a synthetic end-to-end MPEG-TS smoke test.
- Hardened `no_audio\Move-NoAudio.ps1`: ffprobe launch, nonzero-exit, and invalid-output failures now preserve the source, and moves refuse to overwrite an existing destination.
- Hardened `Video\Verify-VideoIntegrity.ps1` and `Video\Detect-BadCuts.ps1`: native tool/input failures now return nonzero, retain diagnostics, and cannot report a healthy/success result. Replaced the invalid `Orange` console color with `DarkYellow`.
- Hardened the legacy video encoder and queue: ffprobe now receives literal native arguments without `Invoke-Expression`, FFmpeg and child encoder exit codes are enforced, stale/partial failed outputs are rejected, and failed queue entries are retained for retry instead of clearing the entire queue.
- Added deterministic safety suites for no-audio moves, video inspection failures, and video encoder/queue failure handling.

## 2026-07-04

- Added `Video\Repair-Mp4DisguisedTs.ps1`, a terminal-only helper that repairs `.mp4` files whose real container is MPEG-TS while refusing to touch normal MP4/MOV containers. It skips `setts` by default to preserve duration on MP4-named TS files.
- Changed `Video\Repair-TsTimestampRemux.ps1` fix output policy: fixed MP4 files now go into `_TS_FIXED_MP4` with the original base name and `.mp4` extension, and the source `.ts` is deleted only after successful creation and verification. Added `-KeepSource` for manual runs that should preserve the source.
- Improved `Video\Repair-TsTimestampRemux.ps1` analysis to flag heavy video cadence jitter as an Avidemux-risk `PROBLEM`, covering `.ts` files like `2.ts` that have monotonic PTS/DTS but still fail direct Avidemux MP4 save.
- Improved `Video\Repair-TsTimestampRemux.ps1` console output for Windows Terminal with clearer status lines, emoji labels, compact folder scan summaries, and problem-file grouping.
- Updated the Shift-only folder analyze context menu to scan `.ts` files and move hard timestamp-problem files into `_TS_TIMESTAMP_PROBLEMS`.
- Added `Video\Repair-TsTimestampRemux.reg` with separate `.ts` context menus for timestamp analysis and no-reencode TS-to-MP4 repair, plus Shift-only folder actions for batch `.ts` processing.
- Extended `Video\Repair-TsTimestampRemux.ps1` with folder batch mode and `-SkipInputAnalysis` for faster context-menu remuxing.
- Added `Video\Repair-TsTimestampRemux.ps1` for MPEG-TS timestamp diagnosis and no-reencode `TS -> MKV -> MP4` repair with optional packet timestamp rewrite.
- Added `Video\Ts-Timestamp-Remux.md` to document the `1.ts` Avidemux/seekbar timestamp issue, MKV intermediate workaround, `setts` repair, verification, and known limits.
- Added `Video\Repair-DamagedVideo.ps1` prototype for damaged MP4/H.264 detection and smart repair that re-encodes only affected patch windows while copying clean regions.
- Added `Video\Damaged-Video-Repair.md` to document the `3.mp4` repair experiment, detector policy, smart patch rendering approach, audio handling lesson, verification checks, and known limits.
- Recorded the damaged-video repair workflow as durable project memory in `PROJECT_RULES.md`.

## 2026-07-03

- Added [Verify-VideoIntegrity.ps1](file:///d:/Users/joty79/scripts/encode/Video/Verify-VideoIntegrity.ps1) script under `Video/` to perform blazing-fast, copy-mode packet integrity checking of video files in under a second (no decoding required).

## 2026-06-28

- Added [Detect-BadCuts.ps1](file:///d:/Users/joty79/scripts/encode/Video/Detect-BadCuts.ps1) script under `Video/` to perform unified, real-time scanning of MP4 files for both decoding errors and non-keyframe scene cuts.
- Enabled GPU-accelerated decoding support (`-UseGPU`) that correctly offloads work to the GPU decode engine while utilizing the `select` and `showinfo` filters.
- Implemented real-time console reporting that immediately prints bad cuts (scene changes landing on P/B frames) and progress (FPS/frames) as they are detected.
- Added a proactive checker mode (`-Cuts`) that instantly verifies proposed cut timestamps against the source video's keyframe indices (running in under a second) and outputs the nearest keyframe values.
- Fixed a bug where `$val` was passed as a reference (`[ref]`) to `TryParse` in the keyframe loader loop before being initialized.

## 2026-05-07

- Initialized `encode` as a Git repository.
- Added root documentation: `README.md`, `CHANGELOG.md`, and `PROJECT_RULES.md`.
- Added `.gitignore` for runtime queue state, logs, local editor state, archives, and Windows clutter.

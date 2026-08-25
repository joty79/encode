# Changelog

All notable changes to this repo are recorded here.

## 2026-08-26

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

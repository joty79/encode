# Changelog

All notable changes to this repo are recorded here.

## 2026-08-25

- Restored AviSynth+ 3.7.5 x86/x64 on the current Windows 11 installation from a local installer whose size and SHA-256 matched the official GitHub release asset.
- Verified x86/x64 runtime DLLs and HKLM plugin registrations, achieved a clean `Test-EncodeEnvironment.ps1` result, and runtime-tested `BlankClip`, preserved FFMS2 `FFVideoSource`, the exact QTGMC recipe, and QTGMC-to-`h264_nvenc` MP4 encoding.
- Revalidated the preserved QTGMC hash manifest and complete `AviSynth+.rar` integrity after installation; the custom payload and safety archive remained unchanged.
- Completed the real-input recovery baseline with a bottom-field-first MPEG-2 sample through the restored Explorer context menu; verified progressive H.264/AAC output metadata, hashes, full error-strict decode, persisted settings, and user visual acceptance.

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

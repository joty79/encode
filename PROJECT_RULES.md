# Project Rules

Long-lived project memory for `D:\Users\joty79\scripts\encode`.

## Current Scope

- This repo owns legacy PowerShell media helper scripts under `Video/`, `audio/`, `subtitle/`, `icons/`, and `no_audio/`.
- Treat `.ps1` files as script logic and `.reg` files as Windows Explorer context-menu integration artifacts.
- Preserve existing behavior unless a change is explicitly requested.
- Treat the established encode/audio/queue workflows as a known-good legacy core; restore and characterize them before modernization.
- Treat the video-integrity and TS timestamp/repair tooling added in `fb33b0d` as a newer diagnostic layer that requires independent validation.
- The known-good interlaced-video path uses FFmpeg `idet`, AviSynth+ 3.7.5 x64, FFMS2, and QTGMC; `docs/AviSynth-QTGMC-Recovery.md` owns its recovery evidence.

## Guardrails

- Confirm active repo path before reads/edits: `D:\Users\joty79\scripts\encode`.
- Review `.reg` files carefully before import or edits, especially absolute script paths and wildcard registry keys.
- Do not track runtime queue state, logs, or machine-local generated archives.
- After PowerShell script edits, run parser validation before runtime testing when command execution is allowed.

## Decisions

### 2026-07-04 - MPEG-TS timestamp remux repair

- Date: 2026-07-04
- Problem: MPEG-TS files can play with laggy Windows seekbars or fail Avidemux MP4 save with "Too short" / invalid timestamp errors even when the encoded streams are readable.
- Root cause: Broadcast-style TS timelines may contain large PTS gaps, tiny/duplicate PTS/DTS deltas, or heavy video cadence jitter even when PTS/DTS remain monotonic. This is a container/timestamp problem, not the same as visual H.264 payload corruption.
- Guardrail/rule: Treat TS timestamp repair as a separate workflow from damaged-frame repair. First diagnose packet PTS/DTS gaps, backwards timestamps, tiny duplicate deltas, and heavy video cadence jitter when investigating. For Shift-only folder diagnosis, show compact per-file statuses and move hard timestamp/Avidemux-risk `.ts` files into `_TS_TIMESTAMP_PROBLEMS`. For routine file/folder context-menu repair, skip the input diagnosis and directly no-reencode remux via `TS -> MKV -> MP4`, `-c copy`, `+faststart`, and video `setts` packet timestamp rewrite before post-verification.
- Files affected: `Video/Repair-TsTimestampRemux.ps1`, `Video/Repair-TsTimestampRemux.reg`, `Video/Ts-Timestamp-Remux.md`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: Prototype on `D:\Users\joty79\Desktop\1.ts`; final `1_fixed_no_reencode.mp4` kept H.264/AAC without re-encode, preserved video/audio packet counts, had no tiny PTS/DTS deltas, no backwards PTS/DTS, and passed copy-mode verification. Context-menu registry artifact reviewed for `.ts` file actions plus Shift-only folder actions.

### 2026-07-06 - MP4 extension with MPEG-TS container helper

- Date: 2026-07-06
- Problem: `D:\Users\joty79\Desktop\1.mp4` looked like an MP4 by extension but failed like the TS timestamp/editing cases.
- Root cause: `ffprobe` identified the real container as `mpegts`; the file started with MPEG-TS sync byte `0x47` and had hundreds of corrupt video packet flags.
- Guardrail/rule: Do not treat this as generic MP4 repair. Use a dedicated helper that first verifies the real container. If the `.mp4` is normal MP4/MOV, stop. If it is MPEG-TS, run no-reencode `TS -> MKV -> MP4`, keep the source file, and skip `setts` by default because it can stretch the video duration on MP4-named TS files with mismatched cadence.
- Files affected: `Video/Repair-Mp4DisguisedTs.ps1`, `Video/Repair-TsTimestampRemux.ps1`, `Video/Ts-Timestamp-Remux.md`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: Parser validation passed. Synthetic real MP4 smoke stopped without output. `D:\Users\joty79\Desktop\1.mp4` repaired to a temp MP4 with no re-encode. The `setts` variant passed copy verification but stretched video duration to about `2039s`; the no-`setts` variant preserved about `1701s` audio/video duration and passed copy-mode verification while preserving the source file.

### 2026-07-04 - TS fix output folder and source cleanup

- Date: 2026-07-04
- Problem: Folder fix was producing MP4 files alongside source `.ts` files and adding extra suffixes, making bulk cleanup awkward after successful TS-to-MP4 remux.
- Root cause: The original default output path was `<name>_fixed_no_reencode.mp4` in the source folder and the script preserved the source `.ts`.
- Guardrail/rule: Default TS fix output should be `_TS_FIXED_MP4\<same base name>.mp4`. After successful remux and verification, delete the source `.ts`. Keep `-KeepSource` available for manual test runs where deletion is not wanted.
- Files affected: `Video/Repair-TsTimestampRemux.ps1`, `Video/Ts-Timestamp-Remux.md`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: Parser validation passed. Synthetic single-file smoke wrote `_TS_FIXED_MP4\single.mp4` and deleted `single.ts` after verification. Synthetic folder smoke wrote `_TS_FIXED_MP4\a.mp4` and `_TS_FIXED_MP4\b.mp4`, deleted both source `.ts` files after verification, and completed with zero failures.

### 2026-07-04 - MPEG-TS Avidemux-risk cadence jitter detection

- Date: 2026-07-04
- Problem: `D:\Users\joty79\Desktop\2.ts` failed Avidemux direct MP4 save with "Too short" / invalid timestamps around `00:01:25.134`, but the analyzer reported it as clean.
- Root cause: The file had monotonic PTS/DTS and no tiny duplicates, but about 52% of video packet deltas deviated from the expected frame cadence. The original analyzer only treated backwards/duplicate timestamps as hard problems.
- Guardrail/rule: For TS analysis, heavy video cadence jitter is an Avidemux-risk `PROBLEM` even when PTS/DTS are monotonic. Folder scan should move those files to `_TS_TIMESTAMP_PROBLEMS` when `-MoveProblemFiles` is used.
- Files affected: `Video/Repair-TsTimestampRemux.ps1`, `Video/Ts-Timestamp-Remux.md`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: Parser validation passed. `2.ts -AnalyzeOnly` now reports `VideoCadenceJitter=166245 (52.0%)` as `PROBLEM`. Temporary folder scan on a 120-second `2.ts` sample reported `PROBLEM` and moved it into `_TS_TIMESTAMP_PROBLEMS`.

### 2026-07-04 - Damaged H.264 smart repair prototype

- Date: 2026-07-04
- Problem: Some MP4/H.264 files opened or played inconsistently in editors/players because corruption was inside video packets, not the outer MP4 container.
- Root cause: Invalid AVCC/NAL packet payloads can produce visible artifacts and Avidemux crashes even when container metadata, duration, and stream layout look valid.
- Guardrail/rule: Treat damaged-video repair as two separate reusable contracts: packet/visual-damage detection and smart patch rendering. Detection should identify bad packet ranges, extend/merge them conservatively, and output timestamp ranges. Rendering should copy clean segments, re-encode only affected patch/kept ranges with matching H.264/AAC settings, cut audio with the same timeline, and verify final video/audio decode.
- Files affected: `Video/Verify-VideoIntegrity.ps1`, `Video/Repair-DamagedVideo.ps1`, `Video/Damaged-Video-Repair.md`
- Validation/tests run: Manual prototype on `D:\Users\joty79\Desktop\3.mp4`; final repaired output had no visual artifacts, no audio desync, full video/NAL verification clean, repaired-area decode clean, and audio decode/level checks clean.

### 2026-05-07 - Repo onboarding

- Date: 2026-05-07
- Problem: The legacy encode scripts did not have a Git repo or root documentation.
- Root cause: The scripts predate the current repo/documentation workflow.
- Guardrail/rule: Keep root docs minimal, track reusable scripts/integration files, and ignore runtime queue/log state.
- Files affected: `.gitignore`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`
- Validation/tests run: Initial file inventory and `git status --short`.

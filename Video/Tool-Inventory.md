# Video Tool Inventory

## Purpose

This is the current source of truth for the `Video` folder during Windows 11 re-onboarding. It records which artifacts are supported, installed, pending review, dependency-blocked, prototypes, support files, or empty scaffolding. Do not bulk-import the remaining `.reg` files; review and validate one workflow at a time.

## Current Installed and Verified Menus

The following legacy Registry groups were manually imported and runtime-verified on 2026-08-25. They are not yet managed by an installer or uninstaller.

| Workflow | Code and integration | Current evidence |
| --- | --- | --- |
| Direct NVIDIA H.264 encode | `video_encode.ps1`, `video_encode.reg` | Real BFF MPEG-2 through QTGMC/NVENC; progressive H.264/AAC output; full decode; user visual acceptance |
| Add to video queue | `add_to_queue.ps1`, `silent_runner.vbs`, `add_to_queue.reg` | Real silent `wscript` launch queued a temporary sample |
| Run video queue | `run_queue.ps1`, `run_queue.reg` | Successful QTGMC batch cleared the entry; invalid media returned nonzero and remained queued |
| Media metadata Inspector | `inspector\inspect.ps1`, `inspector\inspect.reg`, `inspector\lib\Metrics.ps1`, `Policy.ps1`, `render.ps1` | Valid MPG and TS rendering; invalid input returns nonzero; mixed folder continues after failure; `.ts` menu added |

## Pending User-Facing Workflow Review

| Workflow | Artifacts | Dependency/state | Next decision |
| --- | --- | --- | --- |
| Remux video to MP4 | `RemuxToMP4.ps1`, `RemuxToMP4.reg` | FFmpeg/ffprobe available | Review next; test compatible audio copy, incompatible audio conversion, overwrite behavior, and failures |
| Merge matching MP4 + SRT | `Merge-MP4-SRT.ps1`, `Merge-MP4-SRT.reg` | MKVToolNix missing from the recorded path and `PATH` | Recover dependency, then test success/failure and output verification |
| Join related WMV files | `join-wmv-smart.ps1`, `join-wmv-smart.reg` | ASFBin exists at the script's fixed path but is not on `PATH` | Review selection rules, overwrite policy, exit handling, and real join behavior |
| Convert WebP/AVIF/HEIC | `convert_webp_smart.ps1`, `convert_webp_smart.reg` | ImageMagick `magick` missing; FFmpeg available | Recover ImageMagick, then test static and animated inputs without overwriting existing output |
| TS timestamp analysis/remux | `Repair-TsTimestampRemux.ps1`, `.reg`, `Ts-Timestamp-Remux.md` | FFmpeg/ffprobe available; safety and smoke tests pass | Review all six menu actions and real problem samples before Registry import |
| MP4 file containing TS data | `Repair-Mp4DisguisedTs.ps1` | FFmpeg/ffprobe available; terminal-only | Keep terminal-only until a real repeated use case justifies a menu |

## Diagnostics and Prototypes — Do Not Install Yet

| Artifact | Classification | Reason |
| --- | --- | --- |
| `Verify-VideoIntegrity.ps1` | Newer diagnostic | Focused failure tests pass, but it has no context-menu contract and needs representative healthy/corrupt samples |
| `Detect-BadCuts.ps1` | Newer diagnostic | Focused failure tests pass; proactive and full-scan modes still need characterization |
| `Repair-DamagedVideo.ps1` | Saved prototype | Its own help says it is not a universal repair engine; keep terminal-only until independently validated |
| `Damaged-Video-Repair.md` | Prototype documentation | Owns the limits and evidence for the damaged-H.264 experiment |

## Support Files — Not Standalone Tools

| Artifact | Owner/use |
| --- | --- |
| `lib\TsSourceCleanup.ps1` | Shared source-deletion guard used by TS timestamp remux |
| `video_encode_changelog.md` | Historical video encoder notes |
| `CHANGELOG.md` | Historical queue notes |
| `ContextMenuHandlers.reg` | Global Explorer multi-selection tweak; not a media command and deferred until context-menu redesign |
| `icons.code-workspace` | Editor workspace artifact; not an installable tool |

## Empty Inspector Scaffolding

These tracked files are currently zero bytes and are not loaded by `inspect.ps1`:

- `inspector\config\policy.psd1`
- `inspector\lib\Flags.ps1`
- `inspector\lib\Probe.ps1`
- `inspector\Readme.md`

Do not infer intended behavior from their names. Decide whether to populate or remove them only during the Inspector/context-menu redesign.

## Dependency Snapshot — 2026-08-25

| Dependency | Current state |
| --- | --- |
| PowerShell 7 / Windows Terminal | Available |
| FFmpeg / ffprobe 9.0 | Available on `PATH` |
| AviSynth+ 3.7.5 / QTGMC / FFMS2 | Restored and runtime-verified |
| ASFBin | Present at `C:\Program Files\CutAssist\asfbin\asfbin.exe`; not on `PATH` |
| MKVToolNix | Missing from `C:\Program Files\MKVToolNix` and `PATH` |
| ImageMagick | `magick` missing from `PATH` |

## Agreed Order

Finish review and characterization of the `Video` folder before designing an installer. Restore only approved context-menu entries as their workflow tests pass. Revisit installer/uninstaller architecture only after obsolete, testing-only, and prototype tools have been separated from the final context-menu design.

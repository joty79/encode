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
| Remux MKV to MP4 | `RemuxToMP4.ps1`, `RemuxToMP4.reg` | Real AAC stream-copy and PCM-to-AAC tests; source preserved; existing output unchanged; invalid input leaves no partial MP4 |
| Merge matching MP4 + SRT | `Merge-MP4-SRT.ps1`, `Merge-MP4-SRT.reg` | Real video+subtitle MKV validation; sources preserved; existing output unchanged; missing/invalid input leaves no partial MKV |
| Convert WebP/AVIF/HEIC/HEIF | `convert_webp_smart.ps1`, `convert_webp_smart.reg` | 25 real assertions in both shells under Limited policy; five Registry commands imported and read back; static/animated timing and output validation verified |
| TS timestamp analysis/remux | `Repair-TsTimestampRemux.ps1`, `.reg`, `lib\TsSourceCleanup.ps1` | Clean B-frame and deliberately broken-timeline TS classification; single/folder repair; source, collision, partial-output and unique-move safety; six Registry entries read back |

## Pending User-Facing Workflow Review

| Workflow | Artifacts | Dependency/state | Next decision |
| --- | --- | --- | --- |
| Join related WMV files | `join-wmv-smart.ps1`, `join-wmv-smart.reg` | Legacy ASFBin is present but unsigned and has a non-commercial/evaluation license boundary; menu is not installed | Decide whether to replace simple joins with FFmpeg or explicitly retain ASFBin's specialized damaged-ASF behavior |

## Supported Terminal-Only Workflows

| Workflow | Artifact | Current evidence |
| --- | --- | --- |
| Repair `.mp4` filename containing MPEG-TS | `Repair-Mp4DisguisedTs.ps1` | 25 real assertions in both shells: normal MP4 no-op, disguised-TS repair, video/audio validation, custom output, source/collision preservation, and invalid/missing input cleanup |
| Fast packet/container integrity scan | `Verify-VideoIntegrity.ps1` | Real healthy H.264 MP4 returns success; deliberately corrupt NAL length returns nonzero even when FFmpeg itself exits zero; explicitly not a full decode |

## Diagnostics and Prototypes — Do Not Install Yet

| Artifact | Classification | Reason |
| --- | --- | --- |
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

- The legacy Registry entry is not installed. As written, it targets `HKEY_CLASSES_ROOT\*`, so it would appear for every file type instead of only WMV files.
- The script passes ASFBin `-y`, does not protect an existing output, does not verify ASFBin's exit code or output, and can over-match numeric/token-related filenames. Manual mode also shadows PowerShell's automatic `$input` variable.
- Installed ASFBin reports v1.8.3.934, was built in 2012, is not Authenticode-signed, and its bundled documentation states that it is free for non-commercial use while the executable help says evaluation use. No terms were accepted or interpreted by the agent.
- A synthetic two-part WMV test proved that FFmpeg 9 can concatenate compatible WMV2/WMA2 inputs by stream copy into a valid ASF/WMV output with both streams and a clean full decode.
- The FFmpeg test does not prove equivalence to ASFBin's specialized damaged-ASF recovery behavior. Do not restore this menu until the intended use and dependency choice are explicit.

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

## Agreed Order

Finish review and characterization of the `Video` folder before designing an installer. Restore only approved context-menu entries as their workflow tests pass. Revisit installer/uninstaller architecture only after obsolete, testing-only, and prototype tools have been separated from the final context-menu design.

# AviSynth+ / QTGMC Recovery

## Status

This document captures the known-good Windows 10 environment used by the legacy video encoder and its Windows 11 recovery. AviSynth+ 3.7.5, FFMS2, QTGMC, and the existing NVENC path were restored and verified with both synthetic media and a representative real interlaced MPEG-2 input on 2026-08-25.

The existing encoding workflow was working for its intended use. Recovery must preserve that behavior before any modernization or refactoring.

## Existing Encode Behavior

`Video\video_encode.ps1` uses this path only for `.mpg`, `.mpeg`, and `.vob` inputs detected as interlaced:

1. FFmpeg `idet` examines the first 300 video frames.
2. The script selects TFF or BFF from the detection result.
3. A temporary `.avs` file is generated with:

   ```text
   FFVideoSource("<input>")
   AssumeTFF() or AssumeBFF()
   QTGMC(Preset="Slow", TR2=2, FPSDivisor=2)
   Prefetch(14)
   ```

4. FFmpeg reads the `.avs` source and performs the existing NVENC encode.

Do not change this behavior during environment recovery. First produce a known-good output that can serve as the modernization baseline.

## Recovered Windows 10 Installation

The surviving setup log is:

`E:\Compilers\AviSynth+\Setup Log 2026-01-24 #005.txt`

It records:

- Installer: `AviSynthPlus_3.7.5_20250420_vcredist.exe`
- AviSynth+: `3.7.5`, release build dated 2025-04-20
- Installation root: `E:\Compilers\AviSynth+`
- Windows at installation time: Windows 10 x64 build 19045
- Installer elevation: Administrator
- Selected components: `main`, `main\avs32`, `main\avs64`, `associations`, `associations\openwithnotepad`
- x86 and x64 Visual C++ redistributables were included and completed with exit code 0
- x64 plugin autoload path: `E:\Compilers\AviSynth+\plugins64+`

The original installer is no longer present at its recorded Downloads path. Use only the official AviSynth+ release source when restoring it.

Official release page: <https://github.com/AviSynth/AviSynthPlus/releases/tag/v3.7.5>

## Preserved QTGMC Payload

The old `AVSInfoTool` report proves that the following x64 files loaded in the working Windows 10 environment:

| Component | Known-good version or snapshot |
| --- | --- |
| AviSynth+ | 3.7.5 x86_64, interface 11 |
| FFMS2 | 2024-05-28 build |
| MaskTools2 | 2.2.30.0 |
| MVTools2 | 2.7.46.0 |
| NNEDI3 | 0.9.4.68 |
| RgTools | 1.2.0.0 |
| QTGMC | `QTGMC.avsi`, preserved 2026-01-24 |
| Shared functions | `Zs_RF_Shared.avsi`, preserved 2026-01-24 |
| Additional preserved plugins | `DePan.dll`, `DePanEstimate.dll` |

The source function `FFVideoSource` used by the encoder comes from `ffms2.dll`.

The old report warned that some DePan/MVTools functions can use `libfftw3f-3.dll`. The working encode recipe did not establish that this optional DLL was required for the selected QTGMC settings. Do not copy an FFTW DLL into Windows system directories unless a focused runtime test proves it is needed and its source/integrity have been verified.

## Pre-Recovery Windows 11 State

Read-only inspection on 2026-08-23 found:

- `E:\Compilers\AviSynth+` and the custom x64 plugins are preserved.
- `C:\Windows\System32\AviSynth.dll` is absent.
- `C:\Windows\SysWOW64\AviSynth.dll` is absent.
- `HKLM\Software\AviSynth` and its 32-bit equivalent are absent.
- FFmpeg 9.0 is installed and was built with `--enable-avisynth`.
- The preserved `E:` directory is therefore a payload/forensic source, not an active AviSynth installation.
- `E:\Compilers\AviSynth+.rar` is a machine-local safety snapshot created after the Windows reinstall. It is intentionally not tracked by Git.
- `docs\AviSynth-QTGMC-Preserved-Payload.sha256` records the SHA-256 hashes of the recovery evidence, core custom plugins, and safety archive as captured on 2026-08-23.

At that point, the preserved `unins000.exe` belonged to the previous Windows installation and was not safe to run.

## Windows 11 Recovery Result

Recovery completed interactively on 2026-08-25:

- Official installer: `D:\Programs\Video\AviSynthPlus_3.7.5_20250420_vcredist.exe`
- Installer size: `41,243,460` bytes
- Installer SHA-256: `465A42E0157EE2A6A109099A4F2E61D1BE003ECC28FAF4A837AB2F07133FC6F9`
- Provenance: the local file's size and SHA-256 matched the official GitHub v3.7.5 release asset downloaded directly into a memory-only hash stream.
- Installer destination: `E:\Compilers\AviSynth+`
- Components: `main`, `main\avs32`, `main\avs64`, `associations`, `associations\openwithnotepad`
- Elevation/EULA: the installer ran elevated; the user reviewed and accepted the interactive legal/setup choices.
- New setup evidence: `E:\Compilers\AviSynth+\Setup Log 2026-08-25 #001.txt`
- New setup-log SHA-256: `9A1FE7B1B747803B363FB899CAB0920783952C00CD57469FEDF85F70940FD7EB`
- Installer result: installation succeeded and no restart was requested.
- VC redistributables: both bundled installers returned `1638`, meaning an equal or newer product was already installed. AviSynth and all downstream runtime gates succeeded.

Installed runtime state:

| Item | Verified state |
| --- | --- |
| x64 runtime | `C:\Windows\System32\AviSynth.dll`, version 3.7.5, SHA-256 `8F7D07917E4B364DF5FD7F1B8B3C1E135465D73325F8D25BC4354DD6435AFAB4` |
| x86 runtime | `C:\Windows\SysWOW64\AviSynth.dll`, version 3.7.5, SHA-256 `E91A9E1CD0952D23011DF316E27E047AD175D1AD2FDE9442470C362D5F7010EF` |
| x64 plugin registration | `HKLM\Software\AviSynth`: `plugins64` and `plugins64+` |
| x86 plugin registration | `HKLM\Software\WOW6432Node\AviSynth`: `plugins` and `plugins+` |
| Environment preflight | `READY`, exit code `0` |

Runtime gates passed with FFmpeg 9.0:

1. AviSynth `BlankClip` loaded and rendered.
2. `FFVideoSource` loaded a disposable H.264 sample through the preserved `ffms2.dll`.
3. A controlled interlaced H.264 sample passed the exact encoder recipe: `AssumeTFF()`, `QTGMC(Preset="Slow", TR2=2, FPSDivisor=2)`, and `Prefetch(14)`.
4. The QTGMC result encoded through `h264_nvenc` with AAC audio to a valid 320x240 progressive H.264 MP4. FFmpeg and ffprobe returned exit code `0`.
5. The preserved SHA-256 manifest remained 12/12 clean with zero missing files or mismatches.
6. `E:\Compilers\AviSynth+.rar` remained unchanged and passed a complete 7-Zip archive test (`46` files, `Everything is Ok`).

## Representative Real-Input Golden Baseline

The restored classic Explorer context menu launched the unchanged `Video\video_encode.ps1` against a machine-local `3.mpg` sample on 2026-08-25. The media remains untracked; hashes identify the exact files without adding personal video content to the repository.

| Evidence | Result |
| --- | --- |
| Source | `3.mpg`, 23,157,106 bytes, SHA-256 `082D9FC2918125A120086F13E0634920A72D8A56126ECA41397AB24571F7EE53` |
| Source video | MPEG-2, 720x480, 30000/1001 fps, bottom-field-first |
| Full-file FFmpeg `idet` | Multi-frame: 0 TFF, 1170 BFF, 0 progressive, 0 undetermined |
| Encode settings | QP 22, no resize, GOP 1 second |
| Deinterlace recipe | `AssumeBFF()`, `QTGMC(Preset="Slow", TR2=2, FPSDivisor=2)`, `Prefetch(14)` |
| Output | `3.mp4`, 12,947,491 bytes, SHA-256 `EDC2B74011E990CD6838AECBA85EFCE7AEF2ADD6384A7238E2256FEF18DB2F7B` |
| Output video | H.264, 720x480, 30000/1001 fps, progressive, 1169 decoded frames |
| Output audio | AAC stereo, 48 kHz |
| Duration | Source 39.072367 seconds; output 39.058021 seconds |
| Decode validation | Complete FFmpeg audio/video decode with `-xerror`, exit code `0` |
| Visual acceptance | User reported that the result looked good and completed quickly |

The interactive console transcript was not retained because the run was launched before baseline capture began. The persisted batch settings, independent input analysis, output metadata, hashes, complete decode, and user visual acceptance provide the recovery baseline.

The live `unins000.exe` and `unins000.dat` were replaced by the 2026-08-25 installer and now belong to the current Windows 11 installation. The `.rar` snapshot still contains the old Windows 10 uninstall pair; do not restore those old files over the live installation.

## Recovery Sequence

1. Keep the `.rar` snapshot unchanged until recovery and validation are complete.
2. Download the exact 3.7.5 `_vcredist` installer from the official AviSynth+ release.
3. Verify the downloaded file's Authenticode signature where available and record its SHA-256 hash.
4. Review the installer/EULA interactively. Legal terms must be accepted by the user, never automatically by an agent.
5. Use elevation for the real installer because it writes DLLs and registration under protected Windows locations/HKLM.
6. Reproduce the old component selection initially unless a deliberate x64-only decision is made.
7. Restore only the preserved custom `plugins64+` payload after the base runtime is installed.
8. Run `tools\Test-EncodeEnvironment.ps1` and inspect every failed required check.
9. Perform runtime tests in this order:
   - AviSynth `Version()`/blank clip
   - `FFVideoSource` against a disposable sample
   - QTGMC against a short controlled interlaced sample
   - FFmpeg reading the generated `.avs`
   - the unchanged `Video\video_encode.ps1` against a copy of a representative input
10. Preserve the successful input identity, settings, output metadata, output hash, decode result, and visual acceptance as the golden baseline. The 2026-08-25 representative-input run above completed this recovery gate; its interactive console transcript was not retained.

Parser/static checks and Registry readback are not substitutes for the final media encode test.

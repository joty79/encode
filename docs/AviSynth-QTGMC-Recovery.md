# AviSynth+ / QTGMC Recovery

## Status

This document captures the known-good Windows 10 environment used by the legacy video encoder. The environment has **not yet been restored or runtime-verified on the current Windows 11 installation**.

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

## Current Windows 11 State

Read-only inspection on 2026-08-23 found:

- `E:\Compilers\AviSynth+` and the custom x64 plugins are preserved.
- `C:\Windows\System32\AviSynth.dll` is absent.
- `C:\Windows\SysWOW64\AviSynth.dll` is absent.
- `HKLM\Software\AviSynth` and its 32-bit equivalent are absent.
- FFmpeg 9.0 is installed and was built with `--enable-avisynth`.
- The preserved `E:` directory is therefore a payload/forensic source, not an active AviSynth installation.
- `E:\Compilers\AviSynth+.rar` is a machine-local safety snapshot created after the Windows reinstall. It is intentionally not tracked by Git.

Do not run the preserved `unins000.exe`; its uninstall metadata belongs to the previous Windows installation.

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
10. Preserve the successful input, settings, console transcript, output metadata, and output hash as the golden baseline.

Parser/static checks and Registry readback are not substitutes for the final media encode test.

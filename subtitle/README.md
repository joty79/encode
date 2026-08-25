# Subtitle Workflow Recovery

## Current status — 2026-08-26

The subtitle dependencies and both saved helpers are restored and characterized on
the current Windows 11 installation. Their reviewed Explorer actions are installed
under the current user's `HKCU\Software\Classes` scope.

## Dependencies

| Component | Installed state |
| --- | --- |
| Subtitle Edit GUI | v5.1.0 at `C:\Program Files\Subtitle Edit` |
| Subtitle Edit CLI | SeConv v5.1.0 at `C:\Program Files\Subtitle Edit CLI` |
| MKVToolNix | v101.0 at `C:\Program Files\MKVToolNix` |

Official SeConv recovery evidence:

- Release: `v5.1.0`, published 2026-07-29 by the official
  `SubtitleEdit/subtitleedit` GitHub project.
- Asset: `SeConv-Windows-x64.zip`, preserved locally as
  `D:\Programs\Video\SeConv-Windows-x64-5.1.0.zip`.
- Size: `42,300,410` bytes.
- Official GitHub asset SHA-256:
  `CE081A6C6844D44CB1373EE501A963C9E37C788BF757C2FA0B39821EF9969839`.
- Installed `seconv.exe` SHA-256:
  `B3E419E5294E65A8586662A1786ED14E86F97B9B0207C7C071D295B72953FF88`.
- The ZIP contains the MIT license and five files; no installer or EULA was
  accepted by the agent.
- The binaries are not Authenticode-signed. Trust is anchored to the exact digest
  published by the official GitHub release API.
- Embedded file/product version is `5.1.0.0` / `5.1.0+38f1dd4...`.
  `seconv --version` prints `5.0.0`; this is an upstream banner inconsistency in
  the verified v5.1.0 asset.

Official references:

- <https://github.com/SubtitleEdit/subtitleedit/releases/tag/v5.1.0>
- <https://github.com/SubtitleEdit/subtitleedit/blob/main/docs/reference/command-line.md>

## Saved workflows

### Convert a subtitle file to SRT

```powershell
pwsh -File '.\subtitle\Convert-ToSrt.ps1' -Path 'C:\Path\To\subtitle.vtt'
```

The script preserves the source, refuses an existing `.srt`, converts in a unique
temporary directory, validates the result with SeConv, and only then moves it next
to the source. `Convert-to-SRT.vbs` is the hidden Explorer runner and resolves the
PowerShell script relative to its own location.

### Extract the only text subtitle from MKV

```powershell
pwsh -File '.\subtitle\Extract-MKV-Subtitle.ps1' -MkvFile 'C:\Path\To\video.mkv'
```

The helper uses `mkvmerge -J` to inspect the container, requires exactly one text
subtitle track, and lets SeConv perform a real conversion to SubRip. This fixes the
old behavior that could write ASS or binary subtitle bytes under a false `.srt`
extension. Multiple tracks are refused because the script cannot infer the desired
language. Image tracks such as PGS/VobSub are also refused: OCR requires an explicit
engine/language/database choice and belongs in Subtitle Edit GUI unless a dedicated
workflow is designed later.

Both scripts resolve standard installed paths and do not require MKVToolNix or
SeConv to be added to `PATH`.

## Verification

`tests\Test-SubtitleWorkflows.ps1` passes 28 assertions under PowerShell 7 and
Windows PowerShell 5.1. Coverage includes VTT conversion, SRT collision safety,
single SRT and ASS tracks inside MKV, proof that ASS is converted rather than
renamed, source preservation, and missing/invalid/no-subtitle/multiple-track
failures without partial output.

The two Registry files still contain checkout-specific absolute paths, but no
longer require machine-wide `HKCR` writes. Their exact installed values were read
back after import. Replace the absolute paths in the later installer/context-menu
redesign.

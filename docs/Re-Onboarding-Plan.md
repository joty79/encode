# Encode Re-Onboarding Plan

## Project Classification

The encoding, audio, queue, subtitle, icon, and related helpers are a **known-good legacy core**: they worked for the workflows for which they were created. Age, authorship, and coding style are not evidence that their behavior is wrong.

The video-integrity and MPEG-TS timestamp/repair tooling added in commit `fb33b0d` is a newer diagnostic layer and must be validated independently from the stable encoding core.

## Working Principles

- Restore, prove, document, then improve.
- Preserve existing behavior unless a change is explicitly requested.
- Do not rewrite all scripts at once.
- Treat the clean Windows 11 installation as the clean-machine acceptance environment.
- Separate environment/setup failures from encoding-logic failures.
- Use copies or controlled samples for any workflow that moves or removes source files.

## Current Checkpoint — 2026-08-26

Completed and pushed on `codex/re-onboard-encode`:

- Hardened source cleanup, no-audio moves, inspection tools, the video encoder, and queue failure handling with focused regression coverage.
- Restored AviSynth+ 3.7.5 x86/x64 and the preserved x64 QTGMC/FFMS2 plugin environment on Windows 11.
- Verified the FFmpeg-to-AviSynth-to-QTGMC-to-NVENC path with synthetic media and a representative bottom-field-first MPEG-2 input.
- Recorded the real-input golden baseline, including exact settings, input/output hashes, media metadata, full decode validation, and user visual acceptance.
- Manually restored and runtime-verified the classic Explorer actions for direct video encoding, silent queue addition, and queue execution.
- Verified successful queue cleanup and failed-item retention. Invalid media now stops with a focused ffprobe failure instead of cascading metadata parse errors.
- Parsed all 43 PowerShell sources and passed all thirteen test scripts in both PowerShell 7 and Windows PowerShell 5.1. The required encode environment preflight reports `READY`.
- Restored official Subtitle Edit SeConv v5.1.0 as a separate CLI installation and characterized safe VTT conversion plus single-text-track MKV extraction with 28 assertions in both PowerShell hosts.

Current limitations and remaining work:

- All 19 current `.reg` artifacts were imported on 2026-08-26 for an explicit Windows 11 discovery pass; they are not yet owned by a project installer or uninstaller.
- The `.reg` files still contain machine-specific absolute checkout and icon paths.
- MKVToolNix v101.0 and Subtitle Edit SeConv v5.1.0 are installed at standard project-known paths without requiring `PATH`. ImageMagick v7.1.2-30 uses the verified bundled Limited policy, and its reviewed smart-conversion menu is installed.
- Audio, icon, no-audio, and several launcher paths still need representative runtime/visual characterization even though their Registry entries are now installed.

The `Video` folder review is complete and `Video\Tool-Inventory.md` owns its final
re-onboarding classification. The WMV workflow now uses ASFBin through an installed
`.wmv`-only menu with synthetic runtime evidence, while an irregular user WMV remains
the decisive follow-up; the damaged-H.264 tool remains a characterized terminal-only prototype,
and the empty Inspector files are inert historical scaffolding. Subtitle Edit CLI
recovery and subtitle-helper characterization are complete; their two reviewed
menus are installed machine-wide and visible to Shell enumeration. The installer
milestone remains deferred until the broader context-menu redesign.

## Phases

### 1. Environment Recovery

- Recover and validate FFmpeg, AviSynth+/QTGMC, MKVToolNix, ImageMagick, Subtitle Edit CLI, and any other actually used dependency.
- Record source, version, architecture, install scope, paths, integrity information, and runtime proof.
- Do not import the legacy `.reg` files during this phase.

### 2. Characterization Baseline

- Select representative video, audio, subtitle, icon, and queue inputs.
- Record current prompts, defaults, output names, codecs, metadata, quality, timing, logs, and side effects.
- Preserve golden outputs for behavior comparisons.

### 3. Installation Architecture

- Add one user-facing installer and one matching uninstaller.
- Default to user-scoped Explorer integration under `HKCU\Software\Classes` where technically appropriate.
- Replace hardcoded usernames and checkout paths with installer-owned configuration and `$PSScriptRoot`-relative runtime paths.
- Provide selectable components instead of importing every context menu.
- Detect dependencies before offering any installation action.
- Never accept third-party legal terms automatically.

### 4. Incremental Modernization

Modernize one vertical workflow at a time:

1. Video encode and queue
2. Audio encode and queue
3. Subtitle helpers
4. Icon helpers
5. No-audio helper
6. Recent integrity and TS repair layer

For every slice: characterize, make the smallest useful change, validate syntax, run focused behavior tests, compare against the baseline, then integrate it into installation.

### 5. Clean-Machine Acceptance

- Install selected components on Windows 11.
- Verify exact Registry values and actual Explorer menu behavior.
- Run representative end-to-end workflows.
- Uninstall and prove that only installer-owned files and keys were removed.

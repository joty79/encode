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

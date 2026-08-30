# Context Menu Verification

## Purpose

This is the acceptance checklist for the Windows 11 context-menu discovery pass performed on 2026-08-26. All 19 current `.reg` artifacts were imported. Registry readback and Windows Shell enumeration are supporting evidence; a menu is not visually accepted until it is seen and its launcher is exercised through Explorer.

## Automated Inventory Baseline

`tools\Test-EncodeContextMenus.ps1` now performs a read-only comparison of every
repository `.reg` context-menu tree against the live HKLM/HKCU Registry. It also
discovers installed verbs whose values reference this repository, verifies
referenced launcher paths, and detects missing/extra keys and values inside each
owned tree.

The first 2026-08-29 baseline found 108 repository logical roots and the same
108 live roots. After generating and deploying the complete organized preview,
the current baseline is 139 repository roots and the same 139 live roots, with
zero missing roots, unexpected roots, broken launcher paths, duplicate source
owners, catalog drift, or exact tree/value mismatches. Ninety-three legacy
direct definitions still use `HKEY_CLASSES_ROOT`; they match the current live
state but remain intentionally flagged because the source does not explicitly
declare HKLM versus HKCU ownership.

Regenerate the evidence with:

```powershell
pwsh -File '.\tools\Test-EncodeContextMenus.ps1' -OutputDirectory '.\docs'
```

The generated evidence is `Context-Menu-Inventory.md` plus the detailed
`Context-Menu-Inventory.json`. This proves Registry completeness, not Explorer
rendering; the visual acceptance sections below remain required.

## Installed File Menus

| File type | Expected project actions |
| --- | --- |
| `.mp4` | Add to Audio Queue; Add to Encode Queue; Extract/Convert Audio; Encode video (NVIDIA H.264); MediaInfo; Merge MP4 + SRT → MKV; Recover incomplete MP4; Replace audio (AAC) |
| `.mkv` | Add to Audio Queue; Add to Encode Queue; Extract/Convert Audio; Encode video (NVIDIA H.264); Extract subtitle → SRT; MediaInfo; Remux to MP4 (Safe Mode) |
| `.wmv` | Add to Audio Queue; Add to Encode Queue; Extract/Convert Audio; Encode video (NVIDIA H.264); Join WMV (smart); MediaInfo |
| `.ts` | Add to Audio Queue; Analyze TS timestamps; Extract/Convert Audio; Fix TS → MP4 (No re-encode); MediaInfo |
| `.vtt` | Convert to SRT |
| `.webp` | Convert to `.ico`; Convert WebP (smart) |
| `.avif`, `.heic`, `.heif` | Smart image conversion |
| `.png`, `.jpg`, `.jpeg`, `.bmp` | Convert to `.ico` |
| `.exe` | Extract Exe → ICO |
| Other registered audio/video extensions | Audio conversion/queue actions according to the companion `.reg` files |

The table above was reproduced by Windows Shell verb enumeration after import. The former wildcard `JoinWMVSmart` key is absent; the action is registered only for `.wmv`.

## Installed Folder Menus

Normal folder menus include video/audio queue addition, direct video/audio encoding, smart image conversion, no-audio checking, and Run Audio Queue. Folder-background menus include Run Encode Queue, Run Audio Queue, no-audio checking, and the current-folder variants owned by their `.reg` files.

The TS folder actions are deliberately `Shift`-only:

- Analyze TS timestamps
- Fix TS → MP4 in folder (No re-encode)

Those are the existing direct production verbs. In the organized `Media Tools
[PREVIEW]` cascade, the same selected-folder TS actions are normal entries and
do not require `Shift`, matching the redesign decision.

## Organized Menu Preview

The preview is now generated from `config\MediaTools-Menu.json`; the `.reg` file
is an output, not the layout source of truth. `tools\New-MediaToolsMenu.ps1`
checks launcher paths, validates the 15-child budget, requires `Queues` to be
last, and compares every preview target/verb mapping with the current-direct
inventory before writing anything. The current result covers all 104 legacy
mappings with zero missing, extra, or launcher-command mismatches over 35
explicit HKLM/HKCU roots.

The 2026-08-29 generated preview was elevated-imported without removing any
direct production verb. Exact post-import readback found all 139 combined
source/live roots and zero tree/value mismatches. The `.wmv`, selected-folder,
and folder-background layouts have real Explorer visual passes; other target
types and launcher behavior still require acceptance.

Representative layouts are:

| Target | Root branches, in display order |
| --- | --- |
| `.mp4` | Inspect; Video; Audio; Queues |
| `.ts` | Inspect; TS tools; Audio; Queues |
| `.mkv` | Inspect; Video; Audio; Subtitles; Queues |
| Selected folder | Inspect; Process; TS tools; Queues |
| Folder background | Check audio & move here; TS tools; Queues |
| Desktop background | Run video queue |
| Other video formats | Inspect; Video; Audio; Queues |
| Audio formats | Audio; Queues |
| Image/subtitle/executable formats | Relevant single-purpose branch |

`Queues` is last wherever present. The largest generated popup level has five
visible children, below the project budget of 15. The selected-folder preview previously had
two stale branches (`20_Queues` and `30_TsTools`) left after later revisions
renamed/reordered children under the same root; both were removed and verified
absent. They did not exist when the brand-new folder preview originally failed
to appear and therefore do not explain that incident. The source file now
deletes only its own preview roots before rebuilding them, so repeated imports
cannot preserve old preview children.

A separate fresh-key controlled test proved that an agent-only import can create
a visible nested selected-folder cascade with two visible children. No
user-run import, Explorer restart or `SHChangeNotify` was used. This disproves
the earlier hypothesis that agent-side imports inherently fail to produce
visible context menus. Registry readback remains supporting evidence; the final
preview layout still requires the user's visual acceptance in Explorer.

## Windows 11 Multi-Selection

`Video\Explorer-MultiSelectLimit.reg` sets the per-user `MultipleInvokePromptMinimum` DWORD to decimal 100. This keeps relevant verbs available when more than 15 items are selected. It does not switch between the modern and classic Windows 11 menu.

## Runtime Evidence Already Available

- Video encode/QTGMC, video queue, Inspector, smart image conversion, MKV remux, MP4+SRT merge, TS analysis/remux, and subtitle conversion/extraction have focused runtime evidence recorded in their owning docs/tests.
- WMV join now uses ASFBin. Two synthetic WMV2/WMA2 files were joined through the real interactive script into a 2.153-second ASF/WMV with both streams and a clean full decode.
- **2026-08-29 — `Recover incomplete MP4`: MACHINE-WIDE VISUAL PASS, LAUNCH/ICON PENDING.** The initial per-user deployment passed exact `HKCU`/merged-`HKCR` readback and Shell enumeration but failed the user's real `Shift+F10` screenshot. The canonical artifact was moved to explicit `HKLM\Software\Classes\SystemFileAssociations\.mp4`, imported through the narrow elevated path, and read back exactly through both `HKLM` and merged `HKCR`; the failed `HKCU` key was deleted and verified absent. The user then confirmed that the corrected machine-wide action is visible in the real Explorer menu. Its icon now points to the verified repo-owned `.assets\avidemux.ico`; visual icon rendering and launching the action remain pending.

## Explorer Acceptance Recorded

- **2026-08-29 — First generated background-only layout: VISUAL FAIL; FLATTENED RETEST PENDING.** Exact HKCU and merged-HKCR readback succeeded for both `Directory\Background` and `DesktopBackground`, but the user confirmed that neither `Media Tools [PREVIEW]` parent rendered in the real Explorer menus. Unlike every working preview target and the known-working desktop `System Tools` cascade, both failing roots had no direct command at their first child level; they contained only another submenu. The manifest was changed to put `Check audio & move here` directly under the folder-background root and `Run video queue` directly under the desktop root, then regenerated, elevated-imported and exact-audited with zero tree/value mismatches. Whether Explorer now renders the flattened roots remains pending; Registry success is not counted as visual acceptance.
- **2026-08-29 — Background flattening and icon retests: VISUAL FAIL.** The user supplied a real folder-background screenshot after both controlled revisions. `Run Audio Queue`, `Run Encode Queue`, and the same-HKCU-location `System Tools` cascade are visible, while `Media Tools [PREVIEW]` is absent. Adding a direct first-level command and later adding the exact `System Tools` icon (`imageres.dll,-109`) did not make the preview render; both explanations are rejected. The full evidence packet and the remaining documented-structure question are owned by `docs\Context-Menu-Background-Rendering-Case.md`. No further production-key experiments should occur before the narrow inline-vs-`ExtendedSubCommandsKey` A/B conclusion.
- **2026-08-29 — Generated folder-background preview: VISUAL PASS.** A later direct query found the preview background roots absent, invalidating the premise that the final generated state was still live. The current `.reg` was elevated-imported once, direct readback confirmed the folder-background, desktop-background, and selected-folder roots, and the auditor returned 139/139 live roots with zero exact-tree mismatches. After `SHChangeNotify(SHCNE_ASSOCCHANGED)`, the user supplied a real Explorer screenshot showing `Media Tools [PREVIEW]` on ordinary folder empty space with `Check audio & move here`, `TS tools`, and last-positioned `Queues`. This proves the existing inline cascade model works there; desktop-background visual acceptance and launcher tests remain pending.
- **2026-08-29 — Generated `.wmv` preview layout: VISUAL PASS; LAUNCHERS PENDING.** The user confirmed that `Media Tools [PREVIEW]` is visible on `D:\Users\joty79\Desktop\miu\Test files\New folder (5)\1 - Copy.wmv`, with `Inspect media`, `Video`, `Audio` and last-positioned `Queues` at the root. The `Video` cascade visibly contains `Encode video (NVIDIA H.264)` and `Join WMV (smart / ASFBin)`. `.wmv` was not one of the four targets in the former hand-maintained preview, so this directly proves that a newly generated nested target renders. Launching its actions remains pending.
- **2026-08-26 — `.ts` / Analyze TS timestamps: PASS.** The user launched `Analyze TS timestamps` from Explorer on `D:\Users\joty79\Desktop\1.ts`. The expected script opened with the correct input, identified MPEG-TS/H.264/AAC, analyzed 18,096 video and 28,350 audio packets, reported no gaps, jitter, tiny/backward PTS/DTS, and reached its normal close prompt. This proves the real Explorer launcher path and clean-file diagnostic behavior. It does **not** prove broken-file detection or repair; a genuinely problematic TS is still required for that acceptance.
- **2026-08-27 — TS scan performance: PASS.** The full analyzer (no sampling) processed the current 3.75 GiB Desktop `2.ts` in 5.856 seconds instead of the measured 78.825-second baseline, then scanned `1.ts` and `2.ts` together through folder mode in 5.850 seconds. Both were classified `OK`; this still does not replace a genuinely broken TS detection/repair test.
- **2026-08-27 — TS folder parallelism: PASS.** Four copied `1.ts`/`2.ts` pairs (15.91 GiB total) returned the same eight ordered `OK` results at 1, 2 and 4 whole-file workers. Two production runs measured 21.920–22.322 s, 14.460–14.678 s and 10.499–10.749 s respectively; four workers are the retained default/max. Warm file cache prevented a meaningful cold-disk throughput claim. Synthetic smoke tests prove deterministic output, per-file failure isolation and post-classification moving under PowerShell 7 and Windows PowerShell 5.1.

## Still Requiring Explorer Acceptance

1. Launch the now-visible machine-wide `.mp4` action `Recover incomplete MP4` on the chosen incomplete test file and verify that Windows Terminal remains visible with the correct input/output paths.
2. Visually inspect each remaining representative file menu in the table. `.ts` analysis is accepted.
3. Find a genuinely problematic TS and confirm detection; only then test the no-reencode repair and its output.
4. Confirm normal folder, folder-background, desktop-background, and `Shift`-only TS entries.
5. Exercise each remaining launcher with disposable or specifically chosen inputs; verify output names, prompts, collisions and exit behavior.
6. Select at least 16 disposable files and confirm the intended multi-file queue action remains visible.
7. Record any duplicate, noisy or misplaced preview entries and adjust the manifest before promotion.
8. Confirm the expanded generated `Media Tools [PREVIEW]` cascade on the remaining representative `.mp4`, `.mkv`, `.ts`, audio, image, and desktop-background targets. `.wmv`, selected-folder, and folder-background layouts already have visual passes. Only after the complete pass may the matching direct verbs be removed.

## Edited PowerShell Files Without Context Menus

The following edited tools intentionally have no `.reg` companion in the current repository and were not given new Explorer actions during this pass:

- `Video\Repair-Mp4DisguisedTs.ps1`
- `Video\Verify-VideoIntegrity.ps1`
- `Video\Detect-BadCuts.ps1`
- `Video\Repair-DamagedVideo.ps1`
- Support modules and test scripts listed in `PowerShell-Tool-Guide.md`

This is explicit inventory, not evidence that an installer was forgotten.

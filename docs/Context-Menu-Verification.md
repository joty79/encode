# Context Menu Verification

## Purpose

This is the acceptance checklist for the Windows 11 context-menu discovery pass performed on 2026-08-26. All 19 current `.reg` artifacts were imported. Registry readback and Windows Shell enumeration are supporting evidence; a menu is not visually accepted until it is seen and its launcher is exercised through Explorer.

## Installed File Menus

| File type | Expected project actions |
| --- | --- |
| `.mp4` | Add to Audio Queue; Add to Encode Queue; Extract/Convert Audio; Encode video (NVIDIA H.264); MediaInfo; Merge MP4 + SRT → MKV; Replace audio (AAC) |
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

- Scan and move problem TS files
- Fix TS → MP4 in folder (No re-encode)

## Windows 11 Multi-Selection

`Video\Explorer-MultiSelectLimit.reg` sets the per-user `MultipleInvokePromptMinimum` DWORD to decimal 100. This keeps relevant verbs available when more than 15 items are selected. It does not switch between the modern and classic Windows 11 menu.

## Runtime Evidence Already Available

- Video encode/QTGMC, video queue, Inspector, smart image conversion, MKV remux, MP4+SRT merge, TS analysis/remux, and subtitle conversion/extraction have focused runtime evidence recorded in their owning docs/tests.
- WMV join now uses ASFBin. Two synthetic WMV2/WMA2 files were joined through the real interactive script into a 2.153-second ASF/WMV with both streams and a clean full decode.

## Explorer Acceptance Recorded

- **2026-08-26 — `.ts` / Analyze TS timestamps: PASS.** The user launched `Analyze TS timestamps` from Explorer on `D:\Users\joty79\Desktop\1.ts`. The expected script opened with the correct input, identified MPEG-TS/H.264/AAC, analyzed 18,096 video and 28,350 audio packets, reported no gaps, jitter, tiny/backward PTS/DTS, and reached its normal close prompt. This proves the real Explorer launcher path and clean-file diagnostic behavior. It does **not** prove broken-file detection or repair; a genuinely problematic TS is still required for that acceptance.
- **2026-08-27 — TS scan performance: PASS.** The full analyzer (no sampling) processed the current 3.75 GiB Desktop `2.ts` in 5.856 seconds instead of the measured 78.825-second baseline, then scanned `1.ts` and `2.ts` together through folder mode in 5.850 seconds. Both were classified `OK`; this still does not replace a genuinely broken TS detection/repair test.
- **2026-08-27 — TS folder parallelism: PASS.** Four copied `1.ts`/`2.ts` pairs (15.91 GiB total) returned the same eight ordered `OK` results at 1, 2 and 4 whole-file workers. Two production runs measured 21.920–22.322 s, 14.460–14.678 s and 10.499–10.749 s respectively; four workers are the retained default/max. Warm file cache prevented a meaningful cold-disk throughput claim. Synthetic smoke tests prove deterministic output, per-file failure isolation and post-classification moving under PowerShell 7 and Windows PowerShell 5.1.

## Still Requiring Explorer Acceptance

1. Visually inspect each remaining representative file menu in the table. `.ts` analysis is accepted.
2. Find a genuinely problematic TS and confirm detection; only then test the no-reencode repair and its output.
3. Confirm normal folder, folder-background, desktop-background, and `Shift`-only TS entries.
4. Exercise each remaining launcher with disposable or specifically chosen inputs; verify output names, prompts, collisions and exit behavior.
5. Select at least 16 disposable files and confirm the intended multi-file queue action remains visible.
6. Record any duplicate, noisy or misplaced entries. Organize/group menus only after this visibility and launcher pass.

## Edited PowerShell Files Without Context Menus

The following edited tools intentionally have no `.reg` companion in the current repository and were not given new Explorer actions during this pass:

- `Video\Repair-Mp4DisguisedTs.ps1`
- `Video\Verify-VideoIntegrity.ps1`
- `Video\Detect-BadCuts.ps1`
- `Video\Repair-DamagedVideo.ps1`
- Support modules and test scripts listed in `PowerShell-Tool-Guide.md`

This is explicit inventory, not evidence that an installer was forgotten.

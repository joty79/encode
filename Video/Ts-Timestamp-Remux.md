# TS Timestamp Remux Notes

Αυτό το αρχείο κρατάει τη γνώση από το `1.ts` test.

Σκοπός: να διορθώνουμε προβληματικά MPEG-TS files που παίζουν/κάνουν seek άσχημα στα Windows ή αποτυγχάνουν στο Avidemux MP4 save με errors τύπου:

```text
Too short
The saved video is incomplete.
This may happen as a result of invalid time stamps in the video.
Error -22 ("Invalid argument")
```

## Πρόβλημα

Το MPEG-TS μπορεί να έχει valid streams αλλά κακό timeline:

```text
H.264 video packets
AAC audio packets
PTS/DTS gaps
duplicate or tiny timestamp deltas
non-monotonic DTS risk during MP4 muxing
```

Στο `1.ts`, το payload δεν έδειχνε κλασικό corruption. Το full copy read πέρασε, αλλά το packet scan έδειξε:

```text
video gaps: 51
audio gaps: 42
tiny/duplicate video timestamps: 2
max gap: about 9.6 seconds
```

Αυτό εξηγεί γιατί το `TS -> MP4` μπορεί να έχει laggy seekbar ή γιατί το Avidemux σταματάει πολύ νωρίς.

Στο `2.ts`, το πρώτο analyzer έχασε το πρόβλημα επειδή τα PTS/DTS ήταν monotonic και δεν είχαν tiny duplicates. Το Avidemux όμως πάλι απέτυχε στο direct MP4 save περίπου στο `00:01:25.134`. Το χρήσιμο signal ήταν το video cadence jitter:

```text
video packets: 319932
tiny/backwards PTS/DTS: 0
large gaps: 0
video cadence jitter packets: 166245
jitter ratio: about 52.0%
```

Άρα το `Analyze` δεν πρέπει να κοιτάει μόνο backwards/duplicate timestamps. Για MPEG-TS που θέλουμε Avidemux-safe behavior, πρέπει επίσης να flag-άρει έντονο video cadence jitter ως `PROBLEM`.

## Fix Strategy

Το safe πρώτο fix είναι χωρίς re-encode:

```text
TS
  -> MKV copy remux
  -> MP4 copy remux
  -> optional video packet timestamp repair with ffmpeg setts
  -> faststart MP4
  -> packet timestamp verification
```

Το MKV intermediate αλλάζει το container timing model. Μετά, το MP4 muxer γράφει καθαρότερο index. Το extra `setts` βήμα διορθώνει packets που έχουν ίδιο ή πολύ κοντινό PTS/DTS χωρίς να αλλάξει το encoded H.264 bitstream.

## Saved Script

Το reusable script είναι:

```text
Video\Repair-TsTimestampRemux.ps1
```

Analyze only:

```powershell
pwsh -File '.\Video\Repair-TsTimestampRemux.ps1' `
  -Path 'D:\Users\joty79\Desktop\1.ts' `
  -AnalyzeOnly
```

Repair without re-encoding:

```powershell
pwsh -File '.\Video\Repair-TsTimestampRemux.ps1' `
  -Path 'D:\Users\joty79\Desktop\1.ts' `
  -SkipInputAnalysis
```

By default the repaired file is written as:

```text
<source folder>\_TS_FIXED_MP4\<same base name>.mp4
```

The source `.ts` is kept by default, including context-menu runs. Source deletion is an explicit terminal opt-in:

```powershell
pwsh -File '.\Video\Repair-TsTimestampRemux.ps1' `
  -Path 'D:\Users\joty79\Desktop\1.ts' `
  -SkipInputAnalysis `
  -DeleteSource
```

Even with `-DeleteSource`, deletion is allowed only after FFmpeg verification returns cleanly with no warning/error output and the output timestamp checks are clean. `-DeleteSource` cannot be combined with `-NoVerify`. The older `-KeepSource` switch remains accepted for explicit automation and compatibility, but it now matches the default behavior.

Fast routine repair without pre-scanning the input:

```powershell
pwsh -File '.\Video\Repair-TsTimestampRemux.ps1' `
  -Path 'D:\Users\joty79\Desktop\1.ts' `
  -SkipInputAnalysis
```

Repair an `.mp4` filename that is actually an MPEG-TS container:

```powershell
pwsh -File '.\Video\Repair-Mp4DisguisedTs.ps1' `
  -Path 'D:\Users\joty79\Desktop\1.mp4'
```

This helper first checks the real container. If the file is a normal MP4/MOV-style container, it stops without writing output. If the real container is MPEG-TS, it runs no-reencode `TS -> MKV -> MP4` repair and keeps the source file. It skips the `setts` timestamp rewrite by default because `D:\Users\joty79\Desktop\1.mp4` proved that `setts` can stretch the video duration when an MP4-named MPEG-TS file carries a mismatched cadence.

Folder batch repair for all top-level `.ts` files:

```powershell
pwsh -File '.\Video\Repair-TsTimestampRemux.ps1' `
  -Path 'D:\Users\joty79\Desktop\TsFolder' `
  -SkipInputAnalysis
```

Folder scan that moves hard timestamp-problem `.ts` files into `_TS_TIMESTAMP_PROBLEMS`:

```powershell
pwsh -File '.\Video\Repair-TsTimestampRemux.ps1' `
  -Path 'D:\Users\joty79\Desktop\TsFolder' `
  -AnalyzeOnly `
  -MoveProblemFiles
```

The script keeps codecs with `-c copy`. It does not re-encode video or audio.

## Context Menu

The registry file is:

```text
Video\Repair-TsTimestampRemux.reg
```

It adds two normal `.ts` file actions:

```text
Analyze TS timestamps
Fix TS -> MP4 (No re-encode)
```

It also adds two Shift-only folder actions for top-level `.ts` files (both on a folder and its background, for six Registry locations total):

```text
Scan and move problem TS files
Fix TS -> MP4 in folder (No re-encode)
```

The fix actions write MP4 files into `_TS_FIXED_MP4` using the original base name with only the extension changed to `.mp4`. Context-menu runs keep each source `.ts`. Terminal runs may opt into post-verification deletion with `-DeleteSource`.

The scan action displays every `.ts` file with an `OK`, `WARN`, or `PROBLEM` status. `PROBLEM` means hard timestamp issues such as tiny/duplicate PTS/DTS or backwards timestamps; those files are moved into `_TS_TIMESTAMP_PROBLEMS`.
It also treats heavy video cadence jitter as `PROBLEM`, because `2.ts` proved that monotonic timestamps can still fail strict Avidemux direct MP4 save.

PTS cadence is evaluated in sorted presentation order. FFprobe emits H.264 packets in decode/demux order, where B-frames can naturally make PTS values appear to go backwards; treating that packet ordering as corruption caused healthy H.264 TS files to be moved. DTS monotonicity remains checked in packet order, while duplicate PTS, gaps, and cadence are checked in presentation order.

### Packet-scan performance (2026-08-27)

The timestamp rules did not change, but packet storage and presentation-order sorting were optimized. The old implementation created one PowerShell object per packet and used `Sort-Object`; the current implementation stores PTS/duration values in typed `double` lists and uses native array sorting.

Measured on the current Windows 11 host:

| Input | Packets | Before | After | Improvement |
| --- | ---: | ---: | ---: | ---: |
| Current Desktop `1.ts` (243,420,708 bytes, 10:05.600) | 46,446 | 4.061 s | 0.845 s | 4.8× |
| Current Desktop `2.ts` (4,027,285,804 bytes, 2:46:21.286) | 767,217 | 78.825 s | 5.856 s | 13.5× |
| Folder scan containing both files | 813,663 | approximately 83 s from individual baselines | 5.850 s | approximately 14× |

Both files were classified `OK`. The current `2.ts` has SHA-256 `1D12BDD04999D722EF00B81B28FF63BCD7F4EC94836F4C8D7C93E262D527C80B`, 299,367 video packets and only four cadence deviations. It is not interchangeable with the older historical `2.ts` evidence above, which recorded 319,932 video packets and heavy cadence jitter; the matching filename alone is not fixture identity.

Focused TS safety, smoke and exit-code suites pass under PowerShell 7 and Windows PowerShell 5.1 after the optimization. The scan remains a full packet pass, not sampling, and folder scans remain sequential to avoid unnecessary concurrent disk pressure.

## Known Limits

| Limit | Note |
|-------|------|
| Real broadcast gaps remain | Large missing-time gaps are real discontinuities and cannot disappear without changing timeline/content. |
| Cadence jitter is an Avidemux-risk signal | A file may have no backwards/duplicate timestamps and still fail direct TS-to-MP4 save in Avidemux. |
| Source preservation is the default | The `.ts` source remains unless `-DeleteSource` was explicitly supplied. Deletion additionally requires clean timestamp checks and FFmpeg verification with no warning/error output. |
| `-NoVerify` blocks deletion | `-DeleteSource -NoVerify` is rejected before media processing starts. |
| Not visual repair | This does not fix corrupted frames like the `3.mp4` case. |
| Avidemux/GUI still matters | Packet checks can look clean, but final acceptance is opening/seeking in the target player/editor. |
| Re-encode is last resort | If timestamps still fail after copy remux + setts, only then consider re-encoding affected sections. |
| Existing outputs are preserved | Repair refuses an existing MP4, uses a unique stage filename, and removes only a newly-created partial output after failure. |

## Result From `1.ts`

The best output was:

```text
D:\Users\joty79\Desktop\_TS_FIXED_MP4\1.mp4
```

Verification:

```text
Video codec: h264
Audio codec: aac
Video frames: 433935
Audio packets/frames: 686277
TinyPts: 0
TinyDts: 0
PtsBackwards: 0
DtsBackwards: 0
copy-mode verification: clean
```

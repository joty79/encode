# Damaged Video Repair Notes

Αυτό το αρχείο κρατάει τη γνώση από το prototype repair του `3.mp4`.

Σκοπός του δεν είναι να ισχυριστεί ότι λύσαμε όλα τα corrupted video cases. Σκοπός του είναι να σωθεί καθαρά η μέθοδος που δούλεψε, ώστε να την ξαναχρησιμοποιήσουμε και να τη βελτιώσουμε όταν εμφανιστούν άλλα damaged videos.

## Το Πρόβλημα

Κάποια MP4/H.264 αρχεία φαίνονται φυσιολογικά στο container level:

```text
ffprobe: normal streams
MP4Box: normal movie/track info
Players: often play with concealment
```

Αλλά το H.264 payload μέσα στα video packets έχει χαλασμένα AVCC/NAL data:

```text
Invalid NAL unit size
missing picture in access unit
non-existing PPS
decode/concealment errors
```

Αυτό μπορεί να προκαλέσει:

| Symptom | Γιατί Συμβαίνει |
|---------|-----------------|
| Avidemux crash | Το editor/indexer δεν αντέχει τα invalid NAL packet boundaries. |
| Visual blocks/artifacts | Ο decoder κάνει concealment πάνω σε corrupted reference frames. |
| Player weirdness while seeking | Seek μέσα σε damaged GOP/packet cluster μπορεί να χαλάσει προσωρινά playback state. |
| Remux δεν φτάνει | Το πρόβλημα είναι στο H.264 payload, όχι μόνο στο MP4 index. |

## Τα Δύο Reusable Κομμάτια

### 1. Damage Detector

Ο detector δεν βασίζεται μόνο σε full decode ή οπτικό compare.

Η βασική λογική:

```text
MP4 video packets
  -> read packet payload bytes
  -> parse AVCC 4-byte NAL lengths
  -> mark packets with impossible NAL sizes
  -> map bad packet PTS to time ranges
  -> start slightly earlier
  -> extend to next keyframe
  -> merge nearby clusters
```

Στο `3.mp4`, η καλύτερη πρακτική ρύθμιση ήταν:

```text
StartPadding = 0.75 seconds
MergeGap     = 1.0 seconds
```

Αυτή έπιασε όλα τα manually verified visual-bad frames στο 2m10s test clip, με λίγα extra seconds κομμένα.

### 2. Smart Patch Renderer

Το renderer δεν κάνει full re-encode όλο το αρχείο.

Η βασική λογική:

```text
copy clean before patch
re-encode only clean kept ranges inside damaged patch window
drop detected bad ranges
copy clean after patch
concat final MP4
verify video and audio
```

Το σημαντικό μάθημα: το audio πρέπει να κόβεται με το ίδιο timeline. Στο πρώτο prototype υπήρξε silence bug επειδή ένα μεγάλο audio filter concat δεν κράτησε σωστά όλα τα kept chunks. Η πιο αξιόπιστη λύση ήταν να re-encode γίνονται ξεχωριστά patch keep segments με video + audio μαζί και μετά concat.

## Prototype Result: `3.mp4`

Το damaged region του `3.mp4` ήταν γύρω από:

```text
00:16:40 - 00:18:40
```

Τα manually verified visual-bad ranges μέσα στο 2m10s test clip ήταν:

```text
00:00:09.000 - 00:00:29.600
00:00:32.660 - 00:00:56.600
00:01:05.280 - 00:01:08.600
00:01:52.260 - 00:01:53.000
```

Ο detector πρότεινε συντηρητικά:

```text
00:00:09.000 - 00:00:30.005
00:00:32.000 - 00:00:57.005
00:01:05.000 - 00:01:09.005
00:01:52.000 - 00:01:53.405
```

Στο full original timeline αυτά αντιστοιχούσαν περίπου σε:

```text
00:16:49.000 - 00:17:10.005
00:17:12.000 - 00:17:37.005
00:17:45.000 - 00:17:49.005
00:18:32.000 - 00:18:33.405
```

Το τελικό verified output ήταν:

```text
3_smart_repaired_v3_audio_fixed_verified.mp4
```

Validation που πέρασε:

| Check | Result |
|-------|--------|
| Visual review | Τα visible artifacts χάθηκαν. |
| Audio sync review | Δεν παρατηρήθηκε desync. |
| Audio level checks | Non-silent audio after repaired cuts. |
| Audio decode | 0 errors. |
| Video decode around repaired area | 0 errors. |
| NAL/copy verification | 0 errors. |

## Saved Script

Το prototype σώθηκε ως:

```text
Video\Repair-DamagedVideo.ps1
```

Χρήση για detection μόνο:

```powershell
pwsh -File '.\Video\Repair-DamagedVideo.ps1' -Path 'D:\Users\joty79\Desktop\3.mp4' -DetectOnly
```

Χρήση για repair:

```powershell
pwsh -File '.\Video\Repair-DamagedVideo.ps1' `
  -Path 'D:\Users\joty79\Desktop\3.mp4' `
  -OutputPath 'D:\Users\joty79\Desktop\3_fixed.mp4'
```

Dry run:

```powershell
pwsh -File '.\Video\Repair-DamagedVideo.ps1' `
  -Path 'D:\Users\joty79\Desktop\3.mp4' `
  -DryRun
```

## Characterization on the restored Windows 11 machine

The saved implementation was safety-reviewed on 2026-08-25 and remains a
terminal-only prototype. Its executable scope is now deliberately narrow:

- MP4/MOV container with H.264 AVCC and 4-byte NAL lengths only;
- optional audio (video-only input is supported);
- `h264_nvenc` or `libx264` for patch re-encoding;
- source frame timing is retained instead of forcing 50 fps;
- an existing output is refused, the source is never overwritten, and a failed
  repair removes any newly created partial final output;
- the final MP4 must contain exactly one video stream and pass a full FFmpeg
  decode before the script reports success.

The synthetic regression fixture deliberately corrupts the AVCC NAL length of a
known packet at PTS `00:00:00.440`. The test proves exact sub-second range math,
padding to `00:00:00.390`, execution of a real re-encoded patch, audio/video
presence, collision and failure cleanup, video-only support, and strict rejection
of non-H.264 input. It passes under PowerShell 7 and Windows PowerShell 5.1.

Two subtle PowerShell defects were corrected during characterization: casts on
property expressions needed explicit parentheses, and `[Math]::Max(0, value)`
selected an integer overload that rounded sub-second timestamps to zero. The
detector now uses floating-point range math throughout.

Automated structural/decode validation is necessary but cannot judge visual
quality or prove that the detector generalizes to every real corruption pattern.
The workflow therefore stays a prototype until another real damaged sample is
repaired and reviewed visually.

## Required real-video comparison

The hardened script at the repository tip remains the active/default version. Do
not roll it back merely because its behavior changed during the 2026-08-25 audit.
Its synthetic safety coverage found useful correctness defects, but it has not yet
been compared visually against the pre-audit implementation on a new real damaged
video.

When another broken video is available, test both implementations on separate
copies:

| Candidate | Exact reference |
| --- | --- |
| Current hardened script | `Video\Repair-DamagedVideo.ps1` from commit `199c890` or later |
| Pre-edit comparison script | `Video\Repair-DamagedVideo.ps1` from commit `5c202ba` |

The pre-edit snapshot is preserved in two durable forms:

- Git tag: `repair-damaged-video-pre-hardening-2026-08-25`
- Local archive: `D:\Programs\Video\encode-Repair-DamagedVideo-pre-hardening-5c202ba.zip`
- Archive SHA-256:
  `21E44BB3C17388B31AB54164DD7091391A5AC304FFFD205B9CEDD913ABCE94B3`
- Exact pre-edit script Git blob:
  `b252982679caec2db267481a23797c108a22abfd`

Run both only against copies and use different output paths. Compare detected
packet/range boundaries, removed duration, audio continuity and sync, complete
decode results, seeking, and the actual visible artifacts. Record the input hash,
commands, both output hashes, and the visual decision here before promoting the
hardened version beyond prototype status.

## Known Limits

| Limit | Note |
|-------|------|
| Strict H.264/AVC scope | Το script αρνείται οτιδήποτε εκτός MP4/MOV H.264 AVCC με 4-byte NAL lengths. |
| Not visually omniscient | Tiny one-frame visual issues μπορεί να μην είναι worth chasing, ειδικά αν δεν φαίνονται σε realtime playback. |
| Conservative cuts | Καλύτερα να κόψει λίγο παραπάνω παρά να αφήσει visible corruption. |
| Audio matters | Κάθε patch πρέπει να κόβει audio και video με ίδιο timeline. |
| Other videos may need tuning | `StartPadding` και `MergeGap` μπορεί να αλλάξουν ανά corruption pattern. |
| Not final cutter yet | Το smart patch renderer μπορεί αργότερα να γίνει βάση για non-keyframe cutter, αλλά για τώρα είναι damaged-video repair prototype. |

## Future Direction

Το πιθανό τελικό architecture:

```text
Detector
  -> JSON ranges
  -> manual review or auto mode

Smart renderer
  -> copy safe regions
  -> re-encode only patch/boundary regions
  -> preserve audio timeline
  -> concat
  -> verify

Future cutter
  -> use same renderer
  -> re-encode only non-keyframe boundary areas
```

Το σημαντικό είναι να κρατηθούν χωριστά:

```text
detection policy != rendering policy
```

Έτσι μπορούμε να βελτιώνουμε τον detector με νέα damaged videos χωρίς να ξαναγράφουμε το smart rendering engine.

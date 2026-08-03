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

## Known Limits

| Limit | Note |
|-------|------|
| H.264/AVC focus | Το script είναι calibrated για MP4/H.264 AVCC payloads. |
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

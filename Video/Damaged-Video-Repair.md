# Damaged Video Repair Notes

Αυτό το αρχείο κρατάει τη γνώση από το prototype repair του `3.mp4`.

Σκοπός του δεν είναι να ισχυριστεί ότι λύσαμε όλα τα corrupted video cases. Σκοπός του είναι να σωθεί καθαρά η μέθοδος που δούλεψε, ώστε να την ξαναχρησιμοποιήσουμε και να τη βελτιώσουμε όταν εμφανιστούν άλλα damaged videos.

## Πραγματικό repair — 2026-09-03, `test fix\1.mp4`

**Το packet repair είναι μερική ανάκτηση. Ο χρήστης επιβεβαίωσε ότι παραμένουν
freezes, προβληματικό seeking και μεταβαλλόμενο desync.** Το clean decode
παρακάτω δεν αποτελεί επιβεβαίωση ομαλής αναπαραγωγής.

Το νέο sample `D:\Users\joty79\Desktop\test fix\1.mp4` επισκευάστηκε σε
ξεχωριστό `1_smart_repaired.mp4`. Το αρχικό διατηρήθηκε byte-for-byte.
Πρόκειται για διαφορετικό sample από παλιότερες αναφορές σε αρχεία με όνομα
`1.mp4` ή `3.mp4`.

| Έλεγχος | Αποτέλεσμα |
| --- | --- |
| Source | 1,674,885,236 bytes, H.264 Main 1280×720, AAC stereo 48 kHz, διάρκεια 01:22:05.361678 |
| Βλάβη video | 15,419 invalid AVCC packets· 15,418 είναι εξ ολοκλήρου zero-filled |
| Βλάβη audio | 23,707 εξ ολοκλήρου zero-filled AAC packets μέσα στην ίδια περιοχή |
| Conservative detector range | 01:09:17.445789–01:17:54.195267 |
| Πραγματική αφαίρεση | 01:09:17.429122–01:17:54.195267, συνολικά 516.766145 s· το επιπλέον 0.016667 s είναι το μικρότερο από ένα frame τμήμα πριν από το detector range |
| Output | 1,475,248,570 bytes, διάρκεια 01:13:28.595533 |
| Rendering | Δύο stream-copy τμήματα, χωρίς video/audio re-encode σε αυτό το sample |
| Full decode | Ολόκληρο το video και audio πέρασαν, exit `0`, χωρίς error output |
| Αρχικός packet-only έλεγχος | Clean, exit `0`, 0.78 s. Με τον νέο έλεγχο timeline: exit `3`, 247 video gaps |
| Διατήρηση περιεχομένου | Ανεξάρτητη σύγκριση όλων των 114,184 retained video VCL payloads και 177,647 AAC payloads: ίδια με τα αντίστοιχα source packets |
| Χρονισμός | Αυστηρά αυξανόμενα DTS· σταθερό offset ανά retained τμήμα, με συμφωνία audio/video εντός 50 μs |
| Source SHA-256 πριν/μετά | `07BEA36F46884749148C73AC4FC6B263324D8498115FF3FAE42E31FF3265E98D` |
| Output SHA-256 | `8991B4F735EB9F5AF63EA7E5B8EA176A6CB79DEC1E66541C7956E4303FFC9FB1` |

Εντολή του τελικού run, πάνω στο επαληθευμένο αντίγραφο εργασίας:

```powershell
pwsh -NoProfile -File '.\Video\Repair-DamagedVideo.ps1' `
  -Path 'D:\Users\joty79\Desktop\test fix\repair-review-20260903\current-input.mp4' `
  -OutputPath 'D:\Users\joty79\Desktop\test fix\1_smart_repaired.mp4' -KeepTemp
```

Το τελικό run ολοκληρώθηκε σε 35.81 s μαζί με full decode. Ο detector μετά
την αλλαγή αναζήτησης keyframe χρειάστηκε 5.90 s σε ξεχωριστό run. Το αρχικό
αργό detection διακόπηκε χωρίς αποτέλεσμα· δεν υπάρχει ολοκληρωμένος χρόνος
baseline για ισχυρισμό συγκεκριμένου speedup factor.

Διορθώσεις στο reusable script:

- Binary search πάνω σε ταξινομημένα keyframe timestamps, αντί για επαναλαμβανόμενο
  pipeline search για κάθε damaged packet.
- Ρητή εμφάνιση της προγραμματισμένης αφαίρεσης και ακρίβεια χρόνου έξι δεκαδικών.
- Απόρριψη audio preroll με `-copypriorss:a 0`. Το πρώτο repair απέτυχε σωστά
  στο full decode: είχαν αντιγραφεί 17 zero-filled AAC packets πριν από το
  clean video keyframe του δεύτερου τμήματος.
- Presentation-time όριο στα copied video packets μέσω `noise` BSF με μόνο
  `drop` expression, και συμβατό B-frame reordering στα encoded patches.
  Το νέο synthetic B-frame case αποκάλυψε overlapping timestamps που πλέον
  δεν εμφανίζονται σε αυτό το regression.
- Όταν το AAC stream υπερβαίνει το video end κατά περισσότερο από δύο AAC
  frames, το concat duration περιορίζεται στο video end. Στο πραγματικό
  sample το τελευταίο AAC packet του πρώτου κομματιού είχε duration 1.621333 s
  λόγω source gap και αλλιώς πρόσθετε ανεπιθύμητο χρόνο στην ένωση.
  Ο χειρισμός βασίζεται στο [FFmpeg concat duration directive](https://ffmpeg.org/ffmpeg-formats.html#concat).

Τα 40 assertions του `Test-RepairDamagedVideoPrototype.ps1` πέρασαν σε
PowerShell 7 και Windows PowerShell 5.1, με zero-filled A/V cases τόσο χωρίς
B-frames όσο και με B-frames. Το πρώτο copy step στο πραγματικό sample
κατέγραψε input warnings από το όριο ανάγνωσης· το τελικό output πέρασε τους
ξεχωριστούς decode, integrity και payload/timestamp ελέγχους.

Evidence και preview 12 s βρίσκονται στο
`D:\Users\joty79\Desktop\test fix\repair-review-20260903`. Η ένωση βρίσκεται
στο `01:09:17.429` του output, περίπου στα 5.43 s του `join-preview.mp4`.
Το μικρό κενό ήχου πριν από την ένωση προϋπήρχε στον source χρονισμό· δεν
έγινε resynthesis ή time stretching.

**Εκκρεμεί ανθρώπινος οπτικός/ακουστικός έλεγχος.** Δεν εκτελέστηκε η σύγκριση
με το pre-hardening `5c202ba` και δεν έγινε promotion του prototype. Η
επαλήθευση ίδιων payloads/timing αποδεικνύει διατήρηση του υγιούς υλικού,
όχι ανακατασκευή των χαμένων zero-filled δεδομένων.

### Follow-up: μεταβαλλόμενο desync ήδη στον source

Ο χρήστης επιβεβαίωσε ότι περίπου στα 45 λεπτά το `Shift +250 ms` του
Avidemux συγχρονίζει τόσο το αρχικό όσο και το repaired αρχείο, ενώ στην αρχή
και στο τέλος απαιτείται διαφορετική τιμή. Συνεπώς η αφαίρεση corruption
πέτυχε, αλλά το perceptual lip-sync παραμένει ανοικτό: το source-preserving
repair διατήρησε και τον ήδη προβληματικό source συγχρονισμό.

Νέος έλεγχος consecutive PTS έναντι nominal cadence βρήκε 248 video gaps και
254 AAC gaps στο αρχικό, πάνω από nominal packet duration + 50 ms, χωρίς
backwards PTS. Πολλά gaps είναι περίπου 1.6 s ή πολλαπλάσιά του. Η παλιότερη
ένδειξη `gap_count=0` στο `audio-analysis.json` συνέκρινε το επόμενο PTS με
το προηγούμενο **δηλωμένο** packet end· οι δηλωμένες διάρκειες ήδη περιείχαν
τα κενά και επομένως αυτός ο έλεγχος δεν απέκλειε cadence gaps.

Το νέο evidence είναι `repair-review-20260903\sync-timeline-analysis.json`.
Τα gaps είναι παρατηρήσεις χρονισμού, όχι μετρήσεις lip-sync ούτε απόδειξη
ότι μια γραμμική αλλαγή ταχύτητας ή αυτόματο resampling θα λύσει το πρόβλημα.
Πριν επιλεγεί correction curve χρειάζονται τουλάχιστον μετρήσεις Shift με
timestamp στην αρχή και στο τέλος, επιπλέον του γνωστού περίπου 45 min / +250 ms.

### Follow-up: freezes και seeking στο cut

Το πραγματικό αρχείο του νεότερου ελέγχου είναι
`D:\Users\joty79\Desktop\test fix\New folder\1_smart_repaired.mp4`.
Είναι μοντάζ 6:36.393 από διαφορετικά τμήματα του κύριου repaired αρχείου,
όπως επιβεβαιώνουν αντιστοιχίσεις compressed packet payloads στην αρχή,
μέση και τέλος. Τα sampled A/V offsets διατηρούνται μέσα σε περίπου 50 μs.

| Αρχείο | Video gaps | Μεγαλύτερο διάστημα μεταξύ frames | Συνολική υπέρβαση συνήθους video cadence | Audio gaps |
| --- | ---: | ---: | ---: | ---: |
| Κύριο repaired, 01:13:28.596 | 247 | 9.667 s | 602.466 s | 248 |
| Cut, 00:06:36.393 | 25 | 6.433 s | 52.133 s | 27 |

Το cut περνά full video/audio decode χωρίς errors, αλλά στην αρχή το frame
στο 0.766667 s ακολουθείται από το επόμενο στο 4.000000 s. Το πραγματικό
Avidemux log καταγράφει αποτυχημένη αναζήτηση μέσα σε αυτό το κενό και
μετάβαση στο keyframe των 4 s. Δεν βρέθηκαν non-increasing DTS. Η συμπεριφορά
συνάδει με μεγάλα gaps και keyframe seeking, όχι με αποδεδειγμένο backwards
decode timeline. Η εικόνα/αίσθηση κίνησης δεν επαληθεύτηκε με GUI automation.

Τα video/audio gaps δεν συμπίπτουν πάντα. Ανεξάρτητο flattening σε κάθε
stream θα άλλαζε το sync. Remux ή CFR conversion δεν ανακατασκευάζουν
ενδιάμεσες εικόνες που δεν υπάρχουν στο αρχείο. Δεν έγινε νέο retiming ή
αφαίρεση περιεχομένου σε αυτό το follow-up.

Τα `Verify-VideoIntegrity.ps1` και `Repair-DamagedVideo.ps1` χρησιμοποιούν
το shared `lib\MediaTimeline.ps1`: PTS σε presentation order, DTS σε packet
order, median θετικών PTS deltas αντί για inflated packet durations.
Gap warning όταν η διαφορά ξεπερνά `max(0.20 s, 4 × median cadence)`.
Πρόκειται για review heuristic, όχι απόδειξη corruption ή μέτρηση lip-sync.
Duplicate/missing timestamps και ανεπαρκή timing samples επίσης επισημαίνονται.

Exit `3` σημαίνει timeline review, ακόμη κι αν αποθηκεύτηκε decoded repair.
Το recovery διατηρείται. DetectOnly/DryRun με packet damage συνεχίζει να
επιστρέφει `2`. Το integrity tool δίνει προτεραιότητα στο packet corruption
(`2`) και ελέγχει timeline αφού περάσει το packet scan.

Verification: 14 integrity assertions και 44 repair assertions πέρασαν σε
PowerShell 7 και 5.1, συμπεριλαμβανομένων inflated durations, υγιών B-frames,
και διατήρησης recovery με exit `3`. Και τα δύο πραγματικά αρχεία πλέον
επιστρέφουν `3`. Evidence στο `repair-review-20260903`:
`cut-timing-analysis.json`, `cut-source-matches.json`,
`avidemux-cut-freeze-seek.log`, `cut-integrity-with-timeline.log`,
`main-integrity-with-timeline.log`.

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

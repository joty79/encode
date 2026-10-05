# Διάγνωση και επιλογή επισκευής MP4

Το `Repair-Video.ps1` είναι η νέα πειραματική είσοδος για **διάγνωση → κατάλληλη
επισκευή → επαλήθευση**. Τα πραγματικά βίντεο χρησιμοποιούνται ως regression
cases για το εργαλείο. Δεν αντιμετωπίζουμε κάθε αποτυχία decoder ως λόγο να
κόψουμε όλο το αντίστοιχο τμήμα: πρώτα εξετάζουμε μήπως φταίει το container/index.

## Ποιο script χρειάζομαι;

| Σύμπτωμα / εργασία | Εργαλείο | Τι κάνει και τι δεν κάνει |
| --- | --- | --- |
| Δεν ξέρω τι έχει το MP4 | `Repair-Video.ps1` | Αναλύει, προτείνει μόνο αναγνωρισμένη διαδρομή και ζητά επιλογή μέσα στο πρόγραμμα. Άγνωστη βλάβη παραμένει `ManualReview`. |
| Θέλω γρήγορο έλεγχο | `Verify-VideoIntegrity.ps1` | Ελέγχει container/packets και timeline gaps. Δεν αποκωδικοποιεί όλες τις εικόνες ούτε μετρά lip-sync. |
| Θέλω να κόψω χωρίς re-encode | `Detect-BadCuts.ps1 -Cuts ...` | Συγκρίνει συγκεκριμένα timestamps με keyframes. Δεν κάνει το cut. Η υπάρχουσα ανοχή είναι 80 ms, άρα δεν αποτελεί εγγύηση ακριβούς frame alignment ή ασφάλειας κάθε GOP. |
| Θέλω full decode και πληροφορίες scene changes | `Detect-BadCuts.ps1` χωρίς `-Cuts` | Αποκωδικοποιεί με προαιρετικό GPU και δείχνει πρόοδο/diagnostics. Το «live scan» σημαίνει ενημέρωση στο terminal, **δεν περιέχει player ή timeline**. Scene change δεν σημαίνει κατεστραμμένο cut. |
| Έγκυρο index αλλά κατεστραμμένα H.264 packets | `Repair-DamagedVideo.ps1` | Κόβει damaged ranges από A/V και ξανακωδικοποιεί μικρά patches στα όρια. Παραμένει prototype και δεν πρέπει να προηγείται του ελέγχου για shifted data. |
| Ημιτελές download/recording χωρίς τελικό `moov` | `Recover-IncompleteMp4.ps1` | Εξειδικευμένο recovery για το συγκεκριμένο Microsoft H.264 Encoder layout. Το «Incomplete» περιγράφει το αρχείο εισόδου· δεν σημαίνει απλώς ότι το script είναι ημιτελές. Δεν είναι γενικό repair και το reconstructed AAC χρειάζεται ακρόαση. |

## Χρήση της νέας εισόδου

Διαδραστικά, με ερώτηση για το path αν παραλειφθεί:

```powershell
pwsh -File 'D:\Users\joty79\scripts\encode\Video\Repair-Video.ps1'
```

Ή με γνωστό αρχείο:

```powershell
pwsh -File 'D:\Users\joty79\scripts\encode\Video\Repair-Video.ps1' -Path 'E:\sample.mp4'
```

Το πρόγραμμα εξηγεί τη διάγνωση και δίνει επιλογή **repair σε νέο output** ή
**report μόνο**. Το default output είναι `<όνομα>_repaired.mp4`. Αν υπάρχει,
επιλέγεται αυτόματα `_repaired_2.mp4` κ.ο.κ. Ρητό `-OutputPath` που υπάρχει
ήδη απορρίπτεται. Απαιτούνται FFmpeg/ffprobe στο PATH,
PowerShell 7 ή Windows PowerShell 5.1 και τα συνοδευτικά αρχεία `Video\lib`.
Ο C# engine γίνεται compiled με `Add-Type`, χωρίς Python ή downloads.

Για automation:

```powershell
# Διάγνωση μόνο
pwsh -File 'D:\Users\joty79\scripts\encode\Video\Repair-Video.ps1' -Path 'E:\sample.mp4' -AnalyzeOnly

# Αναγνωρισμένο header repair, χωρίς prompt
pwsh -File 'D:\Users\joty79\scripts\encode\Video\Repair-Video.ps1' -Path 'E:\sample.mp4' -Repair

# Ρητή αποδοχή bounded αφαίρεσης A/V για αποδεδειγμένο shifted-data case
pwsh -File 'D:\Users\joty79\scripts\encode\Video\Repair-Video.ps1' -Path 'E:\sample.mp4' -Repair -AllowRangeRemoval -MaxRemovedSeconds 30
```

Τα κοινά actions υπάρχουν στο διαδραστικό πρόγραμμα. Τα flags αποτελούν
automation overrides. Δεν ανοίγει αυτόματα Avidemux ή άλλο player.

## Εμφάνιση και πρόοδος

Το μενού υποστηρίζει Up/Down, Enter, 1/2 και Esc για report μόνο. Χρησιμοποιεί
τον κοινό renderer `%USERPROFILE%\.agent-shared\templates\PS_UI_Blueprint.psm1`.
Το `-NoUI` προσφέρει απλή έξοδο και αριθμητική επιλογή χωρίς αυτό το dependency.
Η οθόνη επιλογής διαχωρίζει αρχείο, προτεινόμενη επισκευή και δύο actions με
περιγραφές. Η ενεργή επιλογή εμφανίζεται ως πλήρης έγχρωμη επιφάνεια με λευκό
κείμενο. Το footer μένει χαμηλά και τα μικρά παράθυρα χρησιμοποιούν compact layout.

Κάθε στάδιο εμφανίζει περιγραφή και χρόνο εκτέλεσης. Οι άμεσες εργασίες FFmpeg
δείχνουν media position, ποσοστό του συγκεκριμένου σταδίου, ταχύτητα, frames/fps
και εκτίμηση υπολοίπου όταν υπάρχουν διαθέσιμα δεδομένα. Το ποσοστό ξεκινά ξανά
σε κάθε στάδιο· δεν είναι συνολική πρόοδος της επισκευής. Στο τέλος του encoding
ακολουθεί πλήρης έλεγχος του output.

Hashing, timeline analysis και οι εσωτερικές εργασίες του παλιού
`Repair-DamagedVideo` εμφανίζουν δραστηριότητα και elapsed time χωρίς επινοημένο
ποσοστό. Το backend παραμένει ανέγγιχτο σε αυτή την αλλαγή UI. Ακόμη και με
`-NoUI`, εμφανίζεται ενημέρωση περίπου ανά 5 s. Τα process timings και τα FFmpeg
progress logs αποθηκεύονται στο report directory.

Τα progress/error/return-value tests πέρασαν σε PowerShell 7 και 5.1. Το κοινό
TUI regression και το `tests/Test-RepairMenuReplay.py` πέρασαν τη διαδοχή πλάτους
120→101→100→99→98→80→60→120 στην ίδια virtual screen, χωρίς wraps, scrolls ή stale
rows. Έγινε επίσης PTY smoke για live progress και Up/Enter επιλογή. Δεν έγινε
Computer Use ή οπτικό Windows Terminal resize με ποντίκι.

Η νέα εκτέλεση του `E:\1.mp4` ολοκληρώθηκε σε περίπου 1:23, με 37 s για AAC
rebuild και 38 s για full A/V decode verification. Σε διπλή δοκιμή 120 s του
ίδιου repaired βίντεο, το auto decoder threading πήρε 4.95–5.00 s, τα 8 threads
6.28 s και τα 4 threads 7.33–7.45 s. Διατηρήθηκαν τα υπάρχοντα defaults και όλοι
οι έλεγχοι· δεν τεκμηριώθηκε ασφαλής επιτάχυνση από αυτό το tuning.
Evidence: `E:\repair-review-20260905\decode-thread-benchmark.json` και
`repair-report-99f75fbd459e4342a4074613526dc1f7` στον ίδιο φάκελο.

## Οι δύο αναγνωρισμένες διαδρομές

### Malformed AAC sample header

Απαιτεί το συγκεκριμένο warning `overread end of atom 'stsd'` μαζί με ελλιπή
AAC configuration. Ελέγχει ότι αποκωδικοποιείται ο αρχικός ήχος και κάνει
video stream-copy + νέο AAC encoding. Επαληθεύει ότι το compressed video
hash παραμένει ίδιο και ότι το output έχει σωστό AAC configuration.

Το AAC re-encode είναι lossy. Η διαδρομή δεν παρουσιάζεται ως lossless recovery
του ήχου ούτε ως λύση κάθε malformed MP4 header.

### Μετατοπισμένα H.264 δεδομένα με διπλό τελικό index

Περιορίζεται σε H.264 AVCC τεσσάρων bytes, χωρίς B-frames, ένα `mdat` και
τελικό `moov`. Βρίσκει μέσα στο `mdat` **μοναδικό byte-identical αντίγραφο**
του τελικού index και παράγει το shift από τη θέση του. Ελέγχει όλα τα indexed
video packets μετά τη χαρτογράφηση, απαιτώντας μεγάλο περιορισμό της βλάβης
σε ένα συνεχόμενο διάστημα έως 30 s και ανακτήσιμα δεδομένα μετά από αυτό.

Δημιουργεί intermediate με μηδενικά placeholders για τα χαμένα bytes. Μετά
καλεί το υπάρχον `Repair-DamagedVideo.ps1`, ελέγχει το πραγματικό πλάνο αφαίρεσης
έναντι `MaxRemovedSeconds` και προχωρά μόνο αν είναι εντός ορίου. Τα placeholders
δεν θεωρούνται ανακτημένο περιεχόμενο. Δεν χρησιμοποιούνται hardcoded offsets,
ονόματα ή hashes των πραγματικών samples στον production detector.

Η παρουσία `moov` bytes από μόνη της δεν αρκεί. Αν δεν υπάρχει μοναδική αντιστοιχία
ή τα νέα offsets δεν επαληθεύονται, το εργαλείο αρνείται αυτόματο realignment.

## Τι σημαίνει επιτυχία

Πριν δημοσιευτεί το τελικό output ελέγχονται probe warnings, αριθμός streams,
video codec/διαστάσεις, αναμενόμενη διάρκεια, full A/V decode, timeline gaps και
timestamp ordering. Το source SHA-256 ελέγχεται ξανά. Το output περνά από staging
και δεν αντικαθιστά existing file. Candidate που αποτυγχάνει παραμένει μόνο στο
report directory για διερεύνηση, χωρίς να δημοσιεύεται ως τελικό repaired.

| Exit | Σημασία |
| --- | --- |
| `0` | Δεν βρέθηκε πρόβλημα στους συγκεκριμένους ελέγχους, ή ολοκληρώθηκε verified repair. Διακρίνονται στο JSON status. |
| `1` | Αποτυχία εκτέλεσης, safety bound ή verification. |
| `2` | Αναγνωρισμένη επισκευή προτάθηκε αλλά δεν εκτελέστηκε. |
| `3` | Άγνωστο πρόβλημα ή timeline που χρειάζεται manual review. |

Το `VerifiedRepair` αφορά τους αυτοματοποιημένους ελέγχους. Δεν αποδεικνύει
perceptual lip-sync, οπτική ποιότητα, ούτε import/seeking σε κάθε editor.
Κάθε run κρατά `repair-report-<id>\report.json` και πλήρη process logs δίπλα
στο output. Τα intermediates μπορεί να είναι μεγάλα και διατηρούνται όσο το
εργαλείο βρίσκεται σε φάση characterization.

## Πραγματικά regression cases — 2026-09-05

| Sample | Διάγνωση | Αυτόματο αποτέλεσμα |
| --- | --- | --- |
| `E:\1.mp4` | Malformed AAC `stsd`, missing AAC configuration. Το Avidemux crash log αποτυγχάνει στην ανάγνωση αυτού του audio atom. | `E:\1_router_test.mp4`: video payload hash ίδιο, AAC ξανακωδικοποιημένο, 16:56.384, clean probe/full decode/timeline. |
| `E:\2.mp4` | Από 5:29.583 το index δείχνει 3,453,630 bytes αργότερα από τα διατηρημένα δεδομένα. Υπάρχει ίδιο embedded και τελικό `moov`. | Realignment μειώνει bad video packets 25,982 → 115. Αφαίρεση περίπου 7.190 s στο 5:28.833–5:36.023. `E:\2_router_test.mp4`: clean probe/full decode/timeline, διατηρείται το υπόλοιπο βίντεο. |

Τα sources διατηρήθηκαν, με hashes στο αντίστοιχο `report.json`:

- `E:\repair-report-7c893c133e0a42339b74ee90c0939556`
- `E:\repair-report-8a97c6af77b34b8a80fa5faca6ceabb1`

Το πρώτο direct patch trial του `2.mp4` εντόπισε διαφορετικά time bases
(`1/90000` copied, `1/12800` patch) και audio rates (44.1 vs 48 kHz).
Το backend πλέον διατηρεί source video timescale, audio rate και channels
στα patches. Η τελική δοκιμή έγινε μέσω του νέου router, με `libx264` patches.

Verification: 20 router assertions και 44 backend assertions πέρασαν σε
PowerShell 7 και 5.1. Οι synthetic fixtures παράγουν διαφορετικό byte shift,
malformed AAC header, healthy input και άγνωστο corruption. Ελέγχονται επίσης
AnalyzeOnly, output collision, source hashes, opt-in για cuts και removal bound.

Ο έλεγχος GUI στο Avidemux διακόπηκε με Esc πριν επαληθευτεί το repaired import.
Δεν υπάρχει claim ότι πέρασε Avidemux playback. Ο χρήστης ζήτησε να προηγείται
ερώτηση πριν από οποιαδήποτε μελλοντική χρήση Computer Use.

## Context menu και playback — κατάσταση 2026-09-05

Το `Recover-IncompleteMp4.ps1` βρίσκεται ήδη στο production manifest και το
live `.mp4` Media Tools tree αντιστοιχεί στο generated Registry tree. Το παλιό
ξεχωριστό `.reg` έχει αποσυρθεί σε retirement notice. Η παλιότερη τεκμηρίωση που
περιγράφει import αυτού του `.reg` δεν είναι η τρέχουσα διαδρομή εγκατάστασης.

Το `Repair-Video` προστέθηκε στο manifest και στο generated `Video\Media-Tools.reg`
ως **Media Tools → Video → Diagnose / Repair MP4** για `.mp4`. Ο χρήστης
επιβεβαίωσε λειτουργική εκτέλεση. Οι αλλαγές UI φορτώνονται στην επόμενη εκτέλεση
από το ίδιο menu action, χωρίς νέο import του `.reg`.

Τα `Repair-DamagedVideo`, `Detect-BadCuts` και `Verify-VideoIntegrity` παραμένουν
χωρίς δική τους νέα καταχώριση. Πιθανή οργάνωση για επόμενο menu pass:

- **Check Video Integrity**: γρήγορος έλεγχος.
- **Advanced → Check Copy Cuts**: χρειάζεται διαδραστική εισαγωγή timestamps.
- **Advanced → Recover Incomplete MP4**: η ειδική Microsoft recovery διαδρομή.

Το `Repair-DamagedVideo` μπορεί να μείνει backend/advanced tool αντί για δεύτερο
ασαφές γενικό «Repair». Η έκθεση στο context menu δεν λύνει το ζήτημα οπτικής
επαλήθευσης: χρειάζεται ξεχωριστό review σε υπάρχον player/editor με timeline,
σύγκριση πριν/μετά στα joins και ακρόαση στην αρχή/μέση/τέλος. Δεν έχει υλοποιηθεί
ενσωματωμένος player ή auto lip-sync ούτε σε αυτά τα τρία παλιότερα scripts.

Ο read-only menu audit βρήκε 3 missing/mismatched folder roots, 9 legacy live
roots και 18 catalog hive-policy mismatches. Δεν έγιναν Registry αλλαγές.
Evidence: `E:\repair-review-20260905\context-menu-audit`.

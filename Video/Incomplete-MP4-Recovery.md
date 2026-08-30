# Incomplete MP4 Recovery

Το `Recover-IncompleteMp4.ps1` ανακτά video και, προαιρετικά, audio από
ένα πολύ συγκεκριμένο είδος ημιτελούς MP4: recording του `Microsoft H.264
Encoder V1.5.3` του οποίου το download σταμάτησε μέσα στο `mdat`, πριν γραφτεί το
τελικό `moov` index.

Δεν είναι generic MP4 repair. Αρνείται healthy MP4, unknown encoder/layout και
αρχεία χωρίς το συγκεκριμένο Microsoft signature.

## Χρήση

```powershell
Set-Location 'D:\Users\joty79\scripts\encode'
pwsh -File '.\Video\Recover-IncompleteMp4.ps1' `
    -Path 'D:\Users\joty79\Desktop\1x.mp4'
```

Το default output είναι `1x_recovered_av.mp4` δίπλα στο source. Για άλλο όνομα:

```powershell
pwsh -File '.\Video\Recover-IncompleteMp4.ps1' `
    -Path 'D:\Users\joty79\Desktop\1x.mp4' `
    -OutputPath 'D:\Users\joty79\Desktop\1x_fixed.mp4'
```

Για τη συντηρητικότερη διαδρομή χωρίς reconstruction του AAC:

```powershell
pwsh -File '.\Video\Recover-IncompleteMp4.ps1' `
    -Path 'D:\Users\joty79\Desktop\1x.mp4' -VideoOnly
```

## Explorer context menu

Το `Recover-IncompleteMp4.reg` εγκαθιστά machine-wide action μόνο για `.mp4`
files και χρειάζεται elevation κατά το import:

```text
Recover incomplete MP4
```

Στα Windows 11 είναι classic static verb και εμφανίζεται με δεξί κλικ → `Show
more options`. Ανοίγει νέο Windows Terminal tab και το κρατά ανοιχτό μετά το
τέλος, ώστε να φαίνεται καθαρά success, rejection ή error. Το αρχικό per-user
deployment έκανε Registry/Shell enumeration αλλά δεν αποδόθηκε στο πραγματικό
Explorer menu· γι' αυτό το canonical artifact χρησιμοποιεί πλέον το ίδιο
machine-wide `SystemFileAssociations` scope με τα ήδη ορατά MP4 actions.
Το menu icon είναι το repo-owned `.assets\avidemux.ico`, αντιγραμμένο
byte-for-byte από το προσωπικό icon library ώστε το installed verb να μην
εξαρτάται από αρχείο εκτός repository.

## Τι κάνει

- Διαβάζει το source μόνο read-only και δεν το διαγράφει ή μετονομάζει.
- Περιορίζει το δηλωμένο αλλά ημιτελές `mdat` στο πραγματικό EOF.
- Εντοπίζει τα length-prefixed H.264 access units και ξαναγράφει raw Annex-B
  H.264 χωρίς re-encode.
- Υπολογίζει πόσα AAC-LC frames ανήκουν ανάμεσα στα video regions από το
  cumulative A/V clock και ανακατασκευάζει ADTS headers.
- Κάνει remux με FFmpeg σε νέο MP4, αρνείται existing output και καθαρίζει
  partial/temp files σε failure.
- Επιβεβαιώνει streams με ffprobe και κάνει full strict decode του recovered
  raw H.264, εκτός αν δοθεί `-NoVerify`.

Χρειάζεται PowerShell 7 x64, Windows Terminal για το Explorer launcher, και
FFmpeg/ffprobe. Το script ελέγχει πρώτα το
`E:\Compilers\ffmpeg\bin` και μετά το `PATH`. Ο binary recovery engine είναι C#
ενσωματωμένο μέσα στο ίδιο `.ps1` και γίνεται compiled in-memory με `Add-Type`
από το .NET runtime του PowerShell. Δεν χρειάζεται Python, Miniconda, `pip`
package ή download κατά την εκτέλεση. Δεν περιλαμβάνει source από το αρχικό
unlicensed recovery prototype που χρησιμοποιήθηκε μόνο για το πρώτο experiment.

## Audio και πραγματικοί περιορισμοί

Χωρίς `moov`, το ακριβές table των AAC sample boundaries έχει χαθεί. Ο engine
μαθαίνει τα συνήθη frame sizes/headers από regions όπου το boundary είναι
βέβαιο και λύνει τα ambiguous regions με constrained search. Αν δεν υπάρχει
plausible header, χρησιμοποιεί timing-based fallback και το αναφέρει.

Γι' αυτό το video μπορεί να είναι `STRICT-CLEAN`, ενώ το audio να αναφέρεται ως
`PLAYBACK-REVIEW`. Αυτό δεν σημαίνει αυτόματα ότι ακούγεται λάθος: το
`1x_recovered_av_test3.mp4` ακούστηκε και συγχρονίστηκε σωστά στο manual test,
παρότι ο strict AAC decoder έβγαζε diagnostics. Με
`-RequireCleanAudioDecode`, οποιοδήποτε τέτοιο diagnostic γίνεται hard failure.

Τα bytes που δεν κατέβηκαν ποτέ δεν μπορούν να ανακτηθούν. Στο `1x.mp4` έλειπαν
περίπου 73 MiB από το δηλωμένο `mdat`, άρα λείπει πραγματικό υλικό από το τέλος,
όχι μόνο το index. Το script απορρίπτει το ημιτελές τελευταίο fragment αντί να
επινοεί περιεχόμενο.

## Επιβεβαιωμένο δείγμα

Στις 2026-08-28, το πραγματικό `D:\Users\joty79\Desktop\1x.mp4` παρήγαγε:

- 19,428 H.264 frames, 1920x1080, 30000/1001 fps,
- 30,385 reconstructed AAC frames και δύο dropped EOF frames,
- MP4 με video και audio streams,
- clean full strict decode του recovered H.264,
- διατηρημένο source,
- self-contained PowerShell output `1x_script_recovered_ps1.mp4` μεγέθους
  2,873,286,350 bytes,
- ακριβώς ίδιο SHA-256 με το ανεξάρτητα δοκιμασμένο Python prototype output:
  `3F43EA628E38162EF6366383DD1591A851906DBA7C60201288D11B618E3CFF04`.

Η τελική αποδοχή του reconstructed audio παραμένει manual listening, όπως και
στο ήδη επιβεβαιωμένο `1x_recovered_av_test3.mp4`.

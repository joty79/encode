<p align="center">
  <img src="https://img.shields.io/badge/Platform-Windows-0078D4?style=for-the-badge&logo=windows&logoColor=white" alt="Platform">
  <img src="https://img.shields.io/badge/Language-PowerShell-5391FE?style=for-the-badge&logo=powershell&logoColor=white" alt="Language">
  <img src="https://img.shields.io/badge/Status-Legacy%20Scripts-orange?style=for-the-badge" alt="Status">
</p>

<h1 align="center">Encode Scripts</h1>

<p align="center">
  <b>Συλλογή παλιών Windows / PowerShell helper scripts για media encoding, audio replacement, subtitle extraction και context-menu workflows.</b><br>
  <sub>PowerShell scripts + .reg integrations για γρήγορες τοπικές media εργασίες.</sub>
</p>

## What's Inside

| Area | Path | Περιγραφή |
|------|------|-----------|
| Video | `Video/` | Video encode/remux/merge scripts, damaged-video repair notes, queue runners και context-menu `.reg` files. |
| Audio | `audio/` | Audio extraction, audio replacement σε MP4, queue tools και context-menu integration. |
| Subtitles | `subtitle/` | Subtitle extraction/conversion helpers για MKV/SRT workflows. |
| Icons | `icons/` | Icon extraction και `.ico` conversion helpers. |
| No Audio | `no_audio/` | Helper για μετακίνηση media χωρίς audio track. |

## Requirements

| Requirement | Details |
|-------------|---------|
| OS | Windows 10/11 |
| Shell | PowerShell 7 recommended |
| Tools | Τα media scripts μπορεί να απαιτούν local tools όπως `ffmpeg`/`ffprobe`, ανάλογα με το script. |
| Interlaced video | Το legacy QTGMC path απαιτεί σωστά registered AviSynth+ και τα preserved x64 QTGMC plugins. Δες `docs/AviSynth-QTGMC-Recovery.md`. |
| Registry | Τα `.reg` files αλλάζουν Windows Explorer context menus και θέλουν προσεκτικό review πριν από import. |
| Subtitle conversion | Τα subtitle helpers χρησιμοποιούν MKVToolNix και το ξεχωριστό official Subtitle Edit `seconv` CLI. Δες `subtitle/README.md`. |

## Usage

Τα scripts είναι legacy και αρκετά από αυτά έχουν δικό τους `.reg` companion για Explorer context menus.

Πριν από εγκατάσταση σε νέο Windows environment, τρέξε το non-mutating preflight και συμβουλέψου το recovery plan:

```powershell
pwsh -File '.\tools\Test-EncodeEnvironment.ps1'
```

Το command επιστρέφει exit code `1` όταν λείπει required dependency, αλλά δεν εγκαθιστά και δεν αλλάζει τίποτα. Η ανακατασκευή του known-good AviSynth+/QTGMC environment βρίσκεται στο `docs/AviSynth-QTGMC-Recovery.md` και το συνολικό project plan στο `docs/Re-Onboarding-Plan.md`.

Για σύντομη περιγραφή κάθε PowerShell script, classification, test evidence και
γνωστό regression risk, δες `docs/PowerShell-Tool-Guide.md`.

Για terminal χρήση, τρέξε πρώτα ένα script με `-?` ή άνοιξέ το για να ελέγξεις parameters και hardcoded paths.

Παράδειγμα 1: Προληπτικός έλεγχος των επιθυμητών σημείων κοπής πριν από το save (τρέχει ακαριαία):
```powershell
Set-Location 'D:\Users\joty79\scripts\encode'
pwsh -File '.\Video\Detect-BadCuts.ps1' -Path 'C:\Path\To\source_video.mp4' -Cuts "01:47", "02:12", "05:56"
```

Παράδειγμα 2: Full decode του αποθηκευμένου αρχείου με χρήση GPU για decode errors. Οι scene transitions σε non-keyframes αναφέρονται μόνο πληροφοριακά και δεν αποδεικνύουν από μόνες τους κακό edit:
```powershell
pwsh -File '.\Video\Detect-BadCuts.ps1' -Path 'C:\Path\To\saved_video.mp4' -UseGPU
```

Παράδειγμα 3: Γρήγορος έλεγχος κοντέινερ και packet/NAL structure χωρίς αποκωδικοποίηση. Δεν αντικαθιστά full decode, αλλά εντοπίζει structural corruptions που μπορεί να απορρίψει το Avidemux:
```powershell
pwsh -File '.\Video\Verify-VideoIntegrity.ps1' -Path 'C:\Path\To\video.mp4'
```

Παράδειγμα 4: Ανίχνευση damaged H.264 ranges και smart repair με re-encode μόνο στα affected patch windows:
```powershell
pwsh -File '.\Video\Repair-DamagedVideo.ps1' -Path 'C:\Path\To\damaged.mp4' -DetectOnly
pwsh -File '.\Video\Repair-DamagedVideo.ps1' -Path 'C:\Path\To\damaged.mp4' -OutputPath 'C:\Path\To\damaged_fixed.mp4'
```

Οι λεπτομέρειες του prototype και τα known limits βρίσκονται στο `Video\Damaged-Video-Repair.md`.

Παράδειγμα 5: Διάγνωση και no-reencode repair για MPEG-TS timestamp προβλήματα που χαλάνε seekbar ή Avidemux MP4 save:
```powershell
pwsh -File '.\Video\Repair-TsTimestampRemux.ps1' -Path 'C:\Path\To\source.ts' -AnalyzeOnly
pwsh -File '.\Video\Repair-TsTimestampRemux.ps1' -Path 'C:\Path\To\source.ts' -SkipInputAnalysis
pwsh -File '.\Video\Repair-TsTimestampRemux.ps1' -Path 'C:\Path\To\source.ts' -SkipInputAnalysis -DeleteSource
pwsh -File '.\Video\Repair-Mp4DisguisedTs.ps1' -Path 'C:\Path\To\looks_like_mp4.mp4'
pwsh -File '.\Video\Repair-TsTimestampRemux.ps1' -Path 'C:\Path\To\Folder' -AnalyzeOnly -MoveProblemFiles
pwsh -File '.\Video\Repair-TsTimestampRemux.ps1' -Path 'C:\Path\To\Folder' -AnalyzeOnly -ScanWorkers 2
pwsh -File '.\Video\Repair-TsTimestampRemux.ps1' -Path 'C:\Path\To\Folder' -SkipInputAnalysis
```

Οι λεπτομέρειες του TS timestamp remux workflow βρίσκονται στο `Video\Ts-Timestamp-Remux.md`.

Το `Video\Repair-TsTimestampRemux.reg` προσθέτει δύο context-menu actions για `.ts` files: `Analyze TS timestamps` και `Fix TS -> MP4 (No re-encode)`. Τα folder actions εμφανίζονται μόνο με Shift: το `Analyze TS timestamps` μετακινεί problem `.ts` files στο `_TS_TIMESTAMP_PROBLEMS`, ενώ `Fix TS -> MP4 in folder (No re-encode)` επεξεργάζεται τα top-level `.ts` files του φακέλου. Το folder analyze χρησιμοποιεί έως 4 independent whole-file workers by default (`-ScanWorkers 1..4`), αλλά εμφανίζει deterministic filename order και απομονώνει τα per-file failures. Το fix γράφει τα MP4 στο `_TS_FIXED_MP4` με ίδιο basename και `.mp4` extension και κρατά το source `.ts` από προεπιλογή. Διαγραφή γίνεται μόνο με ρητό `-DeleteSource`, μετά από clean timestamp checks και clean FFmpeg verification· το `-NoVerify` δεν μπορεί να συνδυαστεί με διαγραφή. Το analyze flag-άρει backwards/duplicate timestamps, μεγάλα gaps και έντονο video cadence jitter που μπορεί να χαλάσει strict Avidemux direct MP4 save.

Το `Video\Repair-Mp4DisguisedTs.ps1` είναι terminal-only helper για `.mp4` files που στην πραγματικότητα είναι MPEG-TS container. Κάνει πρώτα fast container check, σταματάει αν το αρχείο είναι real MP4, και αν είναι disguised TS τρέχει no-reencode `TS -> MKV -> MP4` repair κρατώντας πάντα το source file. Σε αυτό το mode παραλείπει το `setts` timestamp rewrite by default για να μην αλλοιωθεί η πραγματική διάρκεια.

Το `Video\join-wmv-smart.ps1` χρησιμοποιεί ASFBin για confirmed `.wmv` groups και γράφει `<clicked-base>_joined.wmv`. Το Explorer entry περιορίζεται πλέον σε `.wmv`, αρνείται υπάρχον output και ελέγχει ASFBin/ffprobe result. Η επιλογή των related filenames εξακολουθεί να χρειάζεται ανθρώπινη επιβεβαίωση.

Για context-menu χρήση, έλεγξε πρώτα το αντίστοιχο `.reg` file και κάνε import μόνο όταν τα paths δείχνουν στο σωστό local checkout.

## Project Structure

```text
encode/
|-- Video/       # Video encoding, remuxing, merge, queue, inspector tools
|-- audio/       # Audio extraction/replacement and audio queue tools
|-- subtitle/    # Subtitle extraction/conversion helpers
|-- icons/       # Icon extraction/conversion helpers
|-- no_audio/    # No-audio media helper
|-- docs/        # Recovery evidence and re-onboarding plan
|-- tools/       # Non-mutating environment checks
|-- .gitignore   # Runtime/generated files ignored by Git
|-- CHANGELOG.md # Repo-level change history
|-- README.md    # Project overview
`-- PROJECT_RULES.md # Long-lived project notes and guardrails
```

## Notes

<details>
<summary><b>Γιατί αγνοούνται τα queue files;</b></summary>

Τα `queue/*.txt`, `queue/*.log` και `queue/*settings*.json` θεωρούνται runtime state. Δεν πρέπει να μπαίνουν στο initial repo history γιατί αλλάζουν ανά χρήση και μπορεί να περιέχουν τοπικά paths.

</details>

<details>
<summary><b>Τι πρέπει να προσέχουμε στα .reg files;</b></summary>

Τα `.reg` files μπορούν να αλλάξουν Explorer context menus. Πριν από import, χρειάζεται review των registry paths και των target script paths ώστε να μην δείχνουν σε λάθος repo ή παλιό absolute path.

</details>

---

<p align="center">
  <sub>Windows PowerShell media helpers · legacy repo onboarding · local context-menu automation</sub>
</p>

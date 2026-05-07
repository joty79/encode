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
| Video | `Video/` | Video encode/remux/merge scripts, queue runners και context-menu `.reg` files. |
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
| Registry | Τα `.reg` files αλλάζουν Windows Explorer context menus και θέλουν προσεκτικό review πριν από import. |

## Usage

Τα scripts είναι legacy και αρκετά από αυτά έχουν δικό τους `.reg` companion για Explorer context menus.

Για terminal χρήση, τρέξε πρώτα ένα script με `-?` ή άνοιξέ το για να ελέγξεις parameters και hardcoded paths:

```powershell
Set-Location 'D:\Users\joty79\scripts\encode'
pwsh -File '.\Video\video_encode.ps1' -?
```

Για context-menu χρήση, έλεγξε πρώτα το αντίστοιχο `.reg` file και κάνε import μόνο όταν τα paths δείχνουν στο σωστό local checkout.

## Project Structure

```text
encode/
|-- Video/       # Video encoding, remuxing, merge, queue, inspector tools
|-- audio/       # Audio extraction/replacement and audio queue tools
|-- subtitle/    # Subtitle extraction/conversion helpers
|-- icons/       # Icon extraction/conversion helpers
|-- no_audio/    # No-audio media helper
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

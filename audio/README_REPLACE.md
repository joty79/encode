# Replace Audio MP4

**Utility to replace the audio track of an MP4 file with any AAC file in the same folder.**

---

## 🔵 Features

✅ **Smart Audio Selection** - Automatically prioritizes AAC files with matching filename
✅ **Instant Selection** - Single keypress (1-9) to select alternative audio tracks
✅ **Exact Match** - Press ENTER to instantly use `video.aac` for `video.mp4`
✅ **Duration Check** - Auto-detects if audio/video lengths differ by >1s
✅ **Smart Trimming** - Optional auto-trim (`-shortest`) if audio is longer than video
✅ **Loop Mode** - Quickly try different audio tracks for the same video without restarting
✅ **Safe Naming** - Auto-generates unique output names, never overwrites original

---

## 🔵 Usage

### Method 1: Right-Click
1. **Right-click** any `.mp4` file
2. Select **"Replace Audio (AAC)"**
3. Select the AAC file to use from the menu

### Method 2: Drag & Drop
1. **Drag** an `.mp4` file onto `Replace-Audio-MP4.ps1`

### Method 3: Command Line
```powershell
.\Replace-Audio-MP4.ps1 "C:\path\to\video.mp4"
```

---

## 🔵 Interactive Menu

| Key | Action |
|-----|--------|
| **ENTER** | Use "Exact Match" audio (if found) |
| **1-9** | Instantly select alternative audio track |
| **ESC / Q** | Cancel and exit |

---

## 🔵 Output Naming

The script automatically generates clear filenames:

- **Same Name:** `video.mp4` + `video.aac` → `video.audio-replaced.mp4`
- **Different:** `video.mp4` + `track2.aac` → `video-audio-track2.mp4`

---

## 🔵 Installation

1. Place `Replace-Audio-MP4.ps1` in `D:\Users\joty79\scripts\encode\audio\`
2. Run `Replace-Audio-MP4.reg` to add the context menu
   *(Requires paths in .reg file to match script location)*

---

## 🔵 Changelog

### Version 2.0 - 2026-01-25
- **New Feature:** Smart Exact Match detection
- **New Feature:** Instant 1-9 keypress selection
- **New Feature:** Silent ffprobe duration check
- **Improved:** Loop support for multiple replacements
- **Fixed:** Windows Terminal integration

### Version 1.0 - Initial Release
- Basic audio replacement with ffmpeg
- Stream copy mode (no re-encoding)

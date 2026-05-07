# Audio Encoding System

**Utility για μαζική εξαγωγή και μετατροπή ήχου** - Υποστηρίζει input από video files (MP4, MKV, etc) και audio files.

---

## 🔵 Features

✅ **Single File Mode** - Right-click → "Extract/Convert Audio"
✅ **Folder Batch Mode** - Right-click folder → "Extract/Convert Audio" (process all files inside)
✅ **Queue System** - Multi-select files → "Add to Queue" → Run all at once
✅ **Sync-Safe** - Preserves sample rate & uses sync-safe parameters for video workflows
✅ **Smart Logic** - Auto-converts incompatibility codecs (like `pcm_dvd`)
✅ **Organized Output** - Automatic "encoded" subfolder creation

---

## 🔵 Supported Formats

### 📥 Input
- **Video:** .mp4, .mkv, .avi, .mov, .wmv, .mpg, .mpeg, .vob, .webm, .flv, .m2ts, .ts
- **Audio:** .aac, .mp3, .flac, .wav, .ogg, .opus, .m4a, .wma, .ac3, .dts

### 📤 Output Options
1. **Stream Copy (ENTER)** - Lossless extraction (e.g. MP4 → AAC)
2. **AAC** (192 kbps) - Avidemux safe
3. **MP3** (192 kbps) - Universal
4. **AC3** (384 kbps) - DVD/Theater
5. **FLAC** - Lossless archival
6. **WAV** - Uncompressed
7. **Opus** - Modern efficient

---

## 🔵 Usage Guide

### Method 1: Single File / Right-Click
1. **Right-click** any video/audio file
2. Select **"Extract/Convert Audio"**
3. Select format (or press ENTER for default)

### Method 2: Folder Batch
1. **Right-click** a folder containing media
2. Select **"Extract/Convert Audio"**
3. Select format **ONCE**
4. All files in folder will be processed automatically

### Method 3: Queue System (Multi-Select)
1. Select multiple files in Explorer
2. Right-click → **"Add to Audio Queue"**
3. When ready, right-click any folder background → **"Run Audio Queue"**
4. Press **ENTER** to start batch
   - Input format for first item
   - Rest runs automatically

---

## 🔵 Scripts & Components

| File | Purpose |
|------|---------|
| `audio_encode.ps1` | **Core Script** - Handles encoding logic, FFmpeg calls |
| `add_to_audio_queue.ps1` | Adds files to queue with smart duplicate detection |
| `run_audio_queue.ps1` | Queue Manager UI + Batch Processor |
| `queue/batch_settings.json` | Stores your selection for batch mode |

---

## 🔵 Installation

1. **Scripts:** Place all `.ps1` files in `D:\Users\joty79\scripts\encode\audio\`
2. **Registry:**
   - Run `add_to_audio_queue.reg` (Adds "Add to Queue" to files)
   - Run `run_audio_queue.reg` (Adds "Run Audio Queue" to background)
   - Run `audio_encode.reg` (Adds "Extract/Convert" to files)

---

**Version:** 1.0 | **Date:** 2026-01-26

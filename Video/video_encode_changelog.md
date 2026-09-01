# Changelog

All notable changes to the "Video Encode PowerShell Script" will be documented in this file.

## [2026-09-01] - Automatic NVENC/x264 Selection

### Added

- Added `x264` software H.264 as a first-class encoder choice using the benchmarked `CRF 19`, `fast`, High-profile configuration.
- Added a functional NVENC probe which encodes one frame. `Auto` selects NVENC only when this succeeds and otherwise falls back to x264, including on systems without an NVIDIA GPU.
- Added encoder selection to the interactive settings and persisted separate NVENC QP and x264 CRF values for queue runs.
- Added reusable Avidemux x264 and NVENC profiles under `Video\Avidemux-Profiles`.

### Changed

- The existing NVENC `QP 22`, `P5`, High-profile, no-B-frame path remains unchanged.
- Batch settings now resolve relative to the script directory, making the encoder portable to another checkout or laptop.
- Saved encoder values are range-validated before use.

### Verified

- The focused encode/queue contract passes in PowerShell 7 and Windows PowerShell 5.1, including simulated NVENC absence and exact encoder arguments.
- A real two-second x264 script encode produced H.264 High + AAC MP4 and passed strict FFmpeg decode.
- Both Avidemux x264 and NVENC profiles produced H.264 High + AAC MP4 outputs which passed strict FFmpeg decode; Avidemux reported x264 CRF 19, GOP 25 and 3 B-frames.

## [2026-01-26] - Audio Sync & Safety Update (v2.0)

### 🚀 Added

- **Smart Audio Analysis:** Added `Get-AudioSyncAnalysis` function.
  - Detects **Negative Timestamp Offsets** (Start time drift > 60ms).
  - Detects **Duration Mismatch** between Video and Audio streams (> 0.5s).
- **JSON Metadata Parsing:** Replaced legacy parsing with `ffprobe -of json` for accurate stream data extraction.
- **UI Warnings:**
  - **Main Menu:** Displays "Audio Status" with color-coded warnings (Green=OK, Yellow=Risk) *before* encoding starts.
  - **Processing Loop:** Shows real-time audio health checks for every file in the batch queue.

### 🛡️ Fixed (Safety)

- **Auto-Sync Correction:** Added `-avoid_negative_ts make_zero` flag to **ALL** FFmpeg encoding blocks (both QTGMC and Standard paths).
  - This automatically fixes "Audio Delay" issues detected by the analysis tool.
- **Batch Stability:** Verified queue processing with mixed file types (WMV, MPG, MP4) containing various audio codecs (WMA, PCM, AC3).

### 🔄 Changed

- **Script Structure:** Integrated analysis functions into the main workflow without breaking existing QTGMC or Resize logic.
- **Total Line Count:** Script expanded to ~780 lines to accommodate safety checks.

---

## [Previous Versions] - Core Features

### Added

- **Nvidia NVENC Support:** High-performance H.264 encoding (`h264_nvenc`).
- **Avisynth / QTGMC:** Automatic detection of Interlaced content and generation of `.avs` scripts for high-quality deinterlacing.
- **Batch Queue System:** JSON-based queue system to load multiple files or folders.
- **Legacy DVD Support:** Auto-detection of Non-Square Pixels (Anamorphic) and automatic aspect ratio correction for 16:9 NTSC/PAL DVDs.
- **Interactive UI:** Key-based menu for QP, GOP, and Resolution settings.

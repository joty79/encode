# Changelog - Replace-Audio-MP4

## Version 2.0 - 2026-01-25

### 🎯 Major Features

#### Smart Audio Selection

- **Exact Match Detection**: Automatically detects and prioritizes AAC files with matching basename
  - Press ENTER to use exact match (e.g., `video.aac` for `video.mp4`)
  - Number keys (1-9) for instant alternative selection
  - Type multi-digit numbers for >9 alternatives

#### Instant Selection (1-9 Files)

- **Single Keypress Selection**: No ENTER needed for 1-9 alternatives
- **Visual Feedback**: Numbers display as you type for >9 files
- **Backspace Support**: Delete digits before submitting

#### Duration Check

- **Silent ffprobe Check**: Automatic duration verification (~100ms)
- **Mismatch Warning**: Alert when video/audio differ by >1 second
- **Smart Trimming**: Optional `-shortest` flag to preserve video duration
- **User Choice**: ENTER to proceed or ESC to reselect audio

#### Multi-File Workflow

- **Continuous Processing**: Process multiple audio replacements for same video
- **Loop Support**: Press ENTER after success to select different audio
- **Clean Interface**: Header displays once, selections loop smoothly

---

### ✨ UX Improvements

#### Universal ESC Support

- **Instant Cancel**: ESC key works everywhere (no ENTER needed)
- **Q Alternative**: Q key also cancels (for muscle memory)
- **Consistent Behavior**: Same cancel logic across all prompts

#### Error Handling

- **Restart on Invalid**: Invalid selections restart selection (no exit)
- **No Pause Prompts**: Clean flow without "Press Enter to continue"
- **Smart Validation**: Proper int casting for numeric comparisons

#### Output Naming

- **Smart Naming**: 
  - Same name: `video.audio-replaced.mp4`
  - Different: `video-audio-{audioname}.mp4`
- **Clear Identification**: Output name shows which audio was used

---

### 🔧 Technical Fixes

#### Array Handling

- **Force Array Wrapper**: `@()` wrapper prevents single-item string conversion
- **Consistent Behavior**: Works correctly with 1, 2-9, or 10+ files

#### String vs Int Comparison

- **Proper Casting**: Cast to int before numeric comparisons
- **Fixed Validation**: `$num = $choice -as [int]` before range checks

#### Loop Structure

- **Optimized Placement**: Loop only around AAC selection + encoding
- **No Header Spam**: Validation and video info shown once
- **Variable Reset**: `$audioFile = $null` on each iteration

#### Windows Terminal Integration

- **wt Command**: Opens in Windows Terminal with `wt -w 0`
- **NoExit Flag**: Terminal stays open to see results
- **Path Correction**: Full path includes `scripts\encode\audio\`

---

### 📁 Organization

#### File Structure

```
d:\Users\joty79\scripts\encode\audio\
├── Extract-Audio-MP4.ps1
├── Extract-Audio-MP4.reg
├── Replace-Audio-MP4.ps1
├── Replace-Audio-MP4.reg
└── CHANGELOG.md
```

#### Registry Updates

- Updated paths: `D:\Users\joty79\encode\` → `D:\Users\joty79\scripts\encode\audio\`
- Custom icons: `d:\Users\joty79\Documents\Icons\ffmpeg.ico`
- Windows Terminal: Uses `wt -w 0 pwsh -NoExit`

---

### ⚡ Performance

- **ffprobe Checks**: ~100-400ms total overhead
- **Silent on Match**: No interruption when durations align
- **Copy Mode**: Fast stream copy (no re-encoding)

---

### 🐛 Bug Fixes

1. **Array Single-Item Bug**: Fixed PowerShell quirk where single item becomes string
2. **String Comparison Bug**: Fixed validation failing on multi-digit numbers
3. **Loop Structure Bug**: Prevented header/validation repetition
4. **ESC Key Bug**: Fixed Read-Host not detecting ESC key
5. **Variable Scope Bug**: Reset `$audioFile` on each loop iteration

---

### 📝 Breaking Changes

- **Path Change**: Scripts moved from `encode\` to `encode\audio\`
- **REG Files**: Must re-import registry files with updated paths
- **Terminal**: Now opens in Windows Terminal (requires WT installed)

---

### 🔮 Future Enhancements

- [ ] Batch processing multiple MP4 files
- [ ] Audio format conversion (MP3 → AAC)
- [ ] Volume normalization option
- [ ] Metadata preservation

---

## Version 1.0 - Initial Release

- Basic audio replacement with ffmpeg
- AAC file selection
- Stream copy mode (no re-encoding)
- Context menu integration

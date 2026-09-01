# Avidemux H.264 profiles

These profiles mirror the defaults in `Video/video_encode.ps1` for Avidemux 2.8.1.

- `Encode x264 CRF 19 Fast`: software H.264, CRF 19, `fast` preset, High profile, 3 B-frames, 25-frame GOP.
- `Apply Encode NVENC QP 22 P5`: NVIDIA H.264, constant QP 22, P5-equivalent preset, High profile, no B-frames, 25-frame GOP.

The x264 JSON belongs in `%APPDATA%\avidemux\pluginSettings\x264\3` for the normal Qt GUI. Avidemux CLI uses the sibling `x264\1` directory. The two TinyPy scripts belong in `%APPDATA%\avidemux\custom` and appear in Avidemux's **Custom** menu after restarting the program.

The fixed 25-frame GOP is one second at 25 fps. Unlike `video_encode.ps1`, an Avidemux saved profile cannot calculate a different GOP from each source frame rate automatically.

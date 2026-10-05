"""Replay menu-frames.json from Test-RepairVideoProgress on one pyte screen.

Uses the pyte/wcwidth wheels verified by the canonical shared TUI test.
Pass the generated manifest path as the sole argument; no media is accessed.
"""
import json
from pathlib import Path
import re
import sys

import pyte
from wcwidth import wcswidth

ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")


class TrackingScreen(pyte.Screen):
    def __init__(self, columns, lines):
        super().__init__(columns, lines)
        self.scrolls = 0

    def index(self):
        bottom = self.lines - 1 if self.margins is None else self.margins.bottom
        at_bottom = self.cursor.y == bottom
        super().index()
        self.scrolls += int(at_bottom)


frames = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
screen = TrackingScreen(frames[0]["width"], frames[0]["height"])
stream = pyte.Stream(screen)
for item in frames:
    screen.resize(lines=item["height"], columns=item["width"])
    expected = ANSI.sub("", item["text"]).splitlines()
    assert all(wcswidth(line) < item["width"] for line in expected), "Wrapped row"
    # Same home + row erase + trailing erase protocol as Write-UiFrame.
    stream.feed("\x1b[H" + item["text"] + "\x1b[J")
    assert screen.scrolls == 0, "Viewport scrolled"
    actual = [line.rstrip() for line in screen.display]
    expected_screen = [line.rstrip() for line in expected] + [""] * (item["height"] - len(expected))
    assert actual == expected_screen, f"Width {item['width']}: stale, wrapped or missing content: {[(n, a, b) for n, (a, b) in enumerate(zip(actual, expected_screen)) if a != b]}"
    assert sum("MP4 DIAGNOSE / REPAIR" in line for line in actual) == 1, "Duplicate header"
    assert 0 <= screen.cursor.x < item["width"] and 0 <= screen.cursor.y < item["height"], "Cursor outside viewport"
print("PASS: repair menu 120->101->100->99->98->80->60->120 on one VT screen; no wraps, scrolls or stale rows.")

"""JSON-lines bridge between Sample-Twin.ps1 and the Synthetic Sample Library.

The library itself is used unmodified: it is imported from its delivered folder.
Every stdout line is one JSON event: progress, result or error. A "cancel" line
on stdin sets the library's cancel event, which stops the active helper.
"""
import argparse
import json
from pathlib import Path
import sys
import threading


def emit(event, **fields):
    fields["event"] = event
    sys.stdout.write(json.dumps(fields, ensure_ascii=True) + "\n")
    sys.stdout.flush()


def watch_stdin(cancel):
    for line in sys.stdin:
        if line.strip() == "cancel":
            cancel.set()
            return


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tool-root", required=True, help="Folder containing library.py")
    parser.add_argument("--helpers", required=True, help="Folder containing ffmpeg and ffprobe")
    sub = parser.add_subparsers(dest="action", required=True)
    p = sub.add_parser("analyze")
    p.add_argument("reference")
    p = sub.add_parser("generate")
    p.add_argument("profile")
    p.add_argument("destination")
    p.add_argument("--seconds", type=float, required=True)
    args = parser.parse_args()

    sys.path.insert(0, str(Path(args.tool_root).resolve()))
    import library  # noqa: E402  (delivered Sample Library, unmodified)

    cancel = threading.Event()
    threading.Thread(target=watch_stdin, args=(cancel,), daemon=True).start()
    try:
        tool = library.Library(args.helpers, cancel=cancel,
                               progress=lambda text: emit("progress", text=text))
        if args.action == "analyze":
            profile = tool.analyze(args.reference)
            emit("progress", text="Checking whether a synthetic twin can be generated…")
            try:
                plan = tool.plan(profile)
                support = {"ok": True, "plan": plan}
            except library.LibraryError as error:
                support = {"ok": False, "reason": str(error)}
            emit("result", kind="analysis", version=library.VERSION,
                 profile=profile, support=support)
        else:
            profile = library.read_json(args.profile)
            profile = profile.get("profile", profile)
            folder, manifest = tool.generate(profile, args.destination, args.seconds)
            emit("result", kind="generated", folder=str(folder), manifest=manifest)
        return 0
    except Exception as error:  # Report every failure; the UI owns presentation.
        emit("error", message=str(error), cancelled=cancel.is_set())
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Publish GPUI-facing WinMint.vector.svg from the vector-only winmint-mark-v2.svg."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "assets/brand/winmint-mark-v2.svg"
DST = ROOT / "assets/brand/WinMint.vector.svg"


def main() -> None:
    t = SRC.read_text(encoding="utf-8")
    stripped = re.sub(r'<path\s+d=""[^>]*/>\s*', "", t, flags=re.I)

    svg_open = (
        '<svg xmlns="http://www.w3.org/2000/svg" id="winmint-mark" '
        'viewBox="0 0 1024 1024" version="1.1" width="100%" height="auto" '
        'role="img" aria-labelledby="title desc">'
    )
    stripped = re.sub(r"<svg[^>]*>", svg_open, stripped, count=1)

    if '<title id="title"' not in stripped:
        svg_i = stripped.find("<svg")
        if svg_i == -1:
            raise SystemExit("No <svg> root found.")
        gt = stripped.find(">", svg_i)
        inject = """

  <title id="title">WinMint mark</title>
  <desc id="desc">Windows-pane grid with mint-leaf facets. Pure-vector mark derived from authoring source winmint-mark-v2.svg (VTracer output; empty path junk removed).</desc>
"""
        stripped = stripped[: gt + 1] + inject + stripped[gt + 1 :]

    # Drop XML preamble so GPUI doesn't need to special-case PI — optional
    # Keep comment attribution from vectorizer near top if present
    stripped = re.sub(
        r"<\?xml[^?]*\?>\s*",
        '',
        stripped,
        count=1,
    )

    DST.write_text(stripped.strip() + "\n", encoding="utf-8")
    print(f"Wrote {DST.relative_to(ROOT)} ({DST.stat().st_size} bytes)")


if __name__ == "__main__":
    main()

# SPDX-License-Identifier: MIT
"""Build GPUI-compatible WinMint mark: vector panes + traced vector leaf (**fallback path**).

For normal product work prefer ``winmint-mark-v2.svg`` → ``publish_vector_mark_from_v2.py``
(``Build-WinMintVectorMark.ps1`` with no switches).

Master ``WinMint.svg`` carries the raster leaf in ``<image href="data:...png...">``.
resvg inside gpui (without raster-images) skips raster ``<image>`` nodes — panes-but-no-leaf.
This morphology-based tracer heals alpha fragments, simplifies the silhouette, and
overwrites ``WinMint.vector.svg`` when you cannot use ``winmint-mark-v2.svg`` yet.

**Preferred** — publish pane+leaf facets from ``winmint-mark-v2.svg``::

    pwsh -NoProfile -File tools/brand/Build-WinMintVectorMark.ps1

**This** script (fallback) — install venv deps, trace from raster-in-WinMint.svg::

    pwsh -NoProfile -File tools/brand/Build-WinMintVectorMark.ps1 -RasterTrace -Bootstrap
    pwsh -NoProfile -File tools/brand/Build-WinMintVectorMark.ps1 -RasterTrace -- --approx 2.75

Manual equivalent for trace mode::

    uv venv tools/brand/.venv
    uv pip install -r tools/brand/requirements-vector.txt --python tools/brand/.venv/Scripts/python.exe
    tools/brand/.venv/Scripts/python.exe tools/brand/build_vector_winmint_mark.py
"""

from __future__ import annotations

import argparse
import base64
import io
import re
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage
from skimage import measure

RE_PNG_URI = re.compile(
    r'href="data:image/png;base64,([^"]+)"',
)


def decode_leaf_png(master_svg_text: str) -> Image.Image:
    m = RE_PNG_URI.search(master_svg_text)
    if not m:
        raise SystemExit(
            'Expected embedded data:image/png;base64,... leaf inside WinMint.svg'
        )
    raw = base64.b64decode(m.group(1))
    return Image.open(io.BytesIO(raw))


def polygon_area(poly_rc: np.ndarray) -> float:
    """Shoelace area; contours from ``find_contours`` use ``(row, col)``."""
    row, col = poly_rc[:, 0], poly_rc[:, 1]
    x, y = col.astype(np.float64), row.astype(np.float64)
    return (
        np.abs(np.dot(x, np.roll(y, -1)) - np.dot(y, np.roll(x, -1))) * 0.5
    )


def build_leaf_mask(alpha: np.ndarray, alpha_floor: int, closing: int) -> np.ndarray:
    """Return boolean mask of the traced leaf silhouette (filled)."""
    if closing < 1 or closing % 2 == 0:
        raise ValueError('closing kernel size must be a positive odd integer')
    core = alpha > alpha_floor
    sel = ndimage.binary_opening(core, structure=np.ones((3, 3)))
    closed = ndimage.binary_closing(sel, structure=np.ones((closing, closing)))
    return ndimage.binary_fill_holes(closed)


def mask_mean_rgb(rgba: np.ndarray, mask: np.ndarray) -> tuple[int, int, int]:
    rgbs = rgba[:, :, :3][mask]
    if rgbs.size == 0:
        return 73, 220, 100
    m = rgbs.astype(np.float64).mean(axis=0)
    return tuple(int(round(v)) for v in m)


def best_contour_polygon_path(
    contours: list[np.ndarray],
    tolerance_px: float,
    min_area: float,
) -> str:
    usable = []
    for c in contours:
        if len(c) < 14:
            continue
        area = polygon_area(c)
        if area < min_area:
            continue
        usable.append((area, c))
    if not usable:
        raise SystemExit(
            'No contours after filtering — widen ``--closing``, lower ``--alpha-floor``, '
            'or tweak ``--min-area``.'
        )
    usable.sort(key=lambda t: -t[0])
    best = usable[0][1]
    approx = measure.approximate_polygon(best, tolerance=tolerance_px)
    verts = approx[:, ::-1]
    parts: list[str] = []
    for i, (x, y) in enumerate(verts):
        parts.append(('M' if i == 0 else 'L') + f'{x:.2f} {y:.2f}')
    parts.append('Z')
    return ' '.join(parts)


def rgb_to_hex(rgb: tuple[int, int, int]) -> str:
    return '#' + ''.join(f'{max(0, min(255, c)):02x}' for c in rgb)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        '--master',
        type=Path,
        default=Path('assets') / 'brand' / 'WinMint.svg',
        help='Input master SVG (pane paths + raster leaf)',
    )
    parser.add_argument(
        '--output',
        type=Path,
        default=Path('assets') / 'brand' / 'WinMint.vector.svg',
        help='Combined vector-only output',
    )
    parser.add_argument(
        '--approx',
        type=float,
        default=1.4,
        help='approximate_polygon tolerance in pixels',
    )
    parser.add_argument(
        '--alpha-floor',
        type=int,
        default=40,
        help='Treat alpha above this threshold as silhouette interior seed',
    )
    parser.add_argument(
        '--closing',
        type=int,
        default=31,
        help='Morphological closing square kernel edge length (odd, px)',
    )
    parser.add_argument(
        '--min-area',
        type=float,
        default=80_000.0,
        help='Reject contours smaller than this (raw image px²)',
    )
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[2]
    master_path = root / args.master if not args.master.is_absolute() else args.master
    out_path = root / args.output if not args.output.is_absolute() else args.output

    closing = args.closing
    if closing % 2 == 0:
        closing += 1

    text = master_path.read_text(encoding='utf-8')
    try:
        cut = text.index('<image id="original-leaf"')
    except ValueError as e:
        raise SystemExit(f'Leaf <image> not found in {master_path}') from e
    preamble = text[:cut].strip().rstrip('\n')
    preamble = preamble.replace(
        '>Windows panes with the original WinMint leaf artwork.<',
        '>Windows-pane grid with a GPUI-compatible vector mint leaf traced from raster master artwork.<',
        1,
    )

    png = decode_leaf_png(text)
    rgba = np.array(png.convert('RGBA'))
    alpha_u8 = rgba[:, :, 3]

    silhouette = build_leaf_mask(
        alpha_u8, alpha_floor=args.alpha_floor, closing=closing
    )
    contours = measure.find_contours(silhouette.astype(np.float64), level=0.5)
    d_path = best_contour_polygon_path(
        contours,
        tolerance_px=float(args.approx),
        min_area=float(args.min_area),
    )
    rgb = mask_mean_rgb(rgba, silhouette)
    fill_hex = rgb_to_hex(rgb)

    leaf_group = (
        f'  <g id="mint-leaf-vector" aria-label="WinMint mint leaf">\n'
        f'    <path class="wm-mint-fill" fill="{fill_hex}" d="{d_path}"/>\n'
        '  </g>'
    )

    assembled = preamble + '\n' + leaf_group + '\n</svg>\n'
    out_path.write_text(assembled, encoding='utf-8')

    print(
        f'Wrote {out_path.relative_to(root)} — fill {fill_hex}, '
        f'silhouette {silhouette.shape[1]}×{silhouette.shape[0]}, '
        f'{len(contours)} raw contour(s)'
    )


if __name__ == '__main__':
    main()

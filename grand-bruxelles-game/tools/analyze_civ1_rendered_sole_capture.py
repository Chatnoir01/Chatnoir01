#!/usr/bin/env python3
"""Measure low-side rendered-foot silhouette motion from PNG evidence.

This is deliberately diagnostic-only. It reads the actual raster produced by Godot,
not the skeleton/bone proxy, and never promotes ground/runtime/visual approval.
Only 8-bit RGB/RGBA non-interlaced PNGs are accepted so unsupported evidence fails closed.
"""
from __future__ import annotations

import json
import struct
import sys
import zlib
from pathlib import Path

PNG_SIG = b"\x89PNG\r\n\x1a\n"
TARGET = (114, 115, 116, 117, 118, 119)
CANDIDATE = (115, 116, 117, 118)


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    return a if pa <= pb and pa <= pc else b if pb <= pc else c


def read_png(path: Path) -> tuple[int, int, list[bytes]]:
    raw = path.read_bytes()
    if not raw.startswith(PNG_SIG):
        raise ValueError("not PNG")
    pos = len(PNG_SIG)
    width = height = color_type = bit_depth = interlace = None
    payload = bytearray()
    while pos + 12 <= len(raw):
        n = struct.unpack(">I", raw[pos : pos + 4])[0]
        kind = raw[pos + 4 : pos + 8]
        data = raw[pos + 8 : pos + 8 + n]
        pos += 12 + n
        if kind == b"IHDR":
            width, height, bit_depth, color_type, _, _, interlace = struct.unpack(">IIBBBBB", data)
        elif kind == b"IDAT":
            payload.extend(data)
        elif kind == b"IEND":
            break
    if not width or not height or bit_depth != 8 or color_type not in (2, 6) or interlace != 0:
        raise ValueError("unsupported PNG format")
    channels = 3 if color_type == 2 else 4
    stride = width * channels
    decoded = zlib.decompress(bytes(payload))
    rows: list[bytes] = []
    prev = bytearray(stride)
    off = 0
    for _ in range(height):
        f = decoded[off]
        off += 1
        src = decoded[off : off + stride]
        off += stride
        cur = bytearray(stride)
        for i, x in enumerate(src):
            a = cur[i - channels] if i >= channels else 0
            b = prev[i]
            c = prev[i - channels] if i >= channels else 0
            if f == 0:
                v = x
            elif f == 1:
                v = (x + a) & 255
            elif f == 2:
                v = (x + b) & 255
            elif f == 3:
                v = (x + ((a + b) // 2)) & 255
            elif f == 4:
                v = (x + _paeth(a, b, c)) & 255
            else:
                raise ValueError("unsupported PNG filter")
            cur[i] = v
        rows.append(bytes(cur))
        prev = cur
    return width, height, rows


def bottom_silhouette(path: Path) -> dict:
    width, height, rows = read_png(path)
    channels = len(rows[0]) // width
    bottom = -1
    xs: list[int] = []
    for y, row in enumerate(rows):
        row_x: list[int] = []
        for x in range(width):
            i = x * channels
            r, g, b = row[i], row[i + 1], row[i + 2]
            # CIV-1 witness renders the body near-white against a grey canonical-ground scene.
            if r >= 220 and g >= 220 and b >= 220:
                row_x.append(x)
        if row_x:
            bottom = y
            xs = row_x
    if bottom < 0 or len(xs) < 20:
        raise ValueError(f"insufficient rendered silhouette pixels in {path}")
    return {
        "bottom_y_px": bottom,
        "bottom_min_x_px": min(xs),
        "bottom_max_x_px": max(xs),
        "bottom_centroid_x_px": sum(xs) / len(xs),
        "bottom_pixel_count": len(xs),
    }


def analyze(capture_dir: Path) -> dict:
    records = []
    for sample in TARGET:
        path = capture_dir / f"left-ground-side-{sample:03d}.png"
        if not path.is_file():
            raise ValueError(f"missing capture {sample}")
        rec = {"sample_index": sample, **bottom_silhouette(path)}
        records.append(rec)
    candidate = [r for r in records if r["sample_index"] in CANDIDATE]
    path_px = sum(
        abs(candidate[i]["bottom_centroid_x_px"] - candidate[i - 1]["bottom_centroid_x_px"])
        for i in range(1, len(candidate))
    )
    bottom_rows = [r["bottom_y_px"] for r in candidate]
    return {
        "schema": "grand-bruxelles-civ1-rendered-sole-silhouette-v1",
        "diagnostic_only": True,
        "source_semantic": "actual_godot_1280x720_low_side_raster",
        "rendered_mesh_aware": True,
        "rendered_sole_contact_claimed": False,
        "ground_contact_claimed": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "player_view_claimed": False,
        "target_samples": list(TARGET),
        "candidate_samples": list(CANDIDATE),
        "candidate_bottom_row_span_px": max(bottom_rows) - min(bottom_rows),
        "candidate_bottom_centroid_path_px": path_px,
        "records": records,
        "verdict": "AMELIORER_RENDERED_SILHOUETTE_MEASURED_CONTACT_NOT_PROMOTED",
    }


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: analyze_civ1_rendered_sole_capture.py CAPTURE_DIR OUT.json", file=sys.stderr)
        return 2
    try:
        report = analyze(Path(sys.argv[1]))
        Path(sys.argv[2]).write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    except Exception as exc:
        print(f"CIV1_RENDERED_SOLE_SILHOUETTE_FAIL: {exc}", file=sys.stderr)
        return 3
    print(
        "CIV1_RENDERED_SOLE_SILHOUETTE_OK "
        f"bottom_span_px={report['candidate_bottom_row_span_px']} "
        f"centroid_path_px={report['candidate_bottom_centroid_path_px']:.3f}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

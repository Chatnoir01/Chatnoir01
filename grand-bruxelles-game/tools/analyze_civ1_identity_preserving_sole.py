#!/usr/bin/env python3
"""Track the same CIV-1 rendered sole across 2/4/8 m rasters.

Diagnostic-only. Unlike the rejected four-row global centroid, this analyzer
segments near-white pixels into horizontal components in a bounded low-foot
band and follows one component by primary-bottom-row anchoring plus spatial
continuity. A distant recovery is never qualified unless the same tracker first
calibrates against the validated primary estimator at 2 m and 4 m.
"""
from __future__ import annotations

import json
import math
import struct
import sys
import zlib
from pathlib import Path

PNG_SIG = b"\x89PNG\r\n\x1a\n"
DISTANCES = (2, 4, 8)
SAMPLES = (115, 116, 117, 118)
BAND_DEPTH = 6
MIN_PRIMARY_PIXELS = 20
MIN_COMPONENT_PIXELS = 6
MAX_TRACK_JUMP_PX = 12.0
MAX_CALIBRATION_PATH_REL_DIFF = 0.25
MIN_DIRECTION_SIGNAL_PX = 0.25


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    return a if pa <= pb and pa <= pc else b if pb <= pc else c


def read_png(path: Path) -> tuple[int, int, list[bytes]]:
    raw = path.read_bytes()
    if not raw.startswith(PNG_SIG):
        raise ValueError("not PNG")
    pos = len(PNG_SIG)
    width = height = bit_depth = color_type = interlace = None
    payload = bytearray()
    while pos + 12 <= len(raw):
        n = struct.unpack(">I", raw[pos:pos+4])[0]
        kind = raw[pos+4:pos+8]
        data = raw[pos+8:pos+8+n]
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
        f = decoded[off]; off += 1
        src = decoded[off:off+stride]; off += stride
        cur = bytearray(stride)
        for i, x in enumerate(src):
            a = cur[i-channels] if i >= channels else 0
            b = prev[i]
            c = prev[i-channels] if i >= channels else 0
            if f == 0: v = x
            elif f == 1: v = (x + a) & 255
            elif f == 2: v = (x + b) & 255
            elif f == 3: v = (x + ((a+b)//2)) & 255
            elif f == 4: v = (x + _paeth(a,b,c)) & 255
            else: raise ValueError("unsupported PNG filter")
            cur[i] = v
        rows.append(bytes(cur)); prev = cur
    return width, height, rows


def _white_xs(row: bytes, width: int) -> list[int]:
    channels = len(row) // width
    out = []
    for x in range(width):
        i = x * channels
        if row[i] >= 220 and row[i+1] >= 220 and row[i+2] >= 220:
            out.append(x)
    return out


def _primary(rows: list[bytes], width: int) -> dict | None:
    bottom = None
    xs: list[int] = []
    for y, row in enumerate(rows):
        row_xs = _white_xs(row, width)
        if row_xs:
            bottom, xs = y, row_xs
    if bottom is None or len(xs) < MIN_PRIMARY_PIXELS:
        return None
    return {"bottom_y_px": bottom, "centroid_x_px": sum(xs)/len(xs), "pixel_count": len(xs)}


def _components(rows: list[bytes], width: int, bottom_y: int) -> list[dict]:
    counts: dict[int, int] = {}
    min_y = max(0, bottom_y - BAND_DEPTH + 1)
    for y in range(min_y, bottom_y + 1):
        for x in _white_xs(rows[y], width):
            counts[x] = counts.get(x, 0) + 1
    if not counts:
        return []
    xs = sorted(counts)
    groups: list[list[int]] = [[xs[0]]]
    for x in xs[1:]:
        if x <= groups[-1][-1] + 1:
            groups[-1].append(x)
        else:
            groups.append([x])
    out = []
    for group in groups:
        pixels = sum(counts[x] for x in group)
        if pixels < MIN_COMPONENT_PIXELS:
            continue
        weighted = sum(x * counts[x] for x in group) / pixels
        out.append({"min_x_px": group[0], "max_x_px": group[-1], "centroid_x_px": weighted, "pixel_count": pixels})
    return out


def choose_component(components: list[dict], anchor_x: float) -> dict:
    if not components:
        raise ValueError("no low-band components")
    ranked = sorted(components, key=lambda c: (0 if c["min_x_px"] <= anchor_x <= c["max_x_px"] else 1, abs(c["centroid_x_px"]-anchor_x), -c["pixel_count"]))
    best = ranked[0]
    if abs(best["centroid_x_px"] - anchor_x) > MAX_TRACK_JUMP_PX:
        raise ValueError("identity component jump exceeds bound")
    return best


def track_distance(capture_dir: Path, distance: int) -> dict:
    frames = []
    last_x = None
    for sample in SAMPLES:
        path = capture_dir / f"civ1-distance-{distance}m-{sample}.png"
        if not path.is_file():
            raise ValueError(f"missing capture d={distance} sample={sample}")
        width, height, rows = read_png(path)
        primary = _primary(rows, width)
        bottom_y = primary["bottom_y_px"] if primary else max(y for y,row in enumerate(rows) if _white_xs(row,width))
        anchor = primary["centroid_x_px"] if primary is not None else last_x
        if anchor is None:
            raise ValueError("cannot seed identity without primary or previous component")
        component = choose_component(_components(rows, width, bottom_y), anchor)
        last_x = component["centroid_x_px"]
        frames.append({"sample_index": sample, "primary": primary, "tracked_component": component})
    xs = [f["tracked_component"]["centroid_x_px"] for f in frames]
    path_px = sum(abs(xs[i]-xs[i-1]) for i in range(1,len(xs)))
    signed = xs[-1]-xs[0]
    primary_frames = [f for f in frames if f["primary"] is not None]
    primary_resolved = len(primary_frames) == len(frames)
    primary_path = None
    primary_signed = None
    if primary_resolved:
        px = [f["primary"]["centroid_x_px"] for f in frames]
        primary_path = sum(abs(px[i]-px[i-1]) for i in range(1,len(px)))
        primary_signed = px[-1]-px[0]
    return {"distance_m": distance, "frames": frames, "tracker_path_px": path_px, "tracker_signed_displacement_px": signed, "primary_resolved": primary_resolved, "primary_path_px": primary_path, "primary_signed_displacement_px": primary_signed}


def _direction_match(a: float, b: float) -> bool:
    return abs(a) >= MIN_DIRECTION_SIGNAL_PX and abs(b) >= MIN_DIRECTION_SIGNAL_PX and ((a > 0) == (b > 0))


def analyze(capture_dir: Path) -> dict:
    results = [track_distance(capture_dir, d) for d in DISTANCES]
    failures = []
    for r in results:
        if r["distance_m"] not in (2,4) or not r["primary_resolved"]:
            continue
        denom = max(r["tracker_path_px"], r["primary_path_px"], 1e-9)
        rel = abs(r["tracker_path_px"] - r["primary_path_px"]) / denom
        direction = _direction_match(r["tracker_signed_displacement_px"], r["primary_signed_displacement_px"])
        r["calibration_path_relative_difference"] = rel
        r["calibration_direction_match"] = direction
        if not direction or rel > MAX_CALIBRATION_PATH_REL_DIFF:
            failures.append({"distance_m": r["distance_m"], "direction_match": direction, "path_relative_difference": rel})
    calibrated = len([r for r in results if r["distance_m"] in (2,4) and r["primary_resolved"]]) == 2 and not failures
    recovered_8m = next(r for r in results if r["distance_m"] == 8)
    qualified_8m = calibrated and not recovered_8m["primary_resolved"]
    return {
        "schema": "grand-bruxelles-civ1-identity-preserving-sole-v1",
        "diagnostic_only": True,
        "distances_m": list(DISTANCES),
        "samples": list(SAMPLES),
        "band_depth": BAND_DEPTH,
        "max_track_jump_px": MAX_TRACK_JUMP_PX,
        "calibration": {"required_distances_m": [2,4], "passed": calibrated, "failures": failures, "max_path_relative_difference": MAX_CALIBRATION_PATH_REL_DIFF},
        "distance_measurements": results,
        "qualified_8m_recovery": qualified_8m,
        "perceptual_2_8m_claimed": False,
        "planted_contact_claimed": False,
        "animation_correction_authorized": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "player_view_claimed": False,
        "verdict": "AMELIORER_IDENTITY_TRACKER_8M_QUALIFIED_NO_PROMOTION" if qualified_8m else "AMELIORER_IDENTITY_TRACKER_UNQUALIFIED_NO_PROMOTION",
    }


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: analyze_civ1_identity_preserving_sole.py CAPTURE_DIR OUT.json", file=sys.stderr); return 2
    try:
        report = analyze(Path(argv[1]))
        Path(argv[2]).write_text(json.dumps(report, indent=2)+"\n", encoding="utf-8")
    except Exception as exc:
        print(f"CIV1_IDENTITY_SOLE_FAIL: {exc}", file=sys.stderr); return 3
    print(f"CIV1_IDENTITY_SOLE_OK calibrated={report['calibration']['passed']} qualified_8m={report['qualified_8m_recovery']}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

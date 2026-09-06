#!/usr/bin/env python3
"""Bridge an under-sampled CIV-1 bottom-row observation without changing semantics.

Diagnostic-only. The validated bottom-most near-white raster row remains the sole
measurement primitive. A sample below the 20-pixel resolution floor may be used
only as a gap bridge when it still has a strong same-row observation and is
bracketed by resolved samples whose centroids bound it. No multi-row/component
fallback is used, and no production/contact/player-view claim is promoted.

A same-row bridge is not automatically credible as a motion-magnitude witness.
For fixed FOV and the same world-space motion, projected raster motion must not
increase when camera distance increases. The report therefore records a separate
fail-closed distance-scale consistency gate.
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
MIN_RESOLVED_PIXELS = 20
MIN_BRIDGE_PIXELS = 15
MAX_BRACKET_OVERSHOOT_PX = 1.0
DISTANCE_SCALE_EPSILON_PX = 1e-9


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


def bottom_row_observation(path: Path) -> dict:
    width, _, rows = read_png(path)
    channels = len(rows[0]) // width
    bottom = -1
    xs: list[int] = []
    for y, row in enumerate(rows):
        row_xs = []
        for x in range(width):
            i = x * channels
            if row[i] >= 220 and row[i+1] >= 220 and row[i+2] >= 220:
                row_xs.append(x)
        if row_xs:
            bottom, xs = y, row_xs
    if bottom < 0:
        raise ValueError(f"no rendered silhouette in {path}")
    return {
        "bottom_y_px": bottom,
        "bottom_min_x_px": min(xs),
        "bottom_max_x_px": max(xs),
        "bottom_centroid_x_px": sum(xs) / len(xs),
        "bottom_pixel_count": len(xs),
        "measurement_resolved": len(xs) >= MIN_RESOLVED_PIXELS,
    }


def bridge_candidate(records: list[dict], index: int) -> tuple[bool, list[str]]:
    reasons: list[str] = []
    cur = records[index]
    if cur["measurement_resolved"]:
        return False, ["already_resolved"]
    if cur["bottom_pixel_count"] < MIN_BRIDGE_PIXELS:
        reasons.append("below_bridge_sampling_floor")
    if index == 0 or index == len(records) - 1:
        reasons.append("not_bracketed")
        return False, reasons
    left, right = records[index-1], records[index+1]
    if not left["measurement_resolved"] or not right["measurement_resolved"]:
        reasons.append("brackets_not_resolved")
    if cur["bottom_y_px"] != left["bottom_y_px"] or cur["bottom_y_px"] != right["bottom_y_px"]:
        reasons.append("bottom_row_changed")
    lo = min(left["bottom_centroid_x_px"], right["bottom_centroid_x_px"]) - MAX_BRACKET_OVERSHOOT_PX
    hi = max(left["bottom_centroid_x_px"], right["bottom_centroid_x_px"]) + MAX_BRACKET_OVERSHOOT_PX
    if not (lo <= cur["bottom_centroid_x_px"] <= hi):
        reasons.append("centroid_outside_bracket")
    return not reasons, reasons


def _path(xs: list[float]) -> float:
    value = sum(abs(xs[i] - xs[i-1]) for i in range(1, len(xs)))
    if not math.isfinite(value):
        raise ValueError("non-finite path")
    return value


def distance_scale_consistency(distance_measurements: list[dict]) -> dict:
    """Require projected motion to be non-increasing as camera distance grows."""
    failures: list[dict] = []
    usable = [
        (d["distance_m"], d["effective_bottom_row_path_px"])
        for d in distance_measurements
        if d["effective_bottom_row_path_px"] is not None
    ]
    for (near_d, near_path), (far_d, far_path) in zip(usable, usable[1:]):
        if far_d <= near_d:
            raise ValueError("distance measurements not strictly increasing")
        if far_path > near_path + DISTANCE_SCALE_EPSILON_PX:
            failures.append({
                "near_distance_m": near_d,
                "far_distance_m": far_d,
                "near_path_px": near_path,
                "far_path_px": far_path,
                "reason": "projected_motion_increased_with_distance",
            })
    return {
        "rule": "effective_bottom_row_path_px_non_increasing_with_distance",
        "epsilon_px": DISTANCE_SCALE_EPSILON_PX,
        "passed": len(usable) == len(DISTANCES) and not failures,
        "failures": failures,
    }


def analyze(capture_dir: Path) -> dict:
    distances = []
    raw_bridges = []
    for distance in DISTANCES:
        records = []
        for sample in SAMPLES:
            path = capture_dir / f"civ1-distance-{distance}m-{sample}.png"
            if not path.is_file():
                raise ValueError(f"missing capture d={distance} sample={sample}")
            records.append({"sample_index": sample, **bottom_row_observation(path)})
        bridged = []
        bridge_failures = []
        effective_xs = []
        all_effective = True
        for i, rec in enumerate(records):
            if rec["measurement_resolved"]:
                rec["bridge_used"] = False
                effective_xs.append(rec["bottom_centroid_x_px"])
                continue
            ok, reasons = bridge_candidate(records, i)
            rec["bridge_used"] = ok
            rec["bridge_reasons"] = reasons
            if ok:
                bridged.append(rec["sample_index"])
                effective_xs.append(rec["bottom_centroid_x_px"])
            else:
                all_effective = False
                bridge_failures.append({"sample_index": rec["sample_index"], "reasons": reasons})
        effective_path = _path(effective_xs) if all_effective and len(effective_xs) == len(records) else None
        if bridged:
            raw_bridges.append(distance)
        distances.append({
            "distance_m": distance,
            "records": records,
            "bridged_samples": bridged,
            "bridge_failures": bridge_failures,
            "effective_bottom_row_path_px": effective_path,
            "all_samples_effective": all_effective,
        })

    scale = distance_scale_consistency(distances)
    scale_consistent_bridges = raw_bridges if scale["passed"] else []
    verdict = (
        "AMELIORER_SAME_ROW_BRIDGE_SCALE_CONSISTENT_NO_PROMOTION"
        if scale_consistent_bridges
        else "AMELIORER_SAME_ROW_BRIDGE_REJECTED_BY_DISTANCE_SCALE_NO_PROMOTION"
        if raw_bridges and not scale["passed"]
        else "AMELIORER_SAME_ROW_GAP_BRIDGE_UNAVAILABLE_NO_PROMOTION"
    )
    return {
        "schema": "grand-bruxelles-civ1-same-row-gap-bridge-v2",
        "diagnostic_only": True,
        "source_semantic": "actual_godot_1280x720_bottom_most_near_white_row",
        "distances_m": list(DISTANCES),
        "samples": list(SAMPLES),
        "min_resolved_pixels": MIN_RESOLVED_PIXELS,
        "min_bridge_pixels": MIN_BRIDGE_PIXELS,
        "max_bracket_overshoot_px": MAX_BRACKET_OVERSHOOT_PX,
        "raw_same_row_bridge_distances_m": raw_bridges,
        "scale_consistent_bridge_distances_m": scale_consistent_bridges,
        "distance_scale_consistency": scale,
        "distance_measurements": distances,
        "motion_magnitude_credible": scale["passed"],
        "perceptual_2_8m_claimed": False,
        "planted_contact_claimed": False,
        "animation_correction_authorized": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "player_view_claimed": False,
        "verdict": verdict,
    }


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: analyze_civ1_same_row_gap_bridge.py CAPTURE_DIR OUT.json", file=sys.stderr)
        return 2
    try:
        report = analyze(Path(argv[1]))
        Path(argv[2]).write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    except Exception as exc:
        print(f"CIV1_SAME_ROW_GAP_BRIDGE_FAIL: {exc}", file=sys.stderr)
        return 3
    print(
        "CIV1_SAME_ROW_GAP_BRIDGE_OK",
        "raw=", report["raw_same_row_bridge_distances_m"],
        "scale_consistent=", report["scale_consistent_bridge_distances_m"],
        "scale_passed=", report["distance_scale_consistency"]["passed"],
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

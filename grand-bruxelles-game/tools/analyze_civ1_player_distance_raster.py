#!/usr/bin/env python3
"""Measure CIV-1 bottom-silhouette motion in the real 2/4/8 m Godot rasters.

Diagnostic-only. Reuses the validated PNG decoder/silhouette primitive and records
under-resolved distances instead of inventing a perceptual or planted-contact PASS.
"""
from __future__ import annotations

import importlib.util
import json
import math
import sys
from pathlib import Path

DISTANCES = (2, 4, 8)
SAMPLES = (115, 116, 117, 118)


def _load_sole_module():
    path = Path(__file__).with_name("analyze_civ1_rendered_sole_capture.py")
    spec = importlib.util.spec_from_file_location("civ1_rendered_sole", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load rendered-sole analyzer")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def analyze(capture_dir: Path) -> dict:
    sole = _load_sole_module()
    distances = []
    for distance in DISTANCES:
        records = []
        error = None
        for sample in SAMPLES:
            path = capture_dir / f"civ1-distance-{distance}m-{sample}.png"
            if not path.is_file():
                raise ValueError(f"missing capture d={distance} sample={sample}")
            try:
                metric = sole.bottom_silhouette(path)
                records.append({"sample_index": sample, **metric})
            except ValueError as exc:
                error = str(exc)
                break
        resolved = error is None and len(records) == len(SAMPLES)
        path_px = None
        bottom_span_px = None
        min_bottom_pixels = None
        if resolved:
            path_px = sum(
                abs(records[i]["bottom_centroid_x_px"] - records[i - 1]["bottom_centroid_x_px"])
                for i in range(1, len(records))
            )
            bottom_span_px = max(r["bottom_y_px"] for r in records) - min(r["bottom_y_px"] for r in records)
            min_bottom_pixels = min(r["bottom_pixel_count"] for r in records)
            if not math.isfinite(path_px):
                raise ValueError("non-finite raster path")
        distances.append({
            "distance_m": distance,
            "measurement_resolved": resolved,
            "measurement_error": error,
            "bottom_centroid_path_px": path_px,
            "bottom_row_span_px": bottom_span_px,
            "min_bottom_pixel_count": min_bottom_pixels,
            "records": records,
        })
    unresolved = [d["distance_m"] for d in distances if not d["measurement_resolved"]]
    return {
        "schema": "grand-bruxelles-civ1-player-distance-raster-analysis-v1",
        "diagnostic_only": True,
        "source_semantic": "actual_godot_1280x720_player_distance_rasters",
        "distances_m": list(DISTANCES),
        "samples": list(SAMPLES),
        "distance_measurements": distances,
        "unresolved_distances_m": unresolved,
        "perceptual_2_8m_claimed": False,
        "planted_contact_claimed": False,
        "animation_correction_authorized": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "player_view_claimed": False,
        "verdict": "AMELIORER_DISTANCE_RASTER_MEASURED_FAIL_CLOSED" if not unresolved else "AMELIORER_DISTANCE_RASTER_UNDER_RESOLVED",
    }


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: analyze_civ1_player_distance_raster.py CAPTURE_DIR OUT.json", file=sys.stderr)
        return 2
    try:
        report = analyze(Path(argv[1]))
        Path(argv[2]).write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    except Exception as exc:
        print(f"CIV1_PLAYER_DISTANCE_ANALYSIS_FAIL: {exc}", file=sys.stderr)
        return 3
    summary = {d["distance_m"]: d["bottom_centroid_path_px"] for d in report["distance_measurements"]}
    print(f"CIV1_PLAYER_DISTANCE_ANALYSIS_OK paths={summary} unresolved={report['unresolved_distances_m']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

#!/usr/bin/env python3
import json
import math
import sys
from pathlib import Path

SCHEMA_IN = "grand-bruxelles-civ1-ground-geometry-windows-v1"
SCHEMA_OUT = "grand-bruxelles-civ1-ground-geometry-phase-minima-v1"


def fail(msg: str) -> None:
    raise ValueError(msg)


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <ground-geometry-windows.json> <out.json>", file=sys.stderr)
        return 2
    source = json.loads(Path(sys.argv[1]).read_text())
    if source.get("schema") != SCHEMA_IN:
        fail("schema")
    if source.get("same_sample_ground_geometry_ready") is not True:
        fail("same-sample-ground-geometry-not-ready")
    if source.get("fixed_vertex_count") != 3306:
        fail("vertex-count")
    if source.get("canonical_character_placement_available") is not False:
        fail("canonical-placement-unexpected")
    if source.get("ground_contact_classifiable") is not False:
        fail("contact-classification-unexpected")

    samples = source.get("samples")
    if not isinstance(samples, list) or not samples:
        fail("samples")
    lower = {}
    for sample in samples:
        idx = sample.get("sample_index")
        y = sample.get("raw_skinned_lower_envelope_y_m")
        if not isinstance(idx, int) or not isinstance(y, (int, float)) or not math.isfinite(float(y)):
            fail("sample-shape")
        if idx in lower:
            fail("duplicate-sample")
        if sample.get("replayed_vertex_count") != 3306:
            fail("sample-vertex-count")
        lower[idx] = float(y)

    windows = source.get("windows")
    if not isinstance(windows, list) or source.get("window_count") != len(windows):
        fail("windows")

    minima = []
    for raw_window in windows:
        if not isinstance(raw_window, list) or len(raw_window) != 3:
            fail("window-shape")
        a, b, c = [int(x) for x in raw_window]
        if [a, b, c] != [int(x) for x in raw_window] or b != a + 1 or c != b + 1:
            fail("window-order")
        if a not in lower or b not in lower or c not in lower:
            fail("window-sample-missing")
        ya, yb, yc = lower[a], lower[b], lower[c]
        if yb < ya and yb < yc:
            minima.append({
                "sample_index": b,
                "window": [a, b, c],
                "lower_envelope_y_m": yb,
                "drop_from_prev_m": ya - yb,
                "rise_to_next_m": yc - yb,
            })

    minima.sort(key=lambda item: item["sample_index"])
    if not minima:
        fail("no-local-minima")
    lowest = min(minima, key=lambda item: (item["lower_envelope_y_m"], item["sample_index"]))

    receipt = {
        "schema": SCHEMA_OUT,
        "source_schema": SCHEMA_IN,
        "fixed_vertex_count": 3306,
        "local_minima": minima,
        "local_minimum_indices": [item["sample_index"] for item in minima],
        "lowest_candidate_sample_index": lowest["sample_index"],
        "lowest_candidate_window": lowest["window"],
        "lowest_candidate_lower_envelope_y_m": lowest["lower_envelope_y_m"],
        "kinematic_geometry_phase_candidate_only": True,
        "canonical_character_placement_available": False,
        "ground_contact_classifiable": False,
        "contact_proof_claimed": False,
        "planted_interval_claimable": False,
        "quantitative_foot_slide_candidate": False,
        "animation_correction_authorized": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "player_view_claimed": False,
    }
    Path(sys.argv[2]).write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    print("CIV1_GROUND_GEOMETRY_PHASE_MINIMA_OK", receipt["local_minimum_indices"], "lowest", receipt["lowest_candidate_sample_index"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

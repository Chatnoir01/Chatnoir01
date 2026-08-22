#!/usr/bin/env python3
import json
import pathlib
import sys

TOLERANCE = 0.002
SCHEMA = "grand-bruxelles-rendered-main-base-attribution-v2"


def load_fingerprint(path: pathlib.Path):
    doc = json.loads(path.read_text(encoding="utf-8"))
    fp = doc.get("fingerprint")
    if not isinstance(fp, dict):
        raise SystemExit(f"missing fingerprint object: {path}")
    return fp


def require_same_contract(candidate, base, frozen):
    for key in ("schema", "width", "height", "tile_cols", "tile_rows", "tile_sample_step"):
        if candidate.get(key) != base.get(key) or candidate.get(key) != frozen.get(key):
            raise SystemExit(f"fingerprint contract mismatch: {key}")
    ct = candidate.get("tiles_rgbl", [])
    bt = base.get("tiles_rgbl", [])
    ft = frozen.get("tiles_rgbl", [])
    if not ct or len(ct) != len(bt) or len(ct) != len(ft):
        raise SystemExit("fingerprint tile vector mismatch")
    for index, (ca, ba, fa) in enumerate(zip(ct, bt, ft)):
        if len(ca) < 4 or len(ba) < 4 or len(fa) < 4:
            raise SystemExit(f"malformed tile vector at {index}")
    ch = candidate.get("luma_histogram", [])
    bh = base.get("luma_histogram", [])
    fh = frozen.get("luma_histogram", [])
    if not ch or len(ch) != len(bh) or len(ch) != len(fh):
        raise SystemExit("fingerprint histogram mismatch")
    return ct, bt, ft, ch, bh, fh


def drift(value, frozen):
    return abs(float(value) - float(frozen))


def main(argv):
    if len(argv) != 8:
        raise SystemExit(
            "usage: rendered_main_base_attribution.py CANDIDATE BASE FROZEN OUTPUT BASE_SHA HEAD_SHA BASE_FAILED"
        )
    candidate_path, base_path, frozen_path, output_path = map(pathlib.Path, argv[1:5])
    base_sha, head_sha = argv[5:7]
    base_failed = argv[7] == "1"

    candidate = load_fingerprint(candidate_path)
    base = load_fingerprint(base_path)
    frozen = load_fingerprint(frozen_path)
    ct, bt, ft, ch, bh, fh = require_same_contract(candidate, base, frozen)

    max_regression = 0.0
    max_improvement = 0.0
    max_tile_channel_delta = 0.0
    regressed_tile_channels = 0
    improved_tile_channels = 0
    regressed_tile_indexes = set()
    improved_tile_indexes = set()

    for index, (ca, ba, fa) in enumerate(zip(ct, bt, ft)):
        for channel in range(4):
            candidate_drift = drift(ca[channel], fa[channel])
            base_drift = drift(ba[channel], fa[channel])
            movement = candidate_drift - base_drift
            max_tile_channel_delta = max(max_tile_channel_delta, abs(float(ca[channel]) - float(ba[channel])))
            if movement > 0:
                max_regression = max(max_regression, movement)
                if movement > TOLERANCE:
                    regressed_tile_channels += 1
                    regressed_tile_indexes.add(index)
            elif movement < 0:
                improvement = -movement
                max_improvement = max(max_improvement, improvement)
                if improvement > TOLERANCE:
                    improved_tile_channels += 1
                    improved_tile_indexes.add(index)

    max_histogram_delta = 0.0
    max_histogram_regression = 0.0
    max_histogram_improvement = 0.0
    regressed_histogram_bins = 0
    improved_histogram_bins = 0
    for candidate_value, base_value, frozen_value in zip(ch, bh, fh):
        candidate_drift = drift(candidate_value, frozen_value)
        base_drift = drift(base_value, frozen_value)
        movement = candidate_drift - base_drift
        max_histogram_delta = max(max_histogram_delta, abs(float(candidate_value) - float(base_value)))
        if movement > 0:
            max_histogram_regression = max(max_histogram_regression, movement)
            if movement > TOLERANCE:
                regressed_histogram_bins += 1
        elif movement < 0:
            improvement = -movement
            max_histogram_improvement = max(max_histogram_improvement, improvement)
            if improvement > TOLERANCE:
                improved_histogram_bins += 1

    monotonic_to_frozen = max_regression <= TOLERANCE and max_histogram_regression <= TOLERANCE
    inherited = base_failed and monotonic_to_frozen
    result = {
        "schema": SCHEMA,
        "base_sha": base_sha,
        "head_sha": head_sha,
        "base_frozen_baseline_failed": base_failed,
        "inherited_frozen_baseline_drift": inherited,
        "monotonic_toward_frozen": monotonic_to_frozen,
        "tolerance": TOLERANCE,
        "max_tile_channel_delta": max_tile_channel_delta,
        "max_histogram_delta": max_histogram_delta,
        "max_regression_away_from_frozen": max_regression,
        "max_improvement_toward_frozen": max_improvement,
        "max_histogram_regression_away_from_frozen": max_histogram_regression,
        "max_histogram_improvement_toward_frozen": max_histogram_improvement,
        "regressed_tile_channels": regressed_tile_channels,
        "improved_tile_channels": improved_tile_channels,
        "regressed_tile_indexes": sorted(regressed_tile_indexes),
        "improved_tile_indexes": sorted(improved_tile_indexes),
        "regressed_histogram_bins": regressed_histogram_bins,
        "improved_histogram_bins": improved_histogram_bins,
        "frozen_baseline_changed": False,
        "frozen_threshold_changed": False,
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("RENDERED_MAIN_BASE_ATTRIBUTION_JSON: " + json.dumps(result, sort_keys=True))

    if not base_failed:
        raise SystemExit("candidate RED cannot be inherited because exact PR base was GREEN")
    if not monotonic_to_frozen:
        raise SystemExit(
            "candidate moves rendered evidence away from frozen baseline: "
            f"tile_regression={max_regression:.6f} histogram_regression={max_histogram_regression:.6f} "
            f"tolerance={TOLERANCE:.6f}"
        )


if __name__ == "__main__":
    main(sys.argv)

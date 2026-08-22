#!/usr/bin/env python3
import json
import pathlib
import sys

TOLERANCE = 0.002
SCHEMA = "grand-bruxelles-rendered-main-base-attribution-v3"


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


def tile_error(tile, frozen_tile):
    rgb_mae = sum(drift(tile[channel], frozen_tile[channel]) for channel in range(3)) / 3.0
    luma = drift(tile[3], frozen_tile[3])
    return rgb_mae, luma


def histogram_mae(values, frozen):
    return sum(drift(value, reference) for value, reference in zip(values, frozen)) / len(values)


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

    max_tile_channel_delta = 0.0
    max_tile_metric_regression = 0.0
    max_tile_metric_improvement = 0.0
    changed_tile_indexes = []
    improved_tile_indexes = []
    regressed_tile_indexes = []
    base_rgb_errors = []
    candidate_rgb_errors = []
    base_luma_errors = []
    candidate_luma_errors = []

    for index, (ca, ba, fa) in enumerate(zip(ct, bt, ft)):
        base_head_delta = max(abs(float(ca[channel]) - float(ba[channel])) for channel in range(4))
        max_tile_channel_delta = max(max_tile_channel_delta, base_head_delta)
        candidate_rgb, candidate_luma = tile_error(ca, fa)
        base_rgb, base_luma = tile_error(ba, fa)
        base_rgb_errors.append(base_rgb)
        candidate_rgb_errors.append(candidate_rgb)
        base_luma_errors.append(base_luma)
        candidate_luma_errors.append(candidate_luma)

        rgb_movement = candidate_rgb - base_rgb
        luma_movement = candidate_luma - base_luma
        max_tile_metric_regression = max(max_tile_metric_regression, rgb_movement, luma_movement)
        max_tile_metric_improvement = max(max_tile_metric_improvement, -rgb_movement, -luma_movement)

        if base_head_delta <= TOLERANCE:
            continue
        changed_tile_indexes.append(index)
        non_worsening = rgb_movement <= TOLERANCE and luma_movement <= TOLERANCE
        strict_improvement = (-rgb_movement > TOLERANCE) or (-luma_movement > TOLERANCE)
        if non_worsening and strict_improvement:
            improved_tile_indexes.append(index)
        else:
            regressed_tile_indexes.append(index)

    base_tile_rgb_mae = sum(base_rgb_errors) / len(base_rgb_errors)
    candidate_tile_rgb_mae = sum(candidate_rgb_errors) / len(candidate_rgb_errors)
    base_tile_luma_mae = sum(base_luma_errors) / len(base_luma_errors)
    candidate_tile_luma_mae = sum(candidate_luma_errors) / len(candidate_luma_errors)
    base_max_tile_luma = max(base_luma_errors)
    candidate_max_tile_luma = max(candidate_luma_errors)
    base_histogram_mae = histogram_mae(bh, fh)
    candidate_histogram_mae = histogram_mae(ch, fh)
    max_histogram_delta = max(abs(float(a) - float(b)) for a, b in zip(ch, bh))

    aggregate_movements = {
        "tile_rgb_mae": candidate_tile_rgb_mae - base_tile_rgb_mae,
        "tile_luma_mae": candidate_tile_luma_mae - base_tile_luma_mae,
        "max_tile_luma_delta": candidate_max_tile_luma - base_max_tile_luma,
        "luma_histogram_mae": candidate_histogram_mae - base_histogram_mae,
    }
    aggregate_regressions = sorted(
        name for name, movement in aggregate_movements.items() if movement > TOLERANCE
    )
    max_histogram_regression = max(0.0, aggregate_movements["luma_histogram_mae"])
    max_histogram_improvement = max(0.0, -aggregate_movements["luma_histogram_mae"])
    monotonic_to_frozen = not regressed_tile_indexes and not aggregate_regressions
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
        "max_regression_away_from_frozen": max(0.0, max_tile_metric_regression),
        "max_improvement_toward_frozen": max(0.0, max_tile_metric_improvement),
        "max_histogram_regression_away_from_frozen": max_histogram_regression,
        "max_histogram_improvement_toward_frozen": max_histogram_improvement,
        "changed_tile_indexes": changed_tile_indexes,
        "improved_tile_indexes": improved_tile_indexes,
        "regressed_tile_indexes": regressed_tile_indexes,
        "aggregate_regressions": aggregate_regressions,
        "base_frozen_metrics": {
            "tile_rgb_mae": base_tile_rgb_mae,
            "tile_luma_mae": base_tile_luma_mae,
            "max_tile_luma_delta": base_max_tile_luma,
            "luma_histogram_mae": base_histogram_mae,
        },
        "candidate_frozen_metrics": {
            "tile_rgb_mae": candidate_tile_rgb_mae,
            "tile_luma_mae": candidate_tile_luma_mae,
            "max_tile_luma_delta": candidate_max_tile_luma,
            "luma_histogram_mae": candidate_histogram_mae,
        },
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
            f"tile_metric_regression={max_tile_metric_regression:.6f} "
            f"aggregate={aggregate_regressions} tolerance={TOLERANCE:.6f}"
        )


if __name__ == "__main__":
    main(sys.argv)

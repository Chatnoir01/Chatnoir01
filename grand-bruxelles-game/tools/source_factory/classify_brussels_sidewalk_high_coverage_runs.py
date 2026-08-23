#!/usr/bin/env python3
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MEASURE_PATH = ROOT / "tools/source_factory/measure_brussels_sidewalk_horizontal_overlap.py"
MEASUREMENT_LOCK_PATH = ROOT / "data/provenance/brussels_sidewalk_horizontal_overlap_measurement.json"
COVERAGE_THRESHOLD = 0.99
EXPECTED_HIGH_COVERAGE_SURFACES = 47


def _load_measure_module():
    spec = importlib.util.spec_from_file_location("sidewalk_overlap_measure", MEASURE_PATH)
    if spec is None or spec.loader is None:
        raise AssertionError("sidewalk overlap measurement module unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _canonical_sha256(value):
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return "sha256:" + hashlib.sha256(payload).hexdigest()


def classify():
    measure = _load_measure_module()
    measurement_lock = json.loads(MEASUREMENT_LOCK_PATH.read_text(encoding="utf-8"))
    if measurement_lock["measurement"]["surfaces_with_at_least_99pct_coverage"] != EXPECTED_HIGH_COVERAGE_SURFACES:
        raise AssertionError("upstream high-coverage surface count drifted")
    if measurement_lock["policy"]["runtime_replacement_authorized"] is not False:
        raise AssertionError("upstream overlap lock unexpectedly authorizes runtime replacement")

    osm = measure._load(measure.OSM_PATH)
    manifest = measure._load(measure.GEOMETRY_MANIFEST_PATH)
    georef = measure._load(measure.GEOREF_PATH)
    surfaces = measure._generic_sidewalks(osm)
    official = measure._load_official_features(manifest)
    transform = measure._transformer(georef)
    prepared, bins = measure._prepare_official(official, transform)

    high = []
    for surface in surfaces:
        samples = list(measure._surface_samples(surface))
        hits = sum(1 for point in samples if measure._official_contains(point, prepared, bins))
        ratio = hits / len(samples)
        if ratio + 1e-12 < COVERAGE_THRESHOLD:
            continue
        high.append({
            "surface_id": f"osm:{surface['osm_id']}:seg:{surface['segment_index']}:side:{surface['side']}",
            "osm_id": surface["osm_id"],
            "segment_index": surface["segment_index"],
            "side": surface["side"],
            "center_xz": [round(surface["center"][0], 6), round(surface["center"][1], 6)],
            "length_m": round(surface["length_m"], 6),
            "width_m": round(surface["width_m"], 6),
            "road_class": surface["road_class"],
            "sample_count": len(samples),
            "coverage_fraction": round(ratio, 9),
        })

    if len(high) != EXPECTED_HIGH_COVERAGE_SURFACES:
        raise AssertionError(f"high-coverage candidate count drifted: {len(high)} != {EXPECTED_HIGH_COVERAGE_SURFACES}")

    high.sort(key=lambda item: (item["osm_id"], item["side"], item["segment_index"]))
    groups = []
    current = []
    for item in high:
        if current:
            previous = current[-1]
            contiguous = (
                item["osm_id"] == previous["osm_id"]
                and item["side"] == previous["side"]
                and item["segment_index"] == previous["segment_index"] + 1
            )
            if not contiguous:
                groups.append(current)
                current = []
        current.append(item)
    if current:
        groups.append(current)

    run_records = []
    for index, group in enumerate(groups):
        ratios = [item["coverage_fraction"] for item in group]
        run_records.append({
            "run_id": f"official-sidewalk-run-{index:02d}",
            "osm_id": group[0]["osm_id"],
            "side": group[0]["side"],
            "start_segment_index": group[0]["segment_index"],
            "end_segment_index": group[-1]["segment_index"],
            "surface_count": len(group),
            "total_length_m": round(sum(item["length_m"] for item in group), 6),
            "min_coverage_fraction": round(min(ratios), 9),
            "mean_coverage_fraction": round(sum(ratios) / len(ratios), 9),
            "surface_ids": [item["surface_id"] for item in group],
        })

    result = {
        "schema": "grand-bruxelles-sidewalk-high-coverage-runs-v1",
        "classification_kind": "same-osm-way-same-side-consecutive-segment-runs",
        "horizontal_only": True,
        "coverage_threshold": COVERAGE_THRESHOLD,
        "inputs": {
            "generic_sidewalk_count": len(surfaces),
            "official_feature_count": len(official),
            "upstream_measurement_schema": measurement_lock["schema"],
            "upstream_measurement_sha256": _canonical_sha256(measurement_lock),
            "georef_evidence_sha256": georef["method"]["evidence_sha256"],
        },
        "classification": {
            "high_coverage_surface_count": len(high),
            "run_count": len(run_records),
            "multi_surface_run_count": sum(1 for run in run_records if run["surface_count"] > 1),
            "high_coverage_surfaces": high,
            "runs": run_records,
        },
        "policy": {
            "curb_height_authorized": False,
            "vertical_profile_authorized": False,
            "runtime_geometry_authorized": False,
            "runtime_replacement_authorized": False,
            "jouable_promotion_authorized": False,
            "classification_alone_authorizes_runtime": False,
            "exact_location_owner_review_required": True,
        },
        "source": measurement_lock["source"],
    }
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    result = classify()
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    summary = {
        "high_coverage_surface_count": result["classification"]["high_coverage_surface_count"],
        "run_count": result["classification"]["run_count"],
        "multi_surface_run_count": result["classification"]["multi_surface_run_count"],
    }
    print("OFFICIAL_SIDEWALK_HIGH_COVERAGE_RUNS_MEASURED " + json.dumps(summary, sort_keys=True))


if __name__ == "__main__":
    main()

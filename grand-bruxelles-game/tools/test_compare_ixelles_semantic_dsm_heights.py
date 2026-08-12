#!/usr/bin/env python3
from __future__ import annotations

import csv
import importlib.util
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("cmp", HERE / "compare_ixelles_semantic_dsm_heights.py")
assert SPEC and SPEC.loader
cmp = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(cmp)


def semantic_match(building_id: str, height: float, score: float = 0.98, margin: float = 0.98):
    return {
        "status": "matched_semantic_evidence",
        "matched_inspire_id": building_id,
        "busolid_id": "solid-" + building_id.rsplit("/", 1)[-1],
        "semantic_height_m": height,
        "match_score": score,
        "match_margin": margin,
    }


def main() -> int:
    ids = [f"https://databrussels.be/id/building/{n}" for n in (1, 2, 3, 4, 5)]
    semantic = {
        "cell": cmp.CELL,
        "policy": {"crs": "EPSG:31370", "runtime_approval": False},
        "matches": [
            semantic_match(ids[0], 10.0),       # strong, high, validation candidate
            semantic_match(ids[1], 10.0),       # moderate
            semantic_match(ids[2], 10.0),       # conflict/outlier
            semantic_match(ids[3], 10.0, .80, .20), # strong but weak semantic match
            semantic_match(ids[4], 10.0),       # missing DSM
        ],
    }
    with tempfile.TemporaryDirectory() as td:
        csv_path = Path(td) / "dsm.csv"
        with csv_path.open("w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=["cell_id","building_id","confidence","height_p50_m","height_p75_m","height_p90_m"])
            w.writeheader()
            w.writerow({"cell_id":cmp.CELL,"building_id":ids[0],"confidence":"high","height_p50_m":9.5,"height_p75_m":11.0,"height_p90_m":12.0})
            w.writerow({"cell_id":cmp.CELL,"building_id":ids[1],"confidence":"high","height_p50_m":11.0,"height_p75_m":13.0,"height_p90_m":14.0})
            w.writerow({"cell_id":cmp.CELL,"building_id":ids[2],"confidence":"high","height_p50_m":17.0,"height_p75_m":19.0,"height_p90_m":20.0})
            w.writerow({"cell_id":cmp.CELL,"building_id":ids[3],"confidence":"medium","height_p50_m":11.0,"height_p75_m":12.0,"height_p90_m":13.0})
        result = cmp.compare(semantic, cmp.load_dsm_rows(csv_path, cmp.CELL))

    assert result["source_crs"] == "EPSG:31370"
    assert result["runtime_approved"] is False
    assert result["counts"]["semantic_matched_inputs"] == 5
    assert result["counts"]["joined_comparisons"] == 4
    assert result["counts"]["dsm_missing"] == 1
    assert result["counts"]["strong"] == 2
    assert result["counts"]["moderate"] == 1
    assert result["counts"]["conflict"] == 1
    assert result["counts"]["outliers_gt_8m"] == 1
    assert result["counts"]["strong_validation_candidates"] == 1
    assert all(r["runtime_approved"] is False for r in result["records"])
    by_id = {r["building_id"]: r for r in result["records"]}
    assert by_id[ids[0]]["dsm_policy_candidate_m"] == 11.0
    assert by_id[ids[3]]["dsm_policy_candidate_m"] == 11.0
    assert by_id[ids[3]]["strong_validation_candidate"] is False
    print("IXELLES_SEMANTIC_DSM_COMPARISON_TEST_PASS", result["counts"], result["delta_summary_m"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Deterministic guard for the five-cell Ixelles height-policy review.

This test does not approve runtime heights. It only proves that the persisted
cross-cell evidence supports p50 as the next policy candidate while keeping
all runtime/promotion flags false.
"""
from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data" / "processed" / "remaining_brussels" / "references" / "ixelles_height_policy_review.json"

LOCKED_CELLS = {
    "bxl-e149000-n169000-s500",
    "bxl-e149000-n169500-s500",
    "bxl-e149500-n168500-s500",
    "bxl-e149500-n169000-s500",
    "bxl-e149500-n169500-s500",
}
VARIANTS = ("dsm_height_p50_m", "dsm_height_p75_m", "dsm_height_p90_m", "dsm_policy_candidate_m")
EXPECTED_DIST_SHA = "090f4a6aada5c7c19609860d7ee3956ce0f06379c991533975bcf1ddb848dfaa"
EXPECTED_GPKG_SHA = "2aa3057da9d0cfd656baf684fe53d343629b1539a648fbb69fff983327993c78"
EXPECTED_SEED_DIGEST = "sha256:4e5dca00c28a084e242b67044574ea4ea0e8058fb07d56449482801d98f2f467"
EXPECTED_MULTI_DIGEST = "sha256:2e201d33d5c110dfbb27aea9f6af7673e1e311a698ef655b8f3604a6b9e33170"


def pooled(cells: list[dict], variant: str) -> dict:
    n = sum(c["variant_metrics"][variant]["n"] for c in cells)
    assert n > 0
    return {
        "n": n,
        "weighted_mae_m": sum(c["variant_metrics"][variant]["mae_m"] * c["variant_metrics"][variant]["n"] for c in cells) / n,
        "weighted_signed_mean_m": sum(c["variant_metrics"][variant]["signed_mean_m"] * c["variant_metrics"][variant]["n"] for c in cells) / n,
        "weighted_within_2m_fraction": sum(c["variant_metrics"][variant]["within_2m_fraction"] * c["variant_metrics"][variant]["n"] for c in cells) / n,
        "weighted_within_4m_fraction": sum(c["variant_metrics"][variant]["within_4m_fraction"] * c["variant_metrics"][variant]["n"] for c in cells) / n,
        "outliers_gt_8m": sum(c["variant_metrics"][variant]["outliers_gt_8m"] for c in cells),
    }


def close(a: float, b: float, tol: float = 1e-12) -> bool:
    return math.isclose(a, b, rel_tol=tol, abs_tol=tol)


def main() -> int:
    data = json.loads(DATA.read_text(encoding="utf-8"))
    assert data["schema"] == "grand-bruxelles-ixelles-height-policy-review-v1"
    assert data["source_crs"] == "EPSG:31370"
    assert data["runtime_approved"] is False

    sources = data["authoritative_sources"]
    assert sources["urbis_3d_distribution_sha256"] == EXPECTED_DIST_SHA
    assert sources["urbis_3d_gpkg_sha256"] == EXPECTED_GPKG_SHA
    assert sources["seed_calibration"]["artifact_digest"] == EXPECTED_SEED_DIGEST
    assert sources["multicell_validation"]["artifact_digest"] == EXPECTED_MULTI_DIGEST

    cells = data["cells"]
    assert len(cells) == 5
    assert {c["cell"] for c in cells} == LOCKED_CELLS
    assert all(c["runtime_approved"] is False for c in cells)
    for c in cells:
        e0, n0, e1, n1 = c["bbox_epsg31370"]
        assert e1 - e0 == 500.0 and n1 - n0 == 500.0
        assert set(VARIANTS).issubset(c["variant_metrics"])

    winners = {"p50": 0, "p75": 0, "p90": 0}
    p75_margins = []
    for c in cells:
        maes = {
            "p50": c["variant_metrics"]["dsm_height_p50_m"]["mae_m"],
            "p75": c["variant_metrics"]["dsm_height_p75_m"]["mae_m"],
            "p90": c["variant_metrics"]["dsm_height_p90_m"]["mae_m"],
        }
        best = min(maes, key=maes.get)
        assert c["best_tested_statistic"] == best
        winners[best] += 1
        if best == "p75":
            p75_margins.append(maes["p50"] - maes["p75"])

    assert winners == {"p50": 4, "p75": 1, "p90": 0}
    assert len(p75_margins) == 1
    assert 0.0 < p75_margins[0] < 0.01

    recomputed = {variant: pooled(cells, variant) for variant in VARIANTS}
    for variant, metrics in recomputed.items():
        persisted = data["pooled_metrics"][variant]
        assert persisted["n"] == metrics["n"]
        assert persisted["outliers_gt_8m"] == metrics["outliers_gt_8m"]
        for key in ("weighted_mae_m", "weighted_signed_mean_m", "weighted_within_2m_fraction", "weighted_within_4m_fraction"):
            assert close(persisted[key], metrics[key])

    p50 = recomputed["dsm_height_p50_m"]
    p75 = recomputed["dsm_height_p75_m"]
    p90 = recomputed["dsm_height_p90_m"]
    current = recomputed["dsm_policy_candidate_m"]
    assert p50["n"] == 2677
    assert p50["weighted_mae_m"] < p75["weighted_mae_m"] < p90["weighted_mae_m"]
    assert abs(p50["weighted_signed_mean_m"]) < abs(p75["weighted_signed_mean_m"])
    assert p50["weighted_within_2m_fraction"] > p75["weighted_within_2m_fraction"]
    assert p50["weighted_within_4m_fraction"] > p75["weighted_within_4m_fraction"]
    assert p50["outliers_gt_8m"] < p75["outliers_gt_8m"] < p90["outliers_gt_8m"]
    assert p50["weighted_mae_m"] < current["weighted_mae_m"]

    decision = data["decision"]
    assert decision["recommended_statistic"] == "p50"
    assert decision["best_cell_count"] == winners
    assert close(decision["single_p75_win_margin_m"], p75_margins[0])
    assert close(decision["pooled_p50_mae_gain_vs_p75_m"], p75["weighted_mae_m"] - p50["weighted_mae_m"])
    assert decision["pooled_p50_outlier_reduction_vs_p75"] == p75["outliers_gt_8m"] - p50["outliers_gt_8m"]
    assert decision["policy_status"] == "cross_cell_candidate"
    assert decision["runtime_approved"] is False
    assert decision["promote_runtime"] is False

    print(
        "IXELLES_HEIGHT_POLICY_REVIEW_OK",
        f"n={p50['n']}",
        f"p50_mae={p50['weighted_mae_m']:.6f}",
        f"p75_mae={p75['weighted_mae_m']:.6f}",
        f"p50_bias={p50['weighted_signed_mean_m']:.6f}",
        f"p75_bias={p75['weighted_signed_mean_m']:.6f}",
        f"p50_outliers={p50['outliers_gt_8m']}",
        f"p75_outliers={p75['outliers_gt_8m']}",
        "runtime_approved=false",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

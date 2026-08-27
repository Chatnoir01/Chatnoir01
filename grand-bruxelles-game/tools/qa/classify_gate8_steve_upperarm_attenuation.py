#!/usr/bin/env python3
"""Classify the Steve walk / Gate-8 skin attenuation A/B without adopting a factor.

The classifier deliberately reuses the existing CPU skin-space hard limits.  A factor
is viable only when all three exact culprit-edge constraints pass simultaneously:
absolute edge change <= 0.25 m, stretch <= 3x, compression >= 0.25x.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

FACTORS = (1.0, 0.75, 0.5, 0.25)
MAX_ABSOLUTE_EDGE_CHANGE_M = 0.25
MAX_STRETCH_RATIO = 3.0
MIN_COMPRESSION_RATIO = 0.25
EXPECTED_EDGE_IDS = {"max_absolute", "max_stretch", "min_compression"}


def classify(payload: dict) -> dict:
    rows = payload["metrics"]["skin_space"]["upperarm_attenuation_ab"]
    if len(rows) != 8:
        raise AssertionError(f"expected 8 attenuation rows, got {len(rows)}")

    by_factor: dict[float, dict[str, dict]] = {factor: {} for factor in FACTORS}
    sample_factor_pairs = set()
    for row in rows:
        factor = float(row["factor"])
        sample = int(row["sample_index"])
        if factor not in by_factor:
            raise AssertionError(f"unexpected factor {factor}")
        pair = (sample, factor)
        if pair in sample_factor_pairs:
            raise AssertionError(f"duplicate sample/factor row {pair}")
        sample_factor_pairs.add(pair)
        for edge in row.get("edges", []):
            edge_id = str(edge["id"])
            if edge_id in by_factor[factor]:
                raise AssertionError(f"duplicate edge {edge_id} for factor {factor}")
            by_factor[factor][edge_id] = edge

    results = []
    viable = []
    for factor in FACTORS:
        edges = by_factor[factor]
        if set(edges) != EXPECTED_EDGE_IDS:
            raise AssertionError(
                f"factor {factor} edge inventory {sorted(edges)} != {sorted(EXPECTED_EDGE_IDS)}"
            )
        absolute = float(edges["max_absolute"]["absolute_change_m"])
        stretch = float(edges["max_stretch"]["ratio"])
        compression = float(edges["min_compression"]["ratio"])
        gates = {
            "absolute_edge_change": absolute <= MAX_ABSOLUTE_EDGE_CHANGE_M,
            "stretch": stretch <= MAX_STRETCH_RATIO,
            "compression": compression >= MIN_COMPRESSION_RATIO,
        }
        all_pass = all(gates.values())
        if all_pass:
            viable.append(factor)
        results.append(
            {
                "factor": factor,
                "max_absolute_edge_change_m": absolute,
                "max_stretch_ratio": stretch,
                "min_compression_ratio": compression,
                "gates": gates,
                "all_skin_gates_pass": all_pass,
            }
        )

    return {
        "format": "grand-bruxelles-gate8-steve-upperarm-attenuation-classification-v1",
        "thresholds": {
            "max_absolute_edge_change_m": MAX_ABSOLUTE_EDGE_CHANGE_M,
            "max_stretch_ratio": MAX_STRETCH_RATIO,
            "min_compression_ratio": MIN_COMPRESSION_RATIO,
        },
        "tested_factors": list(FACTORS),
        "results": results,
        "viable_factors": viable,
        "modest_075_viable": 0.75 in viable,
        "production_authorized": False,
        "activation_ready": False,
        "adoption_ready": False,
        "runtime_alias_published": False,
        "state": (
            "ATTENUATION_FACTOR_MECHANICALLY_VIABLE_PENDING_VISUAL_REVIEW"
            if viable
            else "REJECT_STEVE_WALK_GATE8_SKIN_PAIR_AT_TESTED_ATTENUATIONS"
        ),
    }


def _fixture(quarter_stretch: float) -> dict:
    rows = []
    values = {
        1.0: (0.54, 45.0, 0.06),
        0.75: (0.41, 35.0, 0.26),
        0.5: (0.27, 24.0, 0.52),
        0.25: (0.12, quarter_stretch, 0.77),
    }
    for factor, (absolute, stretch, compression) in values.items():
        rows.append({"sample_index": 2, "factor": factor, "edges": [{"id": "min_compression", "ratio": compression, "absolute_change_m": 0.0}]})
        rows.append({"sample_index": 8, "factor": factor, "edges": [
            {"id": "max_absolute", "absolute_change_m": absolute, "ratio": 1.0},
            {"id": "max_stretch", "absolute_change_m": 0.0, "ratio": stretch},
        ]})
    return {"metrics": {"skin_space": {"upperarm_attenuation_ab": rows}}}


def self_test() -> None:
    rejected = classify(_fixture(12.8))
    assert rejected["viable_factors"] == []
    assert rejected["state"] == "REJECT_STEVE_WALK_GATE8_SKIN_PAIR_AT_TESTED_ATTENUATIONS"
    assert rejected["production_authorized"] is False

    viable = classify(_fixture(2.5))
    assert viable["viable_factors"] == [0.25]
    assert viable["state"] == "ATTENUATION_FACTOR_MECHANICALLY_VIABLE_PENDING_VISUAL_REVIEW"
    assert viable["adoption_ready"] is False

    malformed = _fixture(2.5)
    malformed["metrics"]["skin_space"]["upperarm_attenuation_ab"].pop()
    try:
        classify(malformed)
    except AssertionError:
        pass
    else:
        raise AssertionError("malformed attenuation inventory must fail closed")

    print("GATE8_STEVE_ATTENUATION_CLASSIFIER_TESTS_OK tests=3")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        return 0
    if not args.input or not args.output:
        parser.error("--input and --output are required unless --self-test is used")

    result = classify(json.loads(args.input.read_text(encoding="utf-8")))
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "GATE8_STEVE_ATTENUATION_CLASSIFICATION "
        f"state={result['state']} viable={result['viable_factors']} production=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

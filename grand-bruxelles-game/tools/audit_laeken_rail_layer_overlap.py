#!/usr/bin/env python3
"""Audit semantic overlap between the committed Laeken TramNetwork/TrainNetwork slices.

The 2026-08-12 UrbIS WFS extraction currently contains two collections that are
semantically identical for this bbox even though they came from distinct WFS
layer names. This tool deliberately ignores the transport-specific WFS feature
id and compares the fields that describe the actual line object and geometry.

It exists to keep the source-truth runtime behaviour reproducible: duplicate
source collections must never become two superposed visual rail networks, while
a future authoritative refresh that makes the collections distinct must fail the
fixture and force a deliberate review rather than silently hiding real railway.
"""

from __future__ import annotations

import argparse
import collections
import hashlib
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
TRAM_PATH = ROOT / "data/urbis/laeken_jette/tram_network.game.json"
TRAIN_PATH = ROOT / "data/urbis/laeken_jette/train_network.game.json"
AUDIT_PATH = ROOT / "data/sources/laeken_jette/rail_layer_overlap_audit.json"
COMPARE_PROPERTIES = ("INSPIRE_ID", "TYPE", "LVL", "LENGTH")


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return value


def normalized_geometry(geometry: Any) -> str:
    return json.dumps(geometry, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def feature_signature(feature: dict[str, Any]) -> str:
    properties = feature.get("properties") or {}
    geometry = feature.get("geometry") or {}
    payload = {
        "properties": {key: properties.get(key) for key in COMPARE_PROPERTIES},
        "geometry": geometry,
    }
    return json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def signature_counter(document: dict[str, Any]) -> collections.Counter[str]:
    features = document.get("features", [])
    if not isinstance(features, list):
        raise ValueError("GeoJSON 'features' must be an array")
    counter: collections.Counter[str] = collections.Counter()
    for feature in features:
        if not isinstance(feature, dict):
            raise ValueError("Every GeoJSON feature must be an object")
        counter[feature_signature(feature)] += 1
    return counter


def observed_types(document: dict[str, Any]) -> list[str]:
    values: set[str] = set()
    for feature in document.get("features", []):
        properties = feature.get("properties") or {}
        value = properties.get("TYPE")
        if value not in (None, ""):
            values.add(str(value))
    return sorted(values)


def digest_counter(counter: collections.Counter[str]) -> str:
    digest = hashlib.sha256()
    for signature, count in sorted(counter.items()):
        digest.update(str(count).encode("ascii"))
        digest.update(b"\0")
        digest.update(signature.encode("utf-8"))
        digest.update(b"\n")
    return digest.hexdigest()


def build_audit() -> dict[str, Any]:
    tram = load_json(TRAM_PATH)
    train = load_json(TRAIN_PATH)
    tram_features = tram.get("features", [])
    train_features = train.get("features", [])
    tram_counter = signature_counter(tram)
    train_counter = signature_counter(train)
    matched = sum((tram_counter & train_counter).values())
    duplicate = (
        len(tram_features) == len(train_features)
        and matched == len(tram_features)
        and tram_counter == train_counter
    )
    return {
        "schema": "grand-bruxelles.laeken-jette.rail-layer-overlap-audit.v1",
        "source": {
            "provider": "Paradigm / Brussels UrbIS vector WFS",
            "crs": "EPSG:31370",
            "bbox": [147300.0, 173650.0, 149100.0, 176750.0],
            "fetch_date": "2026-08-12",
            "tram_layer": "urbisvector:TramNetwork",
            "train_layer": "urbisvector:TrainNetwork",
            "tram_path": "data/urbis/laeken_jette/tram_network.game.json",
            "train_path": "data/urbis/laeken_jette/train_network.game.json",
        },
        "comparison": {
            "ignored_fields": ["feature.id"],
            "properties": list(COMPARE_PROPERTIES),
            "geometry_compared": True,
        },
        "result": {
            "tram_feature_count": len(tram_features),
            "train_feature_count": len(train_features),
            "semantic_signature_match_count": matched,
            "distinct_tram_signatures": len(tram_counter),
            "distinct_train_signatures": len(train_counter),
            "tram_types": observed_types(tram),
            "train_types": observed_types(train),
            "tram_signature_sha256": digest_counter(tram_counter),
            "train_signature_sha256": digest_counter(train_counter),
            "collections_semantically_identical": duplicate,
        },
        "runtime_policy": {
            "preserve_both_source_files": True,
            "hide_second_visual_only_when_semantically_identical": True,
            "future_distinct_source_requires_review": True,
        },
    }


def stable_projection(audit: dict[str, Any]) -> dict[str, Any]:
    """Fields required to remain equal to the committed fixture."""
    return {
        "schema": audit.get("schema"),
        "source": audit.get("source"),
        "comparison": audit.get("comparison"),
        "result": audit.get("result"),
        "runtime_policy": audit.get("runtime_policy"),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="compare live committed source slices to the audit fixture")
    parser.add_argument("--write", action="store_true", help="rewrite the audit fixture from the current committed source slices")
    args = parser.parse_args()

    audit = build_audit()
    if args.write:
        AUDIT_PATH.parent.mkdir(parents=True, exist_ok=True)
        AUDIT_PATH.write_text(json.dumps(audit, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    if args.check:
        expected = load_json(AUDIT_PATH)
        if stable_projection(audit) != stable_projection(expected):
            print("LAEKEN_RAIL_OVERLAP_AUDIT_FAIL: authoritative rail source overlap changed")
            print(json.dumps(audit, indent=2, ensure_ascii=False))
            return 1
        if not audit["result"]["collections_semantically_identical"]:
            print("LAEKEN_RAIL_OVERLAP_AUDIT_FAIL: fixture no longer represents duplicate collections")
            return 1

    result = audit["result"]
    print(
        "LAEKEN_RAIL_OVERLAP_AUDIT_OK: tram=%d train=%d matches=%d duplicate=%s types=%s"
        % (
            result["tram_feature_count"],
            result["train_feature_count"],
            result["semantic_signature_match_count"],
            str(result["collections_semantically_identical"]).lower(),
            ",".join(result["tram_types"]),
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

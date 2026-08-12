#!/usr/bin/env python3
"""Extract one canonical polygon area proven by two official language labels.

Designed for areas such as Pentagone/Vijfhoek. Both labels must resolve through
one common polygon-proven dataset, and their Lambert72 geometry fingerprints
must be identical. If French/Dutch evidence resolves to different geometry, the
pipeline fails instead of guessing which one is authoritative.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

TOOLS_DIR = Path(__file__).resolve().parent
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

from extract_brussels_opendata_subzones import common_dataset, target_features
from probe_brussels_opendata_boundaries import fetch_all_records

PROBE_FORMAT = "grand-bruxelles-opendata-boundary-probe-v1"
SELECTION_FORMAT = "grand-bruxelles-opendata-dataset-selection-v1"
FORMAT = "grand-bruxelles-bilingual-area-boundary-v1"


def load(path: Path, expected: str) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("format") != expected:
        raise ValueError(f"unsupported format in {path}: {payload.get('format')!r}")
    return payload


def fingerprints(features: list[dict[str, Any]]) -> set[str]:
    return {
        json.dumps(feature.get("geometry"), sort_keys=True, separators=(",", ":"))
        for feature in features
        if feature.get("geometry")
    }


def canonical_features(records: list[dict[str, Any]], labels: list[str]) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    if len(labels) < 2:
        raise ValueError("at least two language labels are required")
    by_label: dict[str, list[dict[str, Any]]] = {}
    source_crs: set[str] = set()
    for label in labels:
        features, crs_values = target_features(records, label)
        by_label[label] = features
        source_crs.update(crs_values)
    base = fingerprints(by_label[labels[0]])
    if not base:
        raise ValueError(f"first label has no polygon geometry: {labels[0]}")
    for label in labels[1:]:
        current = fingerprints(by_label[label])
        if current != base:
            raise ValueError(
                f"bilingual labels resolve to different polygon geometry: {labels[0]}={len(base)}, {label}={len(current)}"
            )
    # Keep the first-language features but strip target-specific synthetic IDs.
    output: list[dict[str, Any]] = []
    for index, feature in enumerate(by_label[labels[0]]):
        item = json.loads(json.dumps(feature))
        item["id"] = f"canonical-{index}"
        props = dict(item.get("properties") or {})
        props["canonical_labels"] = labels
        item["properties"] = props
        output.append(item)
    return output, {
        "labels": labels,
        "source_crs_values": sorted(source_crs),
        "geometry_fingerprint_count": len(base),
    }


def build_output(
    probe: dict[str, Any],
    selection: dict[str, Any],
    records: list[dict[str, Any]],
    labels: list[str],
) -> dict[str, Any]:
    dataset_id = common_dataset(probe, labels)
    if dataset_id != str(selection.get("dataset_id")):
        raise ValueError(f"bilingual area dataset {dataset_id} differs from license-approved dataset {selection.get('dataset_id')}")
    gate = selection.get("license_gate") or {}
    if gate.get("production_geometry_allowed") is not True:
        raise ValueError("license-approved production geometry gate is not true")
    features, evidence = canonical_features(records, labels)
    return {
        "type": "FeatureCollection",
        "crs": {"type": "name", "properties": {"name": "EPSG:31370"}},
        "features": features,
        "grand_bruxelles_source": {
            "format": FORMAT,
            "authority": "Brussels Open Data",
            "dataset_id": dataset_id,
            "labels": labels,
            "output_crs": "EPSG:31370",
            "license": selection.get("license"),
            "license_gate": gate,
            "bilingual_geometry_evidence": evidence,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Extract one bilingual Brussels area from proven official polygon data")
    parser.add_argument("--probe", type=Path, required=True)
    parser.add_argument("--selection", type=Path, required=True)
    parser.add_argument("--label", action="append", required=True)
    parser.add_argument("--max-records", type=int, default=2500)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    probe = load(args.probe, PROBE_FORMAT)
    selection = load(args.selection, SELECTION_FORMAT)
    dataset_id = common_dataset(probe, list(args.label))
    records, total = fetch_all_records(dataset_id, max(1, args.max_records))
    if total > args.max_records:
        raise ValueError(f"dataset has {total} records, above --max-records {args.max_records}")
    output = build_output(probe, selection, records, list(args.label))
    output["grand_bruxelles_source"]["source_record_count"] = total
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"bilingual area {args.label} -> {len(output['features'])} canonical polygon feature(s) -> {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

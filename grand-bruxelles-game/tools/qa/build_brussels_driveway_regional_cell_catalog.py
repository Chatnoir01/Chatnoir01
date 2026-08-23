#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import math
import time
import unicodedata
import urllib.parse
import urllib.request
from collections import Counter
from pathlib import Path
from typing import Any

from shapely.geometry import Point, shape as shapely_shape

USER_AGENT = "Grand-Bruxelles-Driveway-Regional-Cells/1.0"


def canonical_json(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def sha256(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def normalize(value: object) -> str:
    text = unicodedata.normalize("NFKD", str(value))
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    return " ".join(text.casefold().replace("-", " ").split())


def get_json(url: str, timeout: int = 180, retries: int = 4) -> dict[str, Any]:
    last: Exception | None = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
            with urllib.request.urlopen(req, timeout=timeout) as response:
                return json.loads(response.read().decode("utf-8"))
        except Exception as exc:
            last = exc
            if attempt + 1 < retries:
                time.sleep(min(2 ** (attempt + 1), 8))
    raise RuntimeError(f"download failed: {url}: {last}")


def wfs_url(base: str, **params: object) -> str:
    query = {"service": "WFS", "request": "GetFeature", "outputFormat": "application/json", "srsName": "EPSG:31370"}
    query.update({key: str(value) for key, value in params.items()})
    return base + "?" + urllib.parse.urlencode(query)


def load_municipalities(contract: dict[str, Any]) -> list[tuple[str, Any]]:
    cfg = contract["municipalities"]
    payload = get_json(wfs_url(cfg["wfs_url"], version="2.0.0", typeNames=cfg["type_name"]))
    features = payload.get("features") or []
    if len(features) != int(cfg["expected_count"]):
        raise RuntimeError(f"municipality count drift: {len(features)} != {cfg['expected_count']}")
    remaining = {normalize(name): name for name in cfg["allowlist"]}
    matched: dict[str, Any] = {}
    for feature in features:
        values = {
            normalize(value)
            for value in (feature.get("properties") or {}).values()
            if value is not None and not isinstance(value, (dict, list))
        }
        hits = [key for key in remaining if key in values]
        if len(hits) != 1:
            continue
        key = hits[0]
        geometry = shapely_shape(feature.get("geometry"))
        if geometry.is_empty or not geometry.is_valid:
            raise RuntimeError(f"invalid municipality geometry: {remaining[key]}")
        matched[key] = geometry
    missing = sorted(set(remaining) - set(matched))
    if missing:
        raise RuntimeError(f"municipality allowlist not resolved exactly: {missing}")
    return [(remaining[key], matched[key]) for key in sorted(matched)]


def load_driveways(contract: dict[str, Any]) -> list[dict[str, Any]]:
    cfg = contract["source"]
    expected = int(cfg["expected_feature_count"])
    page_size = int(cfg["page_size"])
    stable_property = str(cfg["stable_id_property"])
    features: list[dict[str, Any]] = []
    start = 0
    while start < expected:
        payload = get_json(wfs_url(
            cfg["wfs_url"], version="2.0.0", typeNames=cfg["type_name"],
            count=page_size, startIndex=start, sortBy=f"{stable_property} A",
        ))
        page = payload.get("features") or []
        if not page:
            raise RuntimeError(f"empty driveway page before expected count at startIndex={start}")
        features.extend(page)
        start += len(page)
        if len(page) < page_size:
            break
    if len(features) != expected:
        raise RuntimeError(f"driveway feature count drift: {len(features)} != {expected}")
    return features


def stable_id(feature: dict[str, Any], property_name: str) -> str:
    value = (feature.get("properties") or {}).get(property_name)
    if value is None or str(value).strip() == "":
        raise RuntimeError("driveway missing stable id property")
    return str(value)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    contract = json.loads(Path(args.contract).read_text(encoding="utf-8"))
    for key, value in contract["hard_rules"].items():
        if value is not False:
            raise RuntimeError(f"hard rail must remain false: {key}")

    municipalities = load_municipalities(contract)
    features = load_driveways(contract)
    id_property = contract["source"]["stable_id_property"]
    cell_size = int(contract["partition"]["cell_size_m"])

    ids: list[str] = []
    seen: set[str] = set()
    municipality_counts: Counter[str] = Counter()
    cell_counts: Counter[tuple[str, str]] = Counter()
    unassigned: list[str] = []
    ambiguous: list[str] = []

    for feature in features:
        fid = stable_id(feature, id_property)
        if fid in seen:
            raise RuntimeError(f"duplicate driveway stable id: {fid}")
        seen.add(fid)
        ids.append(fid)
        geometry = feature.get("geometry") or {}
        if geometry.get("type") != "Point":
            raise RuntimeError(f"driveway {fid}: expected Point, got {geometry.get('type')}")
        coords = geometry.get("coordinates") or []
        if len(coords) < 2:
            raise RuntimeError(f"driveway {fid}: missing XY")
        x, y = float(coords[0]), float(coords[1])
        if not (10000.0 <= x <= 300000.0 and 10000.0 <= y <= 300000.0):
            raise RuntimeError(f"driveway {fid}: coordinate outside Lambert72 envelope: {(x, y)}")
        point = Point(x, y)
        owners = [name for name, polygon in municipalities if polygon.covers(point)]
        if len(owners) == 0:
            unassigned.append(fid)
            continue
        if len(owners) != 1:
            ambiguous.append(fid)
            continue
        municipality = owners[0]
        east = int(math.floor(x / cell_size) * cell_size)
        north = int(math.floor(y / cell_size) * cell_size)
        cell_id = f"E{east}_N{north}"
        municipality_counts[municipality] += 1
        cell_counts[(municipality, cell_id)] += 1

    if len(unassigned) != int(contract["partition"]["require_unassigned_count"]):
        raise RuntimeError(f"unassigned driveway count: {len(unassigned)}")
    if len(ambiguous) != int(contract["partition"]["require_ambiguous_count"]):
        raise RuntimeError(f"ambiguous driveway count: {len(ambiguous)}")

    ordered_ids = sorted(ids)
    rows = [
        {"municipality": municipality, "cell_id": cell_id, "feature_count": count}
        for (municipality, cell_id), count in sorted(cell_counts.items())
    ]
    result = {
        "schema": "grand-bruxelles-driveway-regional-cell-catalog-v1",
        "production_base_sha": contract["production_base_sha"],
        "source": {
            "publisher": contract["publisher"],
            "dataset": contract["dataset"],
            "license": contract["license"],
            "crs": contract["source_crs"],
            "feature_count": len(features),
            "stable_id_set_sha256": sha256(("\n".join(ordered_ids) + "\n").encode("utf-8")),
        },
        "partition": {
            "cell_size_m": cell_size,
            "municipality_count": len(municipality_counts),
            "cell_count": len(rows),
            "assigned_feature_count": sum(municipality_counts.values()),
            "unassigned_count": len(unassigned),
            "ambiguous_count": len(ambiguous),
            "municipality_counts": dict(sorted(municipality_counts.items())),
            "cells": rows,
            "cells_sha256": sha256(canonical_json(rows)),
        },
        "destination_readiness": "DISCOVERED_SOURCE_ONLY",
        "source_registration_authorized": False,
        "road_crosswalk_authorized": False,
        "parking_evidence_runtime_approved": False,
        "runtime_authorized": False,
        "runtime_mount_authorized": False,
        "collision_authorized": False,
        "materialization_authorized": False,
        "semantic_names_authorized": False,
        "game_world_transform_authorized": False,
        "jouable_promotion_authorized": False,
    }
    Path(args.out).write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        "DRIVEWAY_REGIONAL_CELL_CATALOG_OK "
        f"features={len(features)} municipalities={len(municipality_counts)} cells={len(rows)} "
        f"cells_sha256={result['partition']['cells_sha256']}"
    )


if __name__ == "__main__":
    main()

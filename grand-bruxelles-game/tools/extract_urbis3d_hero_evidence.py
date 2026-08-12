#!/usr/bin/env python3
"""Extract source-traceable UrbIS 3D Z evidence for one hero building.

The tool is deliberately evidence-only: it never changes runtime approval. It first
requires an identifier match in feature attributes (for example UrbIS ref 8186511
or building id 1751663), then reports the full finite Z span of those matched 3D
features. A nearby spatial-only hit is diagnostic and never accepted as identity.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any, Iterable

from osgeo import ogr, osr

EXPECTED_EPSG = "31370"
SCHEMA = "grand-bruxelles-urbis3d-hero-evidence-v1"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def authority_code(spatial_ref: osr.SpatialReference | None) -> str | None:
    if spatial_ref is None:
        return None
    clone = spatial_ref.Clone()
    try:
        clone.AutoIdentifyEPSG()
    except Exception:
        pass
    for target in (None, "PROJCS", "GEOGCS"):
        try:
            code = clone.GetAuthorityCode(target)
        except Exception:
            code = None
        if code:
            return str(code)
    return None


def iter_z(geometry: ogr.Geometry | None) -> Iterable[float]:
    if geometry is None:
        return
    stack = [geometry]
    while stack:
        current = stack.pop()
        if current.GetGeometryCount() > 0:
            for index in range(current.GetGeometryCount()):
                child = current.GetGeometryRef(index)
                if child is not None:
                    stack.append(child)
            continue
        for index in range(current.GetPointCount()):
            point = current.GetPoint(index)
            if len(point) >= 3 and math.isfinite(float(point[2])):
                yield float(point[2])


def feature_properties(feature: ogr.Feature) -> dict[str, str]:
    properties: dict[str, str] = {}
    definition = feature.GetDefnRef()
    for index in range(definition.GetFieldCount()):
        value = feature.GetField(index)
        if value is not None:
            properties[definition.GetFieldDefn(index).GetName()] = str(value)
    return properties


def feature_values(feature: ogr.Feature) -> list[str]:
    return list(feature_properties(feature).values())


def matches_identifier(feature: ogr.Feature, tokens: list[str]) -> bool:
    if not tokens:
        return False
    folded_values = [value.casefold() for value in feature_values(feature)]
    return any(any(token.casefold() in value for value in folded_values) for token in tokens)


def summarize_z(values: list[float]) -> dict[str, Any]:
    if not values:
        return {"count": 0, "min": None, "max": None, "span": None}
    return {
        "count": len(values),
        "min": min(values),
        "max": max(values),
        "span": max(values) - min(values),
    }


def extract(root: Path, tokens: list[str], anchor_e: float, anchor_n: float, radius_m: float) -> dict[str, Any]:
    packages: list[dict[str, Any]] = []
    identifier_matches: list[dict[str, Any]] = []
    nearby_diagnostics: list[dict[str, Any]] = []

    for path in sorted(p for p in root.rglob("*.gpkg") if p.is_file()):
        dataset = ogr.Open(str(path), 0)
        if dataset is None:
            continue
        package = {"path": str(path), "size_bytes": path.stat().st_size, "sha256": sha256_file(path)}
        packages.append(package)
        for layer_index in range(dataset.GetLayerCount()):
            layer = dataset.GetLayerByIndex(layer_index)
            if authority_code(layer.GetSpatialRef()) != EXPECTED_EPSG:
                continue
            layer_name = layer.GetName()
            layer.SetSpatialFilterRect(anchor_e - radius_m, anchor_n - radius_m, anchor_e + radius_m, anchor_n + radius_m)
            for feature in layer:
                geometry = feature.GetGeometryRef()
                z_values = list(iter_z(geometry))
                if not z_values:
                    continue
                record = {
                    "package_sha256": package["sha256"],
                    "layer": layer_name,
                    "fid": int(feature.GetFID()),
                    "properties": feature_properties(feature),
                    "z": summarize_z(z_values),
                    "envelope": None,
                }
                if geometry is not None:
                    envelope = geometry.GetEnvelope()
                    record["envelope"] = [float(value) for value in envelope]
                if matches_identifier(feature, tokens):
                    identifier_matches.append(record)
                elif len(nearby_diagnostics) < 80:
                    nearby_diagnostics.append(record)
            layer.SetSpatialFilter(None)

    all_z: list[float] = []
    for match in identifier_matches:
        package_path = next((p["path"] for p in packages if p["sha256"] == match["package_sha256"]), None)
        if not package_path:
            continue
        dataset = ogr.Open(package_path, 0)
        layer = dataset.GetLayerByName(match["layer"])
        feature = layer.GetFeature(match["fid"]) if layer else None
        if feature is not None:
            all_z.extend(iter_z(feature.GetGeometryRef()))

    return {
        "schema": SCHEMA,
        "purpose": "Palais de la Bourse / Beurs hero height and roof evidence",
        "identity_policy": "Only attribute identifier matches are identity evidence; nearby spatial hits are diagnostics only.",
        "expected_crs": "EPSG:31370",
        "query": {
            "identifier_tokens": tokens,
            "anchor_e": anchor_e,
            "anchor_n": anchor_n,
            "radius_m": radius_m,
        },
        "packages": packages,
        "identifier_match_count": len(identifier_matches),
        "identifier_matches": identifier_matches,
        "combined_identifier_z": summarize_z(all_z),
        "nearby_diagnostics": nearby_diagnostics,
        "identity_proven": len(identifier_matches) > 0,
        "usable_for_runtime_height_review": len(identifier_matches) > 0 and len(all_z) > 0 and (max(all_z) - min(all_z)) > 1.0,
        "runtime_approved": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--identifier", action="append", default=[])
    parser.add_argument("--anchor-e", type=float, required=True)
    parser.add_argument("--anchor-n", type=float, required=True)
    parser.add_argument("--radius-m", type=float, default=90.0)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--require-identity", action="store_true")
    args = parser.parse_args()

    result = extract(args.root, args.identifier, args.anchor_e, args.anchor_n, args.radius_m)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("URBIS3D_HERO_EVIDENCE", "matches=", result["identifier_match_count"], "z=", result["combined_identifier_z"], "nearby=", len(result["nearby_diagnostics"]))
    if args.require_identity and not result["usable_for_runtime_height_review"]:
        raise SystemExit("No source-identified EPSG:31370 3D feature with usable Z span was proven for the hero building")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

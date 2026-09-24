#!/usr/bin/env python3
"""Build the bounded Atomium / Heysel Web runtime slice from canonical UrbIS data.

The extraction envelope is not hand-authored: it is read from the committed official
Atomium DTM tile. Input features are kept when their game-space geometry bounding box
intersects that exact EPSG:31370 envelope. Output order follows canonical source order
and JSON serialization is deterministic.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any, Iterable

LAYERS = (
    "buildings",
    "street_surfaces",
    "street_axes",
    "tram_network",
    "train_network",
)


def read_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"{path}: top level must be an object")
    return value


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def coordinate_pairs(value: Any) -> Iterable[tuple[float, float]]:
    if not isinstance(value, list):
        return
    if (
        len(value) >= 2
        and isinstance(value[0], (int, float))
        and isinstance(value[1], (int, float))
    ):
        yield float(value[0]), float(value[1])
        return
    for child in value:
        yield from coordinate_pairs(child)


def geometry_game_bbox(feature: dict[str, Any]) -> tuple[float, float, float, float] | None:
    geometry = feature.get("geometry")
    if not isinstance(geometry, dict):
        return None
    points = list(coordinate_pairs(geometry.get("coordinates")))
    if not points:
        return None
    xs = [point[0] for point in points]
    zs = [point[1] for point in points]
    return min(xs), min(zs), max(xs), max(zs)


def intersects(a: tuple[float, float, float, float], b: tuple[float, float, float, float]) -> bool:
    return not (a[2] < b[0] or a[0] > b[2] or a[3] < b[1] or a[1] > b[3])


def dtm_contract(path: Path) -> tuple[tuple[float, float, float, float], dict[str, Any]]:
    dtm = read_json(path)
    if dtm.get("source_crs") != "EPSG:31370":
        raise ValueError("Atomium DTM CRS must be EPSG:31370")
    bounds = dtm.get("bounds_epsg31370")
    if not isinstance(bounds, dict):
        raise ValueError("Atomium DTM bounds_epsg31370 missing")
    min_e = float(bounds["min_e"])
    min_n = float(bounds["min_n"])
    max_e = float(bounds["max_e"])
    max_n = float(bounds["max_n"])
    origin_e = float(dtm["game_origin_e"])
    origin_n = float(dtm["game_origin_n"])
    # Game X = E-origin_E, game Z = -(N-origin_N).
    game_bbox = (
        min_e - origin_e,
        -(max_n - origin_n),
        max_e - origin_e,
        -(min_n - origin_n),
    )
    return game_bbox, {
        "source_crs": "EPSG:31370",
        "bounds_epsg31370": [min_e, min_n, max_e, max_n],
        "game_bbox": list(game_bbox),
        "game_origin_e": origin_e,
        "game_origin_n": origin_n,
    }


def slice_document(document: dict[str, Any], game_bbox: tuple[float, float, float, float]) -> dict[str, Any]:
    features = document.get("features")
    if not isinstance(features, list):
        raise ValueError("canonical layer has no features array")
    kept: list[dict[str, Any]] = []
    for raw in features:
        if not isinstance(raw, dict):
            continue
        bbox = geometry_game_bbox(raw)
        if bbox is not None and intersects(bbox, game_bbox):
            kept.append(raw)
    result = dict(document)
    result["features"] = kept
    return result


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"
    path.write_text(text, encoding="utf-8")


def build(project_root: Path, output_root: Path) -> dict[str, Any]:
    canonical_root = project_root / "data" / "urbis" / "laeken_jette"
    dtm_path = project_root / "data" / "terrain" / "laeken_jette" / "atomium_dtm.game.json"
    game_bbox, envelope = dtm_contract(dtm_path)
    layer_receipts: dict[str, Any] = {}

    for layer in LAYERS:
        source_path = canonical_root / f"{layer}.game.json"
        source = read_json(source_path)
        sliced = slice_document(source, game_bbox)
        output_path = output_root / f"{layer}.game.json"
        write_json(output_path, sliced)
        layer_receipts[layer] = {
            "source_path": str(source_path.relative_to(project_root)),
            "source_sha256": sha256(source_path),
            "source_feature_count": len(source.get("features", [])),
            "runtime_feature_count": len(sliced.get("features", [])),
            "runtime_bytes": output_path.stat().st_size,
            "runtime_sha256": sha256(output_path),
        }

    required_nonzero = ("buildings", "street_surfaces", "street_axes")
    missing = [name for name in required_nonzero if layer_receipts[name]["runtime_feature_count"] <= 0]
    if missing:
        raise RuntimeError(f"bounded Heysel slice is empty for required layers: {', '.join(missing)}")

    manifest = {
        "format": "grand-bruxelles-atomium-heysel-runtime-slice-v1",
        "zone": "atomium_heysel",
        "source_family": "Paradigm / Brussels-Capital Region UrbIS",
        "license": "CC0 for used UrbIS vector classes; cadastral parcels excluded",
        "extraction_rule": "keep canonical feature when its game-space geometry bbox intersects the exact committed Atomium DTM tile envelope",
        "envelope": envelope,
        "dtm_source_path": str(dtm_path.relative_to(project_root)),
        "dtm_source_sha256": sha256(dtm_path),
        "layers": layer_receipts,
        "runtime_total_bytes": sum(item["runtime_bytes"] for item in layer_receipts.values()),
        "raw_phase1_payload_reenabled_for_web": False,
        "jouable_claim": False,
    }
    write_json(output_root / "manifest.json", manifest)
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output-root", type=Path)
    args = parser.parse_args()
    project_root = args.project_root.resolve()
    output_root = (
        args.output_root.resolve()
        if args.output_root
        else project_root / "data" / "urbis" / "laeken_jette" / "atomium_heysel_runtime"
    )
    manifest = build(project_root, output_root)
    counts = {name: receipt["runtime_feature_count"] for name, receipt in manifest["layers"].items()}
    print(f"ATOMIUM_HEYSEL_RUNTIME_SLICE_READY counts={json.dumps(counts, sort_keys=True)} bytes={manifest['runtime_total_bytes']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

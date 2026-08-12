#!/usr/bin/env python3
"""Extract a tiny source-backed UrbIS surface set for the Bourse hero context."""
from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
PROBE_PATH = ROOT / "tools" / "probe_bourse_urbis_context.py"
spec = importlib.util.spec_from_file_location("bourse_probe", PROBE_PATH)
probe = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(probe)

BOURSE_GAME_ANCHOR = (81.54, -664.58)
SELECTED_IDS = {
    "https://databrussels.be/id/streetsurface/151494",
    "https://databrussels.be/id/streetsurface/10947",
    "https://databrussels.be/id/streetsurface/5449",
    "https://databrussels.be/id/streetsurface/151334",
    "https://databrussels.be/id/streetsurface/22358",
    "https://databrussels.be/id/streetsurface/151495",
    "https://databrussels.be/id/streetsurface/152281",
}


def epsg_to_game(point: list[float] | tuple[float, float]) -> list[float]:
    east, north = float(point[0]), float(point[1])
    de = east - probe.BOURSE_CENTER[0]
    dn = north - probe.BOURSE_CENTER[1]
    return [BOURSE_GAME_ANCHOR[0] + de, BOURSE_GAME_ANCHOR[1] - dn]


def polygon_rings(geometry: dict[str, Any]) -> list[list[list[float]]]:
    kind = geometry.get("type")
    coords = geometry.get("coordinates", [])
    polygons = [coords] if kind == "Polygon" else coords if kind == "MultiPolygon" else []
    rings: list[list[list[float]]] = []
    for polygon in polygons:
        if not polygon:
            continue
        outer = polygon[0]
        if len(outer) < 4:
            continue
        rings.append([epsg_to_game(point) for point in outer])
    return rings


def build_extract(payload: dict[str, Any]) -> dict[str, Any]:
    selected = []
    for feature in payload.get("features", []):
        props = feature.get("properties") or {}
        inspire_id = props.get("INSPIRE_ID")
        if inspire_id not in SELECTED_IDS:
            continue
        rings = polygon_rings(feature.get("geometry") or {})
        if not rings:
            continue
        selected.append({
            "inspire_id": inspire_id,
            "street_name_fr": props.get("STRNAMEFRE"),
            "street_name_nl": props.get("STRNAMEDUT"),
            "surface_type": props.get("TYPE"),
            "area_m2": props.get("AREA"),
            "level": props.get("LVL"),
            "rings_local_xz": rings,
        })
    missing = sorted(SELECTED_IDS - {item["inspire_id"] for item in selected})
    if missing:
        raise RuntimeError(f"missing selected UrbIS Bourse surfaces: {missing}")
    return {
        "schema": "grand-bruxelles-bourse-urbis-surfaces-v1",
        "source": probe.WFS_URL,
        "crs": probe.CRS,
        "source_control_point_epsg31370": list(probe.BOURSE_CENTER),
        "game_control_point_xz": list(BOURSE_GAME_ANCHOR),
        "transform": "x = anchor_x + (E-E0); z = anchor_z - (N-N0)",
        "runtime_approved": False,
        "surfaces": sorted(selected, key=lambda item: item["inspire_id"]),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    payload, _digest = probe.fetch_layer("urbisvector:StreetSurfaces", probe.probe_bbox())
    extract = build_extract(payload)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(extract, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"surfaces": len(extract["surfaces"]), "output": str(args.output)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Select official UrbIS3D packages needed by a CityGen cell worklist.

The regional target grid identifies every municipality touched by a 500 m cell.
UrbIS3D publishes municipality-specific EPSG:31370 GeoPackage distributions. This
planner resolves the parent Atom entry once, selects the latest matching package for
each required municipality, and emits an auditable download plan. It never downloads
large binaries and never authorizes runtime use.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
from typing import Any

FORMAT = "grand-bruxelles-citygen-urbis3d-package-plan-v1"
GRID_FORMAT = "grand-bruxelles-regional-target-grid-v1"
CRS = "EPSG:31370"
SOURCE_ID = "urbis_3d_constructions"

# Statbel NIS/INS municipality codes for the 19 Brussels-Capital municipalities.
# Both French and Dutch slugs are accepted because the official UrbIS boundary
# payload may expose either language as the shortest stable textual identifier.
MUNICIPALITY_NIS = {
    "anderlecht": "21001",
    "auderghem": "21002", "oudergem": "21002",
    "berchem-sainte-agathe": "21003", "sint-agatha-berchem": "21003",
    "bruxelles": "21004", "brussel": "21004", "ville-de-bruxelles": "21004", "stad-brussel": "21004",
    "etterbeek": "21005",
    "evere": "21006",
    "forest": "21007", "vorst": "21007",
    "ganshoren": "21008",
    "ixelles": "21009", "elsene": "21009",
    "jette": "21010",
    "koekelberg": "21011",
    "molenbeek-saint-jean": "21012", "sint-jans-molenbeek": "21012",
    "saint-gilles": "21013", "sint-gillis": "21013",
    "saint-josse-ten-noode": "21014", "sint-joost-ten-node": "21014",
    "schaerbeek": "21015", "schaarbeek": "21015",
    "uccle": "21016", "ukkel": "21016",
    "watermael-boitsfort": "21017", "watermaal-bosvoorde": "21017",
    "woluwe-saint-lambert": "21018", "sint-lambrechts-woluwe": "21018",
    "woluwe-saint-pierre": "21019", "sint-pieters-woluwe": "21019",
}


def _read(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"expected JSON object: {path}")
    return payload


def _load_selector():
    module_path = Path(__file__).resolve().parents[1] / "select_urbis_distribution.py"
    spec = importlib.util.spec_from_file_location("select_urbis_distribution", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import UrbIS selector: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _worklist(path: Path) -> list[str]:
    values = [line.strip() for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if len(values) != len(set(values)):
        raise ValueError("worklist contains duplicate cell ids")
    if any(not value.startswith("bxl-") for value in values):
        raise ValueError("worklist contains invalid cell id")
    return values


def _grid_cells(grid: dict[str, Any]) -> dict[str, dict[str, Any]]:
    if grid.get("format") != GRID_FORMAT or grid.get("crs") != CRS:
        raise ValueError("unsupported regional target grid or CRS")
    rows: dict[str, dict[str, Any]] = {}
    for row in grid.get("cells") or []:
        if not isinstance(row, dict):
            raise ValueError("regional target grid row is not an object")
        cell_id = str(row.get("cell_id") or "")
        bbox = row.get("bbox")
        municipalities = row.get("municipalities") or []
        if not cell_id or cell_id in rows:
            raise ValueError("regional target grid contains invalid/duplicate cell id")
        if not isinstance(bbox, list) or len(bbox) != 4:
            raise ValueError(f"regional target grid has invalid bbox: {cell_id}")
        if not isinstance(municipalities, list) or not municipalities:
            raise ValueError(f"regional target grid has no municipality ownership: {cell_id}")
        rows[cell_id] = {
            "bbox": [float(value) for value in bbox],
            "municipalities": sorted({str(value) for value in municipalities}),
        }
    return rows


def _parent_entry(feed: dict[str, Any]) -> dict[str, Any]:
    matches = []
    for entry in feed.get("entries") or []:
        title = str((entry or {}).get("title") or "").casefold()
        if "31370" in title and "gpkg" in title:
            matches.append(entry)
    if not matches:
        raise ValueError("UrbIS3D feed has no EPSG:31370 GPKG parent entry")
    matches.sort(key=lambda item: (len(str(item.get("title") or "")), str(item.get("title") or "")))
    return matches[0]


def _nis_for(slug: str) -> str:
    code = MUNICIPALITY_NIS.get(slug.casefold())
    if code is None:
        raise ValueError(f"unknown Brussels municipality slug: {slug}")
    return code


def build(feed_payload: dict[str, Any], grid: dict[str, Any], cells: list[str], selector=None) -> dict[str, Any]:
    selector = selector or _load_selector()
    feed = next((item for item in feed_payload.get("feeds") or [] if item.get("source_id") == SOURCE_ID), None)
    if feed is None:
        raise ValueError(f"official source not found in discovery payload: {SOURCE_ID}")
    rows = _grid_cells(grid)
    missing = sorted(set(cells) - set(rows))
    if missing:
        raise ValueError(f"worklist cell(s) absent from regional target grid: {missing}")

    required_municipalities = sorted({municipality for cell in cells for municipality in rows[cell]["municipalities"]})
    municipality_codes = {municipality: _nis_for(municipality) for municipality in required_municipalities}

    parent = _parent_entry(feed)
    resolved = selector.resolve_links(parent.get("links") or [])
    all_candidates = resolved.get("direct_candidates") or []
    if not all_candidates and cells:
        raise ValueError("UrbIS3D parent entry resolved no direct package candidates")

    package_by_municipality: dict[str, dict[str, Any]] = {}
    for municipality in required_municipalities:
        nis = municipality_codes[municipality]
        candidates = selector.filter_candidates(all_candidates, ["31370", "gpkg", nis])
        selected = selector.choose_candidate(candidates, prefer_latest=True)
        if selected is None:
            raise ValueError(f"no official UrbIS3D EPSG:31370 GPKG package for {municipality} ({nis})")
        package_by_municipality[municipality] = {
            "municipality": municipality,
            "nis_code": nis,
            "url": selected["href"],
            "embedded_date": selector.candidate_date(selected),
        }

    packages = sorted(package_by_municipality.values(), key=lambda row: (row["nis_code"], row["municipality"]))
    planned_cells = []
    for cell_id in cells:
        row = rows[cell_id]
        planned_cells.append({
            "cell_id": cell_id,
            "bbox": row["bbox"],
            "municipalities": row["municipalities"],
            "nis_codes": [_nis_for(value) for value in row["municipalities"]],
        })

    return {
        "format": FORMAT,
        "source_id": SOURCE_ID,
        "crs": CRS,
        "parent_entry_title": parent.get("title"),
        "parent_entry_updated": parent.get("updated"),
        "cells": planned_cells,
        "packages": packages,
        "policy": {
            "official_source_only": True,
            "prefer_latest_dated_distribution": True,
            "runtime_authorized": False,
            "runtime_promotion_allowed": False,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--feed", type=Path, required=True)
    parser.add_argument("--target-grid", type=Path, required=True)
    parser.add_argument("--worklist", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = build(_read(args.feed), _read(args.target_grid), _worklist(args.worklist))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "CITYGEN_URBIS3D_PACKAGE_PLAN_OK",
        f"cells={len(result['cells'])}",
        f"municipalities={len(result['packages'])}",
        "runtime_authorized=false",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

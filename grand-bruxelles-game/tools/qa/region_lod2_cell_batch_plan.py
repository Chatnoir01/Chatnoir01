#!/usr/bin/env python3
"""Plan source-only UrbIS LoD2 persistence batches across Brussels-Capital.

This is QA/planning only. It:
- inventories the current official UrbIS 3D Constructions LoD2 owner set;
- subtracts official building IDs already persisted in repository data;
- gets all 19 official municipality polygons from UrbIS WFS (EPSG:31370);
- derives one representative XY per owner from official BuildingSolids bboxes;
- assigns missing owners to a municipality and 500 m planning cell;
- chunks each municipality/cell into bounded source-persistence micro-batches.

No runtime, geometry, collision, semantic naming or JOUABLE authorization is implied.
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import math
import re
import tempfile
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any
from xml.etree import ElementTree as ET

import shapefile
from shapely.geometry import Point, shape as shapely_shape
from shapely.prepared import prep as prepare_geometry

DEFAULT_FEED = (
    "https://urbisdownload.datastore.brussels/atomfeed/"
    "e9ec2aa4-cffd-11ee-bccc-00090ffe0001-fr.xml"
)
WFS_URL = "https://geoservices-urbis.irisnet.be/geoserver/urbisvector/wfs"
WFS_LAYER = "urbisvector:Municipalities"
CRS = "EPSG:31370"
USER_AGENT = "Grand-Bruxelles-UrbIS-Regional-Batch-Plan/1.0"
ZIP_RE = re.compile(r"UrbISBuildings3D.*31370.*SHP.*\.zip(?:[?#].*)?$", re.I)
DATE_RE = re.compile(r"(?<!\d)(20\d{6})(?!\d)")
BUILDING_URL_RE = re.compile(r"https?://databrussels\.be/id/building/(\d+)", re.I)
OFFICIAL_ID_KEYS = {
    "building_2d_id", "building_id", "urbis_building_id",
    "source_building_id", "bu_id",
}
MUNICIPALITIES = [
    ("anderlecht", "Anderlecht"),
    ("auderghem", "Auderghem"),
    ("berchem-sainte-agathe", "Berchem-Sainte-Agathe"),
    ("bruxelles", "Bruxelles"),
    ("etterbeek", "Etterbeek"),
    ("evere", "Evere"),
    ("forest", "Forest"),
    ("ganshoren", "Ganshoren"),
    ("ixelles", "Ixelles"),
    ("jette", "Jette"),
    ("koekelberg", "Koekelberg"),
    ("molenbeek-saint-jean", "Molenbeek-Saint-Jean"),
    ("saint-gilles", "Saint-Gilles"),
    ("saint-josse-ten-noode", "Saint-Josse-ten-Noode"),
    ("schaerbeek", "Schaerbeek"),
    ("uccle", "Uccle"),
    ("watermael-boitsfort", "Watermael-Boitsfort"),
    ("woluwe-saint-lambert", "Woluwe-Saint-Lambert"),
    ("woluwe-saint-pierre", "Woluwe-Saint-Pierre"),
]


def http_get(url: str, timeout: int = 180, retries: int = 4) -> bytes:
    last: Exception | None = None
    for attempt in range(retries):
        request = urllib.request.Request(
            url, headers={"User-Agent": USER_AGENT, "Accept": "*/*"}
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return response.read()
        except (urllib.error.URLError, TimeoutError) as exc:
            last = exc
            if attempt + 1 < retries:
                time.sleep(min(2 ** (attempt + 1), 8))
    raise RuntimeError(f"download failed: {url}: {last}")


def normalize(value: object) -> str:
    text = unicodedata.normalize("NFKD", str(value))
    text = "".join(char for char in text if not unicodedata.combining(char))
    return " ".join(text.casefold().replace("-", " ").split())


def xml_urls(payload: bytes, base_url: str) -> set[str]:
    root = ET.fromstring(payload)
    urls: set[str] = set()
    for element in root.iter():
        href = element.attrib.get("href")
        if href:
            urls.add(urllib.parse.urljoin(base_url, href.strip()))
        text = (element.text or "").strip()
        if text.startswith(("http://", "https://")):
            urls.add(urllib.parse.urljoin(base_url, text))
    return urls


def discover_distributions(feed_url: str) -> list[str]:
    host = urllib.parse.urlparse(feed_url).netloc.lower()
    queue = [feed_url]
    visited: set[str] = set()
    zips: set[str] = set()
    while queue:
        url = queue.pop(0)
        if url in visited:
            continue
        if len(visited) >= 1000:
            raise RuntimeError("Atom traversal exceeded 1000 XML pages")
        visited.add(url)
        for candidate in xml_urls(http_get(url, timeout=90), url):
            parsed = urllib.parse.urlparse(candidate)
            if parsed.netloc.lower() != host:
                continue
            if ZIP_RE.search(candidate):
                zips.add(candidate)
            elif parsed.path.lower().endswith((".xml", ".atom")):
                queue.append(candidate)
    if not zips:
        raise RuntimeError("official Atom feed exposed no EPSG:31370 SHP Building3D ZIPs")
    return sorted(zips)


def revision(url: str) -> str:
    hits = DATE_RE.findall(urllib.parse.unquote(url))
    return max(hits) if hits else "00000000"


def distribution_key(url: str) -> str:
    name = Path(urllib.parse.urlparse(url).path).name
    return re.sub(r"(?<!\d)20\d{6}(?!\d)", "{DATE}", name).lower()


def latest_distributions(urls: list[str]) -> list[dict[str, str]]:
    latest: dict[str, tuple[str, str]] = {}
    for url in urls:
        key = distribution_key(url)
        rev = revision(url)
        if key not in latest or rev > latest[key][0]:
            latest[key] = (rev, url)
    return [
        {"distribution_key": key, "revision_date": value[0], "url": value[1]}
        for key, value in sorted(latest.items())
    ]


def detect_field(fields: list[str], *candidates: str) -> str | None:
    mapping = {field.upper(): field for field in fields}
    for candidate in candidates:
        if candidate.upper() in mapping:
            return mapping[candidate.upper()]
    return None


def numeric_id(value: object) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    if re.fullmatch(r"\d+", text):
        return text
    match = BUILDING_URL_RE.fullmatch(text)
    return match.group(1) if match else None


def is_lod2(value: object) -> bool:
    if value is None or str(value).strip() == "":
        return True
    text = str(value).strip().lower()
    try:
        return int(float(text)) == 2
    except ValueError:
        return text in {"lod2", "level2", "level_2"}


def archive_member(archive: zipfile.ZipFile, suffix: str) -> str | None:
    matches = [
        name for name in archive.namelist()
        if name.lower().endswith(suffix.lower()) and "buildingsolid" in name.lower()
    ]
    if len(matches) > 1:
        exact = [name for name in matches if name.lower().endswith("buildingsolids" + suffix.lower())]
        if len(exact) == 1:
            return exact[0]
        raise RuntimeError(f"ambiguous BuildingSolids {suffix}: {matches}")
    return matches[0] if matches else None


def inspect_distribution(row: dict[str, str]) -> tuple[dict[str, dict[str, Any]], dict[str, Any]]:
    payload = http_get(row["url"])
    owners: dict[str, dict[str, Any]] = {}
    summary: dict[str, Any] = {
        **row,
        "status": "ok",
        "source_records": 0,
        "lod2_records": 0,
        "unique_building_owners": 0,
        "empty_owner_records": 0,
        "geometryless_lod2_records": 0,
    }

    with zipfile.ZipFile(io.BytesIO(payload)) as archive, tempfile.TemporaryDirectory() as tmp:
        shp_name = archive_member(archive, ".shp")
        dbf_name = archive_member(archive, ".dbf")
        shx_name = archive_member(archive, ".shx")
        if not shp_name or not dbf_name:
            summary["status"] = "no_building_solids"
            return {}, summary

        members = [shp_name, dbf_name]
        if shx_name:
            members.append(shx_name)
        for name in members:
            archive.extract(name, tmp)

        kwargs: dict[str, str] = {
            "shp": str(Path(tmp) / shp_name),
            "dbf": str(Path(tmp) / dbf_name),
        }
        if shx_name:
            kwargs["shx"] = str(Path(tmp) / shx_name)
        reader = shapefile.Reader(
            **kwargs, encoding="utf-8", encodingErrors="replace"
        )
        fields = [field[0] for field in reader.fields[1:]]
        building_field = detect_field(fields, "BU_ID", "BUILDING_ID", "BUILDINGID", "BUILD_ID")
        solid_field = detect_field(fields, "INSPIRE_ID", "SOLID_ID", "SOLIDID", "ID")
        lod_field = detect_field(fields, "DETAILSLEV", "DETAILLEVEL", "LOD", "LEVEL")
        if building_field is None:
            raise RuntimeError(f"BU_ID field missing; fields={fields}")

        for shape_record in reader.iterShapeRecords():
            summary["source_records"] += 1
            values = shape_record.record.as_dict()
            if lod_field and not is_lod2(values.get(lod_field)):
                continue
            summary["lod2_records"] += 1
            building_id = numeric_id(values.get(building_field))
            if building_id is None:
                summary["empty_owner_records"] += 1
                continue

            owner = owners.setdefault(building_id, {
                "sum_x": 0.0,
                "sum_y": 0.0,
                "sample_count": 0,
                "solid_ids": set(),
            })
            if solid_field:
                solid_id = str(values.get(solid_field) or "").strip()
                if solid_id:
                    owner["solid_ids"].add(solid_id)

            bbox = getattr(shape_record.shape, "bbox", None)
            if not bbox or len(bbox) < 4:
                summary["geometryless_lod2_records"] += 1
                continue
            x = (float(bbox[0]) + float(bbox[2])) / 2.0
            y = (float(bbox[1]) + float(bbox[3])) / 2.0
            owner["sum_x"] += x
            owner["sum_y"] += y
            owner["sample_count"] += 1

    summary["unique_building_owners"] = len(owners)
    return owners, summary


def scan_persisted_ids(repo_root: Path) -> dict[str, list[str]]:
    data_root = repo_root / "grand-bruxelles-game" / "data"
    found: dict[str, set[str]] = defaultdict(set)
    if not data_root.is_dir():
        raise RuntimeError(f"missing data root: {data_root}")

    for path in data_root.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in {".json", ".geojson"}:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        rel = path.relative_to(repo_root).as_posix()
        for match in BUILDING_URL_RE.finditer(text):
            found[match.group(1)].add(rel)
        try:
            payload = json.loads(text)
        except json.JSONDecodeError:
            continue
        stack = [payload]
        while stack:
            node = stack.pop()
            if isinstance(node, dict):
                for key, value in node.items():
                    key_l = str(key).lower()
                    if (
                        key_l in OFFICIAL_ID_KEYS
                        or ("urbis" in key_l and "building" in key_l)
                    ) and isinstance(value, (str, int)):
                        candidate = numeric_id(value)
                        if candidate:
                            found[candidate].add(rel)
                    if isinstance(value, (dict, list)):
                        stack.append(value)
            elif isinstance(node, list):
                stack.extend(node)
    return {building_id: sorted(paths) for building_id, paths in found.items()}


def request_municipality_layer() -> dict[str, Any]:
    params = {
        "service": "WFS",
        "version": "2.0.0",
        "request": "GetFeature",
        "typeNames": WFS_LAYER,
        "outputFormat": "application/json",
        "srsName": CRS,
    }
    url = WFS_URL + "?" + urllib.parse.urlencode(params)
    data = json.loads(http_get(url, timeout=90).decode("utf-8"))
    if data.get("type") != "FeatureCollection":
        raise RuntimeError(f"unexpected municipality WFS payload: {data.get('type')!r}")
    return data


def feature_strings(feature: dict[str, Any]) -> set[str]:
    values: set[str] = set()
    for value in (feature.get("properties") or {}).values():
        if value is None or isinstance(value, (dict, list)):
            continue
        normalized = normalize(value)
        if normalized:
            values.add(normalized)
    if feature.get("id"):
        values.add(normalize(feature["id"]))
    return values


def select_municipality(data: dict[str, Any], name: str) -> dict[str, Any]:
    target = normalize(name)
    exact: list[dict[str, Any]] = []
    partial: list[dict[str, Any]] = []
    for feature in data.get("features", []):
        values = feature_strings(feature)
        if target in values:
            exact.append(feature)
            continue
        if any(target in value or value in target for value in values if len(value) >= 4):
            partial.append(feature)
    candidates = exact or partial
    if len(candidates) != 1:
        raise RuntimeError(f"municipality {name!r}: expected one official match, got {len(candidates)}")
    return candidates[0]


def load_municipalities() -> list[dict[str, Any]]:
    layer = request_municipality_layer()
    result: list[dict[str, Any]] = []
    for slug, name in MUNICIPALITIES:
        feature = select_municipality(layer, name)
        geom = shapely_shape(feature.get("geometry"))
        if geom.is_empty or not geom.is_valid:
            raise RuntimeError(f"municipality {name}: invalid/empty official geometry")
        result.append({
            "slug": slug,
            "name": name,
            "geometry": geom,
            "prepared": prepare_geometry(geom),
        })
    if len(result) != 19:
        raise RuntimeError(f"expected 19 municipalities, got {len(result)}")
    return result


def municipality_for_point(point: Point, municipalities: list[dict[str, Any]]) -> tuple[str, str, str]:
    matches = [
        item for item in municipalities
        if item["prepared"].covers(point)
    ]
    if len(matches) == 1:
        item = matches[0]
        return str(item["slug"]), str(item["name"]), "assigned"
    if len(matches) == 0:
        return "hold-unassigned", "", "unassigned"
    return "hold-boundary", ";".join(sorted(str(item["name"]) for item in matches)), "boundary_ambiguous"


def cell_for_xy(x: float, y: float, cell_size: int) -> tuple[str, int, int]:
    east = int(math.floor(x / cell_size) * cell_size)
    north = int(math.floor(y / cell_size) * cell_size)
    return f"E{east}_N{north}", east, north


def write_csv(path: Path, fields: list[str], rows: list[dict[str, Any]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def run(feed_url: str, repo_root: Path, output_dir: Path, workers: int, cell_size: int, max_batch: int) -> dict[str, Any]:
    output_dir.mkdir(parents=True, exist_ok=True)
    discovered = discover_distributions(feed_url)
    selected = latest_distributions(discovered)
    municipalities = load_municipalities()
    print(
        f"REGION_LOD2_BATCH_DISCOVERY: discovered={len(discovered)} "
        f"current={len(selected)} municipalities={len(municipalities)} workers={workers}",
        flush=True,
    )

    regional: dict[str, dict[str, Any]] = {}
    summaries: list[dict[str, Any]] = []
    errors: list[str] = []

    with ThreadPoolExecutor(max_workers=max(1, workers)) as pool:
        futures = {pool.submit(inspect_distribution, row): row for row in selected}
        for index, future in enumerate(as_completed(futures), start=1):
            row = futures[future]
            try:
                owners, summary = future.result()
            except Exception as exc:
                errors.append(f"{row['distribution_key']}: {exc}")
                print(f"[{index}/{len(selected)}] ERROR {errors[-1]}", flush=True)
                continue
            summaries.append(summary)
            print(
                f"[{index}/{len(selected)}] {row['distribution_key']} "
                f"status={summary['status']} owners={summary['unique_building_owners']}",
                flush=True,
            )
            for building_id, local in owners.items():
                owner = regional.setdefault(building_id, {
                    "sum_x": 0.0,
                    "sum_y": 0.0,
                    "sample_count": 0,
                    "solid_ids": set(),
                    "distribution_keys": set(),
                    "revision_dates": set(),
                })
                owner["sum_x"] += float(local["sum_x"])
                owner["sum_y"] += float(local["sum_y"])
                owner["sample_count"] += int(local["sample_count"])
                owner["solid_ids"].update(local["solid_ids"])
                owner["distribution_keys"].add(row["distribution_key"])
                owner["revision_dates"].add(row["revision_date"])

    summaries.sort(key=lambda item: str(item["distribution_key"]))
    if errors:
        (output_dir / "distribution_errors.txt").write_text(
            "\n".join(errors) + "\n", encoding="utf-8"
        )
        raise RuntimeError(f"{len(errors)} distribution(s) failed")

    persisted = scan_persisted_ids(repo_root)
    regional_ids = set(regional)
    present = regional_ids & set(persisted)
    missing = sorted(regional_ids - set(persisted), key=int)

    assignment_rows: list[dict[str, Any]] = []
    group_ids: dict[tuple[str, str], list[str]] = defaultdict(list)
    municipality_stats: dict[str, dict[str, Any]] = {
        slug: {"municipality": name, "missing": 0, "cells": set(), "batches": 0}
        for slug, name in MUNICIPALITIES
    }
    hold_stats = {
        "hold-unassigned": {"municipality": "", "missing": 0, "cells": set(), "batches": 0},
        "hold-boundary": {"municipality": "", "missing": 0, "cells": set(), "batches": 0},
    }

    for building_id in missing:
        owner = regional[building_id]
        if int(owner["sample_count"]) <= 0:
            municipality_slug = "hold-unassigned"
            municipality_name = ""
            assignment_status = "no_source_xy"
            cell_id = "HOLD_NO_XY"
            cell_east: int | str = ""
            cell_north: int | str = ""
            representative_x = ""
            representative_y = ""
        else:
            x = float(owner["sum_x"]) / int(owner["sample_count"])
            y = float(owner["sum_y"]) / int(owner["sample_count"])
            municipality_slug, municipality_name, assignment_status = municipality_for_point(
                Point(x, y), municipalities
            )
            cell_id, cell_east, cell_north = cell_for_xy(x, y, cell_size)
            representative_x = f"{x:.3f}"
            representative_y = f"{y:.3f}"

        group_ids[(municipality_slug, cell_id)].append(building_id)

        stats = municipality_stats.get(municipality_slug) or hold_stats[municipality_slug]
        stats["missing"] += 1
        stats["cells"].add(cell_id)

        assignment_rows.append({
            "building_id": building_id,
            "municipality_slug": municipality_slug,
            "municipality": municipality_name,
            "assignment_status": assignment_status,
            "cell_id": cell_id,
            "cell_east": cell_east,
            "cell_north": cell_north,
            "representative_x": representative_x,
            "representative_y": representative_y,
            "distribution_keys": ";".join(sorted(owner["distribution_keys"])),
            "revision_dates": ";".join(sorted(owner["revision_dates"])),
            "solid_count": len(owner["solid_ids"]),
        })

    batch_rows: list[dict[str, Any]] = []
    for (municipality_slug, cell_id), ids in sorted(group_ids.items()):
        ids = sorted(ids, key=int)
        for offset in range(0, len(ids), max_batch):
            chunk = ids[offset:offset + max_batch]
            batch_no = offset // max_batch + 1
            batch_id = f"{municipality_slug}-{cell_id}-B{batch_no:02d}"
            stats = municipality_stats.get(municipality_slug) or hold_stats[municipality_slug]
            stats["batches"] += 1
            batch_rows.append({
                "batch_id": batch_id,
                "municipality_slug": municipality_slug,
                "municipality": stats["municipality"],
                "assignment_status": "assigned" if municipality_slug in municipality_stats else municipality_slug,
                "cell_id": cell_id,
                "owner_count": len(chunk),
                "first_building_id": chunk[0],
                "last_building_id": chunk[-1],
                "building_ids": ";".join(chunk),
                "runtime_authorized": "false",
            })

    municipality_rows: list[dict[str, Any]] = []
    for slug, name in MUNICIPALITIES:
        stats = municipality_stats[slug]
        municipality_rows.append({
            "municipality_slug": slug,
            "municipality": name,
            "missing_owner_count": stats["missing"],
            "cell_count": len(stats["cells"]),
            "source_batch_count": stats["batches"],
        })
    for slug in ("hold-boundary", "hold-unassigned"):
        stats = hold_stats[slug]
        municipality_rows.append({
            "municipality_slug": slug,
            "municipality": "",
            "missing_owner_count": stats["missing"],
            "cell_count": len(stats["cells"]),
            "source_batch_count": stats["batches"],
        })

    write_csv(
        output_dir / "missing_owner_assignments.csv",
        [
            "building_id", "municipality_slug", "municipality", "assignment_status",
            "cell_id", "cell_east", "cell_north", "representative_x", "representative_y",
            "distribution_keys", "revision_dates", "solid_count",
        ],
        assignment_rows,
    )
    write_csv(
        output_dir / "source_batches.csv",
        [
            "batch_id", "municipality_slug", "municipality", "assignment_status",
            "cell_id", "owner_count", "first_building_id", "last_building_id",
            "building_ids", "runtime_authorized",
        ],
        batch_rows,
    )
    write_csv(
        output_dir / "municipality_summary.csv",
        ["municipality_slug", "municipality", "missing_owner_count", "cell_count", "source_batch_count"],
        municipality_rows,
    )
    write_csv(
        output_dir / "distribution_summary.csv",
        [
            "distribution_key", "revision_date", "status", "source_records",
            "lod2_records", "unique_building_owners", "empty_owner_records",
            "geometryless_lod2_records", "url",
        ],
        summaries,
    )

    assigned = sum(
        row["missing_owner_count"] for row in municipality_rows
        if row["municipality_slug"] not in {"hold-boundary", "hold-unassigned"}
    )
    hold_boundary = hold_stats["hold-boundary"]["missing"]
    hold_unassigned = hold_stats["hold-unassigned"]["missing"]
    report = {
        "schema_version": 1,
        "scope": "Brussels-Capital Region official UrbIS LoD2 source batch planning",
        "source_crs": CRS,
        "cell_size_m": cell_size,
        "max_source_owners_per_batch": max_batch,
        "official_municipality_count": len(MUNICIPALITIES),
        "selected_current_distributions": len(selected),
        "revision_dates": sorted({
            row["revision_date"] for row in selected if row["revision_date"] != "00000000"
        }),
        "lod2_records": sum(int(row["lod2_records"]) for row in summaries),
        "geometryless_lod2_records": sum(int(row["geometryless_lod2_records"]) for row in summaries),
        "official_unique_building_ids": len(regional_ids),
        "already_persisted_official_ids": len(present),
        "missing_official_building_ids": len(missing),
        "assigned_missing_owners": assigned,
        "boundary_ambiguous_missing_owners": hold_boundary,
        "unassigned_missing_owners": hold_unassigned,
        "planning_cell_count": len(group_ids),
        "source_batch_count": len(batch_rows),
        "municipalities": municipality_rows,
        "runtime_authorized": False,
        "materialization_authorized": False,
        "note": (
            "Planning/evidence only. Municipality assignment uses the mean of official "
            "BuildingSolids XY bbox centres per owner when available. Geometryless source "
            "records are preserved; owners with no usable XY remain HOLD_NO_XY. Boundary/unassigned cases remain HOLD. "
            "Source batches do not authorize runtime loading or semantic visual work."
        ),
    }
    (output_dir / "region_lod2_cell_batch_plan.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    if assigned + hold_boundary + hold_unassigned != len(missing):
        raise RuntimeError("assignment accounting mismatch")
    if sum(int(row["owner_count"]) for row in batch_rows) != len(missing):
        raise RuntimeError("batch accounting mismatch")
    if any(int(row["owner_count"]) > max_batch for row in batch_rows):
        raise RuntimeError("source batch exceeds configured cap")

    print(
        "REGION_LOD2_CELL_BATCH_PLAN_OK: "
        f"{len(regional_ids)} official owners, {len(present)} persisted, {len(missing)} missing, "
        f"{assigned} assigned, {hold_boundary} boundary-hold, {hold_unassigned} unassigned-hold, "
        f"{len(group_ids)} cells, {len(batch_rows)} source batches",
        flush=True,
    )
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--feed-url", default=DEFAULT_FEED)
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--cell-size", type=int, default=500)
    parser.add_argument("--max-batch", type=int, default=250)
    args = parser.parse_args()
    try:
        run(
            args.feed_url,
            args.repo_root.resolve(),
            args.output_dir.resolve(),
            args.workers,
            args.cell_size,
            args.max_batch,
        )
    except Exception as exc:
        print(f"REGION_LOD2_CELL_BATCH_PLAN_ERROR: {exc}", flush=True)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

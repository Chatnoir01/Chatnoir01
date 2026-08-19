#!/usr/bin/env python3
"""Verify one bounded UrbIS LoD2 source batch directly against official source data.

This tool is evidence-only. It reproduces a planned batch from:
- the current official UrbIS 3D Constructions Atom feed;
- one official BuildingSolids distribution;
- the official UrbIS municipality WFS polygon;
- current repository persistence state.

It never writes runtime data and never authorizes materialization.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import re
import tempfile
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from collections import defaultdict
from pathlib import Path
from typing import Any
from xml.etree import ElementTree as ET

import shapefile
from shapely.geometry import Point, shape as shapely_shape

DEFAULT_FEED = (
    "https://urbisdownload.datastore.brussels/atomfeed/"
    "e9ec2aa4-cffd-11ee-bccc-00090ffe0001-fr.xml"
)
WFS_URL = "https://geoservices-urbis.irisnet.be/geoserver/urbisvector/wfs"
WFS_LAYER = "urbisvector:Municipalities"
CRS = "EPSG:31370"
USER_AGENT = "Grand-Bruxelles-UrbIS-LoD2-Source-Batch-Verify/1.0"
ZIP_RE = re.compile(r"UrbISBuildings3D.*31370.*SHP.*\.zip(?:[?#].*)?$", re.I)
DATE_RE = re.compile(r"(?<!\d)(20\d{6})(?!\d)")
BUILDING_URL_RE = re.compile(r"https?://databrussels\.be/id/building/(\d+)", re.I)
OFFICIAL_ID_KEYS = {
    "building_2d_id",
    "building_id",
    "urbis_building_id",
    "source_building_id",
    "bu_id",
}


def http_get(url: str, timeout: int = 180, retries: int = 4) -> bytes:
    last: Exception | None = None
    for attempt in range(retries):
        request = urllib.request.Request(
            url,
            headers={"User-Agent": USER_AGENT, "Accept": "*/*"},
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
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
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


def discover_zip_urls(feed_url: str) -> list[str]:
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
    return re.sub(r"(?<!\d)20\d{6}(?!\d)", "{date}", name).lower()


def resolve_distribution(feed_url: str, key: str, expected_revision: str) -> str:
    target = key.lower()
    matches = [url for url in discover_zip_urls(feed_url) if distribution_key(url) == target]
    if not matches:
        raise RuntimeError(f"distribution not found in official Atom feed: {key}")
    current = max(matches, key=revision)
    current_revision = revision(current)
    if current_revision != expected_revision:
        raise RuntimeError(
            f"source revision drift: expected {expected_revision}, current {current_revision}"
        )
    return current


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
        name
        for name in archive.namelist()
        if name.lower().endswith(suffix.lower()) and "buildingsolid" in name.lower()
    ]
    if len(matches) > 1:
        exact = [
            name
            for name in matches
            if name.lower().endswith("buildingsolids" + suffix.lower())
        ]
        if len(exact) == 1:
            return exact[0]
        raise RuntimeError(f"ambiguous BuildingSolids {suffix}: {matches}")
    return matches[0] if matches else None


def scan_persisted_ids(repo_root: Path) -> set[str]:
    data_root = repo_root / "grand-bruxelles-game" / "data"
    if not data_root.is_dir():
        raise RuntimeError(f"missing data root: {data_root}")
    found: set[str] = set()
    for path in data_root.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in {".json", ".geojson"}:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for match in BUILDING_URL_RE.finditer(text):
            found.add(match.group(1))
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
                            found.add(candidate)
                    if isinstance(value, (dict, list)):
                        stack.append(value)
            elif isinstance(node, list):
                stack.extend(node)
    return found


def request_municipality_feature(name: str) -> dict[str, Any]:
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
    target = normalize(name)
    exact: list[dict[str, Any]] = []
    partial: list[dict[str, Any]] = []
    for feature in data.get("features", []):
        values: set[str] = set()
        for value in (feature.get("properties") or {}).values():
            if value is None or isinstance(value, (dict, list)):
                continue
            values.add(normalize(value))
        if feature.get("id"):
            values.add(normalize(feature["id"]))
        if target in values:
            exact.append(feature)
        elif any(target in value or value in target for value in values if len(value) >= 4):
            partial.append(feature)
    candidates = exact or partial
    if len(candidates) != 1:
        raise RuntimeError(f"municipality {name!r}: expected one official match, got {len(candidates)}")
    return candidates[0]


def read_owner_evidence(package: bytes) -> tuple[dict[str, dict[str, Any]], dict[str, Any]]:
    owners: dict[str, dict[str, Any]] = {}
    stats = {
        "source_records": 0,
        "lod2_records": 0,
        "geometryless_lod2_records": 0,
        "empty_owner_records": 0,
    }
    with zipfile.ZipFile(io.BytesIO(package)) as archive, tempfile.TemporaryDirectory() as tmp:
        shp_name = archive_member(archive, ".shp")
        dbf_name = archive_member(archive, ".dbf")
        shx_name = archive_member(archive, ".shx")
        if not shp_name or not dbf_name:
            raise RuntimeError("BuildingSolids SHP/DBF missing from resolved distribution")
        members = [shp_name, dbf_name]
        if shx_name:
            members.append(shx_name)
        for name in members:
            archive.extract(name, tmp)

        shp_bytes = archive.read(shp_name)
        dbf_bytes = archive.read(dbf_name)
        stats["building_solids_shp_sha256"] = hashlib.sha256(shp_bytes).hexdigest()
        stats["building_solids_dbf_sha256"] = hashlib.sha256(dbf_bytes).hexdigest()

        kwargs: dict[str, str] = {
            "shp": str(Path(tmp) / shp_name),
            "dbf": str(Path(tmp) / dbf_name),
        }
        if shx_name:
            kwargs["shx"] = str(Path(tmp) / shx_name)
        reader = shapefile.Reader(
            **kwargs,
            encoding="utf-8",
            encodingErrors="replace",
        )
        fields = [field[0] for field in reader.fields[1:]]
        building_field = detect_field(fields, "BU_ID", "BUILDING_ID", "BUILDINGID", "BUILD_ID")
        solid_field = detect_field(fields, "INSPIRE_ID", "SOLID_ID", "SOLIDID", "ID")
        lod_field = detect_field(fields, "DETAILSLEV", "DETAILLEVEL", "LOD", "LEVEL")
        if building_field is None:
            raise RuntimeError(f"BU_ID field missing; fields={fields}")

        for shape_record in reader.iterShapeRecords():
            stats["source_records"] += 1
            values = shape_record.record.as_dict()
            if lod_field and not is_lod2(values.get(lod_field)):
                continue
            stats["lod2_records"] += 1
            building_id = numeric_id(values.get(building_field))
            if building_id is None:
                stats["empty_owner_records"] += 1
                continue
            owner = owners.setdefault(
                building_id,
                {
                    "sum_x": 0.0,
                    "sum_y": 0.0,
                    "xy_samples": 0,
                    "geometryless_records": 0,
                    "solid_ids": set(),
                    "bbox_min_x": None,
                    "bbox_min_y": None,
                    "bbox_max_x": None,
                    "bbox_max_y": None,
                    "z_min": None,
                    "z_max": None,
                },
            )
            if solid_field:
                solid_id = str(values.get(solid_field) or "").strip()
                if solid_id:
                    owner["solid_ids"].add(solid_id)

            bbox = getattr(shape_record.shape, "bbox", None)
            if not bbox or len(bbox) < 4:
                owner["geometryless_records"] += 1
                stats["geometryless_lod2_records"] += 1
                continue
            min_x, min_y, max_x, max_y = map(float, bbox[:4])
            owner["sum_x"] += (min_x + max_x) / 2.0
            owner["sum_y"] += (min_y + max_y) / 2.0
            owner["xy_samples"] += 1
            owner["bbox_min_x"] = min_x if owner["bbox_min_x"] is None else min(owner["bbox_min_x"], min_x)
            owner["bbox_min_y"] = min_y if owner["bbox_min_y"] is None else min(owner["bbox_min_y"], min_y)
            owner["bbox_max_x"] = max_x if owner["bbox_max_x"] is None else max(owner["bbox_max_x"], max_x)
            owner["bbox_max_y"] = max_y if owner["bbox_max_y"] is None else max(owner["bbox_max_y"], max_y)

            z_values = getattr(shape_record.shape, "z", None)
            if z_values:
                finite = [float(z) for z in z_values if z is not None]
                if finite:
                    z_min = min(finite)
                    z_max = max(finite)
                    owner["z_min"] = z_min if owner["z_min"] is None else min(owner["z_min"], z_min)
                    owner["z_max"] = z_max if owner["z_max"] is None else max(owner["z_max"], z_max)
    return owners, stats


def inside_bbox(x: float, y: float, bbox: list[float]) -> bool:
    min_x, min_y, max_x, max_y = map(float, bbox)
    return min_x <= x < max_x and min_y <= y < max_y


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    fields = [
        "building_id",
        "solid_count",
        "solid_ids",
        "representative_x",
        "representative_y",
        "source_bbox",
        "source_z_min",
        "source_z_max",
        "height_m",
        "geometryless_records",
    ]
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def run(contract_path: Path, repo_root: Path, output_dir: Path, feed_url: str) -> dict[str, Any]:
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    if contract["hard_rules"]["runtime_authorized"] is not False:
        raise RuntimeError("contract must keep runtime_authorized=false")
    if contract["hard_rules"]["materialization_authorized"] is not False:
        raise RuntimeError("contract must keep materialization_authorized=false")

    source = contract["source"]
    distribution_url = resolve_distribution(
        feed_url,
        source["distribution_key"],
        source["revision"],
    )
    package = http_get(distribution_url)
    package_sha256 = hashlib.sha256(package).hexdigest()
    owners, source_stats = read_owner_evidence(package)
    persisted = scan_persisted_ids(repo_root)

    municipality_feature = request_municipality_feature(contract["municipality"]["name"])
    municipality_geometry = shapely_shape(municipality_feature["geometry"])
    if municipality_geometry.is_empty or not municipality_geometry.is_valid:
        raise RuntimeError("official municipality geometry is invalid/empty")

    bbox = list(map(float, contract["cell"]["bbox"]))
    cell_missing: list[str] = []
    representative: dict[str, tuple[float, float]] = {}
    for building_id, owner in owners.items():
        if building_id in persisted or int(owner["xy_samples"]) <= 0:
            continue
        x = float(owner["sum_x"]) / int(owner["xy_samples"])
        y = float(owner["sum_y"]) / int(owner["xy_samples"])
        if not inside_bbox(x, y, bbox):
            continue
        if not municipality_geometry.covers(Point(x, y)):
            continue
        cell_missing.append(building_id)
        representative[building_id] = (x, y)

    cell_missing.sort(key=int)
    selection = contract["selection"]
    expected_cell_count = int(selection["expected_cell_missing_owners"])
    if len(cell_missing) != expected_cell_count:
        raise RuntimeError(
            f"cell count drift: expected {expected_cell_count}, got {len(cell_missing)}"
        )

    batch_index = int(selection["batch_index"])
    batch_size = int(selection["max_owners"])
    start = (batch_index - 1) * batch_size
    selected = cell_missing[start : start + batch_size]
    if len(selected) != int(selection["expected_owner_count"]):
        raise RuntimeError(
            f"batch owner count drift: expected {selection['expected_owner_count']}, got {len(selected)}"
        )
    if not selected:
        raise RuntimeError("batch selection is empty")
    if selected[0] != str(selection["expected_first_building_id"]):
        raise RuntimeError(
            f"first BU_ID drift: expected {selection['expected_first_building_id']}, got {selected[0]}"
        )
    if selected[-1] != str(selection["expected_last_building_id"]):
        raise RuntimeError(
            f"last BU_ID drift: expected {selection['expected_last_building_id']}, got {selected[-1]}"
        )

    rows: list[dict[str, Any]] = []
    total_solids = 0
    selected_geometryless_records = 0
    for building_id in selected:
        owner = owners[building_id]
        x, y = representative[building_id]
        solid_ids = sorted(owner["solid_ids"])
        total_solids += len(solid_ids)
        selected_geometryless_records += int(owner["geometryless_records"])
        source_bbox = [
            owner["bbox_min_x"],
            owner["bbox_min_y"],
            owner["bbox_max_x"],
            owner["bbox_max_y"],
        ]
        z_min = owner["z_min"]
        z_max = owner["z_max"]
        height = None if z_min is None or z_max is None else float(z_max) - float(z_min)
        rows.append(
            {
                "building_id": building_id,
                "solid_count": len(solid_ids),
                "solid_ids": ";".join(solid_ids),
                "representative_x": f"{x:.3f}",
                "representative_y": f"{y:.3f}",
                "source_bbox": json.dumps(source_bbox, separators=(",", ":")),
                "source_z_min": "" if z_min is None else f"{float(z_min):.3f}",
                "source_z_max": "" if z_max is None else f"{float(z_max):.3f}",
                "height_m": "" if height is None else f"{height:.3f}",
                "geometryless_records": int(owner["geometryless_records"]),
            }
        )

    output_dir.mkdir(parents=True, exist_ok=True)
    write_csv(output_dir / "selected_owner_evidence.csv", rows)
    (output_dir / "selected_building_ids.txt").write_text(
        "\n".join(selected) + "\n",
        encoding="utf-8",
    )

    result = {
        "schema": "grand-bruxelles-urbis-lod2-source-batch-verification-v1",
        "batch_id": contract["batch_id"],
        "production_base_sha": contract["production_base_sha"],
        "source": {
            "dataset": source["dataset"],
            "dataset_id": source["dataset_id"],
            "revision": source["revision"],
            "distribution_key": source["distribution_key"],
            "distribution_url": distribution_url,
            "package_sha256": package_sha256,
            "building_solids_shp_sha256": source_stats["building_solids_shp_sha256"],
            "building_solids_dbf_sha256": source_stats["building_solids_dbf_sha256"],
            "license": source["license"],
            "crs": CRS,
        },
        "source_stats": source_stats,
        "cell_missing_owner_count": len(cell_missing),
        "selected_owner_count": len(selected),
        "selected_first_building_id": selected[0],
        "selected_last_building_id": selected[-1],
        "selected_total_solids": total_solids,
        "selected_geometryless_records": selected_geometryless_records,
        "selected_owner_ids_sha256": hashlib.sha256(
            ("\n".join(selected) + "\n").encode("utf-8")
        ).hexdigest(),
        "runtime_authorized": False,
        "materialization_authorized": False,
        "geometry_modified": False,
    }
    (output_dir / "verification.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        "URBIS_LOD2_SOURCE_BATCH_OK: "
        f"batch={contract['batch_id']} cell_missing={len(cell_missing)} "
        f"selected={len(selected)} first={selected[0]} last={selected[-1]} "
        f"solids={total_solids} package_sha256={package_sha256}",
        flush=True,
    )
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--feed-url", default=DEFAULT_FEED)
    args = parser.parse_args()
    try:
        run(
            args.contract.resolve(),
            args.repo_root.resolve(),
            args.output_dir.resolve(),
            args.feed_url,
        )
    except Exception as exc:
        print(f"URBIS_LOD2_SOURCE_BATCH_ERROR: {exc}", flush=True)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

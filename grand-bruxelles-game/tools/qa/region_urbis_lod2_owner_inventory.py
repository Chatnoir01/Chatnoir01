#!/usr/bin/env python3
"""Inventory official UrbIS 3D LoD2 building owners for all Brussels-Capital.

Evidence-only QA tool:
- discovers current EPSG:31370 SHP Building3D distributions from the official Atom feed;
- reads BuildingSolids DBF/SHP records without altering source geometry;
- unions official BU_ID owners at LoD2;
- compares them with official building IDs already persisted under grand-bruxelles-game/data;
- emits complete JSON/CSV inventories for CI artifacts.

No runtime authorization is implied by appearing in the missing list.
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import re
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from collections import defaultdict
from pathlib import Path
from typing import Iterable
from xml.etree import ElementTree as ET

import shapefile


DEFAULT_FEED = (
    "https://urbisdownload.datastore.brussels/atomfeed/"
    "e9ec2aa4-cffd-11ee-bccc-00090ffe0001-fr.xml"
)
USER_AGENT = "Grand-Bruxelles-UrbIS-LoD2-Inventory/1.0"
ZIP_NAME_RE = re.compile(
    r"UrbISBuildings3D.*?31370.*?SHP.*?\.zip(?:[?#].*)?$", re.IGNORECASE
)
DATE_RE = re.compile(r"(?<!\d)(20\d{6})(?!\d)")
BUILDING_URL_RE = re.compile(
    r"https?://databrussels\.be/id/building/(\d+)", re.IGNORECASE
)
OFFICIAL_ID_KEYS = {
    "building_2d_id",
    "building_id",
    "urbis_building_id",
    "source_building_id",
    "bu_id",
}


def _http_get(url: str, timeout: int = 90, retries: int = 3) -> bytes:
    req = urllib.request.Request(
        url,
        headers={"User-Agent": USER_AGENT, "Accept": "*/*"},
    )
    last_error: Exception | None = None
    for attempt in range(1, retries + 1):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as response:
                return response.read()
        except (urllib.error.URLError, TimeoutError) as exc:
            last_error = exc
            if attempt < retries:
                time.sleep(min(2 ** attempt, 8))
    raise RuntimeError(f"download failed after {retries} attempts: {url}: {last_error}")


def _all_urls_from_xml(xml_bytes: bytes, base_url: str) -> set[str]:
    urls: set[str] = set()
    root = ET.fromstring(xml_bytes)
    for elem in root.iter():
        href = elem.attrib.get("href")
        if href:
            urls.add(urllib.parse.urljoin(base_url, href.strip()))
        if elem.text:
            text = elem.text.strip()
            if text.startswith(("http://", "https://")):
                urls.add(urllib.parse.urljoin(base_url, text))
    return urls


def discover_distribution_urls(feed_url: str, max_xml_pages: int = 1000) -> list[str]:
    """Follow official Atom XML links and collect Building3D EPSG:31370 SHP ZIPs."""
    parsed_feed = urllib.parse.urlparse(feed_url)
    allowed_host = parsed_feed.netloc.lower()
    queue = [feed_url]
    visited: set[str] = set()
    zip_urls: set[str] = set()

    while queue:
        url = queue.pop(0)
        if url in visited:
            continue
        if len(visited) >= max_xml_pages:
            raise RuntimeError(
                f"Atom discovery exceeded safety cap of {max_xml_pages} XML pages"
            )
        visited.add(url)
        xml_bytes = _http_get(url)
        for candidate in _all_urls_from_xml(xml_bytes, url):
            parsed = urllib.parse.urlparse(candidate)
            if parsed.scheme not in {"http", "https"}:
                continue
            if parsed.netloc.lower() != allowed_host:
                continue
            clean_path = parsed.path.lower()
            if ZIP_NAME_RE.search(candidate):
                zip_urls.add(candidate)
                continue
            if clean_path.endswith((".xml", ".atom")):
                queue.append(candidate)

    if not zip_urls:
        raise RuntimeError(
            "Official Atom feed discovery returned no "
            "UrbISBuildings3D EPSG:31370 SHP ZIP distributions"
        )
    return sorted(zip_urls)


def _revision_date(url: str) -> str:
    matches = DATE_RE.findall(urllib.parse.unquote(url))
    return max(matches) if matches else "00000000"


def _distribution_key(url: str) -> str:
    """Stable key for one distribution while ignoring an 8-digit revision date."""
    filename = Path(urllib.parse.urlparse(url).path).name
    stem = re.sub(r"(?<!\d)20\d{6}(?!\d)", "{DATE}", filename)
    return stem.lower()


def select_latest_distributions(urls: Iterable[str]) -> list[dict[str, str]]:
    """Keep latest revision for each official distribution/tile."""
    latest: dict[str, tuple[str, str]] = {}
    for url in urls:
        key = _distribution_key(url)
        date = _revision_date(url)
        current = latest.get(key)
        if current is None or date > current[0]:
            latest[key] = (date, url)
    rows = [
        {"distribution_key": key, "revision_date": date, "url": url}
        for key, (date, url) in latest.items()
    ]
    rows.sort(key=lambda row: (row["distribution_key"], row["url"]))
    return rows


def _detect_field(field_names: list[str], candidates: Iterable[str]) -> str | None:
    normalized = {name.upper(): name for name in field_names}
    for candidate in candidates:
        if candidate.upper() in normalized:
            return normalized[candidate.upper()]
    return None


def _safe_id(value: object) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    if re.fullmatch(r"\d+", text):
        return text
    match = BUILDING_URL_RE.fullmatch(text)
    return match.group(1) if match else None


def _lod2(value: object) -> bool:
    if value is None:
        return True
    text = str(value).strip().lower()
    if text in {"", "none", "null"}:
        return True
    try:
        return int(float(text)) == 2
    except ValueError:
        return text in {"lod2", "2d", "level2", "level_2"}


def inspect_distribution(
    url: str,
    distribution_key: str,
    revision_date: str,
) -> tuple[dict[str, dict[str, object]], dict[str, object]]:
    """Return owner observations + distribution summary."""
    payload = _http_get(url, timeout=180, retries=3)
    owners: dict[str, dict[str, object]] = {}
    source_records = 0
    lod2_records = 0
    empty_owner_records = 0

    with zipfile.ZipFile(io.BytesIO(payload)) as zf, tempfile.TemporaryDirectory() as tmp:
        shp_names = [
            name for name in zf.namelist()
            if name.lower().endswith("buildingsolids.shp")
        ]
        if not shp_names:
            shp_names = [
                name for name in zf.namelist()
                if name.lower().endswith(".shp") and "buildingsolid" in name.lower()
            ]
        if len(shp_names) != 1:
            raise RuntimeError(
                f"{distribution_key}: expected one BuildingSolids SHP, found {shp_names}"
            )

        shp_name = shp_names[0]
        base = shp_name[:-4]
        members = {
            ext: next(
                (name for name in zf.namelist() if name.lower() == f"{base}.{ext}".lower()),
                None,
            )
            for ext in ("shp", "shx", "dbf")
        }
        if not all(members.values()):
            raise RuntimeError(
                f"{distribution_key}: incomplete shapefile companions: {members}"
            )
        for member in members.values():
            assert member is not None
            zf.extract(member, tmp)

        shp_path = Path(tmp) / members["shp"]
        reader = shapefile.Reader(str(shp_path), encoding="utf-8", encodingErrors="replace")
        fields = [field[0] for field in reader.fields[1:]]
        building_field = _detect_field(
            fields, ("BU_ID", "BUILDING_ID", "BUILDINGID", "BUILD_ID")
        )
        solid_field = _detect_field(
            fields, ("INSPIRE_ID", "SOLID_ID", "SOLIDID", "ID")
        )
        lod_field = _detect_field(
            fields, ("DETAILSLEV", "DETAILLEVEL", "LOD", "LEVEL")
        )
        if building_field is None:
            raise RuntimeError(
                f"{distribution_key}: could not detect BU_ID field from {fields}"
            )

        for sr in reader.iterShapeRecords():
            source_records += 1
            record = sr.record.as_dict()
            if lod_field is not None and not _lod2(record.get(lod_field)):
                continue
            lod2_records += 1
            building_id = _safe_id(record.get(building_field))
            if building_id is None:
                empty_owner_records += 1
                continue
            solid_id = str(record.get(solid_field)).strip() if solid_field else ""
            owner = owners.setdefault(
                building_id,
                {
                    "building_id": building_id,
                    "solid_ids": set(),
                },
            )
            if solid_id:
                owner["solid_ids"].add(solid_id)

    normalized = {
        building_id: {
            "building_id": building_id,
            "solid_ids": sorted(obs["solid_ids"]),
        }
        for building_id, obs in owners.items()
    }
    summary = {
        "distribution_key": distribution_key,
        "revision_date": revision_date,
        "url": url,
        "source_records": source_records,
        "lod2_records": lod2_records,
        "unique_building_owners": len(normalized),
        "empty_owner_records": empty_owner_records,
    }
    return normalized, summary


def _extract_id_from_key_value(key: str, value: object) -> str | None:
    key_l = key.lower()
    if key_l not in OFFICIAL_ID_KEYS and not (
        "urbis" in key_l and "building" in key_l
    ):
        return None
    if isinstance(value, (str, int)):
        return _safe_id(value)
    return None


def scan_persisted_official_ids(repo_root: Path) -> dict[str, list[str]]:
    """Find official building IDs already persisted in project data."""
    data_root = repo_root / "grand-bruxelles-game" / "data"
    found: dict[str, set[str]] = defaultdict(set)
    if not data_root.is_dir():
        raise RuntimeError(f"data root not found: {data_root}")

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
                    candidate = _extract_id_from_key_value(str(key), value)
                    if candidate is not None:
                        found[candidate].add(rel)
                    if isinstance(value, (dict, list)):
                        stack.append(value)
            elif isinstance(node, list):
                stack.extend(node)

    return {building_id: sorted(paths) for building_id, paths in found.items()}


def _write_csv(path: Path, fieldnames: list[str], rows: Iterable[dict[str, object]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def run(feed_url: str, repo_root: Path, output_dir: Path) -> dict[str, object]:
    output_dir.mkdir(parents=True, exist_ok=True)

    discovered = discover_distribution_urls(feed_url)
    selected = select_latest_distributions(discovered)

    regional: dict[str, dict[str, object]] = {}
    distribution_summaries: list[dict[str, object]] = []

    for index, row in enumerate(selected, start=1):
        print(
            f"[{index}/{len(selected)}] {row['distribution_key']} "
            f"revision={row['revision_date']}",
            flush=True,
        )
        observations, summary = inspect_distribution(
            row["url"], row["distribution_key"], row["revision_date"]
        )
        distribution_summaries.append(summary)
        for building_id, obs in observations.items():
            owner = regional.setdefault(
                building_id,
                {
                    "building_id": building_id,
                    "distribution_keys": set(),
                    "revision_dates": set(),
                    "solid_ids": set(),
                },
            )
            owner["distribution_keys"].add(row["distribution_key"])
            owner["revision_dates"].add(row["revision_date"])
            owner["solid_ids"].update(obs["solid_ids"])

    persisted = scan_persisted_official_ids(repo_root)
    regional_ids = set(regional)
    persisted_ids = set(persisted)
    present = sorted(regional_ids & persisted_ids, key=int)
    missing = sorted(regional_ids - persisted_ids, key=int)
    persisted_not_in_current_region = sorted(persisted_ids - regional_ids, key=int)

    owner_rows: list[dict[str, object]] = []
    for building_id in sorted(regional, key=int):
        obs = regional[building_id]
        owner_rows.append(
            {
                "building_id": building_id,
                "status": "persisted" if building_id in persisted else "missing",
                "distribution_keys": ";".join(sorted(obs["distribution_keys"])),
                "revision_dates": ";".join(sorted(obs["revision_dates"])),
                "solid_count": len(obs["solid_ids"]),
                "solid_ids": ";".join(sorted(obs["solid_ids"])),
                "persisted_paths": ";".join(persisted.get(building_id, [])),
            }
        )

    _write_csv(
        output_dir / "region_urbis_lod2_building_owners.csv",
        [
            "building_id",
            "status",
            "distribution_keys",
            "revision_dates",
            "solid_count",
            "solid_ids",
            "persisted_paths",
        ],
        owner_rows,
    )
    _write_csv(
        output_dir / "missing_urbis_lod2_building_ids.csv",
        ["building_id", "distribution_keys", "revision_dates", "solid_count", "solid_ids"],
        [
            {
                "building_id": row["building_id"],
                "distribution_keys": row["distribution_keys"],
                "revision_dates": row["revision_dates"],
                "solid_count": row["solid_count"],
                "solid_ids": row["solid_ids"],
            }
            for row in owner_rows
            if row["status"] == "missing"
        ],
    )
    _write_csv(
        output_dir / "persisted_urbis_lod2_building_ids.csv",
        ["building_id", "persisted_paths"],
        [
            {
                "building_id": building_id,
                "persisted_paths": ";".join(persisted[building_id]),
            }
            for building_id in present
        ],
    )
    _write_csv(
        output_dir / "distribution_summary.csv",
        [
            "distribution_key",
            "revision_date",
            "source_records",
            "lod2_records",
            "unique_building_owners",
            "empty_owner_records",
            "url",
        ],
        distribution_summaries,
    )

    report = {
        "schema_version": 1,
        "scope": "Brussels-Capital Region / official UrbIS 3D Constructions LoD2 owners",
        "feed_url": feed_url,
        "discovered_distribution_urls": len(discovered),
        "selected_current_distributions": len(selected),
        "revision_dates": sorted(
            {row["revision_date"] for row in selected if row["revision_date"] != "00000000"}
        ),
        "source_records": sum(int(row["source_records"]) for row in distribution_summaries),
        "lod2_records": sum(int(row["lod2_records"]) for row in distribution_summaries),
        "official_unique_building_ids": len(regional_ids),
        "already_persisted_official_ids": len(present),
        "missing_official_building_ids": len(missing),
        "persisted_ids_not_in_current_region_inventory": persisted_not_in_current_region,
        "missing_building_ids": missing,
        "present_building_ids": present,
        "runtime_authorized": False,
        "note": (
            "Evidence inventory only. A BU_ID appearing here does not authorize runtime "
            "geometry, collision, semantic naming, or promotion."
        ),
    }
    (output_dir / "region_urbis_lod2_inventory.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    print(
        "REGION_URBIS_LOD2_INVENTORY_OK: "
        f"{len(selected)} distributions, "
        f"{report['lod2_records']} LoD2 source records, "
        f"{len(regional_ids)} official owners, "
        f"{len(present)} already persisted, "
        f"{len(missing)} missing",
        flush=True,
    )
    print(
        "REGION_URBIS_LOD2_REVISION_DATES: "
        + ",".join(report["revision_dates"]),
        flush=True,
    )
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--feed-url", default=DEFAULT_FEED)
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()

    try:
        run(args.feed_url, args.repo_root.resolve(), args.output_dir.resolve())
    except Exception as exc:
        print(f"REGION_URBIS_LOD2_INVENTORY_ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

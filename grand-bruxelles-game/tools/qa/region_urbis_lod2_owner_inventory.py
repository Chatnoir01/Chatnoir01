#!/usr/bin/env python3
"""Evidence-only inventory of official UrbIS LoD2 building owners for Brussels-Capital."""

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
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from xml.etree import ElementTree as ET

import shapefile

DEFAULT_FEED = (
    "https://urbisdownload.datastore.brussels/atomfeed/"
    "e9ec2aa4-cffd-11ee-bccc-00090ffe0001-fr.xml"
)
USER_AGENT = "Grand-Bruxelles-UrbIS-LoD2-Inventory/2.0"
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


def inspect_distribution(row: dict[str, str]) -> tuple[dict[str, set[str]], dict[str, object]]:
    payload = http_get(row["url"])
    owners: dict[str, set[str]] = defaultdict(set)
    summary: dict[str, object] = {
        **row,
        "status": "ok",
        "source_records": 0,
        "lod2_records": 0,
        "unique_building_owners": 0,
        "empty_owner_records": 0,
    }

    with zipfile.ZipFile(io.BytesIO(payload)) as archive, tempfile.TemporaryDirectory() as tmp:
        dbfs = [
            name for name in archive.namelist()
            if name.lower().endswith("buildingsolids.dbf")
        ]
        if not dbfs:
            dbfs = [
                name for name in archive.namelist()
                if name.lower().endswith(".dbf") and "buildingsolid" in name.lower()
            ]
        if not dbfs:
            summary["status"] = "no_building_solids"
            return {}, summary
        if len(dbfs) != 1:
            raise RuntimeError(f"expected one BuildingSolids DBF, found {dbfs}")

        dbf_name = dbfs[0]
        archive.extract(dbf_name, tmp)
        reader = shapefile.Reader(dbf=str(Path(tmp) / dbf_name), encoding="utf-8", encodingErrors="replace")
        fields = [field[0] for field in reader.fields[1:]]
        building_field = detect_field(fields, "BU_ID", "BUILDING_ID", "BUILDINGID", "BUILD_ID")
        solid_field = detect_field(fields, "INSPIRE_ID", "SOLID_ID", "SOLIDID", "ID")
        lod_field = detect_field(fields, "DETAILSLEV", "DETAILLEVEL", "LOD", "LEVEL")
        if building_field is None:
            raise RuntimeError(f"BU_ID field missing; fields={fields}")

        for record in reader.iterRecords():
            summary["source_records"] = int(summary["source_records"]) + 1
            values = record.as_dict()
            if lod_field and not is_lod2(values.get(lod_field)):
                continue
            summary["lod2_records"] = int(summary["lod2_records"]) + 1
            building_id = numeric_id(values.get(building_field))
            if building_id is None:
                summary["empty_owner_records"] = int(summary["empty_owner_records"]) + 1
                continue
            solid_id = str(values.get(solid_field)).strip() if solid_field else ""
            if solid_id:
                owners[building_id].add(solid_id)
            else:
                owners.setdefault(building_id, set())

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


def write_csv(path: Path, fields: list[str], rows: list[dict[str, object]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def run(feed_url: str, repo_root: Path, output_dir: Path, workers: int) -> dict[str, object]:
    output_dir.mkdir(parents=True, exist_ok=True)
    discovered = discover_distributions(feed_url)
    selected = latest_distributions(discovered)
    print(
        f"REGION_URBIS_LOD2_DISCOVERY: discovered={len(discovered)} "
        f"current={len(selected)} workers={workers}",
        flush=True,
    )

    regional: dict[str, dict[str, set[str]]] = {}
    summaries: list[dict[str, object]] = []
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
            for building_id, solid_ids in owners.items():
                owner = regional.setdefault(
                    building_id,
                    {"distribution_keys": set(), "revision_dates": set(), "solid_ids": set()},
                )
                owner["distribution_keys"].add(row["distribution_key"])
                owner["revision_dates"].add(row["revision_date"])
                owner["solid_ids"].update(solid_ids)

    summaries.sort(key=lambda item: str(item["distribution_key"]))
    if errors:
        (output_dir / "distribution_errors.txt").write_text("\n".join(errors) + "\n", encoding="utf-8")
        raise RuntimeError(f"{len(errors)} distribution(s) failed; see distribution_errors.txt")

    persisted = scan_persisted_ids(repo_root)
    regional_ids = set(regional)
    persisted_ids = set(persisted)
    present = sorted(regional_ids & persisted_ids, key=int)
    missing = sorted(regional_ids - persisted_ids, key=int)

    rows: list[dict[str, object]] = []
    for building_id in sorted(regional_ids, key=int):
        owner = regional[building_id]
        rows.append({
            "building_id": building_id,
            "status": "persisted" if building_id in persisted else "missing",
            "distribution_keys": ";".join(sorted(owner["distribution_keys"])),
            "revision_dates": ";".join(sorted(owner["revision_dates"])),
            "solid_count": len(owner["solid_ids"]),
            "solid_ids": ";".join(sorted(owner["solid_ids"])),
            "persisted_paths": ";".join(persisted.get(building_id, [])),
        })

    write_csv(
        output_dir / "region_urbis_lod2_building_owners.csv",
        ["building_id", "status", "distribution_keys", "revision_dates", "solid_count", "solid_ids", "persisted_paths"],
        rows,
    )
    write_csv(
        output_dir / "missing_urbis_lod2_building_ids.csv",
        ["building_id", "distribution_keys", "revision_dates", "solid_count", "solid_ids"],
        [{key: row[key] for key in ["building_id", "distribution_keys", "revision_dates", "solid_count", "solid_ids"]} for row in rows if row["status"] == "missing"],
    )
    write_csv(
        output_dir / "persisted_urbis_lod2_building_ids.csv",
        ["building_id", "persisted_paths"],
        [{"building_id": building_id, "persisted_paths": ";".join(persisted[building_id])} for building_id in present],
    )
    write_csv(
        output_dir / "distribution_summary.csv",
        ["distribution_key", "revision_date", "status", "source_records", "lod2_records", "unique_building_owners", "empty_owner_records", "url"],
        summaries,
    )

    report = {
        "schema_version": 2,
        "scope": "Brussels-Capital Region / official UrbIS 3D Constructions LoD2 owners",
        "feed_url": feed_url,
        "discovered_distribution_urls": len(discovered),
        "selected_current_distributions": len(selected),
        "distributions_with_building_solids": sum(1 for row in summaries if row["status"] == "ok"),
        "empty_distributions_skipped": sum(1 for row in summaries if row["status"] == "no_building_solids"),
        "revision_dates": sorted({row["revision_date"] for row in selected if row["revision_date"] != "00000000"}),
        "source_records": sum(int(row["source_records"]) for row in summaries),
        "lod2_records": sum(int(row["lod2_records"]) for row in summaries),
        "official_unique_building_ids": len(regional_ids),
        "already_persisted_official_ids": len(present),
        "missing_official_building_ids": len(missing),
        "missing_building_ids": missing,
        "present_building_ids": present,
        "persisted_ids_not_in_current_region_inventory": sorted(persisted_ids - regional_ids, key=int),
        "runtime_authorized": False,
        "note": "Evidence only; no semantic naming, geometry, collision or runtime authorization.",
    }
    (output_dir / "region_urbis_lod2_inventory.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    print(
        "REGION_URBIS_LOD2_INVENTORY_OK: "
        f"{len(selected)} distributions, {report['lod2_records']} LoD2 records, "
        f"{len(regional_ids)} official owners, {len(present)} persisted, {len(missing)} missing",
        flush=True,
    )
    print("REGION_URBIS_LOD2_REVISION_DATES: " + ",".join(report["revision_dates"]), flush=True)
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--feed-url", default=DEFAULT_FEED)
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--workers", type=int, default=10)
    args = parser.parse_args()
    try:
        run(args.feed_url, args.repo_root.resolve(), args.output_dir.resolve(), args.workers)
    except Exception as exc:
        print(f"REGION_URBIS_LOD2_INVENTORY_ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

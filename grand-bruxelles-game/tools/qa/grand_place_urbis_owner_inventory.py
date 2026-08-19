#!/usr/bin/env python3
import hashlib
import json
import pathlib
import re
import sys
import urllib.request
import zipfile

try:
    import shapefile
except ImportError as exc:
    raise SystemExit(f"pyshp is required: {exc}")

ROOT = pathlib.Path(__file__).resolve().parents[2]
CONTRACT_PATH = ROOT / "data/qa/grand_place_urbis_owner_inventory_contract.json"
OUT_DIR = ROOT / "artifacts/qa"
OUT_PATH = OUT_DIR / "grand_place_urbis_owner_inventory.json"
CACHE_DIR = ROOT / ".cache/grand_place_urbis_owner_inventory"


def fail(message: str) -> None:
    print(f"GRAND_PLACE_URBIS_OWNER_INVENTORY_FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def sha256(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def intersects(a, b) -> bool:
    return not (a[2] < b[0] or a[0] > b[2] or a[3] < b[1] or a[1] > b[3])


def clean(value):
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace").strip()
    if isinstance(value, str):
        return value.strip()
    return value


def compact_id(value):
    if value is None:
        return None
    text = str(value).strip()
    match = re.search(r"/(?:building|buildingsolid)/(\d+)$", text)
    if match:
        return match.group(1)
    if text.isdigit():
        return text
    return None


def choose_field(fields, patterns):
    lowered = {name.lower(): name for name in fields}
    for pattern in patterns:
        for lower, original in lowered.items():
            if pattern in lower:
                return original
    return None


def shape_bbox_xy(shape):
    """Return authoritative 2D extent from source XY vertices, or None when empty."""
    points = getattr(shape, "points", None) or []
    if not points:
        return None
    xs = [float(point[0]) for point in points]
    ys = [float(point[1]) for point in points]
    return [min(xs), min(ys), max(xs), max(ys)]


def main() -> None:
    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    source = contract["source"]
    window = contract["inventory_window_lambert72"]
    known = set(contract["known_persisted_building_ids"])

    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    zip_path = CACHE_DIR / "urbis_buildings3d.zip"
    extract_dir = CACHE_DIR / "unzipped"

    if not zip_path.exists():
        print(f"Downloading {source['package_url']}")
        urllib.request.urlretrieve(source["package_url"], zip_path)

    actual_hash = sha256(zip_path)
    if actual_hash != source["package_sha256"]:
        fail(f"package sha256 mismatch: {actual_hash}")

    if not extract_dir.exists():
        extract_dir.mkdir(parents=True)
        with zipfile.ZipFile(zip_path) as archive:
            archive.extractall(extract_dir)

    shp_files = list(extract_dir.rglob("*.shp"))
    if not shp_files:
        fail("no shapefiles found in official package")

    solid_candidates = [p for p in shp_files if "solid" in p.name.lower()]
    if not solid_candidates:
        fail("no BuildingSolids-like shapefile found")
    solid_path = sorted(solid_candidates, key=lambda p: ("buildingsolid" not in p.name.lower(), len(p.name)))[0]

    reader = shapefile.Reader(str(solid_path))
    field_names = [f[0] for f in reader.fields[1:]]
    # Official UrbIS BuildingSolids schema observed in the locked 2026-08-08 package:
    # BU_ID carries the parent Building URI and INSPIRE_ID carries the BuildingSolid URI.
    building_field = "BU_ID" if "BU_ID" in field_names else choose_field(
        field_names, ["building_2d", "building2d", "buildingid", "building_id", "building"]
    )
    solid_field = "INSPIRE_ID" if "INSPIRE_ID" in field_names else choose_field(
        field_names, ["solidid", "solid_id", "solid"]
    )
    print(json.dumps({
        "source_shapefile": solid_path.name,
        "dbf_fields": field_names,
        "detected_building_field": building_field,
        "detected_solid_field": solid_field,
    }, ensure_ascii=False))

    records = []
    recovered_known = set()
    empty_geometry_record_count = 0
    empty_geometry_examples = []

    for shape_record in reader.iterShapeRecords():
        attrs = {field_names[i]: clean(value) for i, value in enumerate(shape_record.record)}
        building_raw = attrs.get(building_field) if building_field else None
        solid_raw = attrs.get(solid_field) if solid_field else None
        building_id = compact_id(building_raw)
        solid_id = compact_id(solid_raw)

        bbox = shape_bbox_xy(shape_record.shape)
        if bbox is None:
            empty_geometry_record_count += 1
            if len(empty_geometry_examples) < 10:
                empty_geometry_examples.append({"building_id": building_id, "solid_id": solid_id, "attributes": attrs})
            continue

        if not intersects(bbox, window):
            continue
        if building_id in known:
            recovered_known.add(building_id)
        records.append({
            "building_id": building_id,
            "solid_id": solid_id,
            "source_bbox_xy": bbox,
            "known_persisted": building_id in known,
            "attributes": attrs,
        })

    missing_known = sorted(known - recovered_known)
    if missing_known:
        diagnostic = {
            "schema": "grand-bruxelles-grand-place-urbis-owner-inventory-diagnostic-v1",
            "source_package_sha256": actual_hash,
            "source_shapefile": solid_path.name,
            "dbf_fields": field_names,
            "detected_building_field": building_field,
            "detected_solid_field": solid_field,
            "inventory_window_lambert72": window,
            "intersecting_solid_count": len(records),
            "known_persisted_building_ids": sorted(known, key=int),
            "recovered_known_building_ids": sorted(recovered_known, key=int),
            "missing_known_building_ids": missing_known,
            "sample_intersecting_records": records[:10],
            "empty_geometry_record_count": empty_geometry_record_count,
            "empty_geometry_examples": empty_geometry_examples,
            "runtime_authorized": False,
            "semantic_registration_authorized": False,
        }
        OUT_PATH.write_text(json.dumps(diagnostic, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(json.dumps({
            "diagnostic_intersecting_count": len(records),
            "sample_intersecting_records": records[:3],
        }, ensure_ascii=False))
        fail(f"known persisted building ids not recovered from official package/window: {missing_known}")

    def sort_key(item):
        bid = item.get("building_id")
        return (bid is None, int(bid) if bid and bid.isdigit() else 10**18, item.get("solid_id") or "")

    records.sort(key=sort_key)
    new_buildings = sorted({r["building_id"] for r in records if r["building_id"] and not r["known_persisted"]}, key=int)
    report = {
        "schema": "grand-bruxelles-grand-place-urbis-owner-inventory-report-v1",
        "source_package_sha256": actual_hash,
        "source_shapefile": solid_path.name,
        "dbf_fields": field_names,
        "detected_building_field": building_field,
        "detected_solid_field": solid_field,
        "inventory_window_lambert72": window,
        "bbox_method": "source_vertex_xy_extent",
        "empty_geometry_policy": "skip_and_report; never nominate or persist empty source geometry",
        "empty_geometry_record_count": empty_geometry_record_count,
        "empty_geometry_examples": empty_geometry_examples,
        "intersecting_solid_count": len(records),
        "known_persisted_building_ids": sorted(known, key=int),
        "recovered_known_building_ids": sorted(recovered_known, key=int),
        "new_candidate_building_ids": new_buildings,
        "new_candidate_building_count": len(new_buildings),
        "records": records,
        "runtime_authorized": False,
        "semantic_registration_authorized": False,
    }
    OUT_PATH.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(
        "GRAND_PLACE_URBIS_OWNER_INVENTORY_OK: "
        f"{len(records)} solids, {len(new_buildings)} new building candidates, "
        f"{empty_geometry_record_count} empty source records skipped"
    )
    print(json.dumps({"new_candidate_building_ids": new_buildings}, ensure_ascii=False))


if __name__ == "__main__":
    main()

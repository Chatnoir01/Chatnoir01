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
OUT_DIR = ROOT / "artifacts/qa/grand_place_perimeter_lod2"
CACHE_DIR = ROOT / ".cache/grand_place_perimeter_lod2"
PACKAGE_URL = "https://urbisdownload.datastore.brussels/UrbIS/Vector/M8/UrbIS-Buildings3D/SHP/UrbISBuildings3D_31370_SHP_148170_20260808.zip"
PACKAGE_SHA256 = "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2"
BUILDING_FACES_SHA256 = "5371b8dfc65bb0565677ccbbeb0936444d827daba81a7e508de3d5f530536997"
BUILDING_SOLIDS_SHA256 = "e11a1ddae370037f1495c7fa2d106245c70fc36a4c5c15c7eb48bd676900c0ec"
TARGET_BUILDINGS = [
    "1608847", "1608851", "1611166", "1613517", "1635455",
    "1637695", "1645578", "1647943", "1653185",
]
CONTROL_BUILDING = "1639974"
LAMBERT_ORIGIN = (147868.29422791934, 169538.62414926197)
WORLD_ORIGIN = (-668.5, 0.0, 627.84)


def fail(message: str) -> None:
    print(f"GRAND_PLACE_PERIMETER_LOD2_EXTRACT_FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def sha256(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def clean(value):
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace").strip()
    if isinstance(value, str):
        return value.strip()
    return value


def compact_id(value, kind: str):
    if value is None:
        return None
    text = str(value).strip()
    m = re.search(rf"/{kind}/(\d+)$", text)
    if m:
        return m.group(1)
    return text if text.isdigit() else None


def shape_zs(shape):
    values = getattr(shape, "z", None)
    return [float(v) for v in values] if values is not None else []


def source_bbox_xy(shape):
    points = list(getattr(shape, "points", None) or [])
    if not points:
        return None
    xs = [float(p[0]) for p in points]
    ys = [float(p[1]) for p in points]
    return [min(xs), min(ys), max(xs), max(ys)]


def ring_triangles(shape, source_base_z):
    points = list(getattr(shape, "points", None) or [])
    zs = shape_zs(shape)
    if not points or len(points) != len(zs):
        return [], {}
    parts = list(getattr(shape, "parts", None) or [0])
    part_types = list(getattr(shape, "partTypes", None) or [4] * len(parts))
    ends = parts[1:] + [len(points)]
    triangles = []
    part_counts = {}
    for idx, (start, end) in enumerate(zip(parts, ends)):
        ptype = int(part_types[idx]) if idx < len(part_types) else 4
        part_counts[str(ptype)] = part_counts.get(str(ptype), 0) + 1
        ring = []
        for i in range(start, end):
            sx, sy = float(points[i][0]), float(points[i][1])
            sz = float(zs[i])
            wx = sx - LAMBERT_ORIGIN[0] + WORLD_ORIGIN[0]
            wy = sz - source_base_z
            wz = WORLD_ORIGIN[2] - (sy - LAMBERT_ORIGIN[1])
            ring.append([round(wx, 4), round(wy, 4), round(wz, 4)])
        if len(ring) >= 2 and ring[0] == ring[-1]:
            ring.pop()
        if len(ring) < 3:
            continue
        for i in range(1, len(ring) - 1):
            triangles.append([ring[0], ring[i], ring[i + 1]])
    return triangles, part_counts


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    zip_path = CACHE_DIR / "urbis_buildings3d.zip"
    extract_dir = CACHE_DIR / "unzipped"
    if not zip_path.exists():
        print(f"Downloading {PACKAGE_URL}")
        urllib.request.urlretrieve(PACKAGE_URL, zip_path)
    if sha256(zip_path) != PACKAGE_SHA256:
        fail("package sha256 mismatch")
    if not extract_dir.exists():
        extract_dir.mkdir(parents=True)
        with zipfile.ZipFile(zip_path) as archive:
            archive.extractall(extract_dir)

    shp_files = list(extract_dir.rglob("*.shp"))
    solids_path = next((p for p in shp_files if "BuildingSolids" in p.name), None)
    faces_path = next((p for p in shp_files if "BuildingFaces" in p.name), None)
    if solids_path is None or faces_path is None:
        fail("BuildingSolids/BuildingFaces shapefiles not found")
    if sha256(solids_path) != BUILDING_SOLIDS_SHA256:
        fail("BuildingSolids sha256 mismatch")
    if sha256(faces_path) != BUILDING_FACES_SHA256:
        fail("BuildingFaces sha256 mismatch")

    requested = set(TARGET_BUILDINGS + [CONTROL_BUILDING])
    solids = shapefile.Reader(str(solids_path))
    solid_fields = [f[0] for f in solids.fields[1:]]
    if "BU_ID" not in solid_fields or "INSPIRE_ID" not in solid_fields:
        fail(f"unexpected BuildingSolids fields: {solid_fields}")
    building_solids = {bid: [] for bid in requested}
    for sr in solids.iterShapeRecords():
        attrs = {solid_fields[i]: clean(v) for i, v in enumerate(sr.record)}
        bid = compact_id(attrs.get("BU_ID"), "building")
        if bid not in requested:
            continue
        sid = compact_id(attrs.get("INSPIRE_ID"), "buildingsolid")
        if sid:
            building_solids[bid].append(sid)
    missing = sorted([bid for bid, sids in building_solids.items() if not sids], key=int)
    if missing:
        fail(f"missing official BuildingSolids owners: {missing}")

    faces = shapefile.Reader(str(faces_path))
    face_fields = [f[0] for f in faces.fields[1:]]
    required = {"INSPIRE_ID", "BS_ID", "TYPE"}
    if not required.issubset(set(face_fields)):
        fail(f"unexpected BuildingFaces fields: {face_fields}")
    detail_field = "DETAILSLEV" if "DETAILSLEV" in face_fields else None
    solid_to_building = {
        sid: bid for bid, sids in building_solids.items() for sid in sids
    }
    raw_faces = {bid: [] for bid in requested}
    z_by_building = {bid: [] for bid in requested}
    for sr in faces.iterShapeRecords():
        attrs = {face_fields[i]: clean(v) for i, v in enumerate(sr.record)}
        sid = compact_id(attrs.get("BS_ID"), "buildingsolid")
        bid = solid_to_building.get(sid)
        if bid is None:
            continue
        zs = shape_zs(sr.shape)
        z_by_building[bid].extend(zs)
        raw_faces[bid].append((sr.shape, attrs, sid))

    outputs = {}
    summaries = []
    for bid in sorted(requested, key=int):
        if not raw_faces[bid] or not z_by_building[bid]:
            fail(f"building {bid} has no BuildingFaces geometry")
        base_z = min(z_by_building[bid])
        max_z = max(z_by_building[bid])
        out_faces = []
        type_counts = {}
        triangle_count = 0
        part_type_counts = {}
        bboxes = []
        for shape, attrs, sid in raw_faces[bid]:
            fid = compact_id(attrs.get("INSPIRE_ID"), "buildingface")
            ftype = str(attrs.get("TYPE", "")).upper()
            tris, part_counts = ring_triangles(shape, base_z)
            if not tris:
                continue
            bbox = source_bbox_xy(shape)
            if bbox:
                bboxes.append(bbox)
            triangle_count += len(tris)
            type_counts[ftype] = type_counts.get(ftype, 0) + 1
            for key, value in part_counts.items():
                part_type_counts[key] = part_type_counts.get(key, 0) + value
            out_faces.append({
                "id": f"https://databrussels.be/id/buildingface/{fid}" if fid else str(attrs.get("INSPIRE_ID")),
                "solid_id": f"https://databrussels.be/id/buildingsolid/{sid}",
                "type": ftype,
                "details_level": attrs.get(detail_field) if detail_field else None,
                "triangles": tris,
            })
        if not bboxes:
            fail(f"building {bid} has no source bbox")
        bbox = [
            min(v[0] for v in bboxes), min(v[1] for v in bboxes),
            max(v[2] for v in bboxes), max(v[3] for v in bboxes),
        ]
        output = {
            "schema": "grand-bruxelles-urbis-context-mesh-v1",
            "context_id": f"grand_place_perimeter_{bid}",
            "name": f"Grand-Place official LoD2 owner {bid}",
            "source": {
                "provider": "Paradigm / Brussels-Capital Region",
                "dataset": "UrbIS - 3D Constructions",
                "dataset_id": "e9ec2aa4-cffd-11ee-bccc-00090ffe0001",
                "package_url": PACKAGE_URL,
                "package_sha256": PACKAGE_SHA256,
                "building_faces_shp_sha256": BUILDING_FACES_SHA256,
                "building_solids_shp_sha256": BUILDING_SOLIDS_SHA256,
                "package_revision": "2026-08-08",
                "license": "CC0-1.0",
                "crs": "EPSG:31370",
                "building_2d_id": f"https://databrussels.be/id/building/{bid}",
                "building_solid_ids": [f"https://databrussels.be/id/buildingsolid/{sid}" for sid in sorted(building_solids[bid], key=int)],
                "solid_count": len(building_solids[bid]),
                "details_level": 2,
            },
            "transform": {
                "lambert72_origin": list(LAMBERT_ORIGIN),
                "world_origin": list(WORLD_ORIGIN),
                "source_base_z": round(base_z, 3),
            },
            "evidence": {
                "source_bbox_xy": [round(v, 3) for v in bbox],
                "source_z_min": round(base_z, 3),
                "source_z_max": round(max_z, 3),
                "height_m": round(max_z - base_z, 3),
                "solid_count": len(building_solids[bid]),
                "face_count": len(out_faces),
                "face_type_counts": type_counts,
                "triangle_count": triangle_count,
                "multipatch_part_type_counts": part_type_counts,
            },
            "runtime_approved": False,
            "approval_note": "Authoritative CC0 LoD2 geometry only; semantic identity and runtime presentation require separate validation.",
            "faces": out_faces,
        }
        outputs[bid] = output
        (OUT_DIR / f"{bid}.game.json").write_text(json.dumps(output, separators=(",", ":"), ensure_ascii=False) + "\n", encoding="utf-8")
        summaries.append({"building_id": bid, **output["evidence"]})

    control = outputs[CONTROL_BUILDING]["evidence"]
    if control["face_count"] != 9 or control["triangle_count"] != 26:
        fail(f"control {CONTROL_BUILDING} triangulation drifted: {control}")
    if control["face_type_counts"] != {"WALLSURFACE": 6, "GROUNDSURFACE": 1, "ROOFSURFACE": 2}:
        fail(f"control {CONTROL_BUILDING} face-type contract drifted")

    report = {
        "schema": "grand-bruxelles-grand-place-perimeter-lod2-extract-v1",
        "source_package_sha256": PACKAGE_SHA256,
        "control_building_id": CONTROL_BUILDING,
        "target_building_ids": TARGET_BUILDINGS,
        "target_count": len(TARGET_BUILDINGS),
        "summaries": [s for s in summaries if s["building_id"] != CONTROL_BUILDING],
        "runtime_authorized": False,
        "semantic_registration_authorized": False,
    }
    (OUT_DIR / "report.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"GRAND_PLACE_PERIMETER_LOD2_EXTRACT_OK: {len(TARGET_BUILDINGS)} target buildings")
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()

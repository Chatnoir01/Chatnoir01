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
OUT_DIR = ROOT / "artifacts/qa/grand_place_contiguous_lod2_front"
CACHE_DIR = ROOT / ".cache/grand_place_contiguous_lod2_front"
PACKAGE_URL = "https://urbisdownload.datastore.brussels/UrbIS/Vector/M8/UrbIS-Buildings3D/SHP/UrbISBuildings3D_31370_SHP_148170_20260808.zip"
PACKAGE_SHA256 = "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2"
BUILDING_FACES_SHA256 = "5371b8dfc65bb0565677ccbbeb0936444d827daba81a7e508de3d5f530536997"
BUILDING_SOLIDS_SHA256 = "e11a1ddae370037f1495c7fa2d106245c70fc36a4c5c15c7eb48bd676900c0ec"
TARGET_BUILDINGS = [
    "1601883", "1601884", "1635485", "1637729", "1639985", "1643344",
    "1645580", "1646728", "1647834", "1649069", "1661439", "1781508",
]
CONTROL_BUILDING = "1639974"
LAMBERT_ORIGIN = (147868.29422791934, 169538.62414926197)
WORLD_ORIGIN = (-668.5, 0.0, 627.84)


def fail(message: str) -> None:
    print(f"GRAND_PLACE_CONTIGUOUS_LOD2_EXTRACT_FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def sha256(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def compact_id(value, kind: str):
    if value is None:
        return None
    text = str(value).strip()
    match = re.search(rf"/{kind}/(\d+)$", text)
    if match:
        return match.group(1)
    if text.isdigit():
        return text
    return None


def clean(value):
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace").strip()
    if isinstance(value, str):
        return value.strip()
    return value


def pick_field(fields, preferred, contains):
    by_upper = {f.upper(): f for f in fields}
    for p in preferred:
        if p.upper() in by_upper:
            return by_upper[p.upper()]
    for token in contains:
        for f in fields:
            if token.lower() in f.lower():
                return f
    return None


def source_bbox_xy(shape):
    pts = getattr(shape, "points", None) or []
    if not pts:
        return None
    xs = [float(p[0]) for p in pts]
    ys = [float(p[1]) for p in pts]
    return [min(xs), min(ys), max(xs), max(ys)]


def shape_zs(shape):
    zs = getattr(shape, "z", None)
    if zs is None:
        return []
    return [float(v) for v in zs]


def ring_triangles(shape, source_base_z):
    points = list(getattr(shape, "points", None) or [])
    zs = shape_zs(shape)
    if not points or len(points) != len(zs):
        return []
    parts = list(getattr(shape, "parts", None) or [0])
    if not parts:
        parts = [0]
    part_types = list(getattr(shape, "partTypes", None) or [4] * len(parts))
    ends = parts[1:] + [len(points)]
    triangles = []
    type_counts = {}
    for idx, (start, end) in enumerate(zip(parts, ends)):
        ptype = int(part_types[idx]) if idx < len(part_types) else 4
        type_counts[str(ptype)] = type_counts.get(str(ptype), 0) + 1
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
        # BuildingFaces in this official package are planar rings. Persisted
        # Grand-Place control 1639974 was produced with deterministic fan
        # triangulation from the first ring vertex; preserve that exact policy.
        for i in range(1, len(ring) - 1):
            triangles.append([ring[0], ring[i], ring[i + 1]])
    return triangles, type_counts


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

    solids = shapefile.Reader(str(solids_path))
    solid_fields = [f[0] for f in solids.fields[1:]]
    bu_field = pick_field(solid_fields, ["BU_ID"], ["building"])
    solid_id_field = pick_field(solid_fields, ["INSPIRE_ID"], ["solid"])
    if bu_field is None or solid_id_field is None:
        fail(f"solid DBF mapping unresolved: {solid_fields}")

    requested = set(TARGET_BUILDINGS + [CONTROL_BUILDING])
    building_solids = {bid: [] for bid in requested}
    solid_bboxes = {}
    for sr in solids.iterShapeRecords():
        attrs = {solid_fields[i]: clean(v) for i, v in enumerate(sr.record)}
        bid = compact_id(attrs.get(bu_field), "building")
        if bid not in requested:
            continue
        sid = compact_id(attrs.get(solid_id_field), "buildingsolid")
        if not sid:
            continue
        building_solids[bid].append(sid)
        solid_bboxes[(bid, sid)] = source_bbox_xy(sr.shape)

    missing = [bid for bid, sids in building_solids.items() if not sids]
    if missing:
        fail(f"target buildings missing solids: {sorted(missing, key=int)}")

    faces = shapefile.Reader(str(faces_path))
    face_fields = [f[0] for f in faces.fields[1:]]
    face_id_field = pick_field(face_fields, ["INSPIRE_ID"], ["face"])
    face_solid_field = pick_field(face_fields, ["BS_ID", "SOLID_ID"], ["solid"])
    face_type_field = pick_field(face_fields, ["TYPE", "FACETYPE", "SURFTYPE"], ["type"])
    detail_field = pick_field(face_fields, ["DETAILSLEV"], ["detail"])
    print(json.dumps({
        "solids_shp": solids_path.name,
        "solid_fields": solid_fields,
        "faces_shp": faces_path.name,
        "face_fields": face_fields,
        "face_id_field": face_id_field,
        "face_solid_field": face_solid_field,
        "face_type_field": face_type_field,
        "detail_field": detail_field,
    }, ensure_ascii=False))
    if face_id_field is None or face_solid_field is None or face_type_field is None:
        fail("face DBF mapping unresolved")

    solid_to_building = {}
    for bid, sids in building_solids.items():
        for sid in sids:
            solid_to_building[sid] = bid

    raw_faces = {bid: [] for bid in requested}
    z_by_building = {bid: [] for bid in requested}
    for sr in faces.iterShapeRecords():
        attrs = {face_fields[i]: clean(v) for i, v in enumerate(sr.record)}
        sid = compact_id(attrs.get(face_solid_field), "buildingsolid")
        bid = solid_to_building.get(sid)
        if bid is None:
            continue
        zs = shape_zs(sr.shape)
        z_by_building[bid].extend(zs)
        raw_faces[bid].append((sr.shape, attrs, sid))

    summaries = []
    all_outputs = {}
    for bid in sorted(requested, key=int):
        if not raw_faces[bid] or not z_by_building[bid]:
            fail(f"building {bid} has no BuildingFaces geometry")
        base_z = min(z_by_building[bid])
        max_z = max(z_by_building[bid])
        out_faces = []
        type_counts = {}
        triangle_count = 0
        part_type_counts = {}
        source_bboxes = []
        for shape, attrs, sid in raw_faces[bid]:
            fid = compact_id(attrs.get(face_id_field), "buildingface")
            ftype = str(attrs.get(face_type_field, "")).upper()
            detail = attrs.get(detail_field) if detail_field else None
            tris, part_counts = ring_triangles(shape, base_z)
            if not tris:
                continue
            triangle_count += len(tris)
            type_counts[ftype] = type_counts.get(ftype, 0) + 1
            for key, value in part_counts.items():
                part_type_counts[key] = part_type_counts.get(key, 0) + value
            bbox = source_bbox_xy(shape)
            if bbox:
                source_bboxes.append(bbox)
            out_faces.append({
                "id": f"https://databrussels.be/id/buildingface/{fid}" if fid else str(attrs.get(face_id_field)),
                "solid_id": f"https://databrussels.be/id/buildingsolid/{sid}",
                "type": ftype,
                "details_level": detail,
                "triangles": tris,
            })
        if not source_bboxes:
            fail(f"building {bid} has no source bbox")
        bbox = [
            min(b[0] for b in source_bboxes), min(b[1] for b in source_bboxes),
            max(b[2] for b in source_bboxes), max(b[3] for b in source_bboxes),
        ]
        output = {
            "schema": "grand-bruxelles-urbis-context-mesh-v1",
            "context_id": f"grand_place_contiguous_front_{bid}",
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
            "approval_note": "Authoritative CC0 LoD2 geometry only; runtime presentation requires separate player-eye validation.",
            "faces": out_faces,
        }
        all_outputs[bid] = output
        (OUT_DIR / f"{bid}.game.json").write_text(json.dumps(output, separators=(",", ":"), ensure_ascii=False) + "\n", encoding="utf-8")
        summaries.append({"building_id": bid, **output["evidence"]})

    control = all_outputs[CONTROL_BUILDING]["evidence"]
    if control["face_count"] != 9 or control["triangle_count"] != 26:
        fail(f"control {CONTROL_BUILDING} triangulation drifted: {control}")
    if control["face_type_counts"] != {"WALLSURFACE": 6, "GROUNDSURFACE": 1, "ROOFSURFACE": 2}:
        fail(f"control {CONTROL_BUILDING} face types drifted: {control['face_type_counts']}")

    report = {
        "schema": "grand-bruxelles-grand-place-contiguous-lod2-front-extract-v1",
        "source_package_sha256": PACKAGE_SHA256,
        "control_building_id": CONTROL_BUILDING,
        "target_building_ids": TARGET_BUILDINGS,
        "target_count": len(TARGET_BUILDINGS),
        "summaries": [s for s in summaries if s["building_id"] != CONTROL_BUILDING],
        "runtime_authorized": False,
        "semantic_registration_authorized": False,
    }
    (OUT_DIR / "report.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("GRAND_PLACE_CONTIGUOUS_LOD2_EXTRACT_OK: %d target buildings" % len(TARGET_BUILDINGS))
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()

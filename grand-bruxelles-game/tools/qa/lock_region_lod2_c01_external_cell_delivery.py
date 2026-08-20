#!/usr/bin/env python3
import argparse
import csv
import hashlib
import json
import re
from pathlib import Path

LOCK_SCHEMA = "grand-bruxelles-region-lod2-c01-external-cell-delivery-lock-v1"
MANIFEST_SCHEMA = "grand-bruxelles-region-lod2-c01-external-cell-delivery-manifest-v1"
CAMPAIGN_ID = "region-lod2-C01-30000"
CELL_RE = re.compile(r"^E(-?\d+)_N(-?\d+)$")

EXPECTED_HARD_RULES = {
    "external_delivery_manifest_authorized": True,
    "runtime_authorized": False,
    "runtime_mount_authorized": False,
    "collision_authorized": False,
    "terrain_runtime_authorized": False,
    "source_geometry_modified": False,
    "jouable_promotion_authorized": False,
    "artifact_only": True,
    "web_pck_embedded": False,
}

def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def canonical_json_bytes(obj) -> bytes:
    return (json.dumps(obj, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode("utf-8")

def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))

def validate_contract(c):
    if c.get("schema") != LOCK_SCHEMA:
        raise SystemExit("contract schema drift")
    if c.get("campaign_id") != CAMPAIGN_ID:
        raise SystemExit("campaign drift")
    if c.get("production_base_sha") != "245432e538bb52d454dd205c0b7e337fe4db093d":
        raise SystemExit("production base drift")

    upstream = c.get("upstream_final_world_geometry", {})
    required_upstream = {
        "source_pr": 981,
        "source_head_sha": "1eb4f3f79157000f95c2a230332ff43d3e58bb7f",
        "workflow_run_id": 32318835420,
        "artifact_id": 9389058771,
        "artifact_name": "region-lod2-c01-30000-final-world-geometry",
        "artifact_archive_sha256": "007077a3d5d6d4da0c78fbe2918d0fa5b0ecf4b8c72fa16e711a0dfefa4b1b1d",
        "artifact_digest": "sha256:007077a3d5d6d4da0c78fbe2918d0fa5b0ecf4b8c72fa16e711a0dfefa4b1b1d",
        "world_geometry_index_sha256": "af8c37bd501ed076a45d1c12eafc3b2208e071e3961c3fd07eabede36befc35c",
        "cell_payload_chain_sha256": "184c0c7fdf41a99eca523a637eb7cacfaf02b15886a7903f8c86ff80e326f6ab",
    }
    if upstream != required_upstream:
        raise SystemExit("upstream final-world artifact identity drift")

    delivery = c.get("delivery", {})
    if delivery != {
        "mode": "external_per_cell",
        "cell_size_m": 500,
        "artifact_relative_root": "cells",
        "public_base_url_locked": False,
        "immutable_by_sha256": True,
    }:
        raise SystemExit("delivery policy drift")

    expected = c.get("expected", {})
    if expected != {
        "owners": 30000,
        "spatial_cells": 132,
        "solids": 30944,
        "faces": 532211,
        "points": 3273027,
        "parts": 534100,
        "source_payload_bytes": 222598504,
        "world_payload_bytes": 200842561,
    }:
        raise SystemExit("expected accounting drift")

    if c.get("hard_rules") != EXPECTED_HARD_RULES:
        raise SystemExit("hard authorization rails drift")

    expected_hashes = c.get("expected_output_sha256", {})
    if set(expected_hashes) != {
        "external_cell_delivery_manifest.json",
        "external_cell_delivery_cells.csv",
    }:
        raise SystemExit("expected output hash set drift")
    for name, digest in expected_hashes.items():
        if not re.fullmatch(r"[0-9a-f]{64}", str(digest)):
            raise SystemExit(f"invalid expected output hash: {name}")

def bounds_from_cell_id(cell_id: str, cell_size_m: int):
    m = CELL_RE.fullmatch(cell_id)
    if not m:
        raise SystemExit(f"invalid cell id: {cell_id}")
    east = int(m.group(1))
    north = int(m.group(2))
    if east % cell_size_m or north % cell_size_m:
        raise SystemExit(f"cell id not aligned to {cell_size_m}m grid: {cell_id}")
    return {
        "east_min": east,
        "east_max": east + cell_size_m,
        "north_min": north,
        "north_max": north + cell_size_m,
    }

def build_manifest(contract, artifact_dir: Path):
    upstream = contract["upstream_final_world_geometry"]
    index_path = artifact_dir / "world_geometry_index.json"
    if not index_path.is_file():
        raise SystemExit("missing upstream world_geometry_index.json")
    index_bytes = index_path.read_bytes()
    if sha256_bytes(index_bytes) != upstream["world_geometry_index_sha256"]:
        raise SystemExit("upstream world geometry index hash drift")
    index = json.loads(index_bytes)

    if index.get("schema") != "grand-bruxelles-region-lod2-c01-final-world-geometry-v1":
        raise SystemExit("upstream index schema drift")
    if index.get("campaign_id") != CAMPAIGN_ID:
        raise SystemExit("upstream campaign drift")
    if index.get("cell_payload_chain_sha256") != upstream["cell_payload_chain_sha256"]:
        raise SystemExit("upstream cell payload chain drift")
    if index.get("artifact_only") is not True:
        raise SystemExit("upstream must remain artifact-only")
    for key in (
        "runtime_authorized",
        "runtime_mount_authorized",
        "collision_authorized",
        "terrain_runtime_authorized",
        "source_geometry_modified",
        "jouable_promotion_authorized",
    ):
        if index.get(key) is not False:
            raise SystemExit(f"upstream closed rail drift: {key}")

    expected = contract["expected"]
    accounting = index.get("accounting", {})
    for src_key, expected_key in (
        ("owners", "owners"),
        ("spatial_cells", "spatial_cells"),
        ("solids", "solids"),
        ("faces", "faces"),
        ("points", "points"),
        ("parts", "parts"),
        ("source_payload_bytes", "source_payload_bytes"),
    ):
        if accounting.get(src_key) != expected[expected_key]:
            raise SystemExit(f"upstream accounting drift: {src_key}")

    cells = index.get("cells")
    if not isinstance(cells, dict) or len(cells) != expected["spatial_cells"]:
        raise SystemExit("upstream cell count drift")

    rows = []
    seen_paths = set()
    total_world_bytes = 0
    totals = {k: 0 for k in ("owner_count", "solid_count", "face_count", "point_count", "part_count")}
    cell_size_m = contract["delivery"]["cell_size_m"]

    for cell_id in sorted(cells):
        item = cells[cell_id]
        expected_rel = f"cells/{cell_id}/world.ndjson"
        if item.get("relative_path") != expected_rel:
            raise SystemExit(f"cell relative path drift: {cell_id}")
        if expected_rel in seen_paths:
            raise SystemExit(f"duplicate cell path: {expected_rel}")
        seen_paths.add(expected_rel)
        payload = artifact_dir / expected_rel
        if not payload.is_file():
            raise SystemExit(f"missing cell payload: {expected_rel}")
        data = payload.read_bytes()
        if len(data) != item.get("bytes"):
            raise SystemExit(f"cell byte length drift: {cell_id}")
        if sha256_bytes(data) != item.get("sha256"):
            raise SystemExit(f"cell sha256 drift: {cell_id}")
        if item.get("coordinate_space") != "game world XYZ":
            raise SystemExit(f"coordinate-space drift: {cell_id}")

        total_world_bytes += len(data)
        for key in totals:
            value = item.get(key)
            if not isinstance(value, int) or value < 0:
                raise SystemExit(f"invalid {key}: {cell_id}")
            totals[key] += value

        row = {
            "cell_id": cell_id,
            "relative_path": expected_rel,
            "sha256": item["sha256"],
            "bytes": item["bytes"],
            "coordinate_space": item["coordinate_space"],
            "lambert72_bounds": bounds_from_cell_id(cell_id, cell_size_m),
            "owner_count": item["owner_count"],
            "solid_count": item["solid_count"],
            "face_count": item["face_count"],
            "point_count": item["point_count"],
            "part_count": item["part_count"],
            "face_type_counts": item.get("face_type_counts", {}),
        }
        if "source_sha256" in item:
            row["source_sha256"] = item["source_sha256"]
        if "source_bytes" in item:
            row["source_bytes"] = item["source_bytes"]
        rows.append(row)

    if total_world_bytes != expected["world_payload_bytes"]:
        raise SystemExit("world payload byte total drift")
    if totals != {
        "owner_count": expected["owners"],
        "solid_count": expected["solids"],
        "face_count": expected["faces"],
        "point_count": expected["points"],
        "part_count": expected["parts"],
    }:
        raise SystemExit(f"cell aggregate accounting drift: {totals}")

    manifest = {
        "schema": MANIFEST_SCHEMA,
        "campaign_id": CAMPAIGN_ID,
        "payload_mode": "external_per_cell",
        "source": {
            "production_base_sha": contract["production_base_sha"],
            "workflow_run_id": upstream["workflow_run_id"],
            "artifact_id": upstream["artifact_id"],
            "artifact_name": upstream["artifact_name"],
            "artifact_digest": upstream["artifact_digest"],
            "world_geometry_index_sha256": upstream["world_geometry_index_sha256"],
            "cell_payload_chain_sha256": upstream["cell_payload_chain_sha256"],
        },
        "delivery": {
            "artifact_relative_root": contract["delivery"]["artifact_relative_root"],
            "public_base_url": None,
            "public_base_url_locked": False,
            "immutable_by_sha256": True,
            "web_pck_embedded": False,
        },
        "accounting": {
            "owners": expected["owners"],
            "spatial_cells": expected["spatial_cells"],
            "solids": expected["solids"],
            "faces": expected["faces"],
            "points": expected["points"],
            "parts": expected["parts"],
            "source_payload_bytes": expected["source_payload_bytes"],
            "world_payload_bytes": expected["world_payload_bytes"],
        },
        "hard_rules": EXPECTED_HARD_RULES,
        "cells": rows,
    }
    return manifest

def csv_bytes(manifest) -> bytes:
    header = [
        "cell_id", "relative_path", "sha256", "bytes",
        "east_min", "east_max", "north_min", "north_max",
        "owner_count", "solid_count", "face_count", "point_count", "part_count",
    ]
    import io
    s = io.StringIO(newline="")
    w = csv.DictWriter(s, fieldnames=header, lineterminator="\n")
    w.writeheader()
    for cell in manifest["cells"]:
        b = cell["lambert72_bounds"]
        w.writerow({
            "cell_id": cell["cell_id"],
            "relative_path": cell["relative_path"],
            "sha256": cell["sha256"],
            "bytes": cell["bytes"],
            "east_min": b["east_min"],
            "east_max": b["east_max"],
            "north_min": b["north_min"],
            "north_max": b["north_max"],
            "owner_count": cell["owner_count"],
            "solid_count": cell["solid_count"],
            "face_count": cell["face_count"],
            "point_count": cell["point_count"],
            "part_count": cell["part_count"],
        })
    return s.getvalue().encode("utf-8")

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--contract", required=True)
    p.add_argument("--artifact-dir")
    p.add_argument("--output-dir")
    p.add_argument("--validate-only", action="store_true")
    args = p.parse_args()

    contract = load_json(Path(args.contract))
    validate_contract(contract)
    if args.validate_only:
        print("C01_EXTERNAL_CELL_DELIVERY_CONTRACT_OK")
        return

    if not args.artifact_dir or not args.output_dir:
        raise SystemExit("--artifact-dir and --output-dir are required unless --validate-only")

    manifest = build_manifest(contract, Path(args.artifact_dir))
    outputs = {
        "external_cell_delivery_manifest.json": canonical_json_bytes(manifest),
        "external_cell_delivery_cells.csv": csv_bytes(manifest),
    }
    actual = {name: sha256_bytes(data) for name, data in outputs.items()}
    if actual != contract["expected_output_sha256"]:
        raise SystemExit(f"output hash drift: {actual}")

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    for name, data in outputs.items():
        (out_dir / name).write_bytes(data)
    result = {
        **actual,
        "upstream_world_geometry_index_sha256": contract["upstream_final_world_geometry"]["world_geometry_index_sha256"],
        "upstream_cell_payload_chain_sha256": contract["upstream_final_world_geometry"]["cell_payload_chain_sha256"],
    }
    (out_dir / "result.sha256.json").write_bytes(canonical_json_bytes(result))
    print(
        "C01_EXTERNAL_CELL_DELIVERY_LOCKED_GREEN: "
        f"cells={len(manifest['cells'])} owners={manifest['accounting']['owners']} "
        f"world_payload_bytes={manifest['accounting']['world_payload_bytes']}"
    )

if __name__ == "__main__":
    main()

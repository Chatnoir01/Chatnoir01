#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import struct
from pathlib import Path

EXPECTED_COUNT = 8
EXPECTED_PACK_SHA256 = "6b1d673e4c1fd169372d3a74fe174d9c185069c1f55ff6bf6b224f6655e4b67a"


def sha256_path(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_glb_json(path: Path) -> dict:
    data = path.read_bytes()
    if len(data) < 20 or data[:4] != b"glTF":
        raise ValueError(f"{path.name}: invalid GLB magic")
    version, total_length = struct.unpack_from("<II", data, 4)
    if version != 2:
        raise ValueError(f"{path.name}: expected GLB v2, got {version}")
    if total_length != len(data):
        raise ValueError(f"{path.name}: GLB length mismatch header={total_length} actual={len(data)}")
    json_length, json_type = struct.unpack_from("<II", data, 12)
    if json_type != 0x4E4F534A:
        raise ValueError(f"{path.name}: first GLB chunk is not JSON")
    raw = data[20 : 20 + json_length].rstrip(b" \x00")
    return json.loads(raw.decode("utf-8"))


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify Grand Bruxelles MPFB Gate-8 GLB artifact")
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    directory = args.directory.resolve()
    manifest_path = directory / "gate8_glb_manifest.json"
    if not manifest_path.is_file():
        raise SystemExit("GATE8_GLB_VERIFY_FAIL manifest missing")

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    problems: list[str] = []
    if manifest.get("character_count") != EXPECTED_COUNT:
        problems.append(f"character_count={manifest.get('character_count')}")
    if manifest.get("mpfb_version") != "2.0.17":
        problems.append(f"mpfb_version={manifest.get('mpfb_version')}")
    if manifest.get("rig") != "game_engine":
        problems.append(f"rig={manifest.get('rig')}")
    if manifest.get("scale_factor") != "METER":
        problems.append(f"scale_factor={manifest.get('scale_factor')}")
    if manifest.get("asset_pack_sha256") != EXPECTED_PACK_SHA256:
        problems.append(f"asset_pack_sha256={manifest.get('asset_pack_sha256')}")

    records = manifest.get("characters", [])
    if len(records) != EXPECTED_COUNT:
        problems.append(f"records={len(records)}")

    ids: set[str] = set()
    seeds: set[int] = set()
    total_bytes = 0
    for index, record in enumerate(records, start=1):
        expected_id = f"npc_gate_{index:02d}"
        rid = record.get("id")
        if rid != expected_id:
            problems.append(f"index {index}: id={rid} expected={expected_id}")
        if rid in ids:
            problems.append(f"duplicate id={rid}")
        ids.add(rid)

        seed = record.get("seed")
        if not isinstance(seed, int) or seed <= 0:
            problems.append(f"{rid}: invalid seed={seed}")
        elif seed in seeds:
            problems.append(f"{rid}: duplicate seed={seed}")
        else:
            seeds.add(seed)

        height = record.get("height_m")
        if not isinstance(height, (int, float)) or not 1.25 <= float(height) <= 2.30:
            problems.append(f"{rid}: implausible height={height}")
        ground = record.get("ground_min_z_m")
        if not isinstance(ground, (int, float)) or abs(float(ground)) > 0.01:
            problems.append(f"{rid}: grounding={ground}")
        if record.get("armature_count") != 1:
            problems.append(f"{rid}: armature_count={record.get('armature_count')}")
        if not isinstance(record.get("mesh_count"), int) or record["mesh_count"] < 1:
            problems.append(f"{rid}: mesh_count={record.get('mesh_count')}")

        glb_path = directory / str(record.get("glb", ""))
        if not glb_path.is_file():
            problems.append(f"{rid}: GLB missing")
            continue
        size = glb_path.stat().st_size
        total_bytes += size
        if size != record.get("size_bytes"):
            problems.append(f"{rid}: size mismatch manifest={record.get('size_bytes')} actual={size}")
        digest = sha256_path(glb_path)
        if digest != record.get("sha256"):
            problems.append(f"{rid}: sha256 mismatch")

        try:
            doc = read_glb_json(glb_path)
        except (ValueError, json.JSONDecodeError, UnicodeDecodeError) as exc:
            problems.append(str(exc))
            continue
        if not doc.get("meshes"):
            problems.append(f"{rid}: no glTF meshes")
        if not doc.get("skins"):
            problems.append(f"{rid}: no glTF skins")
        if not doc.get("materials"):
            problems.append(f"{rid}: no glTF materials")
        if not doc.get("nodes"):
            problems.append(f"{rid}: no glTF nodes")
        for image in doc.get("images", []):
            uri = image.get("uri")
            if uri and not str(uri).startswith("data:"):
                problems.append(f"{rid}: external image URI={uri}")
        for buffer in doc.get("buffers", []):
            uri = buffer.get("uri")
            if uri:
                problems.append(f"{rid}: external buffer URI={uri}")

    if problems:
        print("GATE8_GLB_VERIFY_FAIL")
        for problem in problems:
            print("-", problem)
        return 1

    print(
        "GATE8_GLB_VERIFY_OK "
        f"characters={len(records)} total_bytes={total_bytes} "
        f"blender={manifest.get('blender_version')} mpfb={manifest.get('mpfb_version')}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Character/NPC retarget source characterization.

This tool intentionally does NOT authorize adoption. It records immutable package
identity plus exact animation names exposed by the pinned Godot GLB so a later
Godot 4.7.1 retarget experiment can select clips without substring guessing.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import struct
import zipfile
from pathlib import Path

ANIMATION_EXTENSIONS = {".glb", ".gltf", ".fbx", ".blend", ".tscn", ".tres", ".anim"}
GODOT_STANDARD_GLB = "Animation Library[Standard]/Godot/AnimationLibrary_Godot_Standard.glb"
LOCOMOTION_TOKENS = ("idle", "walk", "run")
REJECT_TOKENS = {
    "attack", "combat", "fire", "shoot", "punch", "kick", "sword", "gun",
    "to", "transition", "start", "stop", "turn", "strafe", "back", "backward", "reverse",
}
TOKEN_SPLIT = re.compile(r"[^a-z0-9]+")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def tokens_for_name(name: str) -> set[str]:
    stem = Path(name).stem.lower()
    return {token for token in TOKEN_SPLIT.split(stem) if token}


def classify_entry(name: str) -> list[str]:
    tokens = tokens_for_name(name)
    if tokens & REJECT_TOKENS:
        return []
    return [token for token in LOCOMOTION_TOKENS if token in tokens]


def glb_json_document(payload: bytes) -> dict[str, object]:
    if len(payload) < 20:
        raise ValueError("GLB payload too short")
    magic, version, declared_length = struct.unpack_from("<4sII", payload, 0)
    if magic != b"glTF":
        raise ValueError("invalid GLB magic")
    if version != 2:
        raise ValueError(f"unsupported GLB version: {version}")
    if declared_length != len(payload):
        raise ValueError(f"GLB length mismatch: header={declared_length} actual={len(payload)}")

    offset = 12
    while offset + 8 <= len(payload):
        chunk_length, chunk_type = struct.unpack_from("<II", payload, offset)
        offset += 8
        end = offset + chunk_length
        if end > len(payload):
            raise ValueError("GLB chunk extends past payload")
        chunk = payload[offset:end]
        offset = end
        if chunk_type == 0x4E4F534A:  # JSON
            try:
                parsed = json.loads(chunk.rstrip(b"\x00 \t\r\n").decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                raise ValueError(f"invalid GLB JSON chunk: {exc}") from exc
            if not isinstance(parsed, dict):
                raise ValueError("GLB JSON root is not an object")
            return parsed
    raise ValueError("GLB JSON chunk missing")


def internal_animation_names(payload: bytes) -> list[str]:
    document = glb_json_document(payload)
    animations = document.get("animations", [])
    if not isinstance(animations, list):
        raise ValueError("GLB animations field is not a list")
    names: list[str] = []
    for index, animation in enumerate(animations):
        if not isinstance(animation, dict):
            raise ValueError(f"GLB animation {index} is not an object")
        name = animation.get("name")
        if not isinstance(name, str) or not name.strip():
            raise ValueError(f"GLB animation {index} has no stable non-empty name")
        names.append(name.strip())
    if len(names) != len(set(names)):
        raise ValueError("GLB animation names are not unique")
    return names


def characterize(package: Path) -> dict[str, object]:
    if not zipfile.is_zipfile(package):
        raise ValueError(f"not a zip archive: {package}")

    filename_token_hits: dict[str, list[str]] = {token: [] for token in LOCOMOTION_TOKENS}
    internal_token_hits: dict[str, list[str]] = {token: [] for token in LOCOMOTION_TOKENS}
    animation_entries: list[str] = []
    total_uncompressed = 0

    with zipfile.ZipFile(package) as archive:
        infos = [info for info in archive.infolist() if not info.is_dir()]
        if not infos:
            raise ValueError("empty source archive")
        for info in infos:
            total_uncompressed += info.file_size
            suffix = Path(info.filename).suffix.lower()
            if suffix not in ANIMATION_EXTENSIONS:
                continue
            animation_entries.append(info.filename)
            for token in classify_entry(info.filename):
                filename_token_hits[token].append(info.filename)

        names = internal_animation_names(archive.read(GODOT_STANDARD_GLB))
        for name in names:
            for token in classify_entry(name):
                internal_token_hits[token].append(name)

    package_sha = sha256_file(package)
    complete_filename_token_surface = all(filename_token_hits[token] for token in LOCOMOTION_TOKENS)
    complete_internal_token_surface = all(internal_token_hits[token] for token in LOCOMOTION_TOKENS)
    exact_single_trio = all(len(internal_token_hits[token]) == 1 for token in LOCOMOTION_TOKENS)
    return {
        "format": "grand-bruxelles-gate8-retarget-source-probe-v2",
        "package_sha256": package_sha,
        "package_size_bytes": package.stat().st_size,
        "zip_file_entries": len(infos),
        "zip_uncompressed_bytes": total_uncompressed,
        "animation_asset_entries": sorted(animation_entries),
        "animation_asset_entry_count": len(animation_entries),
        "filename_token_hits": {key: sorted(value) for key, value in filename_token_hits.items()},
        "complete_filename_token_surface": complete_filename_token_surface,
        "godot_standard_glb": GODOT_STANDARD_GLB,
        "internal_animation_names": names,
        "internal_animation_count": len(names),
        "internal_token_hits": {key: sorted(value) for key, value in internal_token_hits.items()},
        "complete_internal_token_surface": complete_internal_token_surface,
        "exact_single_idle_walk_run_trio": exact_single_trio,
        "candidate_variant": 1,
        "production_authorized": False,
        "retarget_authorized": False,
        "adoption_ready": False,
        "manual_player_view_required": True,
        "godot_4_7_1_retarget_required": True,
        "foot_slide_measurement_required": True,
        "reason": "source_identity_and_internal_animation_catalog_only_engine_retarget_not_yet_approved",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("package", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()

    result = characterize(args.package)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "GATE8_RETARGET_SOURCE_PROBE_OK "
        f"sha256={result['package_sha256']} "
        f"bytes={result['package_size_bytes']} "
        f"entries={result['zip_file_entries']} "
        f"animation_entries={result['animation_asset_entry_count']} "
        f"internal_animations={result['internal_animation_count']} "
        f"internal_tokens_complete={str(result['complete_internal_token_surface']).lower()} "
        f"exact_single_trio={str(result['exact_single_idle_walk_run_trio']).lower()} "
        "adoption_ready=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
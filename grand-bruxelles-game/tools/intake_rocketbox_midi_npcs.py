#!/usr/bin/env python3
"""Reproducible review intake for realistic authored Midi NPC candidates.

This script intentionally creates review-only assets. It pins Microsoft Rocketbox to
one immutable commit, records source blob SHAs + local SHA-256 digests, downsamples
large TGA maps for Web-oriented review, and never marks candidates production-authorized.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import urllib.error
import urllib.parse
import urllib.request

ROCKETBOX_REPO = "microsoft/Microsoft-Rocketbox"
ROCKETBOX_COMMIT = "0943055db6ec570bcef9f2c8b41c9e5467c808f9"
RAW_ROOT = f"https://raw.githubusercontent.com/{ROCKETBOX_REPO}/{ROCKETBOX_COMMIT}"
API_ROOT = f"https://api.github.com/repos/{ROCKETBOX_REPO}/contents"
DEFAULT_PROFILES = [
    "Female_Adult_01",
    "Female_Adult_02",
    "Female_Adult_03",
    "Male_Adult_01",
    "Male_Adult_02",
    "Male_Adult_03",
    "Police_Female_01",
    "Police_Male_01",
]
PROFILE_ROOTS = {
    "Female_Adult_01": "Assets/Avatars/Adults/Female_Adult_01",
    "Female_Adult_02": "Assets/Avatars/Adults/Female_Adult_02",
    "Female_Adult_03": "Assets/Avatars/Adults/Female_Adult_03",
    "Male_Adult_01": "Assets/Avatars/Adults/Male_Adult_01",
    "Male_Adult_02": "Assets/Avatars/Adults/Male_Adult_02",
    "Male_Adult_03": "Assets/Avatars/Adults/Male_Adult_03",
    "Police_Female_01": "Assets/Avatars/Professions/Police_Female_01",
    "Police_Male_01": "Assets/Avatars/Professions/Police_Male_01",
}
TEXTURE_SUFFIXES = (
    "_body_color.tga",
    "_body_normal.tga",
    "_body_specular.tga",
    "_head_color.tga",
    "_head_normal.tga",
    "_head_specular.tga",
    "_opacity_color.tga",
)


def _request_json(url: str):
    req = urllib.request.Request(url, headers={"User-Agent": "grand-bruxelles-asset-intake/1"})
    with urllib.request.urlopen(req, timeout=90) as response:
        return json.load(response)


def _download(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": "grand-bruxelles-asset-intake/1"})
    with urllib.request.urlopen(req, timeout=180) as response, dest.open("wb") as out:
        shutil.copyfileobj(response, out)


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _contents(source_path: str):
    quoted = "/".join(urllib.parse.quote(part) for part in source_path.split("/"))
    return _request_json(f"{API_ROOT}/{quoted}?ref={ROCKETBOX_COMMIT}")


def _pick_export(profile: str, profile_root: str) -> dict:
    exports = _contents(f"{profile_root}/Export")
    target = f"{profile}.fbx"
    for entry in exports:
        if entry.get("name") == target:
            return entry
    raise RuntimeError(f"primary FBX not found for {profile}: expected {target}")


def _pick_textures(profile_root: str) -> list[dict]:
    entries = _contents(f"{profile_root}/Textures")
    picked = [
        entry for entry in entries
        if entry.get("type") == "file" and str(entry.get("name", "")).lower().endswith(TEXTURE_SUFFIXES)
    ]
    if not any(str(x.get("name", "")).lower().endswith("_body_color.tga") for x in picked):
        raise RuntimeError(f"body color texture missing: {profile_root}")
    if not any(str(x.get("name", "")).lower().endswith("_head_color.tga") for x in picked):
        raise RuntimeError(f"head color texture missing: {profile_root}")
    return picked


def _downsample_tga(path: Path, max_size: int) -> dict:
    from PIL import Image

    with Image.open(path) as image:
        original = [image.width, image.height]
        if max(image.width, image.height) > max_size:
            image.thumbnail((max_size, max_size), Image.Resampling.LANCZOS)
            image.save(path, format="TGA")
        final = [image.width, image.height]
    return {"original_dimensions": original, "review_dimensions": final}


def _role(profile: str) -> str:
    return "police" if profile.startswith("Police_") else "civilian"


def intake(output_root: Path, profiles: list[str], texture_max: int) -> dict:
    unknown = [p for p in profiles if p not in PROFILE_ROOTS]
    if unknown:
        raise RuntimeError(f"profile(s) not allowlisted: {', '.join(unknown)}")

    output_root.mkdir(parents=True, exist_ok=True)
    license_dest = output_root / "LICENSE.md"
    _download(f"{RAW_ROOT}/LICENSE.md", license_dest)

    manifest = {
        "schema": "grand-bruxelles-authored-npc-review-manifest-v1",
        "source_repository": ROCKETBOX_REPO,
        "source_commit": ROCKETBOX_COMMIT,
        "license": "MIT",
        "production_authorized": False,
        "review_only": True,
        "texture_max_dimension": texture_max,
        "profiles": [],
    }

    for profile in profiles:
        source_root = PROFILE_ROOTS[profile]
        local_root = output_root / profile
        export = _pick_export(profile, source_root)
        export_dest = local_root / "Export" / f"{profile}.fbx"
        _download(export["download_url"], export_dest)

        record = {
            "id": profile,
            "role": _role(profile),
            "source_root": source_root,
            "source_fbx": export["path"],
            "source_blob_sha": export["sha"],
            "local_fbx": export_dest.relative_to(output_root).as_posix(),
            "fbx_sha256": _sha256(export_dest),
            "production_authorized": False,
            "textures": [],
        }

        for texture in _pick_textures(source_root):
            tex_dest = local_root / "Textures" / texture["name"]
            _download(texture["download_url"], tex_dest)
            dims = _downsample_tga(tex_dest, texture_max)
            record["textures"].append({
                "name": texture["name"],
                "source_path": texture["path"],
                "source_blob_sha": texture["sha"],
                "source_size": texture.get("size", 0),
                "local_sha256": _sha256(tex_dest),
                **dims,
            })

        preview_path = f"{source_root}/{profile}.png"
        try:
            preview_entry = next(x for x in _contents(source_root) if x.get("path") == preview_path)
            preview_dest = local_root / f"{profile}.png"
            _download(preview_entry["download_url"], preview_dest)
            record["preview"] = {
                "source_path": preview_entry["path"],
                "source_blob_sha": preview_entry["sha"],
                "local_sha256": _sha256(preview_dest),
            }
        except (StopIteration, urllib.error.HTTPError):
            record["preview"] = None

        manifest["profiles"].append(record)
        print(f"INTAKE_OK {profile} textures={len(record['textures'])} fbx_sha256={record['fbx_sha256']}")

    manifest_path = output_root / "asset_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (output_root / "licenses.json").write_text(json.dumps({
        "source_repository": ROCKETBOX_REPO,
        "source_commit": ROCKETBOX_COMMIT,
        "license": "MIT",
        "license_file": "LICENSE.md",
        "production_authorized": False,
    }, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-root", default="assets/characters/_review/rocketbox_midi_v1")
    parser.add_argument("--profiles", default=",".join(DEFAULT_PROFILES))
    parser.add_argument("--texture-max", type=int, default=512)
    args = parser.parse_args()
    profiles = [p.strip() for p in args.profiles.split(",") if p.strip()]
    if len(set(profiles)) != len(profiles):
        raise RuntimeError("duplicate profile in intake list")
    manifest = intake(Path(args.output_root), profiles, args.texture_max)
    civilians = sum(1 for p in manifest["profiles"] if p["role"] == "civilian")
    police = sum(1 for p in manifest["profiles"] if p["role"] == "police")
    print(f"ROCKETBOX_MIDI_INTAKE_OK profiles={len(profiles)} civilians={civilians} police={police} production_authorized=false")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"ROCKETBOX_MIDI_INTAKE_FAIL: {exc}", file=sys.stderr)
        raise

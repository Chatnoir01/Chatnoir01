#!/usr/bin/env python3
"""Bound CIV-1 review textures and stage pinned CC0 footwear witnesses.

This runs only after the legal/animation-free preparation step. It never edits
Vitruvian GLB geometry, skins, skeletons or shaders. MakeHuman footwear is
staged as separate review-only geometry with pinned source/license evidence.
The primary visual witness is shoes03 (boots); shoes04 is retained only as a
compatibility resource for the historical parent capture gate.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import urllib.request
from typing import Any

from PIL import Image

MAX_REVIEW_TEXTURE_EDGE = 1024
IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg"}

FOOTWEAR_REPOSITORY = "furqonat/makehuman-assets"
FOOTWEAR_COMMIT = "8cf9645b975a98eea056b140df11a1d278da0d10"
FOOTWEAR_OBJ_PATH = "base/clothes/shoes03/shoes03.obj"
FOOTWEAR_LICENSE_PATH = "LICENSE.txt"
FOOTWEAR_OBJ_GIT_BLOB = "2cd09f0af9c5bd13604d57d8af19e9205933ee85"
FOOTWEAR_LICENSE_GIT_BLOB = "0e259d42c996742e9e3cba14c677129b2c1b6311"
LEGACY_FOOTWEAR_OBJ_PATH = "base/clothes/shoes04/shoes04.obj"
LEGACY_FOOTWEAR_OBJ_GIT_BLOB = "5137b1da52be37e8b5c98f1d3d47c31165ed4023"
RAW_ROOT = (
    "https://raw.githubusercontent.com/"
    + FOOTWEAR_REPOSITORY
    + "/"
    + FOOTWEAR_COMMIT
    + "/"
)


def sha256(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def git_blob_sha1(data: bytes) -> str:
    header = f"blob {len(data)}\0".encode("ascii")
    return hashlib.sha1(header + data).hexdigest()


def fetch_bytes(relative_path: str) -> bytes:
    request = urllib.request.Request(
        RAW_ROOT + relative_path,
        headers={"User-Agent": "grand-bruxelles-civ1-review/1"},
    )
    with urllib.request.urlopen(request, timeout=45) as response:
        data = response.read()
    if not data:
        raise RuntimeError(f"empty pinned source: {relative_path}")
    return data


def _verify_cc0_obj(data: bytes, expected_blob: str, label: str) -> None:
    if git_blob_sha1(data) != expected_blob:
        raise RuntimeError(f"pinned {label} OBJ blob hash mismatch")
    header = data[:4096].decode("utf-8", errors="replace")
    if "explicitly released as CC0" not in header:
        raise RuntimeError(f"{label} OBJ lacks explicit CC0 header evidence")


def stage_cc0_footwear(root: pathlib.Path) -> dict[str, Any]:
    obj = fetch_bytes(FOOTWEAR_OBJ_PATH)
    legacy_obj = fetch_bytes(LEGACY_FOOTWEAR_OBJ_PATH)
    license_text = fetch_bytes(FOOTWEAR_LICENSE_PATH)

    _verify_cc0_obj(obj, FOOTWEAR_OBJ_GIT_BLOB, "shoes03")
    _verify_cc0_obj(legacy_obj, LEGACY_FOOTWEAR_OBJ_GIT_BLOB, "shoes04")
    if git_blob_sha1(license_text) != FOOTWEAR_LICENSE_GIT_BLOB:
        raise RuntimeError("pinned MakeHuman CC0 license blob hash mismatch")

    decoded_license = license_text.decode("utf-8", errors="replace")
    if "CC0 1.0 Universal" not in decoded_license:
        raise RuntimeError("MakeHuman asset license is not CC0 1.0 Universal")

    obj_out = root / "shoes03_cc0.obj"
    legacy_out = root / "shoes04_cc0.obj"
    license_out = root / "MAKEHUMAN_SHOES03_CC0_LICENSE.txt"
    obj_out.write_bytes(obj)
    legacy_out.write_bytes(legacy_obj)
    license_out.write_bytes(license_text)

    return {
        "repository": FOOTWEAR_REPOSITORY,
        "commit": FOOTWEAR_COMMIT,
        "path": FOOTWEAR_OBJ_PATH,
        "license": "CC0-1.0",
        "obj_git_blob_sha1": git_blob_sha1(obj),
        "license_git_blob_sha1": git_blob_sha1(license_text),
        "obj_sha256": hashlib.sha256(obj).hexdigest(),
        "obj_bytes": len(obj),
        "staged_name": obj_out.name,
        "asset_role": "primary_visual_boot",
        "legacy_gate_resource": {
            "path": LEGACY_FOOTWEAR_OBJ_PATH,
            "obj_git_blob_sha1": git_blob_sha1(legacy_obj),
            "staged_name": legacy_out.name,
            "visual_owner": False,
        },
        "character_geometry_modified": False,
        "review_only": True,
    }


def package_bytes(root: pathlib.Path) -> int:
    return sum(p.stat().st_size for p in root.rglob("*") if p.is_file())


def optimize_image(path: pathlib.Path) -> dict[str, Any]:
    before_bytes = path.stat().st_size
    before_sha = sha256(path)
    with Image.open(path) as image:
        before_size = [int(image.width), int(image.height)]
        if max(image.size) > MAX_REVIEW_TEXTURE_EDGE:
            image.thumbnail(
                (MAX_REVIEW_TEXTURE_EDGE, MAX_REVIEW_TEXTURE_EDGE),
                Image.Resampling.LANCZOS,
            )
            save_kwargs: dict[str, Any] = {"optimize": True}
            if path.suffix.lower() in {".jpg", ".jpeg"}:
                if image.mode not in {"RGB", "L"}:
                    image = image.convert("RGB")
                save_kwargs = {"quality": 92, "optimize": True}
            image.save(path, **save_kwargs)

    with Image.open(path) as verified:
        after_size = [int(verified.width), int(verified.height)]
        if max(verified.size) > MAX_REVIEW_TEXTURE_EDGE:
            raise RuntimeError(
                f"texture remains above {MAX_REVIEW_TEXTURE_EDGE}px: {path}: {verified.size}"
            )

    return {
        "path": str(path.name),
        "before_size": before_size,
        "after_size": after_size,
        "before_bytes": before_bytes,
        "after_bytes": path.stat().st_size,
        "before_sha256": before_sha,
        "after_sha256": sha256(path),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package", required=True, type=pathlib.Path)
    parser.add_argument("--report", required=True, type=pathlib.Path)
    args = parser.parse_args()

    if not args.package.is_dir():
        raise RuntimeError(f"prepared package missing: {args.package}")

    footwear = stage_cc0_footwear(args.package)
    before_total = package_bytes(args.package)
    images = sorted(
        p for p in args.package.rglob("*")
        if p.is_file() and p.suffix.lower() in IMAGE_SUFFIXES
    )
    if not images:
        raise RuntimeError("prepared package has no review textures")

    records = [optimize_image(path) for path in images]
    after_total = package_bytes(args.package)
    texture_before = sum(int(r["before_bytes"]) for r in records)
    texture_after = sum(int(r["after_bytes"]) for r in records)

    if after_total > before_total:
        raise RuntimeError(
            f"review optimization increased package bytes: {before_total} -> {after_total}"
        )

    report = {
        "schema": "grand-bruxelles-civ1-review-optimization-v3",
        "production_authorized": False,
        "geometry_modified": False,
        "skin_skeleton_modified": False,
        "shader_modified": False,
        "external_footwear_staged": True,
        "footwear": footwear,
        "max_review_texture_edge_px": MAX_REVIEW_TEXTURE_EDGE,
        "image_count": len(records),
        "package_bytes_before": before_total,
        "package_bytes_after": after_total,
        "package_bytes_saved": before_total - after_total,
        "texture_bytes_before": texture_before,
        "texture_bytes_after": texture_after,
        "texture_bytes_saved": texture_before - texture_after,
        "textures": records,
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print(
        "GB_CIV1_REVIEW_OPTIMIZED "
        + json.dumps(
            {
                "images": len(records),
                "max_edge_px": MAX_REVIEW_TEXTURE_EDGE,
                "package_before": before_total,
                "package_after": after_total,
                "bytes_saved": before_total - after_total,
                "footwear": footwear["staged_name"],
                "footwear_license": footwear["license"],
                "production_authorized": False,
            },
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()

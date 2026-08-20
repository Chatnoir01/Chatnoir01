#!/usr/bin/env python3
"""Deterministically bound the prepared CIV-1 review textures.

This runs only after the legal/animation-free preparation step. It never touches
GLB geometry, skins, skeletons, shaders or provenance inputs. The goal is to
make the owner-review artifact materially lighter while keeping enough texture
resolution for the fixed 2 m / 5 m / 8 m witness.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
from typing import Any

from PIL import Image

MAX_REVIEW_TEXTURE_EDGE = 1024
IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg"}


def sha256(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


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
        "schema": "grand-bruxelles-civ1-review-optimization-v1",
        "production_authorized": False,
        "geometry_modified": False,
        "skin_skeleton_modified": False,
        "shader_modified": False,
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
                "production_authorized": False,
            },
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()

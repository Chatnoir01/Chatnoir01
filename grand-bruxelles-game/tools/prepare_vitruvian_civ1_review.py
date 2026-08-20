#!/usr/bin/env python3
"""Prepare a review-only Vitruvian CIV-1 package.

The input directory is populated by CI from a pinned upstream commit. This tool
never downloads anything. It removes GLB animation tables, rejects residual
Mixamo/Adobe references, copies required PBR/hair textures, downsizes them to a
bounded review resolution, and writes a deterministic audit report. The output
is not production-authorized.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import shutil
import struct
from typing import Any

from PIL import Image

GLB_MAGIC = b"glTF"
JSON_CHUNK = 0x4E4F534A
MAX_TEXTURE_EDGE = 2048
REQUIRED_GLBS = (
    "vitruvian_body.glb",
    "vitruvian_head.glb",
    "hairtool_cards.glb",
    "vitruvian_hair.glb",
)
REVIEW_TEXTURES = (
    "vit_body_bc.png",
    "vit_body_n.png",
    "vit_body_rough.png",
    "vit_fabric_n.png",
    "vit_face_bc.png",
    "vit_face_n.png",
    "vit_face_rough.png",
    "vit_mouth.png",
    "vit_sclera.png",
    "vit_iris.png",
    "vit_lash_atlas.png",
    "vit_hair_diffuse.png",
    "vit_hair_normal.png",
    "vit_hair_ao.png",
    "vit_hair_opacity.png",
    "vit_hair_atlas.png",
)


def sha256(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def read_glb(path: pathlib.Path) -> tuple[dict[str, Any], list[tuple[int, bytes]]]:
    raw = path.read_bytes()
    if len(raw) < 20 or raw[:4] != GLB_MAGIC:
        raise RuntimeError(f"invalid GLB header: {path}")
    version, declared_len = struct.unpack_from("<II", raw, 4)
    if version != 2 or declared_len != len(raw):
        raise RuntimeError(f"invalid GLB version/length: {path}")
    chunks: list[tuple[int, bytes]] = []
    offset = 12
    doc: dict[str, Any] | None = None
    while offset + 8 <= len(raw):
        length, chunk_type = struct.unpack_from("<II", raw, offset)
        offset += 8
        payload = raw[offset : offset + length]
        offset += length
        chunks.append((chunk_type, payload))
        if chunk_type == JSON_CHUNK:
            doc = json.loads(payload.rstrip(b"\x00 \t\r\n").decode("utf-8"))
    if doc is None:
        raise RuntimeError(f"GLB JSON chunk missing: {path}")
    return doc, chunks


def write_glb(path: pathlib.Path, doc: dict[str, Any], chunks: list[tuple[int, bytes]]) -> None:
    encoded = json.dumps(doc, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    encoded += b" " * ((4 - len(encoded) % 4) % 4)
    out_chunks: list[tuple[int, bytes]] = []
    replaced = False
    for chunk_type, payload in chunks:
        if chunk_type == JSON_CHUNK and not replaced:
            out_chunks.append((chunk_type, encoded))
            replaced = True
        else:
            out_chunks.append((chunk_type, payload))
    total = 12 + sum(8 + len(payload) for _, payload in out_chunks)
    with path.open("wb") as handle:
        handle.write(GLB_MAGIC)
        handle.write(struct.pack("<II", 2, total))
        for chunk_type, payload in out_chunks:
            handle.write(struct.pack("<II", len(payload), chunk_type))
            handle.write(payload)


def safe_external_uris(doc: dict[str, Any]) -> list[str]:
    uris: list[str] = []
    for image in doc.get("images") or []:
        uri = image.get("uri")
        if not uri:
            continue
        p = pathlib.PurePosixPath(str(uri))
        if p.is_absolute() or ".." in p.parts or str(uri).startswith("data:"):
            raise RuntimeError(f"unsupported/unsafe image URI: {uri}")
        uris.append(str(uri))
    return sorted(set(uris))


def resize_image(source: pathlib.Path, destination: pathlib.Path) -> dict[str, Any]:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with Image.open(source) as image:
        original_size = [int(image.width), int(image.height)]
        if max(image.size) > MAX_TEXTURE_EDGE:
            image.thumbnail((MAX_TEXTURE_EDGE, MAX_TEXTURE_EDGE), Image.Resampling.LANCZOS)
        final_size = [int(image.width), int(image.height)]
        save_kwargs: dict[str, Any] = {"optimize": True}
        suffix = destination.suffix.lower()
        if suffix in (".jpg", ".jpeg"):
            if image.mode not in ("RGB", "L"):
                image = image.convert("RGB")
            save_kwargs = {"quality": 92, "optimize": True}
        image.save(destination, **save_kwargs)
    return {
        "source": str(source.name),
        "output": str(destination.name),
        "original_size": original_size,
        "final_size": final_size,
        "sha256": sha256(destination),
        "bytes": destination.stat().st_size,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=pathlib.Path)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("--report", required=True, type=pathlib.Path)
    args = parser.parse_args()

    args.output.mkdir(parents=True, exist_ok=True)
    glb_report: dict[str, Any] = {}
    referenced_images: set[str] = set(REVIEW_TEXTURES)

    for name in REQUIRED_GLBS:
        src = args.source / name
        if not src.is_file():
            raise RuntimeError(f"required source GLB missing: {src}")
        doc, chunks = read_glb(src)
        source_animation_count = len(doc.get("animations") or [])
        doc.pop("animations", None)
        serialized = json.dumps(doc, separators=(",", ":")).lower()
        if "mixamo" in serialized or "mixamorig" in serialized or "adobe" in serialized:
            raise RuntimeError(f"forbidden animation-source token remains after strip: {name}")
        output_glb = args.output / name
        write_glb(output_glb, doc, chunks)
        clean_doc, _ = read_glb(output_glb)
        if clean_doc.get("animations"):
            raise RuntimeError(f"animation table survived strip: {name}")
        image_uris = safe_external_uris(clean_doc)
        referenced_images.update(image_uris)
        glb_report[name] = {
            "source_sha256": sha256(src),
            "output_sha256": sha256(output_glb),
            "source_animations": source_animation_count,
            "output_animations": 0,
            "nodes": len(clean_doc.get("nodes") or []),
            "meshes": len(clean_doc.get("meshes") or []),
            "skins": len(clean_doc.get("skins") or []),
            "materials": len(clean_doc.get("materials") or []),
            "external_images": image_uris,
            "bytes": output_glb.stat().st_size,
        }

    texture_report: dict[str, Any] = {}
    for uri in sorted(referenced_images):
        src = args.source / uri
        if not src.is_file():
            raise RuntimeError(f"required/referenced source image missing: {uri}")
        out = args.output / uri
        texture_report[uri] = resize_image(src, out)

    for extra in ("hairtool_card.gdshader", "hair_card.gdshader", "cornea.gdshader"):
        src = args.source / extra
        if not src.is_file():
            raise RuntimeError(f"required review shader missing: {extra}")
        shutil.copy2(src, args.output / extra)

    report = {
        "schema": "grand-bruxelles-civ1-vitruvian-prepared-v1",
        "production_authorized": False,
        "animations_allowed": False,
        "mixamo_payload_allowed": False,
        "max_texture_edge_px": MAX_TEXTURE_EDGE,
        "glbs": glb_report,
        "textures": texture_report,
        "source_file_count": len(REQUIRED_GLBS) + len(referenced_images),
        "output_total_bytes": sum(p.stat().st_size for p in args.output.rglob("*") if p.is_file()),
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("GB_CIV1_VITRUVIAN_PREPARED", json.dumps({
        "glbs": len(glb_report),
        "textures": len(texture_report),
        "bytes": report["output_total_bytes"],
        "production_authorized": False,
    }, sort_keys=True))


if __name__ == "__main__":
    main()

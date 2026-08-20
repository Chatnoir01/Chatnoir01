#!/usr/bin/env python3
"""Prepare a review-only Vitruvian CIV-1 package.

The input directory is populated by CI from a pinned upstream commit. This tool
never downloads anything. It removes GLB animation tables *and* neutralizes the
binary bufferViews owned exclusively by those animations, while refusing any
ambiguous shared bufferView. It also normalizes only the confirmed `mixamorig:`
prefix on glTF node labels and rejects every other residual provider reference.
Required PBR/hair textures are copied and bounded to review resolution. The
output is never production-authorized.
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
BIN_CHUNK = 0x004E4942
MAX_TEXTURE_EDGE = 2048
MIXAMO_RIG_PREFIX = "mixamorig:"
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
    if offset != len(raw):
        raise RuntimeError(f"invalid GLB chunk accounting: {path}")
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
    if not replaced:
        raise RuntimeError("cannot write GLB without JSON chunk")
    total = 12 + sum(8 + len(payload) for _, payload in out_chunks)
    with path.open("wb") as handle:
        handle.write(GLB_MAGIC)
        handle.write(struct.pack("<II", 2, total))
        for chunk_type, payload in out_chunks:
            handle.write(struct.pack("<II", len(payload), chunk_type))
            handle.write(payload)


def provider_string_matches(value: Any, path: str = "$") -> list[dict[str, str]]:
    """Audit residual Mixamo/Adobe strings without equating metadata with payload."""
    matches: list[dict[str, str]] = []
    if isinstance(value, dict):
        for key, child in value.items():
            matches.extend(provider_string_matches(child, "%s.%s" % (path, key)))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            matches.extend(provider_string_matches(child, "%s[%d]" % (path, index)))
    elif isinstance(value, str):
        lowered = value.lower()
        if "mixamo" in lowered or "mixamorig" in lowered or "adobe" in lowered:
            matches.append({"path": path, "value": value[:200]})
    return matches


def normalize_confirmed_rig_node_labels(doc: dict[str, Any]) -> list[dict[str, str]]:
    """Strip only the confirmed `mixamorig:` prefix from `nodes[].name`.

    The run-2 RED proof showed the residual provider strings were node names such
    as `mixamorig:Head`. glTF skins and graph edges reference node indices, so
    this changes labels only: no accessor, joint list, transform, URI or buffer.
    """
    changes: list[dict[str, str]] = []
    for index, node in enumerate(doc.get("nodes") or []):
        if not isinstance(node, dict):
            continue
        name = node.get("name")
        if not isinstance(name, str) or not name.lower().startswith(MIXAMO_RIG_PREFIX):
            continue
        clean = name[len(MIXAMO_RIG_PREFIX):]
        if not clean:
            raise RuntimeError("empty node name after confirmed rig-prefix normalization")
        node["name"] = clean
        changes.append({"path": "$.nodes[%d].name" % index, "before": name, "after": clean})
    return changes


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


def _animation_accessor_indices(doc: dict[str, Any]) -> set[int]:
    indices: set[int] = set()
    for animation in doc.get("animations") or []:
        for sampler in animation.get("samplers") or []:
            for key in ("input", "output"):
                value = sampler.get(key)
                if not isinstance(value, int) or value < 0:
                    raise RuntimeError(f"invalid animation sampler accessor: {value!r}")
                indices.add(value)
    return indices


def _remaining_accessor_indices(value: Any, parent_key: str = "") -> set[int]:
    """Collect accessor references that remain after animations are removed."""
    found: set[int] = set()
    if isinstance(value, dict):
        for key, child in value.items():
            if parent_key in {"attributes", "targets"} and isinstance(child, int):
                found.add(child)
                continue
            if key == "inverseBindMatrices" and isinstance(child, int):
                found.add(child)
                continue
            if key == "indices" and isinstance(child, int) and parent_key != "sparse":
                found.add(child)
                continue
            found.update(_remaining_accessor_indices(child, key))
    elif isinstance(value, list):
        for child in value:
            found.update(_remaining_accessor_indices(child, parent_key))
    return found


def _accessor_buffer_views(doc: dict[str, Any], accessor_indices: set[int]) -> set[int]:
    accessors = doc.get("accessors") or []
    views: set[int] = set()
    for accessor_index in accessor_indices:
        if accessor_index >= len(accessors):
            raise RuntimeError(f"accessor index out of range: {accessor_index}")
        accessor = accessors[accessor_index]
        view = accessor.get("bufferView")
        if isinstance(view, int):
            views.add(view)
        sparse = accessor.get("sparse") or {}
        for part in (sparse.get("indices") or {}, sparse.get("values") or {}):
            sparse_view = part.get("bufferView")
            if isinstance(sparse_view, int):
                views.add(sparse_view)
    return views


def _image_buffer_views(doc: dict[str, Any]) -> set[int]:
    views: set[int] = set()
    for image in doc.get("images") or []:
        view = image.get("bufferView")
        if isinstance(view, int):
            views.add(view)
    return views


def strip_animation_payload(
    doc: dict[str, Any], chunks: list[tuple[int, bytes]]
) -> tuple[dict[str, Any], list[tuple[int, bytes]], dict[str, Any]]:
    """Remove animation tables and zero animation-only binary bufferViews.

    Fail closed if animation data shares an accessor/bufferView with retained
    mesh, skin or image data. This avoids both corrupting geometry and falsely
    claiming that animation payload has been removed.
    """
    animation_count = len(doc.get("animations") or [])
    animation_accessors = _animation_accessor_indices(doc)
    source_animation_provider_strings = provider_string_matches(doc.get("animations") or [], "$.animations")

    clean_doc = json.loads(json.dumps(doc))
    clean_doc.pop("animations", None)
    normalized_rig_node_labels = normalize_confirmed_rig_node_labels(clean_doc)
    residual_provider_strings = provider_string_matches(clean_doc)
    if residual_provider_strings:
        raise RuntimeError(
            "provider reference remains outside confirmed rig-node labels: "
            + json.dumps(residual_provider_strings[:20], sort_keys=True)
        )

    remaining_accessors = _remaining_accessor_indices(clean_doc)
    shared_accessors = animation_accessors & remaining_accessors
    if shared_accessors:
        raise RuntimeError(
            "animation accessor is also referenced by retained content: "
            + ",".join(str(i) for i in sorted(shared_accessors))
        )
    animation_only_accessors = animation_accessors - remaining_accessors
    animation_views = _accessor_buffer_views(clean_doc, animation_only_accessors)
    protected_views = _accessor_buffer_views(clean_doc, remaining_accessors) | _image_buffer_views(clean_doc)
    shared_views = animation_views & protected_views
    if shared_views:
        raise RuntimeError(
            "animation bufferView is shared with retained geometry/skin/image data: "
            + ",".join(str(i) for i in sorted(shared_views))
        )

    buffer_views = clean_doc.get("bufferViews") or []
    bin_indices = [i for i, (chunk_type, _) in enumerate(chunks) if chunk_type == BIN_CHUNK]
    if animation_views and len(bin_indices) != 1:
        raise RuntimeError(f"expected exactly one BIN chunk for animation strip, found {len(bin_indices)}")

    out_chunks = list(chunks)
    zeroed_bytes = 0
    if animation_views:
        bin_index = bin_indices[0]
        bin_payload = bytearray(out_chunks[bin_index][1])
        for view_index in sorted(animation_views):
            if view_index >= len(buffer_views):
                raise RuntimeError(f"animation bufferView index out of range: {view_index}")
            view = buffer_views[view_index]
            buffer_index = view.get("buffer", 0)
            if buffer_index != 0:
                raise RuntimeError(f"unsupported animation buffer index {buffer_index} in view {view_index}")
            start = int(view.get("byteOffset", 0))
            length = int(view.get("byteLength", 0))
            end = start + length
            if start < 0 or length < 0 or end > len(bin_payload):
                raise RuntimeError(f"invalid animation bufferView range {view_index}: {start}:{end}")
            bin_payload[start:end] = b"\x00" * length
            zeroed_bytes += length
        out_chunks[bin_index] = (BIN_CHUNK, bytes(bin_payload))

    audit = {
        "source_animations": animation_count,
        "source_animation_accessors": len(animation_accessors),
        "animation_only_accessors": sorted(animation_only_accessors),
        "animation_buffer_views_zeroed": sorted(animation_views),
        "animation_binary_bytes_zeroed": zeroed_bytes,
        "source_animation_provider_strings": source_animation_provider_strings,
        "normalized_rig_node_labels": normalized_rig_node_labels,
        "residual_provider_strings": provider_string_matches(clean_doc),
    }
    return clean_doc, out_chunks, audit


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
    total_source_animations = 0
    total_animation_binary_bytes_zeroed = 0

    for name in REQUIRED_GLBS:
        src = args.source / name
        if not src.is_file():
            raise RuntimeError(f"required source GLB missing: {src}")
        doc, chunks = read_glb(src)
        clean_doc, clean_chunks, animation_audit = strip_animation_payload(doc, chunks)
        output_glb = args.output / name
        write_glb(output_glb, clean_doc, clean_chunks)
        verified_doc, verified_chunks = read_glb(output_glb)
        if verified_doc.get("animations"):
            raise RuntimeError(f"animation table survived strip: {name}")
        if len(verified_chunks) != len(clean_chunks):
            raise RuntimeError(f"GLB chunk count changed unexpectedly: {name}")
        verified_provider_strings = provider_string_matches(verified_doc)
        if verified_provider_strings:
            raise RuntimeError(
                "provider reference survived serialized output: %s: %s"
                % (name, json.dumps(verified_provider_strings[:20], sort_keys=True))
            )
        image_uris = safe_external_uris(verified_doc)
        referenced_images.update(image_uris)
        total_source_animations += int(animation_audit["source_animations"])
        total_animation_binary_bytes_zeroed += int(animation_audit["animation_binary_bytes_zeroed"])
        glb_report[name] = {
            "source_sha256": sha256(src),
            "output_sha256": sha256(output_glb),
            "source_animations": int(animation_audit["source_animations"]),
            "output_animations": 0,
            "source_animation_accessors": int(animation_audit["source_animation_accessors"]),
            "animation_only_accessors": animation_audit["animation_only_accessors"],
            "animation_buffer_views_zeroed": animation_audit["animation_buffer_views_zeroed"],
            "animation_binary_bytes_zeroed": int(animation_audit["animation_binary_bytes_zeroed"]),
            "source_animation_provider_strings": animation_audit["source_animation_provider_strings"],
            "normalized_rig_node_labels": animation_audit["normalized_rig_node_labels"],
            "residual_provider_strings": animation_audit["residual_provider_strings"],
            "nodes": len(verified_doc.get("nodes") or []),
            "meshes": len(verified_doc.get("meshes") or []),
            "skins": len(verified_doc.get("skins") or []),
            "materials": len(verified_doc.get("materials") or []),
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
        "schema": "grand-bruxelles-civ1-vitruvian-prepared-v4",
        "production_authorized": False,
        "animations_allowed": False,
        "mixamo_payload_allowed": False,
        "animation_payload_policy": "animation tables removed; exclusive animation bufferViews zeroed; shared views rejected",
        "provider_label_policy": "only confirmed nodes[].name mixamorig prefix is normalized; any other residual provider reference fails closed",
        "source_animations": total_source_animations,
        "output_animations": 0,
        "animation_binary_bytes_zeroed": total_animation_binary_bytes_zeroed,
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
        "source_animations": total_source_animations,
        "animation_binary_bytes_zeroed": total_animation_binary_bytes_zeroed,
        "production_authorized": False,
    }, sort_keys=True))


if __name__ == "__main__":
    main()

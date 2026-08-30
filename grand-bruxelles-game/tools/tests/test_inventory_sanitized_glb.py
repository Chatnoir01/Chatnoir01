#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


stripper = load("strip_glb_animations", TOOLS / "strip_glb_animations.py")
inventory_mod = load("inventory_sanitized_glb", TOOLS / "inventory_sanitized_glb.py")


def make_glb(document: dict, binary: bytes = b"ABCD") -> bytes:
    json_bytes = json.dumps(document, separators=(",", ":")).encode("utf-8")
    json_bytes += b" " * ((4 - len(json_bytes) % 4) % 4)
    binary += b"\x00" * ((4 - len(binary) % 4) % 4)
    chunks = struct.pack("<II", len(json_bytes), stripper.JSON_CHUNK) + json_bytes
    chunks += struct.pack("<II", len(binary), stripper.BIN_CHUNK) + binary
    return struct.pack("<4sII", stripper.GLB_MAGIC, 2, 12 + len(chunks)) + chunks


def valid_document() -> dict:
    return {
        "asset": {"version": "2.0", "generator": "test"},
        "nodes": [{"mesh": 0, "skin": 0}, {"name": "joint"}],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "indices": 1, "material": 0}]}],
        "skins": [{"joints": [1], "skeleton": 1, "inverseBindMatrices": 2}],
        "materials": [{}],
        "accessors": [{"bufferView": 0}, {"bufferView": 0}, {"bufferView": 0}],
        "bufferViews": [{"buffer": 0, "byteLength": 4}],
        "buffers": [{"byteLength": 4}],
    }


def assert_rejected(document: dict, fragment: str, binary: bytes = b"ABCD") -> None:
    try:
        inventory_mod.build_inventory(make_glb(document, binary))
    except stripper.GlbError as exc:
        assert fragment in str(exc)
    else:
        raise AssertionError(f"expected fail-closed rejection containing {fragment!r}")


def test_inventory_accepts_animation_free_structure_hashes_chunks_and_refs():
    result = inventory_mod.build_inventory(make_glb(valid_document()))
    assert result["format"] == "grand-bruxelles-sanitized-glb-inventory-v2"
    assert result["animations_present"] is False
    assert result["reference_integrity"] == "validated"
    assert result["counts"]["meshes"] == 1
    assert result["counts"]["skins"] == 1
    assert result["counts"]["materials"] == 1
    assert result["counts"]["accessors"] == 3
    assert len(result["sha256"]) == 64
    assert result["extra_chunks"][0]["type"] == stripper.BIN_CHUNK
    assert len(result["extra_chunks"][0]["sha256"]) == 64


def test_inventory_rejects_residual_animations():
    doc = valid_document(); doc["animations"] = []
    assert_rejected(doc, "still contains animations")


def test_inventory_rejects_malformed_structural_arrays():
    doc = valid_document(); doc["meshes"] = {}
    assert_rejected(doc, "meshes must be an array")


def test_inventory_rejects_wrong_asset_version():
    doc = valid_document(); doc["asset"] = {"version": "1.0"}
    assert_rejected(doc, "asset.version")


def test_inventory_rejects_dangling_node_mesh_reference():
    doc = valid_document(); doc["nodes"][0]["mesh"] = 7
    assert_rejected(doc, "nodes[0].mesh index out of range")


def test_inventory_rejects_dangling_skin_joint_reference():
    doc = valid_document(); doc["skins"][0]["joints"] = [9]
    assert_rejected(doc, "skins[0].joints index out of range")


def test_inventory_rejects_dangling_primitive_accessor_reference():
    doc = valid_document(); doc["meshes"][0]["primitives"][0]["attributes"]["POSITION"] = 99
    assert_rejected(doc, "attributes.POSITION index out of range")


def test_inventory_rejects_dangling_material_reference():
    doc = valid_document(); doc["meshes"][0]["primitives"][0]["material"] = 3
    assert_rejected(doc, "material index out of range")


def test_inventory_rejects_dangling_buffer_view_reference():
    doc = valid_document(); doc["accessors"][0]["bufferView"] = 4
    assert_rejected(doc, "accessors[0].bufferView index out of range")


def test_inventory_rejects_embedded_buffer_larger_than_bin_payload():
    doc = valid_document(); doc["buffers"][0]["byteLength"] = 16
    assert_rejected(doc, "exceeds BIN payload", binary=b"ABCD")


def test_inventory_rejects_empty_skin_joint_list():
    doc = valid_document(); doc["skins"][0]["joints"] = []
    assert_rejected(doc, "joints must be a non-empty array")

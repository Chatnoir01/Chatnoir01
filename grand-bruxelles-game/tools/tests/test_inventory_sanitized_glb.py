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


def test_inventory_accepts_animation_free_structure_and_hashes_chunks():
    source = make_glb({
        "asset": {"version": "2.0", "generator": "test"},
        "nodes": [{"mesh": 0}],
        "meshes": [{"primitives": []}],
        "skins": [{"joints": [0]}],
        "materials": [{}],
        "accessors": [{}, {}],
        "bufferViews": [{}],
        "buffers": [{"byteLength": 4}],
    })
    result = inventory_mod.build_inventory(source)
    assert result["format"] == "grand-bruxelles-sanitized-glb-inventory-v1"
    assert result["animations_present"] is False
    assert result["counts"]["meshes"] == 1
    assert result["counts"]["skins"] == 1
    assert result["counts"]["materials"] == 1
    assert result["counts"]["accessors"] == 2
    assert len(result["sha256"]) == 64
    assert result["extra_chunks"][0]["type"] == stripper.BIN_CHUNK
    assert len(result["extra_chunks"][0]["sha256"]) == 64


def test_inventory_rejects_residual_animations():
    source = make_glb({"asset": {"version": "2.0"}, "animations": []})
    try:
        inventory_mod.build_inventory(source)
    except stripper.GlbError as exc:
        assert "still contains animations" in str(exc)
    else:
        raise AssertionError("residual animations key must fail closed")


def test_inventory_rejects_malformed_structural_arrays():
    source = make_glb({"asset": {"version": "2.0"}, "meshes": {}})
    try:
        inventory_mod.build_inventory(source)
    except stripper.GlbError as exc:
        assert "meshes must be an array" in str(exc)
    else:
        raise AssertionError("malformed meshes must fail closed")


def test_inventory_rejects_wrong_asset_version():
    source = make_glb({"asset": {"version": "1.0"}})
    try:
        inventory_mod.build_inventory(source)
    except stripper.GlbError as exc:
        assert "asset.version" in str(exc)
    else:
        raise AssertionError("wrong glTF version must fail closed")

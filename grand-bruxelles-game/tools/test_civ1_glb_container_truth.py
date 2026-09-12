#!/usr/bin/env python3
from __future__ import annotations

import json
import struct

from civ1_glb_container_truth import BIN_CHUNK, JSON_CHUNK, inspect_glb_bytes

EXTENSION_CHUNK = 0x4E545845


def chunk(chunk_type: int, payload: bytes) -> bytes:
    payload += b"\x00" * ((4 - len(payload) % 4) % 4)
    return struct.pack("<II", len(payload), chunk_type) + payload


def glb(*chunks: bytes) -> bytes:
    body = b"".join(chunks)
    return b"glTF" + struct.pack("<II", 2, 12 + len(body)) + body


def payload(*, buffers: list[dict[str, object]] | None = None) -> bytes:
    root: dict[str, object] = {"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"name": "CharacterRoot"}]}
    if buffers is not None:
        root["buffers"] = buffers
    return json.dumps(root, separators=(",", ":")).encode("utf-8")


def main() -> None:
    canonical_no_buffer = glb(chunk(JSON_CHUNK, payload()))
    assert inspect_glb_bytes(canonical_no_buffer)["valid"] is True
    canonical_embedded = glb(chunk(JSON_CHUNK, payload(buffers=[{"byteLength": 4}])), chunk(BIN_CHUNK, b"ABCD"))
    assert inspect_glb_bytes(canonical_embedded)["valid"] is True
    missing_bin = glb(chunk(JSON_CHUNK, payload(buffers=[{"byteLength": 4}])))
    rejected = inspect_glb_bytes(missing_bin)
    assert rejected["valid"] is False
    assert "embedded_buffer_missing_bin_chunk" in rejected["blocking_reasons"]
    truncated_bin = glb(chunk(JSON_CHUNK, payload(buffers=[{"byteLength": 8}])), chunk(BIN_CHUNK, b"ABCD"))
    rejected = inspect_glb_bytes(truncated_bin)
    assert rejected["valid"] is False
    assert "embedded_buffer_truncated" in rejected["blocking_reasons"]
    extension_glb = glb(chunk(JSON_CHUNK, payload(buffers=[{"byteLength": 4}])), chunk(BIN_CHUNK, b"ABCD"), chunk(EXTENSION_CHUNK, b"EXT0"))
    accepted = inspect_glb_bytes(extension_glb)
    assert accepted["valid"] is True
    assert accepted["extension_chunk_count"] == 1
    print("CIV1_GLB_CONTAINER_TRUTH_V3_GREEN")


if __name__ == "__main__":
    main()

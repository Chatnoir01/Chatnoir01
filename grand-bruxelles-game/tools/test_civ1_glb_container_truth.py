#!/usr/bin/env python3
from __future__ import annotations

import json
import struct

from civ1_glb_container_truth import BIN_CHUNK, JSON_CHUNK, inspect_glb_bytes


def chunk(chunk_type: int, payload: bytes) -> bytes:
    payload += b"\x00" * ((4 - len(payload) % 4) % 4)
    return struct.pack("<II", len(payload), chunk_type) + payload


def glb(*chunks: bytes) -> bytes:
    body = b"".join(chunks)
    return b"glTF" + struct.pack("<II", 2, 12 + len(body)) + body


def payload(*, buffers: list[dict[str, object]] | None = None) -> bytes:
    root: dict[str, object] = {
        "asset": {"version": "2.0"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": "CharacterRoot"}],
    }
    if buffers is not None:
        root["buffers"] = buffers
    return json.dumps(root, separators=(",", ":")).encode("utf-8")


def historical_v1_accepts(data: bytes) -> bool:
    if len(data) < 20 or data[:4] != b"glTF":
        return False
    version, declared_length = struct.unpack_from("<II", data, 4)
    if version != 2 or declared_length != len(data):
        return False
    chunks: list[tuple[int, bytes]] = []
    offset = 12
    while offset < len(data):
        if offset + 8 > len(data):
            return False
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        if chunk_length % 4 != 0:
            return False
        start = offset + 8
        end = start + chunk_length
        if end > len(data):
            return False
        chunks.append((chunk_type, data[start:end]))
        offset = end
    if offset != len(data) or not chunks or len(chunks) > 2:
        return False
    if chunks[0][0] != JSON_CHUNK:
        return False
    if len(chunks) == 2 and chunks[1][0] != BIN_CHUNK:
        return False
    try:
        root = json.loads(chunks[0][1].decode("utf-8").rstrip(" \t\r\n\x00"))
    except (UnicodeError, json.JSONDecodeError):
        return False
    asset = root.get("asset") if isinstance(root, dict) else None
    return isinstance(asset, dict) and asset.get("version") == "2.0"


def main() -> None:
    # Existing v1 topology controls remain green.
    canonical_no_buffer = glb(chunk(JSON_CHUNK, payload()))
    assert inspect_glb_bytes(canonical_no_buffer)["valid"] is True

    external_buffer = glb(chunk(JSON_CHUNK, payload(buffers=[{"byteLength": 4, "uri": "character.bin"}])))
    assert inspect_glb_bytes(external_buffer)["valid"] is True

    canonical_embedded = glb(
        chunk(JSON_CHUNK, payload(buffers=[{"byteLength": 4}])),
        chunk(BIN_CHUNK, b"ABCD"),
    )
    assert inspect_glb_bytes(canonical_embedded)["valid"] is True

    # RED 1: v1 accepted an embedded buffer declaration with no BIN chunk.
    missing_bin = glb(chunk(JSON_CHUNK, payload(buffers=[{"byteLength": 4}])))
    assert historical_v1_accepts(missing_bin) is True
    rejected = inspect_glb_bytes(missing_bin)
    assert rejected["valid"] is False
    assert "embedded_buffer_missing_bin_chunk" in rejected["blocking_reasons"]

    # RED 2: v1 accepted a BIN chunk shorter than buffers[0].byteLength.
    truncated_bin = glb(
        chunk(JSON_CHUNK, payload(buffers=[{"byteLength": 8}])),
        chunk(BIN_CHUNK, b"ABCD"),
    )
    assert historical_v1_accepts(truncated_bin) is True
    rejected = inspect_glb_bytes(truncated_bin)
    assert rejected["valid"] is False
    assert "embedded_buffer_truncated" in rejected["blocking_reasons"]

    # RED 3: v1 accepted a BIN chunk whose post-byteLength padding was non-zero.
    nonzero_padding = glb(
        chunk(JSON_CHUNK, payload(buffers=[{"byteLength": 1}])),
        chunk(BIN_CHUNK, b"ABCD"),
    )
    assert historical_v1_accepts(nonzero_padding) is True
    rejected = inspect_glb_bytes(nonzero_padding)
    assert rejected["valid"] is False
    assert "embedded_buffer_padding_not_zero" in rejected["blocking_reasons"]

    # A framed BIN chunk with no buffers[0] binding is not silently accepted.
    unbound_bin = glb(chunk(JSON_CHUNK, payload()), chunk(BIN_CHUNK, b"ABCD"))
    assert historical_v1_accepts(unbound_bin) is True
    rejected = inspect_glb_bytes(unbound_bin)
    assert rejected["valid"] is False
    assert "bin_chunk_without_embedded_buffer_binding" in rejected["blocking_reasons"]

    print("CIV1_GLB_CONTAINER_TRUTH_V2_GREEN")


if __name__ == "__main__":
    main()

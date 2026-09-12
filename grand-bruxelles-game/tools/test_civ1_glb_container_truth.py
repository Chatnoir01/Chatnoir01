#!/usr/bin/env python3
from __future__ import annotations

import json
import struct
from pathlib import Path

from civ1_glb_container_truth import (
    BIN_CHUNK,
    JSON_CHUNK,
    PLAYER_ASSET,
    inspect_file,
    inspect_glb_bytes,
    role_for_candidate,
    role_for_path,
)

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
    canonical = glb(chunk(JSON_CHUNK, payload()))
    assert inspect_glb_bytes(canonical)["valid"] is True
    embedded = glb(chunk(JSON_CHUNK, payload(buffers=[{"byteLength": 4}])), chunk(BIN_CHUNK, b"ABCD"))
    assert inspect_glb_bytes(embedded)["valid"] is True
    missing_bin = glb(chunk(JSON_CHUNK, payload(buffers=[{"byteLength": 4}])))
    assert "embedded_buffer_missing_bin_chunk" in inspect_glb_bytes(missing_bin)["blocking_reasons"]
    extension_glb = glb(chunk(JSON_CHUNK, payload(buffers=[{"byteLength": 4}])), chunk(BIN_CHUNK, b"ABCD"), chunk(EXTENSION_CHUNK, b"EXT0"))
    assert inspect_glb_bytes(extension_glb)["valid"] is True

    # Path-only identity is not enough: player role becomes qualified only after
    # the actual GLB passes the container/integrity gate.
    assert role_for_path(Path(PLAYER_ASSET)) == "player"
    assert role_for_candidate(Path(PLAYER_ASSET), valid=False) == "unverified_player"
    assert role_for_candidate(Path(PLAYER_ASSET), valid=True) == "player"
    assert role_for_candidate(Path("grand-bruxelles-game/assets/characters/civilian_candidate.glb"), valid=True) == "unclassified"
    assert role_for_candidate(Path("grand-bruxelles-game/assets/characters/police_candidate.glb"), valid=True) == "unclassified"

    player = inspect_file(Path(PLAYER_ASSET))
    assert player["valid"] is True
    assert player["role"] == "player"
    assert player["role_qualified"] is True
    assert isinstance(player["content_sha256"], str) and len(player["content_sha256"]) == 64
    int(player["content_sha256"], 16)
    print("CIV1_GLB_CONTAINER_ROLE_TRUTH_V5_GREEN")


if __name__ == "__main__":
    main()

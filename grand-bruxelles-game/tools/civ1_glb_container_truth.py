#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import struct
from pathlib import Path

SCHEMA = "grand-bruxelles-civ1-glb-container-truth-v5"
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942
PLAYER_ASSET = "grand-bruxelles-game/assets/characters/player_character.glb"


def role_for_path(path: Path) -> str:
    normalized = path.as_posix().lstrip("./")
    return "player" if normalized == PLAYER_ASSET else "unclassified"


def role_for_candidate(path: Path, *, valid: bool) -> str:
    path_role = role_for_path(path)
    if path_role == "player":
        return "player" if valid else "unverified_player"
    return "unclassified"


def inspect_glb_bytes(data: bytes) -> dict[str, object]:
    reasons: list[str] = []
    chunks: list[tuple[int, bytes]] = []
    if len(data) < 20:
        reasons.append("container_too_short")
        return _result(False, chunks, reasons, None)
    if data[:4] != b"glTF":
        reasons.append("invalid_magic")
        return _result(False, chunks, reasons, None)
    version, declared_length = struct.unpack_from("<II", data, 4)
    if version != 2:
        reasons.append("glb_version_not_2")
    if declared_length != len(data):
        reasons.append("declared_length_mismatch")
    offset = 12
    while offset < len(data):
        if offset + 8 > len(data):
            reasons.append("truncated_chunk_header")
            break
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        if chunk_length % 4 != 0:
            reasons.append("chunk_length_not_4_byte_aligned")
            break
        start, end = offset + 8, offset + 8 + chunk_length
        if end > len(data):
            reasons.append("chunk_payload_out_of_bounds")
            break
        chunks.append((chunk_type, data[start:end]))
        offset = end
    if offset != len(data):
        reasons.append("container_not_exactly_exhausted")
    root: dict[str, object] | None = None
    if not chunks:
        reasons.append("missing_json_chunk")
    elif chunks[0][0] != JSON_CHUNK:
        reasons.append("first_chunk_not_json")
    elif not chunks[0][1]:
        reasons.append("empty_json_chunk")
    else:
        try:
            parsed = json.loads(chunks[0][1].decode("utf-8").rstrip(" \t\r\n\x00"))
        except (UnicodeError, json.JSONDecodeError):
            reasons.append("invalid_json_chunk")
        else:
            if not isinstance(parsed, dict):
                reasons.append("json_root_not_object")
            else:
                root = parsed
                asset = root.get("asset")
                if not isinstance(asset, dict) or asset.get("version") != "2.0":
                    reasons.append("gltf_asset_version_not_2_0")
    json_indices = [i for i, (t, _) in enumerate(chunks) if t == JSON_CHUNK]
    bin_indices = [i for i, (t, _) in enumerate(chunks) if t == BIN_CHUNK]
    if json_indices != [0]:
        reasons.append("json_chunk_count_or_position_invalid")
    if len(bin_indices) > 1:
        reasons.append("multiple_bin_chunks")
    if bin_indices and bin_indices[0] != 1:
        reasons.append("bin_chunk_not_second")
    _validate_embedded_buffer_binding(root, chunks, reasons)
    return _result(not reasons, chunks, reasons, root)


def _validate_embedded_buffer_binding(root: dict[str, object] | None, chunks: list[tuple[int, bytes]], reasons: list[str]) -> None:
    if not isinstance(root, dict):
        return
    buffers = root.get("buffers")
    first = buffers[0] if isinstance(buffers, list) and buffers and isinstance(buffers[0], dict) else None
    bin_payload = chunks[1][1] if len(chunks) >= 2 and chunks[1][0] == BIN_CHUNK else None
    embedded = first is not None and "uri" not in first
    if embedded and bin_payload is None:
        reasons.append("embedded_buffer_missing_bin_chunk")
        return
    if bin_payload is None:
        return
    if not embedded:
        reasons.append("bin_chunk_without_embedded_buffer_binding")
        return
    byte_length = first.get("byteLength") if first is not None else None
    if isinstance(byte_length, bool) or not isinstance(byte_length, int) or byte_length < 0:
        reasons.append("embedded_buffer_byte_length_invalid")
        return
    if byte_length > len(bin_payload):
        reasons.append("embedded_buffer_truncated")
        return
    padding = bin_payload[byte_length:]
    if len(padding) > 3:
        reasons.append("embedded_buffer_padding_too_large")
    if any(value != 0 for value in padding):
        reasons.append("embedded_buffer_padding_not_zero")


def _result(valid: bool, chunks: list[tuple[int, bytes]], reasons: list[str], root: dict[str, object] | None) -> dict[str, object]:
    extension_types = [t for i, (t, _) in enumerate(chunks) if not (i == 0 and t == JSON_CHUNK) and not (i == 1 and t == BIN_CHUNK) and t not in {JSON_CHUNK, BIN_CHUNK}]
    return {"schema": SCHEMA, "valid": valid, "canonical_json_bin_order_required": True, "extension_chunks_ignored": True, "extension_chunk_count": len(extension_types), "extension_chunk_types": extension_types, "embedded_buffer_binding_required": True, "blocking_reasons": sorted(set(reasons)), "gltf_asset_version": ((root.get("asset") or {}).get("version") if isinstance(root, dict) and isinstance(root.get("asset"), dict) else None), "runtime_authorized": False, "visual_approval_claimed": False}


def inspect_file(path: Path) -> dict[str, object]:
    path_role = role_for_path(path)
    try:
        data = path.read_bytes()
    except OSError:
        return {
            "schema": SCHEMA,
            "path": path.as_posix(),
            "path_role_claim": path_role,
            "role": "unverified_player" if path_role == "player" else "unclassified",
            "role_qualified": False,
            "content_sha256": None,
            "valid": False,
            "blocking_reasons": ["file_unreadable"],
            "roster_eligible": False,
        }
    result = inspect_glb_bytes(data)
    valid = result.get("valid") is True
    role = role_for_candidate(path, valid=valid)
    result.update({
        "path": path.as_posix(),
        "path_role_claim": path_role,
        "role": role,
        "role_qualified": role == "player" and valid,
        "content_sha256": hashlib.sha256(data).hexdigest(),
        "roster_eligible": False,
    })
    return result


def build_payload(paths: list[Path]) -> dict[str, object]:
    results = [inspect_file(path) for path in paths]
    return {
        "schema": SCHEMA,
        "candidate_count": len(results),
        "valid_candidate_count": sum(1 for x in results if x.get("valid") is True),
        "player_path_claim_count": sum(1 for x in results if x.get("path_role_claim") == "player"),
        "player_asset_count": sum(1 for x in results if x.get("role") == "player" and x.get("role_qualified") is True),
        "unverified_player_count": sum(1 for x in results if x.get("role") == "unverified_player"),
        "civilian_police_roster_candidate_count": sum(1 for x in results if x.get("roster_eligible") is True),
        "player_role_requires_valid_glb": True,
        "content_sha256_recorded": True,
        "player_reuse_as_roster_forbidden": True,
        "role_inference_forbidden": True,
        "roster_authorized": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "candidates": results,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Fail-closed GLB container and role preflight for Character/NPC assets")
    parser.add_argument("paths", nargs="*", type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    payload = build_payload(args.paths)
    text = json.dumps(payload, indent=2, sort_keys=True) + "\n"
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text, encoding="utf-8")
    print(json.dumps(payload, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

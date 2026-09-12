#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path

SCHEMA = "grand-bruxelles-civ1-glb-container-truth-v2"
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942


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
        start = offset + 8
        end = start + chunk_length
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
    else:
        first_type, first_payload = chunks[0]
        if first_type != JSON_CHUNK:
            reasons.append("first_chunk_not_json")
        elif not first_payload:
            reasons.append("empty_json_chunk")
        else:
            try:
                parsed = json.loads(first_payload.decode("utf-8").rstrip(" \t\r\n\x00"))
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

    # glTF 2.0 GLB topology is exactly JSON, optionally followed by one BIN chunk.
    if len(chunks) > 2:
        reasons.append("too_many_chunks")
    if len(chunks) >= 2 and chunks[1][0] != BIN_CHUNK:
        reasons.append("second_chunk_not_bin")
    if any(chunk_type not in {JSON_CHUNK, BIN_CHUNK} for chunk_type, _ in chunks):
        reasons.append("unknown_chunk_type")
    if sum(1 for chunk_type, _ in chunks if chunk_type == JSON_CHUNK) != 1:
        reasons.append("json_chunk_count_not_one")
    if sum(1 for chunk_type, _ in chunks if chunk_type == BIN_CHUNK) > 1:
        reasons.append("multiple_bin_chunks")

    # A GLB BIN chunk is bound only through buffers[0] with no URI. Enforce the
    # binding, declared byte length and zero padding so a structurally framed
    # file cannot point at absent/truncated embedded character data.
    _validate_embedded_buffer_binding(root, chunks, reasons)

    return _result(not reasons, chunks, reasons, root)


def _validate_embedded_buffer_binding(
    root: dict[str, object] | None,
    chunks: list[tuple[int, bytes]],
    reasons: list[str],
) -> None:
    if not isinstance(root, dict):
        return

    buffers = root.get("buffers")
    first_buffer: dict[str, object] | None = None
    if isinstance(buffers, list) and buffers and isinstance(buffers[0], dict):
        first_buffer = buffers[0]

    bin_payload: bytes | None = None
    if len(chunks) >= 2 and chunks[1][0] == BIN_CHUNK:
        bin_payload = chunks[1][1]

    first_is_embedded = first_buffer is not None and "uri" not in first_buffer
    if first_is_embedded and bin_payload is None:
        reasons.append("embedded_buffer_missing_bin_chunk")
        return

    if bin_payload is None:
        return

    if not first_is_embedded:
        reasons.append("bin_chunk_without_embedded_buffer_binding")
        return

    byte_length = first_buffer.get("byteLength") if first_buffer is not None else None
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
    return {
        "schema": SCHEMA,
        "valid": valid,
        "strict_chunk_topology_required": True,
        "embedded_buffer_binding_required": True,
        "embedded_buffer_length_required": True,
        "embedded_buffer_zero_padding_required": True,
        "json_first_required": True,
        "optional_single_bin_second_required": True,
        "unknown_chunks_rejected": True,
        "chunk_types": [chunk_type for chunk_type, _ in chunks],
        "blocking_reasons": sorted(set(reasons)),
        "gltf_asset_version": ((root.get("asset") or {}).get("version") if isinstance(root, dict) and isinstance(root.get("asset"), dict) else None),
        "runtime_authorized": False,
        "visual_approval_claimed": False,
    }


def inspect_file(path: Path) -> dict[str, object]:
    try:
        data = path.read_bytes()
    except OSError:
        return {
            "schema": SCHEMA,
            "path": str(path),
            "valid": False,
            "blocking_reasons": ["file_unreadable"],
            "runtime_authorized": False,
            "visual_approval_claimed": False,
        }
    result = inspect_glb_bytes(data)
    result["path"] = str(path)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description="Fail-closed GLB container preflight for Character/NPC assets")
    parser.add_argument("paths", nargs="*", type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()

    results = [inspect_file(path) for path in args.paths]
    payload = {
        "schema": SCHEMA,
        "candidate_count": len(results),
        "valid_candidate_count": sum(1 for item in results if item.get("valid") is True),
        "all_candidates_valid": bool(results) and all(item.get("valid") is True for item in results),
        "strict_chunk_topology_required": True,
        "embedded_buffer_binding_required": True,
        "embedded_buffer_length_required": True,
        "embedded_buffer_zero_padding_required": True,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "candidates": results,
    }
    text = json.dumps(payload, indent=2, sort_keys=True) + "\n"
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text, encoding="utf-8")
    print(json.dumps(payload, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

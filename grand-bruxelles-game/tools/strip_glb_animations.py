#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

GLB_MAGIC = b"glTF"
GLB_VERSION = 2
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942


class GlbError(ValueError):
    pass


def _pad4(data: bytes, pad: bytes) -> bytes:
    remainder = len(data) % 4
    if remainder:
        data += pad * (4 - remainder)
    return data


def parse_glb(data: bytes) -> tuple[dict, list[tuple[int, bytes]]]:
    if len(data) < 12:
        raise GlbError("GLB header truncated")
    magic, version, declared_length = struct.unpack_from("<4sII", data, 0)
    if magic != GLB_MAGIC:
        raise GlbError("invalid GLB magic")
    if version != GLB_VERSION:
        raise GlbError(f"unsupported GLB version: {version}")
    if declared_length != len(data):
        raise GlbError(f"declared GLB length {declared_length} != actual {len(data)}")

    offset = 12
    chunks: list[tuple[int, bytes]] = []
    while offset < len(data):
        if offset + 8 > len(data):
            raise GlbError("chunk header truncated")
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        offset += 8
        end = offset + chunk_length
        if end > len(data):
            raise GlbError("chunk payload truncated")
        chunks.append((chunk_type, data[offset:end]))
        offset = end
    if not chunks or chunks[0][0] != JSON_CHUNK:
        raise GlbError("first GLB chunk must be JSON")
    if sum(1 for kind, _ in chunks if kind == JSON_CHUNK) != 1:
        raise GlbError("GLB must contain exactly one JSON chunk")

    try:
        document = json.loads(chunks[0][1].rstrip(b" \t\r\n\x00").decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise GlbError(f"invalid GLB JSON: {exc}") from exc
    if not isinstance(document, dict):
        raise GlbError("GLB JSON root must be an object")
    return document, chunks[1:]


def strip_animations(data: bytes) -> tuple[bytes, int]:
    document, extra_chunks = parse_glb(data)
    animations = document.get("animations", [])
    if animations is None:
        animations = []
    if not isinstance(animations, list):
        raise GlbError("animations must be an array when present")
    removed = len(animations)
    document.pop("animations", None)

    json_bytes = json.dumps(document, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    json_bytes = _pad4(json_bytes, b" ")

    chunks = [(JSON_CHUNK, json_bytes), *extra_chunks]
    body = bytearray()
    for chunk_type, chunk_data in chunks:
        body += struct.pack("<II", len(chunk_data), chunk_type)
        body += chunk_data
    output = struct.pack("<4sII", GLB_MAGIC, GLB_VERSION, 12 + len(body)) + bytes(body)

    reparsed, reparsed_extra = parse_glb(output)
    if "animations" in reparsed:
        raise GlbError("animation payload survived stripping")
    if reparsed_extra != extra_chunks:
        raise GlbError("non-JSON GLB chunks changed during stripping")
    return output, removed


def main() -> int:
    parser = argparse.ArgumentParser(description="Strip all glTF animation objects from a GLB while preserving geometry/skin/material payloads")
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--require-animations", action="store_true", help="fail if the source GLB contains no animations")
    args = parser.parse_args()

    try:
        source = args.input.read_bytes()
        output, removed = strip_animations(source)
        if args.require_animations and removed == 0:
            raise GlbError("source GLB contains no animations")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(output)
    except (OSError, GlbError) as exc:
        print(f"GLB_ANIMATION_STRIP_FAIL: {exc}", file=sys.stderr)
        return 1

    print("GLB_ANIMATION_STRIP_OK")
    print(f"removed_animations={removed}")
    print(f"output_bytes={len(output)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

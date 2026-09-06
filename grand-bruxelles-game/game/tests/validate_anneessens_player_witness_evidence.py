#!/usr/bin/env python3
"""Fail-closed validator for the staged Anneessens player-view evidence package."""
from __future__ import annotations

import hashlib
import json
import math
import re
import struct
import sys
import zlib
from pathlib import Path

SCHEMA = "grand-bruxelles-anneessens-player-witness-v1"
ROAD_OSM_ID = 1382734012
FRAME_NAME = "automatic_road_1382734012_player.png"
LOG_NAME = "runtime.log"
MANIFEST_NAME = "evidence-manifest.json"
HASHES_NAME = "evidence-sha256.txt"
CANONICAL_SOURCE_REL = "grand-bruxelles-game/data/osm/vertical_slice_01.game.json"
PROJECT_ROOT = Path(__file__).resolve().parents[2]
CANONICAL_SOURCE = PROJECT_ROOT / "data" / "osm" / "vertical_slice_01.game.json"
GIT_SHA40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
FROZEN_FRAME_SIZE = (1280, 720)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fail(message: str) -> None:
    raise AssertionError(message)


def png_dimensions(path: Path) -> tuple[int, int]:
    data = path.read_bytes()
    if not data.startswith(PNG_SIGNATURE):
        fail("player frame is not a PNG")
    offset = len(PNG_SIGNATURE)
    width = height = bit_depth = color_type = interlace = None
    saw_ihdr = saw_idat = saw_iend = False
    idat = bytearray()
    while offset < len(data):
        if len(data) - offset < 12:
            fail("player frame PNG stream is truncated before a complete chunk")
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        chunk_type = data[offset + 4:offset + 8]
        data_start = offset + 8
        data_end = data_start + length
        crc_end = data_end + 4
        if crc_end > len(data):
            fail("player frame PNG chunk payload is truncated")
        chunk_data = data[data_start:data_end]
        expected_crc = struct.unpack(">I", data[data_end:crc_end])[0]
        actual_crc = zlib.crc32(chunk_type)
        actual_crc = zlib.crc32(chunk_data, actual_crc) & 0xFFFFFFFF
        if expected_crc != actual_crc:
            fail(f"player frame PNG chunk CRC mismatch: {chunk_type!r}")
        if not saw_ihdr:
            if chunk_type != b"IHDR" or length != 13:
                fail("player frame PNG does not begin with a canonical IHDR chunk")
            width, height, bit_depth, color_type, compression, filtering, interlace = struct.unpack(">IIBBBBB", chunk_data)
            if width <= 0 or height <= 0:
                fail("player frame PNG has invalid dimensions")
            if compression != 0 or filtering != 0:
                fail("player frame PNG uses unsupported compression/filter method")
            if interlace != 0:
                fail("player frame PNG must be non-interlaced for deterministic evidence validation")
            saw_ihdr = True
        elif chunk_type == b"IHDR":
            fail("player frame PNG contains multiple IHDR chunks")
        if chunk_type == b"IDAT":
            if saw_iend:
                fail("player frame PNG contains IDAT after IEND")
            saw_idat = True
            idat.extend(chunk_data)
        elif chunk_type == b"IEND":
            if length != 0:
                fail("player frame PNG IEND chunk must be empty")
            saw_iend = True
            offset = crc_end
            break
        offset = crc_end
    if not saw_ihdr:
        fail("player frame PNG is missing IHDR")
    if not saw_idat:
        fail("player frame PNG is missing IDAT image payload")
    if not saw_iend:
        fail("player frame PNG stream is truncated before IEND")
    if offset != len(data):
        fail("player frame PNG has trailing bytes after IEND")
    channels_by_color_type = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}
    valid_depths = {0: {1, 2, 4, 8, 16}, 2: {8, 16}, 3: {1, 2, 4, 8}, 4: {8, 16}, 6: {8, 16}}
    if color_type not in channels_by_color_type or bit_depth not in valid_depths[color_type]:
        fail(f"player frame PNG has unsupported IHDR format: depth={bit_depth} color={color_type}")
    try:
        decompressor = zlib.decompressobj()
        raw = decompressor.decompress(bytes(idat))
        raw += decompressor.flush()
    except zlib.error as exc:
        fail(f"player frame PNG IDAT stream cannot be decompressed: {exc}")
    if not decompressor.eof:
        fail("player frame PNG IDAT zlib stream ended before a complete EOF marker")
    if decompressor.unused_data or decompressor.unconsumed_tail:
        fail("player frame PNG IDAT contains trailing compressed bytes after zlib stream EOF")
    channels = channels_by_color_type[color_type]
    row_bytes = math.ceil(width * channels * bit_depth / 8)
    expected_raw_size = height * (row_bytes + 1)
    if len(raw) != expected_raw_size:
        fail(f"player frame PNG decompressed image size does not match IHDR: expected={expected_raw_size} actual={len(raw)}")
    stride = row_bytes + 1
    for row in range(height):
        filter_type = raw[row * stride]
        if filter_type > 4:
            fail(f"player frame PNG row {row} has invalid filter type {filter_type}")
    return int(width), int(height)


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: validate_anneessens_player_witness_evidence.py <stage-dir> <expected-pr-head-sha> <expected-live-main-sha>", file=sys.stderr)
        return 2
    stage = Path(sys.argv[1])
    expected_head = sys.argv[2].strip().lower()
    expected_main = sys.argv[3].strip().lower()
    for label, value in (("expected PR head", expected_head), ("expected live main", expected_main)):
        if not GIT_SHA40.fullmatch(value):
            fail(f"{label} is not a lowercase 40-hex Git SHA: {value!r}")
    manifest_path = stage / MANIFEST_NAME
    frame_path = stage / FRAME_NAME
    log_path = stage / LOG_NAME
    hashes_path = stage / HASHES_NAME
    for path in (manifest_path, frame_path, log_path, hashes_path):
        if not path.is_file() or path.stat().st_size == 0:
            fail(f"missing or empty evidence file: {path.name}")
    if not CANONICAL_SOURCE.is_file() or CANONICAL_SOURCE.stat().st_size == 0:
        fail("canonical Anneessens OSM source is missing or empty in checkout")
    payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    required = {"schema", "road_osm_id", "pr_head_sha", "live_main_sha", "source_path", "source_sha256", "emitted_source_sha256", "source_sha_matches", "trace_count", "building_hits", "visual_acceptance", "destination_advertisable", "jouable_authorized", "human_review_required", "frame_width", "frame_height", "frame_sha256", "runtime_log_sha256"}
    missing = sorted(required.difference(payload))
    if missing:
        fail(f"manifest missing required fields: {missing}")
    if payload["schema"] != SCHEMA:
        fail(f"unexpected schema: {payload['schema']!r}")
    if payload["road_osm_id"] != ROAD_OSM_ID:
        fail(f"unexpected road_osm_id: {payload['road_osm_id']!r}")
    if payload["pr_head_sha"] != expected_head:
        fail("manifest PR head is not the exact workflow PR head")
    if payload["live_main_sha"] != expected_main:
        fail("manifest live main is not the exact workflow live main")
    if payload["source_path"] != CANONICAL_SOURCE_REL:
        fail("manifest source_path is not canonical")
    manifest_frame_size = (payload["frame_width"], payload["frame_height"])
    if manifest_frame_size != FROZEN_FRAME_SIZE:
        fail("player frame dimensions are not frozen at 1280x720")
    actual_frame_size = png_dimensions(frame_path)
    if actual_frame_size != FROZEN_FRAME_SIZE:
        fail(f"staged PNG dimensions are not frozen at 1280x720: {actual_frame_size}")
    if manifest_frame_size != actual_frame_size:
        fail("manifest frame dimensions do not match staged PNG bytes")
    actual_frame_sha = sha256(frame_path)
    actual_log_sha = sha256(log_path)
    actual_source_sha = sha256(CANONICAL_SOURCE)
    if payload["frame_sha256"] != actual_frame_sha:
        fail("manifest frame_sha256 does not match staged PNG bytes")
    if payload["runtime_log_sha256"] != actual_log_sha:
        fail("manifest runtime_log_sha256 does not match staged runtime log bytes")
    for field in ("source_sha256", "emitted_source_sha256", "frame_sha256", "runtime_log_sha256"):
        value = payload[field]
        if not isinstance(value, str) or not HEX64.fullmatch(value):
            fail(f"manifest {field} must be lowercase 64-hex")
    if payload["source_sha256"] != actual_source_sha:
        fail("manifest source_sha256 does not match canonical source bytes")
    log = log_path.read_text(encoding="utf-8", errors="replace")
    green_rows = re.findall(r"ANNEESSENS_AUTOMATIC_ROAD_PLAYER_WITNESS_GREEN:[^\n]*", log)
    if len(green_rows) != 1:
        fail(f"runtime log must contain exactly one witness GREEN row, found {len(green_rows)}")
    green_row = green_rows[0]
    road_match = re.search(r"\bosm_id=(\d+)\b", green_row)
    source_match = re.search(r"\bsource_sha=([0-9a-f]{64})\b", green_row)
    if road_match is None or int(road_match.group(1)) != ROAD_OSM_ID:
        fail("runtime GREEN witness is not for canonical Anneessens road osm_id=1382734012")
    if source_match is None:
        fail("runtime GREEN witness is missing source_sha")
    emitted_source_sha = source_match.group(1)
    if payload["emitted_source_sha256"] != emitted_source_sha:
        fail("emitted_source_sha256 does not match runtime GREEN source_sha")
    if payload["source_sha_matches"] is not (payload["source_sha256"] == payload["emitted_source_sha256"] == actual_source_sha):
        fail("source_sha_matches disagrees with canonical/runtime source SHA values")
    traces = re.findall(r"ANNEESSENS_VISUAL_BLOCKER_TRACE: sample=\([^\n]+", log)
    building_hits = sum("hit=true" in row and "collider_name=Building_" in row for row in traces)
    if payload["trace_count"] != len(traces):
        fail("manifest trace_count does not match runtime log")
    if payload["building_hits"] != building_hits:
        fail("manifest building_hits does not match runtime log")
    expected_visual_acceptance = len(traces) == 3 and 1 <= building_hits <= 2 and payload["source_sha_matches"]
    if payload["visual_acceptance"] is not expected_visual_acceptance:
        fail("visual_acceptance disagrees with frozen 3-ray/source-SHA rule")
    if payload["destination_advertisable"] is not False:
        fail("evidence artifact may not self-advertise destination readiness")
    if payload["jouable_authorized"] is not False:
        fail("evidence artifact may not self-authorize JOUABLE")
    if payload["human_review_required"] is not True:
        fail("human review must remain required")
    sidecar = {}
    for raw_line in hashes_path.read_text(encoding="utf-8").splitlines():
        parts = raw_line.split(maxsplit=1)
        if len(parts) != 2:
            fail(f"malformed evidence hash line: {raw_line!r}")
        digest, filename = parts
        filename = filename.lstrip("*")
        sidecar[filename] = digest
    expected_sidecar = {FRAME_NAME: actual_frame_sha, LOG_NAME: actual_log_sha, MANIFEST_NAME: sha256(manifest_path)}
    if sidecar != expected_sidecar:
        fail(f"evidence-sha256.txt does not exactly bind staged evidence: {sidecar!r}")
    print("ANNEESSENS_PLAYER_WITNESS_EVIDENCE_GREEN " f"head={expected_head} main={expected_main} hits={building_hits} " f"source_sha256={actual_source_sha} visual_acceptance={str(expected_visual_acceptance).lower()} " f"frame_sha256={actual_frame_sha}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"ANNEESSENS_PLAYER_WITNESS_EVIDENCE_FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)

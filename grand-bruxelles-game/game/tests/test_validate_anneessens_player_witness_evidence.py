#!/usr/bin/env python3
"""Regression tests for staged Anneessens evidence integrity."""
from __future__ import annotations

import hashlib
import json
import struct
import subprocess
import tempfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = ROOT / "game" / "tests" / "validate_anneessens_player_witness_evidence.py"
CANONICAL_SOURCE = ROOT / "data" / "osm" / "vertical_slice_01.game.json"
CANONICAL_SOURCE_PATH = "grand-bruxelles-game/data/osm/vertical_slice_01.game.json"
FRAME = "automatic_road_1382734012_player.png"
# GitHub currently supplies full Git object ids for this repository as SHA-1
# (40 lowercase hex). Keep these distinct from SHA-256 evidence digests below.
HEAD = "1" * 40
MAIN = "2" * 40
SOURCE_SHA = hashlib.sha256(CANONICAL_SOURCE.read_bytes()).hexdigest()
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def png_chunk(kind: bytes, payload: bytes) -> bytes:
    crc = zlib.crc32(kind)
    crc = zlib.crc32(payload, crc) & 0xFFFFFFFF
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", crc)


def fake_png(width: int, height: int) -> bytes:
    # Deterministic, fully valid non-interlaced RGBA8 PNG used only by the
    # validator regression. Zero-filled scanlines compress to a small fixture.
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    scanline = b"\x00" + (b"\x00" * (width * 4))
    raw = scanline * height
    return (
        PNG_SIGNATURE
        + png_chunk(b"IHDR", ihdr)
        + png_chunk(b"IDAT", zlib.compress(raw, level=9))
        + png_chunk(b"IEND", b"")
    )


def header_only_png(width: int, height: int) -> bytes:
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return PNG_SIGNATURE + png_chunk(b"IHDR", ihdr)


def write_stage(stage: Path, width: int = 1280, height: int = 720) -> None:
    frame = stage / FRAME
    log = stage / "runtime.log"
    manifest = stage / "evidence-manifest.json"
    frame.write_bytes(fake_png(width, height))
    log.write_text(
        "ANNEESSENS_AUTOMATIC_ROAD_PLAYER_WITNESS_GREEN: osm_id=1382734012 source_sha=" + SOURCE_SHA + " destination_advertisable=false jouable_authorized=false\n"
        "ANNEESSENS_VISUAL_BLOCKER_TRACE: sample=(760,360) hit=true collider_name=Building_1\n"
        "ANNEESSENS_VISUAL_BLOCKER_TRACE: sample=(900,360) hit=false\n"
        "ANNEESSENS_VISUAL_BLOCKER_TRACE: sample=(1100,360) hit=false\n",
        encoding="utf-8",
    )
    payload = {
        "schema": "grand-bruxelles-anneessens-player-witness-v1",
        "road_osm_id": 1382734012,
        "pr_head_sha": HEAD,
        "live_main_sha": MAIN,
        "source_path": CANONICAL_SOURCE_PATH,
        "source_sha256": SOURCE_SHA,
        "emitted_source_sha256": SOURCE_SHA,
        "source_sha_matches": True,
        "trace_count": 3,
        "building_hits": 1,
        "visual_acceptance": True,
        "destination_advertisable": False,
        "jouable_authorized": False,
        "human_review_required": True,
        "frame_width": 1280,
        "frame_height": 720,
        "frame_sha256": sha(frame),
        "runtime_log_sha256": sha(log),
    }
    manifest.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    refresh_sidecar(stage)


def refresh_sidecar(stage: Path) -> None:
    frame = stage / FRAME
    manifest = stage / "evidence-manifest.json"
    log = stage / "runtime.log"
    (stage / "evidence-sha256.txt").write_text(
        f"{sha(frame)}  {FRAME}\n"
        f"{sha(manifest)}  evidence-manifest.json\n"
        f"{sha(log)}  runtime.log\n",
        encoding="utf-8",
    )


def refresh_frame_binding(stage: Path) -> None:
    frame = stage / FRAME
    manifest_path = stage / "evidence-manifest.json"
    payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    payload["frame_sha256"] = sha(frame)
    manifest_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    refresh_sidecar(stage)


def rewrite_manifest(stage: Path, **changes: object) -> None:
    manifest_path = stage / "evidence-manifest.json"
    payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    payload.update(changes)
    manifest_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    refresh_sidecar(stage)


def run(stage: Path, head: str = HEAD, main: str = MAIN) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["python3", str(VALIDATOR), str(stage), head, main],
        text=True,
        capture_output=True,
        check=False,
    )


with tempfile.TemporaryDirectory() as tmp:
    stage = Path(tmp)
    write_stage(stage)
    result = run(stage)
    assert result.returncode == 0, result.stderr
    assert "ANNEESSENS_PLAYER_WITNESS_EVIDENCE_GREEN" in result.stdout

# Do not silently conflate Git object ids with evidence SHA-256 digests. A
# 64-hex string is a content digest shape here, not the exact GitHub commit-id
# shape consumed by this workflow.
with tempfile.TemporaryDirectory() as tmp:
    stage = Path(tmp)
    write_stage(stage)
    result = run(stage, "a" * 64, MAIN)
    assert result.returncode == 1, result.stdout
    assert "expected PR head is not a lowercase 40-hex Git SHA" in result.stderr

with tempfile.TemporaryDirectory() as tmp:
    stage = Path(tmp)
    write_stage(stage, width=640, height=720)
    result = run(stage)
    assert result.returncode == 1, result.stdout
    assert "staged PNG dimensions are not frozen at 1280x720" in result.stderr

with tempfile.TemporaryDirectory() as tmp:
    stage = Path(tmp)
    write_stage(stage)
    # Rebind every manifest/sidecar hash to a header-only 1280x720 PNG. This
    # reproduces the evidence-integrity hole independently of checksum binding:
    # dimensions and hashes agree, but there is no reviewable image payload.
    (stage / FRAME).write_bytes(header_only_png(1280, 720))
    refresh_frame_binding(stage)
    result = run(stage)
    assert result.returncode == 1, result.stdout
    assert "PNG is missing IDAT image payload" in result.stderr

with tempfile.TemporaryDirectory() as tmp:
    stage = Path(tmp)
    write_stage(stage)
    frame = stage / FRAME
    data = bytearray(frame.read_bytes())
    # Flip one IDAT payload byte while rebinding the outer SHA. PNG CRC must still
    # detect corruption before the artifact can be accepted for human review.
    idat = data.index(b"IDAT")
    payload_index = idat + 4
    data[payload_index] ^= 0x01
    frame.write_bytes(bytes(data))
    refresh_frame_binding(stage)
    result = run(stage)
    assert result.returncode == 1, result.stdout
    assert "PNG chunk CRC mismatch" in result.stderr

with tempfile.TemporaryDirectory() as tmp:
    stage = Path(tmp)
    write_stage(stage)
    rewrite_manifest(stage, source_path="grand-bruxelles-game/data/osm/forged.game.json")
    result = run(stage)
    assert result.returncode == 1, result.stdout
    assert "manifest source_path is not canonical" in result.stderr

with tempfile.TemporaryDirectory() as tmp:
    stage = Path(tmp)
    write_stage(stage)
    forged_sha = "4" * 64
    rewrite_manifest(
        stage,
        source_sha256=forged_sha,
        emitted_source_sha256=forged_sha,
        source_sha_matches=True,
    )
    result = run(stage)
    assert result.returncode == 1, result.stdout
    assert "manifest source_sha256 does not match canonical source bytes" in result.stderr

with tempfile.TemporaryDirectory() as tmp:
    stage = Path(tmp)
    write_stage(stage)
    log = stage / "runtime.log"
    log.write_text(log.read_text(encoding="utf-8").replace(SOURCE_SHA, "5" * 64), encoding="utf-8")
    manifest_path = stage / "evidence-manifest.json"
    payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    payload["runtime_log_sha256"] = sha(log)
    manifest_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    refresh_sidecar(stage)
    result = run(stage)
    assert result.returncode == 1, result.stdout
    assert "emitted_source_sha256 does not match runtime GREEN source_sha" in result.stderr

print("ANNEESSENS_PLAYER_WITNESS_EVIDENCE_VALIDATOR_REGRESSION_GREEN")

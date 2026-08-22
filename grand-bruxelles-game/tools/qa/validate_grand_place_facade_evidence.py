#!/usr/bin/env python3
"""Fail-closed structural validator for the dedicated Grand-Place facade witness.

A successful exit proves artifact structure and exact frozen target binding only. It never
means the visual gate passed: full-frame human review remains mandatory.
"""

from __future__ import annotations

import argparse
import json
import re
import struct
import zlib
from pathlib import Path
from typing import Any

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
SHA40 = re.compile(r"^[0-9a-f]{40}$")
EXPECTED_SCHEMA = "grand-bruxelles-grand-place-facade-evidence-v1"


class EvidenceValidationError(ValueError):
    pass


def _fail(message: str) -> None:
    raise EvidenceValidationError(message)


def _load_json(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        _fail(f"cannot read JSON {path}: {exc}")
    if not isinstance(data, dict):
        _fail(f"JSON root must be an object: {path}")
    return data


def _png_dimensions(path: Path) -> tuple[int, int]:
    try:
        blob = path.read_bytes()
    except OSError as exc:
        _fail(f"cannot read witness PNG {path}: {exc}")
    if not blob.startswith(PNG_SIGNATURE):
        _fail(f"witness is not a PNG: {path}")
    offset = len(PNG_SIGNATURE)
    dimensions = None
    seen_idat = False
    seen_iend = False
    chunk_index = 0
    while offset < len(blob):
        if len(blob) - offset < 12:
            _fail(f"truncated PNG chunk header/trailer: {path}")
        length = struct.unpack(">I", blob[offset:offset + 4])[0]
        kind = blob[offset + 4:offset + 8]
        payload_start = offset + 8
        payload_end = payload_start + length
        crc_end = payload_end + 4
        if crc_end > len(blob):
            _fail(f"truncated PNG chunk payload: {path}")
        payload = blob[payload_start:payload_end]
        expected_crc = struct.unpack(">I", blob[payload_end:crc_end])[0]
        actual_crc = zlib.crc32(kind + payload) & 0xFFFFFFFF
        if actual_crc != expected_crc:
            _fail(f"PNG CRC mismatch in {kind!r}: {path}")
        if chunk_index == 0:
            if kind != b"IHDR" or length != 13:
                _fail(f"PNG must start with a canonical IHDR chunk: {path}")
            width, height = struct.unpack(">II", payload[:8])
            if width <= 0 or height <= 0:
                _fail(f"invalid PNG dimensions in {path}: {width}x{height}")
            dimensions = (width, height)
        elif kind == b"IHDR":
            _fail(f"PNG contains multiple IHDR chunks: {path}")
        if kind == b"IDAT":
            seen_idat = True
        elif kind == b"IEND":
            if length != 0:
                _fail(f"PNG IEND chunk must be empty: {path}")
            if crc_end != len(blob):
                _fail(f"PNG has trailing bytes after IEND: {path}")
            seen_iend = True
            offset = crc_end
            break
        offset = crc_end
        chunk_index += 1
    if dimensions is None or not seen_idat or not seen_iend or offset != len(blob):
        _fail(f"PNG is structurally incomplete: {path}")
    return dimensions


def _safe_artifact_file(root: Path, raw: Any) -> Path:
    if not isinstance(raw, str) or not raw or "\\" in raw:
        _fail("view png must be a non-empty POSIX relative path")
    relative = Path(raw)
    if relative.is_absolute() or ".." in relative.parts or relative.suffix.lower() != ".png":
        _fail(f"unsafe witness PNG path: {raw!r}")
    root = root.resolve()
    candidate = (root / relative).resolve()
    try:
        candidate.relative_to(root)
    except ValueError:
        _fail(f"witness PNG escapes artifact root: {raw!r}")
    if not candidate.is_file():
        _fail(f"missing witness PNG: {raw!r}")
    return candidate


def _exact_sequence(name: str, actual: Any, expected: list[Any]) -> None:
    if not isinstance(actual, list) or actual != expected:
        _fail(f"{name} drifted: expected {expected!r}, got {actual!r}")


def _validate_view_target_binding(view: dict[str, Any], frozen: dict[str, Any]) -> None:
    if view.get("target_method") != frozen.get("target_method"):
        _fail(f"view {frozen.get('id')!r} target_method drifted")
    method = frozen.get("target_method")
    if method == "fixed_existing_witness":
        _exact_sequence(f"view {frozen['id']} target", view.get("target"), frozen.get("target"))
        if "target_owner_ids" in view:
            _fail(f"view {frozen['id']!r} must not invent target_owner_ids")
    elif method == "source_bbox_cluster_center":
        _exact_sequence(
            f"view {frozen['id']} target_owner_ids",
            view.get("target_owner_ids"),
            frozen.get("target_owner_ids"),
        )
        if "target" in view:
            _fail(f"view {frozen['id']!r} must not replace source owners with a free target")
    else:
        _fail(f"unsupported frozen target_method for {frozen.get('id')!r}: {method!r}")


def validate_evidence(gate_path: Path | str, manifest_path: Path | str, artifact_root: Path | str | None = None) -> dict[str, Any]:
    gate_path = Path(gate_path)
    manifest_path = Path(manifest_path)
    gate = _load_json(gate_path)
    manifest = _load_json(manifest_path)
    contract = gate.get("evidence_contract")
    if not isinstance(contract, dict):
        _fail("gate is missing evidence_contract")
    if manifest.get("schema") != EXPECTED_SCHEMA:
        _fail(f"unsupported evidence schema: {manifest.get('schema')!r}")
    if manifest.get("artifact_kind") != contract.get("artifact_kind"):
        _fail("artifact kind does not match the dedicated Grand-Place witness contract")
    base_sha = manifest.get("base_sha")
    head_sha = manifest.get("head_sha")
    if not isinstance(base_sha, str) or SHA40.fullmatch(base_sha) is None:
        _fail("base_sha must be a lowercase 40-hex commit SHA")
    if not isinstance(head_sha, str) or SHA40.fullmatch(head_sha) is None:
        _fail("head_sha must be a lowercase 40-hex commit SHA")
    if base_sha != gate.get("production_base_sha"):
        _fail("witness base_sha does not match the frozen production base")
    if head_sha == base_sha:
        _fail("witness head_sha must identify the candidate, not the production base")
    required_resolution = contract.get("required_resolution")
    if not isinstance(required_resolution, list) or len(required_resolution) != 2:
        _fail("gate required_resolution is malformed")
    _exact_sequence("manifest resolution", manifest.get("resolution"), required_resolution)
    _exact_sequence("manifest camera_position", manifest.get("camera_position"), gate.get("camera_position"))
    if manifest.get("fov_deg") != gate.get("fov_deg"):
        _fail("manifest fov_deg drifted from the frozen gate")
    if manifest.get("human_review_required") is not True:
        _fail("dedicated witness must require human full-frame review")
    if manifest.get("human_review_status") != "pending":
        _fail("CI evidence must remain human-review pending; it cannot self-approve or self-reject")
    required_ids = contract.get("required_view_ids")
    if not isinstance(required_ids, list) or not required_ids or not all(isinstance(item, str) and item for item in required_ids):
        _fail("gate required_view_ids is malformed")
    if len(required_ids) != len(set(required_ids)):
        _fail("gate required_view_ids contains duplicates")
    if gate.get("required_views") != len(required_ids):
        _fail("gate required_views count disagrees with evidence_contract")
    frozen_views = gate.get("views")
    if not isinstance(frozen_views, list) or [v.get("id") for v in frozen_views if isinstance(v, dict)] != required_ids:
        _fail("gate views/order drifted from evidence_contract")
    views = manifest.get("views")
    if not isinstance(views, list) or len(views) != len(required_ids):
        _fail(f"witness must contain exactly {len(required_ids)} views")
    view_ids = [view.get("id") if isinstance(view, dict) else None for view in views]
    if view_ids != required_ids or len(set(view_ids)) != len(view_ids):
        _fail(f"witness view IDs/order must exactly equal {required_ids!r}")
    root = Path(artifact_root) if artifact_root is not None else manifest_path.parent
    expected_dims = (int(required_resolution[0]), int(required_resolution[1]))
    validated_files = []
    seen_files = set()
    for view, frozen in zip(views, frozen_views, strict=True):
        if not isinstance(view, dict) or not isinstance(frozen, dict):
            _fail("view entries must be objects")
        _validate_view_target_binding(view, frozen)
        png = _safe_artifact_file(root, view.get("png"))
        if png in seen_files:
            _fail(f"multiple required views reuse one PNG: {png.name}")
        seen_files.add(png)
        dims = _png_dimensions(png)
        if dims != expected_dims:
            _fail(f"witness PNG {png.name} is {dims[0]}x{dims[1]}, expected {expected_dims[0]}x{expected_dims[1]}")
        validated_files.append(str(png))
    if contract.get("generic_photo_match_artifact_is_sufficient") is not False:
        _fail("gate must explicitly reject generic Photo Match as sufficient evidence")
    if contract.get("human_full_frame_inspection_required") is not True:
        _fail("gate must explicitly require human full-frame inspection")
    if contract.get("numeric_gate_alone_is_sufficient") is not False:
        _fail("gate must explicitly reject numeric-only authorization")
    return {
        "artifact_kind": manifest["artifact_kind"],
        "base_sha": base_sha,
        "head_sha": head_sha,
        "resolution": list(expected_dims),
        "view_count": len(validated_files),
        "view_ids": view_ids,
        "files": validated_files,
        "human_review_status": "pending",
        "visual_approval_claimed": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gate", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--artifact-root", type=Path)
    args = parser.parse_args()
    try:
        result = validate_evidence(args.gate, args.manifest, args.artifact_root)
    except EvidenceValidationError as exc:
        print(f"GRAND_PLACE_FACADE_EVIDENCE_FAIL {exc}")
        return 1
    print(
        "GRAND_PLACE_FACADE_EVIDENCE_STRUCTURALLY_VALID "
        f"views={result['view_count']} resolution={result['resolution'][0]}x{result['resolution'][1]} "
        "human_review=pending visual_approval_claimed=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

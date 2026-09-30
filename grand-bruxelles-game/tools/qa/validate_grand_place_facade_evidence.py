#!/usr/bin/env python3
"""Fail-closed structural validator for the dedicated Grand-Place facade witness.

A successful exit proves artifact structure and exact frozen target binding only. It never
means the visual gate passed: full-frame human review remains mandatory.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import struct
import zlib
from pathlib import Path
from typing import Any

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
SHA40 = re.compile(r"^[0-9a-f]{40}$")
EXPECTED_SCHEMA = "grand-bruxelles-grand-place-facade-evidence-v1"
MAISON_DU_ROI_OWNER_ID = "1654360"


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
        _exact_sequence(f"view {frozen['id']} target_owner_ids", view.get("target_owner_ids"), frozen.get("target_owner_ids"))
        if "target" in view:
            _fail(f"view {frozen['id']!r} must not replace source owners with a free target")
    else:
        _fail(f"unsupported frozen target_method for {frozen.get('id')!r}: {method!r}")


def _finite_number(value: Any, name: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        _fail(f"{name} must be numeric")
    value = float(value)
    if not math.isfinite(value):
        _fail(f"{name} must be finite")
    return value


def _canonical_float32(value: Any, name: str) -> float:
    numeric = _finite_number(value, name)
    try:
        return struct.unpack(">f", struct.pack(">f", numeric))[0]
    except (OverflowError, struct.error):
        _fail(f"{name} is outside Float32 range")


def _exact_float32_sequence(name: str, actual: Any, expected: list[Any]) -> None:
    if not isinstance(actual, list) or len(actual) != len(expected):
        _fail(f"{name} drifted: expected {len(expected)} components, got {actual!r}")
    actual_values = [_canonical_float32(value, f"{name}[{index}]") for index, value in enumerate(actual)]
    expected_values = [_canonical_float32(value, f"{name} expected[{index}]") for index, value in enumerate(expected)]
    if actual_values != expected_values:
        _fail(f"{name} drifted at exact Float32 precision: expected {expected_values!r}, got {actual_values!r}")


def _validate_source_surface_facing(manifest: dict[str, Any], frozen_camera: list[Any]) -> dict[str, Any]:
    evidence = manifest.get("source_surface_facing")
    if not isinstance(evidence, dict):
        _fail("witness is missing source_surface_facing measurement")
    if evidence.get("owner_id") != MAISON_DU_ROI_OWNER_ID:
        _fail("source_surface_facing must measure exact Maison du Roi owner 1654360")
    _exact_float32_sequence("source_surface_facing camera_position", evidence.get("camera_position"), frozen_camera)
    if evidence.get("source_geometry_changed") is not False or evidence.get("source_collision_changed") is not False:
        _fail("source-facing measurement must not mutate source geometry or collision")
    for key in ("wall_triangles", "roof_triangles", "front_facing_wall_triangles", "front_facing_roof_triangles"):
        value = evidence.get(key)
        if isinstance(value, bool) or not isinstance(value, int) or value < 0:
            _fail(f"{key} must be a non-negative integer")
    if evidence["wall_triangles"] <= 0 or evidence["roof_triangles"] <= 0:
        _fail("source-facing measurement must include wall and roof triangles")
    if evidence["front_facing_wall_triangles"] > evidence["wall_triangles"] or evidence["front_facing_roof_triangles"] > evidence["roof_triangles"]:
        _fail("front-facing triangle count exceeds total")
    for key in ("wall_area_m2", "roof_area_m2", "front_facing_wall_area_m2", "front_facing_roof_area_m2"):
        value = _finite_number(evidence.get(key), key)
        if value < 0.0:
            _fail(f"{key} must be non-negative")
    if evidence["wall_area_m2"] <= 0.0 or evidence["roof_area_m2"] <= 0.0:
        _fail("source-facing measurement must include positive wall and roof area")
    if evidence["front_facing_wall_area_m2"] > evidence["wall_area_m2"] + 1e-9 or evidence["front_facing_roof_area_m2"] > evidence["roof_area_m2"] + 1e-9:
        _fail("front-facing area exceeds total source area")
    for key in ("front_facing_wall_area_ratio", "front_facing_roof_area_ratio"):
        ratio = _finite_number(evidence.get(key), key)
        if ratio < 0.0 or ratio > 1.0:
            _fail(f"{key} must be within [0,1]")
    expected_wall_ratio = evidence["front_facing_wall_area_m2"] / evidence["wall_area_m2"]
    expected_roof_ratio = evidence["front_facing_roof_area_m2"] / evidence["roof_area_m2"]
    if not math.isclose(evidence["front_facing_wall_area_ratio"], expected_wall_ratio, rel_tol=0.0, abs_tol=1e-9):
        _fail("front-facing wall area ratio is inconsistent with measured areas")
    if not math.isclose(evidence["front_facing_roof_area_ratio"], expected_roof_ratio, rel_tol=0.0, abs_tol=1e-9):
        _fail("front-facing roof area ratio is inconsistent with measured areas")
    for key in ("dominant_front_wall_normal", "dominant_front_roof_normal"):
        vec = evidence.get(key)
        if not isinstance(vec, list) or len(vec) != 3:
            _fail(f"{key} must be a 3-vector")
        for component in vec:
            _finite_number(component, key)
    return evidence


def validate_evidence(gate_path: Path | str, manifest_path: Path | str, artifact_root: Path | str | None = None) -> dict[str, Any]:
    gate_path = Path(gate_path)
    manifest_path = Path(manifest_path)
    gate = _load_json(gate_path)
    manifest = _load_json(manifest_path)
    contract = gate.get("evidence_contract")
    if not isinstance(contract, dict):
        _fail("gate is missing evidence_contract")
    integration_floor_sha = gate.get("integration_floor_sha")
    if not isinstance(integration_floor_sha, str) or SHA40.fullmatch(integration_floor_sha) is None:
        _fail("integration_floor_sha must be a lowercase 40-hex commit SHA")
    if "production_base_sha" in gate:
        _fail("legacy production_base_sha is forbidden; use immutable integration_floor_sha")
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
    live_main_sha = os.environ.get("GB_LIVE_MAIN_SHA")
    if live_main_sha is not None:
        if SHA40.fullmatch(live_main_sha) is None:
            _fail("GB_LIVE_MAIN_SHA must be a lowercase 40-hex commit SHA")
        if base_sha != live_main_sha:
            _fail("witness base_sha does not match exact live main")
    expected_head_sha = os.environ.get("GB_EVIDENCE_HEAD_SHA")
    if expected_head_sha is not None:
        if SHA40.fullmatch(expected_head_sha) is None:
            _fail("GB_EVIDENCE_HEAD_SHA must be a lowercase 40-hex commit SHA")
        if head_sha != expected_head_sha:
            _fail("witness head_sha does not match exact candidate head")
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
    source_surface_facing = _validate_source_surface_facing(manifest, gate.get("camera_position"))
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
    validated_hashes = []
    seen_files = set()
    seen_digests: dict[str, str] = {}
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
        try:
            digest = hashlib.sha256(png.read_bytes()).hexdigest()
        except OSError as exc:
            _fail(f"cannot hash witness PNG {png}: {exc}")
        previous = seen_digests.get(digest)
        if previous is not None:
            _fail(f"multiple required views contain identical PNG bytes: {previous} and {png.name}")
        seen_digests[digest] = png.name
        validated_hashes.append(digest)
        validated_files.append(str(png))
    if contract.get("generic_photo_match_artifact_is_sufficient") is not False:
        _fail("gate must explicitly reject generic Photo Match as sufficient evidence")
    if contract.get("human_full_frame_inspection_required") is not True:
        _fail("gate must explicitly require human full-frame inspection")
    if contract.get("numeric_gate_alone_is_sufficient") is not False:
        _fail("gate must explicitly reject numeric-only authorization")
    return {"artifact_kind":manifest["artifact_kind"],"base_sha":base_sha,"head_sha":head_sha,"integration_floor_sha":integration_floor_sha,"resolution":list(expected_dims),"view_count":len(validated_files),"view_ids":view_ids,"files":validated_files,"png_sha256":validated_hashes,"source_surface_facing":source_surface_facing,"human_review_status":"pending","visual_approval_claimed":False}


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
    facing = result["source_surface_facing"]
    print("GRAND_PLACE_FACADE_EVIDENCE_STRUCTURALLY_VALID " f"views={result['view_count']} resolution={result['resolution'][0]}x{result['resolution'][1]} " f"distinct_png_bytes={len(result['png_sha256'])} " f"maison_du_roi_front_wall_ratio={facing['front_facing_wall_area_ratio']:.6f} " f"maison_du_roi_front_roof_ratio={facing['front_facing_roof_area_ratio']:.6f} " "human_review=pending visual_approval_claimed=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

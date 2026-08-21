#!/usr/bin/env python3
"""Build a compact, deterministic QA-only terrain runtime candidate for one cell.

The heightfield is sampled from the already validated official DTM at canonical
Lambert cell-edge vertices. Heights are centimetre-quantized into uint16, zlib
compressed and base64 encoded so CityGen can persist regional candidates without
committing ~600 kB of decimal JSON per 2 m cell.

This is deliberately not a production authorization step.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import importlib.util
import json
import math
import zlib
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
_LOD_SPEC = importlib.util.spec_from_file_location("cell_dtm_lod", HERE / "evaluate_cell_dtm_lod.py")
lod_mod = importlib.util.module_from_spec(_LOD_SPEC)
assert _LOD_SPEC and _LOD_SPEC.loader
_LOD_SPEC.loader.exec_module(lod_mod)

FORMAT = "grand-bruxelles-cell-terrain-runtime-candidate-v1"
CRS = "EPSG:31370"
QUANTIZATION_M = 0.01
CODEC = "zlib+base64"
DTYPE = "uint16_le"


def _read(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _digest(value: Any) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _require_sha256(name: str, value: Any) -> str:
    if not isinstance(value, str) or len(value) != 64 or any(ch not in "0123456789abcdef" for ch in value.lower()):
        raise ValueError(f"{name} must be a sha256 hex digest")
    return value.lower()


def _selected_level(lod: dict[str, Any]) -> tuple[float, dict[str, Any]]:
    selection = lod.get("selection")
    if not isinstance(selection, dict):
        raise ValueError("terrain LOD selection missing")
    if selection.get("canonical_edge_alignment_required") is not True:
        raise ValueError("terrain LOD does not require canonical edge alignment")
    raw_resolution = selection.get("selected_resolution_m")
    if raw_resolution is None:
        raise ValueError("terrain LOD has no selected resolution")
    resolution = float(raw_resolution)
    matches = [
        row for row in (lod.get("levels") or [])
        if isinstance(row, dict) and math.isclose(float(row.get("resolution_m", -1.0)), resolution, rel_tol=0.0, abs_tol=1e-9)
    ]
    if len(matches) != 1:
        raise ValueError("selected terrain LOD level is missing or ambiguous")
    level = matches[0]
    if level.get("canonical_edge_compatible") is not True:
        raise ValueError("selected terrain LOD level is not canonical-edge compatible")
    threshold = float(selection.get("p95_threshold_m", math.nan))
    p95 = float(level.get("p95_abs_error_m", math.nan))
    if not math.isfinite(threshold) or not math.isfinite(p95) or p95 > threshold:
        raise ValueError("selected terrain LOD level does not satisfy vertical error policy")
    return resolution, level


def _vertex_grid(array: Any, transform: Any, bbox: tuple[float, float, float, float], resolution: float) -> Any:
    import numpy as np

    if not lod_mod._canonical_edge_compatible(bbox, resolution):
        raise ValueError("terrain runtime grid cannot land exactly on canonical cell edges")
    west, south, east, north = bbox
    x_steps = int(round((east - west) / resolution))
    y_steps = int(round((north - south) / resolution))
    xs = west + np.arange(x_steps + 1, dtype=np.float64) * resolution
    ys = south + np.arange(y_steps + 1, dtype=np.float64) * resolution
    xx, yy = np.meshgrid(xs, ys, indexing="xy")
    sampled = lod_mod.bilinear_sample(array, transform, xx.reshape(-1), yy.reshape(-1)).reshape(y_steps + 1, x_steps + 1)
    if not np.all(np.isfinite(sampled)):
        missing = int(np.size(sampled) - np.count_nonzero(np.isfinite(sampled)))
        raise ValueError(f"official DTM cannot populate canonical terrain edge grid; nonfinite_samples={missing}")
    return np.asarray(sampled, dtype=np.float64)


def _encode_heightfield(grid: Any) -> tuple[dict[str, Any], Any]:
    import numpy as np

    minimum = float(np.min(grid))
    # Decimal rounding of the base makes the representation reproducible and
    # keeps every uint16 value non-negative despite floating-point noise.
    offset = math.floor(minimum / QUANTIZATION_M) * QUANTIZATION_M
    units = np.rint((grid - offset) / QUANTIZATION_M)
    if float(np.min(units)) < 0.0 or float(np.max(units)) > 65535.0:
        raise ValueError("terrain vertical range exceeds uint16 centimetre encoding")
    quantized = units.astype("<u2")
    reconstructed = offset + quantized.astype(np.float64) * QUANTIZATION_M
    max_error = float(np.max(np.abs(reconstructed - grid)))
    if max_error > QUANTIZATION_M * 0.500001:
        raise ValueError("terrain quantization error exceeded half-step bound")
    raw = quantized.tobytes(order="C")
    compressed = zlib.compress(raw, level=9)
    payload = base64.b64encode(compressed).decode("ascii")
    encoding = {
        "codec": CODEC,
        "dtype": DTYPE,
        "quantization_m": QUANTIZATION_M,
        "offset_m": round(offset, 6),
        "uncompressed_bytes": len(raw),
        "compressed_bytes": len(compressed),
        "raw_sha256": hashlib.sha256(raw).hexdigest(),
        "compressed_sha256": hashlib.sha256(compressed).hexdigest(),
        "payload_base64": payload,
        "max_quantization_error_m": round(max_error, 6),
    }
    return encoding, reconstructed


def decode_heightfield(candidate: dict[str, Any]) -> Any:
    import numpy as np

    encoding = candidate.get("height_encoding")
    shape = candidate.get("shape")
    if not isinstance(encoding, dict) or not isinstance(shape, list) or len(shape) != 2:
        raise ValueError("terrain candidate encoding or shape missing")
    if encoding.get("codec") != CODEC or encoding.get("dtype") != DTYPE:
        raise ValueError("unsupported terrain height encoding")
    compressed = base64.b64decode(str(encoding.get("payload_base64", "")), validate=True)
    if hashlib.sha256(compressed).hexdigest() != encoding.get("compressed_sha256"):
        raise ValueError("terrain compressed payload digest mismatch")
    raw = zlib.decompress(compressed)
    if len(raw) != int(encoding.get("uncompressed_bytes", -1)):
        raise ValueError("terrain uncompressed payload length mismatch")
    if hashlib.sha256(raw).hexdigest() != encoding.get("raw_sha256"):
        raise ValueError("terrain raw payload digest mismatch")
    units = np.frombuffer(raw, dtype="<u2")
    expected = int(shape[0]) * int(shape[1])
    if units.size != expected:
        raise ValueError("terrain payload sample count mismatch")
    return float(encoding["offset_m"]) + units.astype(np.float64).reshape(int(shape[0]), int(shape[1])) * float(encoding["quantization_m"])


def build_from_array(
    cell_id: str,
    bbox: tuple[float, float, float, float],
    array: Any,
    transform: Any,
    lod: dict[str, Any],
    raster_validation_digest: str,
) -> dict[str, Any]:
    resolution, selected_level = _selected_level(lod)
    if lod.get("cell_id") != cell_id or lod.get("crs") != CRS:
        raise ValueError("terrain LOD identity or CRS mismatch")
    lod_digest = _require_sha256("terrain LOD evidence digest", lod.get("evidence_digest"))
    raster_digest = _require_sha256("raster validation digest", raster_validation_digest)
    lod_bbox = lod.get("bbox")
    if not isinstance(lod_bbox, list) or len(lod_bbox) != 4 or any(abs(float(a) - float(b)) > 1e-6 for a, b in zip(lod_bbox, bbox)):
        raise ValueError("terrain LOD bbox mismatch")

    grid = _vertex_grid(array, transform, bbox, resolution)
    encoding, reconstructed = _encode_heightfield(grid)
    height, width = grid.shape
    result = {
        "format": FORMAT,
        "cell_id": cell_id,
        "crs": CRS,
        "bbox_epsg31370": [float(v) for v in bbox],
        "spacing_m": resolution,
        "shape": [int(height), int(width)],
        "sample_count": int(height * width),
        "topology": {
            "includes_all_four_canonical_cell_edges": True,
            "columns_increase_easting": True,
            "rows_increase_northing": True,
            "godot_world_z_decreases_with_northing": True,
            "shared_edge_coordinates_are_exact": True,
        },
        "source": {
            "kind": "official_validated_DTM",
            "terrain_lod_evidence_digest": lod_digest,
            "raster_validation_digest": raster_digest,
            "selected_level_p95_abs_error_m": selected_level.get("p95_abs_error_m"),
            "selected_level_vertex_error_evaluated": True,
        },
        "height_encoding": encoding,
        "decoded_height_min_m": round(float(reconstructed.min()), 6),
        "decoded_height_max_m": round(float(reconstructed.max()), 6),
        "authorization": {
            "candidate_only": True,
            "terrain_runtime_authorized": False,
            "collision_authorized": False,
            "runtime_mount_authorized": False,
            "jouable_promotion_authorized": False,
        },
        "status": "qa_terrain_runtime_candidate_pending_measured_gates",
    }
    digest_view = json.loads(json.dumps(result))
    digest_view["height_encoding"].pop("payload_base64", None)
    # Digest both metadata and the compressed payload hash without rehashing a
    # huge base64 string into semantically different evidence.
    result["candidate_digest"] = _digest(digest_view)
    return result


def build(raster_validation_path: Path, terrain_lod_path: Path, extract_root: Path) -> dict[str, Any]:
    validation = _read(raster_validation_path)
    lod = _read(terrain_lod_path)
    if validation.get("format") != lod_mod.RASTER_FORMAT or validation.get("crs") != CRS:
        raise ValueError("unsupported elevation raster validation")
    cell_id = validation.get("cell_id")
    if not isinstance(cell_id, str) or lod.get("cell_id") != cell_id:
        raise ValueError("terrain candidate cell identity mismatch")
    bbox_raw = validation.get("bbox")
    if not isinstance(bbox_raw, list) or len(bbox_raw) != 4:
        raise ValueError("terrain candidate requires canonical cell bbox")
    bbox = tuple(float(v) for v in bbox_raw)
    array, transform = lod_mod._open_dtm_mosaic(lod_mod._find_dtm_sources(validation, extract_root))
    return build_from_array(
        cell_id,
        bbox,
        array,
        transform,
        lod,
        _require_sha256("raster validation digest", validation.get("validation_digest")),
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--raster-validation", type=Path, required=True)
    parser.add_argument("--terrain-lod", type=Path, required=True)
    parser.add_argument("--extract-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = build(args.raster_validation, args.terrain_lod, args.extract_root)
    except Exception as exc:
        print(f"TERRAIN_RUNTIME_CANDIDATE_ERROR: {exc}")
        return 1
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    ratio = result["height_encoding"]["compressed_bytes"] / max(result["height_encoding"]["uncompressed_bytes"], 1)
    print(
        "TERRAIN_RUNTIME_CANDIDATE_OK "
        f"cell={result['cell_id']} spacing={result['spacing_m']} samples={result['sample_count']} "
        f"compression_ratio={ratio:.3f} runtime_authorized=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

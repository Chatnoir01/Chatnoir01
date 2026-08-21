#!/usr/bin/env python3
from __future__ import annotations

import base64
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("terrain_candidate", HERE / "build_cell_terrain_runtime_candidate.py")
mod = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(mod)

try:
    import numpy as np
    from affine import Affine
except ImportError:
    raise SystemExit("numpy/affine missing in runner")

CELL = "bxl-e149000-n169000-s500"
BBOX = (149000.0, 169000.0, 149010.0, 169010.0)
# One-metre source with one-pixel padding around the test cell so exact edge
# vertices remain bilinearly sampleable.
transform = Affine(1.0, 0.0, BBOX[0] - 1.0, 0.0, -1.0, BBOX[3] + 1.0)
rows, cols = np.mgrid[0:13, 0:13]
source = 62.0 + 0.17 * cols + 0.11 * rows + 0.03 * np.sin(cols / 2.0)

lod = {
    "format": mod.lod_mod.FORMAT,
    "cell_id": CELL,
    "crs": mod.CRS,
    "bbox": list(BBOX),
    "levels": [
        {
            "resolution_m": 2.0,
            "p95_abs_error_m": 0.08,
            "canonical_edge_compatible": True,
        }
    ],
    "selection": {
        "p95_threshold_m": 0.15,
        "canonical_edge_alignment_required": True,
        "selected_resolution_m": 2.0,
    },
    "runtime_approved": False,
    "evidence_digest": "a" * 64,
}

first = mod.build_from_array(CELL, BBOX, source.astype("float64"), transform, lod, "b" * 64)
second = mod.build_from_array(CELL, BBOX, source.astype("float64"), transform, lod, "b" * 64)
assert first == second
assert first["format"] == mod.FORMAT
assert first["shape"] == [6, 6]
assert first["sample_count"] == 36
assert first["spacing_m"] == 2.0
assert first["topology"]["includes_all_four_canonical_cell_edges"] is True
assert first["topology"]["shared_edge_coordinates_are_exact"] is True
assert first["height_encoding"]["dtype"] == "uint16_le"
assert first["height_encoding"]["codec"] == "zlib+base64"
assert first["height_encoding"]["max_quantization_error_m"] <= 0.005001
assert len(first["candidate_digest"]) == 64
assert first["authorization"] == {
    "candidate_only": True,
    "terrain_runtime_authorized": False,
    "collision_authorized": False,
    "runtime_mount_authorized": False,
    "jouable_promotion_authorized": False,
}

decoded = mod.decode_heightfield(first)
assert decoded.shape == (6, 6)
expected = mod._vertex_grid(source.astype("float64"), transform, BBOX, 2.0)
assert float(np.max(np.abs(decoded - expected))) <= 0.005001

# Payload integrity is checked independently of the metadata candidate digest.
tampered = json.loads(json.dumps(first))
raw = bytearray(base64.b64decode(tampered["height_encoding"]["payload_base64"]))
raw[-1] ^= 1
tampered["height_encoding"]["payload_base64"] = base64.b64encode(bytes(raw)).decode("ascii")
try:
    mod.decode_heightfield(tampered)
except ValueError as exc:
    assert "compressed payload digest mismatch" in str(exc)
else:
    raise AssertionError("tampered compressed terrain payload must fail closed")

# A selected level that cannot land exactly on both canonical edges is blocked
# even if its p95 vertical error would otherwise be excellent.
misaligned = json.loads(json.dumps(lod))
misaligned["levels"] = [{"resolution_m": 3.0, "p95_abs_error_m": 0.01, "canonical_edge_compatible": False}]
misaligned["selection"]["selected_resolution_m"] = 3.0
try:
    mod.build_from_array(CELL, BBOX, source.astype("float64"), transform, misaligned, "b" * 64)
except ValueError as exc:
    assert "canonical-edge compatible" in str(exc)
else:
    raise AssertionError("misaligned terrain LOD must fail closed")

print(
    "TERRAIN_RUNTIME_CANDIDATE_OK deterministic=true compact_uint16=true canonical_edges=true "
    "payload_integrity=true runtime_authorized=false"
)

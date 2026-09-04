#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
runtime_path = ROOT / "game" / "scripts" / "automatic_road_direct_spawn.gd"
source = runtime_path.read_text(encoding="utf-8")

# Source-backed automatic destinations must not coerce JSON strings/bools into
# geometry. Keep the OSM-id boundary and the coordinate boundary equally strict.
assert "func _exact_source_point_2d(raw: Variant) -> Variant:" in source, (
    "automatic road resolver is missing a strict source-point boundary"
)
assert "raw_type != TYPE_INT and raw_type != TYPE_FLOAT" in source, (
    "source-point boundary must accept only explicit JSON numeric primitives"
)
assert "not is_finite(numeric)" in source, (
    "source-point boundary must reject NaN/Inf before geometry use"
)
assert "Vector2(float(raw[0]), float(raw[1]))" not in source, (
    "road points still use permissive float() coercion"
)

print("AUTOMATIC_ROAD_SOURCE_POINT_BOUNDARY_CONTRACT_GREEN")

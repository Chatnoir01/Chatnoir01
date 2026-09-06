#!/usr/bin/env python3
"""Fail closed if reused shared OSM MultiMesh batches can retain a stale presentation mesh."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "game" / "scripts" / "brussels_osm_environment_runtime.gd"
source = RUNTIME.read_text(encoding="utf-8")

batch = source[source.index("func _batch("):source.index("func _ensure_tree_presentation_meshes")]
assert "if instance != null:" in batch, "reuse path must remain explicit"
assert "multimesh = instance.multimesh" in batch, "existing MultiMesh must be reused when safe"

# The binding must be on the common path, not only nested under `if multimesh == null:`.
# Requiring the exact common-path sequence fails the historical implementation where
# `multimesh.mesh = mesh` was indented inside allocation-only setup.
common_bind = "\n    multimesh.mesh = mesh\n    multimesh.instance_count = transforms.size()"
assert common_bind in batch, (
    "current presentation mesh must be rebound on both new and reused MultiMesh batches before instance refresh"
)

print("OSM_ENVIRONMENT_REUSED_BATCH_MESH_REFRESH_CONTRACT_GREEN")

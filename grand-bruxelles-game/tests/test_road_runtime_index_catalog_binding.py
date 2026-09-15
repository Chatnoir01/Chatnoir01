#!/usr/bin/env python3
"""RED witness: runtime-index contract must bind catalog identity to source descriptors."""
from __future__ import annotations

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "build_road_runtime_index.py"
spec = importlib.util.spec_from_file_location("road_runtime_index", SCRIPT)
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

# A structurally valid index can currently claim an arbitrary catalog digest while
# retaining the same source-document descriptors. This must fail closed: the digest
# is the deterministic binding to the locked generated catalog, not free metadata.
index = {
    "authorization": dict(module.AUTHORIZATION),
    "catalog_sha256": "0" * 64,
    "documents": [{"path": "data/osm/witness.game.json", "road_ids": [1], "sha256": "1" * 64}],
    "format": module.FORMAT,
    "source_lookup_only": True,
}

try:
    module.validate_contract(index)
except SystemExit:
    print("ROAD_RUNTIME_INDEX_CATALOG_BINDING_OK")
else:
    raise SystemExit(
        "ROAD_RUNTIME_INDEX_CATALOG_BINDING_FAIL: validate_contract accepted an unbound catalog_sha256"
    )

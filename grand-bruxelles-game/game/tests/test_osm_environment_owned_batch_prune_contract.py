#!/usr/bin/env python3
"""Fail closed if shared OSM environment batch ownership can retain dead or detached MultiMesh refs."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "game" / "scripts" / "brussels_osm_environment_runtime.gd"
source = RUNTIME.read_text(encoding="utf-8")

assert "func _prune_invalid_owned_batches() -> void:" in source
assert "if not is_instance_valid(batch) or batch.is_queued_for_deletion():" in source
assert "batch.get_parent() != self" in source, "detached/reparented batches must stop being owned by this runtime"
assert "_owned_batches.remove_at(index)" in source

prune = source[source.index("func _prune_invalid_owned_batches"):source.index("func _set_batches_visible")]
assert prune.index("batch.get_parent() != self") < prune.index("_owned_batches.remove_at(index)"), "parent ownership must be checked in the prune path"
assert (
    "if not is_instance_valid(batch) or batch.is_queued_for_deletion() or batch.get_parent() != self:" in prune
), "dead, queued, and detached ownership must be rejected by one fail-closed prune predicate"

set_visible = source[source.index("func _set_batches_visible"):source.index("func _tree_lod_boundary_crossed")]
assert "_prune_invalid_owned_batches()" in set_visible, "visibility pass must prune dead or detached owned batches"

batch = source[source.index("func _batch("):source.index("func _ensure_tree_presentation_meshes")]
assert "_prune_invalid_owned_batches()" in batch, "reuse lookup must prune dead or detached owned batches before matching by name"
assert batch.index("_prune_invalid_owned_batches()") < batch.index("if reuse_existing:"), "prune must happen before reuse lookup"

print("OSM_ENVIRONMENT_OWNED_BATCH_PRUNE_CONTRACT_GREEN")

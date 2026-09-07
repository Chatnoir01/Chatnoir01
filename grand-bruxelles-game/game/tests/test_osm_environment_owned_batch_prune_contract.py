#!/usr/bin/env python3
"""Fail closed if shared OSM environment batch ownership can retain or destroy foreign MultiMesh refs."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "game" / "scripts" / "brussels_osm_environment_runtime.gd"
source = RUNTIME.read_text(encoding="utf-8")

assert "func _prune_invalid_owned_batches() -> void:" in source
assert "_owned_batches.remove_at(index)" in source

prune = source[source.index("func _prune_invalid_owned_batches"):source.index("func _set_batches_visible")]
assert "not is_instance_valid(batch)" in prune, "invalid batches must stop being owned"
assert "batch.is_queued_for_deletion()" in prune, "queued batches must stop being owned"
assert "batch.get_parent() != self" in prune, "detached/reparented batches must stop being owned by this runtime"
assert prune.index("batch.get_parent() != self") < prune.index("_owned_batches.remove_at(index)"), "parent ownership must be checked in the prune path"
assert (
    "if not is_instance_valid(batch) or batch.is_queued_for_deletion() or batch.get_parent() != self:" in prune
), "dead, queued, and detached ownership must be rejected by one fail-closed prune predicate"

set_visible = source[source.index("func _set_batches_visible"):source.index("func _tree_lod_boundary_crossed")]
assert "_prune_invalid_owned_batches()" in set_visible, "visibility pass must prune dead or detached owned batches"

foliage_clear = source[source.index("func _clear_tree_foliage_batches() -> void:"):source.index("func _refresh_tree_lod")]
assert "if not is_instance_valid(batch):" in foliage_clear, "tree foliage teardown must reject invalid refs before classification"
assert "if batch.get_parent() != self:" in foliage_clear, "tree foliage teardown must reject foreign/reparented batches"
foliage_invalid_guard = foliage_clear.index("if not is_instance_valid(batch):")
foliage_guard = foliage_clear.index("if batch.get_parent() != self:")
foliage_queue_free = foliage_clear.index("batch.queue_free()")
assert foliage_invalid_guard < foliage_queue_free, "invalid ownership must be rejected before destructive foliage teardown"
assert foliage_guard < foliage_queue_free, "tree foliage ownership guard must run before queue_free"
assert "_owned_batches.remove_at(index)" in foliage_clear[foliage_guard:foliage_queue_free], "foreign foliage refs must be dropped from local ownership before destructive work"
assert "continue" in foliage_clear[foliage_guard:foliage_queue_free], "foreign foliage batches must be skipped rather than freed"
assert 'batch.get_meta("osm_environment_batch_role", "")' in foliage_clear, "foliage teardown must classify owned batches by immutable runtime role metadata rather than mutable node names"
assert 'batch.name.begins_with("TreeFoliage")' not in foliage_clear, "mutable node names must not decide whether an owned foliage batch is cleared"

batch = source[source.index("func _batch("):source.index("func _ensure_tree_presentation_meshes")]
assert "_prune_invalid_owned_batches()" in batch, "reuse lookup must prune dead or detached owned batches before matching by name"
assert batch.index("_prune_invalid_owned_batches()") < batch.index("if reuse_existing:"), "prune must happen before reuse lookup"
assert 'instance.set_meta("osm_environment_batch_role", name_value)' in batch, "every created/reused batch must retain a stable runtime role independent of mutable node name"

clear = source[source.index("func _clear_owned_batches() -> void:"):source.index("func _rebuild(")]
assert "if batch.get_parent() != self:" in clear, "teardown must reject foreign/reparented batches before destructive operations"
assert "continue" in clear[clear.index("if batch.get_parent() != self:"):], "foreign batches must be skipped rather than freed"
foreign_guard = clear.index("if batch.get_parent() != self:")
queue_free = clear.index("batch.queue_free()")
assert foreign_guard < queue_free, "foreign ownership guard must run before queue_free"

print("OSM_ENVIRONMENT_OWNED_BATCH_PRUNE_CONTRACT_GREEN")
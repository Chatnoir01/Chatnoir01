from pathlib import Path

runtime = Path("grand-bruxelles-game/game/scripts/brussels_osm_environment_runtime.gd")
source = runtime.read_text(encoding="utf-8")

old_refresh = '''func _refresh_tree_lod(anchor: Vector3) -> void:\n    _clear_tree_foliage_batches()\n    _build_tree_foliage_batches(_rendered_trees, anchor)\n    _last_tree_lod_anchor = anchor\n'''
new_refresh = '''func _refresh_tree_lod(anchor: Vector3) -> void:\n    _build_tree_foliage_batches(_rendered_trees, anchor, true)\n    _last_tree_lod_anchor = anchor\n'''
assert source.count(old_refresh) == 1, "refresh block drifted"
source = source.replace(old_refresh, new_refresh, 1)

old_batch = '''func _batch(name_value: String, mesh: Mesh, transforms: Array) -> void:\n    if transforms.is_empty():\n        return\n    var multimesh := MultiMesh.new()\n    multimesh.transform_format = MultiMesh.TRANSFORM_3D\n    multimesh.mesh = mesh\n    multimesh.instance_count = transforms.size()\n    for index in range(transforms.size()):\n        multimesh.set_instance_transform(index, transforms[index] as Transform3D)\n    var instance := MultiMeshInstance3D.new()\n    instance.name = name_value\n    instance.multimesh = multimesh\n    instance.set_meta("source_dimensions_measured", false)\n    instance.visible = _batches_visible\n    add_child(instance)\n    _owned_batches.append(instance)\n'''
new_batch = '''func _batch(name_value: String, mesh: Mesh, transforms: Array, reuse_existing: bool = false) -> void:\n    var instance: MultiMeshInstance3D = null\n    if reuse_existing:\n        for owned: MultiMeshInstance3D in _owned_batches:\n            if is_instance_valid(owned) and not owned.is_queued_for_deletion() and owned.name == name_value:\n                instance = owned\n                break\n    if transforms.is_empty() and instance == null:\n        return\n    var multimesh: MultiMesh = null\n    if instance != null:\n        multimesh = instance.multimesh\n    if multimesh == null:\n        multimesh = MultiMesh.new()\n        multimesh.transform_format = MultiMesh.TRANSFORM_3D\n        multimesh.mesh = mesh\n    multimesh.instance_count = transforms.size()\n    for index in range(transforms.size()):\n        multimesh.set_instance_transform(index, transforms[index] as Transform3D)\n    if instance == null:\n        instance = MultiMeshInstance3D.new()\n        instance.name = name_value\n        instance.set_meta("source_dimensions_measured", false)\n        add_child(instance)\n        _owned_batches.append(instance)\n    instance.multimesh = multimesh\n    instance.visible = _batches_visible\n'''
assert source.count(old_batch) == 1, "batch block drifted"
source = source.replace(old_batch, new_batch, 1)

old_signature = 'func _build_tree_foliage_batches(rows: Array, anchor: Vector3 = Vector3(INF, INF, INF)) -> void:'
new_signature = 'func _build_tree_foliage_batches(rows: Array, anchor: Vector3 = Vector3(INF, INF, INF), reuse_existing: bool = false) -> void:'
assert source.count(old_signature) == 1, "foliage signature drifted"
source = source.replace(old_signature, new_signature, 1)

old_calls = '''    _batch("TreeFoliageDark", _presentation_meshes["tree_foliage_dark"] as Mesh, dark)\n    _batch("TreeFoliageLight", _presentation_meshes["tree_foliage_light"] as Mesh, light)'''
new_calls = '''    _batch("TreeFoliageDark", _presentation_meshes["tree_foliage_dark"] as Mesh, dark, reuse_existing)\n    _batch("TreeFoliageLight", _presentation_meshes["tree_foliage_light"] as Mesh, light, reuse_existing)'''
assert source.count(old_calls) == 1, "foliage batch calls drifted"
source = source.replace(old_calls, new_calls, 1)

runtime.write_text(source, encoding="utf-8")
print("TREE_FOLIAGE_MULTIMESH_REUSE_PATCH_APPLIED")

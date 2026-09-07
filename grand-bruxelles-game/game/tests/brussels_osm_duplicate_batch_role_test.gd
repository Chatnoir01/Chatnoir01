extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/brussels_osm_environment_runtime.gd")
const BATCH_ROLE_META := "osm_environment_batch_role"
const ROLE := "TreeTrunks"

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_DUPLICATE_BATCH_ROLE_FAIL: %s" % message)
    quit(1)

func _initialize() -> void:
    call_deferred("_run")

func _new_batch(name: String, role: String) -> MultiMeshInstance3D:
    var batch := MultiMeshInstance3D.new()
    batch.name = name
    batch.set_meta(BATCH_ROLE_META, role)
    return batch

func _run() -> void:
    var runtime := RUNTIME_SCRIPT.new() as Node3D
    runtime.name = "BrusselsOsmDuplicateBatchRoleProbe"
    var owned := runtime.get("_owned_batches") as Array

    var canonical := _new_batch("TreeTrunksCanonical", ROLE)
    runtime.add_child(canonical)
    owned.append(canonical)

    var duplicate := _new_batch("TreeTrunksDuplicate", ROLE)
    runtime.add_child(duplicate)
    owned.append(duplicate)

    var foreign_parent := Node3D.new()
    var foreign := _new_batch("TreeTrunksForeign", ROLE)
    foreign_parent.add_child(foreign)
    owned.append(foreign)

    runtime.call("_batch", ROLE, BoxMesh.new(), [], true)

    if canonical.is_queued_for_deletion():
        _fail("first same-role locally-owned batch did not retain canonical identity")
        return
    if canonical.multimesh == null:
        _fail("canonical same-role batch was not reused by the live _batch API")
        return
    if not duplicate.is_queued_for_deletion():
        _fail("additional same-role locally-owned batch survived canonicalization")
        return
    if foreign.is_queued_for_deletion():
        _fail("reparented same-role batch owned elsewhere was scheduled for deletion")
        return

    owned = runtime.get("_owned_batches") as Array
    if canonical not in owned:
        _fail("canonical batch was removed from runtime ownership")
        return
    if duplicate in owned:
        _fail("duplicate same-role batch remained in runtime ownership")
        return
    if foreign in owned:
        _fail("reparented batch remained in stale runtime ownership")
        return

    print("BRUSSELS_OSM_DUPLICATE_BATCH_ROLE_OK: canonical_identity_preserved=true duplicate_pruned=true foreign_owner_preserved=true")
    runtime.free()
    foreign_parent.free()
    quit(0)

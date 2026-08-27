extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/ixelles_midi_sidewalk_runtime.gd")
const AUTOLOAD_NAME := &"IxellesMidiSidewalkRuntime"
const MATERIAL_OWNER := "ixelles_midi_sidewalk_runtime"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("IXELLES_MIDI_SIDEWALK_DEFERRED_TEARDOWN_FAIL: %s" % message)
    quit(1)

func _build_target_fixture() -> Dictionary:
    var slice_root := Node3D.new()
    slice_root.name = "IxellesDirectMicroSlice"
    root.add_child(slice_root)
    var parent := Node3D.new()
    parent.name = "OfficialIxellesStreetSurfaces"
    slice_root.add_child(parent)
    var target := MeshInstance3D.new()
    target.name = "StreetSurfaces_SW"
    target.mesh = QuadMesh.new()
    parent.add_child(target)
    return {"slice_root": slice_root, "parent": parent, "target": target}

func _new_runtime(label: String) -> Node:
    var runtime: Node = RUNTIME_SCRIPT.new()
    runtime.name = "IxellesMidiSidewalkRuntimeUnderTest_%s" % label
    root.add_child(runtime)
    return runtime

func _run() -> void:
    # The project autoload is active even when a SceneTree test instantiates a
    # second copy. Remove it so only the instance under test owns callbacks.
    var canonical_runtime: Node = root.get_node_or_null(str(AUTOLOAD_NAME))
    if canonical_runtime != null:
        root.remove_child(canonical_runtime)
        canonical_runtime.free()
        await process_frame

    # Case 1: runtime teardown must suppress a candidate already queued by
    # node_added before MessageQueue executes it.
    var runtime := _new_runtime("teardown")
    await process_frame
    var teardown_fixture := _build_target_fixture()
    var target := teardown_fixture["target"] as MeshInstance3D

    root.remove_child(runtime)
    await process_frame
    await process_frame

    if target.material_override != null:
        _fail("deferred candidate mutated target material after runtime teardown")
        return
    if target.has_meta("shared_sidewalk_material_owner") and str(target.get_meta("shared_sidewalk_material_owner")) == MATERIAL_OWNER:
        _fail("deferred candidate claimed target ownership after runtime teardown")
        return
    if bool(runtime.call("ready_complete")):
        _fail("runtime became ready after leaving SceneTree")
        return

    runtime.free()
    var teardown_root := teardown_fixture["slice_root"] as Node3D
    teardown_root.queue_free()
    await process_frame

    # Case 2: keep the runtime alive, queue a valid LABO target, then free that
    # target before the deferred callback executes. Production must carry only
    # the instance ID, validate it at execution time, and return silently.
    var freed_runtime := _new_runtime("freed_candidate")
    await process_frame
    var freed_fixture := _build_target_fixture()
    var freed_parent := freed_fixture["parent"] as Node3D
    var freed_target := freed_fixture["target"] as MeshInstance3D
    var freed_target_id: int = freed_target.get_instance_id()

    # Remove every non-owning Variant reference before free(). The regression
    # must prove the deferred integer ID is harmless, not manufacture a stale
    # Object Variant in its own fixture that can trigger Godot's freed-object
    # diagnostics while the Dictionary is later destroyed.
    freed_fixture.erase("target")
    freed_parent.remove_child(freed_target)
    freed_target.free()
    freed_target = null

    if is_instance_id_valid(freed_target_id):
        _fail("freed target instance id remained valid before deferred execution")
        return

    await process_frame
    await process_frame

    if bool(freed_runtime.call("ready_complete")):
        _fail("runtime became ready from a candidate freed before deferred execution")
        return
    if int(freed_runtime.call("applied_surface_count")) != 0:
        _fail("freed candidate was counted as an applied surface")
        return

    root.remove_child(freed_runtime)
    freed_runtime.free()
    var freed_root := freed_fixture["slice_root"] as Node3D
    freed_root.queue_free()
    await process_frame

    print("IXELLES_MIDI_SIDEWALK_DEFERRED_TEARDOWN_OK: canonical_autoload_isolated=true teardown_material_unchanged=true teardown_owner_unchanged=true freed_candidate_id_invalid=true stale_variant_removed=true freed_candidate_safe=true ready=false")
    quit(0)

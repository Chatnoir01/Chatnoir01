extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/ixelles_midi_sidewalk_runtime.gd")
const AUTOLOAD_NAME := &"IxellesMidiSidewalkRuntime"
const MATERIAL_OWNER := "ixelles_midi_sidewalk_runtime"

class TestIxellesSlice:
    extends Node3D
    var runtime_loaded := false

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("IXELLES_MIDI_SIDEWALK_DEFERRED_TEARDOWN_FAIL: %s" % message)
    quit(1)

func _phase(name: String) -> void:
    print("IXELLES_MIDI_SIDEWALK_DEFERRED_TEARDOWN_PHASE: %s" % name)

func _build_target_fixture() -> Dictionary:
    # Match the real LABO slice contract closely enough that unrelated registry
    # bridges can inspect runtime_loaded without throwing while this regression
    # still keeps geography/content minimal and owned by the test.
    var slice_root := TestIxellesSlice.new()
    slice_root.name = "IxellesDirectMicroSlice"
    slice_root.runtime_loaded = false
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

func _dispatch_candidate(runtime: Node, instance_id: int) -> void:
    _phase("case2_dispatch_begin")
    if runtime == null or not is_instance_valid(runtime):
        _fail("runtime disappeared before isolated deferred ID dispatch")
        return
    runtime.call("_apply_candidate", instance_id)
    _phase("case2_dispatch_end")

func _run() -> void:
    _phase("isolate_canonical_autoload")
    var canonical_runtime: Node = root.get_node_or_null(str(AUTOLOAD_NAME))
    if canonical_runtime != null:
        root.remove_child(canonical_runtime)
        canonical_runtime.free()
        await process_frame

    _phase("case1_real_node_added_begin")
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
    _phase("case1_real_node_added_ok")

    _phase("case2_invalid_id_begin")
    var freed_runtime := _new_runtime("freed_candidate")
    await process_frame
    var runtime_node_added := Callable(freed_runtime, "_on_node_added")
    if node_added.is_connected(runtime_node_added):
        node_added.disconnect(runtime_node_added)

    var freed_fixture := _build_target_fixture()
    var freed_parent := freed_fixture["parent"] as Node3D
    var freed_target := freed_fixture["target"] as MeshInstance3D
    var freed_target_id: int = freed_target.get_instance_id()

    freed_fixture.erase("target")
    freed_parent.remove_child(freed_target)
    freed_target.free()
    freed_target = null

    if is_instance_id_valid(freed_target_id):
        _fail("freed target instance id remained valid before deferred execution")
        return
    _phase("case2_instance_id_invalid")

    call_deferred("_dispatch_candidate", freed_runtime, freed_target_id)
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
    _phase("case2_invalid_id_ok")

    print("IXELLES_MIDI_SIDEWALK_DEFERRED_TEARDOWN_OK: canonical_autoload_isolated=true real_node_added_teardown_safe=true isolated_deferred_id_dispatch=true freed_candidate_id_invalid=true freed_candidate_safe=true valid_slice_contract=true ready=false")
    quit(0)

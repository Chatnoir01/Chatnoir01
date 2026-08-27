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
    (teardown_fixture["slice_root"] as Node3D).queue_free()
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
    if bool(freed_runtime.call("ready_complete")) or int(freed_runtime.call("applied_surface_count")) != 0:
        _fail("freed candidate was applied after deferred dispatch")
        return
    root.remove_child(freed_runtime)
    freed_runtime.free()
    (freed_fixture["slice_root"] as Node3D).queue_free()
    await process_frame
    _phase("case2_invalid_id_ok")

    _phase("case3_material_restore_begin")
    var restore_fixture := _build_target_fixture()
    var restore_target := restore_fixture["target"] as MeshInstance3D
    var restore_legacy := StandardMaterial3D.new()
    restore_target.material_override = restore_legacy
    var restore_runtime := _new_runtime("material_restore")
    await process_frame
    await process_frame
    if not bool(restore_runtime.call("ready_complete")):
        _fail("runtime did not bind material restore fixture")
        return
    if restore_target.material_override == restore_legacy:
        _fail("runtime never acquired material ownership before teardown")
        return
    if not restore_target.has_meta("shared_sidewalk_material_owner") or str(restore_target.get_meta("shared_sidewalk_material_owner")) != MATERIAL_OWNER:
        _fail("runtime material ownership metadata missing before teardown")
        return
    root.remove_child(restore_runtime)
    if restore_target.material_override != restore_legacy:
        _fail("teardown did not restore exact legacy material")
        return
    if restore_target.has_meta("shared_sidewalk_material_owner") and str(restore_target.get_meta("shared_sidewalk_material_owner")) == MATERIAL_OWNER:
        _fail("teardown left Ixelles material ownership metadata behind")
        return
    if bool(restore_runtime.call("ready_complete")):
        _fail("teardown did not reset ready state after material release")
        return
    restore_runtime.free()
    (restore_fixture["slice_root"] as Node3D).queue_free()
    await process_frame
    _phase("case3_material_restore_ok")

    _phase("case4_later_owner_begin")
    var later_fixture := _build_target_fixture()
    var later_target := later_fixture["target"] as MeshInstance3D
    var later_legacy := StandardMaterial3D.new()
    later_target.material_override = later_legacy
    var later_runtime := _new_runtime("later_owner")
    await process_frame
    await process_frame
    if not bool(later_runtime.call("ready_complete")):
        _fail("runtime did not bind later-owner fixture")
        return
    var later_material := StandardMaterial3D.new()
    later_target.material_override = later_material
    later_target.set_meta("shared_sidewalk_material_owner", "later_owner")
    root.remove_child(later_runtime)
    if later_target.material_override != later_material:
        _fail("teardown overwrote a later material owner")
        return
    if str(later_target.get_meta("shared_sidewalk_material_owner", "")) != "later_owner":
        _fail("teardown removed later-owner metadata")
        return
    later_runtime.free()
    (later_fixture["slice_root"] as Node3D).queue_free()
    await process_frame
    _phase("case4_later_owner_ok")

    print("IXELLES_MIDI_SIDEWALK_DEFERRED_TEARDOWN_OK: canonical_autoload_isolated=true real_node_added_teardown_safe=true isolated_deferred_id_dispatch=true freed_candidate_id_invalid=true freed_candidate_safe=true material_legacy_restored=true later_owner_preserved=true valid_slice_contract=true ready=false")
    quit(0)

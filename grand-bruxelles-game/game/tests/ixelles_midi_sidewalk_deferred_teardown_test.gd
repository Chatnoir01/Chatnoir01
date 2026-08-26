extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/ixelles_midi_sidewalk_runtime.gd")
const AUTOLOAD_NAME := &"IxellesMidiSidewalkRuntime"
const MATERIAL_OWNER := "ixelles_midi_sidewalk_runtime"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("IXELLES_MIDI_SIDEWALK_DEFERRED_TEARDOWN_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    # The project autoload is active even when a SceneTree test instantiates a
    # second copy of the runtime. Remove the canonical instance first so this
    # regression measures only the deferred callbacks owned by the instance
    # under test instead of racing two legitimate material owners.
    var canonical_runtime: Node = root.get_node_or_null(str(AUTOLOAD_NAME))
    if canonical_runtime != null:
        root.remove_child(canonical_runtime)
        canonical_runtime.free()
        await process_frame

    var runtime: Node = RUNTIME_SCRIPT.new()
    runtime.name = "IxellesMidiSidewalkRuntimeUnderTest"
    root.add_child(runtime)
    await process_frame

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

    # node_added has queued the runtime's deferred candidate application.
    # Tear the runtime down before that deferred callback is allowed to run.
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

    print("IXELLES_MIDI_SIDEWALK_DEFERRED_TEARDOWN_OK: canonical_autoload_isolated=true material_unchanged=true owner_unchanged=true ready=false")
    runtime.free()
    slice_root.queue_free()
    await process_frame
    quit(0)

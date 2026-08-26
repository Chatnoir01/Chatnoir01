extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/ixelles_midi_sidewalk_runtime.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("IXELLES_MIDI_SIDEWALK_DEFERRED_TEARDOWN_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var runtime: Node = RUNTIME_SCRIPT.new()
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
    # Tear the autoload down before that deferred callback is allowed to run.
    root.remove_child(runtime)
    await process_frame
    await process_frame

    if target.material_override != null:
        _fail("deferred candidate mutated target after runtime teardown")
        return
    if bool(runtime.call("ready_complete")):
        _fail("runtime became ready after leaving SceneTree")
        return

    print("IXELLES_MIDI_SIDEWALK_DEFERRED_TEARDOWN_OK: material_unchanged=true ready=false")
    runtime.free()
    slice_root.queue_free()
    await process_frame
    quit(0)

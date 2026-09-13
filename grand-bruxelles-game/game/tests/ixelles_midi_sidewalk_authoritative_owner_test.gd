extends SceneTree

const SIDEWALK_RUNTIME := preload("res://game/scripts/ixelles_midi_sidewalk_runtime.gd")

var _failures: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    _failures.append(message)
    push_error(message)

func _assert_true(value: bool, message: String) -> void:
    if not value:
        _fail(message)

func _assert_false(value: bool, message: String) -> void:
    if value:
        _fail(message)

func _make_target_fixture() -> Dictionary:
    var slice_root := Node3D.new()
    slice_root.name = "IxellesDirectMicroSlice"
    var surfaces := Node3D.new()
    surfaces.name = "OfficialIxellesStreetSurfaces"
    slice_root.add_child(surfaces)
    var target := MeshInstance3D.new()
    target.name = "StreetSurfaces_SW"
    surfaces.add_child(target)
    return {"root": slice_root, "target": target}

func _run() -> void:
    var runtime := SIDEWALK_RUNTIME.new()
    runtime.name = "IxellesMidiSidewalkAuthorityWitness"
    root.add_child(runtime)
    await process_frame
    current_scene = null

    var root_fixture := _make_target_fixture()
    var root_decoy := root_fixture["root"] as Node3D
    var root_target := root_fixture["target"] as MeshInstance3D
    root.add_child(root_decoy)
    await process_frame
    _assert_false(runtime._is_valid_target(root_target), "root-level synthetic Ixelles slice must not be authoritative")
    root.remove_child(root_decoy)
    root_decoy.queue_free()
    await process_frame

    var viewport := SubViewport.new()
    viewport.name = "IxellesSidewalkAuthorityDecoyViewport"
    root.add_child(viewport)
    var viewport_fixture := _make_target_fixture()
    var viewport_decoy := viewport_fixture["root"] as Node3D
    var viewport_target := viewport_fixture["target"] as MeshInstance3D
    viewport.add_child(viewport_decoy)
    await process_frame
    _assert_false(runtime._is_valid_target(viewport_target), "SubViewport synthetic Ixelles slice must not be authoritative")
    root.remove_child(viewport)
    viewport.queue_free()
    await process_frame

    var explicit_scene := Node3D.new()
    explicit_scene.name = "ControlledIxellesFixture"
    root.add_child(explicit_scene)
    var explicit_fixture := _make_target_fixture()
    var explicit_root := explicit_fixture["root"] as Node3D
    var explicit_target := explicit_fixture["target"] as MeshInstance3D
    explicit_scene.add_child(explicit_root)
    current_scene = explicit_scene
    await process_frame
    _assert_true(runtime._is_valid_target(explicit_target), "target owned by SceneTree.current_scene must remain an explicit authority path")
    current_scene = null
    root.remove_child(explicit_scene)
    explicit_scene.queue_free()
    await process_frame

    root.remove_child(runtime)
    runtime.queue_free()
    await process_frame

    if _failures.is_empty():
        print("IXELLES_MIDI_SIDEWALK_AUTHORITATIVE_OWNER_OK")
        quit(0)
    else:
        push_error("Ixelles/Midi sidewalk authoritative-owner witness failed with %d assertion(s)" % _failures.size())
        quit(1)

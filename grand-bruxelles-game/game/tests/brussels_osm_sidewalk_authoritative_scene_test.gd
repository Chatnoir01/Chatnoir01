extends SceneTree

const SIDEWALK_RUNTIME := preload("res://game/scripts/brussels_osm_sidewalk_surface_runtime.gd")

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

func _run() -> void:
    var runtime := SIDEWALK_RUNTIME.new()
    runtime.name = "SharedSidewalkAuthorityWitness"
    root.add_child(runtime)
    await process_frame
    current_scene = null

    var root_decoy := Node3D.new()
    root_decoy.name = "SyntheticWorld"
    root.add_child(root_decoy)
    await process_frame
    _assert_false(runtime._is_authoritative_sidewalk_scene(root_decoy), "arbitrary root-level Node3D must not gain shared sidewalk authority")
    root.remove_child(root_decoy)
    root_decoy.queue_free()
    await process_frame

    var viewport := SubViewport.new()
    viewport.name = "SharedSidewalkAuthorityDecoyViewport"
    root.add_child(viewport)
    var viewport_decoy := Node3D.new()
    viewport_decoy.name = "Main"
    viewport.add_child(viewport_decoy)
    await process_frame
    _assert_false(runtime._is_authoritative_sidewalk_scene(viewport_decoy), "synthetic Main under SubViewport must not gain shared sidewalk authority")
    root.remove_child(viewport)
    viewport.queue_free()
    await process_frame

    var explicit_scene := Node3D.new()
    explicit_scene.name = "ControlledSharedSidewalkFixture"
    root.add_child(explicit_scene)
    current_scene = explicit_scene
    await process_frame
    _assert_true(runtime._is_authoritative_sidewalk_scene(explicit_scene), "SceneTree.current_scene must remain an explicit authority path")
    current_scene = null
    root.remove_child(explicit_scene)
    explicit_scene.queue_free()
    await process_frame

    var packed := load("res://game/main.tscn") as PackedScene
    _assert_true(packed != null, "canonical production main scene must load")
    if packed != null:
        var canonical := packed.instantiate() as Node3D
        _assert_true(canonical != null, "canonical production main scene must instantiate as Node3D")
        if canonical != null:
            root.add_child(canonical)
            await process_frame
            _assert_true(canonical.scene_file_path == "res://game/main.tscn", "canonical fixture must retain production scene_file_path")
            _assert_true(runtime._is_authoritative_sidewalk_scene(canonical), "res://game/main.tscn must remain the automatic production authority path")
            root.remove_child(canonical)
            canonical.queue_free()
            await process_frame

    root.remove_child(runtime)
    runtime.queue_free()
    await process_frame

    if _failures.is_empty():
        print("BRUSSELS_OSM_SIDEWALK_AUTHORITATIVE_SCENE_OK")
        quit(0)
    else:
        push_error("Shared OSM sidewalk authoritative-scene witness failed with %d assertion(s)" % _failures.size())
        quit(1)

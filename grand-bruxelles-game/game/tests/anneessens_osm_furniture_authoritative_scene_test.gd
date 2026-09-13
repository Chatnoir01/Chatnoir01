extends SceneTree

const FURNITURE_RUNTIME := preload("res://game/scripts/anneessens_osm_furniture_authoritative_runtime.gd")

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
    var runtime := FURNITURE_RUNTIME.new()
    runtime.name = "AnneessensFurnitureAuthorityWitness"
    root.add_child(runtime)
    await process_frame
    current_scene = null

    var synthetic_root := Node3D.new()
    synthetic_root.name = "Main"
    root.add_child(synthetic_root)
    await process_frame
    _assert_false(runtime._is_authoritative_production_scene(synthetic_root), "synthetic root-level Main without canonical scene identity must not gain furniture authority")
    root.remove_child(synthetic_root)
    synthetic_root.queue_free()
    await process_frame

    var packed := load("res://game/main.tscn") as PackedScene
    _assert_true(packed != null, "canonical production main scene must load")
    if packed != null:
        var viewport := SubViewport.new()
        viewport.name = "FurnitureAuthorityPreviewViewport"
        root.add_child(viewport)
        var viewport_canonical := packed.instantiate() as Node3D
        _assert_true(viewport_canonical != null, "canonical production main scene must instantiate for viewport decoy")
        if viewport_canonical != null:
            viewport.add_child(viewport_canonical)
            await process_frame
            _assert_true(viewport_canonical.scene_file_path == "res://game/main.tscn", "viewport decoy must retain canonical scene identity")
            _assert_false(runtime._is_authoritative_production_scene(viewport_canonical), "canonical Main under SubViewport must not gain automatic furniture authority")
        root.remove_child(viewport)
        viewport.queue_free()
        await process_frame

        var explicit_scene := Node3D.new()
        explicit_scene.name = "ControlledFurnitureFixture"
        root.add_child(explicit_scene)
        current_scene = explicit_scene
        await process_frame
        _assert_true(runtime._is_authoritative_production_scene(explicit_scene), "SceneTree.current_scene must remain an explicit furniture authority path")
        current_scene = null
        root.remove_child(explicit_scene)
        explicit_scene.queue_free()
        await process_frame

        var canonical := packed.instantiate() as Node3D
        _assert_true(canonical != null, "canonical production main scene must instantiate as Node3D")
        if canonical != null:
            root.add_child(canonical)
            await process_frame
            _assert_true(canonical.scene_file_path == "res://game/main.tscn", "canonical fixture must retain production scene_file_path")
            _assert_true(runtime._is_authoritative_production_scene(canonical), "root-mounted res://game/main.tscn must remain the automatic furniture authority path")
            root.remove_child(canonical)
            canonical.queue_free()
            await process_frame

    root.remove_child(runtime)
    runtime.queue_free()
    await process_frame

    if _failures.is_empty():
        print("ANNEESSENS_OSM_FURNITURE_AUTHORITATIVE_SCENE_OK")
        quit(0)
    else:
        push_error("Anneessens furniture authoritative-scene witness failed with %d assertion(s)" % _failures.size())
        quit(1)

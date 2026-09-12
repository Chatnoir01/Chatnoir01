extends SceneTree

const SIDEWALK_RUNTIME := preload("res://game/scripts/anneessens_midi_sidewalk_runtime.gd")

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

func _make_main_fixture() -> Node3D:
    var main := Node3D.new()
    main.name = "Main"
    var brussels_osm := Node3D.new()
    brussels_osm.name = "BrusselsOSM"
    main.add_child(brussels_osm)
    var urbis := Node3D.new()
    urbis.name = "UrbISMidiExact"
    main.add_child(urbis)
    var player := Node3D.new()
    player.name = "Player"
    main.add_child(player)
    return main

func _run() -> void:
    var runtime := SIDEWALK_RUNTIME.new()
    runtime.name = "AnneessensMidiSidewalkAuthorityWitness"
    root.add_child(runtime)
    await process_frame

    current_scene = null

    var root_decoy := _make_main_fixture()
    root.add_child(root_decoy)
    await process_frame
    _assert_false(
        runtime._is_production_scene(root_decoy),
        "root-level synthetic Main with production-like anchors must not be authoritative"
    )
    root.remove_child(root_decoy)
    root_decoy.queue_free()
    await process_frame

    var viewport := SubViewport.new()
    viewport.name = "SidewalkAuthorityDecoyViewport"
    root.add_child(viewport)
    var viewport_decoy := _make_main_fixture()
    viewport.add_child(viewport_decoy)
    await process_frame
    _assert_false(
        runtime._is_production_scene(viewport_decoy),
        "SubViewport synthetic Main with production-like anchors must not be authoritative"
    )
    root.remove_child(viewport)
    viewport.queue_free()
    await process_frame

    var explicit_scene := _make_main_fixture()
    root.add_child(explicit_scene)
    current_scene = explicit_scene
    await process_frame
    _assert_true(
        runtime._is_production_scene(explicit_scene),
        "SceneTree.current_scene must remain an explicit authority path for controlled fixtures"
    )
    current_scene = null
    root.remove_child(explicit_scene)
    explicit_scene.queue_free()
    await process_frame

    var packed := load("res://game/main.tscn") as PackedScene
    _assert_true(packed != null, "canonical production main.tscn must load")
    if packed != null:
        var canonical := packed.instantiate() as Node3D
        _assert_true(canonical != null, "canonical production main.tscn must instantiate as Node3D")
        if canonical != null:
            root.add_child(canonical)
            current_scene = null
            await process_frame
            _assert_true(
                runtime._is_production_scene(canonical),
                "canonical packed main.tscn must remain authoritative without current_scene"
            )
            root.remove_child(canonical)
            canonical.queue_free()
            await process_frame

    root.remove_child(runtime)
    runtime.queue_free()
    await process_frame

    if _failures.is_empty():
        print("ANNEESSENS_MIDI_SIDEWALK_AUTHORITATIVE_ROOT_BIND_OK")
        quit(0)
    else:
        push_error("Anneessens/Midi sidewalk authoritative-root witness failed with %d assertion(s)" % _failures.size())
        quit(1)

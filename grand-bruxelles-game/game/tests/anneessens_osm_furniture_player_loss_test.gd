extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/anneessens_osm_furniture_runtime.gd")
const ANNEESSENS := Vector3(-272.04, 0.0, -217.07)

func _fail(message: String) -> void:
    push_error("ANNEESSENS_OSM_FURNITURE_PLAYER_LOSS_FAIL: %s" % message)
    quit(1)

func _all_collisions_disabled(furniture_root: Node3D) -> bool:
    for child: Node in furniture_root.get_children():
        if child is StaticBody3D:
            var collision := child.get_node_or_null("CollisionShape3D") as CollisionShape3D
            if collision == null or not collision.disabled:
                return false
    return true

func _all_collisions_enabled(furniture_root: Node3D) -> bool:
    for child: Node in furniture_root.get_children():
        if child is StaticBody3D:
            var collision := child.get_node_or_null("CollisionShape3D") as CollisionShape3D
            if collision == null or collision.disabled:
                return false
    return true

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    if current_scene != null:
        _fail("script witness requires current_scene == null")
        return

    var runtime := RUNTIME_SCRIPT.new()
    runtime.name = "AnneessensOsmFurnitureRuntimePlayerLossProbe"
    root.add_child(runtime)

    var main := Node3D.new()
    main.name = "Main"
    root.add_child(main)

    var brussels_osm := Node3D.new()
    brussels_osm.name = "BrusselsOSM"
    main.add_child(brussels_osm)

    var urbis_midi := Node3D.new()
    urbis_midi.name = "UrbISMidiExact"
    main.add_child(urbis_midi)

    var player := Node3D.new()
    player.name = "Player"
    player.position = ANNEESSENS
    main.add_child(player)

    for _frame: int in range(24):
        await process_frame

    var furniture_root := main.get_node_or_null("AnneessensOsmFurniture") as Node3D
    if furniture_root == null:
        _fail("authoritative Main did not receive Anneessens furniture")
        return
    if int(runtime.call("tree_count")) != 7:
        _fail("expected exactly seven source-backed Anneessens trees")
        return
    if not furniture_root.visible or not _all_collisions_enabled(furniture_root):
        _fail("near-player baseline must be visible and collision-enabled")
        return

    main.remove_child(player)
    player.queue_free()
    for _frame: int in range(8):
        await process_frame

    if furniture_root.visible:
        _fail("furniture remained visible after required Player anchor disappeared")
        return
    if not _all_collisions_disabled(furniture_root):
        _fail("furniture collisions remained active after required Player anchor disappeared")
        return

    var replacement_player := Node3D.new()
    replacement_player.name = "Player"
    replacement_player.position = ANNEESSENS
    main.add_child(replacement_player)
    for _frame: int in range(12):
        await process_frame

    if not furniture_root.visible or not _all_collisions_enabled(furniture_root):
        _fail("furniture did not reactivate after a legitimate Player anchor returned")
        return

    if str(furniture_root.get_meta("source", "")) != "OpenStreetMap contributors via Overpass API":
        _fail("source provenance changed")
        return
    if str(furniture_root.get_meta("license", "")) != "ODbL-1.0":
        _fail("license provenance changed")
        return

    print("ANNEESSENS_OSM_FURNITURE_PLAYER_LOSS_OK: trees=7 fail_closed=true reactivated=true source=OSM license=ODbL-1.0")
    quit(0)

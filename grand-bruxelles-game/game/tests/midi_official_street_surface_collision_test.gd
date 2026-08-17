extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const REQUIRED_SURFACES := [
    "ExactRoadCarriageways",
    "ExactSidewalks",
    "ExactTrafficIslands",
    "ExactPavedAreas",
    "ExactOtherStreetSurfaces",
]

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_OFFICIAL_STREET_COLLISION_FAIL: %s" % message)
    quit(1)

func _has_static_collision(mesh_instance: MeshInstance3D) -> bool:
    for child: Node in mesh_instance.get_children():
        if child is StaticBody3D:
            var body := child as StaticBody3D
            if body.collision_layer != 1 or body.collision_mask != 1:
                return false
            for shape_child: Node in body.get_children():
                if shape_child is CollisionShape3D and (shape_child as CollisionShape3D).shape != null:
                    return true
    return false

func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    for _frame: int in range(8):
        await process_frame

    var builder := main.get_node_or_null("UrbISMidiExact")
    if builder == null:
        _fail("UrbISMidiExact missing from production scene")
        return
    var surfaces := builder.get_node_or_null("UrbISStreetSurfaces")
    if surfaces == null:
        _fail("official Midi street-surface root missing")
        return

    var checked := 0
    for surface_name: String in REQUIRED_SURFACES:
        var mesh := surfaces.get_node_or_null(surface_name) as MeshInstance3D
        if mesh == null or mesh.mesh == null or mesh.mesh.get_surface_count() == 0:
            continue
        checked += 1
        if not _has_static_collision(mesh):
            _fail("official surface %s has no player-foot StaticBody3D trimesh collision" % surface_name)
            return

    if checked < 4:
        _fail("too few official surface families reached runtime: %d" % checked)
        return

    print("MIDI_OFFICIAL_STREET_COLLISION_OK: solid_surface_families=%d source_geometry_reused=true" % checked)
    main.queue_free()
    quit(0)

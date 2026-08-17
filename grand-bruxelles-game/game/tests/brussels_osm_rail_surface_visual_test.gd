extends SceneTree

const MIDI_ANCHOR := Vector3(-668.5, 1.65, 627.84)
const BEFORE_PATH := "res://artifacts/visual/brussels_osm_rail_surface_before.png"
const AFTER_PATH := "res://artifacts/visual/brussels_osm_rail_surface_after.png"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_RAIL_SURFACE_VISUAL_FAIL: %s" % message)
    quit(1)

func _walk(node: Node, callback: Callable) -> void:
    callback.call(node)
    for child: Node in node.get_children():
        _walk(child, callback)

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene missing")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    current_scene = scene

    var runtime: Node = root.get_node_or_null("BrusselsOsmRailSurfaceRuntime")
    if runtime == null:
        _fail("autoload missing")
        return

    for _attempt: int in range(240):
        await process_frame
        if runtime.call("ready_complete"):
            break
    if not runtime.call("ready_complete") or runtime.call("failed"):
        _fail("runtime did not become ready")
        return

    var rails_root := root.find_child("GeneratedRails", true, false)
    if rails_root == null:
        _fail("GeneratedRails missing")
        return

    var nearest: CSGBox3D = null
    var nearest_distance := INF
    for child: Node in rails_root.get_children():
        if child is CSGBox3D and child.name.begins_with("Rail_"):
            var rail := child as CSGBox3D
            var p := rail.global_position
            var distance := Vector2(p.x, p.z).distance_to(Vector2(MIDI_ANCHOR.x, MIDI_ANCHOR.z))
            if distance < nearest_distance:
                nearest_distance = distance
                nearest = rail
    if nearest == null or nearest_distance > 45.0:
        _fail("no legitimate Midi rail witness within 45 m")
        return

    _walk(root, func(node: Node) -> void:
        if node is Camera3D:
            (node as Camera3D).current = false
        if node is CanvasItem:
            (node as CanvasItem).visible = false
        if node is AnimationPlayer:
            (node as AnimationPlayer).active = false
        if node is CharacterBody3D or node is RigidBody3D:
            node.process_mode = Node.PROCESS_MODE_DISABLED
    )

    var camera := Camera3D.new()
    camera.name = "OsmRailSurfacePlayerWitnessCamera"
    camera.fov = 69.0
    camera.position = MIDI_ANCHOR
    root.add_child(camera)
    camera.look_at(Vector3(nearest.global_position.x, 0.10, nearest.global_position.z), Vector3.UP)
    camera.current = true

    var output_dir := ProjectSettings.globalize_path("res://artifacts/visual")
    DirAccess.make_dir_recursive_absolute(output_dir)

    runtime.call("set_enhanced_enabled", false)
    for _frame: int in range(8):
        await process_frame
    var before := root.get_viewport().get_texture().get_image()
    if before == null or before.get_width() != 1280 or before.get_height() != 720:
        _fail("BEFORE capture is not 1280x720")
        return
    if before.save_png(BEFORE_PATH) != OK:
        _fail("could not save BEFORE")
        return

    runtime.call("set_enhanced_enabled", true)
    for _frame: int in range(8):
        await process_frame
    var after := root.get_viewport().get_texture().get_image()
    if after == null or after.get_width() != 1280 or after.get_height() != 720:
        _fail("AFTER capture is not 1280x720")
        return
    if after.save_png(AFTER_PATH) != OK:
        _fail("could not save AFTER")
        return

    print("BRUSSELS_OSM_RAIL_SURFACE_VISUAL_OK: anchor=midi eye_height=1.65 fov=69 nearest_m=%.3f rail=%s geometry_changed=false" % [nearest_distance, nearest.name])
    quit(0)

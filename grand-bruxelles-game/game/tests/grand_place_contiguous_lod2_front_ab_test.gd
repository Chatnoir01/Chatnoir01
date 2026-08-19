extends SceneTree

const CAMERA_POSITION := Vector3(319.01, 1.72, -535.20)
const CAMERA_TARGET := Vector3(321.91, 11.8, -485.66)
const CAMERA_FOV := 62.0
const OUTPUT_DIR := "res://artifacts/qa/grand_place_contiguous_lod2_front_ab"
const EXPECTED_BUILDINGS := 12
const EXPECTED_RENDER_TRIANGLES := 573

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_CONTIGUOUS_LOD2_FRONT_AB_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var packed: PackedScene = load("res://game/main.tscn")
    if packed == null:
        _fail("main scene failed to load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    current_scene = scene
    for _i: int in range(24):
        await process_frame

    var runtime := root.get_node_or_null("GrandPlaceContiguousLod2Front")
    if runtime == null:
        _fail("autoload runtime missing")
        return
    if not bool(runtime.geometry_loaded):
        _fail("official frontage did not load")
        return
    if int(runtime.building_count) != EXPECTED_BUILDINGS:
        _fail("building count drifted: %d" % int(runtime.building_count))
        return
    if int(runtime.render_triangle_count) != EXPECTED_RENDER_TRIANGLES:
        _fail("render triangle count drifted: %d" % int(runtime.render_triangle_count))
        return

    _freeze_dynamic_state(scene)
    var sun := scene.get_node_or_null("Sun") as DirectionalLight3D
    if sun != null:
        sun.shadow_enabled = false

    var player_camera := scene.get_node_or_null("Player/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if player_camera != null:
        player_camera.current = false
    var camera := Camera3D.new()
    camera.name = "GrandPlaceContiguousFrontFrozenCamera"
    camera.position = CAMERA_POSITION
    camera.fov = CAMERA_FOV
    scene.add_child(camera)
    camera.look_at(CAMERA_TARGET, Vector3.UP)
    camera.current = true

    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

    runtime.set_front_visible(false)
    for _i: int in range(5):
        await process_frame
    var before := get_root().get_texture().get_image()
    if before == null or before.is_empty():
        _fail("BEFORE capture empty")
        return
    if before.get_width() != 1280 or before.get_height() != 720:
        _fail("BEFORE size drifted: %dx%d" % [before.get_width(), before.get_height()])
        return
    before.save_png("%s/before.png" % OUTPUT_DIR)

    runtime.set_front_visible(true)
    for _i: int in range(5):
        await process_frame
    var after := get_root().get_texture().get_image()
    if after == null or after.is_empty():
        _fail("AFTER capture empty")
        return
    after.save_png("%s/after.png" % OUTPUT_DIR)

    print("GRAND_PLACE_CONTIGUOUS_LOD2_FRONT_AB_OK: buildings=%d triangles=%d masked_osm=%d camera=%s target=%s fov=%.1f" % [
        int(runtime.building_count), int(runtime.render_triangle_count), int(runtime.masked_osm_count),
        str(CAMERA_POSITION), str(CAMERA_TARGET), CAMERA_FOV,
    ])
    quit(0)

func _freeze_dynamic_state(scene: Node) -> void:
    var dynamic_paths := [
        "Player", "PrototypeCar", "PhysicalCarB", "MidiUrbanLife", "TrafficManager",
        "NpcPopulationDirector", "NpcRuntimeIntegration",
    ]
    for path_variant: Variant in dynamic_paths:
        var node := scene.get_node_or_null(str(path_variant))
        if node == null:
            continue
        node.process_mode = Node.PROCESS_MODE_DISABLED
        if node is Node3D:
            (node as Node3D).visible = false
        elif node is CanvasItem:
            (node as CanvasItem).visible = false
    _hide_ui_recursive(scene)

func _hide_ui_recursive(node: Node) -> void:
    for child: Node in node.get_children():
        if child is Control:
            (child as Control).visible = false
        elif child is Label3D:
            (child as Label3D).visible = false
        elif child is CanvasLayer:
            (child as CanvasLayer).visible = false
        _hide_ui_recursive(child)

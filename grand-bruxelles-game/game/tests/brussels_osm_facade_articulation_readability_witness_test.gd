extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const BEFORE_PATH := "res://artifacts/visual/osm_facade_readability_before.png"
const CONTROL_PATH := "res://artifacts/visual/osm_facade_readability_control.png"
const AFTER_PATH := "res://artifacts/visual/osm_facade_readability_after.png"
const MATERIAL_PATH := "res://game/scripts/brussels_osm_facade_articulation_material.gd"
const ANNEESSENS := Vector2(-272.04, -217.07)
const SEARCH_RADIUS_M := 105.0
const MATERIAL_FAMILY := "brussels_osm_facade_articulation_v1"

func _initialize() -> void: call_deferred("_run")
func _fail(message: String) -> void: push_error("BRUSSELS_OSM_FACADE_ARTICULATION_READABILITY_VISUAL_FAIL: %s" % message); quit(1)

func _disable_owned_unrelated_runtime(scene: Node) -> void:
    var stack: Array[Node] = [scene]
    while not stack.is_empty():
        var node: Node = stack.pop_back()
        var script: Script = node.get_script() as Script
        if script != null and script.resource_path == "res://game/scripts/mission_drive_to_center.gd":
            node.process_mode = Node.PROCESS_MODE_DISABLED
        for child: Node in node.get_children(): stack.append(child)

func _capture(viewport: SubViewport, path: String) -> Image:
    RenderingServer.force_draw(); await process_frame
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty(): return null
    var absolute := ProjectSettings.globalize_path(path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    if image.save_png(absolute) != OK: return null
    return image

func _hide_dynamic(scene: Node) -> void:
    for path: String in ["LocationLabel", "MissionLabel", "PrototypeLabel", "MiniMap", "MobileControls", "WalletHUD"]:
        var item := scene.get_node_or_null(path) as CanvasItem
        if item != null: item.visible = false
    for path: String in ["PrototypeCar", "PhysicalCarB", "MidiUrbanLife"]:
        var spatial := scene.get_node_or_null(path) as Node3D
        if spatial != null: spatial.visible = false
    var player := scene.get_node_or_null("Player") as Node3D
    if player != null: player.visible = false

func _polygon_area(points: PackedVector2Array) -> float:
    var sum := 0.0
    for i: int in range(points.size()):
        var a := points[i]; var b := points[(i + 1) % points.size()]
        sum += a.x * b.y - b.x * a.y
    return absf(sum) * 0.5

func _select_generic_building(root_node: Node3D) -> CSGPolygon3D:
    var best: CSGPolygon3D = null; var best_score := -INF
    for child: Node in root_node.get_children():
        if not child is CSGPolygon3D or not str(child.name).begins_with("Building_"): continue
        var building := child as CSGPolygon3D
        var distance := Vector2(building.global_position.x, building.global_position.z).distance_to(ANNEESSENS)
        if distance < 18.0 or distance > SEARCH_RADIUS_M: continue
        var area := _polygon_area(building.polygon)
        if area < 35.0: continue
        var score := area / maxf(distance, 1.0)
        if score > best_score: best = building; best_score = score
    return best

func _active_materials(buildings_root: Node3D) -> Array[ShaderMaterial]:
    var result: Array[ShaderMaterial] = []
    var seen := {}
    for child: Node in buildings_root.get_children():
        if not child is CSGPolygon3D: continue
        var material := (child as CSGPolygon3D).material as ShaderMaterial
        if material == null or str(material.get_meta("material_family", "")) != MATERIAL_FAMILY: continue
        var id := material.get_instance_id()
        if seen.has(id): continue
        seen[id] = true; result.append(material)
    return result

func _run() -> void:
    var material_factory := load(MATERIAL_PATH)
    if material_factory == null or not "SURFACE_READABILITY_STRENGTH" in material_factory:
        _fail("authored facade readability strength unavailable"); return
    var authored_strength := float(material_factory.SURFACE_READABILITY_STRENGTH)
    if authored_strength <= 0.0 or authored_strength > 0.25:
        _fail("authored facade readability strength outside frozen bounds"); return
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null: _fail("production main scene missing"); return
    var scene := packed.instantiate() as Node3D
    _disable_owned_unrelated_runtime(scene)
    var viewport := SubViewport.new(); viewport.size = Vector2i(WIDTH, HEIGHT); viewport.own_world_3d = true; viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport); viewport.add_child(scene); _hide_dynamic(scene)
    var runtime := root.get_node_or_null("BrusselsOsmFacadeArticulationRuntime")
    if runtime == null: _fail("facade articulation runtime missing"); return
    for _frame: int in range(300):
        if bool(runtime.call("ready_complete")): break
        await process_frame
    if not bool(runtime.call("ready_complete")) or bool(runtime.call("failed")): _fail("facade articulation runtime did not bind cleanly"); return
    var buildings_root := scene.get_node_or_null("BrusselsOSM/GeneratedBuildings") as Node3D
    if buildings_root == null: _fail("GeneratedBuildings missing"); return
    var building := _select_generic_building(buildings_root)
    if building == null: _fail("no legitimate generic OSM building found near Anneessens"); return
    var materials := _active_materials(buildings_root)
    if materials.is_empty() or materials.size() > 6: _fail("active articulation material set invalid: %d" % materials.size()); return
    var original_transform := building.global_transform; var original_polygon := building.polygon.duplicate(); var original_depth := building.depth
    var building_xz := Vector2(building.global_position.x, building.global_position.z); var outward := (ANNEESSENS - building_xz).normalized(); var camera_distance := clampf(building_xz.distance_to(ANNEESSENS) * 0.48, 16.0, 30.0); var camera_xz := building_xz + outward * camera_distance
    var camera := Camera3D.new(); camera.position = Vector3(camera_xz.x, 1.65, camera_xz.y); camera.look_at_from_position(camera.position, Vector3(building_xz.x, clampf(building.depth * 0.42, 4.0, 8.5), building_xz.y), Vector3.UP); camera.fov = 67.0; camera.current = true; scene.add_child(camera)
    var colors: Array[Color] = []
    for material: ShaderMaterial in materials:
        colors.append(material.get_shader_parameter("base_color") as Color)
        material.set_shader_parameter("surface_readability_strength", 0.0)
    for _frame: int in range(8): await process_frame
    var before := await _capture(viewport, BEFORE_PATH)
    for i: int in range(materials.size()): materials[i].set_shader_parameter("base_color", Color(1.0, 0.0, 1.0, 1.0))
    for _frame: int in range(4): await process_frame
    var control := await _capture(viewport, CONTROL_PATH)
    for i: int in range(materials.size()):
        materials[i].set_shader_parameter("base_color", colors[i])
        materials[i].set_shader_parameter("surface_readability_strength", authored_strength)
    for _frame: int in range(8): await process_frame
    var after := await _capture(viewport, AFTER_PATH)
    if before == null or control == null or after == null: _fail("1280x720 readability capture failed"); return
    if not building.global_transform.is_equal_approx(original_transform) or building.polygon != original_polygon or not is_equal_approx(building.depth, original_depth): _fail("building geometry changed during readability A/B"); return
    if not bool(runtime.call("geometry_unchanged")): _fail("runtime geometry invariant failed"); return
    print("BRUSSELS_OSM_FACADE_ARTICULATION_READABILITY_VISUAL_CAPTURED: building=%s distance=%.2f materials=%d player_eye_height=1.65m fov=67 strength=%.2f same_camera=true geometry_unchanged=true authored_strength_bound=true" % [building.name, camera_distance, materials.size(), authored_strength])
    quit(0)

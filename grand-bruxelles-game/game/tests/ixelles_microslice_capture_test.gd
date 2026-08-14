extends SceneTree

const SLICE_SCRIPT := preload("res://game/zones/ixelles/ixelles_microslice_draped_intersection.gd")
const OUTPUT_PATH := "res://artifacts/ixelles/ixelles_place_stephanie_foundation.png"
const WIDTH := 1280
const HEIGHT := 960
const CAMERA_AXIS_ID := "https://databrussels.be/id/streetaxe/71374:1"
const TARGET_AXIS_ID := "https://databrussels.be/id/streetaxe/71306:2"
const CAMERA_AXIS_T := 0.68
const CAMERA_EYE_HEIGHT_M := 1.72
const TARGET_EYE_HEIGHT_M := 1.65
const LOS_GUARD_DISTANCE_M := 35.0
const LOS_MIN_CLEARANCE_M := 0.65

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("IXELLES_MICROSLICE_CAPTURE_FAIL: %s" % message)
    quit(1)

func _axis_segment(slice: Node, axis_id: String) -> PackedVector2Array:
    var network: Dictionary = slice.get_meta("ixelles_network_contract", {})
    var axes: Variant = network.get("street_axes", [])
    if not axes is Array:
        return PackedVector2Array()
    for raw: Variant in axes:
        if not raw is Dictionary or str(raw.get("id", "")) != axis_id:
            continue
        var points: Variant = raw.get("points", [])
        if not points is Array or points.size() != 2:
            return PackedVector2Array()
        var result := PackedVector2Array()
        for point: Variant in points:
            if not point is Array or point.size() < 2:
                return PackedVector2Array()
            result.append(Vector2(float(point[0]), float(point[1])))
        return result
    return PackedVector2Array()

func _point_on_axis(segment: PackedVector2Array, t: float) -> Vector2:
    return segment[0].lerp(segment[1], clampf(t, 0.0, 1.0))

func _inside_official_street_surface(slice: Node, point: Vector2) -> bool:
    var cell: Dictionary = slice.get_meta("ixelles_cell_contract", {})
    var surfaces: Variant = cell.get("street_surfaces", [])
    if not surfaces is Array:
        return false
    for raw: Variant in surfaces:
        if not raw is Dictionary:
            continue
        var polygon_raw: Variant = raw.get("polygon", [])
        if not polygon_raw is Array or polygon_raw.size() < 3:
            continue
        var polygon := PackedVector2Array()
        for pair: Variant in polygon_raw:
            if pair is Array and pair.size() >= 2:
                polygon.append(Vector2(float(pair[0]), float(pair[1])))
        if polygon.size() >= 3 and Geometry2D.is_point_in_polygon(point, polygon):
            return true
    return false

func _minimum_los_clearance(slice: Node, from: Vector3, to: Vector3, guard_distance_m: float) -> float:
    var horizontal := Vector2(to.x - from.x, to.z - from.z)
    var horizontal_distance := horizontal.length()
    if horizontal_distance <= 0.001:
        return -INF
    var tested_distance := minf(horizontal_distance, guard_distance_m)
    var tested_t := tested_distance / horizontal_distance
    var minimum_clearance := INF
    for i: int in range(1, 33):
        var t := tested_t * float(i) / 32.0
        var ray_point := from.lerp(to, t)
        var ground := float(slice.call("sample_height", ray_point.x, ray_point.z))
        minimum_clearance = minf(minimum_clearance, ray_point.y - ground)
    return minimum_clearance

func _run() -> void:
    var viewport := SubViewport.new()
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)

    var world := Node3D.new()
    viewport.add_child(world)
    var slice := SLICE_SCRIPT.new()
    slice.build_collision = false
    world.add_child(slice)
    await process_frame
    await process_frame
    if not slice.runtime_loaded:
        _fail("runtime slice did not load")
        return
    if slice.street_drape_outside_source_vertices != 0 or slice.street_drape_source_intersection_piece_count <= 0 or slice.street_drape_min_check_clearance_m < -0.001:
        _fail("StreetSurface source-intersection/drape guard failed before capture")
        return

    var stassart_segment := _axis_segment(slice, CAMERA_AXIS_ID)
    var stephanie_segment := _axis_segment(slice, TARGET_AXIS_ID)
    if stassart_segment.size() != 2 or stephanie_segment.size() != 2:
        _fail("source-confirmed Stassart/Place Stephanie StreetAxis segments unavailable")
        return

    var camera_xz := _point_on_axis(stassart_segment, CAMERA_AXIS_T)
    var target_xz := stephanie_segment[1]
    if camera_xz.distance_to(stassart_segment[1]) < 20.0 or camera_xz.distance_to(target_xz) > 45.0:
        _fail("street-aligned camera corridor distance drifted")
        return
    if not _inside_official_street_surface(slice, camera_xz) or not _inside_official_street_surface(slice, target_xz):
        _fail("camera or target left the official StreetSurface corridor")
        return

    var camera_ground := float(slice.sample_height(camera_xz.x, camera_xz.y))
    var target_ground := float(slice.sample_height(target_xz.x, target_xz.y))
    if not is_finite(camera_ground) or not is_finite(target_ground):
        _fail("camera/target terrain samples are non-finite")
        return

    var camera_position := Vector3(camera_xz.x, camera_ground + CAMERA_EYE_HEIGHT_M, camera_xz.y)
    var target_position := Vector3(target_xz.x, target_ground + TARGET_EYE_HEIGHT_M, target_xz.y)
    var los_min_clearance := _minimum_los_clearance(slice, camera_position, target_position, LOS_GUARD_DISTANCE_M)
    if not is_finite(los_min_clearance) or los_min_clearance < LOS_MIN_CLEARANCE_M:
        _fail("near-field terrain occludes the source-aligned street LOS: min_clearance=%.3f m" % los_min_clearance)
        return

    var environment := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.66, 0.72, 0.79)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.86, 0.89, 0.92)
    env.ambient_light_energy = 0.72
    environment.environment = env
    world.add_child(environment)

    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-48.0, -34.0, 0.0)
    sun.light_energy = 1.15
    sun.shadow_enabled = true
    world.add_child(sun)

    var camera := Camera3D.new()
    camera.position = camera_position
    camera.fov = 54.0
    camera.current = true
    world.add_child(camera)
    camera.look_at(target_position, Vector3.UP)

    for _frame: int in range(12):
        await process_frame
    RenderingServer.force_draw()
    await process_frame
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        _fail("capture invalid")
        return
    var absolute_output := ProjectSettings.globalize_path(OUTPUT_PATH)
    DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
    if image.save_png(absolute_output) != OK:
        _fail("capture save failed")
        return
    print("IXELLES_MICROSLICE_CAPTURE_OK: cell=%s camera_axis=%s target_axis=%s camera=(%.3f,%.3f,%.3f) camera_ground=%.3f target=(%.3f,%.3f,%.3f) target_ground=%.3f los_min_clearance=%.3f drape_triangles=%d drape_min_clearance=%.5f streets=%d buildings=%d skipped=%d capture=%s" % [slice.cell_id, CAMERA_AXIS_ID, TARGET_AXIS_ID, camera.position.x, camera.position.y, camera.position.z, camera_ground, target_position.x, target_position.y, target_position.z, target_ground, los_min_clearance, slice.street_drape_triangle_count, slice.street_drape_min_check_clearance_m, slice.street_surface_count, slice.building_count, slice.skipped_unapproved_height_buildings, OUTPUT_PATH])
    quit(0)

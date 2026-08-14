extends CharacterBody3D

@export var walk_speed: float = 6.0
@export var sprint_speed: float = 10.0
@export var acceleration: float = 18.0
@export var jump_velocity: float = 5.5
@export var mouse_sensitivity: float = 0.0025
@export var vehicle_interaction_range: float = 4.0

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D

const BOURSE_DIRECT_SPAWN_POSITION := Vector3(83.44, 1.05, -663.42)
# Faces the authoritative UrbIS LoD2 Bourse bbox center from the direct-test position.
const BOURSE_DIRECT_SPAWN_YAW_DEGREES := -84.32

const ATOMIUM_TERRAIN_SCRIPT := preload("res://game/zones/laeken_jette/atomium_dtm_terrain.gd")
const ATOMIUM_HERO_SCRIPT := preload("res://game/zones/laeken_jette/atomium_hero_core.gd")
const ATOMIUM_REFLECTION_SCRIPT := preload("res://game/zones/laeken_jette/atomium_hero_reflection_environment.gd")
# Presentation-only visitor viewpoint inside the already validated DTM tile.
# It does not claim a surveyed camera pose or resolve the Atomium global yaw.
const ATOMIUM_DIRECT_SPAWN_OFFSET := Vector3(120.0, 0.0, 0.0)
const ATOMIUM_DIRECT_EYE_HEIGHT_M := 1.05
# Positive X pitch looks upward in this Godot camera rig.
const ATOMIUM_DIRECT_CAMERA_PITCH_DEGREES := 20.0

const IXELLES_SLICE_SCRIPT := preload("res://game/zones/ixelles/ixelles_microslice_draped_intersection.gd")
const IXELLES_CAMERA_AXIS_ID := "https://databrussels.be/id/streetaxe/71374:1"
const IXELLES_TARGET_AXIS_ID := "https://databrussels.be/id/streetaxe/71306:2"
const IXELLES_CAMERA_AXIS_T := 0.68
const IXELLES_CAMERA_EYE_HEIGHT_M := 1.72
const IXELLES_PLAYER_BODY_CENTER_CLEARANCE_M := 0.90

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var _base_collision_layer: int = 1
var _base_collision_mask: int = 1


func _ready() -> void:
    _base_collision_layer = collision_layer
    _base_collision_mask = collision_mask
    _apply_direct_spawn_from_user_args(OS.get_cmdline_user_args())
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if DisplayServer.is_touchscreen_available() else Input.MOUSE_MODE_CAPTURED


func _apply_direct_spawn_from_user_args(args: PackedStringArray) -> void:
    for arg: String in args:
        var normalized := arg.strip_edges().to_lower()
        if normalized == "spawn=bourse":
            global_position = BOURSE_DIRECT_SPAWN_POSITION
            rotation_degrees.y = BOURSE_DIRECT_SPAWN_YAW_DEGREES
            velocity = Vector3.ZERO
            print("Direct test spawn: Bourse / Beursplein")
            return
        if normalized == "spawn=atomium":
            call_deferred("_activate_atomium_direct_spawn")
            return
        if normalized == "spawn=ixelles":
            call_deferred("_activate_ixelles_direct_spawn")
            return


func _ixelles_axis_segment(slice: Node, axis_id: String) -> PackedVector2Array:
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


func _ixelles_inside_official_street_surface(slice: Node, point: Vector2) -> bool:
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


func _ixelles_collision_ground_y(camera_xz: Vector2, sampled_ground: float) -> float:
    var query := PhysicsRayQueryParameters3D.create(
        Vector3(camera_xz.x, sampled_ground + 20.0, camera_xz.y),
        Vector3(camera_xz.x, sampled_ground - 20.0, camera_xz.y)
    )
    query.collision_mask = 1
    query.exclude = [get_rid()]
    var hit := get_world_3d().direct_space_state.intersect_ray(query)
    if hit.is_empty():
        return NAN
    var collider: Variant = hit.get("collider")
    if not collider is Node or not (collider as Node).name.begins_with("OfficialIxellesDTMCollision"):
        return NAN
    var position: Variant = hit.get("position")
    if not position is Vector3:
        return NAN
    return (position as Vector3).y


func _activate_ixelles_direct_spawn() -> void:
    var world := get_parent() as Node3D
    if world == null:
        push_error("Ixelles direct spawn: world root unavailable")
        return

    var slice := IXELLES_SLICE_SCRIPT.new()
    slice.name = "IxellesDirectMicroSlice"
    slice.build_collision = true
    world.add_child(slice)
    await get_tree().process_frame
    await get_tree().physics_frame
    if not bool(slice.get("runtime_loaded")):
        push_error("Ixelles direct spawn: shipped micro-slice failed to load")
        return
    if int(slice.get("building_count")) != 260 or int(slice.get("skipped_unapproved_height_buildings")) != 460:
        push_error("Ixelles direct spawn: strong-height/no-invention contract drifted")
        return

    var camera_axis := _ixelles_axis_segment(slice, IXELLES_CAMERA_AXIS_ID)
    var target_axis := _ixelles_axis_segment(slice, IXELLES_TARGET_AXIS_ID)
    if camera_axis.size() != 2 or target_axis.size() != 2:
        push_error("Ixelles direct spawn: accepted source StreetAxis witness unavailable")
        return
    var camera_xz := camera_axis[0].lerp(camera_axis[1], IXELLES_CAMERA_AXIS_T)
    var target_xz := target_axis[1]
    if not _ixelles_inside_official_street_surface(slice, camera_xz):
        push_error("Ixelles direct spawn: player witness left official StreetSurface")
        return

    var camera_ground := float(slice.call("sample_height", camera_xz.x, camera_xz.y))
    var target_ground := float(slice.call("sample_height", target_xz.x, target_xz.y))
    if not is_finite(camera_ground) or not is_finite(target_ground):
        push_error("Ixelles direct spawn: terrain witness unavailable")
        return
    var physical_ground := _ixelles_collision_ground_y(camera_xz, camera_ground)
    if not is_finite(physical_ground):
        push_error("Ixelles direct spawn: source DTM collision ray did not resolve")
        return

    global_position = Vector3(camera_xz.x, physical_ground + IXELLES_PLAYER_BODY_CENTER_CLEARANCE_M, camera_xz.y)
    var target_position := Vector3(target_xz.x, target_ground + 1.65, target_xz.y)
    var to_target := target_position - Vector3(global_position.x, target_position.y, global_position.z)
    rotation_degrees.y = rad_to_deg(atan2(-to_target.x, -to_target.z))
    camera_pivot.position.y = camera_ground + IXELLES_CAMERA_EYE_HEIGHT_M - global_position.y
    camera_pivot.rotation_degrees.x = 0.0
    var spring_arm := get_node_or_null("CameraPivot/SpringArm3D") as SpringArm3D
    if spring_arm != null:
        spring_arm.spring_length = 0.0
    var base_mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
    if base_mesh != null:
        base_mesh.visible = false
    var visual_upgrade := get_node_or_null("VisualUpgrade") as Node3D
    if visual_upgrade != null:
        visual_upgrade.visible = false
    velocity = Vector3.ZERO

    set_meta("ixelles_direct_camera_axis", IXELLES_CAMERA_AXIS_ID)
    set_meta("ixelles_direct_target_axis", IXELLES_TARGET_AXIS_ID)
    set_meta("ixelles_direct_sampled_ground_y", camera_ground)
    set_meta("ixelles_direct_physical_ground_y", physical_ground)
    set_meta("ixelles_direct_target_position", target_position)

    var location_label := world.get_node_or_null("LocationLabel")
    if location_label != null and location_label.has_method("set_forced_label"):
        location_label.call("set_forced_label", "IXELLES · PLACE STÉPHANIE / STEFANIA")
    elif location_label is Label:
        (location_label as Label).text = "IXELLES · PLACE STÉPHANIE / STEFANIA"
    var mission_label := world.get_node_or_null("MissionLabel")
    if mission_label is CanvasItem:
        (mission_label as CanvasItem).visible = false
    var save_label := world.get_node_or_null("SaveStatusLabel")
    if save_label is CanvasItem:
        (save_label as CanvasItem).visible = false
    var wallet_label := world.get_node_or_null("WalletLabel")
    if wallet_label is CanvasItem:
        (wallet_label as CanvasItem).visible = false
    var minimap := world.get_node_or_null("MiniMap")
    if minimap is CanvasItem:
        (minimap as CanvasItem).visible = false

    print("Direct test spawn: Ixelles / Place Stephanie")


func _activate_atomium_direct_spawn() -> void:
    var world := get_parent() as Node3D
    if world == null:
        push_error("Atomium direct spawn: world root unavailable")
        return

    var terrain := ATOMIUM_TERRAIN_SCRIPT.new()
    terrain.name = "AtomiumDirectTerrain"
    terrain.build_collision = true
    world.add_child(terrain)
    await get_tree().process_frame
    if not bool(terrain.get("terrain_loaded")):
        push_error("Atomium direct spawn: official DTM failed to load")
        return

    var hero := ATOMIUM_HERO_SCRIPT.new()
    hero.name = "AtomiumDirectHero"
    world.add_child(hero)
    if not bool(hero.call("build_on_terrain", terrain)):
        push_error("Atomium direct spawn: hero failed to build")
        return

    var reflection := ATOMIUM_REFLECTION_SCRIPT.new()
    reflection.name = "AtomiumDirectReflectionEnvironment"
    world.add_child(reflection)
    if not bool(reflection.call("build")):
        push_error("Atomium direct spawn: reflection environment failed to build")
        return

    var default_environment := world.get_node_or_null("WorldEnvironment")
    if default_environment is WorldEnvironment:
        (default_environment as WorldEnvironment).environment = null
    var default_sun := world.get_node_or_null("Sun")
    if default_sun is DirectionalLight3D:
        (default_sun as DirectionalLight3D).visible = false

    var atomium_anchor: Vector3 = terrain.get("atomium_game_position")
    var spawn_xz := atomium_anchor + ATOMIUM_DIRECT_SPAWN_OFFSET
    if not bool(terrain.call("contains_game_point", spawn_xz.x, spawn_xz.z)):
        push_error("Atomium direct spawn: visitor viewpoint falls outside official DTM")
        return
    var spawn_y := float(terrain.call("sample_height", spawn_xz.x, spawn_xz.z)) + ATOMIUM_DIRECT_EYE_HEIGHT_M
    global_position = Vector3(spawn_xz.x, spawn_y, spawn_xz.z)
    var to_hero := atomium_anchor - global_position
    rotation_degrees.y = rad_to_deg(atan2(-to_hero.x, -to_hero.z))
    camera_pivot.rotation_degrees.x = ATOMIUM_DIRECT_CAMERA_PITCH_DEGREES
    velocity = Vector3.ZERO

    var location_label := world.get_node_or_null("LocationLabel")
    if location_label != null and location_label.has_method("set_forced_label"):
        location_label.call("set_forced_label", "ATOMIUM · HEYSEL / HEIZEL")
    elif location_label is Label:
        (location_label as Label).text = "ATOMIUM · HEYSEL / HEIZEL"
    var mission_label := world.get_node_or_null("MissionLabel")
    if mission_label is CanvasItem:
        (mission_label as CanvasItem).visible = false
    var save_label := world.get_node_or_null("SaveStatusLabel")
    if save_label is CanvasItem:
        (save_label as CanvasItem).visible = false
    var wallet_label := world.get_node_or_null("WalletLabel")
    if wallet_label is CanvasItem:
        (wallet_label as CanvasItem).visible = false
    var minimap := world.get_node_or_null("MiniMap")
    if minimap is CanvasItem:
        (minimap as CanvasItem).visible = false

    print("Direct test spawn: Atomium / Heysel")


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        rotate_y(-event.relative.x * mouse_sensitivity)
        camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
        camera_pivot.rotation.x = clampf(
            camera_pivot.rotation.x,
            deg_to_rad(-60.0),
            deg_to_rad(35.0)
        )

    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_E:
            try_enter_vehicle()
        elif event.keycode == KEY_ESCAPE:
            Input.mouse_mode = (
                Input.MOUSE_MODE_VISIBLE
                if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
                else Input.MOUSE_MODE_CAPTURED
            )


func _physics_process(delta: float) -> void:
    if not is_on_floor():
        velocity.y -= gravity * delta

    var mobile := _mobile_controls()
    var touch_jump: bool = mobile != null and bool(mobile.get("jump_pressed"))
    if (Input.is_key_pressed(KEY_SPACE) or touch_jump) and is_on_floor():
        velocity.y = jump_velocity

    var left: bool = Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_Q)
    var right: bool = Input.is_key_pressed(KEY_D)
    var forward: bool = Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_Z)
    var backward: bool = Input.is_key_pressed(KEY_S)
    var sprint: bool = Input.is_key_pressed(KEY_SHIFT)

    if mobile != null:
        left = left or bool(mobile.get("left_pressed"))
        right = right or bool(mobile.get("right_pressed"))
        forward = forward or bool(mobile.get("forward_pressed"))
        backward = backward or bool(mobile.get("backward_pressed"))
        sprint = sprint or bool(mobile.get("sprint_pressed"))

    var input_2d: Vector2 = Vector2(
        float(right) - float(left),
        float(backward) - float(forward)
    ).limit_length(1.0)

    var move_direction: Vector3 = Vector3(input_2d.x, 0.0, input_2d.y)
    move_direction = move_direction.rotated(Vector3.UP, rotation.y).normalized()

    var target_speed: float = sprint_speed if sprint else walk_speed
    var target_velocity: Vector3 = move_direction * target_speed

    velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
    velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)

    move_and_slide()


func _mobile_controls() -> Node:
    return get_parent().get_node_or_null("MobileControls")


func try_enter_vehicle() -> void:
    var nearest_vehicle: Node3D = null
    var nearest_distance: float = vehicle_interaction_range

    for candidate: Node in get_tree().get_nodes_in_group("vehicle"):
        if not candidate is Node3D:
            continue
        var vehicle: Node3D = candidate as Node3D
        if not vehicle.has_method("enter_driver"):
            continue
        if vehicle.has_method("has_driver") and bool(vehicle.call("has_driver")):
            continue
        var distance: float = global_position.distance_to(vehicle.global_position)
        if distance <= nearest_distance:
            nearest_vehicle = vehicle
            nearest_distance = distance

    if nearest_vehicle != null:
        nearest_vehicle.call("enter_driver", self)


func set_vehicle_mode(enabled: bool) -> void:
    visible = not enabled
    set_physics_process(not enabled)
    set_process_unhandled_input(not enabled)
    velocity = Vector3.ZERO

    if enabled:
        collision_layer = 0
        collision_mask = 0
    else:
        collision_layer = _base_collision_layer
        collision_mask = _base_collision_mask
        camera.current = true
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if DisplayServer.is_touchscreen_available() else Input.MOUSE_MODE_CAPTURED

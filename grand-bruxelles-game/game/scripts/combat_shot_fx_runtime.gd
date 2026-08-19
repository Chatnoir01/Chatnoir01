extends Node

# Visible, game-only shot feedback. Keeps hitscan gameplay unchanged while
# drawing a brief muzzle flash, tracer, impact burst and generic casing.

const SIGNATURE := "combat_shot_fx_v1"
const SWAY_ROOT_PATH := "WeaponGripPivot/WeaponVisualV2SwayRoot"
const MUZZLE_SOCKET_NAME := "CombatMuzzleFxSocket"

var _last_seen_shot_ms := -1
var _tracer_serial := 0
var _impact_serial := 0
var _casing_serial := 0

func _ready() -> void:
    process_priority = 150
    set_process(true)

func _process(_delta: float) -> void:
    var player := _current_player()
    if player == null:
        return
    var shot_ms := int(player.get_meta("combat_weapon_last_shot_ms", -1))
    if shot_ms < 0 or shot_ms == _last_seen_shot_ms:
        return
    _last_seen_shot_ms = shot_ms
    var weapon_id := StringName(player.get_meta("combat_weapon_id", &""))
    if weapon_id == &"":
        return
    spawn_shot_fx(player, weapon_id)

func spawn_shot_fx(player: CharacterBody3D, weapon_id: StringName) -> bool:
    if player == null or not is_instance_valid(player):
        return false
    var holder := player.get_node_or_null("CombatWeaponVisual") as Node3D
    var camera := _player_camera(player)
    if holder == null or camera == null:
        return false
    var muzzle := _ensure_muzzle_socket(holder, weapon_id)
    if muzzle == null:
        return false

    var start := muzzle.global_position
    var direction := -camera.global_transform.basis.z.normalized()
    var end := camera.global_position + direction * visual_range_m(weapon_id)
    var hit := _visual_raycast(player, camera.global_position, end)
    if not hit.is_empty():
        end = hit.get("position", end)

    _spawn_muzzle_flash(muzzle, weapon_id)
    _spawn_tracer(player, start, end, weapon_id)
    if not hit.is_empty():
        _spawn_impact(player, end, hit.get("normal", Vector3.UP), weapon_id)
    _spawn_casing(player, muzzle, weapon_id)

    player.set_meta("combat_fx_signature", SIGNATURE)
    player.set_meta("combat_fx_last_trace_ms", _last_seen_shot_ms)
    player.set_meta("combat_fx_last_trace_start", start)
    player.set_meta("combat_fx_last_trace_end", end)
    return true

func _ensure_muzzle_socket(holder: Node3D, weapon_id: StringName) -> Node3D:
    var sway := holder.get_node_or_null(SWAY_ROOT_PATH) as Node3D
    if sway == null:
        sway = holder
    var socket := sway.get_node_or_null(MUZZLE_SOCKET_NAME) as Node3D
    if socket == null:
        socket = Node3D.new()
        socket.name = MUZZLE_SOCKET_NAME
        sway.add_child(socket)
    socket.position = muzzle_local(weapon_id)
    socket.set_meta("combat_muzzle_weapon_id", weapon_id)
    return socket

func _visual_raycast(player: CharacterBody3D, origin: Vector3, end: Vector3) -> Dictionary:
    if player.get_world_3d() == null:
        return {}
    var query := PhysicsRayQueryParameters3D.create(origin, end)
    query.collision_mask = 0xFFFFFFFF
    query.collide_with_bodies = true
    query.collide_with_areas = true
    query.exclude = [player.get_rid()]
    return player.get_world_3d().direct_space_state.intersect_ray(query)

func _spawn_muzzle_flash(muzzle: Node3D, weapon_id: StringName) -> void:
    var flash := MeshInstance3D.new()
    flash.name = "CombatMuzzleFlash"
    var mesh := SphereMesh.new()
    var size := 0.075 if weapon_id != &"sct8" else 0.11
    mesh.radius = size
    mesh.height = size * 1.35
    mesh.radial_segments = 8
    mesh.rings = 4
    mesh.material = _emissive_material(Color(1.0, 0.68, 0.18, 1.0), 5.0)
    flash.mesh = mesh
    muzzle.add_child(flash)
    flash.position = Vector3(0.0, 0.0, -0.03)

    var light := OmniLight3D.new()
    light.name = "CombatMuzzleLight"
    light.light_color = Color(1.0, 0.52, 0.16, 1.0)
    light.light_energy = 2.8 if weapon_id != &"sct8" else 4.2
    light.omni_range = 2.2 if weapon_id != &"sct8" else 3.0
    muzzle.add_child(light)

    var tween := create_tween()
    tween.tween_property(flash, "scale", Vector3(1.75, 1.75, 1.75), 0.025)
    tween.tween_property(flash, "scale", Vector3(0.18, 0.18, 0.18), 0.035)
    tween.tween_callback(flash.queue_free)
    get_tree().create_timer(0.055).timeout.connect(light.queue_free)

func _spawn_tracer(player: CharacterBody3D, start: Vector3, end: Vector3, weapon_id: StringName) -> void:
    var scene := get_tree().current_scene
    if scene == null:
        return
    var delta := end - start
    var length := delta.length()
    if length < 0.08:
        return
    _tracer_serial += 1
    var tracer := MeshInstance3D.new()
    tracer.name = "CombatTracer_%d" % _tracer_serial
    var mesh := BoxMesh.new()
    var width := 0.018 if weapon_id != &"sct8" else 0.028
    mesh.size = Vector3(width, width, length)
    mesh.material = _emissive_material(Color(1.0, 0.78, 0.30, 0.92), 3.8)
    tracer.mesh = mesh
    scene.add_child(tracer)
    tracer.global_position = start.lerp(end, 0.5)
    tracer.look_at(end, Vector3.UP, true)
    tracer.set_meta("combat_fx_kind", "tracer")
    tracer.set_meta("combat_fx_weapon_id", weapon_id)
    player.set_meta("combat_fx_tracer_count", int(player.get_meta("combat_fx_tracer_count", 0)) + 1)
    get_tree().create_timer(0.075).timeout.connect(tracer.queue_free)

func _spawn_impact(player: CharacterBody3D, position: Vector3, normal_value: Variant, weapon_id: StringName) -> void:
    var scene := get_tree().current_scene
    if scene == null:
        return
    var normal := Vector3.UP
    if normal_value is Vector3:
        normal = normal_value
    _impact_serial += 1
    var root := Node3D.new()
    root.name = "CombatImpactFx_%d" % _impact_serial
    root.global_position = position + normal * 0.018
    scene.add_child(root)

    var spark := MeshInstance3D.new()
    var spark_mesh := SphereMesh.new()
    var radius := 0.055 if weapon_id != &"sct8" else 0.085
    spark_mesh.radius = radius
    spark_mesh.height = radius * 1.35
    spark_mesh.radial_segments = 7
    spark_mesh.rings = 3
    spark_mesh.material = _emissive_material(Color(1.0, 0.45, 0.12, 1.0), 3.2)
    spark.mesh = spark_mesh
    root.add_child(spark)

    var dust := MeshInstance3D.new()
    var dust_mesh := SphereMesh.new()
    dust_mesh.radius = radius * 1.55
    dust_mesh.height = radius * 1.1
    dust_mesh.radial_segments = 7
    dust_mesh.rings = 3
    var dust_mat := StandardMaterial3D.new()
    dust_mat.albedo_color = Color(0.46, 0.42, 0.35, 0.55)
    dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    dust_mesh.material = dust_mat
    dust.mesh = dust_mesh
    root.add_child(dust)

    var tween := create_tween()
    tween.tween_property(root, "scale", Vector3(2.2, 2.2, 2.2), 0.09)
    tween.tween_property(root, "scale", Vector3(0.25, 0.25, 0.25), 0.11)
    tween.tween_callback(root.queue_free)
    player.set_meta("combat_fx_impact_count", int(player.get_meta("combat_fx_impact_count", 0)) + 1)

func _spawn_casing(player: CharacterBody3D, muzzle: Node3D, weapon_id: StringName) -> void:
    var scene := get_tree().current_scene
    if scene == null:
        return
    _casing_serial += 1
    var casing := MeshInstance3D.new()
    casing.name = "CombatCasing_%d" % _casing_serial
    var mesh := BoxMesh.new()
    mesh.size = Vector3(0.014, 0.030, 0.010)
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.58, 0.43, 0.18, 1.0)
    material.metallic = 0.65
    material.roughness = 0.35
    mesh.material = material
    casing.mesh = mesh
    scene.add_child(casing)
    casing.global_position = muzzle.global_position + muzzle.global_transform.basis.x * 0.055
    casing.global_rotation = muzzle.global_rotation
    var side := muzzle.global_transform.basis.x.normalized()
    var target := casing.global_position + side * (0.30 if weapon_id == &"sct8" else 0.22) + Vector3.UP * 0.12
    var tween := create_tween()
    tween.tween_property(casing, "global_position", target, 0.16)
    tween.parallel().tween_property(casing, "rotation:z", casing.rotation.z + 5.5, 0.16)
    tween.tween_property(casing, "global_position:y", target.y - 0.24, 0.18)
    tween.tween_callback(casing.queue_free)
    player.set_meta("combat_fx_casing_count", int(player.get_meta("combat_fx_casing_count", 0)) + 1)

func _emissive_material(color: Color, energy: float) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.emission_enabled = true
    material.emission = color
    material.emission_energy_multiplier = energy
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    return material

func _current_player() -> CharacterBody3D:
    var scene := get_tree().current_scene
    if scene == null:
        return null
    return scene.get_node_or_null("Player") as CharacterBody3D

func _player_camera(player: CharacterBody3D) -> Camera3D:
    var camera := player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if camera != null:
        return camera
    for node: Node in player.find_children("*", "Camera3D", true, false):
        if node is Camera3D:
            return node as Camera3D
    return null

static func muzzle_local(weapon_id: StringName) -> Vector3:
    match weapon_id:
        &"bx9":
            return Vector3(0.0, 0.02, -0.49)
        &"cbr4":
            return Vector3(0.0, 0.015, -1.08)
        &"sct8":
            return Vector3(0.0, 0.0, -1.20)
        _:
            return Vector3(0.0, 0.0, -0.75)

static func visual_range_m(weapon_id: StringName) -> float:
    match weapon_id:
        &"cbr4":
            return 94.0
        &"sct8":
            return 38.0
        _:
            return 62.0

extends Node

# Visual-only upgrade layer for the fictional Grand Bruxelles arsenal.
# It deliberately uses primitive Godot meshes so the game stays asset/license clean.

const SIGNATURE := "combat_weapon_visual_v2"
const SWAY_ROOT_NAME := "WeaponVisualV2SwayRoot"

var _bound_holder_id := 0
var _bound_weapon_id: StringName = &""
var _sway_phase := 0.0

func _ready() -> void:
    set_process(true)

func _process(delta: float) -> void:
    var player := _current_player()
    if player == null:
        _clear_binding()
        return
    var holder := player.get_node_or_null("CombatWeaponVisual") as Node3D
    if holder == null:
        _clear_binding()
        return
    var weapon_id := StringName(player.get_meta("combat_weapon_id", &""))
    if weapon_id == &"":
        _clear_binding()
        return
    if holder.get_instance_id() != _bound_holder_id or weapon_id != _bound_weapon_id or String(holder.get_meta("visual_upgrade_signature", "")) != SIGNATURE:
        upgrade_weapon_visual(holder, weapon_id)
        _bound_holder_id = holder.get_instance_id()
        _bound_weapon_id = weapon_id
    _animate_weapon(holder, player, delta)

func upgrade_weapon_visual(holder: Node3D, weapon_id: StringName) -> int:
    if holder == null or not is_instance_valid(holder):
        return 0
    var old_root := holder.get_node_or_null(SWAY_ROOT_NAME)
    if old_root != null:
        old_root.queue_free()

    var sway_root := Node3D.new()
    sway_root.name = SWAY_ROOT_NAME
    holder.add_child(sway_root)

    # Move the original lightweight receiver/grip meshes under one presentation root.
    # This keeps the arsenal runtime authoritative while letting this layer add sway/reload motion.
    var existing_children := holder.get_children().duplicate()
    for child: Node in existing_children:
        if child == sway_root or not child is Node3D:
            continue
        child.reparent(sway_root, true)

    var dark := _material(Color(0.045, 0.050, 0.056, 1.0), 0.42, 0.32)
    var steel := _material(Color(0.115, 0.125, 0.135, 1.0), 0.28, 0.50)
    var polymer := _material(Color(0.085, 0.082, 0.074, 1.0), 0.76, 0.04)
    var accent := _material(Color(0.20, 0.22, 0.23, 1.0), 0.52, 0.16)

    var part_count := 0
    match weapon_id:
        &"bx9":
            part_count += _build_compact(sway_root, dark, steel, polymer, accent)
        &"cbr4":
            part_count += _build_carbine(sway_root, dark, steel, polymer, accent)
        &"sct8":
            part_count += _build_scatter(sway_root, dark, steel, polymer, accent)
        _:
            return 0

    holder.set_meta("visual_upgrade_signature", SIGNATURE)
    holder.set_meta("visual_upgrade_weapon_id", weapon_id)
    holder.set_meta("visual_upgrade_part_count", part_count)
    return part_count

func _build_compact(root: Node3D, dark: Material, steel: Material, polymer: Material, accent: Material) -> int:
    var count := 0
    count += _add_box(root, "CompactSlide", Vector3(0.145, 0.105, 0.46), Vector3(0.0, 0.055, -0.17), steel)
    count += _add_cylinder(root, "CompactBarrel", 0.026, 0.26, Vector3(0.0, 0.045, -0.48), dark)
    count += _add_box(root, "CompactMagazine", Vector3(0.105, 0.24, 0.105), Vector3(0.0, -0.255, -0.035), polymer, Vector3(-8.0, 0.0, 0.0))
    count += _add_box(root, "CompactTriggerGuardFront", Vector3(0.075, 0.035, 0.105), Vector3(0.0, -0.105, -0.13), accent)
    count += _add_box(root, "CompactFrontSight", Vector3(0.032, 0.035, 0.038), Vector3(0.0, 0.13, -0.35), dark)
    count += _add_box(root, "CompactRearSight", Vector3(0.072, 0.035, 0.035), Vector3(0.0, 0.13, -0.02), dark)
    count += _add_box(root, "CompactGripBackstrap", Vector3(0.03, 0.23, 0.10), Vector3(0.0, -0.22, 0.04), accent, Vector3(-8.0, 0.0, 0.0))
    return count

func _build_carbine(root: Node3D, dark: Material, steel: Material, polymer: Material, accent: Material) -> int:
    var count := 0
    count += _add_box(root, "CarbineUpper", Vector3(0.17, 0.14, 0.58), Vector3(0.0, 0.06, -0.29), dark)
    count += _add_cylinder(root, "CarbineBarrel", 0.028, 0.54, Vector3(0.0, 0.045, -0.86), steel)
    count += _add_cylinder(root, "CarbineMuzzle", 0.043, 0.12, Vector3(0.0, 0.045, -1.18), dark)
    count += _add_box(root, "CarbineHandguard", Vector3(0.19, 0.16, 0.48), Vector3(0.0, 0.015, -0.69), polymer)
    count += _add_box(root, "CarbineMagazine", Vector3(0.12, 0.32, 0.16), Vector3(0.0, -0.27, -0.22), polymer, Vector3(-10.0, 0.0, 0.0))
    count += _add_box(root, "CarbineStockBeam", Vector3(0.10, 0.11, 0.42), Vector3(0.0, 0.00, 0.43), accent)
    count += _add_box(root, "CarbineShoulderPad", Vector3(0.18, 0.32, 0.10), Vector3(0.0, -0.01, 0.67), polymer)
    count += _add_box(root, "CarbineFrontSight", Vector3(0.05, 0.105, 0.045), Vector3(0.0, 0.18, -0.73), dark)
    count += _add_box(root, "CarbineRearSight", Vector3(0.07, 0.095, 0.05), Vector3(0.0, 0.18, -0.13), dark)
    count += _add_box(root, "CarbineRail", Vector3(0.075, 0.035, 0.60), Vector3(0.0, 0.145, -0.34), steel)
    return count

func _build_scatter(root: Node3D, dark: Material, steel: Material, polymer: Material, accent: Material) -> int:
    var count := 0
    count += _add_box(root, "ScatterReceiver", Vector3(0.19, 0.17, 0.55), Vector3(0.0, 0.04, -0.26), dark)
    count += _add_cylinder(root, "ScatterBarrel", 0.038, 0.82, Vector3(0.0, 0.075, -0.88), steel)
    count += _add_cylinder(root, "ScatterTube", 0.043, 0.62, Vector3(0.0, -0.025, -0.79), dark)
    count += _add_box(root, "ScatterForegrip", Vector3(0.18, 0.16, 0.34), Vector3(0.0, -0.035, -0.67), polymer)
    count += _add_box(root, "ScatterStockNeck", Vector3(0.13, 0.15, 0.34), Vector3(0.0, -0.02, 0.32), accent)
    count += _add_box(root, "ScatterStock", Vector3(0.18, 0.26, 0.46), Vector3(0.0, -0.06, 0.64), polymer)
    count += _add_box(root, "ScatterBeadSight", Vector3(0.035, 0.045, 0.035), Vector3(0.0, 0.15, -1.17), steel)
    count += _add_box(root, "ScatterLoadingPort", Vector3(0.11, 0.035, 0.16), Vector3(0.0, -0.10, -0.20), steel)
    return count

func _animate_weapon(holder: Node3D, player: CharacterBody3D, delta: float) -> void:
    var sway_root := holder.get_node_or_null(SWAY_ROOT_NAME) as Node3D
    if sway_root == null:
        return
    var speed := Vector2(player.velocity.x, player.velocity.z).length()
    var aiming := bool(player.get_meta("combat_weapon_aiming", false))
    var reloading := bool(player.get_meta("combat_weapon_reloading", false))
    _sway_phase += delta * (3.2 + minf(speed, 8.0) * 1.25)
    var amplitude := 0.004 if aiming else 0.010
    amplitude += minf(speed / 8.0, 1.0) * (0.006 if aiming else 0.018)
    var target_position := Vector3(
        sin(_sway_phase) * amplitude,
        absf(cos(_sway_phase * 2.0)) * amplitude * 0.55,
        0.0
    )
    var target_rotation := Vector3(
        deg_to_rad(sin(_sway_phase * 0.85) * (0.35 if aiming else 0.8)),
        deg_to_rad(sin(_sway_phase * 0.55) * (0.25 if aiming else 0.65)),
        deg_to_rad(sin(_sway_phase) * (0.30 if aiming else 0.9))
    )
    if reloading:
        target_position += Vector3(0.11, -0.14, 0.08)
        target_rotation += Vector3(deg_to_rad(-24.0), deg_to_rad(12.0), deg_to_rad(18.0))
    var blend := clampf(delta * (16.0 if reloading else 10.0), 0.0, 1.0)
    sway_root.position = sway_root.position.lerp(target_position, blend)
    sway_root.rotation = sway_root.rotation.lerp(target_rotation, blend)

func _add_box(parent: Node3D, name_value: String, size: Vector3, pos: Vector3, material: Material, rotation_degrees_value: Vector3 = Vector3.ZERO) -> int:
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh.material = material
    var instance := MeshInstance3D.new()
    instance.name = name_value
    instance.mesh = mesh
    instance.position = pos
    instance.rotation_degrees = rotation_degrees_value
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    parent.add_child(instance)
    return 1

func _add_cylinder(parent: Node3D, name_value: String, radius: float, length: float, pos: Vector3, material: Material) -> int:
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = length
    mesh.radial_segments = 12
    mesh.rings = 1
    mesh.material = material
    var instance := MeshInstance3D.new()
    instance.name = name_value
    instance.mesh = mesh
    instance.position = pos
    instance.rotation_degrees = Vector3(90.0, 0.0, 0.0)
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    parent.add_child(instance)
    return 1

func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = metallic
    return material

func _current_player() -> CharacterBody3D:
    var scene := get_tree().current_scene
    if scene == null:
        return null
    return scene.get_node_or_null("Player") as CharacterBody3D

func _clear_binding() -> void:
    _bound_holder_id = 0
    _bound_weapon_id = &""

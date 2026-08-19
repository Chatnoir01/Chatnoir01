extends Node

# Visual-only upgrade layer for the fictional Grand Bruxelles arsenal.
# V3 keeps the weapon grip locked to the player's real right hand instead of
# leaving the weapon at a fixed Player-root offset.

const SIGNATURE := "combat_weapon_visual_v3_hand_mount"
const SWAY_ROOT_NAME := "WeaponVisualV2SwayRoot"
const GRIP_PIVOT_NAME := "WeaponGripPivot"
const RIGHT_HAND_SOCKET_NAME := "WeaponRightHandGripSocket"
const SUPPORT_SOCKET_NAME := "WeaponSupportGripSocket"
const HAND_LOCK_EPSILON_M := 0.025

var _bound_holder_id := 0
var _bound_weapon_id: StringName = &""
var _sway_phase := 0.0
var _last_shot_ms := -1
var _visual_recoil_deg := 0.0

func _ready() -> void:
    set_process(true)

func _process(delta: float) -> void:
    var player := _current_player()
    if player == null:
        _clear_binding()
        return
    var holder := player.get_node_or_null("CombatWeaponVisual") as Node3D
    if holder == null:
        player.set_meta("combat_weapon_grip_locked", false)
        _clear_binding()
        return
    var weapon_id := StringName(player.get_meta("combat_weapon_id", &""))
    if weapon_id == &"":
        player.set_meta("combat_weapon_grip_locked", false)
        _clear_binding()
        return
    if holder.get_instance_id() != _bound_holder_id or weapon_id != _bound_weapon_id or String(holder.get_meta("visual_upgrade_signature", "")) != SIGNATURE:
        upgrade_weapon_visual(holder, weapon_id)
        _bound_holder_id = holder.get_instance_id()
        _bound_weapon_id = weapon_id
        _last_shot_ms = -1
        _visual_recoil_deg = 0.0

    mount_weapon_to_hand(holder, player, weapon_id)
    _animate_weapon(holder, player, delta)
    _publish_support_target(holder, player, weapon_id)

func upgrade_weapon_visual(holder: Node3D, weapon_id: StringName) -> int:
    if holder == null or not is_instance_valid(holder):
        return 0

    _flatten_previous_visual_root(holder)

    var right_grip_local := right_hand_grip_local(weapon_id)
    var right_socket := Node3D.new()
    right_socket.name = RIGHT_HAND_SOCKET_NAME
    right_socket.position = right_grip_local
    holder.add_child(right_socket)

    var grip_pivot := Node3D.new()
    grip_pivot.name = GRIP_PIVOT_NAME
    grip_pivot.position = right_grip_local
    holder.add_child(grip_pivot)

    var sway_root := Node3D.new()
    sway_root.name = SWAY_ROOT_NAME
    sway_root.position = -right_grip_local
    grip_pivot.add_child(sway_root)

    # Keep all visible weapon geometry under a pivot whose origin is the real
    # grip point. Rotations/reload/recoil now happen around the hand instead of
    # translating the whole weapon away from it.
    var existing_children := holder.get_children().duplicate()
    for child: Node in existing_children:
        if child == right_socket or child == grip_pivot or not child is Node3D:
            continue
        (child as Node3D).reparent(sway_root, true)

    var support_socket := Node3D.new()
    support_socket.name = SUPPORT_SOCKET_NAME
    support_socket.position = support_grip_local(weapon_id)
    sway_root.add_child(support_socket)

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
    holder.set_meta("visual_upgrade_hand_mount", true)
    holder.set_meta("visual_upgrade_grip_local", right_grip_local)
    holder.set_meta("visual_upgrade_support_local", support_grip_local(weapon_id))
    return part_count

func mount_weapon_to_hand(holder: Node3D, player: CharacterBody3D, weapon_id: StringName) -> bool:
    if holder == null or player == null or not is_instance_valid(holder) or not is_instance_valid(player):
        return false
    var anchor := resolve_right_hand_anchor(player)
    if not bool(anchor.get("found", false)):
        holder.set_meta("weapon_hand_mount_locked", false)
        player.set_meta("combat_weapon_grip_locked", false)
        player.set_meta("combat_weapon_hand_gap_m", 999.0)
        player.set_meta("combat_weapon_mount_source", "unresolved")
        return false

    var hand_transform: Transform3D = anchor.get("transform", Transform3D.IDENTITY)
    holder.rotation_degrees = weapon_mount_rotation_degrees(weapon_id)
    holder.global_position = hand_transform.origin

    var right_socket := holder.get_node_or_null(RIGHT_HAND_SOCKET_NAME) as Node3D
    if right_socket == null:
        holder.set_meta("weapon_hand_mount_locked", false)
        player.set_meta("combat_weapon_grip_locked", false)
        return false

    holder.global_position += hand_transform.origin - right_socket.global_position
    var gap_m := right_socket.global_position.distance_to(hand_transform.origin)
    var locked := gap_m <= HAND_LOCK_EPSILON_M
    var source := String(anchor.get("source", "unknown"))
    holder.set_meta("weapon_hand_mount_locked", locked)
    holder.set_meta("weapon_hand_mount_source", source)
    holder.set_meta("weapon_hand_gap_m", gap_m)
    player.set_meta("combat_weapon_grip_locked", locked)
    player.set_meta("combat_weapon_mount_source", source)
    player.set_meta("combat_weapon_hand_gap_m", gap_m)
    return locked

func resolve_right_hand_anchor(player: CharacterBody3D) -> Dictionary:
    if player == null or not is_instance_valid(player):
        return {"found": false}
    var visual := player.get_node_or_null("VisualUpgrade")
    if visual == null:
        return {"found": false}

    var skeleton_match := _find_right_hand_skeleton(visual)
    if not skeleton_match.is_empty():
        var skeleton := skeleton_match.get("skeleton") as Skeleton3D
        var bone_index := int(skeleton_match.get("bone_index", -1))
        if skeleton != null and bone_index >= 0:
            var bone_pose := skeleton.get_bone_global_pose(bone_index)
            var world_pose := skeleton.global_transform * bone_pose
            return {
                "found": true,
                "transform": world_pose,
                "source": "skeleton:%s" % skeleton.get_bone_name(bone_index),
            }

    var right_hand := _find_right_hand_node(visual)
    if right_hand != null:
        return {
            "found": true,
            "transform": right_hand.global_transform,
            "source": "node:%s" % right_hand.name,
        }

    return {"found": false}

func _find_right_hand_skeleton(node: Node) -> Dictionary:
    if node is Skeleton3D:
        var skeleton := node as Skeleton3D
        var bone_index := _find_right_hand_bone(skeleton)
        if bone_index >= 0:
            return {"skeleton": skeleton, "bone_index": bone_index}
    for child: Node in node.get_children():
        var found := _find_right_hand_skeleton(child)
        if not found.is_empty():
            return found
    return {}

func _find_right_hand_bone(skeleton: Skeleton3D) -> int:
    if skeleton == null:
        return -1
    for bone_index: int in range(skeleton.get_bone_count()):
        if is_right_hand_name(String(skeleton.get_bone_name(bone_index))):
            return bone_index
    return -1

func _find_right_hand_node(node: Node) -> Node3D:
    if node is Node3D and is_right_hand_name(String(node.name)):
        return node as Node3D
    for child: Node in node.get_children():
        var found := _find_right_hand_node(child)
        if found != null:
            return found
    return null

static func is_right_hand_name(value: String) -> bool:
    var compact := value.to_lower()
    for token: String in [":", "_", "-", ".", " "]:
        compact = compact.replace(token, "")
    return compact.ends_with("righthand") or compact.ends_with("handr") or compact == "rhand"

static func right_hand_grip_local(weapon_id: StringName) -> Vector3:
    match weapon_id:
        &"bx9":
            return Vector3(0.0, -0.18, -0.02)
        &"cbr4":
            return Vector3(0.0, -0.18, -0.05)
        &"sct8":
            return Vector3(0.0, -0.18, -0.05)
        _:
            return Vector3(0.0, -0.18, -0.05)

static func support_grip_local(weapon_id: StringName) -> Vector3:
    match weapon_id:
        &"bx9":
            return Vector3(-0.02, -0.10, -0.16)
        &"cbr4":
            return Vector3(0.0, -0.01, -0.69)
        &"sct8":
            return Vector3(0.0, -0.03, -0.67)
        _:
            return Vector3.ZERO

static func weapon_mount_rotation_degrees(weapon_id: StringName) -> Vector3:
    match weapon_id:
        &"bx9":
            return Vector3(-7.0, 0.0, -5.0)
        &"cbr4":
            return Vector3(-4.0, 0.0, -2.0)
        &"sct8":
            return Vector3(-5.5, 0.0, -2.5)
        _:
            return Vector3(-5.0, 0.0, -4.0)

static func visual_recoil_angle_deg(weapon_id: StringName) -> float:
    match weapon_id:
        &"bx9":
            return 3.2
        &"cbr4":
            return 2.4
        &"sct8":
            return 6.2
        _:
            return 3.0

func _flatten_previous_visual_root(holder: Node3D) -> void:
    var direct_sway := holder.get_node_or_null(SWAY_ROOT_NAME) as Node3D
    if direct_sway != null:
        var old_children := direct_sway.get_children().duplicate()
        for child: Node in old_children:
            if child is Node3D:
                (child as Node3D).reparent(holder, true)
        direct_sway.free()

    var old_pivot := holder.get_node_or_null(GRIP_PIVOT_NAME) as Node3D
    if old_pivot != null:
        var nested_sway := old_pivot.get_node_or_null(SWAY_ROOT_NAME) as Node3D
        if nested_sway != null:
            var nested_children := nested_sway.get_children().duplicate()
            for child: Node in nested_children:
                if child is Node3D and child.name != SUPPORT_SOCKET_NAME:
                    (child as Node3D).reparent(holder, true)
        old_pivot.free()

    for socket_name: String in [RIGHT_HAND_SOCKET_NAME, SUPPORT_SOCKET_NAME]:
        var old_socket := holder.find_child(socket_name, true, false)
        if old_socket != null:
            old_socket.free()

func _publish_support_target(holder: Node3D, player: CharacterBody3D, weapon_id: StringName) -> void:
    var support_socket := holder.find_child(SUPPORT_SOCKET_NAME, true, false) as Node3D
    if support_socket == null:
        player.set_meta("combat_weapon_support_grip_ready", false)
        return
    player.set_meta("combat_weapon_support_grip_ready", true)
    player.set_meta("combat_weapon_support_grip_world", support_socket.global_position)
    player.set_meta("combat_weapon_support_grip_weapon_id", weapon_id)

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
    var sway_root := holder.find_child(SWAY_ROOT_NAME, true, false) as Node3D
    if sway_root == null:
        return

    var shot_ms := int(player.get_meta("combat_weapon_last_shot_ms", -1))
    if shot_ms > _last_shot_ms:
        _last_shot_ms = shot_ms
        _visual_recoil_deg = maxf(_visual_recoil_deg, visual_recoil_angle_deg(_bound_weapon_id))
    _visual_recoil_deg = move_toward(_visual_recoil_deg, 0.0, delta * 38.0)

    var speed := Vector2(player.velocity.x, player.velocity.z).length()
    var aiming := bool(player.get_meta("combat_weapon_aiming", false))
    var reloading := bool(player.get_meta("combat_weapon_reloading", false))
    _sway_phase += delta * (3.2 + minf(speed, 8.0) * 1.25)

    var target_rotation := Vector3(
        deg_to_rad(sin(_sway_phase * 0.85) * (0.25 if aiming else 0.65) + _visual_recoil_deg),
        deg_to_rad(sin(_sway_phase * 0.55) * (0.18 if aiming else 0.50)),
        deg_to_rad(sin(_sway_phase) * (0.22 if aiming else 0.70))
    )
    if reloading:
        target_rotation += Vector3(deg_to_rad(-24.0), deg_to_rad(12.0), deg_to_rad(18.0))

    var blend := clampf(delta * (18.0 if reloading else 12.0), 0.0, 1.0)
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
    _last_shot_ms = -1
    _visual_recoil_deg = 0.0

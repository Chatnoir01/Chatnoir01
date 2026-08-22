extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const OUT_PATH := "res://artifacts/qa/combat_native_weapon/crossbow_geometry_probe.json"
const CROSSBOW_NODE := "2H_Crossbow"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("COMBAT_NATIVE_CROSSBOW_GEOMETRY_PROBE_FAIL: %s" % message)
    quit(1)

func _wait_frames(count: int) -> void:
    for _i: int in range(count):
        await process_frame

func _disable_dynamic(node: Node, player: CharacterBody3D) -> void:
    if node != player and not player.is_ancestor_of(node) and (node is NpcAgent or node is CharacterBody3D or node is RigidBody3D):
        node.set_process(false)
        node.set_physics_process(false)
        if node is Node3D:
            (node as Node3D).visible = false
        return
    for child: Node in node.get_children():
        _disable_dynamic(child, player)

func _wait_equipped(player: CharacterBody3D) -> bool:
    for _attempt: int in range(300):
        await process_frame
        if StringName(player.get_meta("combat_weapon_id", &"")) != &"crossbow":
            continue
        if StringName(player.get_meta("combat_weapon_state", &"")) != &"equipped":
            continue
        if bool(player.get_meta("combat_weapon_switching", true)):
            continue
        return true
    return false

func _wait_post_ik(player: CharacterBody3D) -> bool:
    for _attempt: int in range(300):
        await process_frame
        if bool(player.get_meta("combat_carry_ik_locked", false)) and bool(player.get_meta("combat_support_ik_locked", false)):
            return true
    return false

func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D:
        var mesh_instance := node as MeshInstance3D
        if mesh_instance.mesh != null and mesh_instance.visible:
            out.append(mesh_instance)
    for child: Node in node.get_children():
        _collect_meshes(child, out)

func _vec(value: Vector3) -> Array[float]:
    return [value.x, value.y, value.z]

func _basis_rows(basis: Basis) -> Array:
    return [
        _vec(basis.x),
        _vec(basis.y),
        _vec(basis.z),
    ]

func _parent_chain(node: Node, stop: Node) -> Array:
    var chain: Array = []
    var current: Node = node
    while current != null:
        chain.append({
            "name": String(current.name),
            "class": current.get_class(),
            "path": String(current.get_path()),
        })
        if current == stop:
            break
        current = current.get_parent()
    return chain

func _mesh_geometry_report(crossbow: Node3D) -> Dictionary:
    var meshes: Array[MeshInstance3D] = []
    _collect_meshes(crossbow, meshes)
    var min_local := Vector3(INF, INF, INF)
    var max_local := Vector3(-INF, -INF, -INF)
    var mesh_items: Array = []
    var point_count := 0
    var inverse := crossbow.global_transform.affine_inverse()
    for mesh_instance: MeshInstance3D in meshes:
        var aabb := mesh_instance.get_aabb()
        var mesh_min := Vector3(INF, INF, INF)
        var mesh_max := Vector3(-INF, -INF, -INF)
        for endpoint: int in range(8):
            var world_point := mesh_instance.global_transform * aabb.get_endpoint(endpoint)
            var local_point := inverse * world_point
            min_local = min_local.min(local_point)
            max_local = max_local.max(local_point)
            mesh_min = mesh_min.min(local_point)
            mesh_max = mesh_max.max(local_point)
            point_count += 1
        mesh_items.append({
            "name": String(mesh_instance.name),
            "class": mesh_instance.get_class(),
            "path": String(mesh_instance.get_path()),
            "local_min": _vec(mesh_min),
            "local_max": _vec(mesh_max),
            "local_size": _vec(mesh_max - mesh_min),
        })
    return {
        "mesh_count": meshes.size(),
        "point_count": point_count,
        "local_min": _vec(min_local),
        "local_max": _vec(max_local),
        "local_size": _vec(max_local - min_local),
        "local_center": _vec((min_local + max_local) * 0.5),
        "meshes": mesh_items,
    }

func _run() -> void:
    if change_scene_to_file(MAIN_SCENE) != OK:
        _fail("main scene load failed")
        return

    var player: CharacterBody3D = null
    for _attempt: int in range(360):
        await process_frame
        if current_scene != null:
            player = current_scene.get_node_or_null("Player") as CharacterBody3D
            if player != null:
                break
    if player == null:
        _fail("player unavailable")
        return

    var arsenal := root.get_node_or_null("PlayerCombatArsenalRuntime")
    var grip_runtime := root.get_node_or_null("CombatWeaponVisualUpgradeRuntime")
    if arsenal == null or not arsenal.has_method("equip_weapon"):
        _fail("arsenal unavailable")
        return
    if grip_runtime == null or not grip_runtime.has_method("resolve_right_hand_anchor"):
        _fail("grip runtime unavailable")
        return

    player.velocity = Vector3.ZERO
    player.set_physics_process(false)
    _disable_dynamic(root, player)
    if not bool(arsenal.call("equip_weapon", player, &"crossbow")):
        _fail("crossbow equip rejected")
        return
    if not await _wait_equipped(player):
        _fail("crossbow never equipped")
        return
    if not await _wait_post_ik(player):
        _fail("crossbow IK never locked")
        return
    await _wait_frames(24)

    var crossbow := player.find_child(CROSSBOW_NODE, true, false) as Node3D
    if crossbow == null or not crossbow.visible:
        _fail("visible 2H_Crossbow unavailable")
        return

    var carry_hand_world: Vector3 = player.get_meta("combat_carry_hand_world", Vector3.ZERO)
    var support_hand_world: Vector3 = player.get_meta("combat_support_hand_world", Vector3.ZERO)
    var carry_desired_world: Vector3 = player.get_meta("combat_carry_ik_desired_hand_world", Vector3.ZERO)
    var support_desired_world: Vector3 = player.get_meta("combat_support_ik_desired_hand_world", Vector3.ZERO)
    var raw_anchor_variant: Variant = grip_runtime.call("resolve_right_hand_anchor", player)
    var raw_anchor_world := Vector3.ZERO
    var raw_anchor_source := ""
    if raw_anchor_variant is Dictionary:
        var raw_anchor := raw_anchor_variant as Dictionary
        raw_anchor_world = (raw_anchor.get("transform", Transform3D.IDENTITY) as Transform3D).origin
        raw_anchor_source = String(raw_anchor.get("source", ""))

    var report := {
        "crossbow": {
            "name": String(crossbow.name),
            "class": crossbow.get_class(),
            "path": String(crossbow.get_path()),
            "parent_chain": _parent_chain(crossbow, player),
            "global_origin": _vec(crossbow.global_position),
            "global_basis": _basis_rows(crossbow.global_transform.basis),
            "scale": _vec(crossbow.scale),
            "geometry": _mesh_geometry_report(crossbow),
        },
        "hands": {
            "carry_post_ik_world": _vec(carry_hand_world),
            "support_post_ik_world": _vec(support_hand_world),
            "carry_desired_world": _vec(carry_desired_world),
            "support_desired_world": _vec(support_desired_world),
            "raw_anchor_world": _vec(raw_anchor_world),
            "raw_anchor_source": raw_anchor_source,
            "carry_post_ik_local": _vec(crossbow.to_local(carry_hand_world)),
            "support_post_ik_local": _vec(crossbow.to_local(support_hand_world)),
            "carry_desired_local": _vec(crossbow.to_local(carry_desired_world)),
            "support_desired_local": _vec(crossbow.to_local(support_desired_world)),
            "raw_anchor_local": _vec(crossbow.to_local(raw_anchor_world)),
            "raw_vs_post_ik_gap_m": raw_anchor_world.distance_to(carry_hand_world),
            "crossbow_origin_vs_post_ik_hand_gap_m": crossbow.global_position.distance_to(carry_hand_world),
        },
        "runtime": {
            "presentation_signature": String(player.get_meta("combat_native_weapon_presentation_signature", "")),
            "basis_mode": String(player.get_meta("combat_native_crossbow_basis_mode", "")),
            "reported_hand_region_gap_m": float(player.get_meta("combat_native_crossbow_hand_region_gap_m", 999.0)),
            "carry_gap_m": float(player.get_meta("combat_carry_hand_gap_m", 999.0)),
            "support_gap_m": float(player.get_meta("combat_support_hand_gap_m", 999.0)),
        },
    }

    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/qa/combat_native_weapon"))
    var file := FileAccess.open(OUT_PATH, FileAccess.WRITE)
    if file == null:
        _fail("probe report write failed")
        return
    file.store_string(JSON.stringify(report, "  "))
    file.close()
    print("COMBAT_NATIVE_CROSSBOW_GEOMETRY_PROBE_OK")
    print(JSON.stringify(report))
    quit(0)

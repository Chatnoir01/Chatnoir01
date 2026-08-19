extends SceneTree

const VISUAL_RUNTIME := preload("res://game/scripts/combat_weapon_visual_upgrade_runtime.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("COMBAT_WEAPON_VISUAL_UPGRADE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var runtime := VISUAL_RUNTIME.new()
    root.add_child(runtime)

    var expectations: Dictionary = {
        &"bx9": 7,
        &"cbr4": 10,
        &"sct8": 8,
    }
    for raw_weapon_id: Variant in expectations.keys():
        var weapon_id := StringName(raw_weapon_id)
        var holder := Node3D.new()
        holder.name = "CombatWeaponVisual_%s" % String(weapon_id)
        root.add_child(holder)
        var base_receiver := MeshInstance3D.new()
        base_receiver.name = "LegacyReceiver"
        holder.add_child(base_receiver)

        var built := int(runtime.call("upgrade_weapon_visual", holder, weapon_id))
        if built < int(expectations[weapon_id]):
            _fail("%s built only %d detail parts" % [weapon_id, built]); return
        if String(holder.get_meta("visual_upgrade_signature", "")) != VISUAL_RUNTIME.SIGNATURE:
            _fail("%s visual signature missing" % weapon_id); return
        if int(holder.get_meta("visual_upgrade_part_count", 0)) != built:
            _fail("%s part-count metadata drifted" % weapon_id); return
        if not bool(holder.get_meta("visual_upgrade_hand_mount", false)):
            _fail("%s hand-mount signature missing" % weapon_id); return

        var pivot := holder.get_node_or_null(VISUAL_RUNTIME.GRIP_PIVOT_NAME) as Node3D
        if pivot == null:
            _fail("%s grip pivot missing" % weapon_id); return
        var right_socket := holder.get_node_or_null(VISUAL_RUNTIME.RIGHT_HAND_SOCKET_NAME) as Node3D
        if right_socket == null:
            _fail("%s right-hand grip socket missing" % weapon_id); return
        var sway_root := holder.find_child(VISUAL_RUNTIME.SWAY_ROOT_NAME, true, false) as Node3D
        if sway_root == null:
            _fail("%s sway root missing" % weapon_id); return
        if sway_root.get_parent() != pivot:
            _fail("%s sway root must rotate around grip pivot" % weapon_id); return
        if sway_root.get_node_or_null("LegacyReceiver") == null:
            _fail("%s legacy receiver was not preserved under sway root" % weapon_id); return
        var support_socket := holder.find_child(VISUAL_RUNTIME.SUPPORT_SOCKET_NAME, true, false) as Node3D
        if support_socket == null:
            _fail("%s support-hand target missing" % weapon_id); return
        if sway_root.get_child_count() < built + 2:
            _fail("%s visible child count smaller than recipe + grip target" % weapon_id); return
        holder.queue_free()

    if not VISUAL_RUNTIME.is_right_hand_name("mixamorig:RightHand"):
        _fail("Mixamo right-hand alias must resolve"); return
    if not VISUAL_RUNTIME.is_right_hand_name("hand.R"):
        _fail("hand.R alias must resolve"); return
    if VISUAL_RUNTIME.is_right_hand_name("LeftHand"):
        _fail("left hand must never resolve as the weapon hand"); return

    # Procedural/fallback character: the weapon socket must remain on the hand
    # when the hand moves instead of staying at a fixed Player-root offset.
    var player := CharacterBody3D.new()
    player.name = "GripMountTestPlayer"
    root.add_child(player)
    var visual := Node3D.new()
    visual.name = "VisualUpgrade"
    player.add_child(visual)
    var right_hand := Node3D.new()
    right_hand.name = "RightHand"
    right_hand.position = Vector3(0.34, 1.08, -0.12)
    visual.add_child(right_hand)
    var mounted_holder := Node3D.new()
    mounted_holder.name = "CombatWeaponVisual"
    mounted_holder.scale = Vector3(0.78, 0.82, 0.66)
    player.add_child(mounted_holder)
    var mounted_receiver := MeshInstance3D.new()
    mounted_receiver.name = "LegacyReceiver"
    mounted_holder.add_child(mounted_receiver)
    runtime.upgrade_weapon_visual(mounted_holder, &"bx9")
    if not runtime.mount_weapon_to_hand(mounted_holder, player, &"bx9"):
        _fail("fallback RightHand mount did not lock"); return
    var mounted_socket := mounted_holder.get_node_or_null(VISUAL_RUNTIME.RIGHT_HAND_SOCKET_NAME) as Node3D
    if mounted_socket == null:
        _fail("mounted grip socket disappeared"); return
    if mounted_socket.global_position.distance_to(right_hand.global_position) > 0.001:
        _fail("weapon grip is not coincident with fallback hand"); return
    var first_holder_position := mounted_holder.global_position
    right_hand.position += Vector3(0.11, 0.06, -0.09)
    if not runtime.mount_weapon_to_hand(mounted_holder, player, &"bx9"):
        _fail("moving fallback hand broke the grip lock"); return
    if mounted_socket.global_position.distance_to(right_hand.global_position) > 0.001:
        _fail("weapon did not follow moving fallback hand"); return
    if mounted_holder.global_position.distance_to(first_holder_position) < 0.05:
        _fail("weapon holder stayed at a fixed player-root position"); return
    if String(player.get_meta("combat_weapon_mount_source", "")) != "node:RightHand":
        _fail("fallback mount source metadata is wrong"); return
    if float(player.get_meta("combat_weapon_hand_gap_m", 999.0)) > 0.001:
        _fail("fallback hand-gap metadata is not locked"); return

    # Authored-character path: prove that a legal Godot hand bone resolves.
    # Mixamo-style names remain covered separately by is_right_hand_name() above;
    # Skeleton3D.add_bone itself rejects ':' and '/' in synthetic test names.
    var skeleton_player := CharacterBody3D.new()
    skeleton_player.name = "SkeletonMountTestPlayer"
    root.add_child(skeleton_player)
    var skeleton_visual := Node3D.new()
    skeleton_visual.name = "VisualUpgrade"
    skeleton_player.add_child(skeleton_visual)
    var skeleton := Skeleton3D.new()
    skeleton.name = "ImportedSkeleton"
    skeleton.position = Vector3(0.21, 1.02, -0.15)
    skeleton.add_bone("RightHand")
    skeleton_visual.add_child(skeleton)
    var skeleton_anchor := runtime.resolve_right_hand_anchor(skeleton_player)
    if not bool(skeleton_anchor.get("found", false)):
        _fail("authored skeleton right-hand bone did not resolve"); return
    if not String(skeleton_anchor.get("source", "")).begins_with("skeleton:"):
        _fail("authored skeleton must win over root-offset fallback"); return

    var unknown_holder := Node3D.new()
    root.add_child(unknown_holder)
    if int(runtime.call("upgrade_weapon_visual", unknown_holder, &"unknown")) != 0:
        _fail("unknown weapon unexpectedly produced a visual recipe"); return

    print("COMBAT_WEAPON_VISUAL_UPGRADE_OK: recipes=green grip_pivot=green moving_hand_lock=green skeleton_hand=green support_target=green")
    quit(0)

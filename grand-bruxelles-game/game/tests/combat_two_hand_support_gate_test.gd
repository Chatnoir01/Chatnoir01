extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const WEAPONS: Array[StringName] = [&"cbr4", &"sct8", &"crossbow"]
const MAX_SUPPORT_GAP_M := 0.09

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("COMBAT_TWO_HAND_SUPPORT_FAIL: %s" % message)
    quit(1)

func _wait_frames(count: int) -> void:
    for _i: int in range(count):
        await process_frame

func _support_diag(player: CharacterBody3D) -> String:
    return "solver=%s active=%s gap=%.4f bones=%s reason=%s source=%s socket_local=%s lengths=%s clavicle=%s shoulder=%s pre_hand=%s hand=%s target_hand=%s target_wrist=%s" % [
        String(player.get_meta("combat_support_ik_solver", "")),
        str(player.get_meta("combat_support_ik_active", false)),
        float(player.get_meta("combat_support_hand_gap_m", 999.0)),
        str(player.get_meta("combat_support_ik_bones", {})),
        String(player.get_meta("combat_support_ik_reason", "")),
        String(player.get_meta("combat_support_ik_target_source", "")),
        str(player.get_meta("combat_support_socket_local", Vector3.ZERO)),
        str(player.get_meta("combat_support_ik_lengths", {})),
        str(player.get_meta("combat_support_ik_clavicle_world", Vector3.ZERO)),
        str(player.get_meta("combat_support_ik_shoulder_world", Vector3.ZERO)),
        str(player.get_meta("combat_support_ik_pre_hand_world", Vector3.ZERO)),
        str(player.get_meta("combat_support_hand_world", Vector3.ZERO)),
        str(player.get_meta("combat_support_ik_desired_hand_world", Vector3.ZERO)),
        str(player.get_meta("combat_support_ik_target_world", Vector3.ZERO)),
    ]

func _run() -> void:
    var project_source := FileAccess.get_file_as_string("res://project.godot")
    for token: String in [
        "CombatLongWeaponFitRuntime=\"*res://game/scripts/combat_long_weapon_fit_runtime.gd\"",
        "CombatSupportHandIKRuntime=\"*res://game/scripts/combat_support_hand_ik_runtime.gd\"",
        "CombatCameraShoulderRuntime=\"*res://game/scripts/combat_camera_shoulder_runtime.gd\"",
    ]:
        if project_source.find(token) < 0:
            _fail("production autoload missing: %s" % token)
            return

    var ik_source := FileAccess.get_file_as_string("res://game/scripts/combat_support_hand_ik_runtime.gd")
    if ik_source.find("FABRIK3D.new()") < 0:
        _fail("support hand must use built-in multi-bone FABRIK3D")
        return
    if ik_source.find("_clavicle_bone") < 0:
        _fail("support IK must include clavicle/shoulder participation")
        return
    if ik_source.find(".set_bone_global_pose_override(") >= 0:
        _fail("support hand must never call direct global bone overrides")
        return
    if ik_source.find("animation_player.active") < 0:
        _fail("support IK must yield when authored animation is frozen")
        return

    if change_scene_to_file(MAIN_SCENE) != OK:
        _fail("main scene load failed")
        return
    var player: CharacterBody3D = null
    for _attempt: int in range(420):
        await process_frame
        if current_scene != null:
            player = current_scene.get_node_or_null("Player") as CharacterBody3D
            if player != null:
                break
    if player == null:
        _fail("production player unavailable")
        return
    var arsenal := root.get_node_or_null("PlayerCombatArsenalRuntime")
    if arsenal == null:
        _fail("production arsenal unavailable")
        return

    for weapon_id: StringName in WEAPONS:
        if not bool(arsenal.call("equip_weapon", player, weapon_id)):
            _fail("equip request failed for %s" % weapon_id)
            return
        var equipped := false
        for _attempt: int in range(180):
            await process_frame
            if StringName(player.get_meta("combat_weapon_id", &"")) == weapon_id and not bool(player.get_meta("combat_weapon_switching", true)):
                equipped = true
                break
        if not equipped:
            _fail("weapon never reached equipped state: %s" % weapon_id)
            return

        # CBR-4 and SCT-8 are procedural. Their IK target must stay in the
        # actual visible handguard/foregrip so a green numeric result can never
        # mean the avatar is gripping empty space.
        if weapon_id == &"cbr4" or weapon_id == &"sct8":
            var holder := player.get_node_or_null("CombatWeaponVisual") as Node3D
            if holder == null:
                _fail("long-weapon holder unavailable for %s" % weapon_id)
                return
            if not bool(holder.get_meta("combat_long_weapon_support_surface_locked", false)):
                _fail("support socket is outside visible foregrip for %s: surface=%s socket=%s center=%s size=%s" % [
                    weapon_id,
                    String(holder.get_meta("combat_long_weapon_support_surface_name", "")),
                    str(holder.get_meta("combat_long_weapon_support_socket_local", Vector3.ZERO)),
                    str(holder.get_meta("combat_long_weapon_support_surface_position", Vector3.ZERO)),
                    str(holder.get_meta("combat_long_weapon_support_surface_size", Vector3.ZERO)),
                ])
                return

        var support_locked := false
        for _attempt: int in range(180):
            await process_frame
            var active := bool(player.get_meta("combat_support_ik_active", false))
            var gap := float(player.get_meta("combat_support_hand_gap_m", 999.0))
            if active and bool(player.get_meta("combat_support_ik_locked", false)) and gap <= MAX_SUPPORT_GAP_M:
                support_locked = true
                break
        if not support_locked:
            _fail("support hand never reached %s foregrip: %s" % [weapon_id, _support_diag(player)])
            return

        if String(player.get_meta("combat_support_ik_solver", "")) != "FABRIK3D":
            _fail("unexpected support IK solver for %s: %s" % [weapon_id, String(player.get_meta("combat_support_ik_solver", ""))])
            return

        print("COMBAT_TWO_HAND_SUPPORT_WEAPON_OK: weapon=%s %s" % [weapon_id, _support_diag(player)])

        var shoulder_profile := String(player.get_meta("combat_camera_shoulder_profile", ""))
        var shoulder_offset: Vector3 = player.get_meta("combat_camera_shoulder_offset", Vector3.ZERO)
        if shoulder_profile != "carry" or shoulder_offset.x < 0.60:
            _fail("armed shoulder camera not active for %s: profile=%s offset=%s" % [weapon_id, shoulder_profile, shoulder_offset])
            return

    print("COMBAT_TWO_HAND_SUPPORT_OK: weapons=cbr4/sct8/crossbow builtin_fabrik=green clavicle_chain=green no_bone_override=green left_hand_gap<=%.2fm visible_foregrip_contract=green shoulder_camera=green" % MAX_SUPPORT_GAP_M)
    quit(0)

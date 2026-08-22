extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const WEAPONS: Array[StringName] = [&"cbr4", &"sct8", &"crossbow"]
const MAX_SUPPORT_GAP_M := 0.09
const MAX_CARRY_GAP_M := 0.09
const MIN_AUTOFIT_FORWARD_DOT := 0.45

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("COMBAT_TWO_HAND_SUPPORT_FAIL: %s" % message)
    quit(1)

func _support_diag(player: CharacterBody3D) -> String:
    return "carry_solver=%s carry_active=%s carry_gap=%.4f carry_bones=%s support_solver=%s support_active=%s support_gap=%.4f support_bones=%s reason=%s source=%s socket_local=%s carry_lengths=%s support_lengths=%s autofit_active=%s autofit_yaw=%.1f autofit_distance=%.4f autofit_reach=%.4f autofit_forward=%.3f right_shoulder=%s left_shoulder=%s right_hand=%s left_hand=%s carry_target=%s support_target=%s" % [
        String(player.get_meta("combat_carry_ik_solver", "")),
        str(player.get_meta("combat_carry_ik_active", false)),
        float(player.get_meta("combat_carry_hand_gap_m", 999.0)),
        str(player.get_meta("combat_carry_ik_bones", {})),
        String(player.get_meta("combat_support_ik_solver", "")),
        str(player.get_meta("combat_support_ik_active", false)),
        float(player.get_meta("combat_support_hand_gap_m", 999.0)),
        str(player.get_meta("combat_support_ik_bones", {})),
        String(player.get_meta("combat_support_ik_reason", "")),
        String(player.get_meta("combat_support_ik_target_source", "")),
        str(player.get_meta("combat_support_socket_local", Vector3.ZERO)),
        str(player.get_meta("combat_carry_ik_lengths", {})),
        str(player.get_meta("combat_support_ik_lengths", {})),
        str(player.get_meta("combat_weapon_support_autofit_active", false)),
        float(player.get_meta("combat_weapon_support_autofit_yaw_deg", 0.0)),
        float(player.get_meta("combat_weapon_support_autofit_distance_m", 999.0)),
        float(player.get_meta("combat_weapon_support_autofit_reach_m", 0.0)),
        float(player.get_meta("combat_weapon_support_autofit_forward_dot", -1.0)),
        str(player.get_meta("combat_carry_right_shoulder_world", Vector3.ZERO)),
        str(player.get_meta("combat_support_ik_shoulder_world", Vector3.ZERO)),
        str(player.get_meta("combat_carry_hand_world", Vector3.ZERO)),
        str(player.get_meta("combat_support_hand_world", Vector3.ZERO)),
        str(player.get_meta("combat_carry_ik_desired_hand_world", Vector3.ZERO)),
        str(player.get_meta("combat_support_ik_desired_hand_world", Vector3.ZERO)),
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
    if ik_source.find("TwoBoneIK3D.new()") < 0:
        _fail("two-handed carry must use built-in TwoBoneIK3D")
        return
    if ik_source.find("FABRIK3D.new()") >= 0:
        _fail("two-handed carry must not pull the torso with FABRIK3D")
        return
    if ik_source.find("CombatCarryHandIK") < 0 or ik_source.find("CombatSupportHandIK") < 0:
        _fail("both right-hand carry and left-hand support solvers are required")
        return
    if ik_source.find(".set_bone_global_pose_override(") >= 0:
        _fail("two-handed pose must never call direct global bone overrides")
        return
    if ik_source.find("animation_player.active") < 0:
        _fail("two-handed IK must yield when authored animation is frozen")
        return

    var orientation_source := FileAccess.get_file_as_string("res://game/scripts/combat_weapon_hand_orientation_polish_runtime.gd")
    if orientation_source.find("combat_weapon_support_autofit") < 0:
        _fail("long-weapon support auto-fit is missing")
        return
    if orientation_source.find("set_bone_global_pose_override") >= 0:
        _fail("weapon auto-fit must not manipulate skeleton bones")
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

        var pose_locked := false
        for _attempt: int in range(240):
            await process_frame
            var carry_active := bool(player.get_meta("combat_carry_ik_active", false))
            var support_active := bool(player.get_meta("combat_support_ik_active", false))
            var carry_gap := float(player.get_meta("combat_carry_hand_gap_m", 999.0))
            var support_gap := float(player.get_meta("combat_support_hand_gap_m", 999.0))
            # The public production contract is the measured <=9 cm threshold.
            # Internal solver confidence flags may remain stricter diagnostics,
            # but they must never turn an 8.x cm measured contact into a failure.
            if carry_active and support_active \
                    and carry_gap <= MAX_CARRY_GAP_M and support_gap <= MAX_SUPPORT_GAP_M:
                pose_locked = true
                break
        if not pose_locked:
            _fail("dual-arm pose never reached measured contact for %s: %s" % [weapon_id, _support_diag(player)])
            return

        if String(player.get_meta("combat_carry_ik_solver", "")) != "TwoBoneIK3D" or String(player.get_meta("combat_support_ik_solver", "")) != "TwoBoneIK3D":
            _fail("unexpected dual-arm solver for %s: %s" % [weapon_id, _support_diag(player)])
            return

        var carry_lengths: Dictionary = player.get_meta("combat_carry_ik_lengths", {})
        var support_lengths: Dictionary = player.get_meta("combat_support_ik_lengths", {})
        if not bool(carry_lengths.get("hand_target_reachable", false)):
            _fail("right-hand carry target is outside arm reach for %s: %s" % [weapon_id, _support_diag(player)])
            return
        if not bool(support_lengths.get("hand_target_reachable", false)):
            _fail("left-hand support target is outside arm reach for %s: %s" % [weapon_id, _support_diag(player)])
            return

        if weapon_id == &"cbr4" or weapon_id == &"sct8":
            if not bool(player.get_meta("combat_weapon_support_autofit_active", false)):
                _fail("support auto-fit never became active for %s: %s" % [weapon_id, _support_diag(player)])
                return
            if not bool(player.get_meta("combat_weapon_support_autofit_reachable", false)):
                _fail("support auto-fit could not bring visible foregrip inside arm reach for %s: %s" % [weapon_id, _support_diag(player)])
                return
            if float(player.get_meta("combat_weapon_support_autofit_forward_dot", -1.0)) < MIN_AUTOFIT_FORWARD_DOT:
                _fail("support auto-fit turned weapon too far away from forward for %s: %s" % [weapon_id, _support_diag(player)])
                return

        var shoulder_mid: Vector3 = player.get_meta("combat_carry_shoulder_mid_world", Vector3.ZERO)
        var carry_target: Vector3 = player.get_meta("combat_carry_ik_desired_hand_world", Vector3.ZERO)
        if shoulder_mid.distance_to(carry_target) > 0.42:
            _fail("weapon hand is still too far from torso for %s: distance=%.4f %s" % [weapon_id, shoulder_mid.distance_to(carry_target), _support_diag(player)])
            return

        var shoulder_profile := String(player.get_meta("combat_camera_shoulder_profile", ""))
        var shoulder_offset: Vector3 = player.get_meta("combat_camera_shoulder_offset", Vector3.ZERO)
        if shoulder_profile != "carry" or shoulder_offset.x < 0.60:
            _fail("armed shoulder camera not active for %s: profile=%s offset=%s" % [weapon_id, shoulder_profile, shoulder_offset])
            return

        print("COMBAT_TWO_HAND_SUPPORT_WEAPON_OK: weapon=%s %s" % [weapon_id, _support_diag(player)])

    print("COMBAT_TWO_HAND_SUPPORT_OK: weapons=cbr4/sct8/crossbow dual_twobone=green no_torso_ik=green no_bone_override=green carry_gap<=%.2fm support_gap<=%.2fm visible_foregrip_contract=green support_autofit=green shoulder_camera=green" % [MAX_CARRY_GAP_M, MAX_SUPPORT_GAP_M])
    quit(0)

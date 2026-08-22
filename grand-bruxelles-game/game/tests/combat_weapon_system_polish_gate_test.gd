extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const NATIVE_WEAPONS: Array[String] = [
    "Knife_Offhand",
    "1H_Crossbow",
    "2H_Crossbow",
    "Knife",
    "Throwable",
]

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("COMBAT_WEAPON_POLISH_GATE_FAIL: %s" % message)
    quit(1)

func _wait_frames(count: int) -> void:
    for _i: int in range(count):
        await process_frame

func _native_nodes(player: CharacterBody3D) -> Dictionary:
    var found: Dictionary = {}
    for node_name: String in NATIVE_WEAPONS:
        var node := player.find_child(node_name, true, false) as Node3D
        if node != null:
            found[node_name] = node
    return found

func _visible_native_names(player: CharacterBody3D) -> Array[String]:
    var visible: Array[String] = []
    var nodes := _native_nodes(player)
    for node_name: String in NATIVE_WEAPONS:
        var node := nodes.get(node_name) as Node3D
        if node != null and node.visible:
            visible.append(node_name)
    return visible

func _wait_equipped(player: CharacterBody3D, weapon_id: StringName, max_frames: int = 240) -> bool:
    for _attempt: int in range(max_frames):
        await process_frame
        if StringName(player.get_meta("combat_weapon_id", &"")) != weapon_id:
            continue
        var expected_state := &"stowed" if weapon_id == &"" else &"equipped"
        if StringName(player.get_meta("combat_weapon_state", &"")) != expected_state:
            continue
        if bool(player.get_meta("combat_weapon_switching", false)):
            continue
        return true
    return false

func _assert_native_exact(player: CharacterBody3D, expected: Array[String]) -> bool:
    var nodes := _native_nodes(player)
    if nodes.size() != NATIVE_WEAPONS.size():
        _fail("Rogue native inventory incomplete: found=%d expected=%d names=%s" % [nodes.size(), NATIVE_WEAPONS.size(), str(nodes.keys())])
        return false
    var visible := _visible_native_names(player)
    if visible != expected:
        _fail("native visibility drift: expected=%s actual=%s" % [str(expected), str(visible)])
        return false
    return true

func _assert_single_visual_owner(player: CharacterBody3D) -> bool:
    var native_count := _visible_native_names(player).size()
    var holder := player.get_node_or_null("CombatWeaponVisual") as Node3D
    var procedural_count := 1 if holder != null and holder.visible else 0
    if native_count + procedural_count > 1:
        _fail("multiple active weapon visuals: native=%s procedural=%d" % [str(_visible_native_names(player)), procedural_count])
        return false
    return true

func _run() -> void:
    if change_scene_to_file(MAIN_SCENE) != OK:
        _fail("main scene load failed")
        return

    var player: CharacterBody3D = null
    for _attempt: int in range(420):
        await process_frame
        if current_scene != null:
            player = current_scene.get_node_or_null("Player") as CharacterBody3D
            if player != null and _native_nodes(player).size() == NATIVE_WEAPONS.size():
                break
    if player == null:
        _fail("production Player unavailable")
        return

    var arsenal := root.get_node_or_null("PlayerCombatArsenalRuntime")
    if arsenal == null:
        _fail("PlayerCombatArsenalRuntime unavailable")
        return

    # Procedural handgun: all Rogue-native accessories must be hidden.
    if not bool(arsenal.call("equip_weapon", player, &"bx9")) or not await _wait_equipped(player, &"bx9"):
        _fail("BX-9 failed to settle equipped")
        return
    if not _assert_native_exact(player, []) or not _assert_single_visual_owner(player):
        return

    # Real switch state + action lock.
    if not bool(arsenal.call("equip_weapon", player, &"cbr4")):
        _fail("CBR-4 switch request failed")
        return
    var switch_state := StringName(player.get_meta("combat_weapon_state", &""))
    if switch_state != &"holstering" and switch_state != &"equipping":
        _fail("weapon switch has no explicit transition state: %s" % String(switch_state))
        return
    var fire_variant: Variant = arsenal.call("request_fire", player)
    if not fire_variant is Dictionary:
        _fail("fire result during switch is not a Dictionary")
        return
    var fire_result := fire_variant as Dictionary
    if bool(fire_result.get("fired", false)) or String(fire_result.get("reason", "")) != "switching":
        _fail("fire was not blocked during weapon switch: %s" % JSON.stringify(fire_result))
        return
    if not await _wait_equipped(player, &"cbr4"):
        _fail("CBR-4 never completed holster/equip sequence")
        return
    if not _assert_native_exact(player, []) or not _assert_single_visual_owner(player):
        return

    # Rapid input while switching: only the latest queued request may win.
    if not bool(arsenal.call("equip_weapon", player, &"sct8")):
        _fail("SCT-8 rapid switch rejected")
        return
    if not bool(arsenal.call("equip_weapon", player, &"crossbow")):
        _fail("crossbow queued switch rejected")
        return
    if not bool(arsenal.call("equip_weapon", player, &"knife")):
        _fail("knife last-wins queued switch rejected")
        return
    for _frame: int in range(180):
        await process_frame
        if not _assert_single_visual_owner(player):
            return
        if StringName(player.get_meta("combat_weapon_id", &"")) == &"knife" and StringName(player.get_meta("combat_weapon_state", &"")) == &"equipped":
            break
    if not await _wait_equipped(player, &"knife"):
        _fail("rapid switch did not settle on last requested knife")
        return
    if not _assert_native_exact(player, ["Knife"]) or not _assert_single_visual_owner(player):
        return

    # Native crossbow is a real mode, not a permanently visible model accessory.
    if not bool(arsenal.call("equip_weapon", player, &"crossbow")) or not await _wait_equipped(player, &"crossbow"):
        _fail("crossbow failed to settle equipped")
        return
    if not _assert_native_exact(player, ["2H_Crossbow"]) or not _assert_single_visual_owner(player):
        return
    var crossbow_fire_variant: Variant = arsenal.call("request_fire", player)
    if not crossbow_fire_variant is Dictionary or not bool((crossbow_fire_variant as Dictionary).get("fired", false)):
        _fail("crossbow did not fire from fully equipped state: %s" % JSON.stringify(crossbow_fire_variant))
        return
    var ammo_variant: Variant = arsenal.call("ammo_state", &"crossbow")
    if not ammo_variant is Dictionary or int((ammo_variant as Dictionary).get("mag", -1)) != 0:
        _fail("crossbow single-bolt magazine did not decrement: %s" % JSON.stringify(ammo_variant))
        return
    if not bool(arsenal.call("request_reload", player)):
        _fail("crossbow reload request rejected after empty shot")
        return
    if not bool(player.get_meta("combat_weapon_reloading", false)):
        _fail("crossbow reload state not published")
        return

    # Switching cancels stale reload and returns native equipment to hidden inventory.
    if not bool(arsenal.call("equip_weapon", player, &"bx9")) or not await _wait_equipped(player, &"bx9"):
        _fail("crossbow -> BX-9 switch failed")
        return
    if bool(player.get_meta("combat_weapon_reloading", false)):
        _fail("reload leaked across weapon switch")
        return
    if not _assert_native_exact(player, []) or not _assert_single_visual_owner(player):
        return

    # Explicit equipment slots: one main owner, no accidental back/hip duplicates.
    if StringName(player.get_meta("combat_equipment_slot_main", &"")) != &"bx9":
        _fail("main equipment slot drifted")
        return
    if StringName(player.get_meta("combat_equipment_slot_back", &"")) != &"" or StringName(player.get_meta("combat_equipment_slot_hip", &"")) != &"":
        _fail("back/hip slots unexpectedly contain duplicate active equipment")
        return
    if not bool(player.get_meta("combat_equipment_single_active", false)):
        _fail("single-active equipment invariant not published")
        return
    var hidden_variant: Variant = player.get_meta("combat_equipment_slot_inventory_hidden", [])
    if not hidden_variant is Array or not (hidden_variant as Array).has(&"crossbow") or not (hidden_variant as Array).has(&"knife"):
        _fail("hidden inventory slot does not contain inactive native weapons")
        return

    # Surface-aware impacts: every required family must classify independently.
    var impact_runtime := root.get_node_or_null("CombatSurfaceImpactRuntime")
    if impact_runtime == null or not impact_runtime.has_method("classify_surface") or not impact_runtime.has_method("spawn_impact"):
        _fail("surface impact runtime unavailable")
        return
    var metal := Node3D.new()
    metal.name = "MetalTestPlate"
    var wood := Node3D.new()
    wood.name = "WoodTestDoor"
    var body := Node3D.new()
    body.name = "BodyTest"
    body.set_meta("combat_surface_type", &"body")
    var classifications := {
        "ground": StringName(impact_runtime.call("classify_surface", null, Vector3.UP)),
        "wall": StringName(impact_runtime.call("classify_surface", null, Vector3(0.0, 0.0, 1.0))),
        "metal": StringName(impact_runtime.call("classify_surface", metal, Vector3(0.0, 0.0, 1.0))),
        "wood": StringName(impact_runtime.call("classify_surface", wood, Vector3(0.0, 0.0, 1.0))),
        "body": StringName(impact_runtime.call("classify_surface", body, Vector3.UP)),
    }
    for surface: String in ["ground", "wall", "metal", "wood", "body"]:
        if classifications[surface] != StringName(surface):
            _fail("surface classification drifted for %s: %s" % [surface, String(classifications[surface])])
            return
    var exact_hit := Vector3(1.25, 2.5, -3.75)
    var impact_variant: Variant = impact_runtime.call("spawn_impact", exact_hit, Vector3.UP, metal, &"bx9", 1.0, &"")
    if not impact_variant is Node3D:
        _fail("impact runtime did not spawn visual feedback")
        return
    var impact := impact_variant as Node3D
    if StringName(impact.get_meta("combat_impact_surface", &"")) != &"metal":
        _fail("spawned impact lost metal classification")
        return
    if (impact.get_meta("combat_impact_world_position", Vector3.ZERO) as Vector3).distance_to(exact_hit) > 0.0001:
        _fail("impact world position no longer matches authoritative ray hit")
        return

    print("COMBAT_WEAPON_POLISH_GATE_OK: modes=bx9/cbr4/sct8/crossbow/knife single_owner=green last_input_wins=green fire_lock=green crossbow_reload=green slots=green impacts=ground/wall/metal/wood/body exact_hit=green")
    quit(0)

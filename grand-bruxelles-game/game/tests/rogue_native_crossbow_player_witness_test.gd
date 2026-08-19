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
    push_error("ROGUE_NATIVE_CROSSBOW_WITNESS_FAIL: %s" % message)
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

func _assert_native_visibility(player: CharacterBody3D, expected_visible: String) -> bool:
    var nodes := _native_nodes(player)
    if nodes.size() != NATIVE_WEAPONS.size():
        _fail("native inventory incomplete: found=%d expected=%d names=%s" % [nodes.size(), NATIVE_WEAPONS.size(), str(nodes.keys())])
        return false
    for node_name: String in NATIVE_WEAPONS:
        var node := nodes.get(node_name) as Node3D
        var should_be_visible := not expected_visible.is_empty() and node_name == expected_visible
        if node.visible != should_be_visible:
            _fail("%s visibility=%s expected=%s for mode=%s" % [node_name, node.visible, should_be_visible, expected_visible])
            return false
    return true

func _run() -> void:
    if root.get_node_or_null("CombatAuthoredPoseRuntime") != null:
        _fail("unsafe authored pose runtime must stay disabled")
        return
    var error := change_scene_to_file(MAIN_SCENE)
    if error != OK:
        _fail("main scene load failed: %s" % error)
        return

    var player: CharacterBody3D = null
    for _attempt: int in range(360):
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

    if not bool(arsenal.call("equip_weapon", player, &"crossbow")):
        _fail("crossbow slot 1 equip failed")
        return
    await _wait_frames(6)
    if not _assert_native_visibility(player, "1H_Crossbow"):
        return
    if StringName(arsenal.call("equipped_weapon")) != &"crossbow":
        _fail("crossbow not canonical equipped weapon")
        return
    if player.get_node_or_null("CombatWeaponVisual") != null:
        _fail("procedural weapon holder must be absent while native crossbow is equipped")
        return

    var before_shots := int(player.get_meta("combat_crossbow_shot_count", 0))
    var before_bolts := int(player.get_meta("combat_crossbow_bolt_visual_count", 0))
    var fired_variant: Variant = arsenal.call("request_fire", player)
    if not fired_variant is Dictionary:
        _fail("crossbow fire result is not a Dictionary")
        return
    var fired := fired_variant as Dictionary
    if not bool(fired.get("fired", false)) or StringName(fired.get("weapon", &"")) != &"crossbow":
        _fail("crossbow did not fire: %s" % JSON.stringify(fired))
        return
    await _wait_frames(2)
    if int(player.get_meta("combat_crossbow_shot_count", 0)) != before_shots + 1:
        _fail("crossbow shot counter did not increment")
        return
    if int(player.get_meta("combat_crossbow_bolt_visual_count", 0)) != before_bolts + 1:
        _fail("crossbow bolt visual did not spawn")
        return
    var crossbow_ammo_variant: Variant = arsenal.call("ammo_state", &"crossbow")
    if not crossbow_ammo_variant is Dictionary or int((crossbow_ammo_variant as Dictionary).get("mag", -1)) != 0:
        _fail("crossbow ammo did not decrement after shot")
        return

    for weapon_id: StringName in [&"bx9", &"cbr4", &"sct8"]:
        if not bool(arsenal.call("equip_weapon", player, weapon_id)):
            _fail("equip failed for %s" % weapon_id)
            return
        await _wait_frames(6)
        if not _assert_native_visibility(player, ""):
            return
        if player.get_node_or_null("CombatWeaponVisual") == null:
            _fail("procedural holder missing for %s" % weapon_id)
            return

    if not bool(arsenal.call("equip_weapon", player, &"")):
        _fail("holster/unarmed failed")
        return
    await _wait_frames(4)
    if not _assert_native_visibility(player, ""):
        return

    if not bool(player.get_meta("combat_native_weapon_inventory_sanitized", false)):
        _fail("native inventory was not marked sanitized")
        return

    print("ROGUE_NATIVE_CROSSBOW_WITNESS_OK: native_nodes=5 slot1=1H_Crossbow knives=hidden variant_2H=hidden fire=green bolt=green slots_2_3_4=native_hidden unarmed=native_hidden")
    quit(0)

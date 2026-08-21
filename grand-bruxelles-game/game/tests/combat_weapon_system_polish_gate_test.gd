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

func _assert_native_hidden(player: CharacterBody3D) -> bool:
    var nodes := _native_nodes(player)
    if nodes.size() != NATIVE_WEAPONS.size():
        _fail("Rogue native inventory incomplete: found=%d expected=%d names=%s" % [nodes.size(), NATIVE_WEAPONS.size(), str(nodes.keys())])
        return false
    for node_name: String in NATIVE_WEAPONS:
        var node := nodes[node_name] as Node3D
        if node.visible:
            _fail("ghost native weapon still visible: %s" % node_name)
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

    if not bool(arsenal.call("equip_weapon", player, &"bx9")):
        _fail("BX-9 equip request failed")
        return
    await _wait_frames(8)
    if not _assert_native_hidden(player):
        return

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

    var impact_runtime := root.get_node_or_null("CombatSurfaceImpactRuntime")
    if impact_runtime == null or not impact_runtime.has_method("classify_surface"):
        _fail("surface impact classifier runtime unavailable")
        return
    var ground := StringName(impact_runtime.call("classify_surface", null, Vector3.UP))
    var wall := StringName(impact_runtime.call("classify_surface", null, Vector3(0.0, 0.0, 1.0)))
    if ground != &"ground" or wall != &"wall":
        _fail("surface fallback classification drifted: ground=%s wall=%s" % [String(ground), String(wall)])
        return

    print("COMBAT_WEAPON_POLISH_GATE_OK: rogue_native_hidden=5 switch_state=%s fire_lock=green impacts=ground/wall" % String(switch_state))
    quit(0)

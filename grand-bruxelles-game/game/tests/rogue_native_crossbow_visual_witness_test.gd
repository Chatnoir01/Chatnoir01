extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const OUT_DIR := "res://artifacts/qa/rogue_native_crossbow"
const WIDTH := 1280
const HEIGHT := 720
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
    push_error("ROGUE_NATIVE_CROSSBOW_VISUAL_FAIL: %s" % message)
    quit(1)

func _mask_canvas(node: Node) -> void:
    if node is CanvasLayer:
        (node as CanvasLayer).visible = false
    if node is CanvasItem:
        (node as CanvasItem).visible = false
    for child: Node in node.get_children():
        _mask_canvas(child)

func _hide_dynamic(node: Node, player: CharacterBody3D) -> void:
    if node != player and not player.is_ancestor_of(node) and node is NpcAgent:
        node.set_process(false)
        node.set_physics_process(false)
        (node as Node3D).visible = false
        return
    for child: Node in node.get_children():
        _hide_dynamic(child, player)

func _native_nodes(player: CharacterBody3D) -> Dictionary:
    var found: Dictionary = {}
    for node_name: String in NATIVE_WEAPONS:
        var node := player.find_child(node_name, true, false) as Node3D
        if node != null:
            found[node_name] = node
    return found

func _assert_visibility(player: CharacterBody3D, expected_visible: String) -> bool:
    var nodes := _native_nodes(player)
    if nodes.size() != NATIVE_WEAPONS.size():
        _fail("native inventory incomplete: %s" % str(nodes.keys()))
        return false
    for node_name: String in NATIVE_WEAPONS:
        var node := nodes[node_name] as Node3D
        var expected := not expected_visible.is_empty() and node_name == expected_visible
        if node.visible != expected:
            _fail("%s visible=%s expected=%s" % [node_name, node.visible, expected])
            return false
    return true

func _capture(path: String, player: CharacterBody3D) -> bool:
    for _frame: int in range(12):
        _mask_canvas(root)
        _hide_dynamic(root, player)
        await process_frame
    RenderingServer.force_draw()
    await process_frame
    var image := root.get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        return false
    return image.save_png(ProjectSettings.globalize_path(path)) == OK

func _run() -> void:
    if root.get_node_or_null("CombatAuthoredPoseRuntime") != null:
        _fail("unsafe authored pose runtime is active")
        return
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
    if player == null or _native_nodes(player).size() != NATIVE_WEAPONS.size():
        _fail("production Rogue/native inventory unavailable")
        return

    var arsenal := root.get_node_or_null("PlayerCombatArsenalRuntime")
    if arsenal == null:
        _fail("arsenal unavailable")
        return

    player.velocity = Vector3.ZERO
    player.set_physics_process(false)
    _hide_dynamic(root, player)
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

    if not bool(arsenal.call("equip_weapon", player, &"")):
        _fail("unarmed equip failed")
        return
    for _frame: int in range(18):
        await process_frame
    if not _assert_visibility(player, ""):
        return
    if not await _capture(OUT_DIR + "/unarmed.png", player):
        _fail("unarmed capture failed")
        return

    if not bool(arsenal.call("equip_weapon", player, &"crossbow")):
        _fail("crossbow equip failed")
        return
    for _frame: int in range(18):
        await process_frame
    if not _assert_visibility(player, "2H_Crossbow"):
        return
    if player.get_node_or_null("CombatWeaponVisual") != null:
        _fail("procedural holder exists during native crossbow")
        return
    if not await _capture(OUT_DIR + "/crossbow.png", player):
        _fail("crossbow capture failed")
        return

    if not bool(arsenal.call("equip_weapon", player, &"bx9")):
        _fail("BX-9 equip failed")
        return
    for _attempt: int in range(180):
        await process_frame
        if bool(player.get_meta("combat_weapon_grip_locked", false)):
            break
    if not _assert_visibility(player, ""):
        return
    if player.get_node_or_null("CombatWeaponVisual") == null:
        _fail("BX-9 holder missing")
        return
    if not await _capture(OUT_DIR + "/bx9.png", player):
        _fail("BX-9 capture failed")
        return

    print("ROGUE_NATIVE_CROSSBOW_VISUAL_OK: 1280x720 unarmed=native_hidden crossbow=2H_only bx9=native_hidden unsafe_pose=false")
    quit(0)

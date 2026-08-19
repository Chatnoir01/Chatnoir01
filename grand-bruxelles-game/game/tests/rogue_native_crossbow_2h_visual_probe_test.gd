extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const OUT_DIR := "res://artifacts/qa/rogue_crossbow_2h_probe"
const WIDTH := 1280
const HEIGHT := 720

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ROGUE_CROSSBOW_2H_PROBE_FAIL: %s" % message)
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

func _capture(path: String, player: CharacterBody3D, one_h: Node3D, two_h: Node3D, use_two_h: bool) -> bool:
    for _frame: int in range(14):
        one_h.visible = not use_two_h
        two_h.visible = use_two_h
        _mask_canvas(root)
        _hide_dynamic(root, player)
        await process_frame
    one_h.visible = not use_two_h
    two_h.visible = use_two_h
    RenderingServer.force_draw()
    await process_frame
    one_h.visible = not use_two_h
    two_h.visible = use_two_h
    RenderingServer.force_draw()
    await process_frame
    var image := root.get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        return false
    return image.save_png(ProjectSettings.globalize_path(path)) == OK

func _run() -> void:
    if root.get_node_or_null("CombatAuthoredPoseRuntime") != null:
        _fail("unsafe pose runtime active")
        return
    if change_scene_to_file(MAIN_SCENE) != OK:
        _fail("main scene load failed")
        return

    var player: CharacterBody3D = null
    var one_h: Node3D = null
    var two_h: Node3D = null
    for _attempt: int in range(420):
        await process_frame
        if current_scene == null:
            continue
        player = current_scene.get_node_or_null("Player") as CharacterBody3D
        if player == null:
            continue
        one_h = player.find_child("1H_Crossbow", true, false) as Node3D
        two_h = player.find_child("2H_Crossbow", true, false) as Node3D
        if one_h != null and two_h != null:
            break
    if player == null or one_h == null or two_h == null:
        _fail("Rogue crossbow variants unavailable")
        return

    var arsenal := root.get_node_or_null("PlayerCombatArsenalRuntime")
    if arsenal == null or not bool(arsenal.call("equip_weapon", player, &"crossbow")):
        _fail("crossbow equip failed")
        return
    for _frame: int in range(18):
        await process_frame

    arsenal.set_process(false)
    player.velocity = Vector3.ZERO
    player.set_physics_process(false)
    _hide_dynamic(root, player)
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

    if not await _capture(OUT_DIR + "/crossbow_1h.png", player, one_h, two_h, false):
        _fail("1H capture failed")
        return
    if not await _capture(OUT_DIR + "/crossbow_2h.png", player, one_h, two_h, true):
        _fail("2H capture failed")
        return

    print("ROGUE_CROSSBOW_2H_PROBE_OK: same_player=true same_camera=true no_bone_override=true variants=1H,2H")
    quit(0)

extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const OUT_DIR := "res://artifacts/qa/rogue_crossbow_transform_probe"
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
    push_error("ROGUE_CROSSBOW_TRANSFORM_PROBE_FAIL: %s" % message)
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

func _capture(path: String, player: CharacterBody3D) -> bool:
    for _frame: int in range(8):
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
    if player == null:
        _fail("production Player unavailable")
        return

    var arsenal := root.get_node_or_null("PlayerCombatArsenalRuntime")
    if arsenal == null:
        _fail("arsenal unavailable")
        return
    if not bool(arsenal.call("equip_weapon", player, &"crossbow")):
        _fail("crossbow equip failed")
        return
    for _frame: int in range(18):
        await process_frame

    var nodes := _native_nodes(player)
    var crossbow := nodes.get("2H_Crossbow") as Node3D
    if crossbow == null or not crossbow.visible:
        _fail("2H crossbow unavailable or hidden")
        return
    for node_name: String in NATIVE_WEAPONS:
        if node_name == "2H_Crossbow":
            continue
        var native := nodes.get(node_name) as Node3D
        if native != null and native.visible:
            _fail("unexpected native visible: %s" % node_name)
            return

    player.velocity = Vector3.ZERO
    player.set_physics_process(false)
    arsenal.set_process(false)
    _hide_dynamic(root, player)
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

    var authored := crossbow.transform
    var x90 := Transform3D(
        authored.basis * Basis(Vector3.RIGHT, deg_to_rad(90.0)),
        authored.origin
    )
    var candidates: Dictionary = {
        "x90": x90,
        "x90_x_p10": Transform3D(x90.basis, x90.origin + Vector3(0.10, 0.0, 0.0)),
        "x90_x_m10": Transform3D(x90.basis, x90.origin + Vector3(-0.10, 0.0, 0.0)),
        "x90_x_p20": Transform3D(x90.basis, x90.origin + Vector3(0.20, 0.0, 0.0)),
        "x90_x_m20": Transform3D(x90.basis, x90.origin + Vector3(-0.20, 0.0, 0.0)),
        "x90_y_p10": Transform3D(x90.basis, x90.origin + Vector3(0.0, 0.10, 0.0)),
        "x90_y_m10": Transform3D(x90.basis, x90.origin + Vector3(0.0, -0.10, 0.0)),
        "x90_y_p20": Transform3D(x90.basis, x90.origin + Vector3(0.0, 0.20, 0.0)),
        "x90_y_m20": Transform3D(x90.basis, x90.origin + Vector3(0.0, -0.20, 0.0)),
        "x90_z_p10": Transform3D(x90.basis, x90.origin + Vector3(0.0, 0.0, 0.10)),
        "x90_z_m10": Transform3D(x90.basis, x90.origin + Vector3(0.0, 0.0, -0.10)),
        "x90_z_p20": Transform3D(x90.basis, x90.origin + Vector3(0.0, 0.0, 0.20)),
        "x90_z_m20": Transform3D(x90.basis, x90.origin + Vector3(0.0, 0.0, -0.20)),
    }

    for candidate_name: String in candidates.keys():
        crossbow.transform = candidates[candidate_name] as Transform3D
        if not await _capture(OUT_DIR + "/%s.png" % candidate_name, player):
            _fail("capture failed: %s" % candidate_name)
            return

    crossbow.transform = authored
    print("ROGUE_CROSSBOW_TRANSFORM_PROBE_OK: candidates=%d base=x90 bone_override=false handslot_only=true" % candidates.size())
    quit(0)

extends SceneTree

const HEAD_BONE := "mixamorig_Head"
const BODY_PATH := "res://vitruvian_body.glb"
const HEAD_PATH := "res://vitruvian_head.glb"

func _initialize() -> void:
    call_deferred("_run")

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node as Skeleton3D
    for child in node.get_children():
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null

func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D:
        out.append(node as MeshInstance3D)
    for child in node.get_children():
        _collect_meshes(child, out)

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() != 2:
        push_error("expected <receipt.json> <frame.png>")
        quit(2); return
    var receipt_path: String = args[0]
    var frame_path: String = args[1]
    var body_scene := load(BODY_PATH) as PackedScene
    var head_scene := load(HEAD_PATH) as PackedScene
    if body_scene == null or head_scene == null:
        push_error("missing imported body/head scene")
        quit(3); return

    var world := Node3D.new(); world.name = "CIV1BodyHeadWitness"; root.add_child(world)
    var body := body_scene.instantiate(); body.name = "Body"; world.add_child(body)
    var skel := _find_skeleton(body)
    if skel == null:
        push_error("body Skeleton3D missing"); quit(4); return
    var head_bone_idx := skel.find_bone(HEAD_BONE)
    if head_bone_idx < 0:
        push_error("mixamorig_Head missing"); quit(5); return

    var attachment := BoneAttachment3D.new()
    attachment.name = "HeadAttach"
    skel.add_child(attachment)
    attachment.bone_idx = head_bone_idx
    var head_rig := Node3D.new(); head_rig.name = "HeadRig"; attachment.add_child(head_rig)
    head_rig.global_transform = Transform3D.IDENTITY
    var head := head_scene.instantiate(); head.name = "Head"; head_rig.add_child(head)

    var body_meshes: Array[MeshInstance3D] = []
    var head_meshes: Array[MeshInstance3D] = []
    _collect_meshes(body, body_meshes); _collect_meshes(head, head_meshes)
    var head_material_surfaces := 0
    var head_total_surfaces := 0
    for mi in head_meshes:
        if mi.mesh == null: continue
        for surface_idx in range(mi.mesh.get_surface_count()):
            head_total_surfaces += 1
            if mi.get_active_material(surface_idx) != null:
                head_material_surfaces += 1

    var light := DirectionalLight3D.new(); light.rotation_degrees = Vector3(-35.0, -25.0, 0.0); light.light_energy = 1.4; world.add_child(light)
    var fill := OmniLight3D.new(); fill.position = Vector3(1.2, 1.4, 2.0); fill.omni_range = 6.0; fill.light_energy = 3.0; world.add_child(fill)
    var camera := Camera3D.new(); camera.position = Vector3(0.0, 1.05, 3.2); camera.fov = 38.0; world.add_child(camera); camera.look_at(Vector3(0.0, 0.95, 0.0)); camera.current = true
    root.size = Vector2i(1280, 720)

    await process_frame; await process_frame; await process_frame
    var head_origin := head_rig.global_transform.origin
    var attachment_origin := attachment.global_transform.origin
    var image := root.get_texture().get_image()
    var image_ok := image != null and image.get_width() == 1280 and image.get_height() == 720 and image.save_png(frame_path) == OK
    var composition_pass := body_meshes.size() >= 3 and head_meshes.size() >= 1 and head_total_surfaces > 0 and head_material_surfaces == head_total_surfaces and image_ok
    var receipt := {
        "verdict": "AMELIORER_BODY_HEAD_WITNESS" if composition_pass else "JETER_BODY_HEAD_WITNESS",
        "attachment_mode": "rigid_to_body_head_bone",
        "head_bone": HEAD_BONE,
        "head_bone_index": head_bone_idx,
        "head_rig_world_origin": [head_origin.x, head_origin.y, head_origin.z],
        "attachment_world_origin": [attachment_origin.x, attachment_origin.y, attachment_origin.z],
        "body_mesh_count": body_meshes.size(),
        "head_mesh_count": head_meshes.size(),
        "head_surface_count": head_total_surfaces,
        "head_material_surface_count": head_material_surfaces,
        "frame_width": image.get_width() if image != null else 0,
        "frame_height": image.get_height() if image != null else 0,
        "composition_pass": composition_pass,
        "runtime_authorized": false,
        "visual_approval_claimed": false
    }
    FileAccess.open(receipt_path, FileAccess.WRITE).store_string(JSON.stringify(receipt, "  "))
    print("CIV1_BODY_HEAD_WITNESS_" + ("OK" if composition_pass else "FAIL"))
    quit(0 if composition_pass else 6)

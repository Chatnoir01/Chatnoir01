extends SceneTree

const REVIEW_ROOT := "res://assets/characters/_review/vitruvian_civ1_v1"
const BODY := REVIEW_ROOT + "/vitruvian_body.glb"
const HEAD := REVIEW_ROOT + "/vitruvian_head.glb"
const HAIR := REVIEW_ROOT + "/hairtool_cards.glb"
const BROWS := REVIEW_ROOT + "/vitruvian_hair.glb"
const HAIR_SHADER := REVIEW_ROOT + "/hairtool_card.gdshader"
const BROW_SHADER := REVIEW_ROOT + "/hair_card.gdshader"
const MAIN_SCENE := "res://game/main.tscn"
const CAPTURE_SIZE := Vector2i(1280, 720)
const DISTANCES := [2.0, 5.0, 8.0]
const MIN_HEIGHT_M := 1.40
const MAX_HEIGHT_M := 2.20
const MAX_TRIANGLES := 650000

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var base_output := "/tmp/midi-civ1-vitruvian"
    var args := OS.get_cmdline_user_args()
    if not args.is_empty():
        base_output = str(args[0]).get_basename()

    for path: String in [BODY, HEAD, HAIR, BROWS, HAIR_SHADER, BROW_SHADER, MAIN_SCENE]:
        if not ResourceLoader.exists(path):
            _fail("required review resource missing: %s" % path)
            return

    var main_packed := ResourceLoader.load(MAIN_SCENE) as PackedScene
    if main_packed == null:
        _fail("main scene did not load")
        return
    var main := main_packed.instantiate() as Node3D
    if main == null:
        _fail("main scene did not instantiate")
        return
    get_root().add_child(main)
    current_scene = main

    for _i in range(45):
        await process_frame

    var player := main.get_node_or_null("Player") as Node3D
    if player == null:
        _fail("real Player node missing from main scene")
        return

    var candidate := Node3D.new()
    candidate.name = "CIV1_Vitruvian_Review_Only"
    candidate.set_meta("production_authorized", false)
    candidate.set_meta("movement_owner", "none_review_only")
    candidate.set_meta("source", "ibrews/VitruvianGodot@bdecdcd537b4031fdd0fb299b7e4f93f084fffa0")
    main.add_child(candidate)

    var body := _instantiate(BODY, "Body")
    var head := _instantiate(HEAD, "Head")
    var hair := _instantiate(HAIR, "Hair")
    var brows := _instantiate(BROWS, "BrowsSource")
    if body == null or head == null or hair == null or brows == null:
        return
    candidate.add_child(body)
    candidate.add_child(head)
    candidate.add_child(hair)
    candidate.add_child(brows)

    _apply_hair_review_material(hair)
    _keep_brows_only(brows)

    var animation_clips := _count_animation_clips(candidate)
    if animation_clips != 0:
        _fail("CIV-1 review package must be animation-free, found %d clips" % animation_clips)
        return

    var bounds := _bounds_in_root_space(candidate)
    if bounds.size.y < MIN_HEIGHT_M or bounds.size.y > MAX_HEIGHT_M:
        _fail("full-body metre scale outside CIV-1 gate: %s" % str(bounds))
        return
    var triangles := _triangle_count(candidate)
    if triangles <= 0 or triangles > MAX_TRIANGLES:
        _fail("triangle budget outside review gate: %d" % triangles)
        return

    # Put the witness beside the authoritative player start in the real Midi scene.
    candidate.global_position = player.global_position + Vector3(3.2, 0.0, -1.6)
    candidate.global_position.y = player.global_position.y - bounds.position.y
    candidate.rotation_degrees = Vector3(0.0, 180.0, 0.0)

    var camera := Camera3D.new()
    camera.name = "CIV1ReviewCamera"
    camera.near = 0.04
    camera.fov = 48.0
    main.add_child(camera)
    camera.current = true

    var target := candidate.global_position + Vector3(0.0, bounds.size.y * 0.54, 0.0)
    var outputs: Dictionary = {}
    for distance_value in DISTANCES:
        var distance := float(distance_value)
        camera.global_position = target + Vector3(0.32, 0.08, distance)
        camera.look_at(target, Vector3.UP)
        var label := "%dm" % int(distance)
        var path := "%s_%s.png" % [base_output, label]
        if not await _save_after_frames(path, 12):
            _fail("capture failed at %s" % label)
            return
        outputs[label] = path

    var close_three_quarter := "%s_2m_three_quarter.png" % base_output
    camera.global_position = target + Vector3(1.28, 0.10, 1.62)
    camera.look_at(target, Vector3.UP)
    if not await _save_after_frames(close_three_quarter, 12):
        _fail("three-quarter capture failed")
        return
    outputs["2m_three_quarter"] = close_three_quarter

    var metrics := {
        "schema": "grand-bruxelles-civ1-vitruvian-witness-v1",
        "production_authorized": false,
        "actual_scene": MAIN_SCENE,
        "base_main_sha": "75345935173ba11ead85c317786f9e31e4517afd",
        "upstream_commit": "bdecdcd537b4031fdd0fb299b7e4f93f084fffa0",
        "character_license": "CC0-1.0",
        "mixamo_payload_allowed": false,
        "animation_clip_count": animation_clips,
        "height_m": bounds.size.y,
        "width_m": bounds.size.x,
        "depth_m": bounds.size.z,
        "triangle_count": triangles,
        "capture_resolution": [CAPTURE_SIZE.x, CAPTURE_SIZE.y],
        "fixed_distances_m": DISTANCES,
        "captures": outputs,
        "fallback_changed": false,
        "movement_navigation_density_changed": false,
        "human_verdict_required": "GARDER",
    }
    var metrics_path := "%s.metrics.json" % base_output
    var file := FileAccess.open(metrics_path, FileAccess.WRITE)
    if file == null:
        _fail("could not write metrics")
        return
    file.store_string(JSON.stringify(metrics, "  ") + "\n")
    file.close()

    print("GB_CIV1_VITRUVIAN_WITNESS_OK height=%.3f triangles=%d animations=%d captures=2m,5m,8m production_authorized=false" % [bounds.size.y, triangles, animation_clips])
    quit(0)

func _instantiate(path: String, label: String) -> Node3D:
    var packed := ResourceLoader.load(path) as PackedScene
    if packed == null:
        _fail("%s did not import as PackedScene: %s" % [label, path])
        return null
    var node := packed.instantiate() as Node3D
    if node == null:
        _fail("%s did not instantiate" % label)
        return null
    node.name = label
    return node

func _apply_hair_review_material(root: Node) -> void:
    var shader := ResourceLoader.load(HAIR_SHADER) as Shader
    var diffuse := ResourceLoader.load(REVIEW_ROOT + "/vit_hair_diffuse.png") as Texture2D
    var normal := ResourceLoader.load(REVIEW_ROOT + "/vit_hair_normal.png") as Texture2D
    var ao := ResourceLoader.load(REVIEW_ROOT + "/vit_hair_ao.png") as Texture2D
    var opacity := ResourceLoader.load(REVIEW_ROOT + "/vit_hair_opacity.png") as Texture2D
    if shader == null or diffuse == null or normal == null or ao == null or opacity == null:
        _fail("hair shader/PBR inputs missing")
        return
    var mat := ShaderMaterial.new()
    mat.shader = shader
    mat.set_shader_parameter("tex_diffuse", diffuse)
    mat.set_shader_parameter("tex_normal", normal)
    mat.set_shader_parameter("tex_ao", ao)
    mat.set_shader_parameter("tex_opacity", opacity)
    mat.set_shader_parameter("root_color", Color(0.34, 0.24, 0.16, 1.0))
    mat.set_shader_parameter("tip_color", Color(0.48, 0.35, 0.24, 1.0))
    mat.set_shader_parameter("brightness", 2.8)
    mat.set_shader_parameter("diffuse_mix", 1.0)
    mat.set_shader_parameter("normal_strength", 1.0)
    mat.set_shader_parameter("ao_strength", 0.6)
    mat.set_shader_parameter("roughness_val", 0.76)
    mat.set_shader_parameter("specular_val", 0.25)
    mat.set_shader_parameter("anisotropy_val", 0.40)
    mat.set_shader_parameter("density", 1.0)
    mat.set_shader_parameter("scissor", 0.35)
    var meshes: Array[MeshInstance3D] = []
    _collect_meshes(root, meshes)
    for mesh_node in meshes:
        if mesh_node.name.begins_with("VitBrow"):
            mesh_node.visible = false
            continue
        if mesh_node.mesh == null:
            continue
        for surface in range(mesh_node.mesh.get_surface_count()):
            mesh_node.set_surface_override_material(surface, mat)

func _keep_brows_only(root: Node) -> void:
    var shader := ResourceLoader.load(BROW_SHADER) as Shader
    var atlas := ResourceLoader.load(REVIEW_ROOT + "/vit_hair_atlas.png") as Texture2D
    if shader == null or atlas == null:
        _fail("brow shader/atlas missing")
        return
    var mat := ShaderMaterial.new()
    mat.shader = shader
    mat.set_shader_parameter("hair_color", Color(0.09, 0.06, 0.04, 1.0))
    mat.set_shader_parameter("coverage_atlas", atlas)
    mat.set_shader_parameter("use_red_mask", true)
    mat.set_shader_parameter("invert_mask", false)
    mat.set_shader_parameter("alpha_threshold", 0.28)
    mat.set_shader_parameter("root_darkening", 0.45)
    mat.set_shader_parameter("roughness_val", 0.72)
    mat.set_shader_parameter("specular_val", 0.14)
    mat.set_shader_parameter("anisotropy", 0.50)
    mat.set_shader_parameter("tonal_variation", 0.30)
    var meshes: Array[MeshInstance3D] = []
    _collect_meshes(root, meshes)
    for mesh_node in meshes:
        if not mesh_node.name.begins_with("VitBrow"):
            mesh_node.visible = false
            continue
        mesh_node.visible = true
        if mesh_node.mesh == null:
            continue
        for surface in range(mesh_node.mesh.get_surface_count()):
            mesh_node.set_surface_override_material(surface, mat)

func _count_animation_clips(node: Node) -> int:
    var count := 0
    if node is AnimationPlayer:
        var player := node as AnimationPlayer
        for library_name in player.get_animation_library_list():
            var library := player.get_animation_library(library_name)
            if library == null:
                continue
            for animation_name in library.get_animation_list():
                if str(animation_name).to_upper() != "RESET":
                    count += 1
    for child in node.get_children():
        count += _count_animation_clips(child)
    return count

func _triangle_count(root: Node) -> int:
    var meshes: Array[MeshInstance3D] = []
    _collect_meshes(root, meshes)
    var total := 0
    for mesh_node in meshes:
        if not mesh_node.visible or mesh_node.mesh == null:
            continue
        for surface in range(mesh_node.mesh.get_surface_count()):
            var arrays := mesh_node.mesh.surface_get_arrays(surface)
            if arrays.is_empty():
                continue
            var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
            if not indices.is_empty():
                total += indices.size() / 3
            else:
                var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
                total += vertices.size() / 3
    return total

func _bounds_in_root_space(root: Node3D) -> AABB:
    var meshes: Array[MeshInstance3D] = []
    _collect_meshes(root, meshes)
    var found := false
    var merged := AABB()
    for mesh_node in meshes:
        if not mesh_node.visible or mesh_node.mesh == null:
            continue
        var local := mesh_node.get_aabb()
        for x in [local.position.x, local.end.x]:
            for y in [local.position.y, local.end.y]:
                for z in [local.position.z, local.end.z]:
                    var point := root.to_local(mesh_node.to_global(Vector3(x, y, z)))
                    if not found:
                        merged = AABB(point, Vector3.ZERO)
                        found = true
                    else:
                        merged = merged.expand(point)
    return merged

func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D:
        out.append(node as MeshInstance3D)
    for child in node.get_children():
        _collect_meshes(child, out)

func _save_after_frames(path: String, frames: int) -> bool:
    for _i in range(frames):
        await process_frame
        await RenderingServer.frame_post_draw
    var image := get_root().get_viewport().get_texture().get_image()
    if image == null or image.is_empty():
        return false
    return image.save_png(path) == OK

func _fail(message: String) -> void:
    push_error("GB_CIV1_VITRUVIAN_WITNESS_FAIL: %s" % message)
    quit(2)

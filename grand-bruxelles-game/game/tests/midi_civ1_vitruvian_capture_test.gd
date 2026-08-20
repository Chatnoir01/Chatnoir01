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

    var body_material_audit := _apply_body_review_materials(body)
    var head_material_audit := _apply_head_review_materials(head)
    _apply_hair_review_material(hair)
    _keep_brows_only(brows)
    if int(body_material_audit.get("shirt", 0)) <= 0 or int(body_material_audit.get("pants", 0)) <= 0 or int(body_material_audit.get("shoes", 0)) <= 0:
        _fail("body authored material names not found: %s" % JSON.stringify(body_material_audit))
        return
    if int(head_material_audit.get("skin", 0)) <= 0:
        _fail("head VitSkin surface not found: %s" % JSON.stringify(head_material_audit))
        return

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
    # RED run 5 proved 180° faced the authored civilian away from the camera.
    # Vitruvian's authored forward is +Z in this import; keep zero yaw for front proof.
    candidate.rotation_degrees = Vector3.ZERO

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
        camera.global_position = target + Vector3(0.12, 0.04, distance)
        camera.look_at(target, Vector3.UP)
        var label := "%dm" % int(distance)
        var path := "%s_%s.png" % [base_output, label]
        if not await _save_after_frames(path, 12):
            _fail("capture failed at %s" % label)
            return
        outputs[label] = path

    var close_three_quarter := "%s_2m_three_quarter.png" % base_output
    camera.global_position = target + Vector3(1.22, 0.08, 1.58)
    camera.look_at(target, Vector3.UP)
    if not await _save_after_frames(close_three_quarter, 12):
        _fail("three-quarter capture failed")
        return
    outputs["2m_three_quarter"] = close_three_quarter

    # Dedicated grounding proof: feet and street surface must be visible together.
    var feet_path := "%s_feet_ground.png" % base_output
    var feet_target := candidate.global_position + Vector3(0.0, 0.10, 0.0)
    camera.fov = 38.0
    camera.global_position = feet_target + Vector3(0.16, 0.18, 1.28)
    camera.look_at(feet_target, Vector3.UP)
    if not await _save_after_frames(feet_path, 12):
        _fail("feet/ground capture failed")
        return
    outputs["feet_ground"] = feet_path

    var metrics := {
        "schema": "grand-bruxelles-civ1-vitruvian-witness-v2",
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
        "front_proof": true,
        "feet_ground_proof": true,
        "compatibility_pbr_materials": true,
        "body_material_audit": body_material_audit,
        "head_material_audit": head_material_audit,
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

    print("GB_CIV1_VITRUVIAN_WITNESS_OK height=%.3f triangles=%d animations=%d captures=front_2m,front_5m,front_8m,three_quarter,feet production_authorized=false" % [bounds.size.y, triangles, animation_clips])
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

func _tex(name: String) -> Texture2D:
    var path := REVIEW_ROOT + "/" + name
    return ResourceLoader.load(path) as Texture2D if ResourceLoader.exists(path) else null

func _pbr_skin(albedo_name: String, normal_name: String, rough_name: String) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color.WHITE
    mat.albedo_texture = _tex(albedo_name)
    mat.roughness = 0.86
    mat.roughness_texture = _tex(rough_name)
    mat.metallic = 0.0
    mat.metallic_specular = 0.30
    mat.normal_enabled = true
    mat.normal_texture = _tex(normal_name)
    mat.normal_scale = 0.85
    return mat

func _cloth(color: Color, roughness_value: float, normal_scale_value: float, uv_scale_value: float) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = roughness_value
    mat.metallic = 0.0
    mat.normal_enabled = true
    mat.normal_texture = _tex("vit_fabric_n.png")
    mat.normal_scale = normal_scale_value
    mat.uv1_triplanar = true
    mat.uv1_scale = Vector3(uv_scale_value, uv_scale_value, uv_scale_value)
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    return mat

func _apply_body_review_materials(root: Node) -> Dictionary:
    # Matches the upstream authored look-dev intent, but with StandardMaterial3D
    # so the proof remains valid in Grand Bruxelles' GL Compatibility renderer.
    var skin := _pbr_skin("vit_body_bc.png", "vit_body_n.png", "vit_body_rough.png")
    var shirt := _cloth(Color(0.18, 0.22, 0.30), 0.88, 0.55, 26.0)
    var pants := _cloth(Color(0.12, 0.12, 0.14), 0.82, 0.40, 40.0)
    var shoes := StandardMaterial3D.new()
    shoes.albedo_color = Color(0.07, 0.06, 0.06)
    shoes.roughness = 0.50
    var audit := {"skin": 0, "shirt": 0, "pants": 0, "shoes": 0, "unknown_names": []}
    var meshes: Array[MeshInstance3D] = []
    _collect_meshes(root, meshes)
    for mesh_node in meshes:
        if mesh_node.mesh == null:
            continue
        for surface in range(mesh_node.mesh.get_surface_count()):
            var source_material := mesh_node.mesh.surface_get_material(surface)
            var source_name := (source_material.resource_name if source_material != null else "").split(".")[0]
            match source_name:
                "VitShirt":
                    mesh_node.set_surface_override_material(surface, shirt)
                    audit["shirt"] = int(audit["shirt"]) + 1
                "VitPants":
                    mesh_node.set_surface_override_material(surface, pants)
                    audit["pants"] = int(audit["pants"]) + 1
                "VitShoes":
                    mesh_node.set_surface_override_material(surface, shoes)
                    audit["shoes"] = int(audit["shoes"]) + 1
                _:
                    mesh_node.set_surface_override_material(surface, skin)
                    audit["skin"] = int(audit["skin"]) + 1
                    if source_name != "" and source_name not in audit["unknown_names"]:
                        audit["unknown_names"].append(source_name)
    print("GB_CIV1_BODY_MATERIALS ", JSON.stringify(audit))
    return audit

func _apply_head_review_materials(root: Node) -> Dictionary:
    var face_skin := _pbr_skin("vit_face_bc.png", "vit_face_n.png", "vit_face_rough.png")
    face_skin.roughness = 0.80
    face_skin.metallic_specular = 0.34

    var mouth := StandardMaterial3D.new()
    mouth.albedo_texture = _tex("vit_mouth.png")
    mouth.roughness = 0.52

    var sclera := StandardMaterial3D.new()
    sclera.albedo_texture = _tex("vit_sclera.png")
    sclera.albedo_color = Color(0.96, 0.94, 0.93, 1.0)
    sclera.roughness = 0.18
    sclera.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

    var iris := StandardMaterial3D.new()
    iris.albedo_texture = _tex("vit_iris.png")
    iris.roughness = 0.55

    var eyeball := StandardMaterial3D.new()
    eyeball.albedo_color = Color(0.88, 0.85, 0.82)
    eyeball.roughness = 0.18

    var transparent := StandardMaterial3D.new()
    transparent.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    transparent.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
    transparent.roughness = 0.05
    transparent.cull_mode = BaseMaterial3D.CULL_DISABLED

    var tearline := StandardMaterial3D.new()
    tearline.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    tearline.albedo_color = Color(0.30, 0.36, 0.42, 0.12)
    tearline.roughness = 0.04

    var caruncle := StandardMaterial3D.new()
    caruncle.albedo_color = Color(0.70, 0.34, 0.30)
    caruncle.roughness = 0.38

    var eye_back := StandardMaterial3D.new()
    eye_back.albedo_color = Color(0.008, 0.007, 0.008)
    eye_back.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

    var audit := {"skin": 0, "mouth": 0, "sclera": 0, "iris": 0, "eyeball": 0, "transparent": 0, "other": 0}
    var meshes: Array[MeshInstance3D] = []
    _collect_meshes(root, meshes)
    for mesh_node in meshes:
        if mesh_node.mesh == null:
            continue
        for surface in range(mesh_node.mesh.get_surface_count()):
            var source_material := mesh_node.mesh.surface_get_material(surface)
            var source_name := (source_material.resource_name if source_material != null else "").split(".")[0]
            match source_name:
                "VitSkin":
                    mesh_node.set_surface_override_material(surface, face_skin)
                    audit["skin"] = int(audit["skin"]) + 1
                "VitMouth":
                    mesh_node.set_surface_override_material(surface, mouth)
                    audit["mouth"] = int(audit["mouth"]) + 1
                "VitSclera":
                    mesh_node.set_surface_override_material(surface, sclera)
                    audit["sclera"] = int(audit["sclera"]) + 1
                "VitIris":
                    mesh_node.set_surface_override_material(surface, iris)
                    audit["iris"] = int(audit["iris"]) + 1
                "VitEyeball":
                    mesh_node.set_surface_override_material(surface, eyeball)
                    audit["eyeball"] = int(audit["eyeball"]) + 1
                "VitTearline":
                    mesh_node.set_surface_override_material(surface, tearline)
                    audit["other"] = int(audit["other"]) + 1
                "VitCaruncle":
                    mesh_node.set_surface_override_material(surface, caruncle)
                    audit["other"] = int(audit["other"]) + 1
                "VitEyeBack":
                    mesh_node.set_surface_override_material(surface, eye_back)
                    audit["other"] = int(audit["other"]) + 1
                "VitScalp", "VitEyeshadow", "VitCornea", "VitCornea2":
                    mesh_node.set_surface_override_material(surface, transparent)
                    audit["transparent"] = int(audit["transparent"]) + 1
                _:
                    audit["other"] = int(audit["other"]) + 1
    print("GB_CIV1_HEAD_MATERIALS ", JSON.stringify(audit))
    return audit

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
    mat.set_shader_parameter("root_color", Color(0.34, 0.24, 0.15, 1.0))
    mat.set_shader_parameter("tip_color", Color(0.66, 0.52, 0.36, 1.0))
    mat.set_shader_parameter("brightness", 3.1)
    mat.set_shader_parameter("diffuse_mix", 1.0)
    mat.set_shader_parameter("normal_strength", 0.8)
    mat.set_shader_parameter("ao_strength", 0.7)
    mat.set_shader_parameter("roughness_val", 0.84)
    mat.set_shader_parameter("specular_val", 0.12)
    mat.set_shader_parameter("anisotropy_val", 0.30)
    mat.set_shader_parameter("tonal_variation", 0.45)
    mat.set_shader_parameter("clump_count", 55.0)
    mat.set_shader_parameter("tip_lighten", 0.18)
    mat.set_shader_parameter("emit", 0.10)
    mat.set_shader_parameter("backlight_color", Color(0.30, 0.17, 0.08, 1.0))
    mat.set_shader_parameter("backlight_strength", 0.30)
    mat.set_shader_parameter("density", 1.0)
    mat.set_shader_parameter("scissor", 0.12)
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
    mat.set_shader_parameter("hair_color", Color(0.11, 0.078, 0.05, 1.0))
    mat.set_shader_parameter("coverage_atlas", atlas)
    mat.set_shader_parameter("use_red_mask", true)
    mat.set_shader_parameter("invert_mask", false)
    mat.set_shader_parameter("alpha_threshold", 0.28)
    mat.set_shader_parameter("root_darkening", 0.45)
    mat.set_shader_parameter("roughness_val", 0.92)
    mat.set_shader_parameter("specular_val", 0.02)
    mat.set_shader_parameter("anisotropy", 0.05)
    mat.set_shader_parameter("tonal_variation", 0.20)
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

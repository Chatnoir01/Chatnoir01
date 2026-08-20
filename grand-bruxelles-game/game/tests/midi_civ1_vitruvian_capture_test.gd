extends SceneTree

const REVIEW_ROOT := "res://assets/characters/_review/vitruvian_civ1_v1"
const BODY := REVIEW_ROOT + "/vitruvian_body.glb"
const HEAD := REVIEW_ROOT + "/vitruvian_head.glb"
const HAIR := REVIEW_ROOT + "/hairtool_cards.glb"
const BROWS := REVIEW_ROOT + "/vitruvian_hair.glb"
const SHOES := REVIEW_ROOT + "/shoes04_cc0.obj"
const HAIR_SHADER := REVIEW_ROOT + "/hairtool_card.gdshader"
const BROW_SHADER := REVIEW_ROOT + "/hair_card.gdshader"
const MAIN_SCENE := "res://game/main.tscn"
const CAPTURE_SIZE := Vector2i(1280, 720)
const DISTANCES := [2.0, 5.0, 8.0]
const MIN_HEIGHT_M := 1.40
const MAX_HEIGHT_M := 2.20
const MAX_TRIANGLES := 700000

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var base_output := "/tmp/midi-civ1-vitruvian"
    var args := OS.get_cmdline_user_args()
    if not args.is_empty():
        base_output = str(args[0]).get_basename()

    for path: String in [BODY, HEAD, HAIR, BROWS, SHOES, HAIR_SHADER, BROW_SHADER, MAIN_SCENE]:
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
    candidate.set_meta("footwear_source", "furqonat/makehuman-assets@8cf9645b975a98eea056b140df11a1d278da0d10:base/clothes/shoes04/shoes04.obj")
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
    if int(body_material_audit.get("shirt", 0)) <= 0 or int(body_material_audit.get("pants", 0)) <= 0 or int(body_material_audit.get("painted_shoe_hidden", 0)) <= 0:
        _fail("body authored material names not found: %s" % JSON.stringify(body_material_audit))
        return
    if int(head_material_audit.get("skin", 0)) <= 0:
        _fail("head VitSkin surface not found: %s" % JSON.stringify(head_material_audit))
        return

    # Do not guess about rig ownership. If a Skeleton3D survived the legal preparation,
    # apply only a small upper-arm relaxation and report exactly what happened. If the
    # body is static/baked, leave it untouched and keep the human visual gate RED.
    var pose_audit := _relax_pose_if_rigged(body)

    var pre_footwear_bounds := _bounds_in_root_space(candidate)
    var footwear_audit := _add_cc0_footwear(candidate, pre_footwear_bounds)
    if not bool(footwear_audit.get("added", false)):
        _fail("CC0 footwear could not be staged: %s" % JSON.stringify(footwear_audit))
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

    candidate.global_position = player.global_position + Vector3(3.2, 0.0, -1.6)
    candidate.global_position.y = player.global_position.y - bounds.position.y
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

    var feet_path := "%s_feet_ground.png" % base_output
    var feet_target := candidate.global_position + Vector3(0.0, 0.12, 0.0)
    camera.fov = 38.0
    camera.global_position = feet_target + Vector3(0.18, 0.20, 1.18)
    camera.look_at(feet_target, Vector3.UP)
    if not await _save_after_frames(feet_path, 12):
        _fail("feet/ground capture failed")
        return
    outputs["feet_ground"] = feet_path

    var metrics := {
        "schema": "grand-bruxelles-civ1-vitruvian-witness-v3",
        "production_authorized": false,
        "actual_scene": MAIN_SCENE,
        "base_main_sha": "75345935173ba11ead85c317786f9e31e4517afd",
        "upstream_commit": "bdecdcd537b4031fdd0fb299b7e4f93f084fffa0",
        "character_license": "CC0-1.0",
        "footwear_license": "CC0-1.0",
        "footwear_source_commit": "8cf9645b975a98eea056b140df11a1d278da0d10",
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
        "real_footwear_geometry": true,
        "body_material_audit": body_material_audit,
        "head_material_audit": head_material_audit,
        "footwear_audit": footwear_audit,
        "pose_audit": pose_audit,
        "fallback_changed": false,
        "movement_navigation_density_changed": false,
        "human_verdict_required": "GARDER"
    }
    var metrics_path := "%s.metrics.json" % base_output
    var file := FileAccess.open(metrics_path, FileAccess.WRITE)
    if file == null:
        _fail("could not write metrics")
        return
    file.store_string(JSON.stringify(metrics, "  ") + "\n")
    file.close()

    print("GB_CIV1_VITRUVIAN_WITNESS_OK height=%.3f triangles=%d animations=%d footwear=cc0 pose_applied=%s production_authorized=false" % [bounds.size.y, triangles, animation_clips, str(pose_audit.get("applied", false))])
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

func _hidden_material() -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    mat.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
    mat.roughness = 1.0
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    return mat

func _apply_body_review_materials(root: Node) -> Dictionary:
    var skin := _pbr_skin("vit_body_bc.png", "vit_body_n.png", "vit_body_rough.png")
    var shirt := _cloth(Color(0.18, 0.22, 0.30), 0.88, 0.55, 26.0)
    var pants := _cloth(Color(0.12, 0.12, 0.14), 0.82, 0.40, 40.0)
    var hidden_shoe := _hidden_material()
    var audit := {"skin": 0, "shirt": 0, "pants": 0, "painted_shoe_hidden": 0, "unknown_names": []}
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
                    mesh_node.set_surface_override_material(surface, hidden_shoe)
                    audit["painted_shoe_hidden"] = int(audit["painted_shoe_hidden"]) + 1
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
    var transparent := _hidden_material()
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
                "VitSkin": mesh_node.set_surface_override_material(surface, face_skin); audit["skin"] = int(audit["skin"]) + 1
                "VitMouth": mesh_node.set_surface_override_material(surface, mouth); audit["mouth"] = int(audit["mouth"]) + 1
                "VitSclera": mesh_node.set_surface_override_material(surface, sclera); audit["sclera"] = int(audit["sclera"]) + 1
                "VitIris": mesh_node.set_surface_override_material(surface, iris); audit["iris"] = int(audit["iris"]) + 1
                "VitEyeball": mesh_node.set_surface_override_material(surface, eyeball); audit["eyeball"] = int(audit["eyeball"]) + 1
                "VitTearline": mesh_node.set_surface_override_material(surface, tearline); audit["other"] = int(audit["other"]) + 1
                "VitCaruncle": mesh_node.set_surface_override_material(surface, caruncle); audit["other"] = int(audit["other"]) + 1
                "VitEyeBack": mesh_node.set_surface_override_material(surface, eye_back); audit["other"] = int(audit["other"]) + 1
                "VitScalp", "VitEyeshadow", "VitCornea", "VitCornea2": mesh_node.set_surface_override_material(surface, transparent); audit["transparent"] = int(audit["transparent"]) + 1
                _: audit["other"] = int(audit["other"]) + 1
    print("GB_CIV1_HEAD_MATERIALS ", JSON.stringify(audit))
    return audit

func _add_cc0_footwear(candidate: Node3D, body_bounds: AABB) -> Dictionary:
    var shoe_mesh := ResourceLoader.load(SHOES) as Mesh
    if shoe_mesh == null:
        return {"added": false, "reason": "OBJ did not import as Mesh"}
    var source := shoe_mesh.get_aabb()
    if source.size.x <= 0.001 or source.size.y <= 0.001 or source.size.z <= 0.001:
        return {"added": false, "reason": "invalid shoe AABB", "source_aabb": str(source)}

    var node := MeshInstance3D.new()
    node.name = "Shoes04_CC0_Review"
    node.mesh = shoe_mesh
    node.set_meta("source", "furqonat/makehuman-assets@8cf9645b975a98eea056b140df11a1d278da0d10")
    node.set_meta("license", "CC0-1.0")
    candidate.add_child(node)

    var target_pair_width := 0.38
    var target_height := 0.115
    var target_length := 0.29
    node.scale = Vector3(
        target_pair_width / source.size.x,
        target_height / source.size.y,
        target_length / source.size.z
    )
    var source_center := source.position + source.size * 0.5
    node.position.x = -source_center.x * node.scale.x
    node.position.z = -source_center.z * node.scale.z + 0.015
    node.position.y = body_bounds.position.y - source.position.y * node.scale.y - 0.004

    var shoe_mat := StandardMaterial3D.new()
    shoe_mat.albedo_color = Color(0.055, 0.052, 0.050)
    shoe_mat.roughness = 0.56
    shoe_mat.metallic = 0.0
    shoe_mat.metallic_specular = 0.22
    for surface in range(shoe_mesh.get_surface_count()):
        node.set_surface_override_material(surface, shoe_mat)

    var scaled_size := Vector3(
        source.size.x * node.scale.x,
        source.size.y * node.scale.y,
        source.size.z * node.scale.z
    )
    var audit := {
        "added": true,
        "source_aabb": str(source),
        "target_pair_size_m": [scaled_size.x, scaled_size.y, scaled_size.z],
        "scale": [node.scale.x, node.scale.y, node.scale.z],
        "position": [node.position.x, node.position.y, node.position.z],
        "source_commit": "8cf9645b975a98eea056b140df11a1d278da0d10",
        "license": "CC0-1.0"
    }
    print("GB_CIV1_FOOTWEAR ", JSON.stringify(audit))
    return audit

func _relax_pose_if_rigged(root: Node) -> Dictionary:
    var skeleton := _find_skeleton(root)
    if skeleton == null:
        var no_rig := {"applied": false, "reason": "body export is static/baked; no Skeleton3D"}
        print("GB_CIV1_POSE ", JSON.stringify(no_rig))
        return no_rig

    var left := skeleton.find_bone("LeftArm")
    var right := skeleton.find_bone("RightArm")
    if left < 0 or right < 0:
        var names: Array[String] = []
        for i in range(skeleton.get_bone_count()):
            names.append(skeleton.get_bone_name(i))
        var missing := {"applied": false, "reason": "expected arm bones missing", "bone_names": names}
        print("GB_CIV1_POSE ", JSON.stringify(missing))
        return missing

    # Run #12 proved the opposite signs raise the authored A-pose toward a T-pose.
    # Reverse only the measured sign so both upper arms move down toward the torso.
    skeleton.set_bone_pose_rotation(left, Quaternion(Vector3(0.0, 0.0, 1.0), deg_to_rad(24.0)))
    skeleton.set_bone_pose_rotation(right, Quaternion(Vector3(0.0, 0.0, 1.0), deg_to_rad(-24.0)))
    var applied := {"applied": true, "left_bone": skeleton.get_bone_name(left), "right_bone": skeleton.get_bone_name(right), "extra_upper_arm_degrees": 24.0, "direction_verified_from_red_run": 12}
    print("GB_CIV1_POSE ", JSON.stringify(applied))
    return applied

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node as Skeleton3D
    for child in node.get_children():
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null

func _apply_hair_review_material(root: Node) -> void:
    var shader := ResourceLoader.load(HAIR_SHADER) as Shader
    var diffuse := _tex("vit_hair_diffuse.png")
    var normal := _tex("vit_hair_normal.png")
    var ao := _tex("vit_hair_ao.png")
    var opacity := _tex("vit_hair_opacity.png")
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
    var atlas := _tex("vit_hair_atlas.png")
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

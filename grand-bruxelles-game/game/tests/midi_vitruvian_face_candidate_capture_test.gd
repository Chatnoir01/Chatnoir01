extends SceneTree

const REVIEW_ROOT := "res://assets/characters/_review/vitruvian_face_v1"
const HEAD_RESOURCE := REVIEW_ROOT + "/vitruvian_head.glb"
const HAIR_RESOURCE := REVIEW_ROOT + "/hairtool_cards.glb"
const BROW_RESOURCE := REVIEW_ROOT + "/vitruvian_hair.glb"
const HAIR_SHADER_PATH := REVIEW_ROOT + "/hairtool_card.gdshader"
const BROW_SHADER_PATH := REVIEW_ROOT + "/hair_card.gdshader"
const CORNEA_SHADER_PATH := "res://addons/eyeball_shader/shaders/cornea.gdshader"
const WITNESS_SIZE := Vector2i(1280, 720)
const MIN_BLEND_SHAPES := 12
const MAX_FACE_PILOT_TRIANGLES := 450000

const REQUIRED_TEXTURES := {
    "face_bc": REVIEW_ROOT + "/vit_face_bc.png",
    "face_n": REVIEW_ROOT + "/vit_face_n.png",
    "face_rough": REVIEW_ROOT + "/vit_face_rough.png",
    "mouth": REVIEW_ROOT + "/vit_mouth.png",
    "sclera": REVIEW_ROOT + "/vit_sclera.png",
    "iris": REVIEW_ROOT + "/vit_iris.png",
    "lash": REVIEW_ROOT + "/vit_lash_atlas.png",
    "hair_diffuse": REVIEW_ROOT + "/vit_hair_diffuse.png",
    "hair_normal": REVIEW_ROOT + "/vit_hair_normal.png",
    "hair_ao": REVIEW_ROOT + "/vit_hair_ao.png",
    "hair_opacity": REVIEW_ROOT + "/vit_hair_opacity.png",
    "hair_atlas": REVIEW_ROOT + "/vit_hair_atlas.png",
}

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var output := "/tmp/midi-vitruvian-face-candidate.png"
    var args := OS.get_cmdline_user_args()
    if not args.is_empty():
        output = str(args[0])

    for path in [HEAD_RESOURCE, HAIR_RESOURCE, BROW_RESOURCE, HAIR_SHADER_PATH, BROW_SHADER_PATH, CORNEA_SHADER_PATH]:
        if not ResourceLoader.exists(path):
            _fail("required review resource missing: %s" % path)
            return
    for key in REQUIRED_TEXTURES:
        if not ResourceLoader.exists(str(REQUIRED_TEXTURES[key])):
            _fail("required review texture missing: %s" % str(REQUIRED_TEXTURES[key]))
            return

    var head := _instantiate(HEAD_RESOURCE, "VitruvianHead")
    var hair := _instantiate(HAIR_RESOURCE, "VitruvianHair")
    var brows := _instantiate(BROW_RESOURCE, "VitruvianLegacyBrows")
    if head == null or hair == null or brows == null:
        return

    var viewport := SubViewport.new()
    viewport.size = WITNESS_SIZE
    viewport.own_world_3d = true
    viewport.transparent_bg = false
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
    viewport.msaa_3d = Viewport.MSAA_4X
    get_root().add_child(viewport)

    var world := Node3D.new()
    viewport.add_child(world)
    var character := Node3D.new()
    character.name = "VitruvianFaceReviewOnly"
    world.add_child(character)
    character.add_child(head)
    character.add_child(hair)
    character.add_child(brows)

    var animation_clips := _count_animation_clips(character)
    if animation_clips != 0:
        _fail("face pilot must contain zero animation clips, found %d" % animation_clips)
        return

    var textures := _load_textures()
    if textures.is_empty():
        return
    var roles := _apply_head_materials(head, textures)
    if int(roles.get("skin", 0)) < 1 or int(roles.get("mouth", 0)) < 1:
        _fail("required skin/mouth material roles missing: %s" % str(roles))
        return
    if int(roles.get("sclera", 0)) < 2 or int(roles.get("iris", 0)) < 2 or int(roles.get("cornea", 0)) < 2:
        _fail("expected paired real-eye surfaces: %s" % str(roles))
        return

    var hair_meshes := _apply_hair_material(hair, textures)
    var brow_meshes := _keep_brows_only(brows, textures)
    if hair_meshes < 1 or brow_meshes < 1:
        _fail("hair/brow source missing: hair=%d brows=%d" % [hair_meshes, brow_meshes])
        return

    var blend_shapes := _blend_shape_count(head)
    if blend_shapes < MIN_BLEND_SHAPES:
        _fail("FACS floor missed: %d < %d" % [blend_shapes, MIN_BLEND_SHAPES])
        return
    var triangles := _triangle_count(character)
    if triangles <= 0 or triangles > MAX_FACE_PILOT_TRIANGLES:
        _fail("face triangle budget invalid: %d" % triangles)
        return

    var head_bounds := _bounds_in_root_space(head)
    var combined_bounds := _bounds_in_root_space(character)
    if head_bounds.size.y < 0.15 or head_bounds.size.y > 0.50:
        _fail("head metre scale implausible: %s" % str(head_bounds))
        return
    if combined_bounds.size.y <= 0.01:
        _fail("combined bounds invalid")
        return

    _build_lighting(world)
    var target := head_bounds.position + head_bounds.size * 0.5
    target.y += head_bounds.size.y * 0.02
    var camera := Camera3D.new()
    camera.near = 0.03
    world.add_child(camera)
    camera.current = true

    camera.position = target + Vector3(0.0, 0.02, 2.20)
    camera.fov = 43.0
    camera.look_at(target, Vector3.UP)
    if not await _save_after_frames(viewport, output, 18):
        _fail("player-distance capture failed")
        return

    camera.position = target + Vector3(0.0, 0.02, 1.48)
    camera.fov = 39.0
    camera.look_at(target, Vector3.UP)
    var close_output := output.get_basename() + "_close.png"
    if not await _save_after_frames(viewport, close_output, 10):
        _fail("close capture failed")
        return

    camera.position = target + Vector3(1.25, 0.06, 1.55)
    camera.fov = 43.0
    camera.look_at(target, Vector3.UP)
    var three_quarter_output := output.get_basename() + "_three_quarter.png"
    if not await _save_after_frames(viewport, three_quarter_output, 10):
        _fail("three-quarter capture failed")
        return

    var metrics := {
        "schema": "grand-bruxelles-vitruvian-face-witness-v2",
        "production_authorized": false,
        "review_scope": "face_hair_brows_only_pre_full_body",
        "upstream_repo": "ibrews/VitruvianGodot",
        "upstream_commit": "bdecdcd537b4031fdd0fb299b7e4f93f084fffa0",
        "renderer": "gl_compatibility",
        "eye_pipeline": "current_upstream_real_sclera_iris_eyeback_cornea2",
        "mixamo_payload_allowed": false,
        "animation_clip_count": animation_clips,
        "blend_shape_count": blend_shapes,
        "triangle_count": triangles,
        "head_material_roles": roles,
        "hair_mesh_count": hair_meshes,
        "brow_mesh_count": brow_meshes,
        "resolution": [WITNESS_SIZE.x, WITNESS_SIZE.y],
        "player_distance_png": output,
        "close_png": close_output,
        "three_quarter_png": three_quarter_output,
        "full_body_required_before_promotion": true,
    }
    var metrics_path := output.get_basename() + ".metrics.json"
    var f := FileAccess.open(metrics_path, FileAccess.WRITE)
    if f == null:
        _fail("metrics write failed")
        return
    f.store_string(JSON.stringify(metrics, "  ") + "\n")
    f.close()

    print("MIDI_VITRUVIAN_FACE_OK player=%s close=%s three_quarter=%s triangles=%d blend_shapes=%d animations=%d hair=%d brows=%d production_authorized=false" % [output, close_output, three_quarter_output, triangles, blend_shapes, animation_clips, hair_meshes, brow_meshes])
    quit(0)

func _instantiate(path: String, label: String) -> Node3D:
    var packed := ResourceLoader.load(path) as PackedScene
    if packed == null:
        _fail("%s did not import as PackedScene" % label)
        return null
    var node := packed.instantiate() as Node3D
    if node == null:
        _fail("%s could not instantiate" % label)
        return null
    node.name = label
    return node

func _load_textures() -> Dictionary:
    var out := {}
    for key in REQUIRED_TEXTURES:
        var texture := ResourceLoader.load(str(REQUIRED_TEXTURES[key])) as Texture2D
        if texture == null:
            _fail("texture import failed: %s" % str(REQUIRED_TEXTURES[key]))
            return {}
        out[key] = texture
    return out

func _apply_head_materials(root: Node, textures: Dictionary) -> Dictionary:
    var roles := {"skin": 0, "mouth": 0, "sclera": 0, "iris": 0, "eye_back": 0, "cornea": 0, "tearline": 0, "caruncle": 0, "eyeshadow": 0, "unknown": 0}

    var skin := StandardMaterial3D.new()
    skin.albedo_texture = textures["face_bc"] as Texture2D
    skin.normal_enabled = true
    skin.normal_texture = textures["face_n"] as Texture2D
    skin.normal_scale = 0.70
    skin.roughness = 0.56
    skin.roughness_texture = textures["face_rough"] as Texture2D
    skin.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED

    var mouth := StandardMaterial3D.new()
    mouth.albedo_texture = textures["mouth"] as Texture2D
    mouth.roughness = 0.46

    var sclera := StandardMaterial3D.new()
    sclera.albedo_texture = textures["sclera"] as Texture2D
    sclera.albedo_color = Color(0.96, 0.94, 0.93, 1.0)
    sclera.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    sclera.cull_mode = BaseMaterial3D.CULL_BACK
    sclera.roughness = 0.34
    sclera.metallic_specular = 0.45

    var iris := StandardMaterial3D.new()
    iris.albedo_texture = textures["iris"] as Texture2D
    iris.roughness = 0.55
    iris.metallic_specular = 0.28

    var eye_back := StandardMaterial3D.new()
    eye_back.albedo_color = Color(0.008, 0.007, 0.008)
    eye_back.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

    var cornea_shader := ResourceLoader.load(CORNEA_SHADER_PATH) as Shader
    var cornea := ShaderMaterial.new()
    cornea.shader = cornea_shader
    cornea.set_shader_parameter("shininess", 230.0)
    cornea.set_shader_parameter("spec_intensity", 0.30)
    cornea.set_shader_parameter("alpha_max", 0.70)

    var tearline := StandardMaterial3D.new()
    tearline.albedo_color = Color(0.93, 0.95, 0.98, 0.16)
    tearline.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    tearline.roughness = 0.18
    tearline.cull_mode = BaseMaterial3D.CULL_DISABLED

    var caruncle := StandardMaterial3D.new()
    caruncle.albedo_color = Color(0.36, 0.10, 0.095)
    caruncle.roughness = 0.52

    var eyeshadow := StandardMaterial3D.new()
    eyeshadow.albedo_color = Color(0.12, 0.07, 0.055, 0.12)
    eyeshadow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    eyeshadow.cull_mode = BaseMaterial3D.CULL_DISABLED
    eyeshadow.roughness = 0.72

    var meshes: Array[MeshInstance3D] = []
    _collect_meshes(root, meshes)
    for mesh_node in meshes:
        if mesh_node.mesh == null:
            continue
        for s in range(mesh_node.mesh.get_surface_count()):
            var src := mesh_node.mesh.surface_get_material(s)
            var role := str(src.resource_name).split(".")[0] if src != null else ""
            match role:
                "VitSkin": mesh_node.set_surface_override_material(s, skin); roles["skin"] = int(roles["skin"]) + 1
                "VitMouth": mesh_node.set_surface_override_material(s, mouth); roles["mouth"] = int(roles["mouth"]) + 1
                "VitSclera": mesh_node.set_surface_override_material(s, sclera); roles["sclera"] = int(roles["sclera"]) + 1
                "VitIris": mesh_node.set_surface_override_material(s, iris); roles["iris"] = int(roles["iris"]) + 1
                "VitEyeBack": mesh_node.set_surface_override_material(s, eye_back); roles["eye_back"] = int(roles["eye_back"]) + 1
                "VitCornea2": mesh_node.set_surface_override_material(s, cornea); roles["cornea"] = int(roles["cornea"]) + 1
                "VitTearline": mesh_node.set_surface_override_material(s, tearline); roles["tearline"] = int(roles["tearline"]) + 1
                "VitCaruncle": mesh_node.set_surface_override_material(s, caruncle); roles["caruncle"] = int(roles["caruncle"]) + 1
                "VitEyeshadow": mesh_node.set_surface_override_material(s, eyeshadow); roles["eyeshadow"] = int(roles["eyeshadow"]) + 1
                _: roles["unknown"] = int(roles["unknown"]) + 1
    return roles

func _apply_hair_material(root: Node, textures: Dictionary) -> int:
    var shader := ResourceLoader.load(HAIR_SHADER_PATH) as Shader
    var mat := ShaderMaterial.new()
    mat.shader = shader
    mat.set_shader_parameter("tex_diffuse", textures["hair_diffuse"])
    mat.set_shader_parameter("tex_normal", textures["hair_normal"])
    mat.set_shader_parameter("tex_ao", textures["hair_ao"])
    mat.set_shader_parameter("tex_opacity", textures["hair_opacity"])
    mat.set_shader_parameter("root_color", Color(0.30, 0.205, 0.13, 1.0))
    mat.set_shader_parameter("tip_color", Color(0.39, 0.29, 0.19, 1.0))
    mat.set_shader_parameter("brightness", 2.65)
    mat.set_shader_parameter("diffuse_mix", 0.85)
    mat.set_shader_parameter("normal_strength", 0.85)
    mat.set_shader_parameter("ao_strength", 0.60)
    mat.set_shader_parameter("roughness_val", 0.78)
    mat.set_shader_parameter("specular_val", 0.20)
    mat.set_shader_parameter("anisotropy_val", 0.25)
    mat.set_shader_parameter("tonal_variation", 0.22)
    mat.set_shader_parameter("tip_lighten", 0.10)
    mat.set_shader_parameter("emit", 0.05)
    mat.set_shader_parameter("density", 1.0)
    mat.set_shader_parameter("scissor", 0.10)
    var meshes: Array[MeshInstance3D] = []
    _collect_meshes(root, meshes)
    var count := 0
    for mesh_node in meshes:
        if mesh_node.name.begins_with("VitBrow"):
            mesh_node.visible = false
            continue
        if mesh_node.mesh == null:
            continue
        count += 1
        for s in range(mesh_node.mesh.get_surface_count()):
            mesh_node.set_surface_override_material(s, mat)
    return count

func _keep_brows_only(root: Node, textures: Dictionary) -> int:
    var shader := ResourceLoader.load(BROW_SHADER_PATH) as Shader
    var mat := ShaderMaterial.new()
    mat.shader = shader
    mat.set_shader_parameter("hair_color", Color(0.095, 0.060, 0.038, 1.0))
    mat.set_shader_parameter("coverage_atlas", textures["hair_atlas"])
    mat.set_shader_parameter("alpha_threshold", 0.28)
    mat.set_shader_parameter("root_darkening", 0.45)
    mat.set_shader_parameter("roughness_val", 0.92)
    mat.set_shader_parameter("specular_val", 0.02)
    mat.set_shader_parameter("anisotropy", 0.05)
    var meshes: Array[MeshInstance3D] = []
    _collect_meshes(root, meshes)
    var kept := 0
    for mesh_node in meshes:
        if not mesh_node.name.begins_with("VitBrow"):
            mesh_node.visible = false
            continue
        if mesh_node.mesh == null:
            continue
        mesh_node.visible = true
        kept += 1
        for s in range(mesh_node.mesh.get_surface_count()):
            mesh_node.set_surface_override_material(s, mat)
    return kept

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

func _blend_shape_count(root: Node) -> int:
    var total := 0
    var meshes: Array[MeshInstance3D] = []
    _collect_meshes(root, meshes)
    for mesh_node in meshes:
        if mesh_node.mesh != null:
            total += mesh_node.mesh.get_blend_shape_count()
    return total

func _triangle_count(root: Node) -> int:
    var total := 0
    var meshes: Array[MeshInstance3D] = []
    _collect_meshes(root, meshes)
    for mesh_node in meshes:
        if not mesh_node.visible or mesh_node.mesh == null:
            continue
        for s in range(mesh_node.mesh.get_surface_count()):
            var arrays := mesh_node.mesh.surface_get_arrays(s)
            if arrays.is_empty():
                continue
            var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
            if not indices.is_empty():
                total += indices.size() / 3
            else:
                var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
                total += vertices.size() / 3
    return total

func _build_lighting(parent: Node3D) -> void:
    var key := DirectionalLight3D.new()
    key.rotation_degrees = Vector3(-44.0, -28.0, 0.0)
    key.light_energy = 0.78
    key.shadow_enabled = true
    parent.add_child(key)
    var fill := OmniLight3D.new()
    fill.position = Vector3(-1.8, 2.2, 2.0)
    fill.light_energy = 1.05
    fill.omni_range = 6.0
    parent.add_child(fill)
    var catch := OmniLight3D.new()
    catch.position = Vector3(0.65, 1.72, 1.10)
    catch.light_energy = 0.52
    catch.omni_range = 2.8
    parent.add_child(catch)
    var world_env := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.10, 0.115, 0.14)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.66, 0.70, 0.76)
    env.ambient_light_energy = 0.24
    world_env.environment = env
    parent.add_child(world_env)

func _save_after_frames(viewport: SubViewport, path: String, frames: int) -> bool:
    for _i in range(frames):
        await process_frame
        await RenderingServer.frame_post_draw
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty():
        return false
    return image.save_png(path) == OK

func _bounds_in_root_space(root: Node3D) -> AABB:
    var found := false
    var merged := AABB()
    var meshes: Array[MeshInstance3D] = []
    _collect_meshes(root, meshes)
    for mesh_node in meshes:
        if not mesh_node.visible or mesh_node.mesh == null:
            continue
        var local := mesh_node.get_aabb()
        for corner in [local.position, Vector3(local.end.x, local.position.y, local.position.z), Vector3(local.position.x, local.end.y, local.position.z), Vector3(local.end.x, local.end.y, local.position.z), Vector3(local.position.x, local.position.y, local.end.z), Vector3(local.end.x, local.position.y, local.end.z), Vector3(local.position.x, local.end.y, local.end.z), local.end]:
            var point := root.to_local(mesh_node.to_global(corner))
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

func _fail(message: String) -> void:
    push_error("MIDI_VITRUVIAN_FACE_FAIL: %s" % message)
    quit(2)

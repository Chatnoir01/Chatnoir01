extends Node

# Belgian police presentation bridge.
# Production ownership stays with the existing behavioral NpcAgent police.
# This runtime upgrades their visuals only; it never spawns a second/static police actor.
# The GTA-derived Belgian model stays optional/local-only until reuse rights are clear.
const LOCAL_MODEL_PATH := "res://assets/local_only/police_belge/popo_police_brussels_clean_v2.glb"
const EXPECTED_LOCAL_SHA256 := "22175980c6b2db3c1365f3092ef85a205b59d21e008344127d0113f35338f2f8"
const EXPECTED_LOCAL_BYTES := 1512048
const LOCAL_VISUAL_FOOT_OFFSET_Y := 1.01611328

const PUBLIC_BASE_MODEL_PATH := "res://assets/characters/player_character.glb"
const PUBLIC_BASE_LICENSE := "CC0-1.0"
# NpcAgent spawns are ground-origin. The public GLB is foot-origin, so unlike the
# centered Player capsule it must not inherit the player's -0.90 m visual offset.
const PUBLIC_BASE_POSITION := Vector3.ZERO
const PUBLIC_BASE_ROTATION_DEGREES := Vector3(0.0, 180.0, 0.0)

const SOURCE_GROUP := "police_officer"
const VISUAL_NODE_NAME := "BelgianPoliceVisual"
const VALID_ANIMATIONS := ["idle", "walk", "run", "chase", "arrest"]
const DESIGN_VERSION := "belgian-patrol-authored-v4"
const LEGACY_VISUAL_NAMES := [
    "VisibleHumanoid",
    "AuthoredNpcCharacter",
    "HumanoidVisual",
    "PolicePed",
]

var _bindings: Dictionary = {}
var _mount_attempts := 0
var _recolor_shader: Shader


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    get_tree().node_added.connect(_on_node_added)
    call_deferred("_mount_current_scene")


func _process(_delta: float) -> void:
    _sync_all_bindings()


func _mount_current_scene() -> void:
    var scene_root := get_tree().current_scene as Node3D
    if scene_root == null:
        _mount_attempts += 1
        if _mount_attempts <= 8:
            get_tree().process_frame.connect(_mount_current_scene, CONNECT_ONE_SHOT)
        return
    _upgrade_existing_police(scene_root, false)


func _on_node_added(node: Node) -> void:
    if node is NpcAgent and node.is_in_group(SOURCE_GROUP):
        call_deferred("_try_upgrade_node", node)


func _try_upgrade_node(node: Node) -> void:
    if is_instance_valid(node) and node is NpcAgent and node.is_in_group(SOURCE_GROUP):
        upgrade_agent(node as NpcAgent, false)


# Backward-compatible entry point: return an existing behavioral police agent after
# upgrading its visual. It intentionally never creates a standalone CharacterBody3D.
func mount_into(scene_root: Node3D, force_public: bool = false) -> CharacterBody3D:
    if scene_root == null:
        return null
    var upgraded := _upgrade_existing_police(scene_root, force_public)
    if upgraded.is_empty():
        return null
    return upgraded[0] as CharacterBody3D


func upgrade_agent(agent: NpcAgent, force_public: bool = false) -> bool:
    if agent == null or not is_instance_valid(agent):
        return false
    if not agent.is_in_group(SOURCE_GROUP) and agent.role != NpcBehaviorModel.Role.POLICE:
        return false

    var instance_id := agent.get_instance_id()
    var existing := agent.get_node_or_null(VISUAL_NODE_NAME) as Node3D
    if existing != null:
        _hide_legacy_visuals(agent, true)
        _register_binding(agent, existing)
        return true

    var visual: Node3D = null
    if not force_public:
        visual = _load_local_authored_visual()
    if visual == null:
        visual = _load_public_authored_visual()
    if visual == null:
        visual = _build_emergency_visual()
    if visual == null:
        _hide_legacy_visuals(agent, false)
        return false

    visual.name = VISUAL_NODE_NAME
    agent.add_child(visual)
    agent.add_to_group("belgian_police")
    agent.add_to_group("police_npc")
    agent.set_meta("visual_design", DESIGN_VERSION)
    agent.set_meta("belgian_police_visual_upgrade", true)
    _hide_legacy_visuals(agent, true)
    _register_binding(agent, visual)

    var binding: Dictionary = _bindings.get(instance_id, {})
    var player := binding.get("animation_player", null) as AnimationPlayer
    if player != null and _play_state_on(player, "idle", 0.0):
        binding["state"] = "idle"
        _bindings[instance_id] = binding
    return true


func sync_agent_for_test(agent: NpcAgent) -> void:
    if agent == null:
        return
    _sync_binding(agent.get_instance_id())


func set_police_animation(state: String) -> bool:
    if not VALID_ANIMATIONS.has(state):
        return false
    var played := false
    for instance_id in _bindings.keys():
        var binding: Dictionary = _bindings.get(instance_id, {})
        var player := binding.get("animation_player", null) as AnimationPlayer
        if player != null and _play_state_on(player, state, 0.16):
            binding["state"] = state
            _bindings[instance_id] = binding
            played = true
    return played


func get_runtime_metrics() -> Dictionary:
    _prune_bindings()
    var animation_names := PackedStringArray()
    var sources: Array[String] = []
    var local_active := false
    for instance_id in _bindings.keys():
        var binding: Dictionary = _bindings.get(instance_id, {})
        var source := str(binding.get("source", "none"))
        if not sources.has(source):
            sources.append(source)
        if source == "local_gta_derived":
            local_active = true
        var player := binding.get("animation_player", null) as AnimationPlayer
        if animation_names.is_empty() and player != null:
            animation_names = player.get_animation_list()

    var visual_source := "none"
    if sources.size() == 1:
        visual_source = sources[0]
    elif sources.size() > 1:
        visual_source = ",".join(sources)

    return {
        "mounted": not _bindings.is_empty(),
        "upgraded_police_count": _bindings.size(),
        "visual_source": visual_source,
        "authored_asset_active": local_active,
        "authored_asset_path": LOCAL_MODEL_PATH,
        "authored_asset_expected_sha256": EXPECTED_LOCAL_SHA256,
        "authored_asset_expected_bytes": EXPECTED_LOCAL_BYTES,
        "redistribution_authorized": false,
        "public_visual_path": PUBLIC_BASE_MODEL_PATH,
        "public_visual_license": PUBLIC_BASE_LICENSE,
        "public_visual_redistribution_authorized": true,
        "available_animations": animation_names,
        "design_version": DESIGN_VERSION,
        "equipment_count": 12,
        "source_group": SOURCE_GROUP,
        "preserves_npc_agent": true,
        "standalone_actor_spawned": false,
        "changes_navigation": false,
        "changes_police_response": false,
    }


func _upgrade_existing_police(scene_root: Node3D, force_public: bool) -> Array[NpcAgent]:
    var upgraded: Array[NpcAgent] = []
    if scene_root == null:
        return upgraded
    for node: Node in get_tree().get_nodes_in_group(SOURCE_GROUP):
        if not node is NpcAgent:
            continue
        var agent := node as NpcAgent
        if agent != scene_root and not scene_root.is_ancestor_of(agent):
            continue
        if upgrade_agent(agent, force_public):
            upgraded.append(agent)
    return upgraded


func _register_binding(agent: NpcAgent, visual: Node3D) -> void:
    var source := str(visual.get_meta("visual_source", "unknown"))
    _bindings[agent.get_instance_id()] = {
        "agent": agent,
        "visual": visual,
        "animation_player": _find_animation_player(visual),
        "source": source,
        "state": "",
    }


func _prune_bindings() -> void:
    var stale: Array = []
    for instance_id in _bindings.keys():
        var binding: Dictionary = _bindings.get(instance_id, {})
        var agent: Variant = binding.get("agent", null)
        var visual: Variant = binding.get("visual", null)
        if not is_instance_valid(agent) or not is_instance_valid(visual):
            stale.append(instance_id)
    for instance_id in stale:
        _bindings.erase(instance_id)


func _sync_all_bindings() -> void:
    _prune_bindings()
    for instance_id in _bindings.keys():
        _sync_binding(instance_id)


func _sync_binding(instance_id: int) -> void:
    if not _bindings.has(instance_id):
        return
    var binding: Dictionary = _bindings[instance_id]
    var agent := binding.get("agent", null) as NpcAgent
    var player := binding.get("animation_player", null) as AnimationPlayer
    if agent == null or player == null:
        return
    var desired := _desired_animation_state(agent)
    if str(binding.get("state", "")) == desired:
        return
    if _play_state_on(player, desired, 0.14):
        binding["state"] = desired
        _bindings[instance_id] = binding


func _desired_animation_state(agent: NpcAgent) -> String:
    var planar_speed := Vector2(agent.velocity.x, agent.velocity.z).length()
    if agent.police_response.phase == NpcPoliceResponse.Phase.PURSUIT and planar_speed > 0.10:
        return "chase"
    if planar_speed > 2.35:
        return "run"
    if planar_speed > 0.10:
        return "walk"
    return "idle"


func _hide_legacy_visuals(agent: NpcAgent, hidden: bool) -> void:
    for child: Node in agent.get_children():
        if child.name == VISUAL_NODE_NAME:
            continue
        if str(child.name) in LEGACY_VISUAL_NAMES and child is Node3D:
            (child as Node3D).visible = not hidden


func _load_local_authored_visual() -> Node3D:
    if not FileAccess.file_exists(LOCAL_MODEL_PATH):
        return null
    var file := FileAccess.open(LOCAL_MODEL_PATH, FileAccess.READ)
    if file == null or file.get_length() != EXPECTED_LOCAL_BYTES:
        return null
    file.close()
    if _sha256_file(LOCAL_MODEL_PATH) != EXPECTED_LOCAL_SHA256:
        return null

    var resource := load(LOCAL_MODEL_PATH)
    if not resource is PackedScene:
        return null
    var visual := (resource as PackedScene).instantiate() as Node3D
    if visual == null:
        return null

    visual.position.y = LOCAL_VISUAL_FOOT_OFFSET_Y
    visual.set_meta("visual_design", DESIGN_VERSION)
    visual.set_meta("visual_source", "local_gta_derived")
    _enable_shadows(visual)
    return visual


func _load_public_authored_visual() -> Node3D:
    if not ResourceLoader.exists(PUBLIC_BASE_MODEL_PATH):
        return null
    var resource := ResourceLoader.load(PUBLIC_BASE_MODEL_PATH)
    if not resource is PackedScene:
        return null
    var body := (resource as PackedScene).instantiate() as Node3D
    if body == null:
        return null

    var root := Node3D.new()
    root.set_meta("visual_design", DESIGN_VERSION)
    root.set_meta("visual_source", "public_cc0_authored")
    root.set_meta("body_source", PUBLIC_BASE_MODEL_PATH)
    root.set_meta("body_license", PUBLIC_BASE_LICENSE)

    body.name = "CC0PoliceBody"
    body.position = PUBLIC_BASE_POSITION
    body.rotation_degrees = PUBLIC_BASE_ROTATION_DEGREES
    root.add_child(body)

    _hide_adventurer_props(body)
    _apply_public_police_palette(body)
    _build_police_equipment(root)
    _enable_shadows(root)
    return root


func _apply_public_police_palette(node: Node) -> void:
    if node is MeshInstance3D:
        var mesh_instance := node as MeshInstance3D
        if mesh_instance.mesh != null:
            for surface_idx: int in range(mesh_instance.mesh.get_surface_count()):
                var source := mesh_instance.get_active_material(surface_idx)
                if source is StandardMaterial3D:
                    var base := source as StandardMaterial3D
                    if base.albedo_texture != null:
                        var shader_material := ShaderMaterial.new()
                        shader_material.shader = _get_police_recolor_shader()
                        shader_material.set_shader_parameter("source_tex", base.albedo_texture)
                        shader_material.set_shader_parameter("base_tint", base.albedo_color)
                        mesh_instance.set_surface_override_material(surface_idx, shader_material)
                    else:
                        var duplicate := base.duplicate() as StandardMaterial3D
                        duplicate.albedo_color = Color(0.035, 0.060, 0.105, base.albedo_color.a)
                        duplicate.roughness = 0.72
                        mesh_instance.set_surface_override_material(surface_idx, duplicate)
    for child: Node in node.get_children():
        _apply_public_police_palette(child)


func _get_police_recolor_shader() -> Shader:
    if _recolor_shader != null:
        return _recolor_shader
    _recolor_shader = Shader.new()
    _recolor_shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D source_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 base_tint : source_color = vec4(1.0);

void fragment() {
    vec4 texel = texture(source_tex, UV) * base_tint;
    float max_c = max(texel.r, max(texel.g, texel.b));
    float luminance = dot(texel.rgb, vec3(0.299, 0.587, 0.114));
    bool skin_or_hair = texel.r > 0.34 && texel.r > texel.g * 1.04 && texel.g > texel.b * 1.03 && (texel.r - texel.b) > 0.10;
    bool very_dark = max_c < 0.16;
    vec3 navy_dark = vec3(0.018, 0.036, 0.070);
    vec3 navy_light = vec3(0.060, 0.105, 0.165);
    vec3 uniform_colour = mix(navy_dark, navy_light, smoothstep(0.08, 0.72, luminance));
    vec3 colour = skin_or_hair ? texel.rgb : uniform_colour;
    if (very_dark) {
        colour = mix(texel.rgb, navy_dark, 0.55);
    }
    ALBEDO = colour;
    ROUGHNESS = skin_or_hair ? 0.68 : 0.76;
    METALLIC = 0.0;
    ALPHA = texel.a;
}
"""
    return _recolor_shader


func _hide_adventurer_props(node: Node) -> void:
    var lower := node.name.to_lower()
    var unwanted := [
        "dagger", "sword", "crossbow", "bow", "quiver", "arrow", "shield",
        "weapon", "knife", "throwable", "cape",
    ]
    for token: String in unwanted:
        if token in lower and node is VisualInstance3D:
            (node as VisualInstance3D).visible = false
            break
    for child: Node in node.get_children():
        _hide_adventurer_props(child)


func _build_police_equipment(root: Node3D) -> void:
    var navy_vest := _material(Color(0.025, 0.052, 0.095, 1.0), 0.68)
    var light_blue := _material(Color(0.25, 0.60, 0.86, 1.0), 0.58)
    var white := _material(Color(0.92, 0.95, 0.97, 1.0), 0.52)
    var black := _material(Color(0.010, 0.014, 0.020, 1.0), 0.82)
    var silver := _material(Color(0.54, 0.58, 0.63, 1.0), 0.40, 0.30)
    var lens := _material(Color(0.015, 0.035, 0.055, 1.0), 0.24, 0.12)

    _box(root, "PatrolVest", Vector3(0.52, 0.43, 0.31), Vector3(0.0, 1.23, 0.0), navy_vest)
    _box(root, "FrontIdentityBand", Vector3(0.38, 0.085, 0.014), Vector3(0.0, 1.36, -0.164), light_blue)
    _box(root, "FrontIdentityCore", Vector3(0.245, 0.034, 0.017), Vector3(0.0, 1.36, -0.173), white)
    _box(root, "RearIdentityBand", Vector3(0.39, 0.085, 0.014), Vector3(0.0, 1.36, 0.164), light_blue)

    _cylinder(root, "CapCrown", 0.205, 0.105, Vector3(0.0, 1.91, 0.0), navy_vest)
    _box(root, "CapVisor", Vector3(0.30, 0.035, 0.17), Vector3(0.0, 1.87, -0.155), navy_vest)
    _box(root, "CapBadge", Vector3(0.055, 0.060, 0.018), Vector3(0.0, 1.91, -0.198), silver)

    _box(root, "DutyBelt", Vector3(0.54, 0.095, 0.30), Vector3(0.0, 0.88, 0.0), black)
    _box(root, "BeltBuckle", Vector3(0.080, 0.070, 0.020), Vector3(0.0, 0.88, -0.162), silver)
    _box(root, "LeftPouch", Vector3(0.105, 0.16, 0.105), Vector3(-0.205, 0.83, -0.09), black)
    _box(root, "RightPouch", Vector3(0.105, 0.16, 0.105), Vector3(0.205, 0.83, -0.09), black)
    _box(root, "Holster", Vector3(0.115, 0.27, 0.12), Vector3(0.31, 0.76, 0.0), black)

    _box(root, "Radio", Vector3(0.105, 0.17, 0.070), Vector3(-0.175, 1.31, -0.190), black)
    _cylinder(root, "RadioAntenna", 0.012, 0.16, Vector3(-0.175, 1.46, -0.190), black)
    _box(root, "BodyCamera", Vector3(0.085, 0.115, 0.052), Vector3(0.075, 1.305, -0.195), black)
    _sphere(root, "BodyCameraLens", 0.018, Vector3(0.075, 1.325, -0.225), lens)

    var label := Label3D.new()
    label.name = "BilingualPoliceLabel"
    label.text = "POLICE / POLITIE"
    label.font_size = 28
    label.pixel_size = 0.0017
    label.outline_size = 4
    label.modulate = Color(0.96, 0.98, 1.0, 1.0)
    label.outline_modulate = Color(0.02, 0.04, 0.07, 1.0)
    label.position = Vector3(0.0, 1.36, -0.184)
    label.rotation_degrees.y = 180.0
    root.add_child(label)


func _play_state_on(player: AnimationPlayer, state: String, blend: float) -> bool:
    if player == null:
        return false
    var candidate := StringName(state)
    if not player.has_animation(candidate):
        candidate = _find_animation_candidate(player, state)
    if candidate == &"":
        return false
    if player.current_animation != candidate or not player.is_playing():
        player.play(candidate, blend)
    return true


func _find_animation_candidate(player: AnimationPlayer, state: String) -> StringName:
    if player == null:
        return &""
    var needles: Array[String] = []
    match state:
        "idle": needles = ["idle"]
        "walk": needles = ["walk", "walking"]
        "run": needles = ["run", "running", "jog"]
        "chase": needles = ["chase", "run", "running", "sprint"]
        "arrest": needles = ["arrest", "interact", "use", "grab", "punch", "attack"]
        _: return &""

    for animation_name in player.get_animation_list():
        var lower := str(animation_name).to_lower()
        for needle: String in needles:
            if needle in lower:
                return animation_name
    return &""


func _sha256_file(path: String) -> String:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return ""
    var context := HashingContext.new()
    if context.start(HashingContext.HASH_SHA256) != OK:
        file.close()
        return ""
    while file.get_position() < file.get_length():
        context.update(file.get_buffer(mini(1024 * 1024, file.get_length() - file.get_position())))
    file.close()
    return context.finish().hex_encode()


func _find_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node as AnimationPlayer
    for child: Node in node.get_children():
        var found := _find_animation_player(child)
        if found != null:
            return found
    return null


func _enable_shadows(node: Node) -> void:
    if node is GeometryInstance3D:
        (node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    for child: Node in node.get_children():
        _enable_shadows(child)


func _build_emergency_visual() -> Node3D:
    var root := Node3D.new()
    root.set_meta("visual_design", DESIGN_VERSION)
    root.set_meta("visual_source", "emergency_procedural")
    var navy := _material(Color(0.025, 0.052, 0.095, 1.0), 0.72)
    var black := _material(Color(0.010, 0.014, 0.020, 1.0), 0.82)
    var skin := _material(Color(0.64, 0.46, 0.34, 1.0), 0.78)
    _capsule(root, "Body", 0.24, 1.05, Vector3(0.0, 0.98, 0.0), navy)
    _sphere(root, "Head", 0.205, Vector3(0.0, 1.68, 0.0), skin)
    _box(root, "DutyBelt", Vector3(0.52, 0.10, 0.30), Vector3(0.0, 0.86, 0.0), black)
    return root


func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = metallic
    return material


func _box(parent: Node3D, name_value: String, size: Vector3, position_value: Vector3, material: Material) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    node.name = name_value
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh.material = material
    node.mesh = mesh
    node.position = position_value
    node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    parent.add_child(node)
    return node


func _sphere(parent: Node3D, name_value: String, radius: float, position_value: Vector3, material: Material) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    node.name = name_value
    var mesh := SphereMesh.new()
    mesh.radius = radius
    mesh.height = radius * 2.0
    mesh.material = material
    node.mesh = mesh
    node.position = position_value
    node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    parent.add_child(node)
    return node


func _capsule(parent: Node3D, name_value: String, radius: float, height: float, position_value: Vector3, material: Material) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    node.name = name_value
    var mesh := CapsuleMesh.new()
    mesh.radius = radius
    mesh.height = height
    mesh.material = material
    node.mesh = mesh
    node.position = position_value
    node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    parent.add_child(node)
    return node


func _cylinder(parent: Node3D, name_value: String, radius: float, height: float, position_value: Vector3, material: Material) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    node.name = name_value
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = height
    mesh.material = material
    node.mesh = mesh
    node.position = position_value
    node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    parent.add_child(node)
    return node

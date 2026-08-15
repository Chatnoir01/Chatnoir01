extends Node3D

const DEFAULT_AUTHORED_CHARACTER_PATH := "res://assets/characters/player/thandi/Thandi.glb"
const FALLBACK_AUTHORED_CHARACTER_PATHS := [
    "res://assets/characters/player/thandi/Thandi.fbx",
    "res://assets/characters/player/kaykit_rogue/Rogue.glb",
    "res://assets/characters/player_character.glb",
]

const SKIN_TONES: Array[Color] = [
    Color(0.28, 0.16, 0.11, 1.0),
    Color(0.40, 0.24, 0.16, 1.0),
    Color(0.55, 0.34, 0.23, 1.0),
    Color(0.68, 0.46, 0.33, 1.0),
    Color(0.78, 0.60, 0.47, 1.0),
    Color(0.88, 0.73, 0.61, 1.0),
]

@export var force_police_uniform: bool = false
@export_file("*.glb", "*.gltf", "*.fbx", "*.tscn") var authored_scene_path: String = DEFAULT_AUTHORED_CHARACTER_PATH
@export var allow_authored_fallback_paths: bool = true
@export var authored_position: Vector3 = Vector3(0.0, -0.90, 0.0)
@export var authored_rotation_degrees: Vector3 = Vector3(0.0, 180.0, 0.0)
@export var authored_scale: Vector3 = Vector3.ONE

var _left_arm: MeshInstance3D
var _right_arm: MeshInstance3D
var _left_leg: MeshInstance3D
var _right_leg: MeshInstance3D
var _phase: float = 0.0
var _police: bool = false
var _authored_character: Node3D
var _resolved_authored_scene_path: String = ""
var _visual_signature: String = ""
var _authored_animation_player: AnimationPlayer
var _authored_idle_animation: StringName = &""
var _authored_walk_animation: StringName = &""
var _authored_run_animation: StringName = &""


func _ready() -> void:
    var actor: Node3D = get_parent() as Node3D
    if actor == null:
        return
    _police = force_police_uniform or actor.is_in_group("police_officer")
    _hide_legacy_visuals(actor)
    if not _police and actor.name == "Player" and _try_build_authored_character():
        return
    if actor is NpcAgent:
        _build_profiled_npc(actor as NpcAgent)
        return
    _build_humanoid()


func _process(delta: float) -> void:
    if is_instance_valid(_authored_character):
        _update_authored_locomotion()
        return
    var actor: CharacterBody3D = get_parent() as CharacterBody3D
    if actor == null:
        return
    var horizontal_speed: float = Vector2(actor.velocity.x, actor.velocity.z).length()
    var activity: float = clampf(horizontal_speed / 7.0, 0.0, 1.0)
    _phase += delta * lerpf(3.0, 10.0, activity)
    var swing: float = sin(_phase) * 0.55 * activity
    if is_instance_valid(_left_arm):
        _left_arm.rotation.x = swing
    if is_instance_valid(_right_arm):
        _right_arm.rotation.x = -swing
    if is_instance_valid(_left_leg):
        _left_leg.rotation.x = -swing * 0.72
    if is_instance_valid(_right_leg):
        _right_leg.rotation.x = swing * 0.72


func _hide_legacy_visuals(actor: Node3D) -> void:
    for path: String in ["MeshInstance3D", "Body", "Vest", "PoliceLabel"]:
        var legacy: Node = actor.get_node_or_null(path)
        if legacy is VisualInstance3D:
            (legacy as VisualInstance3D).visible = false


func _try_build_authored_character() -> bool:
    for candidate: String in _authored_candidates():
        var resource: Resource = load(candidate)
        if resource == null:
            continue
        if resource is PackedScene:
            var instance: Node = (resource as PackedScene).instantiate()
            if instance is Node3D:
                _authored_character = instance as Node3D
                _authored_character.name = "AuthoredCharacter"
                _authored_character.position = authored_position
                _authored_character.rotation_degrees = authored_rotation_degrees
                _authored_character.scale = authored_scale
                add_child(_authored_character)
                _resolved_authored_scene_path = candidate
                _visual_signature = "authored:%s" % candidate
                _configure_authored_animation_player()
                print("Grand Bruxelles authored player loaded: %s" % candidate)
                return true
    return false


func _authored_candidates() -> Array[String]:
    var candidates: Array[String] = []
    if not authored_scene_path.is_empty():
        candidates.append(authored_scene_path)
    if allow_authored_fallback_paths:
        for fallback: String in FALLBACK_AUTHORED_CHARACTER_PATHS:
            if fallback not in candidates:
                candidates.append(fallback)
    return candidates



func _configure_authored_animation_player() -> void:
    _authored_animation_player = _find_animation_player(_authored_character)
    if _authored_animation_player == null:
        return
    var names: PackedStringArray = _authored_animation_player.get_animation_list()
    _authored_idle_animation = _find_animation_name(names, ["idle"])
    _authored_walk_animation = _find_animation_name(names, ["walk"])
    _authored_run_animation = _find_animation_name(names, ["run", "sprint"])
    if _authored_idle_animation == &"":
        _authored_idle_animation = _first_non_reset_animation(names)
    if _authored_idle_animation != &"":
        _authored_animation_player.play(_authored_idle_animation)


func _find_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node as AnimationPlayer
    for child: Node in node.get_children():
        var found: AnimationPlayer = _find_animation_player(child)
        if found != null:
            return found
    return null


func _find_animation_name(names: PackedStringArray, needles: Array[String]) -> StringName:
    for animation_name: String in names:
        var lower: String = animation_name.to_lower()
        for needle: String in needles:
            if needle in lower:
                return StringName(animation_name)
    return &""


func _first_non_reset_animation(names: PackedStringArray) -> StringName:
    for animation_name: String in names:
        if animation_name != "RESET":
            return StringName(animation_name)
    return &""


func _update_authored_locomotion() -> void:
    if _authored_animation_player == null:
        return
    var actor: CharacterBody3D = get_parent() as CharacterBody3D
    if actor == null:
        return
    var speed: float = Vector2(actor.velocity.x, actor.velocity.z).length()
    var target: StringName = _authored_idle_animation
    if speed > 5.2 and _authored_run_animation != &"":
        target = _authored_run_animation
    elif speed > 0.25 and _authored_walk_animation != &"":
        target = _authored_walk_animation
    if target != &"" and _authored_animation_player.current_animation != String(target):
        _authored_animation_player.play(target)


func authored_animation_player() -> AnimationPlayer:
    return _authored_animation_player


func authored_locomotion_animations() -> Dictionary:
    return {
        "idle": String(_authored_idle_animation),
        "walk": String(_authored_walk_animation),
        "run": String(_authored_run_animation),
    }

func is_using_authored_character() -> bool:
    return is_instance_valid(_authored_character)


func resolved_authored_scene_path() -> String:
    return _resolved_authored_scene_path


func visual_signature() -> String:
    return _visual_signature


func _build_profiled_npc(agent: NpcAgent) -> void:
    var profile := NpcAppearanceProfile.new()
    profile.configure(agent.variation_seed, agent.role, agent.weather_context)

    var stature: float = profile.stature_scale
    var shoulder: float = profile.shoulder_scale
    var base_y: float = -0.90
    var seed_value: int = agent.variation_seed
    var skin_index: int = posmod(seed_value * 17 + 5, SKIN_TONES.size())
    var skin := _material(SKIN_TONES[skin_index], 0.82)
    var hair := _material(_hair_color(seed_value), 0.92)
    var palette := _clothing_palette(profile.palette_family, seed_value)
    var upper_color: Color = palette[0]
    var lower_color: Color = palette[1]
    var accent_color: Color = palette[2]

    if agent.role == NpcBehaviorModel.Role.POLICE:
        upper_color = Color(0.025, 0.065, 0.14, 1.0)
        lower_color = Color(0.018, 0.04, 0.095, 1.0)
        accent_color = Color(0.76, 0.82, 0.075, 1.0)

    var upper := _material(upper_color, 0.86)
    var lower := _material(lower_color, 0.90)
    var accent := _material(accent_color, 0.74)
    var shoes := _material(_shoe_color(profile.footwear, seed_value), 0.78)

    var leg_h := 0.72 * stature
    var torso_h := 0.61 * stature
    var torso_y := base_y + 1.18 * stature
    var hip_y := base_y + 0.82 * stature
    var head_y := base_y + 1.77 * stature
    var shoulder_width := 0.65 * shoulder
    var hip_width := lerpf(0.42, 0.53, _unit(seed_value, 71))
    var build_factor := lerpf(0.90, 1.08, _unit(seed_value, 73))

    _elliptic_frustum_part(
        "Torso",
        Vector2(shoulder_width * 0.52, 0.17 * build_factor),
        Vector2(hip_width * 0.50, 0.155 * build_factor),
        torso_h,
        Vector3(0.0, torso_y, 0.0),
        upper,
        10
    )
    _elliptic_frustum_part(
        "Hips",
        Vector2(hip_width * 0.52, 0.16 * build_factor),
        Vector2(hip_width * 0.47, 0.15 * build_factor),
        0.25 * stature,
        Vector3(0.0, hip_y, 0.0),
        lower,
        9
    )

    var arm_x := shoulder_width * 0.61
    var arm_h := 0.57 * stature
    _left_arm = _elliptic_frustum_part("LeftArm", Vector2(0.105, 0.105), Vector2(0.075, 0.080), arm_h, Vector3(-arm_x, base_y + 1.17 * stature, 0.0), upper, 8)
    _right_arm = _elliptic_frustum_part("RightArm", Vector2(0.105, 0.105), Vector2(0.075, 0.080), arm_h, Vector3(arm_x, base_y + 1.17 * stature, 0.0), upper, 8)
    _custom_ellipsoid_part("LeftHand", Vector3(0.085, 0.115, 0.075), Vector3(-arm_x, base_y + 0.84 * stature, 0.0), skin, 7, 4)
    _custom_ellipsoid_part("RightHand", Vector3(0.085, 0.115, 0.075), Vector3(arm_x, base_y + 0.84 * stature, 0.0), skin, 7, 4)

    var leg_x := hip_width * 0.25
    _left_leg = _elliptic_frustum_part("LeftLeg", Vector2(0.13, 0.14), Vector2(0.095, 0.105), leg_h, Vector3(-leg_x, base_y + 0.46 * stature, 0.0), lower, 9)
    _right_leg = _elliptic_frustum_part("RightLeg", Vector2(0.13, 0.14), Vector2(0.095, 0.105), leg_h, Vector3(leg_x, base_y + 0.46 * stature, 0.0), lower, 9)
    _custom_prism_part("LeftShoe", Vector3(0.20, 0.12, 0.34), Vector3(0.23, 0.13, 0.39), Vector3(-leg_x, base_y + 0.07, -0.07), shoes)
    _custom_prism_part("RightShoe", Vector3(0.20, 0.12, 0.34), Vector3(0.23, 0.13, 0.39), Vector3(leg_x, base_y + 0.07, -0.07), shoes)

    _elliptic_frustum_part("Neck", Vector2(0.105, 0.095), Vector2(0.11, 0.10), 0.16 * stature, Vector3(0.0, base_y + 1.55 * stature, 0.0), skin, 8)
    var head_scale := Vector3(0.255 * build_factor, 0.31 * stature, 0.245 * build_factor)
    _custom_ellipsoid_part("Head", head_scale, Vector3(0.0, head_y, 0.0), skin, 10, 6)
    _custom_prism_part("Nose", Vector3(0.065, 0.10, 0.085), Vector3(0.075, 0.11, 0.10), Vector3(0.0, head_y - 0.01, -head_scale.z * 0.92), skin)
    _build_profiled_hair(profile, seed_value, head_y, head_scale, hair, accent)
    _build_outer_layer(profile, stature, shoulder_width, torso_y, build_factor, accent)

    if agent.role == NpcBehaviorModel.Role.POLICE:
        _build_police_details(base_y, stature, shoulder_width, accent, upper)

    _visual_signature = "%d|%s|%s|%s|%s|%s|skin%d|%.3f|%.3f" % [
        seed_value,
        str(profile.clothing_base),
        str(profile.outer_layer),
        str(profile.headwear),
        str(profile.footwear),
        str(profile.palette_family),
        skin_index,
        profile.stature_scale,
        profile.shoulder_scale,
    ]
    set_meta("appearance_signature", _visual_signature)
    set_meta("custom_mesh_pipeline", "array_mesh_profiled_v2")


func _build_profiled_hair(profile: NpcAppearanceProfile, seed_value: int, head_y: float, head_scale: Vector3, hair: Material, accent: Material) -> void:
    var style: int = posmod(seed_value * 13 + 3, 4)
    match style:
        0:
            _custom_ellipsoid_part("HairCrown", Vector3(head_scale.x * 1.07, head_scale.y * 0.46, head_scale.z * 1.08), Vector3(0.0, head_y + head_scale.y * 0.62, 0.01), hair, 8, 4)
        1:
            _custom_ellipsoid_part("HairCrown", Vector3(head_scale.x * 1.08, head_scale.y * 0.40, head_scale.z * 1.08), Vector3(0.0, head_y + head_scale.y * 0.67, 0.01), hair, 8, 4)
            _custom_ellipsoid_part("HairBun", Vector3(0.13, 0.14, 0.13), Vector3(0.0, head_y + head_scale.y * 1.15, 0.03), hair, 8, 4)
        2:
            _custom_ellipsoid_part("HairVolume", Vector3(head_scale.x * 1.17, head_scale.y * 0.76, head_scale.z * 1.14), Vector3(0.0, head_y + head_scale.y * 0.25, 0.04), hair, 9, 5)
        _:
            _custom_ellipsoid_part("HairCrown", Vector3(head_scale.x * 1.04, head_scale.y * 0.35, head_scale.z * 1.05), Vector3(0.0, head_y + head_scale.y * 0.72, 0.01), hair, 8, 4)

    match profile.headwear:
        &"beanie":
            _elliptic_frustum_part("Beanie", Vector2(head_scale.x * 0.98, head_scale.z * 0.98), Vector2(head_scale.x * 1.10, head_scale.z * 1.10), 0.19, Vector3(0.0, head_y + head_scale.y * 0.92, 0.0), accent, 9)
        &"cap":
            _elliptic_frustum_part("CapCrown", Vector2(head_scale.x * 0.95, head_scale.z * 0.95), Vector2(head_scale.x * 1.08, head_scale.z * 1.08), 0.16, Vector3(0.0, head_y + head_scale.y * 0.88, 0.0), accent, 9)
            _custom_prism_part("CapPeak", Vector3(0.26, 0.04, 0.22), Vector3(0.31, 0.04, 0.28), Vector3(0.0, head_y + head_scale.y * 0.72, -head_scale.z * 1.20), accent)
        &"hood_up":
            _custom_ellipsoid_part("RaisedHood", Vector3(head_scale.x * 1.35, head_scale.y * 1.18, head_scale.z * 1.28), Vector3(0.0, head_y + 0.02, 0.06), accent, 9, 5)


func _build_outer_layer(profile: NpcAppearanceProfile, stature: float, shoulder_width: float, torso_y: float, build_factor: float, accent: Material) -> void:
    if profile.outer_layer == &"none" or profile.outer_layer == &"police_standard":
        return
    var long_layer := profile.outer_layer in [&"winter_coat", &"wool_coat", &"parka", &"hooded_coat", &"coat", &"police_cold_layer", &"police_rain_layer"]
    var layer_h := (0.69 if long_layer else 0.48) * stature
    var layer_y := torso_y - (0.08 * stature if long_layer else 0.0)
    _elliptic_frustum_part(
        "OuterLayer",
        Vector2(shoulder_width * 0.56, 0.19 * build_factor),
        Vector2(shoulder_width * 0.48, 0.18 * build_factor),
        layer_h,
        Vector3(0.0, layer_y, 0.02),
        accent,
        10
    )


func _build_police_details(base_y: float, stature: float, shoulder_width: float, hivis: Material, uniform: Material) -> void:
    _elliptic_frustum_part("HiVisVest", Vector2(shoulder_width * 0.49, 0.19), Vector2(shoulder_width * 0.44, 0.18), 0.39 * stature, Vector3(0.0, base_y + 1.22 * stature, -0.005), hivis, 10)
    _elliptic_frustum_part("PoliceCap", Vector2(0.22, 0.20), Vector2(0.245, 0.22), 0.12, Vector3(0.0, base_y + 2.03 * stature, 0.0), uniform, 9)
    _custom_prism_part("PoliceCapPeak", Vector3(0.31, 0.04, 0.17), Vector3(0.36, 0.04, 0.22), Vector3(0.0, base_y + 2.025 * stature, -0.30), uniform)
    var label := Label3D.new()
    label.name = "UniformPoliceLabel"
    label.text = "POLICE · POLITIE"
    label.font_size = 22
    label.outline_size = 3
    label.position = Vector3(0.0, base_y + 1.25 * stature, -0.255)
    label.rotation_degrees = Vector3(0.0, 180.0, 0.0)
    label.modulate = Color(0.04, 0.08, 0.18, 1.0)
    add_child(label)


func _clothing_palette(palette_family: StringName, seed_value: int) -> Array[Color]:
    var variant := posmod(seed_value * 19 + 7, 3)
    match palette_family:
        &"earth":
            return [Color(0.31 + 0.035 * variant, 0.25, 0.18, 1.0), Color(0.18, 0.16 + 0.025 * variant, 0.13, 1.0), Color(0.47, 0.36, 0.24 + 0.025 * variant, 1.0)]
        &"muted_cool":
            return [Color(0.20, 0.29 + 0.025 * variant, 0.36, 1.0), Color(0.12, 0.17, 0.24 + 0.025 * variant, 1.0), Color(0.36, 0.46, 0.52 + 0.025 * variant, 1.0)]
        &"muted_warm":
            return [Color(0.42 + 0.025 * variant, 0.25, 0.23, 1.0), Color(0.25, 0.16, 0.17 + 0.02 * variant, 1.0), Color(0.58, 0.39 + 0.025 * variant, 0.31, 1.0)]
        &"dark":
            return [Color(0.10 + 0.02 * variant, 0.12, 0.15, 1.0), Color(0.055, 0.065 + 0.015 * variant, 0.08, 1.0), Color(0.25, 0.28, 0.31 + 0.02 * variant, 1.0)]
        _:
            return [Color(0.26 + 0.025 * variant, 0.28, 0.30, 1.0), Color(0.12, 0.14 + 0.02 * variant, 0.17, 1.0), Color(0.48, 0.49, 0.50 + 0.02 * variant, 1.0)]


func _shoe_color(footwear: StringName, seed_value: int) -> Color:
    if footwear == &"trainer" and posmod(seed_value, 2) == 0:
        return Color(0.73, 0.73, 0.71, 1.0)
    if footwear == &"smart":
        return Color(0.10, 0.075, 0.06, 1.0)
    if footwear == &"boot":
        return Color(0.12, 0.10, 0.085, 1.0)
    return Color(0.075, 0.08, 0.09, 1.0)


func _hair_color(seed_value: int) -> Color:
    var options: Array[Color] = [
        Color(0.035, 0.027, 0.023, 1.0),
        Color(0.09, 0.055, 0.035, 1.0),
        Color(0.18, 0.11, 0.07, 1.0),
        Color(0.30, 0.22, 0.15, 1.0),
    ]
    return options[posmod(seed_value * 11 + 1, options.size())]


func _unit(seed_value: int, salt: int) -> float:
    return float(posmod(seed_value * 1103515245 + salt * 12345, 10000)) / 9999.0


func _build_humanoid() -> void:
    var base_y: float = 0.0 if _police else -0.90
    var skin: StandardMaterial3D = _material(Color(0.63, 0.43, 0.32, 1.0), 0.78)
    var hair: StandardMaterial3D = _material(Color(0.055, 0.045, 0.04, 1.0), 0.90)
    var jacket_color: Color = Color(0.018, 0.04, 0.095, 1.0) if _police else Color(0.075, 0.095, 0.115, 1.0)
    var trousers_color: Color = Color(0.02, 0.035, 0.075, 1.0) if _police else Color(0.075, 0.105, 0.15, 1.0)
    var jacket: StandardMaterial3D = _material(jacket_color, 0.82)
    var trousers: StandardMaterial3D = _material(trousers_color, 0.88)
    var shoes: StandardMaterial3D = _material(Color(0.025, 0.027, 0.03, 1.0), 0.76)
    _box_part("Torso", Vector3(0.62, 0.72, 0.34), Vector3(0.0, base_y + 1.18, 0.0), jacket)
    _box_part("Shoulders", Vector3(0.76, 0.18, 0.36), Vector3(0.0, base_y + 1.48, 0.0), jacket)
    _left_arm = _box_part("LeftArm", Vector3(0.18, 0.70, 0.20), Vector3(-0.43, base_y + 1.17, 0.0), jacket)
    _right_arm = _box_part("RightArm", Vector3(0.18, 0.70, 0.20), Vector3(0.43, base_y + 1.17, 0.0), jacket)
    _left_leg = _box_part("LeftLeg", Vector3(0.22, 0.78, 0.25), Vector3(-0.17, base_y + 0.52, 0.0), trousers)
    _right_leg = _box_part("RightLeg", Vector3(0.22, 0.78, 0.25), Vector3(0.17, base_y + 0.52, 0.0), trousers)
    _box_part("LeftShoe", Vector3(0.24, 0.14, 0.38), Vector3(-0.17, base_y + 0.09, -0.06), shoes)
    _box_part("RightShoe", Vector3(0.24, 0.14, 0.38), Vector3(0.17, base_y + 0.09, -0.06), shoes)
    var head: MeshInstance3D = _sphere_part("Head", Vector3(0.29, 0.34, 0.29), Vector3(0.0, base_y + 1.78, 0.0), skin)
    head.scale = Vector3(1.0, 1.08, 0.94)
    _box_part("Hair", Vector3(0.48, 0.13, 0.48), Vector3(0.0, base_y + 2.04, 0.0), hair)
    if _police:
        var hivis: StandardMaterial3D = _material(Color(0.76, 0.82, 0.075, 1.0), 0.64)
        hivis.emission_enabled = true
        hivis.emission = Color(0.09, 0.10, 0.005, 1.0)
        hivis.emission_energy_multiplier = 0.18
        _box_part("HiVisVest", Vector3(0.65, 0.52, 0.08), Vector3(0.0, base_y + 1.20, -0.205), hivis)
        _box_part("PoliceCap", Vector3(0.52, 0.12, 0.48), Vector3(0.0, base_y + 2.07, 0.0), jacket)
        _box_part("PoliceCapPeak", Vector3(0.42, 0.055, 0.22), Vector3(0.0, base_y + 2.075, -0.30), jacket)
        var label: Label3D = Label3D.new()
        label.name = "UniformPoliceLabel"
        label.text = "POLICE · POLITIE"
        label.font_size = 24
        label.outline_size = 3
        label.position = Vector3(0.0, base_y + 1.25, -0.255)
        label.rotation_degrees = Vector3(0.0, 180.0, 0.0)
        label.modulate = Color(0.04, 0.08, 0.18, 1.0)
        add_child(label)
    _visual_signature = "legacy_fallback"


func _material(color: Color, roughness: float) -> StandardMaterial3D:
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    return material


func _elliptic_frustum_part(name_value: String, top_radii: Vector2, bottom_radii: Vector2, height: float, pos: Vector3, material: Material, segments: int = 8) -> MeshInstance3D:
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    var safe_segments := maxi(segments, 6)
    var half_h := height * 0.5
    var top_center := Vector3(0.0, half_h, 0.0)
    var bottom_center := Vector3(0.0, -half_h, 0.0)
    for segment: int in range(safe_segments):
        var next_segment := (segment + 1) % safe_segments
        var angle_a := TAU * float(segment) / float(safe_segments)
        var angle_b := TAU * float(next_segment) / float(safe_segments)
        var top_a := Vector3(sin(angle_a) * top_radii.x, half_h, cos(angle_a) * top_radii.y)
        var top_b := Vector3(sin(angle_b) * top_radii.x, half_h, cos(angle_b) * top_radii.y)
        var bottom_a := Vector3(sin(angle_a) * bottom_radii.x, -half_h, cos(angle_a) * bottom_radii.y)
        var bottom_b := Vector3(sin(angle_b) * bottom_radii.x, -half_h, cos(angle_b) * bottom_radii.y)
        _add_triangle(surface, bottom_a, top_b, top_a)
        _add_triangle(surface, bottom_a, bottom_b, top_b)
        _add_triangle(surface, top_center, top_a, top_b)
        _add_triangle(surface, bottom_center, bottom_b, bottom_a)
    return _commit_custom_part(name_value, surface, pos, material)


func _custom_prism_part(name_value: String, top_size: Vector3, bottom_size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
    var half_top := Vector3(top_size.x * 0.5, top_size.y * 0.5, top_size.z * 0.5)
    var half_bottom := Vector3(bottom_size.x * 0.5, bottom_size.y * 0.5, bottom_size.z * 0.5)
    var top := [Vector3(-half_top.x, half_top.y, -half_top.z), Vector3(half_top.x, half_top.y, -half_top.z), Vector3(half_top.x, half_top.y, half_top.z), Vector3(-half_top.x, half_top.y, half_top.z)]
    var bottom := [Vector3(-half_bottom.x, -half_bottom.y, -half_bottom.z), Vector3(half_bottom.x, -half_bottom.y, -half_bottom.z), Vector3(half_bottom.x, -half_bottom.y, half_bottom.z), Vector3(-half_bottom.x, -half_bottom.y, half_bottom.z)]
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    _add_triangle(surface, top[0], top[2], top[1])
    _add_triangle(surface, top[0], top[3], top[2])
    _add_triangle(surface, bottom[0], bottom[1], bottom[2])
    _add_triangle(surface, bottom[0], bottom[2], bottom[3])
    for side: int in range(4):
        var next_side := (side + 1) % 4
        _add_triangle(surface, bottom[side], top[next_side], top[side])
        _add_triangle(surface, bottom[side], bottom[next_side], top[next_side])
    return _commit_custom_part(name_value, surface, pos, material)


func _custom_ellipsoid_part(name_value: String, radii: Vector3, pos: Vector3, material: Material, segments: int = 8, rings: int = 5) -> MeshInstance3D:
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    var safe_segments := maxi(segments, 5)
    var safe_rings := maxi(rings, 3)
    for ring: int in range(safe_rings):
        var v0 := float(ring) / float(safe_rings)
        var v1 := float(ring + 1) / float(safe_rings)
        var phi0 := -PI * 0.5 + PI * v0
        var phi1 := -PI * 0.5 + PI * v1
        for segment: int in range(safe_segments):
            var u0 := float(segment) / float(safe_segments)
            var u1 := float(segment + 1) / float(safe_segments)
            var theta0 := TAU * u0
            var theta1 := TAU * u1
            var a := _ellipsoid_point(radii, phi0, theta0)
            var b := _ellipsoid_point(radii, phi0, theta1)
            var c := _ellipsoid_point(radii, phi1, theta1)
            var d := _ellipsoid_point(radii, phi1, theta0)
            if ring > 0:
                _add_triangle(surface, a, c, b)
            if ring < safe_rings - 1:
                _add_triangle(surface, a, d, c)
    return _commit_custom_part(name_value, surface, pos, material)


func _commit_custom_part(name_value: String, surface: SurfaceTool, pos: Vector3, material: Material) -> MeshInstance3D:
    var mesh := surface.commit() as ArrayMesh
    mesh.surface_set_material(0, material)
    var instance := MeshInstance3D.new()
    instance.name = name_value
    instance.mesh = mesh
    instance.position = pos
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    add_child(instance)
    return instance


func _ellipsoid_point(radii: Vector3, phi: float, theta: float) -> Vector3:
    var cos_phi := cos(phi)
    return Vector3(radii.x * cos_phi * sin(theta), radii.y * sin(phi), radii.z * cos_phi * cos(theta))


func _add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
    var normal := (b - a).cross(c - a).normalized()
    surface.set_normal(normal)
    surface.add_vertex(a)
    surface.set_normal(normal)
    surface.add_vertex(b)
    surface.set_normal(normal)
    surface.add_vertex(c)


func _box_part(name_value: String, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
    var mesh: BoxMesh = BoxMesh.new()
    mesh.size = size
    mesh.material = material
    var instance: MeshInstance3D = MeshInstance3D.new()
    instance.name = name_value
    instance.mesh = mesh
    instance.position = pos
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    add_child(instance)
    return instance


func _sphere_part(name_value: String, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
    var mesh: SphereMesh = SphereMesh.new()
    mesh.radius = 0.5
    mesh.height = 1.0
    mesh.radial_segments = 16
    mesh.rings = 8
    mesh.material = material
    var instance: MeshInstance3D = MeshInstance3D.new()
    instance.name = name_value
    instance.mesh = mesh
    instance.position = pos
    instance.scale = size * 2.0
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    add_child(instance)
    return instance

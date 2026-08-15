extends Node3D

const DEFAULT_AUTHORED_PLAYER_PATH := "res://assets/characters/player/thandi/Thandi.glb"
const FALLBACK_AUTHORED_PLAYER_PATHS: Array[String] = [
    "res://assets/characters/player/thandi/Thandi.fbx",
    "res://assets/characters/player_character.glb",
]

@export var force_police_uniform: bool = false
@export var allow_authored_player: bool = true
@export var allow_authored_fallback_paths: bool = true
@export_file("*.glb", "*.gltf", "*.fbx", "*.tscn") var authored_player_scene_path: String = DEFAULT_AUTHORED_PLAYER_PATH
@export var authored_player_position: Vector3 = Vector3(0.0, -0.90, 0.0)
@export var authored_player_rotation_degrees: Vector3 = Vector3(0.0, 180.0, 0.0)
@export var authored_player_scale: Vector3 = Vector3.ONE

var _left_arm: MeshInstance3D
var _right_arm: MeshInstance3D
var _left_leg: MeshInstance3D
var _right_leg: MeshInstance3D
var _phase: float = 0.0
var _police: bool = false
var _authored_character: Node3D
var _using_authored_character: bool = false
var _resolved_authored_scene_path: String = ""


func _ready() -> void:
    var actor: Node3D = get_parent() as Node3D
    if actor == null:
        return
    _police = force_police_uniform or actor.is_in_group("police_officer")
    _hide_legacy_visuals(actor)

    if allow_authored_player and not _police and _is_player_actor(actor):
        if _try_load_authored_player():
            return

    _build_humanoid()


func _process(delta: float) -> void:
    if _using_authored_character:
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


func is_using_authored_character() -> bool:
    return _using_authored_character


func authored_character() -> Node3D:
    return _authored_character


func resolved_authored_scene_path() -> String:
    return _resolved_authored_scene_path


func _is_player_actor(actor: Node3D) -> bool:
    return actor.name == &"Player" or actor.is_in_group("player")


func _authored_candidates() -> Array[String]:
    var candidates: Array[String] = []
    if not authored_player_scene_path.is_empty():
        candidates.append(authored_player_scene_path)
    if allow_authored_fallback_paths:
        for fallback_path: String in FALLBACK_AUTHORED_PLAYER_PATHS:
            if not candidates.has(fallback_path):
                candidates.append(fallback_path)
    return candidates


func _try_load_authored_player() -> bool:
    for candidate_path: String in _authored_candidates():
        if _try_load_authored_player_path(candidate_path):
            return true
    return false


func _try_load_authored_player_path(candidate_path: String) -> bool:
    if candidate_path.is_empty() or not ResourceLoader.exists(candidate_path):
        return false

    var resource: Resource = ResourceLoader.load(candidate_path)
    if not resource is PackedScene:
        push_warning("Authored player asset is not a PackedScene: %s" % candidate_path)
        return false

    var instance: Node = (resource as PackedScene).instantiate()
    if not instance is Node3D:
        instance.queue_free()
        push_warning("Authored player root must be Node3D: %s" % candidate_path)
        return false

    _authored_character = instance as Node3D
    _authored_character.name = "AuthoredCharacter"
    _authored_character.position = authored_player_position
    _authored_character.rotation_degrees = authored_player_rotation_degrees
    _authored_character.scale = authored_player_scale
    add_child(_authored_character)

    _resolved_authored_scene_path = candidate_path
    _using_authored_character = true
    return true


func _hide_legacy_visuals(actor: Node3D) -> void:
    for path: String in ["MeshInstance3D", "Body", "Vest", "PoliceLabel"]:
        var legacy: Node = actor.get_node_or_null(path)
        if legacy is VisualInstance3D:
            (legacy as VisualInstance3D).visible = false


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


func _material(color: Color, roughness: float) -> StandardMaterial3D:
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    return material


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

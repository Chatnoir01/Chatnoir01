extends Node3D
class_name PinkTracksuitPlayerVisual

const CHARACTER_SIGNATURE := "pink_tracksuit_v1"
const PIPELINE_SIGNATURE := "authored_character_or_procedural_v3"
const DEFAULT_AUTHORED_CHARACTER_PATH := "res://assets/characters/player/thandi/Thandi.glb"
const FALLBACK_AUTHORED_CHARACTER_PATHS := [
    "res://assets/characters/player/thandi/Thandi.fbx",
    "res://assets/characters/player_character.glb",
]

@export_file("*.glb", "*.gltf", "*.fbx", "*.tscn") var authored_scene_path: String = DEFAULT_AUTHORED_CHARACTER_PATH
@export var allow_authored_fallback_paths := true
@export var authored_position: Vector3 = Vector3(0.0, -0.90, 0.0)
@export var authored_rotation_degrees: Vector3 = Vector3(0.0, 180.0, 0.0)
@export var authored_scale: Vector3 = Vector3.ONE
@export var accent_color: Color = Color(0.93, 0.12, 0.58, 1.0)
@export var skin_color: Color = Color(0.43, 0.25, 0.17, 1.0)

var _left_arm: MeshInstance3D
var _right_arm: MeshInstance3D
var _left_leg: MeshInstance3D
var _right_leg: MeshInstance3D
var _phase := 0.0
var _authored_character: Node3D
var _using_authored_character := false
var _resolved_authored_scene_path := ""

func _ready() -> void:
    var actor := get_parent() as Node3D
    if actor == null:
        return
    _hide_legacy_visuals(actor)
    if _try_load_authored_character():
        return
    _build_character()

func _process(delta: float) -> void:
    if _using_authored_character:
        return
    var actor := get_parent() as CharacterBody3D
    if actor == null:
        return
    var horizontal_speed := Vector2(actor.velocity.x, actor.velocity.z).length()
    var activity := clampf(horizontal_speed / 7.0, 0.0, 1.0)
    _phase += delta * lerpf(3.2, 9.5, activity)
    var swing := sin(_phase) * 0.48 * activity
    if is_instance_valid(_left_arm): _left_arm.rotation.x = swing
    if is_instance_valid(_right_arm): _right_arm.rotation.x = -swing
    if is_instance_valid(_left_leg): _left_leg.rotation.x = -swing * 0.72
    if is_instance_valid(_right_leg): _right_leg.rotation.x = swing * 0.72

func character_signature() -> String:
    return CHARACTER_SIGNATURE

func pipeline_signature() -> String:
    return PIPELINE_SIGNATURE

func is_using_authored_character() -> bool:
    return _using_authored_character

func authored_character() -> Node3D:
    return _authored_character

func resolved_authored_scene_path() -> String:
    return _resolved_authored_scene_path

func _authored_candidates() -> Array[String]:
    var candidates: Array[String] = []
    if not authored_scene_path.is_empty():
        candidates.append(authored_scene_path)
    if allow_authored_fallback_paths:
        for fallback_path in FALLBACK_AUTHORED_CHARACTER_PATHS:
            if not candidates.has(fallback_path):
                candidates.append(fallback_path)
    return candidates

func _try_load_authored_character() -> bool:
    for candidate_path in _authored_candidates():
        if _try_load_authored_character_path(candidate_path):
            return true
    return false

func _try_load_authored_character_path(candidate_path: String) -> bool:
    if candidate_path.is_empty() or not ResourceLoader.exists(candidate_path):
        return false

    var resource := ResourceLoader.load(candidate_path)
    if not resource is PackedScene:
        push_warning("Player authored asset is not a PackedScene: %s" % candidate_path)
        return false

    var instance := (resource as PackedScene).instantiate()
    if not instance is Node3D:
        instance.queue_free()
        push_warning("Player authored asset root must be Node3D: %s" % candidate_path)
        return false

    _authored_character = instance as Node3D
    _authored_character.name = "AuthoredCharacter"
    _authored_character.position = authored_position
    _authored_character.rotation_degrees = authored_rotation_degrees
    _authored_character.scale = authored_scale
    add_child(_authored_character)
    _resolved_authored_scene_path = candidate_path
    _using_authored_character = true
    return true

func _hide_legacy_visuals(actor: Node3D) -> void:
    for path in ["MeshInstance3D", "Body", "Vest", "PoliceLabel"]:
        var legacy := actor.get_node_or_null(path)
        if legacy is VisualInstance3D:
            (legacy as VisualInstance3D).visible = false

func _build_character() -> void:
    var skin := _material(skin_color, 0.72)
    var hair := _material(Color(0.018, 0.014, 0.012, 1.0), 0.92)
    var pink := _material(accent_color, 0.58)
    var white := _material(Color(0.96, 0.96, 0.97, 1.0), 0.52)
    var bag_mat := _material(Color(0.36, 0.25, 0.17, 1.0), 0.66)
    var metal := _material(Color(0.78, 0.65, 0.27, 1.0), 0.28)

    # Fallback only. Authored Thandi GLB/FBX is the primary rendering path.
    _box("UpperTorso", Vector3(0.66, 0.43, 0.36), Vector3(0, 1.30, 0), pink)
    _box("CropTop", Vector3(0.61, 0.20, 0.365), Vector3(0, 1.09, -0.005), white)
    _box("Waist", Vector3(0.48, 0.18, 0.31), Vector3(0, 0.94, 0), skin)
    _box("Hips", Vector3(0.78, 0.34, 0.43), Vector3(0, 0.74, 0.015), pink)

    _left_arm = _box("LeftArm", Vector3(0.18, 0.69, 0.21), Vector3(-0.43, 1.23, 0), pink)
    _right_arm = _box("RightArm", Vector3(0.18, 0.69, 0.21), Vector3(0.43, 1.23, 0), pink)
    _sphere("LeftHand", Vector3(0.12, 0.14, 0.11), Vector3(-0.43, 0.82, 0), skin)
    _sphere("RightHand", Vector3(0.12, 0.14, 0.11), Vector3(0.43, 0.82, 0), skin)

    _left_leg = _box("LeftLeg", Vector3(0.29, 0.78, 0.32), Vector3(-0.20, 0.28, 0.01), pink)
    _right_leg = _box("RightLeg", Vector3(0.29, 0.78, 0.32), Vector3(0.20, 0.28, 0.01), pink)
    _box("LeftShoe", Vector3(0.29, 0.15, 0.44), Vector3(-0.20, -0.18, -0.06), white)
    _box("RightShoe", Vector3(0.29, 0.15, 0.44), Vector3(0.20, -0.18, -0.06), white)

    var head := _sphere("Head", Vector3(0.28, 0.34, 0.27), Vector3(0, 1.78, 0), skin)
    head.scale *= Vector3(0.98, 1.08, 0.94)
    _sphere("HairCap", Vector3(0.30, 0.19, 0.29), Vector3(0, 1.96, 0.02), hair)
    _sphere("HairBun", Vector3(0.17, 0.16, 0.17), Vector3(0, 1.99, 0.22), hair)
    _box("FaceStrand", Vector3(0.035, 0.43, 0.035), Vector3(-0.20, 1.75, -0.18), hair)

    _box("LeftSleeveStripe", Vector3(0.025, 0.62, 0.225), Vector3(-0.535, 1.23, 0), white)
    _box("RightSleeveStripe", Vector3(0.025, 0.62, 0.225), Vector3(0.535, 1.23, 0), white)
    _box("LeftTrouserStripe", Vector3(0.025, 0.71, 0.33), Vector3(-0.355, 0.29, 0), white)
    _box("RightTrouserStripe", Vector3(0.025, 0.71, 0.33), Vector3(0.355, 0.29, 0), white)

    _box("ShoulderBag", Vector3(0.30, 0.24, 0.13), Vector3(-0.53, 0.94, 0.03), bag_mat)
    var strap := _box("BagStrap", Vector3(0.035, 0.90, 0.035), Vector3(-0.22, 1.29, 0.01), bag_mat)
    strap.rotation.z = -0.58
    _sphere("Pendant", Vector3(0.045, 0.045, 0.025), Vector3(0, 1.48, -0.205), metal)
    _box("Phone", Vector3(0.105, 0.20, 0.025), Vector3(0.50, 0.88, -0.04), white)

func _material(color: Color, roughness: float) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    return material

func _box(name_value: String, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh.material = material
    var instance := MeshInstance3D.new()
    instance.name = name_value
    instance.mesh = mesh
    instance.position = pos
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    add_child(instance)
    return instance

func _sphere(name_value: String, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
    var mesh := SphereMesh.new()
    mesh.radius = 0.5
    mesh.height = 1.0
    mesh.radial_segments = 24
    mesh.rings = 12
    mesh.material = material
    var instance := MeshInstance3D.new()
    instance.name = name_value
    instance.mesh = mesh
    instance.position = pos
    instance.scale = size * 2.0
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    add_child(instance)
    return instance

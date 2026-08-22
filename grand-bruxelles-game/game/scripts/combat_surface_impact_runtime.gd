extends Node

# Lightweight, asset-independent impact presentation. The ray resolver supplies
# the exact collision point/normal/collider; this service classifies the hit and
# emits short-lived marks + debris/sparks without changing gameplay collision.

const SIGNATURE := "combat_surface_impact_v1"
const GROUND_NORMAL_Y := 0.55
const IMPACT_LIFETIME_S := 0.34
const MARK_LIFETIME_S := 1.60

var _impact_serial := 0

func classify_surface(collider: Variant, normal: Vector3 = Vector3.UP) -> StringName:
    var current := collider as Node if collider is Node else null
    while current != null:
        if current is NpcAgent:
            return &"body"
        var lowered := String(current.name).to_lower()
        if current.is_in_group("combat_surface_body") or current.is_in_group("npc") or current.is_in_group("pedestrian"):
            return &"body"
        if current.is_in_group("combat_surface_metal") or _contains_any(lowered, ["metal", "steel", "iron", "rail", "vehicle", "car", "bollard", "lamp"]):
            return &"metal"
        if current.is_in_group("combat_surface_wood") or _contains_any(lowered, ["wood", "timber", "tree", "bench", "door"]):
            return &"wood"
        if current.has_meta("combat_surface_type"):
            var explicit := StringName(current.get_meta("combat_surface_type", &""))
            if explicit in [&"ground", &"wall", &"metal", &"wood", &"body"]:
                return explicit
        current = current.get_parent()
    return &"ground" if normal.normalized().y >= GROUND_NORMAL_Y else &"wall"

func spawn_impact(
    position: Vector3,
    normal: Vector3,
    collider: Variant,
    weapon_id: StringName,
    strength: float = 1.0,
    surface_hint: StringName = &""
) -> Node3D:
    var scene := get_tree().current_scene
    if scene == null:
        return null
    var safe_normal := normal.normalized()
    if safe_normal.length_squared() <= 0.001:
        safe_normal = Vector3.UP
    var surface := surface_hint if surface_hint != &"" else classify_surface(collider, safe_normal)
    if surface not in [&"ground", &"wall", &"metal", &"wood", &"body"]:
        surface = classify_surface(collider, safe_normal)

    _impact_serial += 1
    var root := Node3D.new()
    root.name = "CombatImpact_%s_%d" % [String(surface), _impact_serial]
    scene.add_child(root)
    root.global_position = position + safe_normal * 0.008
    root.set_meta("combat_impact_signature", SIGNATURE)
    root.set_meta("combat_impact_surface", surface)
    root.set_meta("combat_impact_weapon_id", weapon_id)
    root.set_meta("combat_impact_world_position", position)
    root.set_meta("combat_impact_world_normal", safe_normal)

    var profile := impact_profile(surface)
    _spawn_contact_mark(root, profile)
    var particle_count := maxi(1, int(round(float(profile.get("particle_count", 4)) * clampf(strength, 0.5, 1.5))))
    for index: int in range(particle_count):
        _spawn_fragment(root, safe_normal, surface, profile, index, particle_count, strength)

    set_meta("combat_last_impact_surface", surface)
    set_meta("combat_last_impact_weapon_id", weapon_id)
    set_meta("combat_last_impact_position", position)
    set_meta("combat_impact_count", int(get_meta("combat_impact_count", 0)) + 1)

    var timer := get_tree().create_timer(MARK_LIFETIME_S)
    timer.timeout.connect(root.queue_free)
    return root

func _spawn_contact_mark(root: Node3D, profile: Dictionary) -> void:
    var mark := MeshInstance3D.new()
    mark.name = "ImpactTrace"
    var mesh := SphereMesh.new()
    mesh.radius = float(profile.get("mark_radius", 0.032))
    mesh.height = float(profile.get("mark_radius", 0.032)) * 0.55
    mesh.radial_segments = 8
    mesh.rings = 4
    mesh.material = _material(profile.get("mark_color", Color(0.16, 0.15, 0.14, 1.0)), bool(profile.get("emissive", false)))
    mark.mesh = mesh
    mark.scale = Vector3(1.0, 0.32, 1.0)
    root.add_child(mark)
    var tween := create_tween()
    tween.tween_interval(0.90)
    tween.tween_property(mark, "scale", Vector3(0.55, 0.12, 0.55), 0.65)

func _spawn_fragment(root: Node3D, normal: Vector3, surface: StringName, profile: Dictionary, index: int, count: int, strength: float) -> void:
    var fragment := MeshInstance3D.new()
    fragment.name = "ImpactFragment_%02d" % index
    var mesh := BoxMesh.new()
    var spark := surface == &"metal"
    var body := surface == &"body"
    if spark:
        mesh.size = Vector3(0.008, 0.008, 0.085)
    elif body:
        mesh.size = Vector3(0.018, 0.018, 0.026)
    else:
        mesh.size = Vector3(0.014, 0.014, 0.032)
    mesh.material = _material(profile.get("particle_color", Color(0.34, 0.31, 0.27, 1.0)), spark)
    fragment.mesh = mesh
    root.add_child(fragment)

    var tangent_a := normal.cross(Vector3.UP)
    if tangent_a.length_squared() < 0.01:
        tangent_a = normal.cross(Vector3.RIGHT)
    tangent_a = tangent_a.normalized()
    var tangent_b := normal.cross(tangent_a).normalized()
    var phase := (float(index) / maxf(float(count), 1.0)) * TAU
    var radial := tangent_a * cos(phase) + tangent_b * sin(phase)
    var outward := 0.08 + 0.055 * float(index % 3)
    var forward := 0.12 + 0.045 * float((index + 1) % 4)
    if spark:
        outward *= 1.8
        forward *= 1.55
    elif surface == &"ground" or surface == &"wall":
        outward *= 1.25
    var travel := (radial * outward + normal * forward) * clampf(strength, 0.65, 1.35)
    if surface == &"ground" or surface == &"wood":
        travel += Vector3.UP * 0.04

    var tween := create_tween()
    tween.set_parallel(true)
    tween.tween_property(fragment, "position", travel, IMPACT_LIFETIME_S)
    tween.tween_property(fragment, "rotation", Vector3(phase, phase * 0.7, phase * 1.3), IMPACT_LIFETIME_S)
    tween.tween_property(fragment, "scale", Vector3.ZERO, IMPACT_LIFETIME_S)

func _material(color: Color, emissive: bool) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.62
    material.metallic = 0.45 if emissive else 0.04
    if emissive:
        material.emission_enabled = true
        material.emission = color
        material.emission_energy_multiplier = 2.2
    return material

static func impact_profile(surface: StringName) -> Dictionary:
    match surface:
        &"metal":
            return {
                "mark_color": Color(0.12, 0.12, 0.13, 1.0),
                "particle_color": Color(1.0, 0.58, 0.16, 1.0),
                "particle_count": 7,
                "mark_radius": 0.028,
                "emissive": false,
            }
        &"wood":
            return {
                "mark_color": Color(0.18, 0.105, 0.055, 1.0),
                "particle_color": Color(0.46, 0.27, 0.10, 1.0),
                "particle_count": 6,
                "mark_radius": 0.034,
                "emissive": false,
            }
        &"body":
            return {
                "mark_color": Color(0.24, 0.025, 0.025, 1.0),
                "particle_color": Color(0.56, 0.035, 0.035, 1.0),
                "particle_count": 5,
                "mark_radius": 0.030,
                "emissive": false,
            }
        &"ground":
            return {
                "mark_color": Color(0.15, 0.14, 0.13, 1.0),
                "particle_color": Color(0.43, 0.39, 0.33, 1.0),
                "particle_count": 5,
                "mark_radius": 0.036,
                "emissive": false,
            }
        _:
            return {
                "mark_color": Color(0.13, 0.13, 0.13, 1.0),
                "particle_color": Color(0.36, 0.35, 0.33, 1.0),
                "particle_count": 4,
                "mark_radius": 0.032,
                "emissive": false,
            }

static func _contains_any(value: String, tokens: Array[String]) -> bool:
    for token: String in tokens:
        if value.contains(token):
            return true
    return false

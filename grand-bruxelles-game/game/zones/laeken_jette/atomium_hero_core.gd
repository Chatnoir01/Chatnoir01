extends Node3D

## Source-bounded Atomium core silhouette.
## Only the published 9-sphere / 20-tube dimensions are rendered here.
## The three support pillars and global yaw remain unresolved and are deliberately omitted.

@export_file("*.json") var evidence_path := "res://data/sources/laeken_jette/atomium_hero_core_evidence.json"

const SPHERE_RADIAL_SEGMENTS := 48
const SPHERE_RINGS := 24
const TUBE_RADIAL_SEGMENTS := 32

var hero_built := false
var sphere_count := 0
var tube_count := 0
var source_height_m := 0.0
var source_sphere_diameter_m := 0.0
var source_tube_diameter_m := 0.0
var unresolved_support_pillars := 0
var anchor_position := Vector3.ZERO

var _sphere_material: StandardMaterial3D
var _tube_material: StandardMaterial3D

func build_on_terrain(terrain: Node) -> bool:
    if hero_built:
        return true
    if terrain == null or not terrain.has_method("sample_height"):
        push_error("AtomiumHeroCore: terrain sampler unavailable")
        return false
    var evidence := _load_evidence()
    if evidence.is_empty():
        return false
    var dimensions: Dictionary = evidence.get("authoritative_dimensions", {})
    var centres_raw: Variant = evidence.get("core_sphere_centres_m", [])
    var tubes_raw: Variant = evidence.get("connecting_tubes", [])
    if not centres_raw is Array or not tubes_raw is Array:
        push_error("AtomiumHeroCore: invalid topology payload")
        return false
    source_height_m = float(dimensions.get("total_height_m", 0.0))
    source_sphere_diameter_m = float(dimensions.get("sphere_diameter_m", 0.0))
    source_tube_diameter_m = float(dimensions.get("tube_diameter_m", 0.0))
    unresolved_support_pillars = int(dimensions.get("support_pillar_count", 0))
    if centres_raw.size() != int(dimensions.get("sphere_count", -1)) or tubes_raw.size() != int(dimensions.get("connecting_tube_count", -1)):
        push_error("AtomiumHeroCore: source counts do not match topology")
        return false
    if not terrain.get("terrain_loaded"):
        push_error("AtomiumHeroCore: terrain is not loaded")
        return false
    var atomium_anchor: Vector3 = terrain.get("atomium_game_position")
    var sampled_y := float(terrain.call("sample_height", atomium_anchor.x, atomium_anchor.z))
    anchor_position = Vector3(atomium_anchor.x, sampled_y, atomium_anchor.z)
    position = anchor_position
    _make_materials()
    var centres: Array[Vector3] = []
    for raw: Variant in centres_raw:
        if not raw is Array or raw.size() != 3:
            push_error("AtomiumHeroCore: invalid sphere centre")
            return false
        centres.append(Vector3(float(raw[0]), float(raw[1]), float(raw[2])))
    for i: int in range(centres.size()):
        _add_sphere("Sphere_%02d" % i, centres[i])
    for raw_edge: Variant in tubes_raw:
        if not raw_edge is Array or raw_edge.size() != 2:
            push_error("AtomiumHeroCore: invalid tube edge")
            return false
        var a := int(raw_edge[0])
        var b := int(raw_edge[1])
        if a < 0 or b < 0 or a >= centres.size() or b >= centres.size() or a == b:
            push_error("AtomiumHeroCore: tube edge outside sphere topology")
            return false
        _add_tube(centres[a], centres[b])
    hero_built = sphere_count == 9 and tube_count == 20
    if hero_built:
        print("ATOMIUM_HERO_CORE_READY: spheres=%d tubes=%d anchor_y=%.3f unresolved_pillars=%d" % [sphere_count, tube_count, anchor_position.y, unresolved_support_pillars])
    return hero_built

func _load_evidence() -> Dictionary:
    if not FileAccess.file_exists(evidence_path):
        push_error("AtomiumHeroCore: evidence missing")
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(evidence_path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("AtomiumHeroCore: evidence is not a dictionary")
        return {}
    var evidence := parsed as Dictionary
    if str(evidence.get("crs", "")) != "EPSG:31370":
        push_error("AtomiumHeroCore: evidence CRS is not EPSG:31370")
        return {}
    var status: Dictionary = evidence.get("status", {})
    if bool(status.get("runtime_approved", true)) or bool(status.get("realism_complete", true)):
        push_error("AtomiumHeroCore: provisional evidence was incorrectly promoted")
        return {}
    return evidence

func _make_materials() -> void:
    _sphere_material = StandardMaterial3D.new()
    _sphere_material.albedo_color = Color(0.82, 0.85, 0.87, 1.0)
    _sphere_material.metallic = 0.96
    _sphere_material.roughness = 0.16
    _tube_material = StandardMaterial3D.new()
    _tube_material.albedo_color = Color(0.57, 0.61, 0.64, 1.0)
    _tube_material.metallic = 0.78
    _tube_material.roughness = 0.28

func _add_sphere(node_name: String, centre: Vector3) -> void:
    var sphere := SphereMesh.new()
    sphere.radius = source_sphere_diameter_m * 0.5
    sphere.height = source_sphere_diameter_m
    sphere.radial_segments = SPHERE_RADIAL_SEGMENTS
    sphere.rings = SPHERE_RINGS
    sphere.material = _sphere_material
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = sphere
    instance.position = centre
    add_child(instance)
    sphere_count += 1

func _add_tube(a: Vector3, b: Vector3) -> void:
    var delta := b - a
    var length := delta.length()
    if length <= 0.01:
        return
    var cylinder := CylinderMesh.new()
    cylinder.top_radius = source_tube_diameter_m * 0.5
    cylinder.bottom_radius = source_tube_diameter_m * 0.5
    cylinder.height = length
    cylinder.radial_segments = TUBE_RADIAL_SEGMENTS
    cylinder.material = _tube_material
    var instance := MeshInstance3D.new()
    instance.name = "Tube_%02d" % tube_count
    instance.mesh = cylinder
    instance.position = (a + b) * 0.5
    instance.quaternion = Quaternion(Vector3.UP, delta.normalized())
    add_child(instance)
    tube_count += 1

func measured_vertical_extent() -> Vector2:
    if not hero_built:
        return Vector2.ZERO
    var half_diameter := source_sphere_diameter_m * 0.5
    var min_y := INF
    var max_y := -INF
    for child: Node in get_children():
        if child is MeshInstance3D and child.name.begins_with("Sphere_"):
            var y := (child as MeshInstance3D).position.y
            min_y = minf(min_y, y - half_diameter)
            max_y = maxf(max_y, y + half_diameter)
    return Vector2(min_y, max_y)

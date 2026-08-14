extends Node3D

## Source-positioned public-tree context for the Atomium hero view.
## Only point positions/species metadata are authoritative. Mesh dimensions are
## deterministic presentation approximations and are deliberately non-physical.

@export_file("*.json") var data_path := "res://data/environment/laeken_jette/official_city_trees.game.json"
@export_file("*.json") var provenance_path := "res://data/sources/laeken_jette/official_city_trees_provenance.json"
@export var hero_radius_m := 420.0

const PRESENTATION_TRUNK_RADIUS_M := 0.22
const PRESENTATION_TRUNK_HEIGHT_M := 5.0
const PRESENTATION_CROWN_RADIUS_M := 2.4
const PRESENTATION_CROWN_Y_M := 6.1

var source_feature_count := 0
var rendered_tree_count := 0
var terrain_rejected_count := 0
var radius_rejected_count := 0
var source_dimensions_claimed := false
var collision_created := false
var _trunk_multimesh: MultiMesh
var _crown_multimesh: MultiMesh

func build_on_terrain(terrain: Node) -> bool:
    if terrain == null or not terrain.has_method("sample_height") or not terrain.has_method("contains_game_point"):
        push_error("AtomiumOfficialCityTrees: terrain sampler unavailable")
        return false
    if not bool(terrain.get("terrain_loaded")):
        push_error("AtomiumOfficialCityTrees: terrain not loaded")
        return false
    var provenance := _load_dictionary(provenance_path)
    if provenance.is_empty() or str(provenance.get("source_crs", "")) != "EPSG:31370":
        push_error("AtomiumOfficialCityTrees: provenance CRS invalid")
        return false
    var parsed := _load_dictionary(data_path)
    if parsed.is_empty() or str(parsed.get("type", "")) != "FeatureCollection":
        push_error("AtomiumOfficialCityTrees: tree GeoJSON unavailable")
        return false
    var features: Variant = parsed.get("features", [])
    if not features is Array:
        push_error("AtomiumOfficialCityTrees: features payload invalid")
        return false
    source_feature_count = features.size()
    if source_feature_count != int(provenance.get("selected_feature_count", -1)):
        push_error("AtomiumOfficialCityTrees: source feature count drift")
        return false
    source_dimensions_claimed = false

    var hero_pos: Vector3 = terrain.get("atomium_game_position")
    var positions: Array[Vector3] = []
    var scales: Array[float] = []
    for raw_feature: Variant in features:
        if not raw_feature is Dictionary:
            continue
        var feature := raw_feature as Dictionary
        var geometry: Variant = feature.get("geometry", {})
        if not geometry is Dictionary or str((geometry as Dictionary).get("type", "")) != "Point":
            continue
        var coords: Variant = (geometry as Dictionary).get("coordinates", [])
        if not coords is Array or coords.size() < 2:
            continue
        var x := float(coords[0])
        var z := float(coords[1])
        var horizontal := Vector2(x - hero_pos.x, z - hero_pos.z).length()
        if horizontal > hero_radius_m:
            radius_rejected_count += 1
            continue
        if not bool(terrain.call("contains_game_point", x, z)):
            terrain_rejected_count += 1
            continue
        var y := float(terrain.call("sample_height", x, z))
        positions.append(Vector3(x, y, z))
        scales.append(_presentation_scale(str(feature.get("id", "tree_%d" % positions.size()))))

    rendered_tree_count = positions.size()
    if rendered_tree_count <= 0:
        push_error("AtomiumOfficialCityTrees: no source trees intersect hero terrain")
        return false
    _build_multimeshes(positions, scales)
    print("ATOMIUM_OFFICIAL_TREES_READY: source=%d rendered=%d radius_rejected=%d terrain_rejected=%d" % [source_feature_count, rendered_tree_count, radius_rejected_count, terrain_rejected_count])
    return true

func _load_dictionary(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}

func _presentation_scale(identifier: String) -> float:
    var bucket := abs(identifier.hash()) % 9
    return 0.84 + float(bucket) * 0.04

func _build_multimeshes(positions: Array[Vector3], scales: Array[float]) -> void:
    var trunk_mesh := CylinderMesh.new()
    trunk_mesh.top_radius = PRESENTATION_TRUNK_RADIUS_M
    trunk_mesh.bottom_radius = PRESENTATION_TRUNK_RADIUS_M * 1.15
    trunk_mesh.height = PRESENTATION_TRUNK_HEIGHT_M
    trunk_mesh.radial_segments = 8
    var trunk_mat := StandardMaterial3D.new()
    trunk_mat.albedo_color = Color(0.20, 0.12, 0.07, 1.0)
    trunk_mat.roughness = 0.92
    trunk_mesh.material = trunk_mat

    var crown_mesh := SphereMesh.new()
    crown_mesh.radius = PRESENTATION_CROWN_RADIUS_M
    crown_mesh.height = PRESENTATION_CROWN_RADIUS_M * 2.0
    crown_mesh.radial_segments = 12
    crown_mesh.rings = 8
    var crown_mat := StandardMaterial3D.new()
    crown_mat.albedo_color = Color(0.16, 0.34, 0.12, 1.0)
    crown_mat.roughness = 0.96
    crown_mesh.material = crown_mat

    _trunk_multimesh = MultiMesh.new()
    _trunk_multimesh.transform_format = MultiMesh.TRANSFORM_3D
    _trunk_multimesh.mesh = trunk_mesh
    _trunk_multimesh.instance_count = positions.size()
    _crown_multimesh = MultiMesh.new()
    _crown_multimesh.transform_format = MultiMesh.TRANSFORM_3D
    _crown_multimesh.mesh = crown_mesh
    _crown_multimesh.instance_count = positions.size()

    for i: int in range(positions.size()):
        var p := positions[i]
        var s := scales[i]
        var trunk_basis := Basis.from_scale(Vector3(s, s, s))
        var crown_basis := Basis.from_scale(Vector3(s, s, s))
        _trunk_multimesh.set_instance_transform(i, Transform3D(trunk_basis, p + Vector3(0.0, PRESENTATION_TRUNK_HEIGHT_M * 0.5 * s, 0.0)))
        _crown_multimesh.set_instance_transform(i, Transform3D(crown_basis, p + Vector3(0.0, PRESENTATION_CROWN_Y_M * s, 0.0)))

    var trunks := MultiMeshInstance3D.new()
    trunks.name = "OfficialAtomiumTreeTrunks"
    trunks.multimesh = _trunk_multimesh
    add_child(trunks)
    var crowns := MultiMeshInstance3D.new()
    crowns.name = "OfficialAtomiumTreeCrowns"
    crowns.multimesh = _crown_multimesh
    add_child(crowns)

func instance_position(index: int) -> Vector3:
    if _trunk_multimesh == null or index < 0 or index >= _trunk_multimesh.instance_count:
        return Vector3.ZERO
    var transform := _trunk_multimesh.get_instance_transform(index)
    var scale_y := transform.basis.get_scale().y
    return transform.origin - Vector3(0.0, PRESENTATION_TRUNK_HEIGHT_M * 0.5 * scale_y, 0.0)

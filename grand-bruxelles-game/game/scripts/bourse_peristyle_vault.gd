extends Node3D

@export_file("*.json") var candidate_path: String = "res://data/qa/bourse_portico_articulation_candidate.json"

var _stone_material: StandardMaterial3D
var _interior_column_count := 0
var _vault_count := 0

func _ready() -> void:
    _stone_material = StandardMaterial3D.new()
    _stone_material.albedo_color = Color(0.84, 0.82, 0.76, 1.0)
    _stone_material.roughness = 0.76
    _stone_material.cull_mode = BaseMaterial3D.CULL_DISABLED
    _build_source_bounded_interior()

func _read_candidate() -> Dictionary:
    if not FileAccess.file_exists(candidate_path):
        push_error("Bourse peristyle vault candidate missing")
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(candidate_path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Bourse peristyle vault candidate invalid")
        return {}
    var data := parsed as Dictionary
    var source_contract: Dictionary = data.get("source_contract", {})
    var fact := str(source_contract.get("heritage_peristyle_fact", ""))
    if not fact.contains("two additional Corinthian columns") or not fact.contains("barrel vault"):
        push_error("Bourse peristyle heritage contract missing")
        return {}
    if bool(data.get("runtime_approved", true)) or bool(data.get("realism_complete", true)):
        push_error("Bourse peristyle candidate must remain provisional")
        return {}
    return data

func _vec2(raw: Variant) -> Vector2:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 2:
        return Vector2.ZERO
    return Vector2(float(raw[0]), float(raw[1]))

func _column_piece(name_value: String, radius: float, height: float, position_value: Vector3) -> void:
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = height
    mesh.radial_segments = 28
    mesh.rings = 2
    var instance := MeshInstance3D.new()
    instance.name = name_value
    instance.mesh = mesh
    instance.material_override = _stone_material
    instance.position = position_value
    add_child(instance)

func _build_inner_column(center: Vector3, index: int) -> void:
    var base_y := 4.05
    var base_height := 0.46
    var shaft_height := 10.65
    var capital_height := 0.58
    _column_piece("InnerColumn_%02d_Base" % index, 0.72, base_height, center + Vector3(0.0, base_y + base_height * 0.5, 0.0))
    _column_piece("InnerColumn_%02d_Shaft" % index, 0.56, shaft_height, center + Vector3(0.0, base_y + base_height + shaft_height * 0.5, 0.0))
    _column_piece("InnerColumn_%02d_Capital" % index, 0.76, capital_height, center + Vector3(0.0, base_y + base_height + shaft_height + capital_height * 0.5, 0.0))
    _interior_column_count += 1

func _build_barrel_vault(center: Vector3, tangent: Vector3, depth_axis: Vector3) -> void:
    var half_span := 7.2
    var depth := 4.6
    var spring_y := 14.75
    var rise := 4.25
    var segments := 24
    var vertices := PackedVector3Array()
    var indices := PackedInt32Array()
    for depth_index: int in range(2):
        var depth_offset := (-0.5 if depth_index == 0 else 0.5) * depth
        for i: int in range(segments + 1):
            var angle := PI * float(i) / float(segments)
            var across := cos(angle) * half_span
            var y := spring_y + sin(angle) * rise
            vertices.append(center + tangent * across + depth_axis * depth_offset + Vector3(0.0, y, 0.0))
    var row := segments + 1
    for i: int in range(segments):
        var a := i
        var b := i + 1
        var c := row + i
        var d := row + i + 1
        indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    var instance := MeshInstance3D.new()
    instance.name = "PeristyleBarrelVault"
    instance.mesh = mesh
    instance.material_override = _stone_material
    add_child(instance)
    _vault_count = 1

func _build_source_bounded_interior() -> void:
    var data := _read_candidate()
    if data.is_empty():
        return
    var envelope: Dictionary = data.get("authoritative_front_envelope", {})
    var plane_xz := _vec2(envelope.get("plane_point_game_x_z", []))
    var forward_xz := _vec2(envelope.get("toward_camera_x_z", []))
    var tangent_xz := _vec2(envelope.get("tangent_x_z", []))
    var toward_camera := Vector3(forward_xz.x, 0.0, forward_xz.y).normalized()
    var tangent := Vector3(tangent_xz.x, 0.0, tangent_xz.y).normalized()
    if toward_camera.length_squared() < 0.99 or tangent.length_squared() < 0.99:
        push_error("Bourse peristyle basis invalid")
        return
    var front_mid_t := (float(envelope.get("tangent_min_m", 0.0)) + float(envelope.get("tangent_max_m", 0.0))) * 0.5
    var plane := Vector3(plane_xz.x, 0.0, plane_xz.y)
    var interior_center := plane + tangent * front_mid_t - toward_camera * 1.8
    for index: int in range(2):
        var along := -5.0 if index == 0 else 5.0
        _build_inner_column(interior_center + tangent * along + toward_camera * 0.35, index)
    _build_barrel_vault(interior_center, tangent, toward_camera)
    set_meta("runtime_approved", false)
    set_meta("realism_complete", false)
    set_meta("source_semantic", "two additional Corinthian columns + coffered barrel vault")
    set_meta("exact_dimensions_measured", false)
    print("BOURSE_PERISTYLE_VAULT_READY: inner_columns=%d vaults=%d runtime_approved=false" % [_interior_column_count, _vault_count])

func diagnostic_inner_column_count() -> int:
    return _interior_column_count

func diagnostic_vault_count() -> int:
    return _vault_count

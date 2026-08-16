extends Node3D

@export_file("*.json") var candidate_path: String = "res://data/qa/bourse_portico_articulation_candidate.json"

var _stone_material: StandardMaterial3D
var _stair_material: StandardMaterial3D
var _opening_material: StandardMaterial3D
var _column_count := 0
var _inner_column_count := 0
var _pediment_count := 0
var _step_count := 0
var _pilaster_count := 0
var _opening_count := 0
var _oval_light_count := 0
var _entablature_count := 0
var _clock_count := 0


func _ready() -> void:
    _make_materials()
    _build_candidate()


func _make_materials() -> void:
    _stone_material = StandardMaterial3D.new()
    _stone_material.albedo_color = Color(0.72, 0.69, 0.61, 1.0)
    _stone_material.roughness = 0.90
    _stone_material.cull_mode = BaseMaterial3D.CULL_DISABLED

    _stair_material = StandardMaterial3D.new()
    _stair_material.albedo_color = Color(0.67, 0.65, 0.60, 1.0)
    _stair_material.roughness = 0.94

    _opening_material = StandardMaterial3D.new()
    _opening_material.albedo_color = Color(0.045, 0.06, 0.065, 1.0)
    _opening_material.roughness = 0.34
    _opening_material.metallic = 0.08


func _read_candidate() -> Dictionary:
    if not FileAccess.file_exists(candidate_path):
        push_error("Bourse portico candidate missing: %s" % candidate_path)
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(candidate_path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Invalid Bourse portico candidate JSON")
        return {}
    var data := parsed as Dictionary
    if str(data.get("schema", "")) != "grand-bruxelles-bourse-portico-articulation-candidate-v1":
        push_error("Unsupported Bourse portico candidate schema")
        return {}
    if bool(data.get("runtime_approved", true)) or bool(data.get("realism_complete", true)):
        push_error("Provisional Bourse portico candidate must remain unapproved")
        return {}
    return data


func _vec2(raw: Variant) -> Vector2:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 2:
        return Vector2.ZERO
    return Vector2(float(raw[0]), float(raw[1]))


func _cylinder(name_value: String, radius: float, height: float, position_value: Vector3) -> MeshInstance3D:
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = height
    mesh.radial_segments = 24
    mesh.rings = 2
    var instance := MeshInstance3D.new()
    instance.name = name_value
    instance.mesh = mesh
    instance.material_override = _stone_material
    instance.position = position_value
    add_child(instance)
    return instance


func _front_box(
    name_value: String,
    width: float,
    height: float,
    depth: float,
    position_value: Vector3,
    yaw: float,
    material: Material
) -> CSGBox3D:
    var box := CSGBox3D.new()
    box.name = name_value
    box.size = Vector3(width, height, depth)
    box.position = position_value
    box.rotation.y = yaw
    box.material = material
    box.use_collision = false
    add_child(box)
    return box


func _round_opening(
    name_value: String,
    radius_x: float,
    radius_y: float,
    depth_scale: float,
    position_value: Vector3,
    yaw: float
) -> MeshInstance3D:
    var mesh := SphereMesh.new()
    mesh.radius = 1.0
    mesh.height = 2.0
    mesh.radial_segments = 32
    mesh.rings = 16
    var instance := MeshInstance3D.new()
    instance.name = name_value
    instance.mesh = mesh
    instance.material_override = _opening_material
    instance.position = position_value
    instance.rotation.y = yaw
    instance.scale = Vector3(radius_x, radius_y, depth_scale)
    add_child(instance)
    return instance


func _build_column(center: Vector3, index: int, visual: Dictionary) -> void:
    var base_y := float(visual.get("column_base_y_m", 4.0))
    var base_height := float(visual.get("column_base_height_m", 0.55))
    var shaft_height := float(visual.get("column_shaft_height_m", 14.8))
    var capital_height := float(visual.get("column_capital_height_m", 0.65))
    var base_radius := float(visual.get("column_base_radius_m", 0.88))
    var shaft_radius := float(visual.get("column_shaft_radius_m", 0.72))
    var capital_radius := float(visual.get("column_capital_radius_m", 0.92))

    _cylinder("Column_%02d_Base" % index, base_radius, base_height, center + Vector3(0.0, base_y + base_height * 0.5, 0.0))
    _cylinder("Column_%02d_Shaft" % index, shaft_radius, shaft_height, center + Vector3(0.0, base_y + base_height + shaft_height * 0.5, 0.0))
    _cylinder("Column_%02d_Capital" % index, capital_radius, capital_height, center + Vector3(0.0, base_y + base_height + shaft_height + capital_height * 0.5, 0.0))
    _column_count += 1


func _build_inner_column(center: Vector3, index: int, visual: Dictionary) -> void:
    # The heritage inventory explicitly states that the covered peristyle is
    # punctuated by two additional Corinthian columns. Reuse the already-bounded
    # candidate's Corinthian proxy dimensions; only the discrete count is source
    # truth. Exact recess/spacing remains a bounded visualization parameter.
    var base_y := float(visual.get("column_base_y_m", 4.0))
    var base_height := float(visual.get("column_base_height_m", 0.55))
    var shaft_height := float(visual.get("column_shaft_height_m", 14.8))
    var capital_height := float(visual.get("column_capital_height_m", 0.65))
    var base_radius := float(visual.get("column_base_radius_m", 0.88))
    var shaft_radius := float(visual.get("column_shaft_radius_m", 0.72))
    var capital_radius := float(visual.get("column_capital_radius_m", 0.92))

    var base := _cylinder("SourceInnerColumn_%02d_Base" % index, base_radius, base_height, center + Vector3(0.0, base_y + base_height * 0.5, 0.0))
    var shaft := _cylinder("SourceInnerColumn_%02d_Shaft" % index, shaft_radius, shaft_height, center + Vector3(0.0, base_y + base_height + shaft_height * 0.5, 0.0))
    var capital := _cylinder("SourceInnerColumn_%02d_Capital" % index, capital_radius, capital_height, center + Vector3(0.0, base_y + base_height + shaft_height + capital_height * 0.5, 0.0))
    for piece in [base, shaft, capital]:
        piece.add_to_group("bourse_source_semantic_completion")
        piece.set_meta("source_semantic", "covered peristyle additional Corinthian column")
    _inner_column_count += 1


func _add_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
    st.add_vertex(a)
    st.add_vertex(b)
    st.add_vertex(c)


func _build_source_pediment(
    front_center: Vector3,
    toward_camera: Vector3,
    tangent: Vector3,
    span: float,
    envelope: Dictionary,
    visual: Dictionary
) -> void:
    # Source truth: the six Corinthian columns carry a triangular pediment.
    # Exact sculptural relief is deliberately NOT invented. The neutral solid
    # tympanum is bounded by the authoritative front envelope and candidate
    # entablature; it restores the dominant silhouette while remaining honest.
    var width := minf(float(visual.get("entablature_width_m", 28.7)), span * 0.91)
    var base_y := float(visual.get("entablature_center_y_m", 20.225)) + float(visual.get("entablature_height_m", 0.45)) * 0.5
    var envelope_top := float(envelope.get("y_max_m", 22.6831))
    var apex_y := minf(envelope_top - 0.12, base_y + 2.20)
    var depth := 0.42
    var forward_offset := float(visual.get("entablature_forward_offset_m", 0.75)) + 0.03
    if width <= 0.0 or apex_y <= base_y + 0.5:
        push_error("Bourse source pediment cannot fit authoritative envelope")
        return

    var front_offset := toward_camera * (forward_offset + depth * 0.5)
    var back_offset := toward_camera * (forward_offset - depth * 0.5)
    var half := width * 0.5
    var lf := front_center - tangent * half + front_offset + Vector3(0.0, base_y, 0.0)
    var rf := front_center + tangent * half + front_offset + Vector3(0.0, base_y, 0.0)
    var af := front_center + front_offset + Vector3(0.0, apex_y, 0.0)
    var lb := front_center - tangent * half + back_offset + Vector3(0.0, base_y, 0.0)
    var rb := front_center + tangent * half + back_offset + Vector3(0.0, base_y, 0.0)
    var ab := front_center + back_offset + Vector3(0.0, apex_y, 0.0)

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    _add_triangle(st, lf, rf, af)
    _add_triangle(st, rb, lb, ab)
    _add_triangle(st, lb, rb, rf)
    _add_triangle(st, lb, rf, lf)
    _add_triangle(st, lf, af, ab)
    _add_triangle(st, lf, ab, lb)
    _add_triangle(st, af, rf, rb)
    _add_triangle(st, af, rb, ab)
    st.generate_normals()
    var mesh := st.commit()
    if mesh == null:
        push_error("Bourse source pediment mesh failed")
        return
    var instance := MeshInstance3D.new()
    instance.name = "SourceTriangularPediment"
    instance.mesh = mesh
    instance.material_override = _stone_material
    instance.add_to_group("bourse_source_semantic_completion")
    instance.set_meta("source_semantic", "six Corinthian columns carrying triangular pediment")
    instance.set_meta("sculptural_relief_authored", false)
    instance.set_meta("bounded_by_authoritative_front_envelope", true)
    add_child(instance)
    _pediment_count = 1


func _build_source_peristyle_completion(
    front_center: Vector3,
    toward_camera: Vector3,
    tangent: Vector3,
    span: float,
    envelope: Dictionary,
    visual: Dictionary
) -> void:
    _build_source_pediment(front_center, toward_camera, tangent, span, envelope, visual)
    var recess := -2.55
    var spacing := minf(5.0, span * 0.16)
    for index in range(2):
        var along := -spacing if index == 0 else spacing
        _build_inner_column(front_center + tangent * along + toward_camera * recess, index, visual)


func _build_entablature(front_center: Vector3, toward_camera: Vector3, yaw: float, visual: Dictionary) -> void:
    var width := float(visual.get("entablature_width_m", 28.7))
    var height := float(visual.get("entablature_height_m", 0.45))
    var depth := float(visual.get("entablature_depth_m", 0.65))
    var y := float(visual.get("entablature_center_y_m", 20.225))
    var offset := float(visual.get("entablature_forward_offset_m", 0.75))
    if width <= 0.0 or height <= 0.0 or depth <= 0.0:
        push_error("Invalid Bourse entablature candidate")
        return
    _front_box("PorticoEntablature", width, height, depth, front_center + toward_camera * offset + Vector3(0.0, y, 0.0), yaw, _stone_material)
    _entablature_count = 1


func _build_stair(front_center: Vector3, toward_camera: Vector3, yaw: float, visual: Dictionary) -> void:
    var width := float(visual.get("stair_width_m", 29.0))
    var depth := float(visual.get("stair_depth_m", 9.6))
    var total_rise := float(visual.get("stair_total_rise_m", 4.0))
    var count := int(visual.get("stair_step_count", 16))
    var clearance := float(visual.get("stair_building_clearance_m", 0.35))
    if count <= 0 or width <= 0.0 or depth <= 0.0 or total_rise <= 0.0:
        push_error("Invalid Bourse stair candidate")
        return
    var tread := depth / float(count)
    var rise := total_rise / float(count)
    for index: int in range(count):
        var top_y := total_rise - float(index) * rise
        var offset := clearance + (float(index) + 0.5) * tread
        _front_box("MonumentalStair_%02d" % index, width, top_y, tread, front_center + toward_camera * offset + Vector3(0.0, top_y * 0.5, 0.0), yaw, _stair_material)
        _step_count += 1


func _build_clock(center: Vector3, yaw: float, visual: Dictionary) -> void:
    var radius := float(visual.get("clock_radius_m", 1.12))
    var depth_scale := float(visual.get("clock_depth_scale_m", 0.09))
    if radius <= 0.0 or depth_scale <= 0.0:
        push_error("Invalid Bourse clock candidate")
        return
    _round_opening("RearFacadeClock", radius, radius, depth_scale, center, yaw)
    _clock_count = 1


func _build_rear_facade(plane: Vector3, front_mid_t: float, toward_camera: Vector3, tangent: Vector3, yaw: float, visual: Dictionary) -> void:
    var forward_offset := float(visual.get("rear_detail_forward_offset_m", 0.38))
    var base_y := float(visual.get("rear_detail_base_y_m", 4.05))
    var rear_center := plane + tangent * front_mid_t + toward_camera * forward_offset

    var raw_pilaster_offsets: Variant = visual.get("rear_pilaster_offsets_m", [])
    if typeof(raw_pilaster_offsets) != TYPE_ARRAY:
        push_error("Invalid Bourse rear pilaster offsets")
        return
    var pilaster_offsets := raw_pilaster_offsets as Array
    var expected_pilasters := int(visual.get("rear_pilaster_count", 0))
    if expected_pilasters != 4 or pilaster_offsets.size() != expected_pilasters:
        push_error("Bourse rear pilaster count is not source-bounded")
        return
    var pilaster_width := float(visual.get("rear_pilaster_width_m", 0.72))
    var pilaster_height := float(visual.get("rear_pilaster_height_m", 10.9))
    var pilaster_depth := float(visual.get("rear_pilaster_depth_m", 0.30))
    for index: int in range(pilaster_offsets.size()):
        var along := float(pilaster_offsets[index])
        _front_box("RearPilaster_%02d" % index, pilaster_width, pilaster_height, pilaster_depth, rear_center + tangent * along + Vector3(0.0, base_y + pilaster_height * 0.5, 0.0), yaw, _stone_material)
        _pilaster_count += 1

    var central_width := float(visual.get("central_entry_width_m", 5.8))
    var central_height := float(visual.get("central_entry_height_m", 5.8))
    var central_depth := float(visual.get("central_entry_depth_m", 0.20))
    _front_box("RearCentralEntry", central_width, central_height, central_depth, rear_center + Vector3(0.0, base_y + central_height * 0.5, 0.0), yaw, _opening_material)
    _opening_count += 1

    var raw_side_offsets: Variant = visual.get("side_entry_offsets_m", [])
    if typeof(raw_side_offsets) != TYPE_ARRAY:
        push_error("Invalid Bourse side entry offsets")
        return
    var side_offsets := raw_side_offsets as Array
    var expected_side_entries := int(visual.get("side_entry_count", 0))
    if expected_side_entries != 2 or side_offsets.size() != expected_side_entries:
        push_error("Bourse side entry count is invalid")
        return
    var side_width := float(visual.get("side_entry_width_m", 3.1))
    var side_height := float(visual.get("side_entry_height_m", 4.55))
    var side_depth := float(visual.get("side_entry_depth_m", 0.20))
    for index: int in range(side_offsets.size()):
        var along := float(side_offsets[index])
        _front_box("RearSideEntry_%02d" % index, side_width, side_height, side_depth, rear_center + tangent * along + Vector3(0.0, base_y + side_height * 0.5, 0.0), yaw, _opening_material)
        _opening_count += 1

    var raw_oval_offsets: Variant = visual.get("oval_light_offsets_m", [])
    if typeof(raw_oval_offsets) != TYPE_ARRAY:
        push_error("Invalid Bourse oval light offsets")
        return
    var oval_offsets := raw_oval_offsets as Array
    var expected_ovals := int(visual.get("oval_light_count", 0))
    if expected_ovals != 2 or oval_offsets.size() != expected_ovals:
        push_error("Bourse oval light count is invalid")
        return
    var oval_radius_x := float(visual.get("oval_light_radius_x_m", 0.72))
    var oval_radius_y := float(visual.get("oval_light_radius_y_m", 1.02))
    var oval_depth_scale := float(visual.get("oval_light_depth_scale_m", 0.09))
    var oval_y := float(visual.get("oval_light_center_y_m", 9.75))
    for index: int in range(oval_offsets.size()):
        var along := float(oval_offsets[index])
        _round_opening("RearOvalLight_%02d" % index, oval_radius_x, oval_radius_y, oval_depth_scale, rear_center + tangent * along + Vector3(0.0, oval_y, 0.0), yaw)
        _oval_light_count += 1

    var lintel_width := float(visual.get("entry_lintel_width_m", 6.4))
    var lintel_height := float(visual.get("entry_lintel_height_m", 0.34))
    var lintel_y := float(visual.get("entry_lintel_center_y_m", 10.05))
    _front_box("RearCentralEntryLintel", lintel_width, lintel_height, 0.30, rear_center + Vector3(0.0, lintel_y, 0.0), yaw, _stone_material)
    var clock_y := float(visual.get("clock_center_y_m", 12.35))
    _build_clock(rear_center + Vector3(0.0, clock_y, 0.0), yaw, visual)


func _build_candidate() -> void:
    var data := _read_candidate()
    if data.is_empty():
        return
    var envelope: Dictionary = data.get("authoritative_front_envelope", {})
    var visual: Dictionary = data.get("provisional_visualization", {})
    if envelope.is_empty() or visual.is_empty():
        push_error("Bourse portico candidate missing envelope or visualization")
        return

    var plane_xz := _vec2(envelope.get("plane_point_game_x_z", []))
    var forward_xz := _vec2(envelope.get("toward_camera_x_z", []))
    var tangent_xz := _vec2(envelope.get("tangent_x_z", []))
    var toward_camera := Vector3(forward_xz.x, 0.0, forward_xz.y).normalized()
    var tangent := Vector3(tangent_xz.x, 0.0, tangent_xz.y).normalized()
    if toward_camera.length_squared() < 0.99 or tangent.length_squared() < 0.99:
        push_error("Bourse portico basis is invalid")
        return

    var t_min := float(envelope.get("tangent_min_m", 0.0))
    var t_max := float(envelope.get("tangent_max_m", 0.0))
    var span := t_max - t_min
    var count := int(visual.get("column_count", 0))
    var inset_ratio := float(visual.get("column_edge_inset_ratio", 0.10))
    var forward_offset := float(visual.get("column_forward_offset_m", 0.75))
    if count != 6 or span <= 0.0 or inset_ratio < 0.0 or inset_ratio >= 0.4:
        push_error("Bourse portico column layout is invalid")
        return

    var first_t := t_min + span * inset_ratio
    var last_t := t_max - span * inset_ratio
    var spacing := (last_t - first_t) / float(count - 1)
    var plane := Vector3(plane_xz.x, 0.0, plane_xz.y)
    var yaw := atan2(toward_camera.x, toward_camera.z)
    for index: int in range(count):
        var along := first_t + spacing * float(index)
        var center := plane + tangent * along + toward_camera * forward_offset
        _build_column(center, index, visual)

    var front_mid_t := (t_min + t_max) * 0.5
    var front_center := plane + tangent * front_mid_t
    _build_entablature(front_center, toward_camera, yaw, visual)
    _build_source_peristyle_completion(front_center, toward_camera, tangent, span, envelope, visual)
    _build_stair(front_center, toward_camera, yaw, visual)
    _build_rear_facade(plane, front_mid_t, toward_camera, tangent, yaw, visual)

    set_meta("runtime_approved", false)
    set_meta("realism_complete", false)
    set_meta("source_front_span_m", span)
    set_meta("column_count", _column_count)
    set_meta("source_inner_column_count", _inner_column_count)
    set_meta("source_pediment_count", _pediment_count)
    set_meta("source_semantics_completed", _inner_column_count == 2 and _pediment_count == 1)
    set_meta("stair_step_count", _step_count)
    set_meta("rear_pilaster_count", _pilaster_count)
    set_meta("rear_opening_count", _opening_count)
    set_meta("rear_oval_light_count", _oval_light_count)
    set_meta("entablature_count", _entablature_count)
    set_meta("clock_count", _clock_count)
    print(
        "Bourse provisional portico: columns=%d inner_columns=%d pediment=%d steps=%d pilasters=%d openings=%d ovals=%d entablature=%d clock=%d source_front_span=%.3f m runtime_approved=false" %
        [_column_count, _inner_column_count, _pediment_count, _step_count, _pilaster_count, _opening_count, _oval_light_count, _entablature_count, _clock_count, span]
    )


func diagnostic_column_count() -> int:
    return _column_count


func diagnostic_inner_column_count() -> int:
    return _inner_column_count


func diagnostic_pediment_count() -> int:
    return _pediment_count


func diagnostic_step_count() -> int:
    return _step_count


func diagnostic_pilaster_count() -> int:
    return _pilaster_count


func diagnostic_opening_count() -> int:
    return _opening_count


func diagnostic_oval_light_count() -> int:
    return _oval_light_count


func diagnostic_entablature_count() -> int:
    return _entablature_count


func diagnostic_clock_count() -> int:
    return _clock_count

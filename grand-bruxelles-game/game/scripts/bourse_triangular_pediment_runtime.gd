extends Node3D

const CANDIDATE_PATH := "res://data/qa/bourse_triangular_pediment_candidate.json"
const WHITE_STONE := preload("res://game/scripts/brussels_white_stone_material.gd")

var _pediment_count := 0
var _material: Material


func _ready() -> void:
    _build_candidate()


func _fail(message: String) -> void:
    push_error("Bourse triangular pediment: %s" % message)


func _vec2(raw: Variant) -> Vector2:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 2:
        return Vector2.ZERO
    return Vector2(float(raw[0]), float(raw[1]))


func _read_candidate() -> Dictionary:
    if not FileAccess.file_exists(CANDIDATE_PATH):
        _fail("candidate JSON missing")
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CANDIDATE_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("candidate JSON invalid")
        return {}
    var data := parsed as Dictionary
    if str(data.get("schema", "")) != "grand-bruxelles-bourse-triangular-pediment-candidate-v1":
        _fail("candidate schema drifted")
        return {}
    if bool(data.get("runtime_approved", true)) or bool(data.get("realism_complete", true)):
        _fail("provisional candidate must remain unapproved")
        return {}
    return data


func _add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
    surface.add_vertex(a)
    surface.add_vertex(b)
    surface.add_vertex(c)


func _make_pediment_mesh(
    center: Vector3,
    tangent: Vector3,
    toward_camera: Vector3,
    width: float,
    rise: float,
    depth: float,
    base_y: float
) -> ArrayMesh:
    var half_width := width * 0.5
    var half_depth := depth * 0.5
    var front_center := center + toward_camera * half_depth
    var back_center := center - toward_camera * half_depth

    var fl := front_center - tangent * half_width + Vector3(0.0, base_y, 0.0)
    var fr := front_center + tangent * half_width + Vector3(0.0, base_y, 0.0)
    var ft := front_center + Vector3(0.0, base_y + rise, 0.0)
    var bl := back_center - tangent * half_width + Vector3(0.0, base_y, 0.0)
    var br := back_center + tangent * half_width + Vector3(0.0, base_y, 0.0)
    var bt := back_center + Vector3(0.0, base_y + rise, 0.0)

    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)

    _add_triangle(surface, fl, ft, fr)
    _add_triangle(surface, br, bt, bl)

    _add_triangle(surface, fl, fr, br)
    _add_triangle(surface, fl, br, bl)

    _add_triangle(surface, fl, bl, bt)
    _add_triangle(surface, fl, bt, ft)

    _add_triangle(surface, ft, bt, br)
    _add_triangle(surface, ft, br, fr)

    surface.generate_normals()
    return surface.commit()


func _build_candidate() -> void:
    var data := _read_candidate()
    if data.is_empty():
        return

    var source_contract: Dictionary = data.get("source_contract", {})
    var heritage_fact := str(source_contract.get("heritage_fact", ""))
    if not heritage_fact.contains("triangular pediment"):
        _fail("source contract does not prove triangular pediment identity")
        return

    var envelope: Dictionary = data.get("authoritative_front_envelope", {})
    var visual: Dictionary = data.get("provisional_visualization", {})
    if envelope.is_empty() or visual.is_empty():
        _fail("candidate missing envelope or visualization")
        return

    var plane_xz := _vec2(envelope.get("plane_point_game_x_z", []))
    var forward_xz := _vec2(envelope.get("toward_camera_x_z", []))
    var tangent_xz := _vec2(envelope.get("tangent_x_z", []))
    var toward_camera := Vector3(forward_xz.x, 0.0, forward_xz.y).normalized()
    var tangent := Vector3(tangent_xz.x, 0.0, tangent_xz.y).normalized()
    if toward_camera.length_squared() < 0.99 or tangent.length_squared() < 0.99:
        _fail("front basis invalid")
        return

    var t_min := float(envelope.get("tangent_min_m", 0.0))
    var t_max := float(envelope.get("tangent_max_m", 0.0))
    var span := t_max - t_min
    var y_max := float(envelope.get("y_max_m", 0.0))
    var width := float(visual.get("pediment_width_m", 0.0))
    var rise := float(visual.get("pediment_rise_m", 0.0))
    var depth := float(visual.get("pediment_depth_m", 0.0))
    var base_y := float(visual.get("pediment_base_y_m", 0.0))
    var forward_offset := float(visual.get("pediment_forward_offset_m", 0.0))

    if width <= 0.0 or width >= span:
        _fail("pediment width escapes authoritative front span")
        return
    if rise <= 0.0 or depth <= 0.0 or base_y <= 0.0:
        _fail("pediment dimensions invalid")
        return
    if base_y + rise >= y_max:
        _fail("pediment exceeds authoritative vertical envelope")
        return

    var plane := Vector3(plane_xz.x, 0.0, plane_xz.y)
    var mid_t := (t_min + t_max) * 0.5
    var center := plane + tangent * mid_t + toward_camera * forward_offset

    _material = WHITE_STONE.create(
        Color(0.72, 0.70, 0.65, 1.0),
        Color(0.84, 0.81, 0.74, 1.0),
        0.84,
        "Bourse triangular pediment heritage identity; exact geometry provisional"
    )

    var mesh_instance := MeshInstance3D.new()
    mesh_instance.name = "BourseTriangularPediment"
    mesh_instance.mesh = _make_pediment_mesh(center, tangent, toward_camera, width, rise, depth, base_y)
    mesh_instance.material_override = _material
    add_child(mesh_instance)
    _pediment_count = 1

    set_meta("runtime_approved", false)
    set_meta("realism_complete", false)
    set_meta("source_identity", "triangular_pediment")
    set_meta("pediment_width_m", width)
    set_meta("pediment_rise_m", rise)
    set_meta("pediment_top_y_m", base_y + rise)
    set_meta("source_front_span_m", span)
    set_meta("authoritative_y_max_m", y_max)
    print(
        "Bourse triangular pediment candidate: width=%.3f rise=%.3f top_y=%.3f span=%.3f runtime_approved=false" %
        [width, rise, base_y + rise, span]
    )


func diagnostic_pediment_count() -> int:
    return _pediment_count

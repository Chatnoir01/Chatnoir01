extends Node

@export var hero_builder_path: NodePath = NodePath("../UrbISHeroGeometry")
@export_file("*.json") var candidate_path: String = "res://data/qa/bourse_portico_articulation_candidate.json"
@export var front_plane_tolerance_m: float = 1.0
@export var tangent_margin_m: float = 0.75

var _removed_triangles := 0
var _kept_triangles := 0

func _ready() -> void:
    call_deferred("_apply_reveal")

func _vec2(raw: Variant) -> Vector2:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 2:
        return Vector2.ZERO
    return Vector2(float(raw[0]), float(raw[1]))

func _is_front_triangle(a: Vector3, b: Vector3, c: Vector3, plane: Vector2, normal: Vector2, tangent: Vector2, t_min: float, t_max: float) -> bool:
    var points := [Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)]
    var max_plane_distance := 0.0
    for point: Vector2 in points:
        max_plane_distance = maxf(max_plane_distance, absf((point - plane).dot(normal)))
    if max_plane_distance > front_plane_tolerance_m:
        return false
    var centroid := (points[0] + points[1] + points[2]) / 3.0
    var along := (centroid - plane).dot(tangent)
    return along >= t_min - tangent_margin_m and along <= t_max + tangent_margin_m

func _apply_reveal() -> void:
    if not FileAccess.file_exists(candidate_path):
        push_error("Bourse front reveal: candidate evidence missing")
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(candidate_path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Bourse front reveal: invalid candidate evidence")
        return
    var data := parsed as Dictionary
    if bool(data.get("runtime_approved", true)) or bool(data.get("realism_complete", true)):
        push_error("Bourse front reveal: provisional evidence must remain unapproved")
        return
    var envelope: Dictionary = data.get("authoritative_front_envelope", {})
    var plane := _vec2(envelope.get("plane_point_game_x_z", []))
    var normal := _vec2(envelope.get("toward_camera_x_z", [])).normalized()
    var tangent := _vec2(envelope.get("tangent_x_z", [])).normalized()
    var t_min := float(envelope.get("tangent_min_m", 0.0))
    var t_max := float(envelope.get("tangent_max_m", 0.0))
    if normal.length_squared() < 0.99 or tangent.length_squared() < 0.99 or t_max <= t_min:
        push_error("Bourse front reveal: invalid authoritative front envelope")
        return

    var builder := get_node_or_null(hero_builder_path)
    if builder == null:
        push_error("Bourse front reveal: hero builder missing")
        return
    var hero := builder.get_node_or_null("Hero_Bourse")
    if hero == null:
        push_error("Bourse front reveal: Hero_Bourse missing")
        return
    var walls := hero.get_node_or_null("Walls") as MeshInstance3D
    if walls == null or walls.mesh == null or walls.mesh.get_surface_count() == 0:
        push_error("Bourse front reveal: wall mesh missing")
        return

    var arrays := walls.mesh.surface_get_arrays(0)
    var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    if vertices.size() < 3 or vertices.size() % 3 != 0:
        push_error("Bourse front reveal: non-triangle wall mesh")
        return

    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    var material := walls.mesh.surface_get_material(0)
    if material != null:
        tool.set_material(material)

    _removed_triangles = 0
    _kept_triangles = 0
    for index: int in range(0, vertices.size(), 3):
        var a := vertices[index]
        var b := vertices[index + 1]
        var c := vertices[index + 2]
        if _is_front_triangle(a, b, c, plane, normal, tangent, t_min, t_max):
            _removed_triangles += 1
            continue
        var face_normal := (b - a).cross(c - a).normalized()
        if not face_normal.is_finite() or face_normal.length_squared() < 0.5:
            continue
        for vertex: Vector3 in [a, b, c]:
            tool.set_normal(face_normal)
            tool.add_vertex(vertex)
        _kept_triangles += 1

    var revealed := tool.commit()
    if revealed == null or revealed.get_surface_count() == 0:
        push_error("Bourse front reveal: filtered wall mesh is empty")
        return
    if _removed_triangles <= 0 or _kept_triangles <= _removed_triangles:
        push_error("Bourse front reveal: unsafe front-plane selection removed=%d kept=%d" % [_removed_triangles, _kept_triangles])
        return
    walls.mesh = revealed
    walls.set_meta("bourse_front_reveal_source_bounded", true)
    walls.set_meta("bourse_front_reveal_removed_triangles", _removed_triangles)
    walls.set_meta("bourse_front_reveal_kept_triangles", _kept_triangles)
    set_meta("runtime_approved", false)
    set_meta("realism_complete", false)
    print("Bourse front wall reveal: removed=%d kept=%d runtime_approved=false" % [_removed_triangles, _kept_triangles])

func diagnostic_removed_triangles() -> int:
    return _removed_triangles

func diagnostic_kept_triangles() -> int:
    return _kept_triangles

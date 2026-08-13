extends Node

@export var hero_builder_path: NodePath = NodePath("../UrbISHeroGeometry")

var _flipped_count := 0
var _triangle_count := 0

func _ready() -> void:
    call_deferred("_repair_bourse_walls")

func _repair_bourse_walls() -> void:
    var builder := get_node_or_null(hero_builder_path)
    if builder == null:
        push_error("Bourse normal repair: hero builder missing")
        return
    var hero := builder.get_node_or_null("Hero_Bourse")
    if hero == null:
        push_error("Bourse normal repair: Hero_Bourse missing")
        return
    var walls := hero.get_node_or_null("Walls") as MeshInstance3D
    if walls == null or walls.mesh == null or walls.mesh.get_surface_count() == 0:
        push_error("Bourse normal repair: wall mesh missing")
        return

    var source_arrays := walls.mesh.surface_get_arrays(0)
    var vertices: PackedVector3Array = source_arrays[Mesh.ARRAY_VERTEX]
    if vertices.size() < 3 or vertices.size() % 3 != 0:
        push_error("Bourse normal repair: non-triangle wall mesh")
        return

    var center := Vector3.ZERO
    for vertex in vertices:
        center += vertex
    center /= float(vertices.size())

    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    var material := walls.mesh.surface_get_material(0)
    if material != null:
        tool.set_material(material)

    _triangle_count = 0
    _flipped_count = 0
    for index in range(0, vertices.size(), 3):
        var a := vertices[index]
        var b := vertices[index + 1]
        var c := vertices[index + 2]
        var normal := (b - a).cross(c - a).normalized()
        if not normal.is_finite() or normal.length_squared() < 0.5:
            continue
        var centroid := (a + b + c) / 3.0
        var outward := centroid - center
        outward.y = 0.0
        var horizontal_normal := Vector3(normal.x, 0.0, normal.z)
        if outward.length_squared() > 0.0001 and horizontal_normal.length_squared() > 0.0001 and horizontal_normal.dot(outward) < 0.0:
            normal = -normal
            _flipped_count += 1
        for vertex in [a, b, c]:
            tool.set_normal(normal)
            tool.add_vertex(vertex)
        _triangle_count += 1

    var repaired := tool.commit()
    if repaired == null or repaired.get_surface_count() == 0:
        push_error("Bourse normal repair: repaired mesh empty")
        return
    walls.mesh = repaired
    walls.set_meta("normal_repair_source_preserving", true)
    walls.set_meta("normal_repair_flipped_count", _flipped_count)
    walls.set_meta("normal_repair_triangle_count", _triangle_count)
    set_meta("runtime_approved", false)
    set_meta("realism_complete", false)
    print("Bourse hero normal repair: triangles=%d flipped=%d runtime_approved=false" % [_triangle_count, _flipped_count])

func diagnostic_flipped_count() -> int:
    return _flipped_count

func diagnostic_triangle_count() -> int:
    return _triangle_count

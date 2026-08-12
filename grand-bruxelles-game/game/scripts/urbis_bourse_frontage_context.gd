extends Node3D

@export_file("*.json") var manifest_path: String = "res://data/urbis/bourse_frontage/manifest.json"

var _wall_material: StandardMaterial3D
var _roof_material: StandardMaterial3D
var _context_count: int = 0
var _source_face_count: int = 0
var _source_triangle_count: int = 0
var _render_triangle_count: int = 0


func _ready() -> void:
    _make_materials()
    _build_manifest()


func _material(color: Color, roughness: float) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    return material


func _make_materials() -> void:
    _wall_material = _material(Color(0.50, 0.455, 0.37, 1.0), 0.91)
    _roof_material = _material(Color(0.17, 0.18, 0.19, 1.0), 0.92)


func _read_dictionary(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        push_error("Bourse frontage data missing: %s" % path)
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Invalid Bourse frontage JSON: %s" % path)
        return {}
    return parsed


func _point(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return Vector3.INF
    return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))


func _append_face_type(tool: SurfaceTool, faces: Array, face_type: String) -> int:
    var triangle_count := 0
    for raw_face: Variant in faces:
        if typeof(raw_face) != TYPE_DICTIONARY:
            continue
        var face: Dictionary = raw_face
        if str(face.get("type", "")) != face_type:
            continue
        for raw_triangle: Variant in face.get("triangles", []):
            if typeof(raw_triangle) != TYPE_ARRAY or raw_triangle.size() != 3:
                continue
            var a := _point(raw_triangle[0])
            var b := _point(raw_triangle[1])
            var c := _point(raw_triangle[2])
            if not a.is_finite() or not b.is_finite() or not c.is_finite():
                continue
            var normal := (b - a).cross(c - a).normalized()
            if not normal.is_finite() or normal.length_squared() < 0.5:
                continue
            for vertex: Vector3 in [a, b, c]:
                tool.set_normal(normal)
                tool.add_vertex(vertex)
            triangle_count += 1
    return triangle_count


func _commit(tool: SurfaceTool, name: String, root: Node3D) -> void:
    var mesh := tool.commit()
    if mesh == null or mesh.get_surface_count() == 0:
        return
    var instance := MeshInstance3D.new()
    instance.name = name
    instance.mesh = mesh
    root.add_child(instance)


func _build_context(entry: Dictionary) -> bool:
    var path := str(entry.get("geometry_path", ""))
    var data := _read_dictionary(path)
    if data.is_empty():
        return false
    if str(data.get("schema", "")) != "grand-bruxelles-urbis-context-mesh-v1":
        push_error("Unsupported Bourse frontage schema: %s" % path)
        return false
    var source: Dictionary = data.get("source", {})
    if str(source.get("building_2d_id", "")) != str(entry.get("building_id", "")):
        push_error("Bourse frontage building ID mismatch: %s" % path)
        return false
    if bool(data.get("runtime_approved", true)):
        push_error("Bourse frontage source unexpectedly runtime-approved: %s" % path)
        return false

    var evidence: Dictionary = data.get("evidence", {})
    if int(evidence.get("face_count", -1)) != int(entry.get("expected_faces", -2)):
        push_error("Bourse frontage face count mismatch: %s" % path)
        return false
    if int(evidence.get("triangle_count", -1)) != int(entry.get("expected_triangles", -2)):
        push_error("Bourse frontage triangle count mismatch: %s" % path)
        return false

    var root := Node3D.new()
    root.name = "Frontage_%s" % str(entry.get("building_id", "unknown")).get_slice("/", -1)
    add_child(root)
    var faces: Array = data.get("faces", [])
    var rendered := 0
    for definition: Array in [
        ["WALLSURFACE", _wall_material, "Walls"],
        ["ROOFSURFACE", _roof_material, "Roofs"],
    ]:
        var tool := SurfaceTool.new()
        tool.begin(Mesh.PRIMITIVE_TRIANGLES)
        tool.set_material(definition[1])
        rendered += _append_face_type(tool, faces, definition[0])
        _commit(tool, definition[2], root)

    if rendered != int(entry.get("render_triangles", -1)):
        push_error("Bourse frontage render triangle mismatch: %s" % path)
        root.queue_free()
        return false

    root.set_meta("building_id", str(entry.get("building_id", "")))
    root.set_meta("runtime_approved", false)
    root.set_meta("render_triangles", rendered)
    _context_count += 1
    _source_face_count += int(evidence.get("face_count", 0))
    _source_triangle_count += int(evidence.get("triangle_count", 0))
    _render_triangle_count += rendered
    return true


func _build_manifest() -> void:
    var manifest := _read_dictionary(manifest_path)
    if manifest.is_empty():
        return
    if str(manifest.get("schema", "")) != "grand-bruxelles-bourse-frontage-runtime-v1":
        push_error("Unsupported Bourse frontage manifest: %s" % manifest_path)
        return
    if bool(manifest.get("runtime_approved", true)) or bool(manifest.get("realism_complete", true)):
        push_error("Bourse frontage manifest approval gates must remain false")
        return
    for raw_entry: Variant in manifest.get("contexts", []):
        if typeof(raw_entry) == TYPE_DICTIONARY:
            _build_context(raw_entry)
    print(
        "Bourse official frontage candidate: %d buildings, %d source faces, %d/%d rendered/source triangles" %
        [_context_count, _source_face_count, _render_triangle_count, _source_triangle_count]
    )


func context_count() -> int:
    return _context_count


func source_face_count() -> int:
    return _source_face_count


func source_triangle_count() -> int:
    return _source_triangle_count


func render_triangle_count() -> int:
    return _render_triangle_count

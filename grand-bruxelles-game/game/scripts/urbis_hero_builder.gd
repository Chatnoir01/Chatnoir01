extends Node3D

@export_file("*.json") var manifest_path: String = "res://data/urbis/heroes/manifest.json"
@export var build_collisions: bool = true

var _wall_material: StandardMaterial3D
var _roof_material: StandardMaterial3D
var _ground_material: StandardMaterial3D
var _other_material: StandardMaterial3D


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
    _wall_material = _material(Color(0.69, 0.655, 0.555, 1.0), 0.88)
    _roof_material = _material(Color(0.18, 0.19, 0.205, 1.0), 0.91)
    _ground_material = _material(Color(0.31, 0.30, 0.275, 1.0), 0.94)
    _other_material = _material(Color(0.46, 0.44, 0.39, 1.0), 0.90)


func _read_dictionary(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        push_error("UrbIS hero data missing: %s" % path)
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Invalid UrbIS hero JSON: %s" % path)
        return {}
    return parsed


func _tool(material: Material) -> SurfaceTool:
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_material(material)
    return tool


func _point(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return Vector3.INF
    return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))


func _append_triangles(tool: SurfaceTool, faces: Array, face_type: String) -> int:
    var count := 0
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
            count += 1
    return count


func _commit_surface(tool: SurfaceTool, name: String, root: Node3D) -> MeshInstance3D:
    var mesh := tool.commit()
    if mesh.get_surface_count() == 0:
        return null
    var instance := MeshInstance3D.new()
    instance.name = name
    instance.mesh = mesh
    root.add_child(instance)
    return instance


func _build_hero(entry: Dictionary) -> bool:
    var path := str(entry.get("geometry_path", ""))
    var data := _read_dictionary(path)
    if data.is_empty():
        return false
    if str(data.get("schema", "")) != "grand-bruxelles-urbis-hero-mesh-v1":
        push_error("Unsupported UrbIS hero schema: %s" % path)
        return false
    if str(data.get("hero_id", "")) != str(entry.get("id", "")):
        push_error("UrbIS hero ID mismatch: %s" % path)
        return false

    var hero_root := Node3D.new()
    hero_root.name = "Hero_%s" % str(entry.get("id", "unknown")).capitalize()
    add_child(hero_root)
    var faces: Array = data.get("faces", [])
    var triangle_count := 0
    var surfaces: Array[MeshInstance3D] = []
    for definition: Array in [
        ["WALLSURFACE", _wall_material, "Walls"],
        ["ROOFSURFACE", _roof_material, "Roofs"],
        ["GROUNDSURFACE", _ground_material, "Ground"],
    ]:
        var tool := _tool(definition[1])
        triangle_count += _append_triangles(tool, faces, definition[0])
        var instance := _commit_surface(tool, definition[2], hero_root)
        if instance != null:
            surfaces.append(instance)

    if triangle_count <= 0:
        push_error("UrbIS hero contains no valid triangles: %s" % path)
        hero_root.queue_free()
        return false
    if build_collisions:
        for surface: MeshInstance3D in surfaces:
            if surface.name == "Walls" or surface.name == "Roofs":
                surface.create_trimesh_collision()
    hero_root.set_meta("source_runtime_approved", bool(data.get("runtime_approved", false)))
    hero_root.set_meta("triangle_count", triangle_count)
    hero_root.set_meta("geometry_path", path)
    print(
        "Grand Bruxelles UrbIS hero: %s, %d faces, %d triangles, runtime_approved=%s" %
        [str(entry.get("id", "unknown")), faces.size(), triangle_count, str(data.get("runtime_approved", false))]
    )
    return true


func _build_manifest() -> void:
    var manifest := _read_dictionary(manifest_path)
    if manifest.is_empty():
        return
    if str(manifest.get("schema", "")) != "grand-bruxelles-urbis-hero-manifest-v1":
        push_error("Unsupported UrbIS hero manifest: %s" % manifest_path)
        return
    for raw_entry: Variant in manifest.get("heroes", []):
        if typeof(raw_entry) == TYPE_DICTIONARY:
            _build_hero(raw_entry)

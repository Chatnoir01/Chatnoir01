extends Node3D

@export_file("*.json") var source_path := "res://data/sources/laeken_jette/atomium_pavilion_lod2.game.json"

var pavilion_built := false
var triangle_count := 0
var source_height_m := 0.0
var source_building_id := ""
var source_license := ""

func build_on_terrain(terrain: Node) -> bool:
    if pavilion_built:
        return true
    if terrain == null or not terrain.has_method("sample_height") or not bool(terrain.get("terrain_loaded")):
        push_error("AtomiumPavilionLoD2: official terrain unavailable")
        return false
    if not FileAccess.file_exists(source_path):
        push_error("AtomiumPavilionLoD2: source geometry missing")
        return false
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(source_path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("AtomiumPavilionLoD2: invalid source payload")
        return false
    var data := parsed as Dictionary
    var source: Dictionary = data.get("source", {})
    var evidence: Dictionary = data.get("evidence", {})
    if str(source.get("crs", "")) != "EPSG:31370" or str(source.get("license", "")) != "CC0-1.0":
        push_error("AtomiumPavilionLoD2: provenance contract drifted")
        return false
    if bool(data.get("runtime_approved", true)):
        push_error("AtomiumPavilionLoD2: source evidence was incorrectly promoted")
        return false
    source_building_id = str(source.get("building_2d_id", ""))
    source_license = str(source.get("license", ""))
    source_height_m = float(evidence.get("height_m", 0.0))
    if source_building_id != "https://databrussels.be/id/building/1651628" or absf(source_height_m - 6.674) > 0.001:
        push_error("AtomiumPavilionLoD2: exact source identity/height drifted")
        return false
    var anchor: Vector3 = terrain.get("atomium_game_position")
    position = Vector3(anchor.x, float(terrain.call("sample_height", anchor.x, anchor.z)), anchor.z)
    var faces: Variant = data.get("faces", [])
    if not faces is Array:
        push_error("AtomiumPavilionLoD2: faces missing")
        return false
    var wall_vertices := PackedVector3Array()
    var roof_vertices := PackedVector3Array()
    for raw_face: Variant in faces:
        if not raw_face is Dictionary:
            continue
        var face := raw_face as Dictionary
        var face_type := str(face.get("type", ""))
        if face_type != "WALLSURFACE" and face_type != "ROOFSURFACE":
            continue
        var target := wall_vertices if face_type == "WALLSURFACE" else roof_vertices
        var triangles: Variant = face.get("triangles", [])
        if not triangles is Array:
            continue
        for raw_triangle: Variant in triangles:
            if not raw_triangle is Array or raw_triangle.size() != 3:
                continue
            for raw_point: Variant in raw_triangle:
                if not raw_point is Array or raw_point.size() != 3:
                    continue
                target.append(Vector3(float(raw_point[0]), float(raw_point[1]), float(raw_point[2])))
            triangle_count += 1
    if wall_vertices.size() == 0 or roof_vertices.size() == 0 or triangle_count != 48:
        push_error("AtomiumPavilionLoD2: source surface topology drifted")
        return false
    _add_surface("PavilionWalls", wall_vertices, _wall_material())
    _add_surface("PavilionRoof", roof_vertices, _roof_material())
    pavilion_built = true
    print("ATOMIUM_PAVILION_LOD2_READY: building=1651628 triangles=%d height=%.3f license=%s" % [triangle_count, source_height_m, source_license])
    return true

func _add_surface(node_name: String, vertices: PackedVector3Array, material: Material) -> void:
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    mesh.surface_set_material(0, material)
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    add_child(instance)

func _wall_material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.60, 0.68, 0.72, 0.58)
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.metallic = 0.08
    material.roughness = 0.22
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    return material

func _roof_material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.34, 0.37, 0.39, 1.0)
    material.metallic = 0.18
    material.roughness = 0.48
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    return material

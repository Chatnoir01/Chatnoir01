extends Node3D

const GEOMETRY_SOURCES := [
    {
        "path": "res://data/urbis/bourse_geotagged_context/1598452.game.json",
        "building_id": "https://databrussels.be/id/building/1598452",
    },
    {
        "path": "res://data/urbis/bourse_geotagged_context/1645621.game.json",
        "building_id": "https://databrussels.be/id/building/1645621",
    },
]

var _wall_material: StandardMaterial3D
var _roof_material: StandardMaterial3D
var _render_triangle_count := 0
var _masked_osm_count := 0
var _bounds := Rect2()
var _building_ids: Array[String] = []


func _ready() -> void:
    _make_materials()
    var combined_initialized := false
    var combined_min := Vector2.ZERO
    var combined_max := Vector2.ZERO
    for source_def: Dictionary in GEOMETRY_SOURCES:
        var path := str(source_def.get("path", ""))
        var expected_id := str(source_def.get("building_id", ""))
        var data := _read_geometry(path, expected_id)
        if data.is_empty():
            continue
        var bounds := _horizontal_bounds(data.get("faces", []))
        if bounds.size.length_squared() > 0.001:
            if not combined_initialized:
                combined_min = bounds.position
                combined_max = bounds.end
                combined_initialized = true
            else:
                combined_min.x = minf(combined_min.x, bounds.position.x)
                combined_min.y = minf(combined_min.y, bounds.position.y)
                combined_max.x = maxf(combined_max.x, bounds.end.x)
                combined_max.y = maxf(combined_max.y, bounds.end.y)
        _mask_replaced_osm(bounds, expected_id)
        _build_geometry(data, expected_id)
    _bounds = Rect2(combined_min, combined_max - combined_min) if combined_initialized else Rect2()
    set_meta("building_ids", _building_ids.duplicate())
    set_meta("runtime_approved", false)
    set_meta("realism_complete", false)
    print("Bourse geotagged frontages %s: %d rendered triangles, %d OSM replacements" % [str(_building_ids), _render_triangle_count, _masked_osm_count])


func _make_materials() -> void:
    _wall_material = StandardMaterial3D.new()
    _wall_material.albedo_color = Color(0.48, 0.43, 0.35, 1.0)
    _wall_material.roughness = 0.92
    _wall_material.cull_mode = BaseMaterial3D.CULL_DISABLED
    _roof_material = StandardMaterial3D.new()
    _roof_material.albedo_color = Color(0.17, 0.18, 0.19, 1.0)
    _roof_material.roughness = 0.92
    _roof_material.cull_mode = BaseMaterial3D.CULL_DISABLED


func _read_geometry(path: String, expected_id: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        push_error("Bourse geotagged frontage geometry missing: %s" % path)
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Invalid Bourse geotagged frontage JSON: %s" % path)
        return {}
    var data: Dictionary = parsed
    if str(data.get("schema", "")) != "grand-bruxelles-urbis-context-mesh-v1":
        push_error("Unsupported Bourse geotagged frontage schema: %s" % path)
        return {}
    var source: Dictionary = data.get("source", {})
    if str(source.get("building_2d_id", "")) != expected_id:
        push_error("Unexpected Bourse geotagged frontage building: %s" % path)
        return {}
    if str(source.get("provider", "")) != "Paradigm / Brussels-Capital Region":
        push_error("Unexpected Bourse geotagged frontage provider: %s" % path)
        return {}
    if str(source.get("crs", "")) != "EPSG:31370" or str(source.get("license", "")) != "CC0-1.0":
        push_error("Bourse frontage source provenance drifted: %s" % path)
        return {}
    if bool(data.get("runtime_approved", true)):
        push_error("Source evidence must remain non-approved: %s" % path)
        return {}
    return data


func _point(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return Vector3.INF
    return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))


func _horizontal_bounds(faces: Array) -> Rect2:
    var initialized := false
    var min_point := Vector2.ZERO
    var max_point := Vector2.ZERO
    for raw_face: Variant in faces:
        if typeof(raw_face) != TYPE_DICTIONARY:
            continue
        for raw_triangle: Variant in raw_face.get("triangles", []):
            if typeof(raw_triangle) != TYPE_ARRAY:
                continue
            for raw_point: Variant in raw_triangle:
                var point := _point(raw_point)
                if not point.is_finite():
                    continue
                var flat := Vector2(point.x, point.z)
                if not initialized:
                    min_point = flat
                    max_point = flat
                    initialized = true
                else:
                    min_point.x = minf(min_point.x, flat.x)
                    min_point.y = minf(min_point.y, flat.y)
                    max_point.x = maxf(max_point.x, flat.x)
                    max_point.y = maxf(max_point.y, flat.y)
    return Rect2(min_point, max_point - min_point) if initialized else Rect2()


func _mask_replaced_osm(bounds: Rect2, building_id: String) -> void:
    var buildings := get_node_or_null("../BrusselsOSM/GeneratedBuildings")
    if buildings == null or bounds.size.length_squared() <= 0.001:
        return
    var expanded := bounds.grow(2.0)
    for child: Node in buildings.get_children():
        if not child is Node3D:
            continue
        var node := child as Node3D
        var center := Vector2(node.position.x, node.position.z)
        if not expanded.has_point(center):
            continue
        if node.has_meta("replaced_by_urbis_building"):
            continue
        node.visible = false
        if node is CSGShape3D:
            (node as CSGShape3D).use_collision = false
        node.set_meta("replaced_by_urbis_building", building_id.get_slice("/", -1))
        _masked_osm_count += 1


func _append_type(tool: SurfaceTool, faces: Array, face_type: String) -> int:
    var count := 0
    for raw_face: Variant in faces:
        if typeof(raw_face) != TYPE_DICTIONARY or str(raw_face.get("type", "")) != face_type:
            continue
        for raw_triangle: Variant in raw_face.get("triangles", []):
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


func _build_surface(faces: Array, face_type: String, material: Material, node_name: String) -> int:
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_material(material)
    var count := _append_type(tool, faces, face_type)
    var mesh := tool.commit()
    if mesh != null and mesh.get_surface_count() > 0:
        var instance := MeshInstance3D.new()
        instance.name = node_name
        instance.mesh = mesh
        add_child(instance)
    return count


func _build_geometry(data: Dictionary, building_id: String) -> void:
    var faces: Array = data.get("faces", [])
    var short_id := building_id.get_slice("/", -1)
    _render_triangle_count += _build_surface(faces, "WALLSURFACE", _wall_material, "Walls_%s" % short_id)
    _render_triangle_count += _build_surface(faces, "ROOFSURFACE", _roof_material, "Roofs_%s" % short_id)
    _building_ids.append(building_id)


func render_triangle_count() -> int:
    return _render_triangle_count


func masked_osm_count() -> int:
    return _masked_osm_count


func source_bounds() -> Rect2:
    return _bounds


func building_ids() -> Array[String]:
    return _building_ids.duplicate()

extends Node

const HERO_PATH := "res://data/urbis/heroes/bourse_lod2.game.json"
const HERO_ID := "bourse"
const EXPECTED_BUILDING_ID := "https://databrussels.be/id/building/1751663"
const EXPECTED_PACKAGE_SHA256 := "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2"

@export var enabled: bool = true

var _applied := false
var _source_face_count := 0
var _source_triangle_count := 0
var _smoothed_vertex_occurrences := 0
var _flipped_triangle_count := 0


func _ready() -> void:
    if enabled:
        call_deferred("_apply_current_scene_when_ready")


func _apply_current_scene_when_ready() -> void:
    for _frame: int in range(12):
        await get_tree().process_frame
        var scene := get_tree().current_scene
        if scene == null:
            continue
        var roofs := scene.get_node_or_null("UrbISHeroGeometry/Hero_Bourse/Roofs") as MeshInstance3D
        if roofs == null:
            continue
        if not bool(roofs.get_meta("bourse_roof_winding_upward", false)):
            continue
        apply_to_scene(scene)
        return


func _read_source() -> Dictionary:
    if not FileAccess.file_exists(HERO_PATH):
        push_error("Bourse roof smoothing: source hero geometry missing")
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(HERO_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Bourse roof smoothing: source hero JSON invalid")
        return {}
    var data := parsed as Dictionary
    if str(data.get("schema", "")) != "grand-bruxelles-urbis-hero-mesh-v1":
        push_error("Bourse roof smoothing: unsupported hero schema")
        return {}
    if str(data.get("hero_id", "")) != HERO_ID:
        push_error("Bourse roof smoothing: unexpected hero id")
        return {}
    var source: Dictionary = data.get("source", {})
    if str(source.get("building_2d_id", "")) != EXPECTED_BUILDING_ID:
        push_error("Bourse roof smoothing: unexpected building id")
        return {}
    if str(source.get("package_sha256", "")) != EXPECTED_PACKAGE_SHA256:
        push_error("Bourse roof smoothing: source package lock drifted")
        return {}
    return data


func _point(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return Vector3.INF
    return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))


func _vertex_key(point: Vector3) -> String:
    return "%.4f|%.4f|%.4f" % [point.x, point.y, point.z]


func _face_triangles(raw_face: Dictionary) -> Array:
    var triangles: Array = []
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
        if normal.y < 0.0:
            var swap := b
            b = c
            c = swap
            normal = -normal
            _flipped_triangle_count += 1
        triangles.append({"vertices": [a, b, c], "normal": normal})
    return triangles


func _append_smoothed_source_face(tool: SurfaceTool, raw_face: Dictionary) -> int:
    var triangles := _face_triangles(raw_face)
    if triangles.is_empty():
        return 0

    var normal_sums: Dictionary = {}
    for triangle: Dictionary in triangles:
        var face_normal: Vector3 = triangle["normal"]
        for vertex: Vector3 in triangle["vertices"]:
            var key := _vertex_key(vertex)
            normal_sums[key] = normal_sums.get(key, Vector3.ZERO) + face_normal

    for triangle: Dictionary in triangles:
        var face_normal: Vector3 = triangle["normal"]
        for vertex: Vector3 in triangle["vertices"]:
            var average: Vector3 = normal_sums.get(_vertex_key(vertex), face_normal)
            if not average.is_finite() or average.length_squared() < 0.0001:
                average = face_normal
            else:
                average = average.normalized()
            if average.dot(face_normal) < 0.99999:
                _smoothed_vertex_occurrences += 1
            tool.set_normal(average)
            tool.add_vertex(vertex)
    return triangles.size()


func apply_to_scene(scene: Node) -> bool:
    if not enabled:
        return false
    var roofs := scene.get_node_or_null("UrbISHeroGeometry/Hero_Bourse/Roofs") as MeshInstance3D
    if roofs == null or roofs.mesh == null or roofs.mesh.get_surface_count() == 0:
        push_error("Bourse roof smoothing: runtime roof mesh missing")
        return false
    if not bool(roofs.get_meta("bourse_roof_winding_upward", false)):
        push_error("Bourse roof smoothing: #241 upward winding must run first")
        return false

    var data := _read_source()
    if data.is_empty():
        return false

    var source_material := roofs.mesh.surface_get_material(0)
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    if source_material != null:
        tool.set_material(source_material)

    _source_face_count = 0
    _source_triangle_count = 0
    _smoothed_vertex_occurrences = 0
    _flipped_triangle_count = 0
    for raw_face: Variant in data.get("faces", []):
        if typeof(raw_face) != TYPE_DICTIONARY:
            continue
        var face := raw_face as Dictionary
        if str(face.get("type", "")) != "ROOFSURFACE":
            continue
        _source_face_count += 1
        _source_triangle_count += _append_smoothed_source_face(tool, face)

    if _source_face_count <= 0 or _source_triangle_count <= 0:
        push_error("Bourse roof smoothing: source contains no roof geometry")
        return false
    if _smoothed_vertex_occurrences <= 0:
        push_error("Bourse roof smoothing: source-face normals produced no smoothing candidates")
        return false

    var smoothed := tool.commit()
    if smoothed == null or smoothed.get_surface_count() == 0:
        push_error("Bourse roof smoothing: rebuilt roof mesh is empty")
        return false
    var output_vertices := smoothed.surface_get_array_len(0)
    if output_vertices != _source_triangle_count * 3:
        push_error("Bourse roof smoothing: source triangle preservation drifted")
        return false

    roofs.mesh = smoothed
    roofs.set_meta("bourse_roof_source_face_smoothing", true)
    roofs.set_meta("bourse_roof_source_face_count", _source_face_count)
    roofs.set_meta("bourse_roof_source_triangle_count", _source_triangle_count)
    roofs.set_meta("bourse_roof_smoothed_vertex_occurrences", _smoothed_vertex_occurrences)
    roofs.set_meta("bourse_roof_smoothing_geometry_unchanged", true)
    _applied = true
    print(
        "BOURSE_ROOF_SOURCE_FACE_SMOOTHING_OK faces=%d triangles=%d smoothed_vertex_occurrences=%d flipped=%d" %
        [_source_face_count, _source_triangle_count, _smoothed_vertex_occurrences, _flipped_triangle_count]
    )
    return true


func diagnostic_applied() -> bool:
    return _applied


func diagnostic_source_face_count() -> int:
    return _source_face_count


func diagnostic_source_triangle_count() -> int:
    return _source_triangle_count


func diagnostic_smoothed_vertex_occurrences() -> int:
    return _smoothed_vertex_occurrences

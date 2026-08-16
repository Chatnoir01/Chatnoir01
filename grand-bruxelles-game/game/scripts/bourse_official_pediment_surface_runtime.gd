extends Node

const MATERIAL_FACTORY := preload("res://game/scripts/brussels_white_stone_material.gd")
const HERO_GEOMETRY_PATH := "res://data/urbis/heroes/bourse_lod2.game.json"
const CANDIDATE_PATH := "res://data/qa/bourse_portico_articulation_candidate.json"
const SOURCE_PACKAGE_SHA256 := "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2"
const SOURCE_COORD_EPSILON_M := 0.02
const SURFACE_OFFSET_M := 0.025

var _surface: MeshInstance3D
var _enabled := true
var _ready_complete := false
var _identity_failure := false
var _source_triangle_count := 0
var _source_face_id := ""


func _ready() -> void:
    call_deferred("_build")


func _read_dictionary(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        push_error("Bourse pediment source missing: %s" % path)
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Bourse pediment source invalid: %s" % path)
        return {}
    return parsed as Dictionary


func _vec2(raw: Variant) -> Vector2:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 2:
        return Vector2.INF
    return Vector2(float(raw[0]), float(raw[1]))


func _point(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return Vector3.INF
    return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))


func _sources_are_safe(hero: Dictionary, candidate: Dictionary) -> bool:
    if str(hero.get("schema", "")) != "grand-bruxelles-urbis-hero-mesh-v1" or str(hero.get("hero_id", "")) != "bourse":
        return false
    var source := hero.get("source", {}) as Dictionary
    if str(source.get("crs", "")) != "EPSG:31370" or str(source.get("license", "")) != "CC0-1.0":
        return false
    if str(source.get("package_sha256", "")) != SOURCE_PACKAGE_SHA256:
        return false
    var contract := candidate.get("source_contract", {}) as Dictionary
    if str(contract.get("urbis3d_package_sha256", "")) != SOURCE_PACKAGE_SHA256:
        return false
    if str(contract.get("hero_id", "")) != "bourse":
        return false
    if not str(contract.get("heritage_front_fact", "")).contains("triangular pediment"):
        return false
    return true


func _triangle_points(raw_triangle: Variant) -> Array[Vector3]:
    var points: Array[Vector3] = []
    if typeof(raw_triangle) != TYPE_ARRAY or raw_triangle.size() != 3:
        return points
    for raw_point: Variant in raw_triangle:
        var point := _point(raw_point)
        if not point.is_finite():
            return []
        points.append(point)
    return points


func _is_source_pediment_triangle(
    triangle: Array[Vector3],
    plane_xz: Vector2,
    toward_xz: Vector2,
    tangent_xz: Vector2,
    t_min: float,
    t_max: float,
    source_y_max: float
) -> bool:
    if triangle.size() != 3:
        return false

    # A classical triangular pediment is represented by a single planar
    # triangular WALLSURFACE face in the committed LoD2. Identify its topology
    # from source coordinates only: one apex reaches the authoritative front
    # y_max and the other two source vertices form a level base. No authored
    # pediment width, height or entablature elevation participates here.
    var ys := [triangle[0].y, triangle[1].y, triangle[2].y]
    ys.sort()
    if absf(float(ys[2]) - source_y_max) > SOURCE_COORD_EPSILON_M:
        return false
    if absf(float(ys[0]) - float(ys[1])) > SOURCE_COORD_EPSILON_M:
        return false
    if float(ys[2]) - float(ys[1]) <= SOURCE_COORD_EPSILON_M:
        return false

    for point: Vector3 in triangle:
        var relative := Vector2(point.x, point.z) - plane_xz
        var along := relative.dot(tangent_xz)
        if along < t_min - SOURCE_COORD_EPSILON_M or along > t_max + SOURCE_COORD_EPSILON_M:
            return false

    # The front-envelope plane is the ordering anchor, not a guessed distance
    # cutoff. Candidate triangular source faces are ranked by absolute distance
    # to this plane and the nearest one is selected below.
    return true


func _triangle_plane_distance(
    triangle: Array[Vector3],
    plane_xz: Vector2,
    toward_xz: Vector2
) -> float:
    var centroid := (triangle[0] + triangle[1] + triangle[2]) / 3.0
    return absf((Vector2(centroid.x, centroid.z) - plane_xz).dot(toward_xz))


func _append_source_triangle(tool: SurfaceTool, triangle: Array[Vector3], toward_camera: Vector3) -> bool:
    if triangle.size() != 3:
        return false
    var a := triangle[0]
    var b := triangle[1]
    var c := triangle[2]
    var normal := (b - a).cross(c - a).normalized()
    if not normal.is_finite() or normal.length_squared() < 0.5:
        return false
    if Vector3(normal.x, 0.0, normal.z).dot(toward_camera) < 0.0:
        var swap := b
        b = c
        c = swap
        normal = -normal
    for vertex: Vector3 in [a, b, c]:
        tool.set_normal(normal)
        tool.add_vertex(vertex + toward_camera * SURFACE_OFFSET_M)
    return true


func _build() -> void:
    var hero := _read_dictionary(HERO_GEOMETRY_PATH)
    var candidate := _read_dictionary(CANDIDATE_PATH)
    if hero.is_empty() or candidate.is_empty() or not _sources_are_safe(hero, candidate):
        _identity_failure = true
        _ready_complete = true
        push_error("Bourse pediment source contract failed")
        return

    var envelope := candidate.get("authoritative_front_envelope", {}) as Dictionary
    var plane_xz := _vec2(envelope.get("plane_point_game_x_z", []))
    var toward_xz := _vec2(envelope.get("toward_camera_x_z", []))
    var tangent_xz := _vec2(envelope.get("tangent_x_z", []))
    if not plane_xz.is_finite() or not toward_xz.is_finite() or not tangent_xz.is_finite():
        _identity_failure = true
        _ready_complete = true
        push_error("Bourse pediment front envelope invalid")
        return
    toward_xz = toward_xz.normalized()
    tangent_xz = tangent_xz.normalized()
    var toward_camera := Vector3(toward_xz.x, 0.0, toward_xz.y)
    var t_min := float(envelope.get("tangent_min_m", 0.0))
    var t_max := float(envelope.get("tangent_max_m", 0.0))
    var source_y_max := float(envelope.get("y_max_m", 0.0))
    if t_max <= t_min or source_y_max <= 0.0:
        _identity_failure = true
        _ready_complete = true
        push_error("Bourse pediment source bounds invalid")
        return

    var best_triangle: Array[Vector3] = []
    var best_face_id := ""
    var best_distance := INF
    var candidate_count := 0
    for raw_face: Variant in hero.get("faces", []):
        if typeof(raw_face) != TYPE_DICTIONARY:
            continue
        var face := raw_face as Dictionary
        if str(face.get("type", "")) != "WALLSURFACE":
            continue
        var triangles := face.get("triangles", []) as Array
        if triangles.size() != 1:
            continue
        var triangle := _triangle_points(triangles[0])
        if not _is_source_pediment_triangle(triangle, plane_xz, toward_xz, tangent_xz, t_min, t_max, source_y_max):
            continue
        candidate_count += 1
        var distance := _triangle_plane_distance(triangle, plane_xz, toward_xz)
        if distance < best_distance:
            best_distance = distance
            best_triangle = triangle
            best_face_id = str(face.get("id", ""))

    if best_triangle.size() != 3 or best_face_id.is_empty():
        _identity_failure = true
        _ready_complete = true
        push_error("Bourse pediment topology selection returned no triangular front face")
        return

    var material := MATERIAL_FACTORY.create(
        Color(0.76, 0.745, 0.69, 1.0),
        Color(0.89, 0.86, 0.78, 1.0),
        0.79,
        "Bourse Urban 31241 triangular pediment; exact source LoD2 wall face"
    )
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_material(material)
    if not _append_source_triangle(tool, best_triangle, toward_camera):
        _identity_failure = true
        _ready_complete = true
        push_error("Bourse pediment source face failed to append")
        return
    _source_triangle_count = 1
    _source_face_id = best_face_id

    var mesh := tool.commit()
    if mesh == null or mesh.get_surface_count() == 0:
        _identity_failure = true
        _ready_complete = true
        push_error("Bourse pediment source surface failed to build")
        return
    _surface = MeshInstance3D.new()
    _surface.name = "BourseOfficialPedimentSourceSurface"
    _surface.mesh = mesh
    _surface.set_meta("geometry_source_triangles", _source_triangle_count)
    _surface.set_meta("geometry_source_face_id", _source_face_id)
    _surface.set_meta("source_face_candidates", candidate_count)
    _surface.set_meta("source_plane_distance_m", best_distance)
    _surface.set_meta("source_package_sha256", SOURCE_PACKAGE_SHA256)
    _surface.set_meta("geometry_dimensions_authored", false)
    _surface.set_meta("presentation_offset_m", SURFACE_OFFSET_M)
    _surface.set_meta("heritage_semantic", "six Corinthian columns carrying a triangular pediment")
    add_child(_surface)
    _ready_complete = true
    print("BOURSE_OFFICIAL_PEDIMENT_SURFACE_READY: face=%s candidates=%d plane_distance=%.3f source_triangles=1 authored_dimensions=false offset_m=%.3f" % [_source_face_id, candidate_count, best_distance, SURFACE_OFFSET_M])


func set_enabled(enabled: bool) -> void:
    _enabled = enabled
    if is_instance_valid(_surface):
        _surface.visible = enabled


func diagnostic_enabled() -> bool:
    return _enabled and is_instance_valid(_surface) and _surface.visible


func diagnostic_ready_complete() -> bool:
    return _ready_complete


func diagnostic_identity_failure() -> bool:
    return _identity_failure


func diagnostic_source_triangle_count() -> int:
    return _source_triangle_count


func diagnostic_source_face_id() -> String:
    return _source_face_id

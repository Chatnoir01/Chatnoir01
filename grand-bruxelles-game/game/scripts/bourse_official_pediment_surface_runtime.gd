extends Node

const MATERIAL_FACTORY := preload("res://game/scripts/brussels_white_stone_material.gd")
const HERO_GEOMETRY_PATH := "res://data/urbis/heroes/bourse_lod2.game.json"
const CANDIDATE_PATH := "res://data/qa/bourse_portico_articulation_candidate.json"
const SOURCE_PACKAGE_SHA256 := "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2"
const FRONT_PLANE_TOLERANCE_M := 0.55
const SURFACE_OFFSET_M := 0.025

var _surface: MeshInstance3D
var _enabled := true
var _ready_complete := false
var _identity_failure := false
var _source_triangle_count := 0


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


func _front_triangle(
    a: Vector3,
    b: Vector3,
    c: Vector3,
    plane_xz: Vector2,
    toward_xz: Vector2,
    tangent_xz: Vector2,
    t_min: float,
    t_max: float,
    pediment_floor_y: float,
    source_y_max: float
) -> bool:
    var centroid := (a + b + c) / 3.0
    var centroid_xz := Vector2(centroid.x, centroid.z)
    var relative := centroid_xz - plane_xz
    if absf(relative.dot(toward_xz)) > FRONT_PLANE_TOLERANCE_M:
        return false
    var along := relative.dot(tangent_xz)
    if along < t_min or along > t_max:
        return false
    # The lower boundary comes from the already-registered portico candidate;
    # the upper boundary comes from the authoritative front envelope. No
    # pediment width/height is authored in this runtime.
    if centroid.y < pediment_floor_y or centroid.y > source_y_max + 0.01:
        return false
    return true


func _append_source_triangle(tool: SurfaceTool, triangle: Array, toward_camera: Vector3) -> bool:
    if triangle.size() != 3:
        return false
    var a := _point(triangle[0])
    var b := _point(triangle[1])
    var c := _point(triangle[2])
    if not a.is_finite() or not b.is_finite() or not c.is_finite():
        return false
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
    var visual := candidate.get("provisional_visualization", {}) as Dictionary
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
    var pediment_floor_y := float(visual.get("entablature_center_y_m", 0.0)) + float(visual.get("entablature_height_m", 0.0)) * 0.5
    if t_max <= t_min or source_y_max <= pediment_floor_y:
        _identity_failure = true
        _ready_complete = true
        push_error("Bourse pediment source bounds invalid")
        return

    var material := MATERIAL_FACTORY.create(
        Color(0.76, 0.745, 0.69, 1.0),
        Color(0.89, 0.86, 0.78, 1.0),
        0.79,
        "Bourse Urban 31241 triangular pediment; exact source LoD2 wall triangles"
    )
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_material(material)

    for raw_face: Variant in hero.get("faces", []):
        if typeof(raw_face) != TYPE_DICTIONARY:
            continue
        var face := raw_face as Dictionary
        if str(face.get("type", "")) != "WALLSURFACE":
            continue
        for raw_triangle: Variant in face.get("triangles", []):
            if typeof(raw_triangle) != TYPE_ARRAY or raw_triangle.size() != 3:
                continue
            var triangle := raw_triangle as Array
            var a := _point(triangle[0])
            var b := _point(triangle[1])
            var c := _point(triangle[2])
            if not a.is_finite() or not b.is_finite() or not c.is_finite():
                continue
            if not _front_triangle(a, b, c, plane_xz, toward_xz, tangent_xz, t_min, t_max, pediment_floor_y, source_y_max):
                continue
            if _append_source_triangle(tool, triangle, toward_camera):
                _source_triangle_count += 1

    if _source_triangle_count <= 0:
        _identity_failure = true
        _ready_complete = true
        push_error("Bourse pediment source selection returned zero triangles")
        return

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
    _surface.set_meta("source_package_sha256", SOURCE_PACKAGE_SHA256)
    _surface.set_meta("geometry_dimensions_authored", false)
    _surface.set_meta("presentation_offset_m", SURFACE_OFFSET_M)
    _surface.set_meta("heritage_semantic", "six Corinthian columns carrying a triangular pediment")
    add_child(_surface)
    _ready_complete = true
    print("BOURSE_OFFICIAL_PEDIMENT_SURFACE_READY: source_triangles=%d authored_dimensions=false offset_m=%.3f" % [_source_triangle_count, SURFACE_OFFSET_M])


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

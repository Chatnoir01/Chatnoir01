extends Node3D

const SOURCE_PATH := "res://data/qa/grand_place_brasseurs_wall_skin_source.json"
const WALL_NODE := "GrandPlaceBrasseursWall10945501"

var wall_ready := false
var _source: Dictionary = {}
var _wall: MeshInstance3D

func _ready() -> void:
    _build()

func _v3(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return Vector3.INF
    return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))

func _read_source() -> Dictionary:
    if not FileAccess.file_exists(SOURCE_PATH):
        push_error("Brasseurs wall-skin source contract missing")
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Brasseurs wall-skin source contract invalid")
        return {}
    return parsed as Dictionary

func _build() -> void:
    if wall_ready:
        return
    _source = _read_source()
    if _source.is_empty():
        return
    var target: Dictionary = _source.get("target", {})
    var presentation: Dictionary = _source.get("presentation_contract", {})
    if str(target.get("building_id", "")) != "1639974" or str(target.get("front_wall_id", "")) != "10945501":
        push_error("Brasseurs wall-skin identity mismatch")
        return
    if int(target.get("source_triangle_count", -1)) != 3:
        push_error("Brasseurs wall-skin source triangle count mismatch")
        return
    if int(presentation.get("details", -1)) != 0 or absf(float(presentation.get("outward_offset_m", 999.0))) > 0.000001:
        push_error("Brasseurs wall-skin base-presentation contract mismatch")
        return
    if bool(presentation.get("hide_neighbor_geometry", true)) or bool(presentation.get("raw_commons_pixels_shipped", true)):
        push_error("Brasseurs wall-skin forbidden presentation mutation")
        return

    var raw_triangles: Array = target.get("official_triangles_world", [])
    if raw_triangles.size() != 3:
        push_error("Brasseurs wall-skin official triangles missing")
        return

    var vertices := PackedVector3Array()
    var normals := PackedVector3Array()
    for raw_triangle: Variant in raw_triangles:
        if typeof(raw_triangle) != TYPE_ARRAY or raw_triangle.size() != 3:
            push_error("Brasseurs wall-skin malformed source triangle")
            return
        var a := _v3(raw_triangle[0])
        var b := _v3(raw_triangle[1])
        var c := _v3(raw_triangle[2])
        if not a.is_finite() or not b.is_finite() or not c.is_finite():
            push_error("Brasseurs wall-skin non-finite source vertex")
            return
        var normal := (b - a).cross(c - a).normalized()
        if not normal.is_finite() or normal.length_squared() < 0.5:
            push_error("Brasseurs wall-skin degenerate source triangle")
            return
        vertices.append(a)
        vertices.append(b)
        vertices.append(c)
        normals.append(normal)
        normals.append(normal)
        normals.append(normal)

    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.69, 0.61, 0.49, 1.0)
    material.roughness = 0.84
    material.metallic = 0.0
    # UrbIS face winding is preserved exactly. Two-sided presentation avoids
    # changing source triangle order merely to satisfy a camera-facing winding.
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material.set_meta("authored_visibility_presentation", true)
    material.set_meta("measured_photometry", false)
    material.set_meta("source_geometry_changed", false)

    _wall = MeshInstance3D.new()
    _wall.name = WALL_NODE
    _wall.mesh = mesh
    _wall.material_override = material
    _wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    add_child(_wall)

    set_meta("building_id", "1639974")
    set_meta("source_wall_id", "10945501")
    set_meta("source_vertex_count", 5)
    set_meta("source_triangle_count", 3)
    set_meta("details_count", 0)
    set_meta("wall_offset_m", 0.0)
    set_meta("hides_neighbor_geometry", false)
    set_meta("raw_photo_pixels_shipped", false)
    set_meta("runtime_approved", false)
    set_meta("realism_complete", false)
    set_meta("two_sided_presentation_preserves_source_winding", true)
    wall_ready = true
    print("BRASSEURS_EXACT_WALL_READY: building=1639974 wall=10945501 triangles=3 details=0 offset=0 hide_neighbor=false")

func source_contract() -> Dictionary:
    return {
        "building_id": "1639974",
        "front_wall_id": "10945501",
        "unique_vertex_count": 5,
        "triangle_count": 3,
        "horizontal_span_m": 8.749036,
        "world_y_max_m": 24.746,
        "detail_count": 0,
        "outward_offset_used": false,
        "neighbor_geometry_hidden": false,
        "raw_photo_pixels_shipped": false,
        "runtime_approved": false,
        "realism_complete": false,
    }

func set_wall_visible(enabled: bool) -> void:
    visible = enabled

func wall_visible() -> bool:
    return visible

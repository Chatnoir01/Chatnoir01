extends Node3D

const SOURCE_PATH := "res://data/qa/grand_place_brasseurs_wall_skin_source.json"
const WALL_NODE := "GrandPlaceBrasseursWall10945501"

var _source: Dictionary = {}
var _mesh_instance: MeshInstance3D

func _ready() -> void:
    _build_from_source()

func _fail(message: String) -> void:
    push_error("Grand-Place Brasseurs wall skin: " + message)

func _build_from_source() -> void:
    if not FileAccess.file_exists(SOURCE_PATH):
        _fail("source contract missing")
        return
    var parsed := JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("source contract invalid")
        return
    _source = parsed as Dictionary
    var target := _source.get("target", {}) as Dictionary
    var presentation := _source.get("presentation_contract", {}) as Dictionary
    if str(target.get("building_id", "")) != "1639974" or str(target.get("front_wall_id", "")) != "10945501":
        _fail("source target drifted")
        return
    if int(presentation.get("details", -1)) != 0 or absf(float(presentation.get("outward_offset_m", 999.0))) > 0.000001:
        _fail("base wall proof must stay details=0 and offset=0")
        return

    var raw_vertices := target.get("official_unique_vertices_world", []) as Array
    var raw_triangles := target.get("continuous_skin_triangle_indices", []) as Array
    if raw_vertices.size() != 5 or raw_triangles.size() != 3:
        _fail("expected five exact boundary vertices and three triangles")
        return

    var vertices: Array[Vector3] = []
    for raw: Variant in raw_vertices:
        if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
            _fail("invalid official vertex")
            return
        vertices.append(Vector3(float(raw[0]), float(raw[1]), float(raw[2])))

    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    for raw_triangle: Variant in raw_triangles:
        if typeof(raw_triangle) != TYPE_ARRAY or raw_triangle.size() != 3:
            _fail("invalid triangle index record")
            return
        var a := vertices[int(raw_triangle[0])]
        var b := vertices[int(raw_triangle[1])]
        var c := vertices[int(raw_triangle[2])]
        var normal := (b - a).cross(c - a).normalized()
        for vertex: Vector3 in [a, b, c]:
            tool.set_normal(normal)
            tool.add_vertex(vertex)

    var mesh := tool.commit()
    if mesh == null or mesh.get_surface_count() != 1:
        _fail("continuous wall mesh commit failed")
        return

    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.73, 0.67, 0.56, 1.0)
    material.roughness = 0.88
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    mesh.surface_set_material(0, material)

    _mesh_instance = MeshInstance3D.new()
    _mesh_instance.name = WALL_NODE
    _mesh_instance.mesh = mesh
    _mesh_instance.set_meta("urbis_building_id", "1639974")
    _mesh_instance.set_meta("urbis_front_wall_id", "10945501")
    _mesh_instance.set_meta("geometry_authority", "UrbIS_3D_Constructions")
    _mesh_instance.set_meta("outward_offset_m", 0.0)
    _mesh_instance.set_meta("detail_count", 0)
    _mesh_instance.set_meta("material_identity_source_measured", false)
    add_child(_mesh_instance)

func set_candidate_visible(enabled: bool) -> void:
    if is_instance_valid(_mesh_instance):
        _mesh_instance.visible = enabled

func candidate_visible() -> bool:
    return is_instance_valid(_mesh_instance) and _mesh_instance.visible

func source_contract() -> Dictionary:
    var target := _source.get("target", {}) as Dictionary
    var presentation := _source.get("presentation_contract", {}) as Dictionary
    return {
        "building_id": str(target.get("building_id", "")),
        "front_wall_id": str(target.get("front_wall_id", "")),
        "unique_vertex_count": (target.get("official_unique_vertices_world", []) as Array).size(),
        "triangle_count": (target.get("continuous_skin_triangle_indices", []) as Array).size(),
        "horizontal_span_m": float(target.get("horizontal_span_m", 0.0)),
        "world_y_max_m": float(target.get("world_y_max_m", 0.0)),
        "outward_offset_used": absf(float(presentation.get("outward_offset_m", 0.0))) > 0.000001,
        "detail_count": int(presentation.get("details", -1)),
        "raw_commons_pixels_shipped": bool(presentation.get("raw_commons_pixels_shipped", true)),
        "material_identity_source_measured": bool(presentation.get("material_identity_source_measured", true)),
    }

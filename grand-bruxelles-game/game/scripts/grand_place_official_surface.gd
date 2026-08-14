extends Node3D

@export_file("*.json") var data_path: String = "res://data/urbis/grand_place_surface_42405.game.json"
@export var presentation_lift_m: float = 0.081

var surface_loaded := false
var triangle_count := 0
var open_vertex_count := 0
var official_area_m2 := 0
var _surface_mesh: MeshInstance3D


func _ready() -> void:
    _build_surface()


func _fail(message: String) -> void:
    push_error("Grand-Place official surface: %s" % message)


func _build_surface() -> void:
    if not FileAccess.file_exists(data_path):
        _fail("data missing: %s" % data_path)
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("invalid JSON")
        return
    var data := parsed as Dictionary
    if str(data.get("schema", "")) != "grand-bruxelles-grand-place-official-surface-v1":
        _fail("unsupported schema")
        return
    if bool(data.get("runtime_approved", true)) or bool(data.get("realism_complete", true)):
        _fail("source-bounded surface must remain explicitly incomplete")
        return
    if bool(data.get("curb_elevation_resolved", true)):
        _fail("curb elevation must remain unresolved")
        return

    var surface: Dictionary = data.get("surface", {})
    if str(surface.get("inspire_id", "")) != "https://databrussels.be/id/streetsurface/42405":
        _fail("unexpected official StreetSurface")
        return
    if int(surface.get("level", 999)) != 0 or int(surface.get("area_m2", 0)) != 5337:
        _fail("official level/area contract drifted")
        return
    if str(surface.get("street_name_fr", "")) != "Grand-Place" or str(surface.get("street_name_nl", "")) != "Grote Markt":
        _fail("Grand-Place bilingual identity drifted")
        return

    var rings: Variant = surface.get("game_rings_xz", [])
    if not rings is Array or rings.size() != 1:
        _fail("expected one official exterior ring")
        return
    var raw_ring: Variant = rings[0]
    if not raw_ring is Array or raw_ring.size() < 4:
        _fail("official ring too small")
        return

    var polygon := PackedVector2Array()
    for raw: Variant in raw_ring:
        if raw is Array and raw.size() >= 2:
            polygon.append(Vector2(float(raw[0]), float(raw[1])))
    if polygon.size() < 4:
        _fail("official ring conversion failed")
        return
    if polygon[0].is_equal_approx(polygon[polygon.size() - 1]):
        polygon.resize(polygon.size() - 1)
    open_vertex_count = polygon.size()

    var indices := Geometry2D.triangulate_polygon(polygon)
    if indices.size() < 3 or indices.size() % 3 != 0:
        _fail("official polygon triangulation failed")
        return

    var material := StandardMaterial3D.new()
    # urban.brussels establishes granite paving identity. These PBR values are
    # authored presentation values, not sampled photometry or surveyed stone size.
    material.albedo_color = Color(0.39, 0.385, 0.37, 1.0)
    material.metallic = 0.0
    material.roughness = 0.94
    # Ground paving is a planar source surface and has no surveyed thickness.
    # Disable culling so renderer front-face convention cannot suppress the
    # authoritative top plane; the generic ground beneath prevents an underside read.
    material.cull_mode = BaseMaterial3D.CULL_DISABLED

    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_material(material)
    for i: int in range(0, indices.size(), 3):
        var a := Vector3(polygon[indices[i]].x, presentation_lift_m, polygon[indices[i]].y)
        var b := Vector3(polygon[indices[i + 1]].x, presentation_lift_m, polygon[indices[i + 1]].y)
        var c := Vector3(polygon[indices[i + 2]].x, presentation_lift_m, polygon[indices[i + 2]].y)
        var normal := (b - a).cross(c - a).normalized()
        if normal.y < 0.0:
            var swap := b
            b = c
            c = swap
            normal = -normal
        for vertex: Vector3 in [a, b, c]:
            tool.set_normal(normal)
            tool.add_vertex(vertex)

    var mesh := tool.commit()
    if mesh == null or mesh.get_surface_count() == 0:
        _fail("official surface mesh empty")
        return
    _surface_mesh = MeshInstance3D.new()
    _surface_mesh.name = "OfficialStreetSurface_42405"
    _surface_mesh.mesh = mesh
    add_child(_surface_mesh)

    triangle_count = indices.size() / 3
    official_area_m2 = int(surface.get("area_m2", 0))
    surface_loaded = true
    set_meta("official_inspire_id", surface.get("inspire_id", ""))
    set_meta("type_uninterpreted", surface.get("type_uninterpreted", ""))
    set_meta("granite_identity_source", "urban.brussels heritage site 322")
    set_meta("presentation_lift_only", true)
    set_meta("runtime_approved", false)
    set_meta("realism_complete", false)
    print("Grand-Place official surface: id=42405 area=%d vertices=%d triangles=%d granite_identity=true runtime_approved=false" % [official_area_m2, open_vertex_count, triangle_count])


func set_surface_visible(enabled: bool) -> void:
    if _surface_mesh != null:
        _surface_mesh.visible = enabled


func surface_is_visible() -> bool:
    return _surface_mesh != null and _surface_mesh.visible

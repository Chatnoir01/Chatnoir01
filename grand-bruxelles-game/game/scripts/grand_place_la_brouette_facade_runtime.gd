extends Node3D

const CONTRACT_PATH := "res://data/qa/grand_place_la_brouette_facade_contract.json"
const WHITE_STONE := preload("res://game/scripts/brussels_white_stone_material.gd")

var articulation_ready := false
var level_count := 4
var bay_count := 4
var opening_proxy_count := 0
var support_proxy_count := 0
var facade_skin_triangle_count := 0

var _skin_material: Material
var _opening_material: StandardMaterial3D
var _support_material: Material

func _ready() -> void:
    _build()

func _fail(message: String) -> void:
    push_error("Grand-Place La Brouette facade: %s" % message)

func _vec3(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return Vector3.ZERO
    return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))

func _read_contract() -> Dictionary:
    if not FileAccess.file_exists(CONTRACT_PATH):
        _fail("contract missing")
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("contract invalid JSON")
        return {}
    var data := parsed as Dictionary
    if str(data.get("schema", "")) != "grand-bruxelles-grand-place-la-brouette-facade-contract-v1":
        _fail("contract schema drifted")
        return {}
    if bool(data.get("runtime_approved", true)) or bool(data.get("realism_complete", true)):
        _fail("candidate must remain visually gated")
        return {}
    return data

func _make_materials() -> void:
    _skin_material = WHITE_STONE.create(
        Color(0.72, 0.70, 0.65, 1.0),
        Color(0.84, 0.81, 0.74, 1.0),
        0.84,
        "La Brouette Urban 31120 / UrbIS frontage face 10897437"
    )
    _support_material = _skin_material
    _opening_material = StandardMaterial3D.new()
    _opening_material.albedo_color = Color(0.045, 0.060, 0.070, 1.0)
    _opening_material.roughness = 0.26
    _opening_material.metallic = 0.03
    _opening_material.cull_mode = BaseMaterial3D.CULL_DISABLED

func _surface_normal(tangent: Vector3, midpoint: Vector3, player_side: Vector3) -> Vector3:
    var normal := Vector3(-tangent.z, 0.0, tangent.x).normalized()
    if normal.dot(player_side - midpoint) < 0.0:
        normal = -normal
    return normal

func _build_skin(triangles: Array, normal: Vector3, offset: float) -> void:
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_material(_skin_material)
    var count := 0
    for raw_triangle: Variant in triangles:
        if typeof(raw_triangle) != TYPE_ARRAY or raw_triangle.size() != 3:
            _fail("official frontage triangle malformed")
            return
        for raw_point: Variant in raw_triangle:
            var point := _vec3(raw_point) + normal * offset
            tool.set_normal(normal)
            tool.add_vertex(point)
        count += 1
    var mesh_instance := MeshInstance3D.new()
    mesh_instance.name = "OfficialFrontageSkin"
    mesh_instance.mesh = tool.commit()
    mesh_instance.material_override = _skin_material
    add_child(mesh_instance)
    facade_skin_triangle_count = count

func _panel_mesh(center: Vector3, tangent: Vector3, normal: Vector3, width: float, height: float) -> ArrayMesh:
    var half_w := tangent * width * 0.5
    var half_h := Vector3.UP * height * 0.5
    var p0 := center - half_w - half_h
    var p1 := center + half_w - half_h
    var p2 := center + half_w + half_h
    var p3 := center - half_w + half_h
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_material(_opening_material)
    for p: Vector3 in [p0,p1,p2,p0,p2,p3]:
        tool.set_normal(normal)
        tool.add_vertex(p)
    return tool.commit()

func _add_opening(center: Vector3, tangent: Vector3, normal: Vector3, width: float, height: float, register_index: int, bay_index: int) -> void:
    var panel := MeshInstance3D.new()
    panel.name = "Opening_R%d_B%d" % [register_index + 1, bay_index + 1]
    panel.mesh = _panel_mesh(center, tangent, normal, width, height)
    panel.material_override = _opening_material
    add_child(panel)
    opening_proxy_count += 1

func _add_flat_support(center: Vector3, tangent: Vector3, width: float, height: float, depth: float, name_value: String) -> void:
    var box := CSGBox3D.new()
    box.name = name_value
    box.size = Vector3(width, height, depth)
    box.position = center
    box.rotation.y = atan2(tangent.x, tangent.z)
    box.material = _support_material
    box.use_collision = false
    add_child(box)
    support_proxy_count += 1

func _add_round_support(center: Vector3, radius: float, height: float, name_value: String) -> void:
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = height
    mesh.radial_segments = 18
    mesh.rings = 1
    var instance := MeshInstance3D.new()
    instance.name = name_value
    instance.mesh = mesh
    instance.material_override = _support_material
    instance.position = center
    add_child(instance)
    support_proxy_count += 1

func _build() -> void:
    var data := _read_contract()
    if data.is_empty():
        return
    var source: Dictionary = data.get("source_contract", {})
    var frontage: Dictionary = data.get("official_frontage", {})
    var visual: Dictionary = data.get("provisional_visualization", {})
    if source.is_empty() or frontage.is_empty() or visual.is_empty():
        _fail("contract sections missing")
        return
    if str(source.get("building_id", "")) != "https://databrussels.be/id/building/1607758":
        _fail("building identity drifted")
        return
    if str(source.get("frontage_face_id", "")) != "https://databrussels.be/id/buildingface/10897437":
        _fail("frontage identity drifted")
        return
    level_count = int(source.get("documented_levels", 0))
    bay_count = int(source.get("documented_bays", 0))
    if level_count != 4 or bay_count != 4:
        _fail("heritage level/bay count drifted")
        return

    var a := _vec3(frontage.get("baseline_start_game", []))
    var b := _vec3(frontage.get("baseline_end_game", []))
    var player_side := _vec3(frontage.get("player_side_game", []))
    var tangent := (b - a)
    tangent.y = 0.0
    var length := tangent.length()
    if length < 7.0 or length > 8.0:
        _fail("official frontage width drifted: %.3f" % length)
        return
    tangent = tangent.normalized()
    var midpoint := (a + b) * 0.5
    var normal := _surface_normal(tangent, midpoint, player_side)
    _make_materials()

    var triangles: Variant = frontage.get("triangles", [])
    if typeof(triangles) != TYPE_ARRAY or triangles.size() != 4:
        _fail("official frontage must contain four triangles")
        return
    _build_skin(triangles as Array, normal, float(visual.get("surface_forward_offset_m", 0.045)))

    var bottom_y := float(visual.get("register_bottom_y_m", 0.55))
    var top_y := float(visual.get("register_top_y_m", 17.55))
    var register_height := (top_y - bottom_y) / float(level_count)
    var bay_spacing := length / float(bay_count)
    var opening_width := bay_spacing * float(visual.get("opening_width_ratio_of_bay", 0.56))
    var opening_height := register_height * float(visual.get("opening_height_ratio_of_register", 0.58))
    var opening_offset := float(visual.get("opening_forward_offset_m", 0.075))
    var support_offset := float(visual.get("support_forward_offset_m", 0.095))
    var flat_width := float(visual.get("flat_support_width_m", 0.12))
    var round_radius := float(visual.get("round_support_radius_m", 0.09))

    for register_index: int in range(level_count):
        var center_y := bottom_y + register_height * (float(register_index) + 0.5)
        for bay_index: int in range(bay_count):
            var t := (float(bay_index) + 0.5) / float(bay_count)
            var center := a.lerp(b, t)
            center.y = center_y
            center += normal * opening_offset
            _add_opening(center, tangent, normal, opening_width, opening_height, register_index, bay_index)
        for boundary_index: int in range(bay_count + 1):
            var bt := float(boundary_index) / float(bay_count)
            var support_center := a.lerp(b, bt)
            support_center.y = center_y
            support_center += normal * support_offset
            var support_height := register_height * 0.78
            if register_index == 1 or register_index == 2:
                _add_round_support(support_center, round_radius, support_height, "OrderSupport_R%d_B%d" % [register_index + 1, boundary_index + 1])
            else:
                _add_flat_support(support_center, tangent, flat_width, support_height, 0.08, "OrderSupport_R%d_B%d" % [register_index + 1, boundary_index + 1])

    articulation_ready = facade_skin_triangle_count == 4 and opening_proxy_count == 16 and support_proxy_count == 20
    set_meta("building_id", str(source.get("building_id", "")))
    set_meta("frontage_face_id", str(source.get("frontage_face_id", "")))
    set_meta("heritage_source", "urban.brussels/31120")
    set_meta("gable_from_official_frontage", true)
    set_meta("geometry_claimed_surveyed", false)
    set_meta("ornament_authored", false)
    set_meta("runtime_approved", false)
    set_meta("realism_complete", false)
    set_meta("placement_semantics", "official_urbis_frontage_plus_source_counted_visualization_conventions")
    print("GRAND_PLACE_LA_BROUETTE_FACADE_READY: levels=%d bays=%d openings=%d supports=%d frontage_triangles=%d surveyed=false ornament=false" % [level_count,bay_count,opening_proxy_count,support_proxy_count,facade_skin_triangle_count])

func set_articulation_visible(enabled: bool) -> void:
    visible = enabled

func articulation_visible() -> bool:
    return visible

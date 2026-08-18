extends Node3D

const BrusselsWhiteStoneMaterial := preload("res://game/scripts/brussels_white_stone_material.gd")

const OFFICIAL_NODE := "GrandPlaceOfficialLod2"
const BUILDING_ID := "https://databrussels.be/id/building/1655673"
const EAST_FROM := Vector3(282.2, 0.0, -523.4)
const EAST_TO := Vector3(303.2, 0.0, -499.9)
const WEST_FROM := Vector3(277.1, 0.0, -529.7)
const WEST_TO := Vector3(252.1, 0.0, -540.5)
const PLAYER_SIDE := Vector3(319.01, 1.72, -535.20)
const REGISTER_Y := [10.0, 18.0]
const PANEL_HEIGHT := 3.4
const PANEL_WIDTH_RATIO := 0.55
const CROSS_MEMBER_M := 0.18
const CROSS_OFFSET_M := 0.014
const CROSS_DIMENSIONS_SOURCE := "visualization_convention_not_survey_dimensions"

var articulation_ready := false
var east_bay_count := 10
var west_bay_count := 9
var window_register_count := 2
var window_panel_count := 0
var placement_semantics := "heritage_counts_on_official_lod2_visualization_convention_not_survey"
var geometry_claimed_surveyed := false
var _panels: Array[MeshInstance3D] = []
var _cross_details: Array[MeshInstance3D] = []
var _cross_count := 0
var _cross_enabled := true
var _cross_material: Material

func _ready() -> void:
    call_deferred("_bind_when_ready")

func _bind_when_ready() -> void:
    var official := get_tree().root.get_node_or_null(OFFICIAL_NODE)
    for _frame: int in range(480):
        if official != null and bool(official.get("geometry_loaded")):
            break
        await get_tree().process_frame
        official = get_tree().root.get_node_or_null(OFFICIAL_NODE)
    if official == null or not bool(official.get("geometry_loaded")):
        push_error("Grand-Place Town Hall window rhythm: official LoD2 missing")
        return
    if str(official.get_meta("building_id", "")) != BUILDING_ID:
        push_error("Grand-Place Town Hall window rhythm: building identity drifted")
        return
    _cross_material = BrusselsWhiteStoneMaterial.create(
        Color(0.68, 0.66, 0.60, 1.0),
        Color(0.86, 0.82, 0.74, 1.0),
        0.82,
        "Urban Brussels 31125 east-wing fenetres a croisee; cross-member dimensions authored presentation only"
    )
    _build_wing(EAST_FROM, EAST_TO, east_bay_count, "East", true)
    _build_wing(WEST_FROM, WEST_TO, west_bay_count, "West", false)
    window_panel_count = _panels.size()
    articulation_ready = window_panel_count == 38 and _cross_count == 20 and _cross_details.size() == 40
    set_meta("building_id", BUILDING_ID)
    set_meta("heritage_source", "urban.brussels/31125")
    set_meta("east_bays_documented", 10)
    set_meta("west_bays_documented", 9)
    set_meta("window_registers_documented", 2)
    set_meta("east_window_identity", "fenetres_a_croisee")
    set_meta("west_special_ordination_deferred", true)
    set_meta("placement_semantics", placement_semantics)
    set_meta("cross_dimensions_source", CROSS_DIMENSIONS_SOURCE)
    set_meta("geometry_changed", false)
    set_meta("new_openings_authored", false)
    set_meta("runtime_approved", false)
    set_meta("realism_complete", false)
    print("GRAND_PLACE_TOWN_HALL_WINDOW_RHYTHM_READY: east=%d west=%d registers=%d panels=%d east_crosses=%d strips=%d west_deferred=true surveyed=false" % [east_bay_count, west_bay_count, window_register_count, window_panel_count, _cross_count, _cross_details.size()])

func _build_wing(a: Vector3, b: Vector3, bays: int, label: String, add_crosses: bool) -> void:
    var tangent := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
    var segment_length := Vector2(b.x - a.x, b.z - a.z).length()
    var bay_spacing := segment_length / float(bays)
    var width := bay_spacing * PANEL_WIDTH_RATIO
    var horizontal_normal := Vector3(-tangent.z, 0.0, tangent.x)
    var midpoint := (a + b) * 0.5
    if horizontal_normal.dot(PLAYER_SIDE - midpoint) < 0.0:
        horizontal_normal = -horizontal_normal
    for register_index: int in range(REGISTER_Y.size()):
        for bay: int in range(bays):
            var t := (float(bay) + 0.5) / float(bays)
            var center := a.lerp(b, t)
            center.y = float(REGISTER_Y[register_index])
            center += horizontal_normal * 0.055
            var panel := MeshInstance3D.new()
            panel.name = "%s_R%d_B%02d" % [label, register_index + 1, bay + 1]
            panel.mesh = _panel_mesh(center, tangent, horizontal_normal, width, PANEL_HEIGHT)
            add_child(panel)
            _panels.append(panel)
            if add_crosses:
                _add_cross_detail(center, tangent, horizontal_normal, width, PANEL_HEIGHT, label, register_index, bay)

func _panel_mesh(center: Vector3, tangent: Vector3, normal: Vector3, width: float, height: float) -> ArrayMesh:
    var half_w := tangent * width * 0.5
    var half_h := Vector3.UP * height * 0.5
    var p0 := center - half_w - half_h
    var p1 := center + half_w - half_h
    var p2 := center + half_w + half_h
    var p3 := center - half_w + half_h
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.055, 0.075, 0.085, 1.0)
    material.roughness = 0.24
    material.metallic = 0.05
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    tool.set_material(material)
    for p: Vector3 in [p0,p1,p2,p0,p2,p3]:
        tool.set_normal(normal)
        tool.add_vertex(p)
    return tool.commit()

func _add_cross_detail(center: Vector3, tangent: Vector3, normal: Vector3, width: float, height: float, label: String, register_index: int, bay: int) -> void:
    var detail_center := center + normal * CROSS_OFFSET_M
    var vertical := MeshInstance3D.new()
    vertical.name = "%s_R%d_B%02d_Mullion" % [label, register_index + 1, bay + 1]
    vertical.mesh = _strip_mesh(detail_center, tangent, normal, CROSS_MEMBER_M, height)
    vertical.material_override = _cross_material
    vertical.set_meta("role", "cross_window_mullion")
    vertical.set_meta("dimensions_source", CROSS_DIMENSIONS_SOURCE)
    add_child(vertical)
    _cross_details.append(vertical)

    var horizontal := MeshInstance3D.new()
    horizontal.name = "%s_R%d_B%02d_Transom" % [label, register_index + 1, bay + 1]
    horizontal.mesh = _strip_mesh(detail_center, tangent, normal, width, CROSS_MEMBER_M)
    horizontal.material_override = _cross_material
    horizontal.set_meta("role", "cross_window_transom")
    horizontal.set_meta("dimensions_source", CROSS_DIMENSIONS_SOURCE)
    add_child(horizontal)
    _cross_details.append(horizontal)
    _cross_count += 1

func _strip_mesh(center: Vector3, tangent: Vector3, normal: Vector3, width: float, height: float) -> ArrayMesh:
    var half_w := tangent * width * 0.5
    var half_h := Vector3.UP * height * 0.5
    var p0 := center - half_w - half_h
    var p1 := center + half_w - half_h
    var p2 := center + half_w + half_h
    var p3 := center - half_w + half_h
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    for p: Vector3 in [p0,p1,p2,p0,p2,p3]:
        tool.set_normal(normal)
        tool.add_vertex(p)
    return tool.commit()

func set_articulation_visible(enabled: bool) -> void:
    visible = enabled

func articulation_visible() -> bool:
    return visible

func set_cross_detail_visible(enabled: bool) -> void:
    _cross_enabled = enabled
    for detail: MeshInstance3D in _cross_details:
        if is_instance_valid(detail):
            detail.visible = enabled

func cross_detail_visible() -> bool:
    return _cross_enabled

func cross_detail_count() -> int:
    return _cross_count

func cross_strip_count() -> int:
    return _cross_details.size()

func cross_source_truth() -> Dictionary:
    return {
        "heritage_record": "Urban Brussels 31125",
        "window_identity": "fenetres_a_croisee",
        "placement_semantics": "existing_east_window_panels_only",
        "dimensions_source": CROSS_DIMENSIONS_SOURCE,
        "west_special_ordination_deferred": true,
        "dimensions_claimed_surveyed": false,
        "urbis_mesh_modified": false,
        "new_openings_authored": false,
    }

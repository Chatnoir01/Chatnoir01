extends Node3D

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

var articulation_ready := false
var east_bay_count := 10
var west_bay_count := 9
var window_register_count := 2
var window_panel_count := 0
var placement_semantics := "heritage_counts_on_official_lod2_visualization_convention_not_survey"
var geometry_claimed_surveyed := false
var _panels: Array[MeshInstance3D] = []

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
    _build_wing(EAST_FROM, EAST_TO, east_bay_count, "East")
    _build_wing(WEST_FROM, WEST_TO, west_bay_count, "West")
    window_panel_count = _panels.size()
    articulation_ready = window_panel_count == 38
    set_meta("building_id", BUILDING_ID)
    set_meta("heritage_source", "urban.brussels/31125")
    set_meta("east_bays_documented", 10)
    set_meta("west_bays_documented", 9)
    set_meta("window_registers_documented", 2)
    set_meta("placement_semantics", placement_semantics)
    set_meta("geometry_changed", false)
    set_meta("runtime_approved", false)
    set_meta("realism_complete", false)
    print("GRAND_PLACE_TOWN_HALL_WINDOW_RHYTHM_READY: east=%d west=%d registers=%d panels=%d surveyed=false" % [east_bay_count, west_bay_count, window_register_count, window_panel_count])

func _build_wing(a: Vector3, b: Vector3, bays: int, label: String) -> void:
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

func set_articulation_visible(enabled: bool) -> void:
    visible = enabled

func articulation_visible() -> bool:
    return visible

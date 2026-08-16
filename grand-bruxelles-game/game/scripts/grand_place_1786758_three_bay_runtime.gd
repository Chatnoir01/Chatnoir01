extends Node3D

const OFFICIAL_NODE := "GrandPlaceOfficialLod2Next"
const CONTRACT_PATH := "res://data/qa/grand_place_1786758_three_bay_contract.json"
const BUILDING_ID := "https://databrussels.be/id/building/1786758"
const WALL_FACE_ID := "https://databrussels.be/id/buildingface/11521730"
const PLAYER_SIDE := Vector3(319.01, 1.72, -535.20)

var articulation_ready := false
var bay_count := 3
var window_register_count := 2
var window_panel_count := 0
var central_bay_emphasized := true
var placement_semantics := "shared_heritage_three_bay_on_official_wall_face_visualization_convention_not_survey"
var geometry_claimed_surveyed := false
var _panels: Array[MeshInstance3D] = []

func _ready() -> void:
    call_deferred("_bind_when_ready")

func _vec3(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return Vector3.INF
    return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))

func _read_contract() -> Dictionary:
    if not FileAccess.file_exists(CONTRACT_PATH):
        push_error("Grand-Place 1786758 three-bay contract missing")
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Grand-Place 1786758 three-bay contract invalid")
        return {}
    var data := parsed as Dictionary
    if str(data.get("schema", "")) != "grand-bruxelles-grand-place-1786758-three-bay-v1":
        push_error("Grand-Place 1786758 three-bay schema drifted")
        return {}
    if str(data.get("building_id", "")) != BUILDING_ID:
        push_error("Grand-Place 1786758 three-bay building identity drifted")
        return {}
    if bool(data.get("runtime_approved", true)) or bool(data.get("realism_complete", true)):
        push_error("Grand-Place 1786758 three-bay candidate must remain incomplete")
        return {}
    return data

func _bind_when_ready() -> void:
    var official := get_tree().root.get_node_or_null(OFFICIAL_NODE)
    for _frame: int in range(480):
        if official != null and bool(official.get("geometry_loaded")):
            break
        await get_tree().process_frame
        official = get_tree().root.get_node_or_null(OFFICIAL_NODE)
    if official == null or not bool(official.get("geometry_loaded")):
        push_error("Grand-Place 1786758 three-bay: official LoD2 missing")
        return
    if str(official.get_meta("building_id", "")) != BUILDING_ID:
        push_error("Grand-Place 1786758 three-bay: official building identity drifted")
        return

    var contract := _read_contract()
    if contract.is_empty():
        return
    var geometry := contract.get("official_geometry", {}) as Dictionary
    var semantics := contract.get("shared_discrete_semantics", {}) as Dictionary
    var visual := contract.get("visualization_convention", {}) as Dictionary
    if str(geometry.get("wall_face_id", "")) != WALL_FACE_ID:
        push_error("Grand-Place 1786758 three-bay: wall face identity drifted")
        return
    bay_count = int(semantics.get("main_bay_count", 0))
    central_bay_emphasized = bool(semantics.get("central_bay_emphasized", false))
    window_register_count = int(semantics.get("window_registers_visualized", 0))
    if bay_count != 3 or not central_bay_emphasized or window_register_count != 2:
        push_error("Grand-Place 1786758 three-bay: shared heritage semantics invalid")
        return

    var a := _vec3(geometry.get("player_facing_edge_from_game_x_y_z", []))
    var b := _vec3(geometry.get("player_facing_edge_to_game_x_y_z", []))
    if not a.is_finite() or not b.is_finite():
        push_error("Grand-Place 1786758 three-bay: official edge invalid")
        return
    var raw_registers: Variant = visual.get("register_center_y_m", [])
    if typeof(raw_registers) != TYPE_ARRAY or raw_registers.size() != 2:
        push_error("Grand-Place 1786758 three-bay: register convention invalid")
        return
    var registers := raw_registers as Array
    var panel_height := float(visual.get("panel_height_m", 0.0))
    var side_ratio := float(visual.get("side_panel_width_ratio_of_bay", 0.0))
    var central_ratio := float(visual.get("central_panel_width_ratio_of_bay", 0.0))
    var surface_offset := float(visual.get("surface_offset_m", 0.0))
    if panel_height <= 0.0 or side_ratio <= 0.0 or central_ratio <= side_ratio or central_ratio >= 0.9:
        push_error("Grand-Place 1786758 three-bay: visualization convention invalid")
        return

    var tangent := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
    var segment_length := Vector2(b.x - a.x, b.z - a.z).length()
    var bay_spacing := segment_length / float(bay_count)
    var normal := Vector3(-tangent.z, 0.0, tangent.x)
    var midpoint := (a + b) * 0.5
    if normal.dot(PLAYER_SIDE - midpoint) < 0.0:
        normal = -normal

    for register_index: int in range(registers.size()):
        for bay: int in range(bay_count):
            var t := (float(bay) + 0.5) / float(bay_count)
            var center := a.lerp(b, t)
            center.y = float(registers[register_index])
            center += normal * surface_offset
            var width_ratio := central_ratio if bay == 1 else side_ratio
            var panel := MeshInstance3D.new()
            panel.name = "R%d_B%d%s" % [register_index + 1, bay + 1, "_Central" if bay == 1 else ""]
            panel.mesh = _panel_mesh(center, tangent, normal, bay_spacing * width_ratio, panel_height)
            add_child(panel)
            _panels.append(panel)

    window_panel_count = _panels.size()
    articulation_ready = window_panel_count == 6
    set_meta("building_id", BUILDING_ID)
    set_meta("official_wall_face_id", WALL_FACE_ID)
    set_meta("heritage_sources", "urban.brussels/31126 + urban.brussels/40020")
    set_meta("shared_main_bays_documented", 3)
    set_meta("central_bay_emphasis_documented", true)
    set_meta("placement_semantics", placement_semantics)
    set_meta("geometry_changed", false)
    set_meta("runtime_approved", false)
    set_meta("realism_complete", false)
    print("GRAND_PLACE_1786758_THREE_BAY_READY: bays=3 registers=2 panels=%d central_emphasis=true surveyed=false" % window_panel_count)

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
    material.albedo_color = Color(0.055, 0.072, 0.080, 1.0)
    material.roughness = 0.26
    material.metallic = 0.04
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material.set_meta("presentation", "dark_glazing_proxy")
    material.set_meta("exact_photometry_claimed", false)
    tool.set_material(material)
    for p: Vector3 in [p0, p1, p2, p0, p2, p3]:
        tool.set_normal(normal)
        tool.add_vertex(p)
    return tool.commit()

func set_articulation_visible(enabled: bool) -> void:
    visible = enabled

func articulation_visible() -> bool:
    return visible

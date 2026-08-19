extends Node3D

const FACE_ID := "https://databrussels.be/id/buildingface/10796610"
const BUILDING_ID := "https://databrussels.be/id/building/1655673"
const HERITAGE_RECORD := 31125
const EDGE_A := Vector3(278.0758, 0.0, -482.9369)
const EDGE_B := Vector3(302.7318, 0.0, -499.9249)
const EDGE_LENGTH_M := 29.9417848499
const BAY_COUNT := 3
const OUTER_MARGIN_M := 0.72
const BAY_GAP_M := 0.42
const PANEL_BASE_M := 1.35
const PANEL_TOP_M := 19.40
const SURFACE_OFFSET_M := 0.022
const TURRET_OFFSET_M := 0.20
const TURRET_RADIUS_M := 0.48
const TURRET_HEIGHT_M := 8.80
const TURRET_CENTER_Y_M := 17.15
const TURRET_EDGE_INSET_M := 0.92
const SPIRE_HEIGHT_M := 2.40
const SPIRE_RADIUS_M := 0.46
const SPIRE_CENTER_Y_M := 22.75
const PRESENTATION_CONTRACT := "town_hall_tete_or_three_bay_gable_turret_v1"

var _presentation_root: Node3D
var _built := false


func _ready() -> void:
    call_deferred("_build_when_ready")


func _build_when_ready() -> void:
    for _frame: int in range(240):
        var official := get_node_or_null("/root/GrandPlaceOfficialLod2")
        if official != null and bool(official.get("geometry_loaded")):
            _build_presentation()
            return
        await get_tree().process_frame
    push_error("Town Hall Tete d'Or presentation: official LoD2 did not become ready")


func _edge_tangent() -> Vector3:
    var tangent := EDGE_B - EDGE_A
    tangent.y = 0.0
    return tangent.normalized()


func _face_normal() -> Vector3:
    var tangent := _edge_tangent()
    return Vector3(tangent.z, 0.0, -tangent.x).normalized()


func _world(s: float, y: float, offset: float = SURFACE_OFFSET_M) -> Vector3:
    var t := clampf(s / EDGE_LENGTH_M, 0.0, 1.0)
    var base := EDGE_A.lerp(EDGE_B, t)
    return Vector3(base.x, y, base.z) + _face_normal() * offset


func _material(color: Color, roughness: float) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    return material


func _append_quad(tool: SurfaceTool, s0: float, s1: float, y0: float, y1: float) -> void:
    var normal := _face_normal()
    var a := _world(s0, y0)
    var b := _world(s1, y0)
    var c := _world(s1, y1)
    var d := _world(s0, y1)
    for vertex: Vector3 in [a, b, c, a, c, d]:
        tool.set_normal(normal)
        tool.add_vertex(vertex)


func _make_panel(name: String, s0: float, s1: float, color: Color) -> MeshInstance3D:
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_material(_material(color, 0.90))
    _append_quad(tool, s0, s1, PANEL_BASE_M, PANEL_TOP_M)
    var instance := MeshInstance3D.new()
    instance.name = name
    instance.mesh = tool.commit()
    return instance


func _make_relief_band(name: String, s0: float, s1: float, y0: float, y1: float) -> MeshInstance3D:
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_material(_material(Color(0.86, 0.84, 0.78, 1.0), 0.84))
    _append_quad(tool, s0, s1, y0, y1)
    var instance := MeshInstance3D.new()
    instance.name = name
    instance.mesh = tool.commit()
    return instance


func _add_octagonal_turret(name: String, s: float) -> void:
    var turret := MeshInstance3D.new()
    turret.name = name
    var cylinder := CylinderMesh.new()
    cylinder.top_radius = TURRET_RADIUS_M
    cylinder.bottom_radius = TURRET_RADIUS_M
    cylinder.height = TURRET_HEIGHT_M
    cylinder.radial_segments = 8
    cylinder.rings = 1
    cylinder.material = _material(Color(0.74, 0.71, 0.65, 1.0), 0.88)
    turret.mesh = cylinder
    turret.position = _world(s, TURRET_CENTER_Y_M, TURRET_OFFSET_M)
    _presentation_root.add_child(turret)

    var spire := MeshInstance3D.new()
    spire.name = name + "Spire"
    var cone := CylinderMesh.new()
    cone.top_radius = 0.0
    cone.bottom_radius = SPIRE_RADIUS_M
    cone.height = SPIRE_HEIGHT_M
    cone.radial_segments = 8
    cone.rings = 1
    cone.material = _material(Color(0.18, 0.19, 0.19, 1.0), 0.92)
    spire.mesh = cone
    spire.position = _world(s, SPIRE_CENTER_Y_M, TURRET_OFFSET_M)
    _presentation_root.add_child(spire)


func _build_presentation() -> void:
    if _built:
        return
    if absf(EDGE_A.distance_to(EDGE_B) - EDGE_LENGTH_M) > 0.002:
        push_error("Town Hall Tete d'Or official ground-edge span drifted")
        return

    _presentation_root = Node3D.new()
    _presentation_root.name = "GrandPlaceTownHallTeteOrFacadePresentation"
    add_child(_presentation_root)

    var usable := EDGE_LENGTH_M - OUTER_MARGIN_M * 2.0 - BAY_GAP_M * 2.0
    var bay_width := usable / float(BAY_COUNT)
    var panel_colors := [
        Color(0.69, 0.665, 0.61, 1.0),
        Color(0.72, 0.695, 0.64, 1.0),
        Color(0.69, 0.665, 0.61, 1.0),
    ]
    for bay: int in range(BAY_COUNT):
        var s0 := OUTER_MARGIN_M + float(bay) * (bay_width + BAY_GAP_M)
        var s1 := s0 + bay_width
        var panel := _make_panel("TeteOrBay_%d" % (bay + 1), s0, s1, panel_colors[bay])
        panel.set_meta("presentation_only", true)
        panel.set_meta("documented_bay_index", bay + 1)
        _presentation_root.add_child(panel)

    for separator: int in range(1, BAY_COUNT):
        var center_s := OUTER_MARGIN_M + float(separator) * bay_width + float(separator - 1) * BAY_GAP_M + BAY_GAP_M * 0.5
        _presentation_root.add_child(_make_relief_band("TeteOrBaySeparator_%d" % separator, center_s - 0.18, center_s + 0.18, PANEL_BASE_M, PANEL_TOP_M))

    # Stepped-gable relief cue. The heritage source authorizes the stepped-gable
    # language, not these exact dimensions; all bands stay explicitly authored
    # presentation and remain on the already-official face plane.
    for step: int in range(5):
        var inset := float(step) * 1.35
        var y0 := 19.35 + float(step) * 0.62
        _presentation_root.add_child(_make_relief_band("TeteOrGableStep_%d" % (step + 1), 1.0 + inset, EDGE_LENGTH_M - 1.0 - inset, y0, y0 + 0.34))

    _add_octagonal_turret("TeteOrCornerTurret_W", TURRET_EDGE_INSET_M)
    _add_octagonal_turret("TeteOrCornerTurret_E", EDGE_LENGTH_M - TURRET_EDGE_INSET_M)

    _presentation_root.set_meta("presentation_contract", PRESENTATION_CONTRACT)
    _presentation_root.set_meta("source_face_id", FACE_ID)
    _presentation_root.set_meta("heritage_record", HERITAGE_RECORD)
    _presentation_root.set_meta("bay_count", BAY_COUNT)
    _presentation_root.set_meta("source_vertices_changed", false)
    _presentation_root.set_meta("collision_changed", false)
    _presentation_root.set_meta("opening_coordinates_claimed", false)
    _presentation_root.set_meta("exact_dimensions_claimed", false)
    _presentation_root.set_meta("authored_presentation", true)
    _built = true
    print("GRAND_PLACE_TOWN_HALL_TETE_OR_READY: face=10796610 bays=3 stepped_gable=true octagonal_turrets=2 presentation_only=true")


func tete_or_contract() -> Dictionary:
    return {
        "presentation_contract": PRESENTATION_CONTRACT,
        "building_id": BUILDING_ID,
        "source_face_id": FACE_ID,
        "heritage_record": HERITAGE_RECORD,
        "bay_count": BAY_COUNT,
        "ground_edge_length_m": EDGE_LENGTH_M,
        "stepped_gable_semantics": true,
        "octagonal_corner_turrets": 2,
        "source_vertices_changed": false,
        "collision_changed": false,
        "opening_coordinates_claimed": false,
        "exact_dimensions_claimed": false,
        "authored_presentation": true,
    }


func set_tete_or_visible(enabled: bool) -> void:
    if _presentation_root != null:
        _presentation_root.visible = enabled


func is_built() -> bool:
    return _built

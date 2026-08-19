extends Node3D

const FACE_ID := "https://databrussels.be/id/buildingface/10796609"
const BUILDING_ID := "https://databrussels.be/id/building/1655673"
const HERITAGE_RECORD := 31125
const EDGE_A := Vector3(263.2768, 0.0, -496.3369)
const EDGE_B := Vector3(275.1758, 0.0, -481.0559)
const EDGE_LENGTH_M := 19.3673736475
const CANONICAL_CAMERA := Vector3(319.01, 1.72, -535.20)
const BAY_COUNT := 3
const SURFACE_OFFSET_M := 0.028
const PRESENTATION_CONTRACT := "town_hall_tete_or_gable_relief_v1"

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
    push_error("Town Hall Tete d'Or gable presentation: official LoD2 did not become ready")

func _edge_tangent() -> Vector3:
    var tangent := EDGE_B - EDGE_A
    tangent.y = 0.0
    return tangent.normalized()

func _face_normal() -> Vector3:
    var tangent := _edge_tangent()
    var normal := Vector3(tangent.z, 0.0, -tangent.x).normalized()
    var midpoint := (EDGE_A + EDGE_B) * 0.5
    if normal.dot(CANONICAL_CAMERA - midpoint) < 0.0:
        normal = -normal
    return normal

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

func _make_band(name: String, s0: float, s1: float, y0: float, y1: float, color: Color) -> MeshInstance3D:
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_material(_material(color, 0.88))
    _append_quad(tool, s0, s1, y0, y1)
    var instance := MeshInstance3D.new()
    instance.name = name
    instance.mesh = tool.commit()
    instance.set_meta("presentation_only", true)
    return instance

func _add_octagonal_turret(name: String, s: float) -> void:
    var stone := _material(Color(0.79, 0.765, 0.70, 1.0), 0.88)
    var slate := _material(Color(0.16, 0.17, 0.18, 1.0), 0.94)
    var turret := MeshInstance3D.new()
    turret.name = name
    var cylinder := CylinderMesh.new()
    cylinder.top_radius = 0.38
    cylinder.bottom_radius = 0.43
    cylinder.height = 7.4
    cylinder.radial_segments = 8
    cylinder.rings = 1
    cylinder.material = stone
    turret.mesh = cylinder
    turret.position = _world(s, 18.9, 0.18)
    turret.set_meta("presentation_only", true)
    _presentation_root.add_child(turret)

    var spire := MeshInstance3D.new()
    spire.name = name + "Spire"
    var cone := CylinderMesh.new()
    cone.top_radius = 0.0
    cone.bottom_radius = 0.40
    cone.height = 2.5
    cone.radial_segments = 8
    cone.rings = 1
    cone.material = slate
    spire.mesh = cone
    spire.position = _world(s, 23.85, 0.18)
    spire.set_meta("presentation_only", true)
    _presentation_root.add_child(spire)

func _build_presentation() -> void:
    if _built:
        return
    if absf(EDGE_A.distance_to(EDGE_B) - EDGE_LENGTH_M) > 0.002:
        push_error("Town Hall Tete d'Or gable official ground-edge span drifted")
        return

    _presentation_root = Node3D.new()
    _presentation_root.name = "GrandPlaceTownHallTeteOrGablePresentation"
    add_child(_presentation_root)

    var stone_light := Color(0.82, 0.795, 0.73, 1.0)
    var stone_mid := Color(0.72, 0.695, 0.63, 1.0)

    # Three-bay rhythm only: shallow vertical relief strips, not authored openings.
    var margin := 0.75
    var usable := EDGE_LENGTH_M - margin * 2.0
    var bay_width := usable / float(BAY_COUNT)
    for divider: int in range(BAY_COUNT + 1):
        var center_s := margin + float(divider) * bay_width
        _presentation_root.add_child(_make_band(
            "TeteOrBayRelief_%d" % divider,
            center_s - 0.16,
            center_s + 0.16,
            1.2,
            19.6,
            stone_mid
        ))

    # Two horizontal level cues preserve the three-storey reading documented for
    # the gothic wings while remaining authored presentation, not survey levels.
    for level_index: int in range(2):
        var y := 7.4 if level_index == 0 else 13.35
        _presentation_root.add_child(_make_band(
            "TeteOrLevelBand_%d" % (level_index + 1),
            0.9,
            EDGE_LENGTH_M - 0.9,
            y - 0.14,
            y + 0.14,
            stone_light
        ))

    # Stepped-gable cue. Each band narrows toward the official source apex and
    # never replaces the underlying white-stone face.
    var step_specs := [
        [1.35, EDGE_LENGTH_M - 1.35, 19.6],
        [2.65, EDGE_LENGTH_M - 2.65, 22.4],
        [4.00, EDGE_LENGTH_M - 4.00, 25.2],
        [5.35, EDGE_LENGTH_M - 5.35, 28.0],
        [6.75, EDGE_LENGTH_M - 6.75, 30.8],
        [8.15, EDGE_LENGTH_M - 8.15, 33.6]
    ]
    for step_index: int in range(step_specs.size()):
        var spec: Array = step_specs[step_index]
        var y := float(spec[2])
        _presentation_root.add_child(_make_band(
            "TeteOrGableStep_%d" % (step_index + 1),
            float(spec[0]),
            float(spec[1]),
            y,
            y + 0.38,
            stone_light
        ))

    # One silhouette cue at each bounding corner of this exact face. Urban 31125
    # documents four octagonal corner turrets on the gothic wings; this face uses
    # two bounded corner cues without claiming surveyed turret coordinates.
    _add_octagonal_turret("TeteOrCornerTurret_A", 0.72)
    _add_octagonal_turret("TeteOrCornerTurret_B", EDGE_LENGTH_M - 0.72)

    _presentation_root.set_meta("presentation_contract", PRESENTATION_CONTRACT)
    _presentation_root.set_meta("source_face_id", FACE_ID)
    _presentation_root.set_meta("heritage_record", HERITAGE_RECORD)
    _presentation_root.set_meta("bay_count", BAY_COUNT)
    _presentation_root.set_meta("source_vertices_changed", false)
    _presentation_root.set_meta("collision_changed", false)
    _presentation_root.set_meta("opening_coordinates_claimed", false)
    _presentation_root.set_meta("exact_dimensions_claimed", false)
    _presentation_root.set_meta("statuary_authored", false)
    _presentation_root.set_meta("reused_10796610_presentation", false)
    _built = true
    print("GRAND_PLACE_TOWN_HALL_TETE_OR_GABLE_READY: face=10796609 bays=3 stepped_gable=true corner_turret_cues=2 presentation_only=true")

func presentation_contract() -> Dictionary:
    return {
        "presentation_contract": PRESENTATION_CONTRACT,
        "building_id": BUILDING_ID,
        "source_face_id": FACE_ID,
        "heritage_record": HERITAGE_RECORD,
        "bay_count": BAY_COUNT,
        "ground_edge_length_m": EDGE_LENGTH_M,
        "stepped_gable_semantics": true,
        "corner_turret_cues": 2,
        "source_vertices_changed": false,
        "collision_changed": false,
        "opening_coordinates_claimed": false,
        "exact_dimensions_claimed": false,
        "statuary_authored": false,
        "reused_10796610_presentation": false,
        "authored_presentation": true
    }

func set_presentation_visible(enabled: bool) -> void:
    if _presentation_root != null:
        _presentation_root.visible = enabled

func is_built() -> bool:
    return _built

extends Node3D

## Bruxelles-Central / Brussel-Centraal source-backed LABO_BRUT review.
## Architectural identity is constrained by Urban 30201. Dimensions and the
## temporary game anchor are presentation conventions until authoritative UrbIS
## Central geometry is materialized; this runtime may therefore never promote
## itself to JOUABLE.

const IDENTITY_PATH := "res://data/visual/central_station_identity.json"
const CENTRAL_REVIEW_ANCHOR := Vector3(647.68, 0.0, -407.70)
const STATION_ROOT_NAME := "CentralStationUrban30201"
const EXPECTED_UPPER_BAYS := 9
const EXPECTED_ENTRANCE_COLUMNS := 4

var last_stats: Dictionary = {
    "buildings": 0,
    "street_surfaces": 0,
    "upper_bays": 0,
    "entrance_columns": 0,
}

var _identity_failure := false
var _station_root: Node3D
var _white_stone: StandardMaterial3D
var _blue_stone: StandardMaterial3D
var _bronze: StandardMaterial3D
var _glass: StandardMaterial3D
var _canopy: StandardMaterial3D
var _paving: StandardMaterial3D


func _ready() -> void:
    var identity := _read_identity()
    if not _identity_allowed(identity):
        _identity_failure = true
        push_error("Central station LABO: Urban 30201 identity contract invalid")
        return
    _make_materials()
    _build_review_forecourt()
    _build_station(identity)
    if _station_root == null:
        _identity_failure = true
        push_error("Central station LABO: review station build failed")
        return
    last_stats["buildings"] = 1
    last_stats["street_surfaces"] = 1
    print(
        "CENTRAL_STATION_LABO_READY urban_id=30201 bays=%d columns=%d authoritative_urbis=false promotion=false" %
        [last_stats["upper_bays"], last_stats["entrance_columns"]]
    )


func _read_identity() -> Dictionary:
    if not FileAccess.file_exists(IDENTITY_PATH):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(IDENTITY_PATH))
    return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}


func _identity_allowed(identity: Dictionary) -> bool:
    if str(identity.get("schema", "")) != "grand-bruxelles-central-station-identity-v1":
        return false
    var target := identity.get("target", {}) as Dictionary
    if str(target.get("quality", "")) != "LABO_BRUT" or bool(target.get("jouable", true)):
        return false
    var source := identity.get("heritage_source", {}) as Dictionary
    if int(source.get("urban_id", -1)) != 30201:
        return false
    var contract := identity.get("presentation_contract", {}) as Dictionary
    if bool(contract.get("procedural_dimensions_are_source_measured", true)):
        return false
    if bool(contract.get("official_urbis_footprint_active", true)):
        return false
    if bool(contract.get("official_urbis_lod2_active", true)):
        return false
    if bool(contract.get("surrounding_regional_osm_active", true)):
        return false
    if not bool(contract.get("additive_review_geometry_only", false)):
        return false
    return not bool(contract.get("promotion_allowed", true))


func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
    var result := StandardMaterial3D.new()
    result.albedo_color = color
    result.roughness = roughness
    result.metallic = metallic
    result.cull_mode = BaseMaterial3D.CULL_DISABLED
    return result


func _make_materials() -> void:
    _white_stone = _material(Color(0.70, 0.69, 0.64, 1.0), 0.88)
    _blue_stone = _material(Color(0.22, 0.25, 0.27, 1.0), 0.82)
    _bronze = _material(Color(0.22, 0.16, 0.09, 1.0), 0.48, 0.48)
    _glass = _material(Color(0.10, 0.19, 0.24, 1.0), 0.20, 0.12)
    _canopy = _material(Color(0.17, 0.18, 0.18, 1.0), 0.54, 0.32)
    _paving = _material(Color(0.36, 0.36, 0.35, 1.0), 0.94)


func _add_box(parent: Node3D, node_name: String, size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh.material = material
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    instance.position = position
    parent.add_child(instance)
    return instance


func _add_column(parent: Node3D, index: int, position: Vector3) -> MeshInstance3D:
    var mesh := CylinderMesh.new()
    mesh.top_radius = 0.34
    mesh.bottom_radius = 0.38
    mesh.height = 4.35
    mesh.radial_segments = 16
    mesh.material = _white_stone
    var instance := MeshInstance3D.new()
    instance.name = "MainEntranceColumn_%02d" % index
    instance.mesh = mesh
    instance.position = position
    parent.add_child(instance)
    return instance


func _add_label(parent: Node3D, node_name: String, text_value: String, position: Vector3) -> Label3D:
    var label := Label3D.new()
    label.name = node_name
    label.text = text_value
    label.font_size = 42
    label.outline_size = 8
    label.position = position
    label.modulate = Color(0.90, 0.90, 0.84, 1.0)
    parent.add_child(label)
    return label


func _build_review_forecourt() -> void:
    var pavement := MeshInstance3D.new()
    pavement.name = "CentralReviewForecourt"
    var plane := PlaneMesh.new()
    plane.size = Vector2(76.0, 46.0)
    plane.material = _paving
    pavement.mesh = plane
    pavement.position = CENTRAL_REVIEW_ANCHOR + Vector3(0.0, 0.015, 17.0)
    add_child(pavement)

    var body := StaticBody3D.new()
    body.name = "CentralReviewForecourtCollision"
    var shape_node := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(76.0, 0.16, 46.0)
    shape_node.shape = shape
    body.position = CENTRAL_REVIEW_ANCHOR + Vector3(0.0, -0.08, 17.0)
    body.add_child(shape_node)
    add_child(body)


func _build_station(identity: Dictionary) -> void:
    _station_root = Node3D.new()
    _station_root.name = STATION_ROOT_NAME
    _station_root.position = CENTRAL_REVIEW_ANCHOR
    _station_root.set_meta("source_urban_id", 30201)
    _station_root.set_meta("source_record", "Gare Centrale")
    _station_root.set_meta("quality", "LABO_BRUT")
    _station_root.set_meta("authoritative_urbis_alignment", false)
    _station_root.set_meta("procedural_dimensions_are_visualization_convention", true)
    _station_root.set_meta("promotion_allowed", false)
    _station_root.set_meta("identity_schema", str(identity.get("schema", "")))
    add_child(_station_root)

    # Conservative station massing only. The heritage record establishes the
    # five-level + mezzanine reading and trapezoidal block, not these dimensions.
    _add_box(_station_root, "StationMassing", Vector3(64.0, 20.0, 25.0), Vector3(0.0, 10.0, -10.5), _white_stone)
    _add_box(_station_root, "BlueStoneBase", Vector3(62.5, 1.15, 1.0), Vector3(0.0, 0.58, 2.25), _blue_stone)
    _add_box(_station_root, "BlueStoneCrown", Vector3(63.0, 0.72, 1.0), Vector3(0.0, 19.62, 2.20), _blue_stone)

    # Concave-reading main entrance: three shallow front segments establish the
    # heritage-described recess without pretending to be survey geometry.
    var entrance := Node3D.new()
    entrance.name = "MainEntranceConcaveReview"
    entrance.position = Vector3(0.0, 0.0, 2.55)
    _station_root.add_child(entrance)
    var left := _add_box(entrance, "EntranceApronLeft", Vector3(11.0, 4.2, 0.55), Vector3(-10.5, 2.1, -0.15), _white_stone)
    left.rotation_degrees.y = -5.0
    var center := _add_box(entrance, "EntranceApronCenter", Vector3(10.5, 4.2, 0.55), Vector3(0.0, 2.1, -0.62), _white_stone)
    center.rotation_degrees.y = 0.0
    var right := _add_box(entrance, "EntranceApronRight", Vector3(11.0, 4.2, 0.55), Vector3(10.5, 2.1, -0.15), _white_stone)
    right.rotation_degrees.y = 5.0

    # Four supports under the main canopy, explicitly sourced as a count only.
    for index: int in range(EXPECTED_ENTRANCE_COLUMNS):
        var x := -8.1 + float(index) * 5.4
        _add_column(entrance, index, Vector3(x, 2.18, 2.15))
        last_stats["entrance_columns"] = int(last_stats["entrance_columns"]) + 1

    _add_box(entrance, "MainEntranceCanopy", Vector3(27.5, 0.42, 5.2), Vector3(0.0, 4.45, 1.55), _canopy)
    _add_box(entrance, "EntranceOpeningDark", Vector3(21.0, 3.15, 0.28), Vector3(0.0, 1.9, 0.18), _glass)
    _add_box(entrance, "ReliefPanelLeft", Vector3(3.4, 2.25, 0.20), Vector3(-14.2, 2.15, 0.28), _blue_stone)
    _add_box(entrance, "ReliefPanelRight", Vector3(3.4, 2.25, 0.20), Vector3(14.2, 2.15, 0.28), _blue_stone)

    # Nine upper bow-window bays are a documented source invariant. The bay
    # dimensions/cadence below remain explicitly non-survey presentation data.
    var upper := Node3D.new()
    upper.name = "UpperNineBayRhythm"
    _station_root.add_child(upper)
    var start_x := -25.6
    var spacing := 6.4
    for index: int in range(EXPECTED_UPPER_BAYS):
        var x := start_x + float(index) * spacing
        _add_box(upper, "UpperBayGlass_%02d" % index, Vector3(4.25, 10.5, 0.30), Vector3(x, 11.9, 2.66), _glass)
        _add_box(upper, "UpperBayBronzeLeft_%02d" % index, Vector3(0.18, 10.65, 0.38), Vector3(x - 2.16, 11.9, 2.55), _bronze)
        _add_box(upper, "UpperBayBronzeRight_%02d" % index, Vector3(0.18, 10.65, 0.38), Vector3(x + 2.16, 11.9, 2.55), _bronze)
        for bar: int in range(3):
            _add_box(
                upper,
                "UpperBayHorizontal_%02d_%02d" % [index, bar],
                Vector3(4.25, 0.15, 0.38),
                Vector3(x, 8.4 + float(bar) * 3.3, 2.55),
                _bronze
            )
        last_stats["upper_bays"] = int(last_stats["upper_bays"]) + 1

    _add_label(_station_root, "SignBruxellesCentral", "BRUXELLES CENTRAL", Vector3(-11.5, 5.55, 3.05))
    _add_label(_station_root, "SignBrusselCentraal", "BRUSSEL CENTRAAL", Vector3(11.5, 5.55, 3.05))

    _add_station_collision()


func _add_station_collision() -> void:
    var body := StaticBody3D.new()
    body.name = "CentralStationReviewCollision"
    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(64.0, 20.0, 25.0)
    collision.shape = shape
    body.position = Vector3(0.0, 10.0, -10.5)
    body.add_child(collision)
    _station_root.add_child(body)


func identity_failure() -> bool:
    return _identity_failure


func station_root() -> Node3D:
    return _station_root


func review_anchor() -> Vector3:
    return CENTRAL_REVIEW_ANCHOR

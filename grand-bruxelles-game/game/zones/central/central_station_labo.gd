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

var last_stats: Dictionary = {"buildings": 0, "street_surfaces": 0, "upper_bays": 0, "entrance_columns": 0}
var _identity_failure := false
var _station_root: Node3D
var _white_stone: StandardMaterial3D
var _white_stone_shadow: StandardMaterial3D
var _blue_stone: StandardMaterial3D
var _bronze: StandardMaterial3D
var _glass: StandardMaterial3D
var _glass_dark: StandardMaterial3D
var _canopy: StandardMaterial3D
var _paving: StandardMaterial3D
var _relief: StandardMaterial3D

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
        return
    last_stats["buildings"] = 1
    last_stats["street_surfaces"] = 1
    print("CENTRAL_STATION_LABO_READY urban_id=30201 bays=%d columns=%d authoritative_urbis=false promotion=false" % [last_stats["upper_bays"], last_stats["entrance_columns"]])

func _read_identity() -> Dictionary:
    if not FileAccess.file_exists(IDENTITY_PATH): return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(IDENTITY_PATH))
    return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}

func _identity_allowed(identity: Dictionary) -> bool:
    if str(identity.get("schema", "")) != "grand-bruxelles-central-station-identity-v1": return false
    var target := identity.get("target", {}) as Dictionary
    if str(target.get("quality", "")) != "LABO_BRUT" or bool(target.get("jouable", true)): return false
    var source := identity.get("heritage_source", {}) as Dictionary
    if int(source.get("urban_id", -1)) != 30201: return false
    var contract := identity.get("presentation_contract", {}) as Dictionary
    if bool(contract.get("procedural_dimensions_are_source_measured", true)): return false
    if bool(contract.get("official_urbis_footprint_active", true)): return false
    if bool(contract.get("official_urbis_lod2_active", true)): return false
    if bool(contract.get("surrounding_regional_osm_active", true)): return false
    if not bool(contract.get("additive_review_geometry_only", false)): return false
    return not bool(contract.get("promotion_allowed", true))

func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
    var result := StandardMaterial3D.new(); result.albedo_color = color; result.roughness = roughness; result.metallic = metallic; result.cull_mode = BaseMaterial3D.CULL_DISABLED; return result

func _make_materials() -> void:
    _white_stone = _material(Color(0.73, 0.71, 0.65, 1.0), 0.91)
    _white_stone_shadow = _material(Color(0.58, 0.57, 0.53, 1.0), 0.93)
    _blue_stone = _material(Color(0.20, 0.23, 0.25, 1.0), 0.84)
    _bronze = _material(Color(0.19, 0.13, 0.075, 1.0), 0.43, 0.52)
    _glass = _material(Color(0.075, 0.15, 0.18, 1.0), 0.18, 0.16)
    _glass_dark = _material(Color(0.035, 0.065, 0.075, 1.0), 0.24, 0.08)
    _canopy = _material(Color(0.15, 0.16, 0.16, 1.0), 0.50, 0.38)
    _paving = _material(Color(0.35, 0.35, 0.34, 1.0), 0.95)
    _relief = _material(Color(0.36, 0.30, 0.22, 1.0), 0.78, 0.10)

func _add_box(parent: Node3D, node_name: String, size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
    var mesh := BoxMesh.new(); mesh.size = size; mesh.material = material
    var instance := MeshInstance3D.new(); instance.name = node_name; instance.mesh = mesh; instance.position = position; parent.add_child(instance); return instance

func _add_column(parent: Node3D, index: int, position: Vector3) -> MeshInstance3D:
    var mesh := CylinderMesh.new(); mesh.top_radius = 0.36; mesh.bottom_radius = 0.41; mesh.height = 4.55; mesh.radial_segments = 24; mesh.material = _white_stone
    var instance := MeshInstance3D.new(); instance.name = "MainEntranceColumn_%02d" % index; instance.mesh = mesh; instance.position = position; parent.add_child(instance); return instance

func _add_label(parent: Node3D, node_name: String, text_value: String, position: Vector3) -> Label3D:
    var label := Label3D.new(); label.name = node_name; label.text = text_value; label.font_size = 64; label.outline_size = 10; label.pixel_size = 0.0105; label.position = position; label.modulate = Color(0.13, 0.12, 0.10, 1.0); label.outline_modulate = Color(0.83, 0.80, 0.70, 0.60); label.double_sided = true; parent.add_child(label); return label

func _build_review_forecourt() -> void:
    var pavement := MeshInstance3D.new(); pavement.name = "CentralReviewForecourt"
    var plane := PlaneMesh.new(); plane.size = Vector2(96.0, 58.0); plane.material = _paving; pavement.mesh = plane; pavement.position = CENTRAL_REVIEW_ANCHOR + Vector3(0.0, 0.015, 19.0); add_child(pavement)
    for index: int in range(6):
        _add_box(self, "CentralReviewPavingBand_%02d" % index, Vector3(90.0, 0.025, 0.10), CENTRAL_REVIEW_ANCHOR + Vector3(0.0, 0.035, 3.0 + float(index) * 8.0), _blue_stone)
    # Street-scale review furniture: deliberately generic, not surveyed assets.
    for side: int in [-1, 1]:
        for index: int in range(4):
            var x := float(side) * (20.0 + float(index) * 5.0)
            _add_box(self, "CentralReviewBollard_%d_%02d" % [side, index], Vector3(0.28, 0.85, 0.28), CENTRAL_REVIEW_ANCHOR + Vector3(x, 0.43, 8.0), _blue_stone)
    for side: int in [-1, 1]:
        var lamp := Node3D.new(); lamp.name = "CentralReviewLamp_%d" % side; lamp.position = CENTRAL_REVIEW_ANCHOR + Vector3(float(side) * 28.0, 0.0, 17.0); add_child(lamp)
        _add_box(lamp, "Pole", Vector3(0.18, 6.0, 0.18), Vector3(0.0, 3.0, 0.0), _blue_stone)
        _add_box(lamp, "Head", Vector3(0.95, 0.25, 0.45), Vector3(0.0, 5.9, 0.0), _canopy)
    var body := StaticBody3D.new(); body.name = "CentralReviewForecourtCollision"
    var shape_node := CollisionShape3D.new(); var shape := BoxShape3D.new(); shape.size = Vector3(96.0, 0.16, 58.0); shape_node.shape = shape; body.position = CENTRAL_REVIEW_ANCHOR + Vector3(0.0, -0.08, 19.0); body.add_child(shape_node); add_child(body)

func _build_station(identity: Dictionary) -> void:
    _station_root = Node3D.new(); _station_root.name = STATION_ROOT_NAME; _station_root.position = CENTRAL_REVIEW_ANCHOR
    _station_root.set_meta("source_urban_id", 30201); _station_root.set_meta("source_record", "Gare Centrale"); _station_root.set_meta("quality", "LABO_BRUT"); _station_root.set_meta("authoritative_urbis_alignment", false); _station_root.set_meta("procedural_dimensions_are_visualization_convention", true); _station_root.set_meta("promotion_allowed", false); _station_root.set_meta("identity_schema", str(identity.get("schema", ""))); add_child(_station_root)
    _add_box(_station_root, "StationMassing", Vector3(66.0, 21.0, 27.0), Vector3(0.0, 10.5, -11.0), _white_stone)
    _add_box(_station_root, "BlueStoneBase", Vector3(65.0, 1.10, 1.25), Vector3(0.0, 0.55, 2.05), _blue_stone)
    _add_box(_station_root, "FirstFloorShadowBand", Vector3(64.6, 0.35, 0.58), Vector3(0.0, 5.75, 2.48), _white_stone_shadow)
    _add_box(_station_root, "BlueStoneCrown", Vector3(65.2, 0.72, 1.18), Vector3(0.0, 20.62, 2.10), _blue_stone)
    _add_box(_station_root, "RoofParapet", Vector3(64.8, 0.65, 1.40), Vector3(0.0, 21.25, 1.86), _white_stone)
    _build_main_entrance(); _build_upper_nine_bays(); _build_ground_floor_wings(); _build_side_elevations(); _build_roofline_details(); _add_station_collision()

func _build_main_entrance() -> void:
    var entrance := Node3D.new(); entrance.name = "MainEntranceConcaveReview"; entrance.position = Vector3(0.0, 0.0, 2.68); _station_root.add_child(entrance)
    var left := _add_box(entrance, "EntranceApronLeft", Vector3(11.8, 4.55, 0.70), Vector3(-11.0, 2.30, -0.02), _white_stone); left.rotation_degrees.y = -7.0
    _add_box(entrance, "EntranceApronCenter", Vector3(11.0, 4.55, 0.70), Vector3(0.0, 2.30, -0.72), _white_stone)
    var right := _add_box(entrance, "EntranceApronRight", Vector3(11.8, 4.55, 0.70), Vector3(11.0, 2.30, -0.02), _white_stone); right.rotation_degrees.y = 7.0
    _add_box(entrance, "EntranceOpeningDark", Vector3(22.8, 3.35, 0.32), Vector3(0.0, 2.00, 0.12), _glass_dark)
    for door_index: int in range(5):
        var door_x := -8.8 + float(door_index) * 4.4
        _add_box(entrance, "EntranceDoorGlass_%02d" % door_index, Vector3(3.55, 2.90, 0.16), Vector3(door_x, 1.72, 0.31), _glass)
        _add_box(entrance, "EntranceDoorBronze_%02d" % door_index, Vector3(0.11, 3.00, 0.24), Vector3(door_x + 1.77, 1.72, 0.25), _bronze)
    for index: int in range(EXPECTED_ENTRANCE_COLUMNS):
        var x := -8.25 + float(index) * 5.50; _add_column(entrance, index, Vector3(x, 2.28, 2.25)); last_stats["entrance_columns"] = int(last_stats["entrance_columns"]) + 1
    _add_box(entrance, "MainEntranceCanopy", Vector3(29.2, 0.46, 5.9), Vector3(0.0, 4.72, 1.78), _canopy)
    _add_box(entrance, "CanopyBronzeLip", Vector3(29.4, 0.15, 0.20), Vector3(0.0, 4.51, 4.70), _bronze)
    _add_box(entrance, "ReliefPanelLeft", Vector3(3.8, 2.45, 0.23), Vector3(-15.1, 2.30, 0.37), _relief); _add_box(entrance, "ReliefPanelRight", Vector3(3.8, 2.45, 0.23), Vector3(15.1, 2.30, 0.37), _relief); _add_box(entrance, "InauguralPlaque", Vector3(1.35, 1.65, 0.20), Vector3(0.0, 5.72, 0.37), _blue_stone)
    _add_label(_station_root, "SignBruxellesCentral", "BRUXELLES CENTRAL", Vector3(-10.6, 5.70, 3.18)); _add_label(_station_root, "SignBrusselCentraal", "BRUSSEL CENTRAAL", Vector3(10.6, 5.70, 3.18))

func _build_upper_nine_bays() -> void:
    var upper := Node3D.new(); upper.name = "UpperNineBayRhythm"; _station_root.add_child(upper)
    for index: int in range(EXPECTED_UPPER_BAYS):
        var x := -25.6 + float(index) * 6.4
        _add_box(upper, "UpperBayRecess_%02d" % index, Vector3(4.82, 11.25, 0.22), Vector3(x, 13.05, 2.57), _white_stone_shadow)
        _add_box(upper, "UpperBayGlass_%02d" % index, Vector3(4.22, 10.65, 0.24), Vector3(x, 13.05, 2.74), _glass)
        _add_box(upper, "UpperBayBronzeLeft_%02d" % index, Vector3(0.15, 10.75, 0.34), Vector3(x - 2.10, 13.05, 2.78), _bronze); _add_box(upper, "UpperBayBronzeRight_%02d" % index, Vector3(0.15, 10.75, 0.34), Vector3(x + 2.10, 13.05, 2.78), _bronze); _add_box(upper, "UpperBayBronzeMid_%02d" % index, Vector3(0.12, 10.65, 0.34), Vector3(x, 13.05, 2.79), _bronze)
        for bar: int in range(5): _add_box(upper, "UpperBayHorizontal_%02d_%02d" % [index, bar], Vector3(4.20, 0.12, 0.34), Vector3(x, 8.65 + float(bar) * 2.20, 2.79), _bronze)
        last_stats["upper_bays"] = int(last_stats["upper_bays"]) + 1
    for pier_index: int in range(10): _add_box(upper, "RecessedTrumeau_%02d" % pier_index, Vector3(1.18, 11.65, 0.48), Vector3(-28.8 + float(pier_index) * 6.4, 13.05, 2.46), _white_stone)

func _build_ground_floor_wings() -> void:
    for side: int in [-1, 1]:
        for index: int in range(3):
            var x := float(side) * (20.6 + float(index) * 4.0)
            _add_box(_station_root, "GroundWingGlass_%d_%02d" % [side, index], Vector3(3.05, 3.15, 0.24), Vector3(x, 2.15, 2.72), _glass_dark); _add_box(_station_root, "GroundWingHead_%d_%02d" % [side, index], Vector3(3.35, 0.22, 0.32), Vector3(x, 3.76, 2.78), _bronze); _add_box(_station_root, "GroundWingSill_%d_%02d" % [side, index], Vector3(3.35, 0.18, 0.32), Vector3(x, 0.56, 2.78), _blue_stone)

func _build_side_elevations() -> void:
    for side: int in [-1, 1]:
        var x := float(side) * 33.12
        for index: int in range(6):
            var z := -21.0 + float(index) * 4.2
            _add_box(_station_root, "SideGroundGlass_%d_%02d" % [side, index], Vector3(0.25, 3.10, 3.20), Vector3(x, 2.10, z), _glass_dark)
            for floor_index: int in range(3): _add_box(_station_root, "SideUpperWindow_%d_%02d_%02d" % [side, index, floor_index], Vector3(0.28, 2.40, 2.85), Vector3(x, 8.25 + float(floor_index) * 4.05, z), _glass)
        for pier_index: int in range(7): _add_box(_station_root, "SideLesene_%d_%02d" % [side, pier_index], Vector3(0.42, 13.2, 0.55), Vector3(x + float(side) * 0.05, 13.0, -23.1 + float(pier_index) * 4.2), _white_stone_shadow)
    var bow := Node3D.new(); bow.name = "BoulevardImperatriceThreeSidedBowWindowReview"; bow.position = Vector3(33.45, 12.8, -8.2); _station_root.add_child(bow)
    _add_box(bow, "BowCenter", Vector3(0.30, 8.6, 4.2), Vector3(0.55, 0.0, 0.0), _glass)
    var bow_front := _add_box(bow, "BowFrontFacet", Vector3(0.28, 8.6, 2.4), Vector3(0.28, 0.0, 2.85), _glass); bow_front.rotation_degrees.y = -26.0
    var bow_rear := _add_box(bow, "BowRearFacet", Vector3(0.28, 8.6, 2.4), Vector3(0.28, 0.0, -2.85), _glass); bow_rear.rotation_degrees.y = 26.0
    _add_box(bow, "BowCap", Vector3(1.25, 0.40, 8.0), Vector3(0.20, 4.50, 0.0), _blue_stone)

func _build_roofline_details() -> void:
    # Adds silhouette and depth so the surface station does not read as a bare box.
    _add_box(_station_root, "RoofSetback", Vector3(51.0, 2.0, 17.0), Vector3(0.0, 22.0, -10.0), _white_stone_shadow)
    for index: int in range(5):
        _add_box(_station_root, "RoofVent_%02d" % index, Vector3(3.0, 1.1, 2.0), Vector3(-20.0 + float(index) * 10.0, 23.35, -10.0), _blue_stone)

func _add_station_collision() -> void:
    var body := StaticBody3D.new(); body.name = "CentralStationReviewCollision"; var collision := CollisionShape3D.new(); var shape := BoxShape3D.new(); shape.size = Vector3(66.0, 21.0, 27.0); collision.shape = shape; body.position = Vector3(0.0, 10.5, -11.0); body.add_child(collision); _station_root.add_child(body)

func identity_failure() -> bool: return _identity_failure
func station_root() -> Node3D: return _station_root
func review_anchor() -> Vector3: return CENTRAL_REVIEW_ANCHOR

extends "res://game/zones/central/central_station_labo.gd"

## Street/block context for owner visual review only.
## Nothing created here is claimed as surveyed OSM/UrbIS geometry. The layer is
## deliberately separated from the Urban 30201 station identity so it can be
## replaced wholesale when authoritative Central regional data is materialized.

var _context_road: StandardMaterial3D
var _context_sidewalk: StandardMaterial3D
var _context_facade_a: StandardMaterial3D
var _context_facade_b: StandardMaterial3D
var _context_roof: StandardMaterial3D
var _context_window: StandardMaterial3D
var _context_marking: StandardMaterial3D

func _ready() -> void:
    super._ready()
    if _identity_failure or _station_root == null:
        return
    _make_context_materials()
    _build_review_street_context()
    set_meta("central_context_authoritative", false)
    set_meta("central_context_claim", "procedural_review_only_replace_with_regional_osm_urbis")
    set_meta("central_context_block_masses", 7)
    set_meta("central_context_road_segments", 3)
    print("CENTRAL_STATION_CONTEXT_LABO_READY blocks=7 roads=3 authoritative=false")

func _make_context_materials() -> void:
    _context_road = _material(Color(0.115, 0.12, 0.125, 1.0), 0.98)
    _context_sidewalk = _material(Color(0.47, 0.46, 0.43, 1.0), 0.96)
    _context_facade_a = _material(Color(0.49, 0.42, 0.34, 1.0), 0.92)
    _context_facade_b = _material(Color(0.66, 0.62, 0.53, 1.0), 0.92)
    _context_roof = _material(Color(0.16, 0.17, 0.18, 1.0), 0.90)
    _context_window = _material(Color(0.055, 0.09, 0.105, 1.0), 0.28, 0.08)
    _context_marking = _material(Color(0.82, 0.81, 0.75, 1.0), 0.90)

func _build_review_street_context() -> void:
    var context := Node3D.new()
    context.name = "CentralProceduralStreetContext"
    context.position = CENTRAL_REVIEW_ANCHOR
    context.set_meta("authoritative", false)
    context.set_meta("source_geometry", false)
    context.set_meta("purpose", "street_scale_visual_review_only")
    add_child(context)

    # Three street corridors make the station read as part of an urban block
    # instead of an isolated object on a review slab. Dimensions are conventions.
    _add_box(context, "ReviewRoad_CarrefourEurope", Vector3(92.0, 0.10, 12.0), Vector3(0.0, 0.06, 33.0), _context_road)
    _add_box(context, "ReviewRoad_Impératrice", Vector3(13.0, 0.10, 96.0), Vector3(-39.5, 0.055, -2.0), _context_road)
    _add_box(context, "ReviewRoad_Putterie", Vector3(12.0, 0.10, 88.0), Vector3(39.0, 0.055, -5.0), _context_road)

    # Raised sidewalk bands / curbs. They are deliberately not registered as
    # official ground-network surfaces.
    _add_box(context, "ReviewSidewalk_Front", Vector3(84.0, 0.22, 5.0), Vector3(0.0, 0.13, 25.0), _context_sidewalk)
    _add_box(context, "ReviewSidewalk_West", Vector3(5.0, 0.22, 82.0), Vector3(-31.0, 0.13, -5.0), _context_sidewalk)
    _add_box(context, "ReviewSidewalk_East", Vector3(5.0, 0.22, 78.0), Vector3(31.0, 0.13, -6.0), _context_sidewalk)

    # Crosswalk language at the station forecourt.
    for index: int in range(8):
        _add_box(context, "ReviewCrosswalk_%02d" % index, Vector3(2.1, 0.035, 5.6), Vector3(-14.7 + float(index) * 4.2, 0.125, 33.0), _context_marking)

    # Seven adjacent review masses frame the station at street and overview
    # scale. Their footprint, height and façade rhythm are intentionally generic.
    _build_context_block(context, "WestBlockNorth", Vector3(-55.0, 0.0, -1.0), Vector3(24.0, 25.0, 35.0), _context_facade_a, 5)
    _build_context_block(context, "WestBlockSouth", Vector3(-55.0, 0.0, 28.0), Vector3(24.0, 20.0, 18.0), _context_facade_b, 4)
    _build_context_block(context, "EastBlockNorth", Vector3(54.0, 0.0, -4.0), Vector3(22.0, 27.0, 34.0), _context_facade_b, 6)
    _build_context_block(context, "EastBlockSouth", Vector3(54.0, 0.0, 27.0), Vector3(22.0, 22.0, 20.0), _context_facade_a, 5)
    _build_context_block(context, "ForecourtOppositeWest", Vector3(-27.0, 0.0, 50.0), Vector3(35.0, 18.0, 16.0), _context_facade_b, 4)
    _build_context_block(context, "ForecourtOppositeCenter", Vector3(8.0, 0.0, 52.0), Vector3(31.0, 24.0, 18.0), _context_facade_a, 5)
    _build_context_block(context, "ForecourtOppositeEast", Vector3(39.0, 0.0, 50.0), Vector3(20.0, 20.0, 16.0), _context_facade_b, 4)

    # Street furniture / vertical rhythm in the wider frame.
    for side: int in [-1, 1]:
        for index: int in range(4):
            var pole_x := float(side) * 30.0
            var pole_z := 19.0 + float(index) * 10.0
            _add_box(context, "ContextLampPole_%d_%02d" % [side, index], Vector3(0.16, 5.6, 0.16), Vector3(pole_x, 2.8, pole_z), _blue_stone)
            _add_box(context, "ContextLampHead_%d_%02d" % [side, index], Vector3(0.75, 0.20, 0.38), Vector3(pole_x, 5.55, pole_z), _canopy)

func _build_context_block(parent: Node3D, node_name: String, ground_position: Vector3, size: Vector3, facade: Material, floors: int) -> void:
    var block := Node3D.new()
    block.name = node_name
    block.position = ground_position
    block.set_meta("authoritative", false)
    block.set_meta("procedural_context", true)
    parent.add_child(block)
    _add_box(block, "Massing", size, Vector3(0.0, size.y * 0.5, 0.0), facade)
    _add_box(block, "RoofBand", Vector3(size.x + 0.3, 0.65, size.z + 0.3), Vector3(0.0, size.y + 0.25, 0.0), _context_roof)
    var floor_height := maxf(2.7, (size.y - 2.2) / float(maxi(floors, 1)))
    var bay_count := maxi(3, int(floor(size.x / 4.2)))
    var span := size.x - 3.0
    for floor_index: int in range(floors):
        var window_y := 2.6 + float(floor_index) * floor_height
        if window_y > size.y - 1.0:
            continue
        for bay: int in range(bay_count):
            var t := 0.5 if bay_count == 1 else float(bay) / float(bay_count - 1)
            var window_x := -span * 0.5 + span * t
            _add_box(block, "Window_%02d_%02d" % [floor_index, bay], Vector3(2.15, 1.45, 0.16), Vector3(window_x, window_y, size.z * 0.5 + 0.09), _context_window)

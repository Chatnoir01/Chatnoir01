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
var _context_trim: StandardMaterial3D
var _context_shop: StandardMaterial3D
var _context_tree_trunk: StandardMaterial3D
var _context_tree_leaf: StandardMaterial3D

func _ready() -> void:
    super._ready()
    if _identity_failure or _station_root == null:
        return
    _make_context_materials()
    _build_station_review_depth()
    _build_review_street_context()
    set_meta("central_context_authoritative", false)
    set_meta("central_context_claim", "procedural_review_only_replace_with_regional_osm_urbis")
    set_meta("central_context_block_masses", 7)
    set_meta("central_context_road_segments", 3)
    set_meta("central_context_storefront_groups", 7)
    set_meta("central_context_tree_count", 6)
    print("CENTRAL_STATION_CONTEXT_LABO_READY blocks=7 roads=3 storefront_groups=7 trees=6 authoritative=false")

func _make_context_materials() -> void:
    _context_road = _material(Color(0.115, 0.12, 0.125, 1.0), 0.98)
    _context_sidewalk = _material(Color(0.47, 0.46, 0.43, 1.0), 0.96)
    _context_facade_a = _material(Color(0.49, 0.42, 0.34, 1.0), 0.92)
    _context_facade_b = _material(Color(0.66, 0.62, 0.53, 1.0), 0.92)
    _context_roof = _material(Color(0.16, 0.17, 0.18, 1.0), 0.90)
    _context_window = _material(Color(0.055, 0.09, 0.105, 1.0), 0.28, 0.08)
    _context_marking = _material(Color(0.82, 0.81, 0.75, 1.0), 0.90)
    _context_trim = _material(Color(0.30, 0.29, 0.27, 1.0), 0.94)
    _context_shop = _material(Color(0.035, 0.060, 0.070, 1.0), 0.20, 0.10)
    _context_tree_trunk = _material(Color(0.25, 0.17, 0.10, 1.0), 0.98)
    _context_tree_leaf = _material(Color(0.16, 0.27, 0.15, 1.0), 0.96)

func _build_station_review_depth() -> void:
    var detail := Node3D.new()
    detail.name = "CentralStationReviewDepth"
    detail.set_meta("authoritative", false)
    detail.set_meta("purpose", "visual_depth_only")
    _station_root.add_child(detail)

    _add_box(detail, "EntranceTransomGlass", Vector3(20.8, 0.82, 0.18), Vector3(0.0, 4.10, 3.06), _glass)
    _add_box(detail, "GroundFloorStoneRail", Vector3(63.0, 0.38, 0.34), Vector3(0.0, 4.18, 2.98), _white_stone_shadow)
    _add_box(detail, "GroundFloorBlueStoneSill", Vector3(63.0, 0.30, 0.42), Vector3(0.0, 0.32, 2.96), _blue_stone)
    for pier_index: int in range(8):
        var pier_x := -28.0 + float(pier_index) * 8.0
        if absf(pier_x) < 11.5:
            continue
        _add_box(detail, "GroundFacadePier_%02d" % pier_index, Vector3(0.72, 4.10, 0.42), Vector3(pier_x, 2.25, 3.02), _white_stone_shadow)
    for bay_index: int in range(9):
        var bay_x := -25.6 + float(bay_index) * 6.4
        _add_box(detail, "UpperBaySill_%02d" % bay_index, Vector3(4.58, 0.30, 0.36), Vector3(bay_x, 7.62, 3.00), _blue_stone)
        _add_box(detail, "UpperBayHead_%02d" % bay_index, Vector3(4.58, 0.26, 0.34), Vector3(bay_x, 18.48, 2.98), _white_stone_shadow)
    for step_index: int in range(3):
        _add_box(detail, "EntranceStep_%02d" % step_index, Vector3(26.0 - float(step_index) * 1.6, 0.10, 1.05), Vector3(0.0, 0.06 + float(step_index) * 0.08, 3.70 + float(step_index) * 0.72), _blue_stone)
    for handle_index: int in range(5):
        _add_box(detail, "EntranceDoorHandle_%02d" % handle_index, Vector3(0.08, 0.75, 0.10), Vector3(-8.8 + float(handle_index) * 4.4, 1.70, 3.06), _bronze)

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
    _add_box(context, "ReviewCurb_Front", Vector3(84.0, 0.20, 0.28), Vector3(0.0, 0.20, 27.45), _blue_stone)
    _add_box(context, "ReviewCurb_West", Vector3(0.28, 0.20, 82.0), Vector3(-33.45, 0.20, -5.0), _blue_stone)
    _add_box(context, "ReviewCurb_East", Vector3(0.28, 0.20, 78.0), Vector3(33.45, 0.20, -6.0), _blue_stone)

    # Crosswalk and lane-marking language at the station forecourt.
    for index: int in range(8):
        _add_box(context, "ReviewCrosswalk_%02d" % index, Vector3(2.1, 0.035, 5.6), Vector3(-14.7 + float(index) * 4.2, 0.125, 33.0), _context_marking)
    _add_box(context, "ReviewStopLine_West", Vector3(15.0, 0.035, 0.28), Vector3(-29.0, 0.125, 29.6), _context_marking)
    _add_box(context, "ReviewStopLine_East", Vector3(15.0, 0.035, 0.28), Vector3(29.0, 0.125, 29.6), _context_marking)
    for dash_index: int in range(10):
        _add_box(context, "ReviewFrontLaneDash_%02d" % dash_index, Vector3(3.2, 0.035, 0.18), Vector3(-42.0 + float(dash_index) * 9.2, 0.125, 36.4), _context_marking)
    for side: int in [-1, 1]:
        for dash_index: int in range(8):
            _add_box(context, "ReviewSideLaneDash_%d_%02d" % [side, dash_index], Vector3(0.18, 0.035, 3.0), Vector3(float(side) * 39.5, 0.125, -34.0 + float(dash_index) * 10.0), _context_marking)

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
    for bench_index: int in range(4):
        var bench_x := -22.0 + float(bench_index) * 14.5
        _add_box(context, "ContextBenchSeat_%02d" % bench_index, Vector3(3.2, 0.18, 0.62), Vector3(bench_x, 0.72, 22.9), _context_trim)
        _add_box(context, "ContextBenchBack_%02d" % bench_index, Vector3(3.2, 0.92, 0.16), Vector3(bench_x, 1.08, 23.22), _context_trim)
    var tree_positions := [Vector3(-25.0, 0.0, 42.0), Vector3(-15.0, 0.0, 43.5), Vector3(-5.0, 0.0, 42.0), Vector3(8.0, 0.0, 43.0), Vector3(20.0, 0.0, 42.0), Vector3(29.0, 0.0, 43.5)]
    for tree_index: int in range(tree_positions.size()):
        _build_context_tree(context, "ContextTree_%02d" % tree_index, tree_positions[tree_index])

func _build_context_tree(parent: Node3D, node_name: String, position: Vector3) -> void:
    var tree := Node3D.new()
    tree.name = node_name
    tree.position = position
    tree.set_meta("authoritative", false)
    parent.add_child(tree)
    var trunk_mesh := CylinderMesh.new()
    trunk_mesh.top_radius = 0.18
    trunk_mesh.bottom_radius = 0.24
    trunk_mesh.height = 3.2
    trunk_mesh.radial_segments = 10
    trunk_mesh.material = _context_tree_trunk
    var trunk := MeshInstance3D.new()
    trunk.name = "Trunk"
    trunk.mesh = trunk_mesh
    trunk.position = Vector3(0.0, 1.6, 0.0)
    tree.add_child(trunk)
    var crown_mesh := SphereMesh.new()
    crown_mesh.radius = 1.45
    crown_mesh.height = 2.8
    crown_mesh.radial_segments = 12
    crown_mesh.rings = 6
    crown_mesh.material = _context_tree_leaf
    var crown := MeshInstance3D.new()
    crown.name = "Crown"
    crown.mesh = crown_mesh
    crown.position = Vector3(0.0, 4.0, 0.0)
    tree.add_child(crown)

func _build_context_block(parent: Node3D, node_name: String, ground_position: Vector3, size: Vector3, facade: Material, floors: int) -> void:
    var block := Node3D.new()
    block.name = node_name
    block.position = ground_position
    block.set_meta("authoritative", false)
    block.set_meta("procedural_context", true)
    parent.add_child(block)
    _add_box(block, "Massing", size, Vector3(0.0, size.y * 0.5, 0.0), facade)
    _add_box(block, "RoofBand", Vector3(size.x + 0.3, 0.65, size.z + 0.3), Vector3(0.0, size.y + 0.25, 0.0), _context_roof)
    _add_box(block, "GroundCornice", Vector3(size.x + 0.18, 0.34, 0.34), Vector3(0.0, 4.6, size.z * 0.5 + 0.10), _context_trim)
    _add_box(block, "UpperCornice", Vector3(size.x + 0.22, 0.30, 0.34), Vector3(0.0, size.y - 1.15, size.z * 0.5 + 0.10), _context_trim)

    var shop_count := maxi(2, int(floor(size.x / 7.0)))
    var shop_span := size.x - 2.4
    for shop_index: int in range(shop_count):
        var shop_t := 0.5 if shop_count == 1 else float(shop_index) / float(shop_count - 1)
        var shop_x := -shop_span * 0.5 + shop_span * shop_t
        _add_box(block, "ShopGlass_%02d" % shop_index, Vector3(4.4, 2.65, 0.18), Vector3(shop_x, 2.00, size.z * 0.5 + 0.12), _context_shop)
        _add_box(block, "ShopLintel_%02d" % shop_index, Vector3(4.55, 0.22, 0.28), Vector3(shop_x, 3.42, size.z * 0.5 + 0.16), _context_trim)
        _add_box(block, "ShopCanopy_%02d" % shop_index, Vector3(4.1, 0.18, 1.15), Vector3(shop_x, 3.55, size.z * 0.5 + 0.64), _context_roof)

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
        if floor_index > 0:
            _add_box(block, "FloorBand_%02d" % floor_index, Vector3(size.x - 1.4, 0.14, 0.22), Vector3(0.0, window_y - 1.15, size.z * 0.5 + 0.08), _context_trim)

    for side: int in [-1, 1]:
        var side_x := float(side) * (size.x * 0.5 + 0.09)
        for side_floor: int in range(maxi(2, floors - 1)):
            var side_y := 3.2 + float(side_floor) * maxf(3.0, floor_height)
            if side_y > size.y - 1.0:
                continue
            for side_bay: int in range(2):
                _add_box(block, "SideWindow_%d_%02d_%02d" % [side, side_floor, side_bay], Vector3(0.16, 1.45, 2.15), Vector3(side_x, side_y, -2.0 + float(side_bay) * 4.0), _context_window)

    for roof_index: int in range(2):
        _add_box(block, "RoofEquipment_%02d" % roof_index, Vector3(2.8, 1.0, 2.2), Vector3(-size.x * 0.18 + float(roof_index) * size.x * 0.36, size.y + 0.85, -size.z * 0.08), _context_roof)

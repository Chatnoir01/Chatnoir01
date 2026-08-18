extends Node3D

# Large west-side Place Anneessens landmark.
# Plan geometry is exact OSM way 256375327. The heritage inventory supplies
# frontage semantics (five bays, projecting gabled bays 2/4, central loggia,
# brick + white/blue stone, slate roof) but no metric height. Vertical scale is
# therefore an explicit visualization convention, never promoted as source truth.

const SOURCE_PATH := "res://data/osm/anneessens_school_256375327.game.json"
const OSM_ID := 256375327
const ANNEESSENS_ANCHOR := Vector2(-272.04, -217.07)
const VISUAL_FLOOR_HEIGHT_M := 3.15
const VISUAL_STOREYS := 3
const VISUAL_BODY_HEIGHT_M := VISUAL_FLOOR_HEIGHT_M * VISUAL_STOREYS
const VISUAL_ROOF_CAP_M := 0.45
const FACADE_OFFSET_M := 0.10

var _brick := StandardMaterial3D.new()
var _white_stone := StandardMaterial3D.new()
var _blue_stone := StandardMaterial3D.new()
var _slate := StandardMaterial3D.new()
var _shadow := StandardMaterial3D.new()


func _ready() -> void:
    var source := _load_source()
    if source.is_empty():
        return
    _make_materials()
    var footprint := source.get("footprint", []) as Array
    var center := _center(footprint)
    _build_exact_massing(footprint, center)
    _build_main_frontage(footprint, center, source.get("heritage_contract", {}) as Dictionary)
    set_meta("source_osm_id", OSM_ID)
    set_meta("plan_geometry", "exact_osm_way")
    set_meta("vertical_geometry", "explicit_visualization_convention_not_source")
    set_meta("visual_floor_height_m", VISUAL_FLOOR_HEIGHT_M)
    print("Anneessens school hero: exact OSM footprint + heritage frontage semantics active")


func _load_source() -> Dictionary:
    if not FileAccess.file_exists(SOURCE_PATH):
        push_error("Anneessens school source missing: %s" % SOURCE_PATH)
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Anneessens school source is invalid JSON")
        return {}
    var source := parsed as Dictionary
    if int(source.get("osm_id", 0)) != OSM_ID:
        push_error("Anneessens school source has wrong OSM id")
        return {}
    if str(source.get("license", "")) != "ODbL-1.0":
        push_error("Anneessens school source has unexpected license")
        return {}
    if not (source.get("vertical_tags", {}) as Dictionary).is_empty():
        push_error("Anneessens school vertical source changed; re-evaluate visualization convention")
        return {}
    var heritage := source.get("heritage_contract", {}) as Dictionary
    if int(heritage.get("main_facade_bays", 0)) != 5:
        push_error("Anneessens school heritage frontage contract changed")
        return {}
    return source


func _make_materials() -> void:
    _brick.albedo_color = Color(0.42, 0.19, 0.11, 1.0)
    _brick.roughness = 0.93
    _white_stone.albedo_color = Color(0.80, 0.77, 0.68, 1.0)
    _white_stone.roughness = 0.88
    _blue_stone.albedo_color = Color(0.24, 0.27, 0.30, 1.0)
    _blue_stone.roughness = 0.86
    _slate.albedo_color = Color(0.10, 0.13, 0.16, 1.0)
    _slate.roughness = 0.82
    _shadow.albedo_color = Color(0.045, 0.055, 0.06, 1.0)
    _shadow.roughness = 0.42


func _center(footprint: Array) -> Vector2:
    var center := Vector2.ZERO
    for raw: Variant in footprint:
        center += Vector2(float(raw[0]), float(raw[1]))
    return center / maxf(1.0, float(footprint.size()))


func _local_polygon(footprint: Array, center: Vector2) -> PackedVector2Array:
    var polygon := PackedVector2Array()
    for raw: Variant in footprint:
        polygon.append(Vector2(float(raw[0]) - center.x, float(raw[1]) - center.y))
    return polygon


func _add_exact_slab(name: String, footprint: Array, center: Vector2, height: float, y: float, material: Material) -> CSGPolygon3D:
    var solid := CSGPolygon3D.new()
    solid.name = name
    solid.polygon = _local_polygon(footprint, center)
    solid.depth = height
    solid.rotation_degrees.x = -90.0
    solid.position = Vector3(center.x, y, center.y)
    solid.material = material
    solid.use_collision = false
    add_child(solid)
    return solid


func _build_exact_massing(footprint: Array, center: Vector2) -> void:
    _add_exact_slab("AnneessensSchoolBrickMassing", footprint, center, VISUAL_BODY_HEIGHT_M, VISUAL_BODY_HEIGHT_M, _brick)
    _add_exact_slab("AnneessensSchoolSlateCap", footprint, center, VISUAL_ROOF_CAP_M, VISUAL_BODY_HEIGHT_M + VISUAL_ROOF_CAP_M, _slate)


func _front_edge(footprint: Array, center: Vector2) -> Array[Vector2]:
    # The landmark occupies the west side of Place Anneessens. Select a real
    # footprint edge by natural player exposure: closest suitable edge midpoint
    # to the exact Anneessens player anchor, never a fabricated frontage chord.
    var best_a := Vector2.ZERO
    var best_b := Vector2.ZERO
    var best_distance := INF
    for index: int in range(footprint.size()):
        var raw_a: Variant = footprint[index]
        var raw_b: Variant = footprint[(index + 1) % footprint.size()]
        var a := Vector2(float(raw_a[0]), float(raw_a[1]))
        var b := Vector2(float(raw_b[0]), float(raw_b[1]))
        var length := a.distance_to(b)
        if length < 10.0:
            continue
        var midpoint := (a + b) * 0.5
        var distance := midpoint.distance_to(ANNEESSENS_ANCHOR)
        if distance < best_distance:
            best_distance = distance
            best_a = a
            best_b = b
    return [best_a, best_b]


func _add_facade_box(name: String, center: Vector2, direction: Vector2, width: float, height: float, y: float, depth: float, material: Material) -> CSGBox3D:
    var box := CSGBox3D.new()
    box.name = name
    box.size = Vector3(width, height, depth)
    box.position = Vector3(center.x, y, center.y)
    box.rotation.y = atan2(-direction.y, direction.x)
    box.material = material
    box.use_collision = false
    add_child(box)
    return box


func _add_gable(name: String, center: Vector2, direction: Vector2, width: float, base_y: float) -> void:
    var gable := CSGPolygon3D.new()
    gable.name = name
    gable.polygon = PackedVector2Array([
        Vector2(-width * 0.5, 0.0),
        Vector2(width * 0.5, 0.0),
        Vector2(0.0, width * 0.42),
    ])
    gable.depth = 0.34
    gable.position = Vector3(center.x, base_y, center.y)
    gable.rotation.y = atan2(-direction.y, direction.x)
    gable.material = _brick
    gable.use_collision = false
    add_child(gable)


func _build_main_frontage(footprint: Array, center: Vector2, heritage: Dictionary) -> void:
    var edge := _front_edge(footprint, center)
    var a: Vector2 = edge[0]
    var b: Vector2 = edge[1]
    var delta := b - a
    var length := delta.length()
    if length < 10.0:
        push_error("Anneessens school main exposed footprint edge unresolved")
        return
    var direction := delta / length
    var outward := Vector2(-direction.y, direction.x)
    var midpoint := (a + b) * 0.5
    if (ANNEESSENS_ANCHOR - midpoint).dot(outward) < 0.0:
        outward = -outward
    var frontage_origin := midpoint + outward * FACADE_OFFSET_M
    var bay_count := int(heritage.get("main_facade_bays", 5))
    var bay_width := length / float(bay_count)

    _add_facade_box("BlueStoneFrontBase", frontage_origin + outward * 0.08, direction, length, 0.95, 0.475, 0.22, _blue_stone)
    for floor_index: int in range(1, VISUAL_STOREYS):
        _add_facade_box(
            "WhiteStoneBand_%d" % floor_index,
            frontage_origin + outward * 0.12,
            direction,
            length,
            0.24,
            float(floor_index) * VISUAL_FLOOR_HEIGHT_M,
            0.18,
            _white_stone
        )

    for bay_index: int in range(bay_count):
        var along := -length * 0.5 + bay_width * (float(bay_index) + 0.5)
        var bay_center := frontage_origin + direction * along
        var source_bay := bay_index + 1
        if source_bay in [2, 4]:
            var projected := bay_center + outward * 0.28
            _add_facade_box(
                "ProjectingGabledBay_%d" % source_bay,
                projected,
                direction,
                bay_width * 0.88,
                VISUAL_BODY_HEIGHT_M,
                VISUAL_BODY_HEIGHT_M * 0.5,
                0.54,
                _brick
            )
            _add_gable("Gable_%d" % source_bay, projected, direction, bay_width * 0.88, VISUAL_BODY_HEIGHT_M)
        elif source_bay == 3 and bool(heritage.get("central_loggia", false)):
            _add_facade_box(
                "CentralLoggiaShadow",
                bay_center + outward * 0.30,
                direction,
                bay_width * 0.66,
                VISUAL_FLOOR_HEIGHT_M * 1.72,
                VISUAL_FLOOR_HEIGHT_M * 1.92,
                0.20,
                _shadow
            )
        else:
            for floor_index: int in range(VISUAL_STOREYS):
                _add_facade_box(
                    "Window_%d_%d" % [source_bay, floor_index],
                    bay_center + outward * 0.22,
                    direction,
                    bay_width * 0.46,
                    VISUAL_FLOOR_HEIGHT_M * 0.48,
                    VISUAL_FLOOR_HEIGHT_M * (float(floor_index) + 0.57),
                    0.14,
                    _shadow
                )

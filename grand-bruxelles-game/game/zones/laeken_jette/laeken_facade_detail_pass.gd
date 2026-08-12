extends Node3D

## Street-level façade detail for the Heysel/Atomium play area.
##
## Horizontal placement remains authoritative UrbIS geometry and vertical scale
## remains the committed DSM-DTM height dataset. This pass adds lightweight
## secondary 3D glazing/sills/ribs so nearby walls do not read as flat procedural
## boxes. The façade pattern itself is deliberately generic and must not be read as
## a surveyed copy of a specific real façade.

const BUILDINGS_PATH := "res://data/urbis/laeken_jette/buildings.game.json"
const HEIGHTS_PATH := "res://data/urbis/laeken_jette/building_heights_dsm.game.json"
const OVERRIDES_PATH := "res://data/urbis/laeken_jette/building_height_landmark_overrides.game.json"
const ATOMIUM := Vector2(224.92615906274295, -6553.143077999353)
const DETAIL_RADIUS_M := 430.0
const MAX_WINDOW_INSTANCES := 18000
const MAX_SILL_INSTANCES := 18000
const MAX_HALL_RIB_INSTANCES := 6000
const VALID_QUALITIES := ["high", "medium", "low"]

var detail_ready: bool = false
var detailed_buildings: int = 0
var detailed_halls: int = 0
var window_instances: int = 0
var sill_instances: int = 0
var hall_rib_instances: int = 0

var _glass_material: StandardMaterial3D
var _sill_material: StandardMaterial3D
var _hall_rib_material: StandardMaterial3D
var _hall_glass_material: StandardMaterial3D


func _ready() -> void:
    call_deferred("_build")


func _material(colour: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = colour
    material.roughness = roughness
    material.metallic = metallic
    return material


func _make_materials() -> void:
    _glass_material = _material(Color(0.045, 0.070, 0.085, 1.0), 0.18, 0.05)
    _sill_material = _material(Color(0.46, 0.44, 0.39, 1.0), 0.88)
    _hall_rib_material = _material(Color(0.48, 0.50, 0.50, 1.0), 0.52, 0.20)
    _hall_glass_material = _material(Color(0.065, 0.095, 0.105, 1.0), 0.16, 0.08)


func _load_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var value = JSON.parse_string(file.get_as_text())
    return value as Dictionary if typeof(value) == TYPE_DICTIONARY else {}


func _outer_rings(geometry: Dictionary) -> Array:
    var result: Array = []
    var kind := str(geometry.get("type", ""))
    var coordinates = geometry.get("coordinates", [])
    if kind == "Polygon" and coordinates is Array and not coordinates.is_empty():
        result.append(coordinates[0])
    elif kind == "MultiPolygon" and coordinates is Array:
        for polygon in coordinates:
            if polygon is Array and not polygon.is_empty():
                result.append(polygon[0])
    return result


func _ring_points(raw_ring) -> PackedVector2Array:
    var result := PackedVector2Array()
    if not raw_ring is Array:
        return result
    for raw in raw_ring:
        if raw is Array and raw.size() >= 2:
            result.append(Vector2(float(raw[0]), float(raw[1])))
    if result.size() >= 2 and result[0].distance_to(result[result.size() - 1]) < 0.001:
        result.resize(result.size() - 1)
    return result


func _centroid(points: PackedVector2Array) -> Vector2:
    if points.is_empty():
        return Vector2.ZERO
    var sum := Vector2.ZERO
    for point in points:
        sum += point
    return sum / float(points.size())


func _signed_area(points: PackedVector2Array) -> float:
    var area := 0.0
    for index in range(points.size()):
        var a := points[index]
        var b := points[(index + 1) % points.size()]
        area += a.x * b.y - b.x * a.y
    return area * 0.5


func _resolve_height(record: Dictionary, properties: Dictionary, overrides: Dictionary) -> float:
    var inspire_id := str(properties.get("INSPIRE_ID", ""))
    var override = overrides.get(inspire_id, null)
    if override is Dictionary:
        var corrected := float(override.get("height_m", -1.0))
        if corrected >= 2.0 and corrected <= 120.0:
            return corrected
    var quality := str(record.get("quality", ""))
    var raw_height = record.get("height_m", null)
    if quality in VALID_QUALITIES and raw_height != null:
        var height := float(raw_height)
        if height >= 2.0 and height <= 120.0:
            return height
    return 10.5


func _resolve_base_y(record: Dictionary, terrain: Node, points: PackedVector2Array) -> float:
    var ground_abs = record.get("ground_median_abs_m", null)
    if ground_abs != null:
        return float(ground_abs) - float(terrain.get("atomium_absolute_elevation_m"))
    var centre := _centroid(points)
    return float(terrain.call("sample_height", centre.x, centre.y))


func _box_transform(position: Vector3, yaw: float, size: Vector3) -> Transform3D:
    return Transform3D(Basis(Vector3.UP, yaw).scaled(size), position)


func _make_multimesh(node_name: String, material: Material, transforms: Array[Transform3D]) -> void:
    if transforms.is_empty():
        return
    var mesh := BoxMesh.new()
    mesh.size = Vector3.ONE
    mesh.material = material
    var multimesh := MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.mesh = mesh
    multimesh.instance_count = transforms.size()
    for index in range(transforms.size()):
        multimesh.set_instance_transform(index, transforms[index])
    var instance := MultiMeshInstance3D.new()
    instance.name = node_name
    instance.multimesh = multimesh
    add_child(instance)


func _append_residential_edge(
    windows: Array[Transform3D],
    sills: Array[Transform3D],
    a: Vector2,
    b: Vector2,
    outward: Vector2,
    base_y: float,
    height: float,
    seed: int
) -> void:
    if windows.size() >= MAX_WINDOW_INSTANCES:
        return
    var edge := b - a
    var edge_length := edge.length()
    if edge_length < 3.2:
        return
    var direction := edge / edge_length
    var floor_height := 2.95 + float(seed % 7) * 0.055
    var floors := clampi(int(floor((height - 1.0) / floor_height)), 1, 12)
    var target_bay := 2.45 + float((seed / 11) % 9) * 0.10
    var bays := clampi(int(floor(edge_length / target_bay)), 1, 28)
    var bay_width := edge_length / float(bays)
    var glass_width := clampf(bay_width * 0.57, 0.82, 1.82)
    var glass_height := clampf(floor_height * 0.48, 1.18, 1.68)
    var yaw := atan2(direction.x, direction.y)

    for floor_index in range(floors):
        var centre_y := base_y + 1.25 + float(floor_index) * floor_height
        if centre_y + glass_height * 0.5 > base_y + height - 0.45:
            break
        for bay_index in range(bays):
            if windows.size() >= MAX_WINDOW_INSTANCES:
                return
            var along := (float(bay_index) + 0.5) * bay_width
            var xz := a + direction * along + outward * 0.055
            windows.append(_box_transform(
                Vector3(xz.x, centre_y, xz.y),
                yaw,
                Vector3(0.055, glass_height, glass_width)
            ))
            if sills.size() < MAX_SILL_INSTANCES:
                sills.append(_box_transform(
                    Vector3(xz.x, centre_y - glass_height * 0.5 - 0.075, xz.y) + Vector3(outward.x, 0.0, outward.y) * 0.02,
                    yaw,
                    Vector3(0.095, 0.09, glass_width + 0.14)
                ))


func _append_hall_edge(
    ribs: Array[Transform3D],
    glass_bands: Array[Transform3D],
    a: Vector2,
    b: Vector2,
    outward: Vector2,
    base_y: float,
    height: float
) -> void:
    var edge := b - a
    var edge_length := edge.length()
    if edge_length < 5.0:
        return
    var direction := edge / edge_length
    var yaw := atan2(direction.x, direction.y)
    var rib_step := 5.6
    var rib_count := int(floor(edge_length / rib_step))
    for index in range(rib_count + 1):
        if ribs.size() >= MAX_HALL_RIB_INSTANCES:
            break
        var along := minf(float(index) * rib_step, edge_length)
        var xz := a + direction * along + outward * 0.075
        ribs.append(_box_transform(
            Vector3(xz.x, base_y + height * 0.49, xz.y),
            yaw,
            Vector3(0.18, maxf(2.5, height * 0.86), 0.32)
        ))

    if glass_bands.size() < 3000 and edge_length >= 10.0 and height >= 7.0:
        var middle := (a + b) * 0.5 + outward * 0.065
        glass_bands.append(_box_transform(
            Vector3(middle.x, base_y + minf(3.15, height * 0.28), middle.y),
            yaw,
            Vector3(0.07, clampf(height * 0.18, 1.2, 2.5), edge_length * 0.88)
        ))


func _build() -> void:
    _make_materials()
    var terrain = get_parent().get_node_or_null("LaekenTerrain")
    if terrain == null or not bool(terrain.get("terrain_loaded")):
        push_warning("LaekenFacadeDetailPass: terrain not ready")
        return

    var buildings := _load_json(BUILDINGS_PATH)
    var heights := _load_json(HEIGHTS_PATH)
    var override_doc := _load_json(OVERRIDES_PATH)
    var features = buildings.get("features", [])
    var records = heights.get("records", [])
    var overrides = override_doc.get("overrides", {})
    if not (features is Array) or not (records is Array) or features.size() != records.size():
        push_warning("LaekenFacadeDetailPass: aligned building/height data unavailable")
        return
    if not overrides is Dictionary:
        overrides = {}

    var windows: Array[Transform3D] = []
    var sills: Array[Transform3D] = []
    var hall_ribs: Array[Transform3D] = []
    var hall_glass: Array[Transform3D] = []

    for feature_index in range(features.size()):
        var feature = features[feature_index]
        var record = records[feature_index]
        if not (feature is Dictionary) or not (record is Dictionary):
            continue
        var geometry = feature.get("geometry", {})
        if not geometry is Dictionary:
            continue
        var properties = feature.get("properties", {})
        if not properties is Dictionary:
            properties = {}
        var area_m2 := float(properties.get("AREA", 0.0))
        var height := _resolve_height(record, properties, overrides)
        var seed := absi(str(properties.get("INSPIRE_ID", feature_index)).hash())
        var feature_touched := false
        var hall_touched := false

        for raw_ring in _outer_rings(geometry):
            var points := _ring_points(raw_ring)
            if points.size() < 3:
                continue
            var centre := _centroid(points)
            if centre.distance_to(ATOMIUM) > DETAIL_RADIUS_M:
                continue
            var base_y := _resolve_base_y(record, terrain, points)
            var ccw := _signed_area(points) > 0.0
            var large_hall := area_m2 >= 3500.0 or height >= 24.0

            for edge_index in range(points.size()):
                var a := points[edge_index]
                var b := points[(edge_index + 1) % points.size()]
                var edge := b - a
                if edge.length_squared() < 0.04:
                    continue
                var right := Vector2(edge.y, -edge.x).normalized()
                var outward := right if ccw else -right
                if large_hall:
                    _append_hall_edge(hall_ribs, hall_glass, a, b, outward, base_y, height)
                    hall_touched = true
                else:
                    _append_residential_edge(windows, sills, a, b, outward, base_y, height, seed + edge_index * 31)
                    feature_touched = true

        if feature_touched:
            detailed_buildings += 1
        if hall_touched:
            detailed_halls += 1

    _make_multimesh("FacadeGlassPanels", _glass_material, windows)
    _make_multimesh("FacadeStoneSills", _sill_material, sills)
    _make_multimesh("HallVerticalRibs", _hall_rib_material, hall_ribs)
    _make_multimesh("HallLowerGlassBands", _hall_glass_material, hall_glass)

    window_instances = windows.size()
    sill_instances = sills.size()
    hall_rib_instances = hall_ribs.size()
    detail_ready = window_instances > 0 and detailed_buildings > 0
    print("LAEKEN_FACADE_DETAIL_READY: buildings=%d halls=%d windows=%d sills=%d hall_ribs=%d" % [
        detailed_buildings,
        detailed_halls,
        window_instances,
        sill_instances,
        hall_rib_instances,
    ])

extends Node3D

@export_file("*.json") var data_path: String = "res://data/osm/vertical_slice_01.game.json"
@export var max_buildings: int = 260
@export var max_road_segments: int = 850
@export var build_collisions: bool = true
@export var midi_detail_radius_m: float = 300.0
@export var bourse_detail_radius_m: float = 180.0
@export_file("*.json") var hero_manifest_path: String = "res://data/urbis/heroes/manifest.json"

const MIDI_ANCHOR := Vector2(-668.5, 627.84)
const BOURSE_ANCHOR := Vector2(81.54, -664.58)
const MAJOR_ROADS := ["primary", "secondary", "tertiary"]

var _road_material: StandardMaterial3D
var _road_major_material: StandardMaterial3D
var _sidewalk_material: StandardMaterial3D
var _marking_material: StandardMaterial3D
var _rail_material: StandardMaterial3D
var _sleeper_material: StandardMaterial3D
var _roof_material: StandardMaterial3D
var _window_material: StandardMaterial3D
var _shop_material: StandardMaterial3D
var _building_materials: Array[StandardMaterial3D] = []

var _window_transforms: Array[Transform3D] = []
var _shop_transforms: Array[Transform3D] = []
var _marking_count: int = 0
var _sleeper_count: int = 0


func _ready() -> void:
    _make_materials()
    _build_from_file()


func _material(color: Color, roughness: float = 0.85, metallic: float = 0.0) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = metallic
    return material


func _make_materials() -> void:
    _road_material = _material(Color(0.105, 0.11, 0.115, 1.0), 0.96)
    _road_major_material = _material(Color(0.075, 0.08, 0.085, 1.0), 0.94)
    _sidewalk_material = _material(Color(0.40, 0.385, 0.36, 1.0), 0.92)
    _marking_material = _material(Color(0.88, 0.87, 0.80, 1.0), 0.82)
    _rail_material = _material(Color(0.19, 0.205, 0.22, 1.0), 0.42, 0.72)
    _sleeper_material = _material(Color(0.24, 0.235, 0.22, 1.0), 0.96)
    _roof_material = _material(Color(0.18, 0.19, 0.205, 1.0), 0.86)
    _window_material = _material(Color(0.045, 0.075, 0.095, 1.0), 0.24, 0.16)
    _shop_material = _material(Color(0.07, 0.115, 0.135, 1.0), 0.20, 0.20)

    _building_materials = [
        _material(Color(0.37, 0.205, 0.145, 1.0), 0.91),
        _material(Color(0.29, 0.205, 0.17, 1.0), 0.92),
        _material(Color(0.53, 0.47, 0.37, 1.0), 0.90),
        _material(Color(0.58, 0.555, 0.49, 1.0), 0.91),
        _material(Color(0.37, 0.385, 0.395, 1.0), 0.89),
        _material(Color(0.255, 0.19, 0.175, 1.0), 0.93),
    ]


func _build_from_file() -> void:
    if not FileAccess.file_exists(data_path):
        push_warning("OSM city data missing: %s" % data_path)
        return

    var text: String = FileAccess.get_file_as_string(data_path)
    var parsed: Variant = JSON.parse_string(text)
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Invalid OSM city JSON: %s" % data_path)
        return

    var city_data: Dictionary = parsed
    var roads_root := Node3D.new()
    roads_root.name = "GeneratedRoads"
    add_child(roads_root)

    var buildings_root := Node3D.new()
    buildings_root.name = "GeneratedBuildings"
    add_child(buildings_root)

    var rails_root := Node3D.new()
    rails_root.name = "GeneratedRails"
    add_child(rails_root)

    var details_root := Node3D.new()
    details_root.name = "GeneratedFacadeDetails"
    add_child(details_root)

    var road_segments: int = _build_roads(city_data.get("roads", []), roads_root)
    var building_count: int = _build_buildings(
        city_data.get("buildings", []), buildings_root, _validated_hero_replacements()
    )
    var rail_segments: int = _build_rails(city_data.get("railways", []), rails_root)
    _flush_facade_details(details_root)

    print(
        "Grand Bruxelles visual pass: %d road segments, %d buildings, %d rail segments, %d windows" %
        [road_segments, building_count, rail_segments, _window_transforms.size()]
    )


func _point(raw: Variant) -> Vector3:
    return Vector3(float(raw[0]), 0.0, float(raw[1]))


func _is_detail_zone(point: Vector3) -> bool:
    var point_2d := Vector2(point.x, point.z)
    return (
        point_2d.distance_to(MIDI_ANCHOR) <= midi_detail_radius_m
        or point_2d.distance_to(BOURSE_ANCHOR) <= bourse_detail_radius_m
    )


func _point_segment_distance(point: Vector2, start: Vector2, finish: Vector2) -> float:
    var segment := finish - start
    var length_squared := segment.length_squared()
    if length_squared <= 0.000001:
        return point.distance_to(start)
    var amount := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
    return point.distance_to(start + segment * amount)


func _footprint_intersects_detail_zone(footprint: Array) -> bool:
    if footprint.is_empty():
        return false
    for raw: Variant in footprint:
        var vertex := Vector2(float(raw[0]), float(raw[1]))
        if (
            vertex.distance_to(MIDI_ANCHOR) <= midi_detail_radius_m
            or vertex.distance_to(BOURSE_ANCHOR) <= bourse_detail_radius_m
        ):
            return true
    for edge_index: int in range(footprint.size()):
        var raw_start: Variant = footprint[edge_index]
        var raw_finish: Variant = footprint[(edge_index + 1) % footprint.size()]
        var start := Vector2(float(raw_start[0]), float(raw_start[1]))
        var finish := Vector2(float(raw_finish[0]), float(raw_finish[1]))
        if (
            _point_segment_distance(MIDI_ANCHOR, start, finish) <= midi_detail_radius_m
            or _point_segment_distance(BOURSE_ANCHOR, start, finish) <= bourse_detail_radius_m
        ):
            return true
    return false


func facade_window_count_near(anchor: Vector2, radius_m: float) -> int:
    var count := 0
    for transform: Transform3D in _window_transforms:
        if Vector2(transform.origin.x, transform.origin.z).distance_to(anchor) <= radius_m:
            count += 1
    return count


func facade_window_bounds() -> Rect2:
    if _window_transforms.is_empty():
        return Rect2()
    var first := _window_transforms[0].origin
    var min_point := Vector2(first.x, first.z)
    var max_point := min_point
    for transform: Transform3D in _window_transforms:
        var point := Vector2(transform.origin.x, transform.origin.z)
        min_point.x = minf(min_point.x, point.x)
        min_point.y = minf(min_point.y, point.y)
        max_point.x = maxf(max_point.x, point.x)
        max_point.y = maxf(max_point.y, point.y)
    return Rect2(min_point, max_point - min_point)


func _road_width_for(road: Dictionary) -> float:
    var width := float(road.get("width", 4.5))
    var road_class := str(road.get("class", ""))
    if road_class == "primary":
        return maxf(width, 10.5)
    if road_class == "secondary":
        return maxf(width, 8.5)
    if road_class == "tertiary":
        return maxf(width, 7.2)
    return width


func _build_roads(roads: Array, root: Node3D) -> int:
    var segment_count: int = 0
    for road: Dictionary in roads:
        if segment_count >= max_road_segments:
            break
        var points: Array = road.get("points", [])
        var width: float = _road_width_for(road)
        var road_class := str(road.get("class", ""))
        var material := _road_major_material if road_class in MAJOR_ROADS else _road_material
        for index: int in range(points.size() - 1):
            if segment_count >= max_road_segments:
                break
            var start: Vector3 = _point(points[index])
            var finish: Vector3 = _point(points[index + 1])
            var delta: Vector3 = finish - start
            var length: float = delta.length()
            if length < 0.75:
                continue

            var segment := CSGBox3D.new()
            segment.name = "Road_%s_%d" % [str(road.get("osm_id", "x")), index]
            segment.size = Vector3(width, 0.10, length)
            segment.position = (start + finish) * 0.5 + Vector3(0, 0.025, 0)
            segment.rotation.y = atan2(delta.x, delta.z)
            segment.material = material
            segment.use_collision = false
            root.add_child(segment)

            var midpoint := (start + finish) * 0.5
            if _is_detail_zone(midpoint) and bool(road.get("drivable", false)):
                _add_sidewalks(root, start, finish, width, road_class)
                if road_class in MAJOR_ROADS:
                    _add_lane_markings(root, start, finish)

            segment_count += 1
    return segment_count


func _add_sidewalks(root: Node3D, start: Vector3, finish: Vector3, road_width: float, road_class: String) -> void:
    var delta := finish - start
    var length := delta.length()
    if length < 1.0:
        return
    var direction := delta / length
    var perpendicular := Vector3(-direction.z, 0.0, direction.x)
    var sidewalk_width := 2.55 if road_class in ["primary", "secondary"] else 1.85
    var offset := road_width * 0.5 + sidewalk_width * 0.5 + 0.10
    var center := (start + finish) * 0.5
    var angle := atan2(delta.x, delta.z)

    for side: float in [-1.0, 1.0]:
        var pavement := CSGBox3D.new()
        pavement.size = Vector3(sidewalk_width, 0.12, length)
        pavement.position = center + perpendicular * offset * side + Vector3(0, 0.085, 0)
        pavement.rotation.y = angle
        pavement.material = _sidewalk_material
        pavement.use_collision = false
        root.add_child(pavement)


func _add_lane_markings(root: Node3D, start: Vector3, finish: Vector3) -> void:
    if _marking_count >= 260:
        return
    var delta := finish - start
    var length := delta.length()
    if length < 7.0:
        return
    var direction := delta / length
    var spacing := 8.5
    var dash_length := 3.5
    var dash_count := int(floor(length / spacing))
    var angle := atan2(delta.x, delta.z)

    for dash_index: int in range(dash_count):
        if _marking_count >= 260:
            return
        var distance := minf(length - 0.6, 1.7 + float(dash_index) * spacing)
        var dash := CSGBox3D.new()
        dash.size = Vector3(0.12, 0.025, minf(dash_length, length - distance))
        dash.position = start + direction * distance + Vector3(0, 0.09, 0)
        dash.rotation.y = angle
        dash.material = _marking_material
        dash.use_collision = false
        root.add_child(dash)
        _marking_count += 1


func _building_center(footprint: Array) -> Vector2:
    var center := Vector2.ZERO
    for raw: Variant in footprint:
        center += Vector2(float(raw[0]), float(raw[1]))
    return center / float(footprint.size())


func _building_material_for(building: Dictionary) -> StandardMaterial3D:
    var kind := str(building.get("kind", "yes"))
    if kind in ["office", "commercial", "retail", "train_station"]:
        return _building_materials[4]
    var osm_id: int = abs(int(building.get("osm_id", 0)))
    return _building_materials[osm_id % _building_materials.size()]


func _validated_hero_replacements() -> Dictionary:
    var replacements := {}
    if not FileAccess.file_exists(hero_manifest_path):
        return replacements
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(hero_manifest_path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Invalid UrbIS hero manifest: %s" % hero_manifest_path)
        return replacements
    var manifest: Dictionary = parsed
    if str(manifest.get("schema", "")) != "grand-bruxelles-urbis-hero-manifest-v1":
        push_error("Unsupported UrbIS hero manifest schema: %s" % hero_manifest_path)
        return replacements
    for raw_entry: Variant in manifest.get("heroes", []):
        if typeof(raw_entry) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = raw_entry
        var geometry_path := str(entry.get("geometry_path", ""))
        if geometry_path.is_empty() or not FileAccess.file_exists(geometry_path):
            push_error("UrbIS hero replacement geometry missing: %s" % geometry_path)
            continue
        var geometry: Variant = JSON.parse_string(FileAccess.get_file_as_string(geometry_path))
        if typeof(geometry) != TYPE_DICTIONARY or str(geometry.get("schema", "")) != "grand-bruxelles-urbis-hero-mesh-v1":
            push_error("Invalid UrbIS hero replacement geometry: %s" % geometry_path)
            continue
        for raw_osm_id: Variant in entry.get("replaces_osm_ids", []):
            replacements[int(raw_osm_id)] = true
    return replacements


func _build_buildings(buildings: Array, root: Node3D, replacement_ids: Dictionary = {}) -> int:
    var count: int = 0
    for building: Dictionary in buildings:
        if count >= max_buildings:
            break
        if replacement_ids.has(int(building.get("osm_id", 0))):
            continue
        var footprint: Array = building.get("footprint", [])
        if footprint.size() < 3:
            continue

        var center := _building_center(footprint)
        var polygon := PackedVector2Array()
        for raw: Variant in footprint:
            polygon.append(Vector2(float(raw[0]) - center.x, float(raw[1]) - center.y))

        var height: float = clampf(float(building.get("height", 10.5)), 2.8, 120.0)
        var solid := CSGPolygon3D.new()
        solid.name = "Building_%s" % str(building.get("osm_id", "x"))
        solid.polygon = polygon
        solid.depth = height
        solid.rotation_degrees.x = -90.0
        solid.position = Vector3(center.x, height, center.y)
        solid.material = _building_material_for(building)
        solid.use_collision = build_collisions
        root.add_child(solid)

        var roof := CSGPolygon3D.new()
        roof.name = "Roof_%s" % str(building.get("osm_id", "x"))
        roof.polygon = polygon
        roof.depth = 0.20
        roof.rotation_degrees.x = -90.0
        roof.position = Vector3(center.x, height + 0.10, center.y)
        roof.material = _roof_material
        roof.use_collision = false
        root.add_child(roof)

        var world_center := Vector3(center.x, 0.0, center.y)
        if _is_detail_zone(world_center) or _footprint_intersects_detail_zone(footprint):
            _queue_facade_details(footprint, height)

        count += 1
    return count


func _queue_facade_details(footprint: Array, height: float) -> void:
    if height < 6.0:
        return
    var floor_count := clampi(int(floor(height / 3.15)) - 1, 1, 7)

    for edge_index: int in range(footprint.size()):
        if _window_transforms.size() >= 2600:
            return
        var raw_a: Variant = footprint[edge_index]
        var raw_b: Variant = footprint[(edge_index + 1) % footprint.size()]
        var a := Vector2(float(raw_a[0]), float(raw_a[1]))
        var b := Vector2(float(raw_b[0]), float(raw_b[1]))
        var edge := b - a
        var edge_length := edge.length()
        if edge_length < 4.0:
            continue

        var direction := edge / edge_length
        var module_count := clampi(int(edge_length / 3.2), 1, 24)
        var step := edge_length / float(module_count + 1)
        var window_width := clampf(step * 0.58, 1.05, 1.85)
        var angle := atan2(-direction.y, direction.x)

        for module_index: int in range(module_count):
            var along := step * float(module_index + 1)
            var point := a + direction * along

            if _shop_transforms.size() < 650 and edge_length <= 30.0:
                var shop_basis := Basis(Vector3.UP, angle).scaled(Vector3(minf(2.25, step * 0.72), 2.15, 0.11))
                _shop_transforms.append(Transform3D(shop_basis, Vector3(point.x, 1.55, point.y)))

            for floor_index: int in range(floor_count):
                if _window_transforms.size() >= 2600:
                    return
                var y := 4.35 + float(floor_index) * 3.05
                if y + 0.8 >= height:
                    break
                var basis := Basis(Vector3.UP, angle).scaled(Vector3(window_width, 1.38, 0.10))
                _window_transforms.append(Transform3D(basis, Vector3(point.x, y, point.y)))


func _flush_facade_details(root: Node3D) -> void:
    if not _window_transforms.is_empty():
        var window_mesh := BoxMesh.new()
        window_mesh.size = Vector3.ONE
        window_mesh.material = _window_material
        var windows := MultiMesh.new()
        windows.transform_format = MultiMesh.TRANSFORM_3D
        windows.mesh = window_mesh
        windows.instance_count = _window_transforms.size()
        for index: int in range(_window_transforms.size()):
            windows.set_instance_transform(index, _window_transforms[index])
        var window_instance := MultiMeshInstance3D.new()
        window_instance.name = "CorridorFacadeWindows"
        window_instance.multimesh = windows
        root.add_child(window_instance)

    if not _shop_transforms.is_empty():
        var shop_mesh := BoxMesh.new()
        shop_mesh.size = Vector3.ONE
        shop_mesh.material = _shop_material
        var shops := MultiMesh.new()
        shops.transform_format = MultiMesh.TRANSFORM_3D
        shops.mesh = shop_mesh
        shops.instance_count = _shop_transforms.size()
        for index: int in range(_shop_transforms.size()):
            shops.set_instance_transform(index, _shop_transforms[index])
        var shop_instance := MultiMeshInstance3D.new()
        shop_instance.name = "CorridorShopfronts"
        shop_instance.multimesh = shops
        root.add_child(shop_instance)


func _railway_surface_visible(railway: Dictionary) -> bool:
    if railway.has("surface_visible"):
        return bool(railway.get("surface_visible", true))
    return true


func _build_rails(railways: Array, root: Node3D) -> int:
    var count: int = 0
    for railway: Dictionary in railways:
        if not _railway_surface_visible(railway):
            continue
        var points: Array = railway.get("points", [])
        for index: int in range(points.size() - 1):
            if count >= 400:
                return count
            var start: Vector3 = _point(points[index])
            var finish: Vector3 = _point(points[index + 1])
            var delta: Vector3 = finish - start
            var length: float = delta.length()
            if length < 0.75:
                continue

            var direction := delta / length
            var perpendicular := Vector3(-direction.z, 0.0, direction.x)
            var angle := atan2(delta.x, delta.z)
            for side: float in [-1.0, 1.0]:
                var rail := CSGBox3D.new()
                rail.name = "Rail_%s_%d_%s" % [str(railway.get("osm_id", "x")), index, str(side)]
                rail.size = Vector3(0.095, 0.09, length)
                rail.position = (start + finish) * 0.5 + perpendicular * 0.72 * side + Vector3(0, 0.105, 0)
                rail.rotation.y = angle
                rail.material = _rail_material
                rail.use_collision = false
                root.add_child(rail)

            if _is_detail_zone((start + finish) * 0.5):
                _add_sleepers(root, start, finish)
            count += 1
    return count


func _add_sleepers(root: Node3D, start: Vector3, finish: Vector3) -> void:
    if _sleeper_count >= 180:
        return
    var delta := finish - start
    var length := delta.length()
    if length < 2.0:
        return
    var direction := delta / length
    var angle := atan2(delta.x, delta.z)
    var spacing := 2.9
    var sleeper_total := int(floor(length / spacing))
    for sleeper_index: int in range(sleeper_total):
        if _sleeper_count >= 180:
            return
        var sleeper := CSGBox3D.new()
        sleeper.size = Vector3(2.15, 0.055, 0.22)
        sleeper.position = start + direction * (float(sleeper_index) * spacing + 1.0) + Vector3(0, 0.065, 0)
        sleeper.rotation.y = angle
        sleeper.material = _sleeper_material
        sleeper.use_collision = false
        root.add_child(sleeper)
        _sleeper_count += 1

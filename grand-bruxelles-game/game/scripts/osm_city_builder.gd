extends Node3D

@export_file("*.json") var data_path: String = "res://data/osm/vertical_slice_01.game.json"
@export var max_buildings: int = 260
@export var max_road_segments: int = 850
@export var build_collisions: bool = true

var _road_material: StandardMaterial3D
var _building_material: StandardMaterial3D
var _rail_material: StandardMaterial3D


func _ready() -> void:
    _make_materials()
    _build_from_file()


func _make_materials() -> void:
    _road_material = StandardMaterial3D.new()
    _road_material.albedo_color = Color(0.12, 0.13, 0.15, 1.0)
    _road_material.roughness = 0.96

    _building_material = StandardMaterial3D.new()
    _building_material.albedo_color = Color(0.42, 0.43, 0.46, 1.0)
    _building_material.roughness = 0.92

    _rail_material = StandardMaterial3D.new()
    _rail_material.albedo_color = Color(0.25, 0.27, 0.30, 1.0)
    _rail_material.metallic = 0.55
    _rail_material.roughness = 0.48


func _build_from_file() -> void:
    if not FileAccess.file_exists(data_path):
        push_warning("OSM city data missing: %s" % data_path)
        return

    var text := FileAccess.get_file_as_string(data_path)
    var parsed = JSON.parse_string(text)
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Invalid OSM city JSON: %s" % data_path)
        return

    var roads_root := Node3D.new()
    roads_root.name = "GeneratedRoads"
    add_child(roads_root)

    var buildings_root := Node3D.new()
    buildings_root.name = "GeneratedBuildings"
    add_child(buildings_root)

    var rails_root := Node3D.new()
    rails_root.name = "GeneratedRails"
    add_child(rails_root)

    var road_segments := _build_roads(parsed.get("roads", []), roads_root)
    var building_count := _build_buildings(parsed.get("buildings", []), buildings_root)
    var rail_segments := _build_rails(parsed.get("railways", []), rails_root)

    print(
        "Grand Bruxelles OSM greybox: %d road segments, %d buildings, %d rail segments" %
        [road_segments, building_count, rail_segments]
    )


func _point(raw) -> Vector3:
    return Vector3(float(raw[0]), 0.0, float(raw[1]))


func _build_roads(roads: Array, root: Node3D) -> int:
    var segment_count := 0
    for road in roads:
        if segment_count >= max_road_segments:
            break
        var points: Array = road.get("points", [])
        var width := float(road.get("width", 4.5))
        for index in range(points.size() - 1):
            if segment_count >= max_road_segments:
                break
            var start := _point(points[index])
            var finish := _point(points[index + 1])
            var delta := finish - start
            var length := delta.length()
            if length < 0.75:
                continue

            var segment := CSGBox3D.new()
            segment.name = "Road_%s_%d" % [str(road.get("osm_id", "x")), index]
            segment.size = Vector3(width, 0.10, length)
            segment.position = (start + finish) * 0.5 + Vector3(0, 0.02, 0)
            segment.rotation.y = atan2(delta.x, delta.z)
            segment.material = _road_material
            segment.use_collision = false
            root.add_child(segment)
            segment_count += 1
    return segment_count


func _build_buildings(buildings: Array, root: Node3D) -> int:
    var count := 0
    for building in buildings:
        if count >= max_buildings:
            break
        var footprint: Array = building.get("footprint", [])
        if footprint.size() < 3:
            continue

        var center := Vector2.ZERO
        for raw in footprint:
            center += Vector2(float(raw[0]), float(raw[1]))
        center /= float(footprint.size())

        var polygon := PackedVector2Array()
        for raw in footprint:
            polygon.append(Vector2(float(raw[0]) - center.x, float(raw[1]) - center.y))

        var height := clamp(float(building.get("height", 10.5)), 2.8, 120.0)
        var solid := CSGPolygon3D.new()
        solid.name = "Building_%s" % str(building.get("osm_id", "x"))
        solid.polygon = polygon
        solid.depth = height
        solid.rotation_degrees.x = -90.0
        solid.position = Vector3(center.x, height * 0.5, center.y)
        solid.material = _building_material
        solid.use_collision = build_collisions
        root.add_child(solid)
        count += 1
    return count


func _build_rails(railways: Array, root: Node3D) -> int:
    var count := 0
    for railway in railways:
        var points: Array = railway.get("points", [])
        for index in range(points.size() - 1):
            if count >= 400:
                return count
            var start := _point(points[index])
            var finish := _point(points[index + 1])
            var delta := finish - start
            var length := delta.length()
            if length < 0.75:
                continue
            var segment := CSGBox3D.new()
            segment.name = "Rail_%s_%d" % [str(railway.get("osm_id", "x")), index]
            segment.size = Vector3(1.4, 0.07, length)
            segment.position = (start + finish) * 0.5 + Vector3(0, 0.10, 0)
            segment.rotation.y = atan2(delta.x, delta.z)
            segment.material = _rail_material
            segment.use_collision = false
            root.add_child(segment)
            count += 1
    return count

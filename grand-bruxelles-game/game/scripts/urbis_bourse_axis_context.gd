extends Node3D

@export_file("*.json") var data_path: String = "res://data/urbis/bourse_street_axes.game.json"

var _material: StandardMaterial3D
var _segments: Array[Dictionary] = []


func _ready() -> void:
    _material = StandardMaterial3D.new()
    _material.albedo_color = Color(0.30, 0.29, 0.265, 1.0)
    _material.roughness = 0.96
    _build()


func _build() -> void:
    if not FileAccess.file_exists(data_path):
        push_error("Bourse UrbIS axis data missing: %s" % data_path)
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Invalid Bourse UrbIS axis JSON: %s" % data_path)
        return
    var data: Dictionary = parsed
    if str(data.get("schema", "")) != "grand-bruxelles-urbis-bourse-axis-v1":
        push_error("Unsupported Bourse axis schema: %s" % data_path)
        return

    var width := float(data.get("visual_strip_width_m", 8.8))
    for raw_axis: Variant in data.get("axes", []):
        if typeof(raw_axis) != TYPE_DICTIONARY:
            continue
        var axis: Dictionary = raw_axis
        var points: Array = axis.get("world_points_xz", [])
        if points.size() < 2:
            continue
        for index: int in range(points.size() - 1):
            var start := Vector3(float(points[index][0]), 0.0, float(points[index][1]))
            var finish := Vector3(float(points[index + 1][0]), 0.0, float(points[index + 1][1]))
            var delta := finish - start
            var length := delta.length()
            if length < 0.5:
                continue
            var strip := CSGBox3D.new()
            strip.name = "OfficialBourseAxis_%s_%d" % [str(axis.get("inspire_id", "unknown")).get_file(), index]
            strip.size = Vector3(width, 0.08, length)
            strip.position = (start + finish) * 0.5 + Vector3(0.0, 0.055, 0.0)
            strip.rotation.y = atan2(delta.x, delta.z)
            strip.material = _material
            strip.use_collision = false
            add_child(strip)
            _segments.append({
                "inspire_id": axis.get("inspire_id"),
                "start": Vector2(start.x, start.z),
                "finish": Vector2(finish.x, finish.z),
                "length_m": length,
                "width_m": width,
            })

    print("Bourse UrbIS axis context: %d official segments" % _segments.size())


func official_segment_count() -> int:
    return _segments.size()


func official_axis_endpoint_error_max_m(expected: Array[Vector2]) -> float:
    var actual: Array[Vector2] = []
    for segment: Dictionary in _segments:
        actual.append(segment["start"])
        actual.append(segment["finish"])
    var maximum := 0.0
    for point: Vector2 in expected:
        var nearest := INF
        for candidate: Vector2 in actual:
            nearest = minf(nearest, point.distance_to(candidate))
        maximum = maxf(maximum, nearest)
    return maximum

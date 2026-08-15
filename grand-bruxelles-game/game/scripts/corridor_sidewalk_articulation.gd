extends Node3D

const MIDI_ANCHOR := Vector2(-668.5, 627.84)
const BOURSE_ANCHOR := Vector2(81.54, -664.58)
const MIDI_RADIUS_M := 300.0
const BOURSE_RADIUS_M := 180.0
const MAX_CURBS := 700
const MAX_JOINTS := 2200

var _curb_transforms: Array[Transform3D] = []
var _joint_transforms: Array[Transform3D] = []
var _segment_keys: Dictionary = {}
var _built := false

func build_from_city_builder(city_builder: Node) -> bool:
    if _built or city_builder == null:
        return _built
    if city_builder.get_node_or_null("GeneratedRoads") == null:
        return false
    var data_path := str(city_builder.get("data_path"))
    if data_path.is_empty() or not FileAccess.file_exists(data_path):
        push_warning("Corridor sidewalk articulation source missing: %s" % data_path)
        return false
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Corridor sidewalk articulation could not parse source road data")
        return false

    var city_data := parsed as Dictionary
    for raw_road: Variant in city_data.get("roads", []):
        if typeof(raw_road) != TYPE_DICTIONARY:
            continue
        var road := raw_road as Dictionary
        if not bool(road.get("drivable", false)):
            continue
        var points: Array = road.get("points", [])
        if points.size() < 2:
            continue
        var road_class := str(road.get("class", ""))
        var road_width := _road_width_for(road)
        for index: int in range(points.size() - 1):
            if _curb_transforms.size() >= MAX_CURBS and _joint_transforms.size() >= MAX_JOINTS:
                break
            var start := _point(points[index])
            var finish := _point(points[index + 1])
            var midpoint := (start + finish) * 0.5
            if not _is_detail_zone(midpoint):
                continue
            _queue_segment(start, finish, road_width, road_class)

    _flush_layers()
    _built = true
    print("Corridor sidewalk articulation: unique_segments=%d curbs=%d joints=%d" % [_segment_keys.size(), _curb_transforms.size(), _joint_transforms.size()])
    return true

func _point(raw: Variant) -> Vector3:
    return Vector3(float(raw[0]), 0.0, float(raw[1]))

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

func _is_detail_zone(point: Vector3) -> bool:
    var p := Vector2(point.x, point.z)
    return p.distance_to(MIDI_ANCHOR) <= MIDI_RADIUS_M or p.distance_to(BOURSE_ANCHOR) <= BOURSE_RADIUS_M

func _segment_key(start: Vector3, finish: Vector3) -> String:
    var a := Vector2(start.x, start.z)
    var b := Vector2(finish.x, finish.z)
    if a.x > b.x or (is_equal_approx(a.x, b.x) and a.y > b.y):
        var swap := a
        a = b
        b = swap
    return "%d:%d:%d:%d" % [roundi(a.x * 2.0), roundi(a.y * 2.0), roundi(b.x * 2.0), roundi(b.y * 2.0)]

func _queue_segment(start: Vector3, finish: Vector3, road_width: float, road_class: String) -> void:
    var key := _segment_key(start, finish)
    if _segment_keys.has(key):
        return
    _segment_keys[key] = true

    var delta := finish - start
    var length := delta.length()
    if length < 1.0:
        return
    var direction := delta / length
    var perpendicular := Vector3(-direction.z, 0.0, direction.x)
    var sidewalk_width := 2.55 if road_class in ["primary", "secondary"] else 1.85
    var sidewalk_center_offset := road_width * 0.5 + sidewalk_width * 0.5 + 0.10
    var curb_offset := road_width * 0.5 + 0.055
    var center := (start + finish) * 0.5
    var angle := atan2(delta.x, delta.z)

    for side: float in [-1.0, 1.0]:
        if _curb_transforms.size() < MAX_CURBS:
            var curb_center := center + perpendicular * curb_offset * side + Vector3(0.0, 0.105, 0.0)
            var curb_basis := Basis(Vector3.UP, angle).scaled(Vector3(0.10, 0.12, length * 0.975))
            _curb_transforms.append(Transform3D(curb_basis, curb_center))

        var joint_spacing := 3.0
        var joint_count := int(floor(length / joint_spacing))
        for joint_index: int in range(1, joint_count + 1):
            if _joint_transforms.size() >= MAX_JOINTS:
                break
            var distance := minf(length - 0.35, float(joint_index) * joint_spacing)
            if distance <= 0.35:
                continue
            var point := start + direction * distance + perpendicular * sidewalk_center_offset * side
            point.y = 0.147
            var joint_basis := Basis(Vector3.UP, angle).scaled(Vector3(sidewalk_width * 0.90, 0.004, 0.024))
            _joint_transforms.append(Transform3D(joint_basis, point))

func _flush_layers() -> void:
    var curb_material := StandardMaterial3D.new()
    curb_material.albedo_color = Color(0.35, 0.34, 0.32, 1.0)
    curb_material.roughness = 0.96
    var joint_material := StandardMaterial3D.new()
    joint_material.albedo_color = Color(0.34, 0.33, 0.31, 1.0)
    joint_material.roughness = 0.98
    _add_multimesh_layer("CurbLips", _curb_transforms, curb_material, true)
    _add_multimesh_layer("PavementJoints", _joint_transforms, joint_material, false)

func _add_multimesh_layer(layer_name: String, transforms: Array[Transform3D], material: Material, casts_shadow: bool) -> void:
    if transforms.is_empty():
        return
    var mesh := BoxMesh.new()
    mesh.size = Vector3.ONE
    mesh.material = material
    var multimesh := MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.mesh = mesh
    multimesh.instance_count = transforms.size()
    for index: int in range(transforms.size()):
        multimesh.set_instance_transform(index, transforms[index])
    var instance := MultiMeshInstance3D.new()
    instance.name = layer_name
    instance.multimesh = multimesh
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(instance)

func _count_near(transforms: Array[Transform3D], anchor: Vector2, radius_m: float) -> int:
    var count := 0
    for transform: Transform3D in transforms:
        if Vector2(transform.origin.x, transform.origin.z).distance_to(anchor) <= radius_m:
            count += 1
    return count

func articulation_counts_near(anchor: Vector2, radius_m: float) -> Dictionary:
    return {
        "curbs": _count_near(_curb_transforms, anchor, radius_m),
        "joints": _count_near(_joint_transforms, anchor, radius_m),
    }

func truth_contract() -> Dictionary:
    return {
        "geometry_reference": "existing production OSM road segments and production sidewalk width rules",
        "art_direction_only": true,
        "moves_source_geometry": false,
        "changes_road_width": false,
        "external_assets": 0,
        "layers": 2,
    }

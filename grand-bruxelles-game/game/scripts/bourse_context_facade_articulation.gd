extends Node3D

const BOURSE_ANCHOR := Vector2(81.54, -664.58)
const DETAIL_RADIUS_M := 180.0
const MAX_CORNICES := 420
const MAX_WINDOW_TRIMS := 2200
const MAX_ENTRIES := 360
const MAX_SHOP_HEADERS := 720

var _cornice_transforms: Array[Transform3D] = []
var _lintel_transforms: Array[Transform3D] = []
var _sill_transforms: Array[Transform3D] = []
var _entry_transforms: Array[Transform3D] = []
var _shop_header_transforms: Array[Transform3D] = []

var _stone_trim_material: StandardMaterial3D
var _sill_material: StandardMaterial3D
var _entry_material: StandardMaterial3D
var _shop_header_material: StandardMaterial3D
var _built := false

func build_from_city_builder(city_builder: Node) -> bool:
    if _built or city_builder == null:
        return _built
    if city_builder.get_node_or_null("GeneratedBuildings") == null:
        return false
    var data_path := str(city_builder.get("data_path"))
    if data_path.is_empty() or not FileAccess.file_exists(data_path):
        push_warning("Bourse facade articulation source missing: %s" % data_path)
        return false
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Bourse facade articulation could not parse source city data")
        return false

    _make_materials()
    var city_data: Dictionary = parsed
    var replacement_ids: Dictionary = {}
    if city_builder.has_method("_validated_hero_replacements"):
        replacement_ids = city_builder.call("_validated_hero_replacements") as Dictionary
    var accepted_buildings := 0
    for raw_building: Variant in city_data.get("buildings", []):
        if typeof(raw_building) != TYPE_DICTIONARY:
            continue
        var building: Dictionary = raw_building
        if replacement_ids.has(int(building.get("osm_id", 0))):
            continue
        var footprint: Array = building.get("footprint", [])
        if footprint.size() < 3 or not _footprint_near_bourse(footprint):
            continue
        var height := clampf(float(building.get("height", 10.5)), 2.8, 120.0)
        _queue_building_articulation(footprint, height)
        accepted_buildings += 1

    _flush_layers()
    _built = true
    print(
        "Bourse context facade articulation: buildings=%d cornices=%d lintels=%d sills=%d entries=%d shop_headers=%d" %
        [accepted_buildings, _cornice_transforms.size(), _lintel_transforms.size(), _sill_transforms.size(), _entry_transforms.size(), _shop_header_transforms.size()]
    )
    return true

func _make_materials() -> void:
    _stone_trim_material = _material(Color(0.63, 0.58, 0.49, 1.0), 0.90)
    _sill_material = _material(Color(0.48, 0.46, 0.42, 1.0), 0.88)
    _entry_material = _material(Color(0.10, 0.075, 0.055, 1.0), 0.72)
    _shop_header_material = _material(Color(0.24, 0.25, 0.24, 1.0), 0.83)

func _material(color: Color, roughness: float) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    return material

func _point_segment_distance(point: Vector2, start: Vector2, finish: Vector2) -> float:
    var segment := finish - start
    var length_squared := segment.length_squared()
    if length_squared <= 0.000001:
        return point.distance_to(start)
    var amount := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
    return point.distance_to(start + segment * amount)

func _footprint_near_bourse(footprint: Array) -> bool:
    for raw: Variant in footprint:
        var point := Vector2(float(raw[0]), float(raw[1]))
        if point.distance_to(BOURSE_ANCHOR) <= DETAIL_RADIUS_M:
            return true
    for edge_index: int in range(footprint.size()):
        var raw_a: Variant = footprint[edge_index]
        var raw_b: Variant = footprint[(edge_index + 1) % footprint.size()]
        var a := Vector2(float(raw_a[0]), float(raw_a[1]))
        var b := Vector2(float(raw_b[0]), float(raw_b[1]))
        if _point_segment_distance(BOURSE_ANCHOR, a, b) <= DETAIL_RADIUS_M:
            return true
    return false

func _queue_building_articulation(footprint: Array, height: float) -> void:
    if height < 6.0:
        return
    var floor_count := clampi(int(floor(height / 3.15)) - 1, 1, 7)
    for edge_index: int in range(footprint.size()):
        var raw_a: Variant = footprint[edge_index]
        var raw_b: Variant = footprint[(edge_index + 1) % footprint.size()]
        var a := Vector2(float(raw_a[0]), float(raw_a[1]))
        var b := Vector2(float(raw_b[0]), float(raw_b[1]))
        var edge := b - a
        var edge_length := edge.length()
        if edge_length < 4.0:
            continue
        var direction := edge / edge_length
        var angle := atan2(-direction.y, direction.x)
        var midpoint := (a + b) * 0.5

        if _cornice_transforms.size() < MAX_CORNICES and edge_length >= 5.0:
            var cornice_basis := Basis(Vector3.UP, angle).scaled(Vector3(edge_length * 0.94, 0.18, 0.26))
            _cornice_transforms.append(Transform3D(cornice_basis, Vector3(midpoint.x, maxf(3.2, height - 0.34), midpoint.y)))

        var module_count := clampi(int(edge_length / 3.2), 1, 24)
        var step := edge_length / float(module_count + 1)
        var window_width := clampf(step * 0.58, 1.05, 1.85)
        var commercial_edge := edge_length <= 30.0

        if commercial_edge and _entry_transforms.size() < MAX_ENTRIES:
            var entry_point := a + direction * step
            var entry_width := clampf(step * 0.38, 0.95, 1.38)
            var entry_basis := Basis(Vector3.UP, angle).scaled(Vector3(entry_width, 2.55, 0.18))
            _entry_transforms.append(Transform3D(entry_basis, Vector3(entry_point.x, 1.42, entry_point.y)))

        for module_index: int in range(module_count):
            var along := step * float(module_index + 1)
            var point := a + direction * along
            if commercial_edge and _shop_header_transforms.size() < MAX_SHOP_HEADERS:
                var header_basis := Basis(Vector3.UP, angle).scaled(Vector3(minf(2.35, step * 0.76), 0.24, 0.18))
                _shop_header_transforms.append(Transform3D(header_basis, Vector3(point.x, 2.88, point.y)))

            for floor_index: int in range(floor_count):
                if _lintel_transforms.size() >= MAX_WINDOW_TRIMS:
                    break
                var y := 4.35 + float(floor_index) * 3.05
                if y + 0.8 >= height:
                    break
                var trim_width := window_width + 0.28
                var lintel_basis := Basis(Vector3.UP, angle).scaled(Vector3(trim_width, 0.14, 0.17))
                var sill_basis := Basis(Vector3.UP, angle).scaled(Vector3(trim_width + 0.08, 0.12, 0.20))
                _lintel_transforms.append(Transform3D(lintel_basis, Vector3(point.x, y + 0.82, point.y)))
                _sill_transforms.append(Transform3D(sill_basis, Vector3(point.x, y - 0.82, point.y)))

func _flush_layers() -> void:
    _add_multimesh_layer("CorridorFacadeCornices", _cornice_transforms, _stone_trim_material)
    _add_multimesh_layer("CorridorFacadeLintels", _lintel_transforms, _stone_trim_material)
    _add_multimesh_layer("CorridorFacadeSills", _sill_transforms, _sill_material)
    _add_multimesh_layer("CorridorFacadeEntries", _entry_transforms, _entry_material)
    _add_multimesh_layer("CorridorShopHeaders", _shop_header_transforms, _shop_header_material)

func _add_multimesh_layer(layer_name: String, transforms: Array[Transform3D], material: Material) -> void:
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
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    add_child(instance)

func _count_near(transforms: Array[Transform3D], anchor: Vector2, radius_m: float) -> int:
    var count := 0
    for transform: Transform3D in transforms:
        if Vector2(transform.origin.x, transform.origin.z).distance_to(anchor) <= radius_m:
            count += 1
    return count

func facade_articulation_counts_near(anchor: Vector2, radius_m: float) -> Dictionary:
    return {
        "cornices": _count_near(_cornice_transforms, anchor, radius_m),
        "lintels": _count_near(_lintel_transforms, anchor, radius_m),
        "sills": _count_near(_sill_transforms, anchor, radius_m),
        "entries": _count_near(_entry_transforms, anchor, radius_m),
        "shop_headers": _count_near(_shop_header_transforms, anchor, radius_m),
    }

func truth_contract() -> Dictionary:
    return {
        "geometry_reference": "existing OSM source footprints and existing runtime heights",
        "art_direction_only": true,
        "moves_source_geometry": false,
        "changes_building_height": false,
        "external_assets": 0,
        "placement_scope": "Bourse context within 180 m",
    }

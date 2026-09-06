extends Node3D

## Visible City Machine LABO for Midi.
## This scene consumes the normalized City Machine outputs directly. It never
## replaces the canonical Midi fast-travel runtime and never promotes itself.

const DATA_ROOT := "res://data/urbis/midi"
const OSM_ENVIRONMENT_RUNTIME := preload("res://game/scripts/brussels_osm_environment_runtime.gd")
const OSM_ENVIRONMENT_DATA := "res://data/osm/zones/midi/environment.game.json"
const FACADE_MATERIAL_FACTORY := preload("res://game/scripts/midi_city_machine_facade_material.gd")

@export var building_fallback_height_m := 10.5
@export var ground_y := 0.0
@export var facade_labo_enabled := true

var last_stats: Dictionary = {
    "buildings": 0,
    "street_surfaces": 0,
    "street_axes": 0,
    "tram_network": 0,
    "train_network": 0,
}

var _road_material: StandardMaterial3D
var _building_material: StandardMaterial3D
var _building_facade_material: ShaderMaterial
var _building_instance: MeshInstance3D
var _rail_material: StandardMaterial3D
var _tram_material: StandardMaterial3D


func _ready() -> void:
    _make_materials()
    _build_ground_reference()
    _build_official_geometry()
    _install_facade_labo_contract()
    _build_osm_environment()
    print("MIDI_CITY_MACHINE_LABO_READY: %s facade=%s promotion=false" % [JSON.stringify(last_stats), str(facade_labo_enabled).to_lower()])


func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = metallic
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    return material


func _make_materials() -> void:
    _road_material = _material(Color(0.16, 0.17, 0.18, 1.0), 0.96)
    _building_material = _material(Color(0.58, 0.56, 0.53, 1.0), 0.92)
    _building_facade_material = FACADE_MATERIAL_FACTORY.create_material(_building_material.albedo_color)
    _rail_material = _material(Color(0.15, 0.16, 0.17, 1.0), 0.42, 0.50)
    _tram_material = _material(Color(0.25, 0.25, 0.25, 1.0), 0.55, 0.28)


func _install_facade_labo_contract() -> void:
    _building_instance = get_node_or_null("MidiCityMachineBuildings") as MeshInstance3D
    if _building_instance == null:
        push_warning("Midi City Machine facade LABO contract has no building mesh to bind")
        return
    _building_instance.set_meta("facade_contract", FACADE_MATERIAL_FACTORY.MATERIAL_FAMILY)
    _building_instance.set_meta("facade_geometry_changed", false)
    _building_instance.set_meta("facade_semantic_windows_claimed", false)
    _building_instance.set_meta("facade_semantic_doors_claimed", false)
    _building_instance.set_meta("facade_material_identity_claimed", false)
    _building_instance.set_meta("facade_jouable_authorized", false)
    _building_instance.set_meta("facade_promotion_performed", false)
    _apply_facade_state()


func _apply_facade_state() -> void:
    if _building_instance == null:
        return
    _building_instance.material_override = _building_facade_material if facade_labo_enabled else null


func set_facade_enabled(enabled: bool) -> void:
    facade_labo_enabled = enabled
    _apply_facade_state()


func facade_enabled() -> bool:
    return facade_labo_enabled


func facade_material_family() -> String:
    return FACADE_MATERIAL_FACTORY.MATERIAL_FAMILY


func facade_geometry_changed() -> bool:
    return false


func facade_semantic_claims() -> bool:
    return false


func facade_material_identity_claimed() -> bool:
    return false


func facade_jouable_authorized() -> bool:
    return false


func facade_contract() -> Dictionary:
    return {
        "family": FACADE_MATERIAL_FACTORY.MATERIAL_FAMILY,
        "scope": "midi_machine_labo",
        "geometry_source": FACADE_MATERIAL_FACTORY.GEOMETRY_SOURCE,
        "visual_provenance": FACADE_MATERIAL_FACTORY.VISUAL_PROVENANCE,
        "geometry_changed": false,
        "semantic_windows_claimed": false,
        "semantic_doors_claimed": false,
        "material_identity_claimed": false,
        "jouable_authorized": false,
        "promotion_performed": false,
        "ab_toggle": true,
    }


func _build_ground_reference() -> void:
    # No city-wide synthetic ground is authored here. Official StreetSurfaces
    # provide the visible ground and collision. The small review pad only keeps
    # the LABO spawn stable while the user inspects the generated candidate.
    var pad := MeshInstance3D.new()
    pad.name = "MidiCityMachineReviewPad"
    var mesh := PlaneMesh.new()
    mesh.size = Vector2(24.0, 24.0)
    mesh.material = _road_material
    pad.mesh = mesh
    pad.position = Vector3(-600.0, ground_y - 0.08, 600.0)
    add_child(pad)

    var body := StaticBody3D.new()
    body.name = "MidiCityMachineReviewPadCollision"
    var collision := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(24.0, 0.16, 24.0)
    collision.shape = box
    body.position = Vector3(-600.0, ground_y - 0.16, 600.0)
    body.add_child(collision)
    add_child(body)


func _build_osm_environment() -> void:
    var runtime := OSM_ENVIRONMENT_RUNTIME.new()
    runtime.name = "MidiCityMachineOSMEnvironment"
    runtime.data_path = OSM_ENVIRONMENT_DATA
    add_child(runtime)


func _load_collection(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        push_warning("Midi City Machine layer missing: %s" % path)
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_warning("Unable to open Midi City Machine layer: %s" % path)
        return {}
    var parsed = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        push_warning("Invalid Midi City Machine JSON: %s" % path)
        return {}
    return parsed as Dictionary


func _feature_count(document: Dictionary) -> int:
    var features = document.get("features", [])
    return features.size() if features is Array else 0


func _build_official_geometry() -> void:
    var roads := _load_collection(DATA_ROOT + "/street_surfaces.game.json")
    var buildings := _load_collection(DATA_ROOT + "/buildings.game.json")
    var axes := _load_collection(DATA_ROOT + "/street_axes.game.json")
    var trams := _load_collection(DATA_ROOT + "/tram_network.game.json")
    var trains := _load_collection(DATA_ROOT + "/train_network.game.json")

    last_stats["street_surfaces"] = _feature_count(roads)
    last_stats["buildings"] = _feature_count(buildings)
    last_stats["street_axes"] = _feature_count(axes)
    last_stats["tram_network"] = _feature_count(trams)
    last_stats["train_network"] = _feature_count(trains)

    _build_polygon_layer(roads, "MidiCityMachineStreetSurfaces", _road_material, ground_y + 0.02, true)
    _build_buildings(buildings)
    _build_line_layer(trams, "MidiCityMachineTramNetwork", _tram_material, 1.0, ground_y + 0.055)
    _build_line_layer(trains, "MidiCityMachineTrainNetwork", _rail_material, 1.45, ground_y + 0.07)


func _outer_rings(geometry: Dictionary) -> Array:
    var result: Array = []
    var kind := String(geometry.get("type", ""))
    var coords = geometry.get("coordinates", [])
    if kind == "Polygon" and coords is Array and not coords.is_empty():
        result.append(coords[0])
    elif kind == "MultiPolygon" and coords is Array:
        for polygon in coords:
            if polygon is Array and not polygon.is_empty():
                result.append(polygon[0])
    return result


func _line_strings(geometry: Dictionary) -> Array:
    var result: Array = []
    var kind := String(geometry.get("type", ""))
    var coords = geometry.get("coordinates", [])
    if kind == "LineString" and coords is Array:
        result.append(coords)
    elif kind == "MultiLineString" and coords is Array:
        for line in coords:
            if line is Array:
                result.append(line)
    return result


func _ring_points(ring: Array) -> PackedVector2Array:
    var points := PackedVector2Array()
    for raw in ring:
        if raw is Array and raw.size() >= 2:
            points.append(Vector2(float(raw[0]), float(raw[1])))
    if points.size() >= 2 and points[0].distance_to(points[points.size() - 1]) < 0.001:
        points.resize(points.size() - 1)
    return points


func _append_flat(st: SurfaceTool, points: PackedVector2Array, y: float) -> void:
    var triangles := Geometry2D.triangulate_polygon(points)
    for index in triangles:
        var point := points[int(index)]
        st.set_normal(Vector3.UP)
        st.add_vertex(Vector3(point.x, y, point.y))


func _append_walls(st: SurfaceTool, points: PackedVector2Array, bottom_y: float, top_y: float) -> void:
    for i in range(points.size()):
        var a := points[i]
        var b := points[(i + 1) % points.size()]
        var edge := b - a
        if edge.length_squared() < 0.0001:
            continue
        var normal := Vector3(edge.y, 0.0, -edge.x).normalized()
        var a0 := Vector3(a.x, bottom_y, a.y)
        var a1 := Vector3(a.x, top_y, a.y)
        var b0 := Vector3(b.x, bottom_y, b.y)
        var b1 := Vector3(b.x, top_y, b.y)
        for vertex in [a0, b0, b1, a0, b1, a1]:
            st.set_normal(normal)
            st.add_vertex(vertex)


func _commit_mesh(st: SurfaceTool, node_name: String, material: Material, collision_enabled: bool = false) -> void:
    var mesh := st.commit()
    if mesh == null or mesh.get_surface_count() == 0:
        return
    mesh.surface_set_material(0, material)
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    add_child(instance)
    if collision_enabled:
        instance.create_trimesh_collision()


func _build_polygon_layer(document: Dictionary, node_name: String, material: Material, y: float, collision_enabled: bool) -> void:
    var features = document.get("features", [])
    if not (features is Array) or features.is_empty():
        return
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for feature in features:
        if not (feature is Dictionary):
            continue
        var geometry = feature.get("geometry", {})
        if not (geometry is Dictionary):
            continue
        for ring in _outer_rings(geometry):
            var points := _ring_points(ring)
            if points.size() >= 3:
                _append_flat(st, points, y)
    _commit_mesh(st, node_name, material, collision_enabled)


func _building_height(properties: Dictionary) -> float:
    for key in ["height", "Height", "HEIGHT", "roof_height", "RoofHeight", "ROOFHEIGHT"]:
        if properties.has(key):
            var value := float(properties[key])
            if value >= 2.5 and value <= 220.0:
                return value
    for key in ["floors", "Floors", "FLOORS", "levels", "Levels", "LEVELS"]:
        if properties.has(key):
            var levels := float(properties[key])
            if levels >= 1.0 and levels <= 60.0:
                return levels * 3.15
    # Explicit LABO-only procedural massing fallback. It is not source truth and
    # is never sufficient for JOUABLE promotion.
    return building_fallback_height_m


func _build_buildings(document: Dictionary) -> void:
    var features = document.get("features", [])
    if not (features is Array) or features.is_empty():
        return
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for feature in features:
        if not (feature is Dictionary):
            continue
        var geometry = feature.get("geometry", {})
        if not (geometry is Dictionary):
            continue
        var properties = feature.get("properties", {})
        if not (properties is Dictionary):
            properties = {}
        var height := _building_height(properties)
        for ring in _outer_rings(geometry):
            var points := _ring_points(ring)
            if points.size() < 3:
                continue
            _append_flat(st, points, ground_y + height)
            _append_walls(st, points, ground_y, ground_y + height)
    _commit_mesh(st, "MidiCityMachineBuildings", _building_material, true)


func _build_line_layer(document: Dictionary, node_name: String, material: Material, width: float, y: float) -> void:
    var features = document.get("features", [])
    if not (features is Array) or features.is_empty():
        return
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for feature in features:
        if not (feature is Dictionary):
            continue
        var geometry = feature.get("geometry", {})
        if not (geometry is Dictionary):
            continue
        for line in _line_strings(geometry):
            _append_line_ribbon(st, line, width, y)
    _commit_mesh(st, node_name, material)


func _append_line_ribbon(st: SurfaceTool, line: Array, width: float, y: float) -> void:
    if line.size() < 2:
        return
    for i in range(line.size() - 1):
        var raw_a = line[i]
        var raw_b = line[i + 1]
        if not (raw_a is Array and raw_b is Array and raw_a.size() >= 2 and raw_b.size() >= 2):
            continue
        var a := Vector2(float(raw_a[0]), float(raw_a[1]))
        var b := Vector2(float(raw_b[0]), float(raw_b[1]))
        var delta := b - a
        if delta.length_squared() < 0.0001:
            continue
        var side := Vector2(-delta.y, delta.x).normalized() * width * 0.5
        var p0 := Vector3(a.x + side.x, y, a.y + side.y)
        var p1 := Vector3(a.x - side.x, y, a.y - side.y)
        var p2 := Vector3(b.x - side.x, y, b.y - side.y)
        var p3 := Vector3(b.x + side.x, y, b.y + side.y)
        for vertex in [p0, p1, p2, p0, p2, p3]:
            st.set_normal(Vector3.UP)
            st.add_vertex(vertex)

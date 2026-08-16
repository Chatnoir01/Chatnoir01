extends Node3D

## Visual realism pass for Laeken/Heysel.
## Official UrbIS geometry stays authoritative. This pass only improves materials
## and adds explicitly photo-guided street furniture around the Atomium approach.

const DATA_ROOT := "res://data/urbis/laeken_jette"
const ATOMIUM := Vector2(224.92615906274295, -6553.143077999353)
const MAX_APPROACH_RADIUS := 340.0
const TREE_SPACING := 24.0
const LAMP_SPACING := 32.0

var selected_axis_distance_m: float = INF
var selected_axis_points: PackedVector2Array = PackedVector2Array()
var generated_trees: int = 0
var generated_lamps: int = 0
var generated_dashes: int = 0

var _tree_trunk: StandardMaterial3D
var _tree_leaf: StandardMaterial3D
var _lamp_metal: StandardMaterial3D
var _lamp_glow: StandardMaterial3D
var _marking: StandardMaterial3D
var _grass: StandardMaterial3D
var _glass: StandardMaterial3D
var _atomium_metal: StandardMaterial3D


func _ready() -> void:
    call_deferred("_apply_realism")


func _apply_realism() -> void:
    _make_materials()
    _upgrade_official_mesh_materials()
    _upgrade_atomium_materials()
    _build_atomium_base_detail()
    _select_official_atomium_axis()
    if selected_axis_points.size() >= 2:
        _build_photo_guided_approach()
    print("LAEKEN_REALISM_READY: axis_distance=%.2f trees=%d lamps=%d dashes=%d" % [selected_axis_distance_m, generated_trees, generated_lamps, generated_dashes])


func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = metallic
    return material


func _make_materials() -> void:
    _tree_trunk = _material(Color(0.20, 0.12, 0.07, 1.0), 0.98)
    _tree_leaf = _material(Color(0.075, 0.19, 0.075, 1.0), 0.94)
    _lamp_metal = _material(Color(0.17, 0.18, 0.19, 1.0), 0.36, 0.66)
    _lamp_glow = _material(Color(1.0, 0.91, 0.68, 1.0), 0.24)
    _marking = _material(Color(0.88, 0.87, 0.80, 1.0), 0.90)
    _grass = _material(Color(0.12, 0.25, 0.10, 1.0), 0.98)
    _glass = _material(Color(0.16, 0.25, 0.29, 0.66), 0.12, 0.12)
    _glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    _atomium_metal = _material(Color(0.72, 0.75, 0.77, 1.0), 0.08, 0.98)


func _upgrade_official_mesh_materials() -> void:
    var buildings := get_parent().get_node_or_null("OfficialBuildings") as MeshInstance3D
    if buildings != null:
        buildings.material_override = _make_facade_shader()
    var roads := get_parent().get_node_or_null("OfficialStreetSurfaces") as MeshInstance3D
    if roads != null:
        roads.material_override = _make_road_shader()


func _make_facade_shader() -> ShaderMaterial:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode cull_disabled;
varying vec3 local_pos;
varying vec3 local_normal;

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

void vertex() {
    local_pos = VERTEX;
    local_normal = NORMAL;
}

void fragment() {
    vec3 n = normalize(local_normal);
    float roof = step(0.72, abs(n.y));
    float side_coord = abs(n.x) > abs(n.z) ? local_pos.z : local_pos.x;
    float seed = hash21(floor(local_pos.xz / 18.0));

    vec3 brick_red = vec3(0.43, 0.19, 0.12);
    vec3 brick_brown = vec3(0.32, 0.22, 0.16);
    vec3 warm_stone = vec3(0.59, 0.53, 0.43);
    vec3 pale_stucco = vec3(0.68, 0.65, 0.58);
    vec3 facade = mix(brick_red, brick_brown, step(0.30, seed));
    facade = mix(facade, warm_stone, step(0.58, seed));
    facade = mix(facade, pale_stucco, step(0.82, seed));

    float floor_band = fract(local_pos.y / 3.15);
    float bay = fract(side_coord / 3.0);
    float is_window = step(0.19, bay) * step(bay, 0.79) * step(0.22, floor_band) * step(floor_band, 0.73);
    float frame_x = step(0.15, bay) * step(bay, 0.83) - is_window;
    vec3 window_col = vec3(0.055, 0.075, 0.085);
    vec3 trim_col = mix(vec3(0.56), vec3(0.72, 0.68, 0.58), seed);

    float mortar_x = step(fract(side_coord / 0.62), 0.035);
    float mortar_y = step(fract(local_pos.y / 0.22), 0.055);
    float brick_pattern = max(mortar_x, mortar_y) * (1.0 - step(0.58, seed));
    facade = mix(facade, facade * 1.18, brick_pattern * 0.34);

    float ground_shop = (1.0 - step(3.6, local_pos.y)) * step(0.12, bay) * step(bay, 0.88);
    vec3 colour = facade;
    colour = mix(colour, trim_col, clamp(frame_x, 0.0, 1.0) * 0.42);
    colour = mix(colour, window_col, is_window * (1.0 - roof));
    colour = mix(colour, vec3(0.075, 0.085, 0.09), ground_shop * 0.65 * (1.0 - roof));
    colour = mix(colour, vec3(0.20, 0.18, 0.16), roof);

    ALBEDO = colour;
    ROUGHNESS = mix(0.88, 0.28, is_window);
    METALLIC = is_window * 0.08;
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    return material


func _make_road_shader() -> ShaderMaterial:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
varying vec3 local_pos;
float hash21(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    p += dot(p, p + 19.19);
    return fract(p.x * p.y);
}
void vertex() { local_pos = VERTEX; }
void fragment() {
    float grain = hash21(floor(local_pos.xz * 1.6));
    float broad = hash21(floor(local_pos.xz / 11.0));
    vec3 base = vec3(0.105, 0.112, 0.118);
    ALBEDO = base * (0.88 + grain * 0.13 + broad * 0.06);
    ROUGHNESS = 0.96;
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    return material


func _upgrade_atomium_materials() -> void:
    var atomium := get_parent().get_node_or_null("AtomiumHero")
    if atomium == null:
        return
    for child in atomium.get_children():
        if child is MeshInstance3D:
            var mesh_instance := child as MeshInstance3D
            if child.name.begins_with("Sphere") or child.name == "Tube":
                mesh_instance.material_override = _atomium_metal


func _build_atomium_base_detail() -> void:
    var root := Node3D.new()
    root.name = "AtomiumBaseRealism"
    root.position = Vector3(ATOMIUM.x, 0.0, ATOMIUM.y)
    get_parent().add_child(root)

    var ring := CylinderMesh.new()
    ring.top_radius = 15.8
    ring.bottom_radius = 15.8
    ring.height = 3.1
    ring.radial_segments = 48
    ring.material = _glass
    var ring_instance := MeshInstance3D.new()
    ring_instance.name = "GlazedEntranceRing"
    ring_instance.mesh = ring
    ring_instance.position.y = 1.75
    root.add_child(ring_instance)

    var canopy := CylinderMesh.new()
    canopy.top_radius = 19.0
    canopy.bottom_radius = 19.0
    canopy.height = 0.32
    canopy.radial_segments = 48
    canopy.material = _atomium_metal
    var canopy_instance := MeshInstance3D.new()
    canopy_instance.name = "EntranceCanopy"
    canopy_instance.mesh = canopy
    canopy_instance.position.y = 3.45
    root.add_child(canopy_instance)


func _load_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var parsed = JSON.parse_string(file.get_as_text())
    return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}


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


func _closest_point_on_segment(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
    var ab := b - a
    var denom := ab.length_squared()
    if denom < 0.000001:
        return a
    var t := clampf((p - a).dot(ab) / denom, 0.0, 1.0)
    return a + ab * t


func _select_official_atomium_axis() -> void:
    var data := _load_json(DATA_ROOT + "/street_axes.game.json")
    var features = data.get("features", [])
    if not (features is Array):
        return
    for feature in features:
        if not (feature is Dictionary):
            continue
        var geometry = feature.get("geometry", {})
        if not (geometry is Dictionary):
            continue
        for raw_line in _line_strings(geometry):
            if not (raw_line is Array) or raw_line.size() < 2:
                continue
            var points := PackedVector2Array()
            for raw in raw_line:
                if raw is Array and raw.size() >= 2:
                    points.append(Vector2(float(raw[0]), float(raw[1])))
            for i in range(points.size() - 1):
                var closest := _closest_point_on_segment(ATOMIUM, points[i], points[i + 1])
                var distance := closest.distance_to(ATOMIUM)
                if distance < selected_axis_distance_m:
                    selected_axis_distance_m = distance
                    selected_axis_points = points


func _build_photo_guided_approach() -> void:
    var root := Node3D.new()
    root.name = "AtomiumApproachPhotoGuided"
    get_parent().add_child(root)

    for i in range(selected_axis_points.size() - 1):
        var a := selected_axis_points[i]
        var b := selected_axis_points[i + 1]
        var mid := (a + b) * 0.5
        if mid.distance_to(ATOMIUM) > MAX_APPROACH_RADIUS:
            continue
        _add_segment_dashes(root, a, b)
        _add_segment_furniture(root, a, b)


func _add_segment_dashes(parent: Node3D, a: Vector2, b: Vector2) -> void:
    var delta := b - a
    var length := delta.length()
    if length < 2.0:
        return
    var dir := delta / length
    var cursor := 3.0
    while cursor < length - 2.0:
        var dash_len := minf(3.6, length - cursor)
        var centre := a + dir * (cursor + dash_len * 0.5)
        if centre.distance_to(ATOMIUM) <= MAX_APPROACH_RADIUS:
            _add_box(parent, "RoadDash", Vector3(0.13, 0.025, dash_len), Vector3(centre.x, 0.075, centre.y), atan2(dir.x, dir.y), _marking)
            generated_dashes += 1
        cursor += 9.0


func _add_segment_furniture(parent: Node3D, a: Vector2, b: Vector2) -> void:
    var delta := b - a
    var length := delta.length()
    if length < 10.0:
        return
    var dir := delta / length
    var side := Vector2(-dir.y, dir.x)
    var cursor := TREE_SPACING * 0.5
    while cursor < length:
        var centre := a + dir * cursor
        if centre.distance_to(ATOMIUM) <= MAX_APPROACH_RADIUS and centre.distance_to(ATOMIUM) >= 28.0:
            for sign_value in [-1.0, 1.0]:
                var tree_pos: Vector2 = centre + side * 12.5 * float(sign_value)
                _add_tree(parent, tree_pos)
                generated_trees += 1
        cursor += TREE_SPACING

    cursor = LAMP_SPACING * 0.35
    while cursor < length:
        var centre_lamp := a + dir * cursor
        if centre_lamp.distance_to(ATOMIUM) <= MAX_APPROACH_RADIUS and centre_lamp.distance_to(ATOMIUM) >= 25.0:
            for sign_value in [-1.0, 1.0]:
                var lamp_pos: Vector2 = centre_lamp + side * 8.8 * float(sign_value)
                _add_lamp(parent, lamp_pos)
                generated_lamps += 1
        cursor += LAMP_SPACING


func _add_tree(parent: Node3D, xz: Vector2) -> void:
    var root := Node3D.new()
    root.name = "ApproachTree"
    root.position = Vector3(xz.x, 0.0, xz.y)
    parent.add_child(root)

    var trunk := CylinderMesh.new()
    trunk.top_radius = 0.24
    trunk.bottom_radius = 0.34
    trunk.height = 4.6
    trunk.radial_segments = 7
    trunk.material = _tree_trunk
    var trunk_instance := MeshInstance3D.new()
    trunk_instance.mesh = trunk
    trunk_instance.position.y = 2.3
    root.add_child(trunk_instance)

    var crown := SphereMesh.new()
    crown.radius = 2.25
    crown.height = 4.5
    crown.radial_segments = 10
    crown.rings = 6
    crown.material = _tree_leaf
    var crown_instance := MeshInstance3D.new()
    crown_instance.mesh = crown
    crown_instance.position.y = 5.5
    root.add_child(crown_instance)


func _add_lamp(parent: Node3D, xz: Vector2) -> void:
    var root := Node3D.new()
    root.name = "ApproachLamp"
    root.position = Vector3(xz.x, 0.0, xz.y)
    parent.add_child(root)

    var pole := CylinderMesh.new()
    pole.top_radius = 0.09
    pole.bottom_radius = 0.12
    pole.height = 7.2
    pole.radial_segments = 8
    pole.material = _lamp_metal
    var pole_instance := MeshInstance3D.new()
    pole_instance.mesh = pole
    pole_instance.position.y = 3.6
    root.add_child(pole_instance)

    var head := BoxMesh.new()
    head.size = Vector3(0.34, 0.16, 0.74)
    head.material = _lamp_glow
    var head_instance := MeshInstance3D.new()
    head_instance.mesh = head
    head_instance.position = Vector3(0.0, 7.15, 0.0)
    root.add_child(head_instance)


func _add_box(parent: Node3D, node_name: String, size: Vector3, position: Vector3, rotation_y: float, material: Material) -> void:
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh.material = material
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    instance.position = position
    instance.rotation.y = rotation_y
    parent.add_child(instance)

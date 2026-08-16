extends Node3D

## Sourced hero-detail pass for Palais 5 / Grand Palais.
##
## Placement and long-axis orientation come from the validated OSM hall outline,
## itself checked against the aggregate official UrbIS Expo feature. The major
## structural dimensions below are recorded in palais5_hero_provenance.json from
## Brussels heritage/BIE sources. Decorative sculpture bodies, exact setback
## depths and minor bay widths are simplified game geometry, not survey claims.

const OUTLINE_PATH := "res://data/sources/laeken_jette/palais5_osm_outline.game.json"
const PROVENANCE_PATH := "res://data/sources/laeken_jette/palais5_hero_provenance.json"
const ATOMIUM := Vector2(224.92615906274295, -6553.143077999353)

var hero_ready: bool = false
var arch_instances: int = 0
var facade_glass_panels: int = 0
var facade_pilasters: int = 0
var facade_statues: int = 0
var side_windows: int = 0
var roof_strips: int = 0
var source_outline_vertices: int = 0
var source_height_m: float = 0.0
var source_span_m: float = 0.0

var _stone: StandardMaterial3D
var _stone_dark: StandardMaterial3D
var _glass: StandardMaterial3D
var _bronze: StandardMaterial3D
var _metal: StandardMaterial3D
var _roof: StandardMaterial3D


func _ready() -> void:
    call_deferred("_build")


func _load_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var value = JSON.parse_string(file.get_as_text())
    return value as Dictionary if typeof(value) == TYPE_DICTIONARY else {}


func _material(colour: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = colour
    material.roughness = roughness
    material.metallic = metallic
    return material


func _make_materials() -> void:
    _stone = _material(Color(0.38, 0.405, 0.41, 1.0), 0.86)
    _stone_dark = _material(Color(0.25, 0.275, 0.285, 1.0), 0.91)
    _glass = _material(Color(0.055, 0.095, 0.115, 0.88), 0.15, 0.08)
    _glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    _bronze = _material(Color(0.24, 0.17, 0.095, 1.0), 0.42, 0.72)
    _metal = _material(Color(0.16, 0.18, 0.19, 1.0), 0.32, 0.70)
    _roof = _material(Color(0.29, 0.305, 0.31, 1.0), 0.79, 0.08)


func _outline_points(document: Dictionary) -> PackedVector2Array:
    var result := PackedVector2Array()
    var geometry = document.get("geometry", {})
    if not geometry is Dictionary:
        return result
    var coords = geometry.get("coordinates", [])
    if not coords is Array or coords.is_empty() or not coords[0] is Array:
        return result
    for raw in coords[0]:
        if raw is Array and raw.size() >= 2:
            result.append(Vector2(float(raw[0]), float(raw[1])))
    if result.size() >= 2 and result[0].distance_to(result[result.size() - 1]) < 0.001:
        result.resize(result.size() - 1)
    return result


func _support_front(points: PackedVector2Array, centre: Vector2, forward: Vector2) -> Vector2:
    var max_projection := -INF
    for point in points:
        max_projection = maxf(max_projection, point.dot(forward))
    # Keep the facade just inside the OSM envelope to cover the generic wall
    # without floating outside the sourced hall footprint.
    var centre_projection := centre.dot(forward)
    return centre + forward * (max_projection - centre_projection - 0.55)


func _local_root_transform(front: Vector2, base_y: float, forward: Vector2) -> Transform3D:
    var side := Vector2(-forward.y, forward.x)
    var x_axis := Vector3(side.x, 0.0, side.y)
    var y_axis := Vector3.UP
    var z_axis := Vector3(-forward.x, 0.0, -forward.y) # local +Z goes into the hall
    return Transform3D(Basis(x_axis, y_axis, z_axis), Vector3(front.x, base_y, front.y))


func _add_box(parent: Node3D, name: String, size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh.material = material
    var instance := MeshInstance3D.new()
    instance.name = name
    instance.mesh = mesh
    instance.position = position
    parent.add_child(instance)
    return instance


func _add_statue(parent: Node3D, x: float, pedestal_y: float) -> void:
    var root := Node3D.new()
    root.name = "TransportAllegorySilhouette"
    root.position = Vector3(x, pedestal_y, -0.72)
    parent.add_child(root)

    var torso := CapsuleMesh.new()
    torso.radius = 0.52
    torso.height = 2.25
    torso.radial_segments = 12
    torso.rings = 5
    torso.material = _bronze
    var body := MeshInstance3D.new()
    body.mesh = torso
    body.position.y = 1.40
    root.add_child(body)

    var head_mesh := SphereMesh.new()
    head_mesh.radius = 0.42
    head_mesh.height = 0.84
    head_mesh.radial_segments = 12
    head_mesh.rings = 6
    head_mesh.material = _bronze
    var head := MeshInstance3D.new()
    head.mesh = head_mesh
    head.position.y = 3.08
    root.add_child(head)

    var base_mesh := CylinderMesh.new()
    base_mesh.top_radius = 0.38
    base_mesh.bottom_radius = 0.72
    base_mesh.height = 0.80
    base_mesh.radial_segments = 10
    base_mesh.material = _bronze
    var lower := MeshInstance3D.new()
    lower.mesh = base_mesh
    lower.position.y = 0.38
    root.add_child(lower)
    facade_statues += 1


func _arch_y(x: float, half_span: float, spring_y: float, apex_y: float) -> float:
    var t := clampf(absf(x) / half_span, 0.0, 1.0)
    return spring_y + (apex_y - spring_y) * pow(maxf(0.0, 1.0 - t * t), 0.58)


func _tube_transform(a: Vector3, b: Vector3, radius: float) -> Transform3D:
    var delta := b - a
    var length := delta.length()
    var direction := delta / maxf(length, 0.0001)
    var rotation := Basis(Quaternion(Vector3.UP, direction))
    return Transform3D(rotation.scaled(Vector3(radius, length, radius)), (a + b) * 0.5)


func _build_arch_multimesh(parent: Node3D, arch_count: int, spacing: float, span: float, hall_length: float, apex: float) -> void:
    var transforms: Array[Transform3D] = []
    var half_span := span * 0.5
    var spring_y := 8.2
    var segments := 22
    var used_depth := minf(hall_length - 12.0, float(arch_count - 1) * spacing)
    var start_z := maxf(7.0, (hall_length - used_depth) * 0.5)

    for arch_index in range(arch_count):
        var z := start_z + float(arch_index) * spacing
        for segment_index in range(segments):
            var x0 := lerpf(-half_span, half_span, float(segment_index) / float(segments))
            var x1 := lerpf(-half_span, half_span, float(segment_index + 1) / float(segments))
            var a := Vector3(x0, _arch_y(x0, half_span, spring_y, apex), z)
            var b := Vector3(x1, _arch_y(x1, half_span, spring_y, apex), z)
            transforms.append(_tube_transform(a, b, 0.22))

    var mesh := CylinderMesh.new()
    mesh.top_radius = 1.0
    mesh.bottom_radius = 1.0
    mesh.height = 1.0
    mesh.radial_segments = 10
    mesh.material = _stone_dark
    var multimesh := MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.mesh = mesh
    multimesh.instance_count = transforms.size()
    for index in range(transforms.size()):
        multimesh.set_instance_transform(index, transforms[index])
    var instance := MultiMeshInstance3D.new()
    instance.name = "TwelveSourcedRoofArches"
    instance.multimesh = multimesh
    parent.add_child(instance)
    arch_instances = transforms.size()


func _build_roof_strips(parent: Node3D, span: float, hall_length: float, apex: float) -> void:
    var half_span := span * 0.5
    var spring_y := 8.2
    var strip_count := 20
    var strip_width := span / float(strip_count)
    for index in range(strip_count):
        var x := lerpf(-half_span + strip_width * 0.5, half_span - strip_width * 0.5, float(index) / float(strip_count - 1))
        var y := _arch_y(x, half_span, spring_y, apex) - 0.28
        _add_box(parent, "RoofSkinStrip", Vector3(strip_width + 0.10, 0.30, hall_length - 12.0), Vector3(x, y, hall_length * 0.5), _roof)
        roof_strips += 1


func _build_facade(parent: Node3D, facade_width: float, apex: float, statue_height: float) -> void:
    var central_width := 44.0
    var side_width := (facade_width - central_width) * 0.5
    var wing_height := 8.6
    var central_height := minf(25.4, apex - statue_height - 1.0)

    _add_box(parent, "LeftStoneWing", Vector3(side_width, wing_height, 4.8), Vector3(-(central_width + side_width) * 0.5, wing_height * 0.5, 2.4), _stone)
    _add_box(parent, "RightStoneWing", Vector3(side_width, wing_height, 4.8), Vector3((central_width + side_width) * 0.5, wing_height * 0.5, 2.4), _stone)
    _add_box(parent, "CentralMonumentalPorch", Vector3(central_width, central_height, 5.8), Vector3(0.0, central_height * 0.5, 2.9), _stone_dark)

    var pilaster_x := [-20.0, -6.65, 6.65, 20.0]
    for raw_x in pilaster_x:
        var x: float = float(raw_x)
        _add_box(parent, "MonumentalPilaster", Vector3(2.35, central_height + 0.8, 1.30), Vector3(x, (central_height + 0.8) * 0.5, -0.42), _stone)
        facade_pilasters += 1
        _add_statue(parent, x, central_height + 0.55)

    # Three large glazed bays between the four pilasters.
    var bay_centres := [-13.3, 0.0, 13.3]
    var bay_widths := [10.4, 9.0, 10.4]
    for index in range(3):
        var bay_x := float(bay_centres[index])
        var bay_width := float(bay_widths[index])
        _add_box(parent, "GrandGlazedBay", Vector3(bay_width, 14.8, 0.16), Vector3(bay_x, 14.4, -1.13), _glass)
        facade_glass_panels += 1
        for mullion_index in range(1, 5):
            var mx := bay_x - bay_width * 0.5 + bay_width * float(mullion_index) / 5.0
            _add_box(parent, "BayVerticalMullion", Vector3(0.15, 14.8, 0.22), Vector3(mx, 14.4, -1.25), _metal)
        for row_index in range(1, 5):
            var my := 7.0 + 14.8 * float(row_index) / 5.0
            _add_box(parent, "BayHorizontalMullion", Vector3(bay_width, 0.13, 0.22), Vector3(bay_x, my, -1.25), _metal)

        _add_box(parent, "BronzeEntrance", Vector3(bay_width * 0.72, 4.8, 0.34), Vector3(bay_x, 3.0, -1.36), _bronze)

    # Seven low square windows on each lateral body, as described by the heritage inventory.
    for raw_side_sign in [-1.0, 1.0]:
        var side_sign: float = float(raw_side_sign)
        var wing_center: float = side_sign * (central_width * 0.5 + side_width * 0.5)
        var usable: float = side_width * 0.80
        for index in range(7):
            var local_offset := lerpf(-usable * 0.5, usable * 0.5, float(index) / 6.0)
            _add_box(parent, "SideLowSquareWindow", Vector3(1.9, 1.9, 0.14), Vector3(wing_center + local_offset, 4.2, -0.08), _glass)
            side_windows += 1

    # Monumental stair flight is photo-guided; exact step dimensions are explicitly non-surveyed.
    for index in range(6):
        var width := 42.0 + float(index) * 1.6
        var depth := 1.18
        _add_box(parent, "EntranceStep", Vector3(width, 0.20, depth), Vector3(0.0, 0.10 + float(index) * 0.20, -1.9 - float(index) * depth), _stone)


func _build() -> void:
    _make_materials()
    var outline := _load_json(OUTLINE_PATH)
    var provenance := _load_json(PROVENANCE_PATH)
    var points := _outline_points(outline)
    if points.size() < 20:
        push_warning("LaekenPalais5HeroPass: validated Palais 5 outline unavailable")
        return
    source_outline_vertices = points.size()

    var facts = provenance.get("architectural_facts", {})
    if not facts is Dictionary:
        push_warning("LaekenPalais5HeroPass: source dimensions unavailable")
        return
    source_height_m = float(facts.get("hall_height_m", 31.0))
    source_span_m = float(facts.get("structural_span_m", 86.0))
    var hall_length := float(facts.get("approx_historic_length_m", 165.0))
    var arch_count := int(facts.get("arch_count", 12))
    var arch_spacing := float(facts.get("arch_spacing_m", 12.0))
    var statue_height := float(facts.get("transport_statue_height_m", 4.3))

    var metrics = outline.get("metrics", {})
    if not metrics is Dictionary:
        return
    var centre := Vector2(float(metrics.get("centroid_x", 0.0)), float(metrics.get("centroid_z", 0.0)))
    var forward := (ATOMIUM - centre).normalized()
    var front := _support_front(points, centre, forward)

    var terrain = get_parent().get_node_or_null("LaekenTerrain")
    if terrain == null or not bool(terrain.get("terrain_loaded")):
        push_warning("LaekenPalais5HeroPass: terrain unavailable")
        return
    var base_y := float(terrain.call("sample_height", front.x, front.y)) + 0.06

    var hero := Node3D.new()
    hero.name = "Palais5HeroGeometry"
    hero.transform = _local_root_transform(front, base_y, forward)
    add_child(hero)

    _build_facade(hero, 90.0, source_height_m, statue_height)
    _build_arch_multimesh(hero, arch_count, arch_spacing, source_span_m, hall_length, source_height_m)
    _build_roof_strips(hero, source_span_m, hall_length, source_height_m)

    hero_ready = (
        facade_pilasters == 4
        and facade_statues == 4
        and facade_glass_panels == 3
        and side_windows == 14
        and arch_instances == arch_count * 22
        and roof_strips == 20
    )
    print("LAEKEN_PALAIS5_HERO_READY: ready=%s outline_vertices=%d height=%.1f span=%.1f arches=%d arch_segments=%d pilasters=%d statues=%d glass_bays=%d side_windows=%d roof_strips=%d" % [
        hero_ready,
        source_outline_vertices,
        source_height_m,
        source_span_m,
        arch_count,
        arch_instances,
        facade_pilasters,
        facade_statues,
        facade_glass_panels,
        side_windows,
        roof_strips,
    ])

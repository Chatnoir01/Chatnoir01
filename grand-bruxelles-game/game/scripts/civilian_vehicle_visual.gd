extends Node3D
class_name CivilianVehicleVisual

@export var paint_color: Color = Color(0.055, 0.16, 0.30, 1.0)
@export_enum("Sedan", "Hatchback", "Wagon") var body_style: int = 0

const QUALITY_CONTRACT := "realistic_european_car_v3"
const STYLE_SEDAN := 0
const STYLE_HATCHBACK := 1
const STYLE_WAGON := 2
const BODY_STATIONS := 16
const GLASS_STATIONS := 10
const RING_VERTICES := 12

const BODY_T := [0.0, 0.035, 0.08, 0.14, 0.21, 0.29, 0.38, 0.47, 0.56, 0.65, 0.74, 0.82, 0.89, 0.94, 0.975, 1.0]
const BODY_WIDTH := [0.70, 0.80, 0.89, 0.96, 1.0, 1.0, 0.995, 1.0, 1.0, 1.0, 1.0, 0.99, 0.96, 0.90, 0.80, 0.72]
const GLASS_U := [0.0, 0.07, 0.16, 0.28, 0.42, 0.58, 0.72, 0.84, 0.93, 1.0]
const GLASS_WIDTH := [0.69, 0.74, 0.78, 0.80, 0.805, 0.805, 0.80, 0.77, 0.72, 0.65]


func _ready() -> void:
    var vehicle: Node3D = get_parent() as Node3D
    if vehicle == null:
        return
    _hide_legacy(vehicle)
    _build_vehicle()


func get_visual_contract() -> Dictionary:
    var profile: Dictionary = _style_profile()
    return {
        "quality": QUALITY_CONTRACT,
        "body_style": str(profile["name"]),
        "length_m": float(profile["length_m"]),
        "width_m": float(profile["width_m"]),
        "height_m": float(profile["height_m"]),
        "wheelbase_m": float(profile["wheelbase_m"]),
        "body_stations": BODY_STATIONS,
        "glass_stations": GLASS_STATIONS,
        "ring_vertices": RING_VERTICES,
        "minimum_mesh_parts": 34,
        "brand_specific": false,
    }


func _hide_legacy(vehicle: Node3D) -> void:
    for path: String in ["Body", "Cabin"]:
        var legacy: Node = vehicle.get_node_or_null(path)
        if legacy is VisualInstance3D:
            (legacy as VisualInstance3D).visible = false


func _style_profile() -> Dictionary:
    match body_style:
        STYLE_HATCHBACK:
            return {
                "name": "hatchback",
                "length_m": 4.10,
                "width_m": 1.80,
                "height_m": 1.46,
                "wheelbase_m": 2.61,
                "rear_deck_y": 0.44,
                "glass_start_t": 0.245,
                "glass_end_t": 0.865,
                "glass_roof": [0.61, 0.82, 0.99, 1.075, 1.095, 1.095, 1.07, 1.015, 0.86, 0.61],
                "roof_size": Vector3(1.27, 0.055, 1.34),
                "roof_pos": Vector3(0.0, 1.085, 0.15),
            }
        STYLE_WAGON:
            return {
                "name": "wagon",
                "length_m": 4.38,
                "width_m": 1.84,
                "height_m": 1.48,
                "wheelbase_m": 2.68,
                "rear_deck_y": 0.45,
                "glass_start_t": 0.235,
                "glass_end_t": 0.865,
                "glass_roof": [0.62, 0.83, 1.00, 1.075, 1.105, 1.105, 1.095, 1.065, 0.97, 0.70],
                "roof_size": Vector3(1.30, 0.055, 1.72),
                "roof_pos": Vector3(0.0, 1.095, 0.30),
            }
        _:
            body_style = STYLE_SEDAN
            return {
                "name": "sedan",
                "length_m": 4.28,
                "width_m": 1.82,
                "height_m": 1.45,
                "wheelbase_m": 2.64,
                "rear_deck_y": 0.37,
                "glass_start_t": 0.245,
                "glass_end_t": 0.755,
                "glass_roof": [0.61, 0.82, 0.99, 1.07, 1.095, 1.095, 1.07, 0.99, 0.79, 0.58],
                "roof_size": Vector3(1.27, 0.055, 1.10),
                "roof_pos": Vector3(0.0, 1.085, 0.07),
            }


func _build_vehicle() -> void:
    var profile: Dictionary = _style_profile()
    var length_m: float = float(profile["length_m"])
    var width_m: float = float(profile["width_m"])
    var wheelbase_m: float = float(profile["wheelbase_m"])
    var half_width: float = width_m * 0.5
    var half_length: float = length_m * 0.5

    var paint: StandardMaterial3D = _material(paint_color, 0.24, 0.42)
    var glass: StandardMaterial3D = _material(Color(0.018, 0.045, 0.068, 0.78), 0.10, 0.10)
    glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    var dark: StandardMaterial3D = _material(Color(0.012, 0.016, 0.021, 1.0), 0.84)
    var rubber: StandardMaterial3D = _material(Color(0.010, 0.012, 0.014, 1.0), 0.96)
    var chrome: StandardMaterial3D = _material(Color(0.46, 0.49, 0.53, 1.0), 0.20, 0.84)
    var alloy: StandardMaterial3D = _material(Color(0.38, 0.40, 0.43, 1.0), 0.25, 0.78)
    var brake_disc: StandardMaterial3D = _material(Color(0.22, 0.23, 0.24, 1.0), 0.44, 0.64)
    var caliper: StandardMaterial3D = _material(Color(0.34, 0.045, 0.028, 1.0), 0.50, 0.28)
    var white_light: StandardMaterial3D = _emissive(Color(0.98, 0.95, 0.82, 1.0), 1.45)
    var red_light: StandardMaterial3D = _emissive(Color(0.82, 0.020, 0.014, 1.0), 1.35)
    var amber_light: StandardMaterial3D = _emissive(Color(1.0, 0.33, 0.020, 1.0), 1.15)
    var plate: StandardMaterial3D = _material(Color(0.95, 0.95, 0.92, 1.0), 0.62)

    _loft_shell("BodyShell", _body_station_data(profile), paint, false)
    _loft_shell("GlassHouse", _glass_station_data(profile), glass, true)
    _box("RoofCap", profile["roof_size"] as Vector3, profile["roof_pos"] as Vector3, paint)

    _box("FrontBumper", Vector3(width_m * 0.88, 0.145, 0.105), Vector3(0.0, -0.105, -half_length + 0.025), dark)
    _box("RearBumper", Vector3(width_m * 0.88, 0.145, 0.105), Vector3(0.0, -0.105, half_length - 0.025), dark)
    _box("FrontGrille", Vector3(width_m * 0.50, 0.19, 0.035), Vector3(0.0, 0.005, -half_length - 0.020), dark)
    _box("GrilleTrim", Vector3(width_m * 0.55, 0.025, 0.040), Vector3(0.0, 0.125, -half_length - 0.022), chrome)
    _box("LowerAirIntake", Vector3(width_m * 0.39, 0.060, 0.040), Vector3(0.0, -0.105, -half_length - 0.022), dark)

    _ellipsoid("HeadlampLeft", Vector3(0.43, 0.16, 0.070), Vector3(-width_m * 0.29, 0.205, -half_length - 0.005), white_light)
    _ellipsoid("HeadlampRight", Vector3(0.43, 0.16, 0.070), Vector3(width_m * 0.29, 0.205, -half_length - 0.005), white_light)
    _ellipsoid("FrontIndicatorLeft", Vector3(0.115, 0.075, 0.072), Vector3(-width_m * 0.42, 0.18, -half_length - 0.006), amber_light)
    _ellipsoid("FrontIndicatorRight", Vector3(0.115, 0.075, 0.072), Vector3(width_m * 0.42, 0.18, -half_length - 0.006), amber_light)
    _ellipsoid("TailLeft", Vector3(0.40, 0.18, 0.070), Vector3(-width_m * 0.29, 0.19, half_length + 0.002), red_light)
    _ellipsoid("TailRight", Vector3(0.40, 0.18, 0.070), Vector3(width_m * 0.29, 0.19, half_length + 0.002), red_light)
    _ellipsoid("RearIndicatorLeft", Vector3(0.10, 0.068, 0.072), Vector3(-width_m * 0.42, 0.19, half_length + 0.004), amber_light)
    _ellipsoid("RearIndicatorRight", Vector3(0.10, 0.068, 0.072), Vector3(width_m * 0.42, 0.19, half_length + 0.004), amber_light)

    _box("FrontPlate", Vector3(0.48, 0.12, 0.030), Vector3(0.0, -0.072, -half_length - 0.043), plate)
    _box("RearPlate", Vector3(0.48, 0.12, 0.030), Vector3(0.0, -0.072, half_length + 0.043), plate)
    _box("FrontPlateRedBand", Vector3(0.48, 0.016, 0.033), Vector3(0.0, -0.124, -half_length - 0.045), red_light)
    _box("RearPlateRedBand", Vector3(0.48, 0.016, 0.033), Vector3(0.0, -0.124, half_length + 0.045), red_light)

    _box("SideSkirtLeft", Vector3(0.038, 0.105, wheelbase_m + 0.34), Vector3(-half_width + 0.010, -0.155, 0.0), dark)
    _box("SideSkirtRight", Vector3(0.038, 0.105, wheelbase_m + 0.34), Vector3(half_width - 0.010, -0.155, 0.0), dark)
    _box("BPillarLeft", Vector3(0.022, 0.52, 0.070), Vector3(-half_width * 0.79, 0.70, 0.04), dark)
    _box("BPillarRight", Vector3(0.022, 0.52, 0.070), Vector3(half_width * 0.79, 0.70, 0.04), dark)
    _box("WindowBeltLeft", Vector3(0.022, 0.026, minf(1.80, length_m * 0.45)), Vector3(-half_width * 0.82, 0.445, 0.03), chrome)
    _box("WindowBeltRight", Vector3(0.022, 0.026, minf(1.80, length_m * 0.45)), Vector3(half_width * 0.82, 0.445, 0.03), chrome)

    _ellipsoid("MirrorLeft", Vector3(0.22, 0.13, 0.30), Vector3(-half_width - 0.095, 0.64, -0.57), paint)
    _ellipsoid("MirrorRight", Vector3(0.22, 0.13, 0.30), Vector3(half_width + 0.095, 0.64, -0.57), paint)
    _ellipsoid("MirrorGlassLeft", Vector3(0.025, 0.090, 0.225), Vector3(-half_width - 0.197, 0.64, -0.57), glass)
    _ellipsoid("MirrorGlassRight", Vector3(0.025, 0.090, 0.225), Vector3(half_width + 0.197, 0.64, -0.57), glass)

    for side: float in [-1.0, 1.0]:
        var side_name: String = "Left" if side < 0.0 else "Right"
        var side_x: float = side * (half_width + 0.010)
        _box("FrontDoorHandle%s" % side_name, Vector3(0.024, 0.032, 0.19), Vector3(side_x, 0.37, -0.38), chrome)
        _box("RearDoorHandle%s" % side_name, Vector3(0.024, 0.032, 0.19), Vector3(side_x, 0.37, 0.64), chrome)
        _box("FrontDoorSeam%s" % side_name, Vector3(0.018, 0.39, 0.018), Vector3(side_x, 0.19, -0.78), dark)
        _box("RearDoorSeam%s" % side_name, Vector3(0.018, 0.39, 0.018), Vector3(side_x, 0.19, 0.26), dark)

    var wheel_x: float = half_width - 0.10
    var wheel_z: float = wheelbase_m * 0.5
    _wheel_assembly("WheelFL", Vector3(-wheel_x, -0.15, -wheel_z), rubber, alloy, brake_disc, caliper)
    _wheel_assembly("WheelFR", Vector3(wheel_x, -0.15, -wheel_z), rubber, alloy, brake_disc, caliper)
    _wheel_assembly("WheelRL", Vector3(-wheel_x, -0.15, wheel_z), rubber, alloy, brake_disc, caliper)
    _wheel_assembly("WheelRR", Vector3(wheel_x, -0.15, wheel_z), rubber, alloy, brake_disc, caliper)

    _cylinder("ExhaustTip", 0.038, 0.18, Vector3(width_m * 0.31, -0.17, half_length + 0.075), chrome, Vector3(PI * 0.5, 0.0, 0.0), 20)


func _body_station_data(profile: Dictionary) -> Array:
    var data: Array = []
    var half_length: float = float(profile["length_m"]) * 0.5
    var half_width: float = float(profile["width_m"]) * 0.5
    var rear_deck: float = float(profile["rear_deck_y"])
    var top_levels: Array = [0.06, 0.14, 0.25, 0.34, 0.42, 0.455, 0.47, 0.48, 0.48, 0.48, 0.47, 0.445, rear_deck, rear_deck - 0.045, 0.22, 0.08]
    for index: int in range(BODY_STATIONS):
        data.append({
            "z": lerpf(-half_length, half_length, float(BODY_T[index])),
            "half_width": half_width * float(BODY_WIDTH[index]),
            "low_y": -0.22,
            "top_y": float(top_levels[index]),
        })
    return data


func _glass_station_data(profile: Dictionary) -> Array:
    var data: Array = []
    var length_m: float = float(profile["length_m"])
    var half_length: float = length_m * 0.5
    var half_width: float = float(profile["width_m"]) * 0.5
    var start_t: float = float(profile["glass_start_t"])
    var end_t: float = float(profile["glass_end_t"])
    var roof_curve: Array = profile["glass_roof"] as Array
    for index: int in range(GLASS_STATIONS):
        var u: float = float(GLASS_U[index])
        var t: float = lerpf(start_t, end_t, u)
        data.append({
            "z": lerpf(-half_length, half_length, t),
            "half_width": half_width * float(GLASS_WIDTH[index]),
            "low_y": 0.435,
            "top_y": float(roof_curve[index]),
        })
    return data


func _loft_shell(name_value: String, stations: Array, material: Material, glass_shape: bool) -> MeshInstance3D:
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    surface.set_smooth_group(0)
    var rings: Array = []
    for station_value: Variant in stations:
        var station: Dictionary = station_value as Dictionary
        rings.append(_glass_ring(station) if glass_shape else _body_ring(station))

    for station_index: int in range(rings.size() - 1):
        var ring_a: PackedVector3Array = rings[station_index]
        var ring_b: PackedVector3Array = rings[station_index + 1]
        for ring_index: int in range(RING_VERTICES):
            var next_index: int = (ring_index + 1) % RING_VERTICES
            _quad(surface, ring_a[ring_index], ring_b[ring_index], ring_b[next_index], ring_a[next_index])

    _cap_ring(surface, rings[0], true)
    _cap_ring(surface, rings[rings.size() - 1], false)
    surface.generate_normals()
    var mesh: ArrayMesh = surface.commit()
    var instance := MeshInstance3D.new()
    instance.name = name_value
    instance.mesh = mesh
    instance.material_override = material
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    add_child(instance)
    return instance


func _body_ring(station: Dictionary) -> PackedVector3Array:
    var z: float = float(station["z"])
    var w: float = float(station["half_width"])
    var low: float = float(station["low_y"])
    var top: float = float(station["top_y"])
    var shoulder: float = lerpf(low, top, 0.78)
    return PackedVector3Array([
        Vector3(-w * 0.70, low, z),
        Vector3(-w * 0.94, low + 0.07, z),
        Vector3(-w, lerpf(low, top, 0.40), z),
        Vector3(-w * 0.96, lerpf(low, top, 0.68), z),
        Vector3(-w * 0.78, shoulder, z),
        Vector3(-w * 0.38, top, z),
        Vector3(w * 0.38, top, z),
        Vector3(w * 0.78, shoulder, z),
        Vector3(w * 0.96, lerpf(low, top, 0.68), z),
        Vector3(w, lerpf(low, top, 0.40), z),
        Vector3(w * 0.94, low + 0.07, z),
        Vector3(w * 0.70, low, z),
    ])


func _glass_ring(station: Dictionary) -> PackedVector3Array:
    var z: float = float(station["z"])
    var w: float = float(station["half_width"])
    var low: float = float(station["low_y"])
    var top: float = float(station["top_y"])
    var mid: float = lerpf(low, top, 0.56)
    return PackedVector3Array([
        Vector3(-w * 0.72, low - 0.012, z),
        Vector3(-w * 0.96, low + 0.035, z),
        Vector3(-w, mid, z),
        Vector3(-w * 0.83, top - 0.075, z),
        Vector3(-w * 0.47, top - 0.015, z),
        Vector3(0.0, top + 0.010, z),
        Vector3(w * 0.47, top - 0.015, z),
        Vector3(w * 0.83, top - 0.075, z),
        Vector3(w, mid, z),
        Vector3(w * 0.96, low + 0.035, z),
        Vector3(w * 0.72, low - 0.012, z),
        Vector3(0.0, low - 0.020, z),
    ])


func _cap_ring(surface: SurfaceTool, ring: PackedVector3Array, reverse: bool) -> void:
    var center := Vector3.ZERO
    for point: Vector3 in ring:
        center += point
    center /= float(ring.size())
    for index: int in range(ring.size()):
        var next_index: int = (index + 1) % ring.size()
        if reverse:
            _triangle(surface, center, ring[next_index], ring[index])
        else:
            _triangle(surface, center, ring[index], ring[next_index])


func _quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
    _triangle(surface, a, b, c)
    _triangle(surface, a, c, d)


func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
    surface.add_vertex(a)
    surface.add_vertex(b)
    surface.add_vertex(c)


func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = metallic
    return material


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
    var material: StandardMaterial3D = _material(color, 0.34)
    material.emission_enabled = true
    material.emission = color
    material.emission_energy_multiplier = energy
    return material


func _box(name_value: String, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh.material = material
    var instance := MeshInstance3D.new()
    instance.name = name_value
    instance.mesh = mesh
    instance.position = pos
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    add_child(instance)
    return instance


func _ellipsoid(name_value: String, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
    var mesh := SphereMesh.new()
    mesh.radius = 0.5
    mesh.height = 1.0
    mesh.radial_segments = 16
    mesh.rings = 8
    mesh.material = material
    var instance := MeshInstance3D.new()
    instance.name = name_value
    instance.mesh = mesh
    instance.position = pos
    instance.scale = size
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    add_child(instance)
    return instance


func _cylinder(name_value: String, radius: float, width: float, pos: Vector3, material: Material, rotation_value: Vector3, segments: int) -> MeshInstance3D:
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = width
    mesh.radial_segments = segments
    mesh.material = material
    var instance := MeshInstance3D.new()
    instance.name = name_value
    instance.mesh = mesh
    instance.position = pos
    instance.rotation = rotation_value
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    add_child(instance)
    return instance


func _wheel_assembly(name_value: String, pos: Vector3, tire_material: Material, rim_material: Material, disc_material: Material, caliper_material: Material) -> Node3D:
    var root_wheel := Node3D.new()
    root_wheel.name = name_value
    root_wheel.position = pos
    root_wheel.rotation.z = PI * 0.5
    add_child(root_wheel)

    var tire_mesh := CylinderMesh.new()
    tire_mesh.top_radius = 0.315
    tire_mesh.bottom_radius = 0.315
    tire_mesh.height = 0.225
    tire_mesh.radial_segments = 32
    tire_mesh.material = tire_material
    var tire := MeshInstance3D.new()
    tire.name = "Tire"
    tire.mesh = tire_mesh
    tire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    root_wheel.add_child(tire)

    var rim_mesh := CylinderMesh.new()
    rim_mesh.top_radius = 0.205
    rim_mesh.bottom_radius = 0.205
    rim_mesh.height = 0.233
    rim_mesh.radial_segments = 24
    rim_mesh.material = rim_material
    var rim := MeshInstance3D.new()
    rim.name = "Rim"
    rim.mesh = rim_mesh
    rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    root_wheel.add_child(rim)

    var disc_mesh := CylinderMesh.new()
    disc_mesh.top_radius = 0.145
    disc_mesh.bottom_radius = 0.145
    disc_mesh.height = 0.238
    disc_mesh.radial_segments = 24
    disc_mesh.material = disc_material
    var disc := MeshInstance3D.new()
    disc.name = "BrakeDisc"
    disc.mesh = disc_mesh
    root_wheel.add_child(disc)

    var hub_mesh := CylinderMesh.new()
    hub_mesh.top_radius = 0.052
    hub_mesh.bottom_radius = 0.052
    hub_mesh.height = 0.246
    hub_mesh.radial_segments = 20
    hub_mesh.material = rim_material
    var hub := MeshInstance3D.new()
    hub.name = "Hub"
    hub.mesh = hub_mesh
    root_wheel.add_child(hub)

    for index: int in range(5):
        var spoke_mesh := BoxMesh.new()
        spoke_mesh.size = Vector3(0.035, 0.242, 0.145)
        spoke_mesh.material = rim_material
        var spoke := MeshInstance3D.new()
        spoke.name = "Spoke%d" % index
        spoke.mesh = spoke_mesh
        spoke.position = Vector3(0.0, 0.0, 0.075)
        spoke.rotation.y = TAU * float(index) / 5.0
        root_wheel.add_child(spoke)

    var caliper_mesh := BoxMesh.new()
    caliper_mesh.size = Vector3(0.065, 0.245, 0.085)
    caliper_mesh.material = caliper_material
    var caliper := MeshInstance3D.new()
    caliper.name = "BrakeCaliper"
    caliper.mesh = caliper_mesh
    caliper.position = Vector3(0.0, 0.0, 0.115)
    root_wheel.add_child(caliper)
    return root_wheel

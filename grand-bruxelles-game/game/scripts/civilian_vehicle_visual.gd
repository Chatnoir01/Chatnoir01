extends Node3D
class_name CivilianVehicleVisual

@export var paint_color: Color = Color(0.055, 0.16, 0.30, 1.0)
@export_enum("Sedan", "Hatchback", "Wagon") var body_style: int = 0

const QUALITY_CONTRACT := "realistic_european_car_v2"
const STYLE_SEDAN := 0
const STYLE_HATCHBACK := 1
const STYLE_WAGON := 2


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
                "body_sections": [
                    Vector4(-2.05, 0.74, -0.22, 0.13),
                    Vector4(-1.58, 0.89, -0.22, 0.39),
                    Vector4(1.48, 0.90, -0.22, 0.43),
                    Vector4(2.05, 0.78, -0.22, 0.20),
                ],
                "glass_sections": [
                    Vector4(-0.88, 0.74, 0.43, 0.62),
                    Vector4(-0.53, 0.66, 0.43, 1.03),
                    Vector4(0.82, 0.67, 0.43, 1.04),
                    Vector4(1.43, 0.76, 0.43, 0.67),
                ],
                "roof_size": Vector3(1.30, 0.075, 1.38),
                "roof_pos": Vector3(0.0, 1.045, 0.17),
                "rear_glass_z": 1.46,
            }
        STYLE_WAGON:
            return {
                "name": "wagon",
                "length_m": 4.38,
                "width_m": 1.84,
                "height_m": 1.48,
                "wheelbase_m": 2.68,
                "body_sections": [
                    Vector4(-2.19, 0.76, -0.22, 0.14),
                    Vector4(-1.66, 0.91, -0.22, 0.40),
                    Vector4(1.70, 0.92, -0.22, 0.45),
                    Vector4(2.19, 0.82, -0.22, 0.21),
                ],
                "glass_sections": [
                    Vector4(-0.91, 0.76, 0.44, 0.63),
                    Vector4(-0.56, 0.68, 0.44, 1.04),
                    Vector4(1.34, 0.70, 0.44, 1.05),
                    Vector4(1.72, 0.78, 0.44, 0.72),
                ],
                "roof_size": Vector3(1.34, 0.075, 1.83),
                "roof_pos": Vector3(0.0, 1.055, 0.34),
                "rear_glass_z": 1.74,
            }
        _:
            body_style = STYLE_SEDAN
            return {
                "name": "sedan",
                "length_m": 4.28,
                "width_m": 1.82,
                "height_m": 1.45,
                "wheelbase_m": 2.64,
                "body_sections": [
                    Vector4(-2.14, 0.75, -0.22, 0.14),
                    Vector4(-1.62, 0.90, -0.22, 0.40),
                    Vector4(1.58, 0.91, -0.22, 0.43),
                    Vector4(2.14, 0.79, -0.22, 0.16),
                ],
                "glass_sections": [
                    Vector4(-0.90, 0.75, 0.43, 0.62),
                    Vector4(-0.54, 0.67, 0.43, 1.03),
                    Vector4(0.75, 0.68, 0.43, 1.04),
                    Vector4(1.08, 0.76, 0.43, 0.62),
                ],
                "roof_size": Vector3(1.30, 0.075, 1.18),
                "roof_pos": Vector3(0.0, 1.045, 0.10),
                "rear_glass_z": 1.10,
            }


func _build_vehicle() -> void:
    var profile: Dictionary = _style_profile()
    var length_m: float = float(profile["length_m"])
    var width_m: float = float(profile["width_m"])
    var wheelbase_m: float = float(profile["wheelbase_m"])
    var half_width: float = width_m * 0.5
    var half_length: float = length_m * 0.5

    var paint: StandardMaterial3D = _material(paint_color, 0.30, 0.46)
    var glass: StandardMaterial3D = _material(Color(0.022, 0.050, 0.075, 0.80), 0.12, 0.12)
    glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    var dark: StandardMaterial3D = _material(Color(0.015, 0.019, 0.024, 1.0), 0.86)
    var rubber: StandardMaterial3D = _material(Color(0.012, 0.014, 0.017, 1.0), 0.96)
    var chrome: StandardMaterial3D = _material(Color(0.43, 0.46, 0.50, 1.0), 0.22, 0.82)
    var alloy: StandardMaterial3D = _material(Color(0.34, 0.36, 0.39, 1.0), 0.28, 0.74)
    var brake_disc: StandardMaterial3D = _material(Color(0.22, 0.23, 0.24, 1.0), 0.46, 0.62)
    var white_light: StandardMaterial3D = _emissive(Color(0.96, 0.94, 0.82, 1.0), 1.45)
    var red_light: StandardMaterial3D = _emissive(Color(0.82, 0.022, 0.016, 1.0), 1.35)
    var amber_light: StandardMaterial3D = _emissive(Color(1.0, 0.34, 0.025, 1.0), 1.15)
    var plate: StandardMaterial3D = _material(Color(0.94, 0.94, 0.91, 1.0), 0.64)

    _section_shell("BodyShell", profile["body_sections"] as Array, paint)
    _section_shell("GlassHouse", profile["glass_sections"] as Array, glass)
    _box("RoofCap", profile["roof_size"] as Vector3, profile["roof_pos"] as Vector3, paint)

    _box("FrontBumper", Vector3(width_m * 0.90, 0.17, 0.15), Vector3(0.0, -0.08, -half_length + 0.015), dark)
    _box("RearBumper", Vector3(width_m * 0.90, 0.17, 0.15), Vector3(0.0, -0.08, half_length - 0.015), dark)
    _box("FrontGrille", Vector3(width_m * 0.54, 0.22, 0.043), Vector3(0.0, 0.015, -half_length - 0.018), dark)
    _box("GrilleTrim", Vector3(width_m * 0.58, 0.028, 0.048), Vector3(0.0, 0.145, -half_length - 0.020), chrome)
    _box("LowerAirIntake", Vector3(width_m * 0.42, 0.075, 0.047), Vector3(0.0, -0.105, -half_length - 0.020), dark)

    _box("HeadlampLeft", Vector3(0.40, 0.15, 0.052), Vector3(-width_m * 0.29, 0.205, -half_length + 0.005), white_light)
    _box("HeadlampRight", Vector3(0.40, 0.15, 0.052), Vector3(width_m * 0.29, 0.205, -half_length + 0.005), white_light)
    _box("FrontIndicatorLeft", Vector3(0.105, 0.075, 0.054), Vector3(-width_m * 0.425, 0.185, -half_length + 0.007), amber_light)
    _box("FrontIndicatorRight", Vector3(0.105, 0.075, 0.054), Vector3(width_m * 0.425, 0.185, -half_length + 0.007), amber_light)
    _box("TailLeft", Vector3(0.38, 0.17, 0.052), Vector3(-width_m * 0.29, 0.19, half_length - 0.004), red_light)
    _box("TailRight", Vector3(0.38, 0.17, 0.052), Vector3(width_m * 0.29, 0.19, half_length - 0.004), red_light)
    _box("RearIndicatorLeft", Vector3(0.09, 0.065, 0.054), Vector3(-width_m * 0.43, 0.19, half_length - 0.006), amber_light)
    _box("RearIndicatorRight", Vector3(0.09, 0.065, 0.054), Vector3(width_m * 0.43, 0.19, half_length - 0.006), amber_light)

    _box("FrontPlate", Vector3(0.48, 0.12, 0.032), Vector3(0.0, -0.075, -half_length - 0.040), plate)
    _box("RearPlate", Vector3(0.48, 0.12, 0.032), Vector3(0.0, -0.075, half_length + 0.040), plate)
    _box("FrontPlateRedBand", Vector3(0.48, 0.017, 0.035), Vector3(0.0, -0.124, -half_length - 0.043), red_light)
    _box("RearPlateRedBand", Vector3(0.48, 0.017, 0.035), Vector3(0.0, -0.124, half_length + 0.043), red_light)

    _box("SideSkirtLeft", Vector3(0.045, 0.12, wheelbase_m + 0.36), Vector3(-half_width + 0.015, -0.15, 0.0), dark)
    _box("SideSkirtRight", Vector3(0.045, 0.12, wheelbase_m + 0.36), Vector3(half_width - 0.015, -0.15, 0.0), dark)
    _box("BPillarLeft", Vector3(0.025, 0.57, 0.085), Vector3(-half_width + 0.17, 0.70, 0.04), dark)
    _box("BPillarRight", Vector3(0.025, 0.57, 0.085), Vector3(half_width - 0.17, 0.70, 0.04), dark)
    _box("WindowBeltLeft", Vector3(0.026, 0.030, 1.75), Vector3(-half_width + 0.15, 0.445, 0.03), chrome)
    _box("WindowBeltRight", Vector3(0.026, 0.030, 1.75), Vector3(half_width - 0.15, 0.445, 0.03), chrome)

    _box("MirrorLeft", Vector3(0.20, 0.12, 0.30), Vector3(-half_width - 0.095, 0.64, -0.57), paint)
    _box("MirrorRight", Vector3(0.20, 0.12, 0.30), Vector3(half_width + 0.095, 0.64, -0.57), paint)
    _box("MirrorGlassLeft", Vector3(0.023, 0.085, 0.22), Vector3(-half_width - 0.198, 0.64, -0.57), glass)
    _box("MirrorGlassRight", Vector3(0.023, 0.085, 0.22), Vector3(half_width + 0.198, 0.64, -0.57), glass)

    for side: float in [-1.0, 1.0]:
        var side_name: String = "Left" if side < 0.0 else "Right"
        var side_x: float = side * (half_width + 0.012)
        _box("FrontDoorHandle%s" % side_name, Vector3(0.028, 0.035, 0.20), Vector3(side_x, 0.38, -0.37), chrome)
        _box("RearDoorHandle%s" % side_name, Vector3(0.028, 0.035, 0.20), Vector3(side_x, 0.38, 0.66), chrome)

    var wheel_x: float = half_width - 0.11
    var wheel_z: float = wheelbase_m * 0.5
    _wheel_assembly("WheelFL", Vector3(-wheel_x, -0.15, -wheel_z), rubber, alloy, brake_disc)
    _wheel_assembly("WheelFR", Vector3(wheel_x, -0.15, -wheel_z), rubber, alloy, brake_disc)
    _wheel_assembly("WheelRL", Vector3(-wheel_x, -0.15, wheel_z), rubber, alloy, brake_disc)
    _wheel_assembly("WheelRR", Vector3(wheel_x, -0.15, wheel_z), rubber, alloy, brake_disc)

    _cylinder("ExhaustTip", 0.040, 0.19, Vector3(width_m * 0.31, -0.17, half_length + 0.075), chrome, Vector3(PI * 0.5, 0.0, 0.0), 18)


func _section_shell(name_value: String, sections: Array, material: Material) -> MeshInstance3D:
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    for index: int in range(sections.size() - 1):
        var a: Vector4 = sections[index] as Vector4
        var b: Vector4 = sections[index + 1] as Vector4
        var a_lb := Vector3(-a.y, a.z, a.x)
        var a_rb := Vector3(a.y, a.z, a.x)
        var a_lt := Vector3(-a.y, a.w, a.x)
        var a_rt := Vector3(a.y, a.w, a.x)
        var b_lb := Vector3(-b.y, b.z, b.x)
        var b_rb := Vector3(b.y, b.z, b.x)
        var b_lt := Vector3(-b.y, b.w, b.x)
        var b_rt := Vector3(b.y, b.w, b.x)
        _quad(surface, a_lt, b_lt, b_rt, a_rt)
        _quad(surface, a_lb, a_rb, b_rb, b_lb)
        _quad(surface, a_lb, b_lb, b_lt, a_lt)
        _quad(surface, a_rt, b_rt, b_rb, a_rb)
    var first: Vector4 = sections[0] as Vector4
    var last: Vector4 = sections[sections.size() - 1] as Vector4
    _quad(surface, Vector3(-first.y, first.z, first.x), Vector3(-first.y, first.w, first.x), Vector3(first.y, first.w, first.x), Vector3(first.y, first.z, first.x))
    _quad(surface, Vector3(-last.y, last.z, last.x), Vector3(last.y, last.z, last.x), Vector3(last.y, last.w, last.x), Vector3(-last.y, last.w, last.x))
    surface.generate_normals()
    var mesh := surface.commit()
    var instance := MeshInstance3D.new()
    instance.name = name_value
    instance.mesh = mesh
    instance.material_override = material
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    add_child(instance)
    return instance


func _quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
    surface.set_smooth_group(-1)
    surface.add_vertex(a)
    surface.add_vertex(b)
    surface.add_vertex(c)
    surface.add_vertex(a)
    surface.add_vertex(c)
    surface.add_vertex(d)


func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = metallic
    return material


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
    var material: StandardMaterial3D = _material(color, 0.38)
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


func _wheel_assembly(name_value: String, pos: Vector3, tire_material: Material, rim_material: Material, disc_material: Material) -> Node3D:
    var root_wheel := Node3D.new()
    root_wheel.name = name_value
    root_wheel.position = pos
    root_wheel.rotation.z = PI * 0.5
    add_child(root_wheel)

    var tire_mesh := CylinderMesh.new()
    tire_mesh.top_radius = 0.315
    tire_mesh.bottom_radius = 0.315
    tire_mesh.height = 0.225
    tire_mesh.radial_segments = 24
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
    rim_mesh.radial_segments = 18
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
    disc_mesh.radial_segments = 18
    disc_mesh.material = disc_material
    var disc := MeshInstance3D.new()
    disc.name = "BrakeDisc"
    disc.mesh = disc_mesh
    root_wheel.add_child(disc)
    return root_wheel

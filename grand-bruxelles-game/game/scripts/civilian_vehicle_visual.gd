extends Node3D

@export var paint_color: Color = Color(0.055, 0.16, 0.30, 1.0)


func _ready() -> void:
    var vehicle: Node3D = get_parent() as Node3D
    if vehicle == null:
        return
    _hide_legacy(vehicle)
    _build_vehicle()


func _hide_legacy(vehicle: Node3D) -> void:
    for path: String in ["Body", "Cabin"]:
        var legacy: Node = vehicle.get_node_or_null(path)
        if legacy is VisualInstance3D:
            (legacy as VisualInstance3D).visible = false


func _build_vehicle() -> void:
    var paint: StandardMaterial3D = _material(paint_color, 0.32, 0.42)
    var glass: StandardMaterial3D = _material(Color(0.025, 0.055, 0.08, 0.78), 0.14, 0.16)
    glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    var dark: StandardMaterial3D = _material(Color(0.018, 0.022, 0.028, 1.0), 0.82)
    var chrome: StandardMaterial3D = _material(Color(0.38, 0.40, 0.42, 1.0), 0.34, 0.72)
    var white_light: StandardMaterial3D = _emissive(Color(0.95, 0.92, 0.80, 1.0), 1.4)
    var red_light: StandardMaterial3D = _emissive(Color(0.80, 0.025, 0.018, 1.0), 1.25)
    var plate: StandardMaterial3D = _material(Color(0.92, 0.92, 0.90, 1.0), 0.70)

    _box("LowerBody", Vector3(1.88, 0.52, 4.18), Vector3(0.0, 0.02, 0.0), paint)
    _box("FrontBumper", Vector3(1.84, 0.25, 0.22), Vector3(0.0, -0.08, -2.12), paint)
    _box("RearBumper", Vector3(1.84, 0.25, 0.22), Vector3(0.0, -0.08, 2.12), paint)
    _box("Hood", Vector3(1.76, 0.22, 1.34), Vector3(0.0, 0.40, -1.28), paint)
    _box("Cabin", Vector3(1.58, 0.68, 1.90), Vector3(0.0, 0.74, 0.14), glass)
    _box("Roof", Vector3(1.53, 0.14, 1.64), Vector3(0.0, 1.10, 0.18), paint)
    _box("A_Pillar", Vector3(1.64, 0.09, 0.10), Vector3(0.0, 0.82, -0.80), dark)
    _box("C_Pillar", Vector3(1.64, 0.09, 0.10), Vector3(0.0, 0.82, 1.02), dark)
    _box("FrontGrille", Vector3(1.10, 0.24, 0.05), Vector3(0.0, 0.08, -2.25), dark)
    _box("GrilleTrim", Vector3(1.16, 0.035, 0.055), Vector3(0.0, 0.20, -2.26), chrome)

    _box("HeadlampLeft", Vector3(0.45, 0.17, 0.06), Vector3(-0.55, 0.29, -2.24), white_light)
    _box("HeadlampRight", Vector3(0.45, 0.17, 0.06), Vector3(0.55, 0.29, -2.24), white_light)
    _box("TailLeft", Vector3(0.42, 0.18, 0.06), Vector3(-0.56, 0.29, 2.24), red_light)
    _box("TailRight", Vector3(0.42, 0.18, 0.06), Vector3(0.56, 0.29, 2.24), red_light)
    _box("FrontPlate", Vector3(0.50, 0.13, 0.04), Vector3(0.0, 0.02, -2.29), plate)
    _box("RearPlate", Vector3(0.50, 0.13, 0.04), Vector3(0.0, 0.02, 2.29), plate)

    for x: float in [-0.93, 0.93]:
        for z: float in [-1.38, 1.38]:
            var wheel: MeshInstance3D = _wheel(Vector3(x, -0.15, z), dark)
            wheel.rotation.z = PI * 0.5


func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = metallic
    return material


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
    var material: StandardMaterial3D = _material(color, 0.40)
    material.emission_enabled = true
    material.emission = color
    material.emission_energy_multiplier = energy
    return material


func _box(name_value: String, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
    var mesh: BoxMesh = BoxMesh.new()
    mesh.size = size
    mesh.material = material
    var instance: MeshInstance3D = MeshInstance3D.new()
    instance.name = name_value
    instance.mesh = mesh
    instance.position = pos
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    add_child(instance)
    return instance


func _wheel(pos: Vector3, material: Material) -> MeshInstance3D:
    var mesh: CylinderMesh = CylinderMesh.new()
    mesh.top_radius = 0.31
    mesh.bottom_radius = 0.31
    mesh.height = 0.24
    mesh.radial_segments = 16
    mesh.material = material
    var instance: MeshInstance3D = MeshInstance3D.new()
    instance.name = "Wheel"
    instance.mesh = mesh
    instance.position = pos
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    add_child(instance)
    return instance

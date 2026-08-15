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

    _section_shell(
        "BodyShell",
        [
            Vector4(-2.18, 0.82, -0.20, 0.10),
            Vector4(-1.62, 0.92, -0.20, 0.38),
            Vector4(0.92, 0.95, -0.20, 0.44),
            Vector4(2.16, 0.84, -0.20, 0.18),
        ],
        paint
    )
    _section_shell(
        "GlassHouse",
        [
            Vector4(-0.88, 0.76, 0.43, 0.62),
            Vector4(-0.52, 0.67, 0.43, 1.04),
            Vector4(0.78, 0.66, 0.43, 1.05),
            Vector4(1.12, 0.75, 0.43, 0.62),
        ],
        glass
    )
    _box("RoofCap", Vector3(1.30, 0.09, 1.32), Vector3(0.0, 1.055, 0.14), paint)
    _box("FrontBumper", Vector3(1.66, 0.18, 0.16), Vector3(0.0, -0.08, -2.18), dark)
    _box("RearBumper", Vector3(1.66, 0.18, 0.16), Vector3(0.0, -0.08, 2.18), dark)
    _box("FrontGrille", Vector3(0.96, 0.21, 0.045), Vector3(0.0, 0.02, -2.205), dark)
    _box("GrilleTrim", Vector3(1.02, 0.03, 0.050), Vector3(0.0, 0.15, -2.21), chrome)

    _box("HeadlampLeft", Vector3(0.42, 0.16, 0.055), Vector3(-0.53, 0.20, -2.19), white_light)
    _box("HeadlampRight", Vector3(0.42, 0.16, 0.055), Vector3(0.53, 0.20, -2.19), white_light)
    _box("TailLeft", Vector3(0.39, 0.17, 0.055), Vector3(-0.52, 0.18, 2.18), red_light)
    _box("TailRight", Vector3(0.39, 0.17, 0.055), Vector3(0.52, 0.18, 2.18), red_light)
    _box("FrontPlate", Vector3(0.48, 0.12, 0.035), Vector3(0.0, -0.08, -2.225), plate)
    _box("RearPlate", Vector3(0.48, 0.12, 0.035), Vector3(0.0, -0.08, 2.225), plate)

    for x: float in [-0.93, 0.93]:
        for z: float in [-1.38, 1.38]:
            var wheel: MeshInstance3D = _wheel(Vector3(x, -0.15, z), dark)
            wheel.rotation.z = PI * 0.5


func _section_shell(name_value: String, sections: Array[Vector4], material: Material) -> MeshInstance3D:
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    for index: int in range(sections.size() - 1):
        var a: Vector4 = sections[index]
        var b: Vector4 = sections[index + 1]
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
    var first: Vector4 = sections[0]
    var last: Vector4 = sections[sections.size() - 1]
    _quad(
        surface,
        Vector3(-first.y, first.z, first.x),
        Vector3(-first.y, first.w, first.x),
        Vector3(first.y, first.w, first.x),
        Vector3(first.y, first.z, first.x)
    )
    _quad(
        surface,
        Vector3(-last.y, last.z, last.x),
        Vector3(last.y, last.z, last.x),
        Vector3(last.y, last.w, last.x),
        Vector3(-last.y, last.w, last.x)
    )
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

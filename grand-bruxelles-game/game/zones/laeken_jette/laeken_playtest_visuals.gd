extends Node

## Playtest-only visual replacement for the generic capsule player and box car.
## Gameplay/collision/controllers remain untouched; this script only changes the
## visible prototype geometry inside the isolated Laeken test scene.

var _player: CharacterBody3D
var _left_leg: Node3D
var _right_leg: Node3D
var _left_arm: Node3D
var _right_arm: Node3D
var _walk_clock: float = 0.0

var _skin: StandardMaterial3D
var _jacket: StandardMaterial3D
var _trousers: StandardMaterial3D
var _shoe: StandardMaterial3D
var _car_paint: StandardMaterial3D
var _car_dark: StandardMaterial3D
var _car_glass: StandardMaterial3D
var _car_light: StandardMaterial3D
var _car_tail: StandardMaterial3D


func _ready() -> void:
    call_deferred("_build_visuals")


func _process(delta: float) -> void:
    if _player == null or _left_leg == null:
        return
    var horizontal_speed := Vector2(_player.velocity.x, _player.velocity.z).length()
    if horizontal_speed > 0.35:
        _walk_clock += delta * clampf(horizontal_speed * 1.45, 5.0, 14.0)
        var swing := sin(_walk_clock) * 0.52
        _left_leg.rotation.x = swing
        _right_leg.rotation.x = -swing
        _left_arm.rotation.x = -swing * 0.72
        _right_arm.rotation.x = swing * 0.72
    else:
        _left_leg.rotation.x = lerpf(_left_leg.rotation.x, 0.0, delta * 8.0)
        _right_leg.rotation.x = lerpf(_right_leg.rotation.x, 0.0, delta * 8.0)
        _left_arm.rotation.x = lerpf(_left_arm.rotation.x, 0.0, delta * 8.0)
        _right_arm.rotation.x = lerpf(_right_arm.rotation.x, 0.0, delta * 8.0)


func _build_visuals() -> void:
    _make_materials()
    _player = get_parent().get_node_or_null("Player") as CharacterBody3D
    var car := get_parent().get_node_or_null("PrototypeCar") as CharacterBody3D
    if _player != null:
        var old_player_mesh := _player.get_node_or_null("MeshInstance3D") as MeshInstance3D
        if old_player_mesh != null:
            old_player_mesh.visible = false
        _build_humanoid(_player)
    if car != null:
        var old_body := car.get_node_or_null("Body") as MeshInstance3D
        if old_body != null:
            old_body.visible = false
        var old_cabin := car.get_node_or_null("Cabin") as CSGBox3D
        if old_cabin != null:
            old_cabin.visible = false
        _build_car(car)
    print("LAEKEN_PLAYTEST_VISUALS_READY")


func _make_materials() -> void:
    _skin = _material(Color(0.52, 0.34, 0.23, 1.0), 0.82)
    _jacket = _material(Color(0.075, 0.105, 0.15, 1.0), 0.76)
    _trousers = _material(Color(0.075, 0.075, 0.082, 1.0), 0.88)
    _shoe = _material(Color(0.025, 0.027, 0.030, 1.0), 0.78)
    _car_paint = _material(Color(0.07, 0.20, 0.34, 1.0), 0.28, 0.42)
    _car_dark = _material(Color(0.025, 0.028, 0.032, 1.0), 0.48, 0.12)
    _car_glass = _material(Color(0.055, 0.095, 0.125, 0.72), 0.10, 0.16)
    _car_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    _car_light = _material(Color(0.93, 0.88, 0.67, 1.0), 0.18, 0.02)
    _car_tail = _material(Color(0.55, 0.035, 0.025, 1.0), 0.28, 0.02)


func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = metallic
    return material


func _build_humanoid(parent: Node3D) -> void:
    var visual := Node3D.new()
    visual.name = "PlayableHumanoidVisual"
    parent.add_child(visual)

    _add_capsule(visual, "Torso", 0.27, 0.82, Vector3(0.0, 0.18, 0.0), _jacket)
    _add_sphere(visual, "Head", 0.20, Vector3(0.0, 0.84, -0.015), _skin)
    _add_box(visual, "Hair", Vector3(0.32, 0.12, 0.29), Vector3(0.0, 1.015, -0.005), _shoe)

    _left_leg = _limb_root(visual, "LeftLeg", Vector3(-0.14, -0.28, 0.0))
    _right_leg = _limb_root(visual, "RightLeg", Vector3(0.14, -0.28, 0.0))
    _add_capsule(_left_leg, "Leg", 0.09, 0.66, Vector3(0.0, -0.27, 0.0), _trousers)
    _add_capsule(_right_leg, "Leg", 0.09, 0.66, Vector3(0.0, -0.27, 0.0), _trousers)
    _add_box(_left_leg, "Shoe", Vector3(0.18, 0.11, 0.32), Vector3(0.0, -0.60, -0.07), _shoe)
    _add_box(_right_leg, "Shoe", Vector3(0.18, 0.11, 0.32), Vector3(0.0, -0.60, -0.07), _shoe)

    _left_arm = _limb_root(visual, "LeftArm", Vector3(-0.34, 0.42, 0.0))
    _right_arm = _limb_root(visual, "RightArm", Vector3(0.34, 0.42, 0.0))
    _add_capsule(_left_arm, "Arm", 0.075, 0.58, Vector3(0.0, -0.24, 0.0), _jacket)
    _add_capsule(_right_arm, "Arm", 0.075, 0.58, Vector3(0.0, -0.24, 0.0), _jacket)
    _add_sphere(_left_arm, "Hand", 0.085, Vector3(0.0, -0.54, 0.0), _skin)
    _add_sphere(_right_arm, "Hand", 0.085, Vector3(0.0, -0.54, 0.0), _skin)


func _limb_root(parent: Node3D, node_name: String, position: Vector3) -> Node3D:
    var root := Node3D.new()
    root.name = node_name
    root.position = position
    parent.add_child(root)
    return root


func _build_car(parent: Node3D) -> void:
    var visual := Node3D.new()
    visual.name = "PlayableCarVisual"
    parent.add_child(visual)

    # Compact Brussels-street hatchback silhouette; visual-only placeholder.
    _add_box(visual, "LowerBody", Vector3(1.82, 0.52, 4.02), Vector3(0.0, -0.02, 0.0), _car_paint)
    _add_box(visual, "Hood", Vector3(1.70, 0.30, 1.05), Vector3(0.0, 0.30, -1.36), _car_paint)
    _add_box(visual, "RearDeck", Vector3(1.72, 0.28, 0.62), Vector3(0.0, 0.31, 1.55), _car_paint)
    _add_box(visual, "CabinShell", Vector3(1.56, 0.75, 1.95), Vector3(0.0, 0.61, 0.12), _car_paint)
    _add_box(visual, "Windshield", Vector3(1.42, 0.50, 0.045), Vector3(0.0, 0.67, -0.88), _car_glass, deg_to_rad(-16.0))
    _add_box(visual, "RearGlass", Vector3(1.40, 0.46, 0.045), Vector3(0.0, 0.65, 1.10), _car_glass, deg_to_rad(15.0))

    for side_x in [-0.785, 0.785]:
        _add_box(visual, "SideGlass", Vector3(0.035, 0.48, 1.45), Vector3(side_x, 0.66, 0.10), _car_glass)
    for z_value in [-1.30, 1.30]:
        for x_value in [-0.93, 0.93]:
            _add_wheel(visual, Vector3(x_value, -0.31, z_value))

    for x_value in [-0.58, 0.58]:
        _add_box(visual, "HeadLamp", Vector3(0.34, 0.18, 0.06), Vector3(x_value, 0.11, -2.035), _car_light)
        _add_box(visual, "TailLamp", Vector3(0.32, 0.17, 0.055), Vector3(x_value, 0.12, 2.035), _car_tail)

    _add_box(visual, "FrontBumper", Vector3(1.70, 0.14, 0.12), Vector3(0.0, -0.13, -2.04), _car_dark)
    _add_box(visual, "RearBumper", Vector3(1.70, 0.14, 0.12), Vector3(0.0, -0.13, 2.04), _car_dark)


func _add_wheel(parent: Node3D, position: Vector3) -> void:
    var mesh := CylinderMesh.new()
    mesh.top_radius = 0.34
    mesh.bottom_radius = 0.34
    mesh.height = 0.24
    mesh.radial_segments = 14
    mesh.material = _car_dark
    var instance := MeshInstance3D.new()
    instance.name = "Wheel"
    instance.mesh = mesh
    instance.position = position
    instance.rotation.z = PI * 0.5
    parent.add_child(instance)


func _add_box(parent: Node3D, node_name: String, size: Vector3, position: Vector3, material: Material, rotation_x: float = 0.0) -> void:
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh.material = material
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    instance.position = position
    instance.rotation.x = rotation_x
    parent.add_child(instance)


func _add_sphere(parent: Node3D, node_name: String, radius: float, position: Vector3, material: Material) -> void:
    var mesh := SphereMesh.new()
    mesh.radius = radius
    mesh.height = radius * 2.0
    mesh.radial_segments = 12
    mesh.rings = 7
    mesh.material = material
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    instance.position = position
    parent.add_child(instance)


func _add_capsule(parent: Node3D, node_name: String, radius: float, height: float, position: Vector3, material: Material) -> void:
    var mesh := CapsuleMesh.new()
    mesh.radius = radius
    mesh.height = height
    mesh.radial_segments = 10
    mesh.rings = 4
    mesh.material = material
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    instance.position = position
    parent.add_child(instance)

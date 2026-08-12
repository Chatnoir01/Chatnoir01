extends Node

## Higher-detail playtest visuals for the isolated Laeken scene.
## Gameplay, collision and controllers are unchanged. These meshes are still
## generic/unbranded placeholders, but their proportions and part separation are
## intentionally closer to a modern third-person game than the original capsule
## and box prototypes.

var _player: CharacterBody3D
var _left_leg: Node3D
var _right_leg: Node3D
var _left_arm: Node3D
var _right_arm: Node3D
var _walk_clock: float = 0.0
var visuals_ready: bool = false
var player_mesh_parts: int = 0
var vehicle_mesh_parts: int = 0

var _skin: StandardMaterial3D
var _hair: StandardMaterial3D
var _jacket: StandardMaterial3D
var _jacket_dark: StandardMaterial3D
var _shirt: StandardMaterial3D
var _trousers: StandardMaterial3D
var _shoe: StandardMaterial3D
var _car_paint: StandardMaterial3D
var _car_dark: StandardMaterial3D
var _car_glass: StandardMaterial3D
var _car_light: StandardMaterial3D
var _car_tail: StandardMaterial3D
var _car_metal: StandardMaterial3D
var _plate: StandardMaterial3D


func _ready() -> void:
    call_deferred("_build_visuals")


func _process(delta: float) -> void:
    if _player == null or _left_leg == null:
        return
    var horizontal_speed := Vector2(_player.velocity.x, _player.velocity.z).length()
    if horizontal_speed > 0.35:
        _walk_clock += delta * clampf(horizontal_speed * 1.45, 5.0, 14.0)
        var swing := sin(_walk_clock) * 0.43
        _left_leg.rotation.x = swing
        _right_leg.rotation.x = -swing
        _left_arm.rotation.x = -swing * 0.70
        _right_arm.rotation.x = swing * 0.70
        # A subtle counter-rotation keeps the procedural figure from reading as
        # four rigid sticks pivoting around one point.
        _left_leg.rotation.z = sin(_walk_clock * 0.5) * 0.025
        _right_leg.rotation.z = -_left_leg.rotation.z
    else:
        _left_leg.rotation.x = lerpf(_left_leg.rotation.x, 0.0, delta * 8.0)
        _right_leg.rotation.x = lerpf(_right_leg.rotation.x, 0.0, delta * 8.0)
        _left_arm.rotation.x = lerpf(_left_arm.rotation.x, 0.0, delta * 8.0)
        _right_arm.rotation.x = lerpf(_right_arm.rotation.x, 0.0, delta * 8.0)
        _left_leg.rotation.z = lerpf(_left_leg.rotation.z, 0.0, delta * 8.0)
        _right_leg.rotation.z = lerpf(_right_leg.rotation.z, 0.0, delta * 8.0)


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
    visuals_ready = player_mesh_parts >= 18 and vehicle_mesh_parts >= 28
    print("LAEKEN_PLAYTEST_VISUALS_READY: ready=%s player_parts=%d vehicle_parts=%d" % [visuals_ready, player_mesh_parts, vehicle_mesh_parts])


func _make_materials() -> void:
    _skin = _material(Color(0.53, 0.35, 0.24, 1.0), 0.76)
    _hair = _material(Color(0.018, 0.020, 0.023, 1.0), 0.78)
    _jacket = _material(Color(0.065, 0.105, 0.155, 1.0), 0.69)
    _jacket_dark = _material(Color(0.035, 0.052, 0.074, 1.0), 0.74)
    _shirt = _material(Color(0.50, 0.51, 0.49, 1.0), 0.83)
    _trousers = _material(Color(0.055, 0.058, 0.065, 1.0), 0.84)
    _shoe = _material(Color(0.018, 0.019, 0.021, 1.0), 0.72)
    _car_paint = _material(Color(0.055, 0.175, 0.315, 1.0), 0.25, 0.46)
    _car_dark = _material(Color(0.018, 0.021, 0.025, 1.0), 0.48, 0.10)
    _car_glass = _material(Color(0.035, 0.070, 0.095, 0.78), 0.11, 0.12)
    _car_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    _car_light = _material(Color(0.92, 0.88, 0.69, 1.0), 0.16, 0.02)
    _car_tail = _material(Color(0.61, 0.028, 0.020, 1.0), 0.24, 0.02)
    _car_metal = _material(Color(0.42, 0.45, 0.48, 1.0), 0.25, 0.78)
    _plate = _material(Color(0.88, 0.86, 0.82, 1.0), 0.62)


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

    # Pelvis + tapered torso make the body read as a person even at mid-distance.
    _add_capsule(visual, "Pelvis", 0.235, 0.37, Vector3(0.0, -0.04, 0.0), _trousers, 12, 5, true)
    _add_frustum(visual, "Torso", 0.30, 0.235, 0.58, Vector3(0.0, 0.36, 0.0), _jacket, true)
    _add_box(visual, "JacketHem", Vector3(0.50, 0.09, 0.25), Vector3(0.0, 0.08, 0.0), _jacket_dark, Vector3.ZERO, true)
    _add_box(visual, "ShirtOpening", Vector3(0.105, 0.30, 0.018), Vector3(0.0, 0.43, -0.248), _shirt, Vector3.ZERO, true)
    _add_capsule(visual, "Neck", 0.075, 0.18, Vector3(0.0, 0.72, 0.0), _skin, 10, 4, true)
    _add_scaled_sphere(visual, "Head", 0.20, Vector3(0.0, 0.91, -0.010), Vector3(0.88, 1.10, 0.91), _skin, true)
    _add_scaled_sphere(visual, "HairCap", 0.202, Vector3(0.0, 0.995, 0.006), Vector3(0.91, 0.58, 0.93), _hair, true)
    _add_box(visual, "HairBack", Vector3(0.28, 0.15, 0.055), Vector3(0.0, 0.94, 0.175), _hair, Vector3.ZERO, true)

    _left_leg = _limb_root(visual, "LeftLeg", Vector3(-0.135, -0.17, 0.0))
    _right_leg = _limb_root(visual, "RightLeg", Vector3(0.135, -0.17, 0.0))
    for leg in [_left_leg, _right_leg]:
        _add_capsule(leg, "Thigh", 0.095, 0.42, Vector3(0.0, -0.18, 0.0), _trousers, 10, 4, true)
        _add_scaled_sphere(leg, "Knee", 0.10, Vector3(0.0, -0.405, -0.008), Vector3(0.92, 0.76, 0.92), _trousers, true)
        _add_capsule(leg, "Calf", 0.078, 0.39, Vector3(0.0, -0.58, 0.018), _trousers, 10, 4, true)
        _add_box(leg, "Shoe", Vector3(0.18, 0.11, 0.33), Vector3(0.0, -0.80, -0.075), _shoe, Vector3(deg_to_rad(-3.0), 0.0, 0.0), true)

    _left_arm = _limb_root(visual, "LeftArm", Vector3(-0.315, 0.57, 0.0))
    _right_arm = _limb_root(visual, "RightArm", Vector3(0.315, 0.57, 0.0))
    for arm in [_left_arm, _right_arm]:
        _add_capsule(arm, "UpperArm", 0.075, 0.31, Vector3(0.0, -0.13, 0.0), _jacket, 10, 4, true)
        _add_scaled_sphere(arm, "Elbow", 0.075, Vector3(0.0, -0.31, 0.0), Vector3(0.92, 0.82, 0.92), _jacket_dark, true)
        _add_capsule(arm, "Forearm", 0.063, 0.28, Vector3(0.0, -0.43, -0.008), _jacket, 10, 4, true)
        _add_scaled_sphere(arm, "Hand", 0.075, Vector3(0.0, -0.60, -0.015), Vector3(0.82, 1.06, 0.72), _skin, true)


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

    # Generic compact European hatchback: unbranded and deliberately not copied
    # from a real vehicle, but with enough layers to avoid the box-car silhouette.
    _add_box(visual, "LowerBody", Vector3(1.84, 0.45, 3.94), Vector3(0.0, -0.02, 0.02), _car_paint, Vector3.ZERO, false)
    _add_box(visual, "LowerSill", Vector3(1.78, 0.18, 3.55), Vector3(0.0, -0.24, 0.06), _car_dark, Vector3.ZERO, false)
    _add_box(visual, "Hood", Vector3(1.72, 0.22, 1.13), Vector3(0.0, 0.27, -1.37), _car_paint, Vector3(deg_to_rad(-4.5), 0.0, 0.0), false)
    _add_box(visual, "RearDeck", Vector3(1.72, 0.24, 0.57), Vector3(0.0, 0.28, 1.59), _car_paint, Vector3(deg_to_rad(3.5), 0.0, 0.0), false)
    _add_box(visual, "Roof", Vector3(1.44, 0.10, 1.45), Vector3(0.0, 0.98, 0.18), _car_paint, Vector3.ZERO, false)

    # Front/rear glazing and separate side windows/pillars.
    _add_box(visual, "Windshield", Vector3(1.43, 0.62, 0.045), Vector3(0.0, 0.68, -0.73), _car_glass, Vector3(deg_to_rad(-25.0), 0.0, 0.0), false)
    _add_box(visual, "RearGlass", Vector3(1.41, 0.58, 0.045), Vector3(0.0, 0.69, 1.06), _car_glass, Vector3(deg_to_rad(22.0), 0.0, 0.0), false)
    for side_x in [-0.755, 0.755]:
        var side_sign := -1.0 if side_x < 0.0 else 1.0
        _add_box(visual, "FrontSideGlass", Vector3(0.035, 0.48, 0.67), Vector3(side_x, 0.70, -0.30), _car_glass, Vector3.ZERO, false)
        _add_box(visual, "RearSideGlass", Vector3(0.035, 0.46, 0.61), Vector3(side_x, 0.69, 0.47), _car_glass, Vector3.ZERO, false)
        _add_box(visual, "B_Pillar", Vector3(0.055, 0.54, 0.10), Vector3(side_x + 0.006 * side_sign, 0.70, 0.08), _car_dark, Vector3.ZERO, false)
        _add_box(visual, "MirrorStem", Vector3(0.09, 0.09, 0.16), Vector3(side_x + 0.075 * side_sign, 0.57, -0.70), _car_dark, Vector3.ZERO, false)
        _add_scaled_sphere(visual, "Mirror", 0.13, Vector3(side_x + 0.13 * side_sign, 0.59, -0.76), Vector3(0.55, 0.46, 0.82), _car_paint, false)
        _add_box(visual, "FrontDoorHandle", Vector3(0.032, 0.045, 0.20), Vector3(side_x + 0.025 * side_sign, 0.34, -0.14), _car_metal, Vector3.ZERO, false)
        _add_box(visual, "RearDoorHandle", Vector3(0.032, 0.045, 0.20), Vector3(side_x + 0.025 * side_sign, 0.34, 0.62), _car_metal, Vector3.ZERO, false)

    for z_value in [-1.28, 1.28]:
        for x_value in [-0.91, 0.91]:
            _add_wheel(visual, Vector3(x_value, -0.30, z_value))

    for x_value in [-0.57, 0.57]:
        _add_box(visual, "HeadLamp", Vector3(0.36, 0.17, 0.055), Vector3(x_value, 0.13, -1.985), _car_light, Vector3.ZERO, false)
        _add_box(visual, "TailLamp", Vector3(0.34, 0.18, 0.055), Vector3(x_value, 0.15, 2.005), _car_tail, Vector3.ZERO, false)

    _add_box(visual, "FrontBumper", Vector3(1.68, 0.13, 0.12), Vector3(0.0, -0.13, -2.00), _car_dark, Vector3.ZERO, false)
    _add_box(visual, "RearBumper", Vector3(1.68, 0.13, 0.12), Vector3(0.0, -0.13, 2.00), _car_dark, Vector3.ZERO, false)
    _add_box(visual, "FrontGrille", Vector3(0.92, 0.20, 0.045), Vector3(0.0, 0.00, -2.066), _car_dark, Vector3.ZERO, false)
    _add_box(visual, "FrontPlate", Vector3(0.50, 0.12, 0.025), Vector3(0.0, -0.02, -2.102), _plate, Vector3.ZERO, false)
    _add_box(visual, "RearPlate", Vector3(0.50, 0.12, 0.025), Vector3(0.0, 0.02, 2.073), _plate, Vector3.ZERO, false)
    _add_box(visual, "RoofAntenna", Vector3(0.035, 0.20, 0.035), Vector3(0.0, 1.10, 0.70), _car_dark, Vector3(deg_to_rad(-18.0), 0.0, 0.0), false)


func _add_wheel(parent: Node3D, position: Vector3) -> void:
    var tire := CylinderMesh.new()
    tire.top_radius = 0.335
    tire.bottom_radius = 0.335
    tire.height = 0.235
    tire.radial_segments = 20
    tire.material = _car_dark
    var tire_instance := MeshInstance3D.new()
    tire_instance.name = "Tire"
    tire_instance.mesh = tire
    tire_instance.position = position
    tire_instance.rotation.z = PI * 0.5
    parent.add_child(tire_instance)
    vehicle_mesh_parts += 1

    var rim := CylinderMesh.new()
    rim.top_radius = 0.205
    rim.bottom_radius = 0.205
    rim.height = 0.247
    rim.radial_segments = 16
    rim.material = _car_metal
    var rim_instance := MeshInstance3D.new()
    rim_instance.name = "WheelRim"
    rim_instance.mesh = rim
    rim_instance.position = position
    rim_instance.rotation.z = PI * 0.5
    parent.add_child(rim_instance)
    vehicle_mesh_parts += 1

    var hub := CylinderMesh.new()
    hub.top_radius = 0.075
    hub.bottom_radius = 0.075
    hub.height = 0.255
    hub.radial_segments = 12
    hub.material = _car_dark
    var hub_instance := MeshInstance3D.new()
    hub_instance.name = "WheelHub"
    hub_instance.mesh = hub
    hub_instance.position = position
    hub_instance.rotation.z = PI * 0.5
    parent.add_child(hub_instance)
    vehicle_mesh_parts += 1


func _add_box(parent: Node3D, node_name: String, size: Vector3, position: Vector3, material: Material, rotation: Vector3 = Vector3.ZERO, is_player_part: bool = false) -> void:
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh.material = material
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    instance.position = position
    instance.rotation = rotation
    parent.add_child(instance)
    if is_player_part:
        player_mesh_parts += 1
    else:
        vehicle_mesh_parts += 1


func _add_scaled_sphere(parent: Node3D, node_name: String, radius: float, position: Vector3, scale: Vector3, material: Material, is_player_part: bool) -> void:
    var mesh := SphereMesh.new()
    mesh.radius = radius
    mesh.height = radius * 2.0
    mesh.radial_segments = 16
    mesh.rings = 9
    mesh.material = material
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    instance.position = position
    instance.scale = scale
    parent.add_child(instance)
    if is_player_part:
        player_mesh_parts += 1
    else:
        vehicle_mesh_parts += 1


func _add_capsule(parent: Node3D, node_name: String, radius: float, height: float, position: Vector3, material: Material, radial_segments: int = 10, rings: int = 4, is_player_part: bool = false) -> void:
    var mesh := CapsuleMesh.new()
    mesh.radius = radius
    mesh.height = height
    mesh.radial_segments = radial_segments
    mesh.rings = rings
    mesh.material = material
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    instance.position = position
    parent.add_child(instance)
    if is_player_part:
        player_mesh_parts += 1
    else:
        vehicle_mesh_parts += 1


func _add_frustum(parent: Node3D, node_name: String, top_radius: float, bottom_radius: float, height: float, position: Vector3, material: Material, is_player_part: bool = false) -> void:
    var mesh := CylinderMesh.new()
    mesh.top_radius = top_radius
    mesh.bottom_radius = bottom_radius
    mesh.height = height
    mesh.radial_segments = 14
    mesh.rings = 1
    mesh.material = material
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    instance.position = position
    parent.add_child(instance)
    if is_player_part:
        player_mesh_parts += 1
    else:
        vehicle_mesh_parts += 1

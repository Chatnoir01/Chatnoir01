extends "res://game/scripts/traffic_manager_core_v4.gd"

@export_range(0.0, 1.0, 0.01) var scooter_share: float = 0.18
@export_range(0.0, 1.0, 0.01) var motorcycle_share: float = 0.10

const MIXED_TRAFFIC_VEHICLE_SCRIPT := preload("res://game/scripts/traffic_vehicle.gd")

const CAR_SIZE := Vector3(1.82, 1.16, 4.15)
const SCOOTER_SIZE := Vector3(0.72, 1.22, 2.00)
const MOTORCYCLE_SIZE := Vector3(0.78, 1.18, 2.28)

const MIXED_COLORS: Array[Color] = [
    Color(0.18, 0.20, 0.22, 1.0),
    Color(0.36, 0.39, 0.42, 1.0),
    Color(0.12, 0.24, 0.38, 1.0),
    Color(0.43, 0.12, 0.10, 1.0),
    Color(0.73, 0.73, 0.69, 1.0),
    Color(0.12, 0.31, 0.22, 1.0),
]


func _create_vehicle_node() -> CharacterBody3D:
    var archetype := _choose_archetype()
    var vehicle := CharacterBody3D.new()
    vehicle.name = "%s_%03d" % [_archetype_node_prefix(archetype), _spawn_serial]
    vehicle.set_script(MIXED_TRAFFIC_VEHICLE_SCRIPT)
    vehicle.collision_layer = 1
    vehicle.collision_mask = 1
    vehicle.add_to_group("traffic_vehicle")
    vehicle.add_to_group("traffic_%s" % archetype)

    var body_size := _body_size_for(archetype)
    var collision := CollisionShape3D.new()
    collision.name = "CollisionShape3D"
    var box_shape := BoxShape3D.new()
    box_shape.size = body_size
    collision.shape = box_shape
    vehicle.add_child(collision)

    match archetype:
        "scooter":
            _add_scooter_visual(vehicle)
        "motorcycle":
            _add_motorcycle_visual(vehicle)
        _:
            _add_car_visual(vehicle)

    var obstacle_ray := RayCast3D.new()
    obstacle_ray.name = "ObstacleRay"
    obstacle_ray.position = Vector3(0.0, 0.15, -body_size.z * 0.42)
    obstacle_ray.target_position = Vector3(0.0, 0.0, -9.0)
    obstacle_ray.collision_mask = 1
    obstacle_ray.exclude_parent = true
    obstacle_ray.enabled = true
    vehicle.add_child(obstacle_ray)

    if vehicle.has_method("configure_archetype"):
        vehicle.call("configure_archetype", archetype)

    _spawn_serial += 1
    return vehicle


func _choose_archetype() -> String:
    var scooter := clampf(scooter_share, 0.0, 1.0)
    var motorcycle := clampf(motorcycle_share, 0.0, 1.0 - scooter)
    var roll := _rng.randf()
    if roll < motorcycle:
        return "motorcycle"
    if roll < motorcycle + scooter:
        return "scooter"
    return "car"


func _body_size_for(archetype: String) -> Vector3:
    match archetype:
        "scooter":
            return SCOOTER_SIZE
        "motorcycle":
            return MOTORCYCLE_SIZE
        _:
            return CAR_SIZE


func _archetype_node_prefix(archetype: String) -> String:
    match archetype:
        "scooter":
            return "TrafficScooter"
        "motorcycle":
            return "TrafficMotorcycle"
        _:
            return "TrafficCar"


func _material(color: Color, roughness: float = 0.5, metallic: float = 0.1) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = metallic
    return material


func _box_mesh(size: Vector3, color: Color, position: Vector3) -> MeshInstance3D:
    var mesh_instance := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh_instance.mesh = mesh
    mesh_instance.position = position
    mesh_instance.material_override = _material(color)
    return mesh_instance


func _wheel_mesh(radius: float, width: float, position: Vector3) -> MeshInstance3D:
    var wheel := MeshInstance3D.new()
    var cylinder := CylinderMesh.new()
    cylinder.top_radius = radius
    cylinder.bottom_radius = radius
    cylinder.height = width
    wheel.mesh = cylinder
    wheel.rotation.z = PI * 0.5
    wheel.position = position
    wheel.material_override = _material(Color(0.035, 0.035, 0.04, 1.0), 0.9, 0.0)
    return wheel


func _add_car_visual(vehicle: CharacterBody3D) -> void:
    var color := MIXED_COLORS[_spawn_serial % MIXED_COLORS.size()]
    var body := _box_mesh(Vector3(1.82, 0.72, 4.15), color, Vector3(0.0, -0.12, 0.0))
    body.name = "Body"
    vehicle.add_child(body)

    var cabin := _box_mesh(Vector3(1.52, 0.66, 1.95), color.lightened(0.08), Vector3(0.0, 0.48, -0.14))
    cabin.name = "Cabin"
    vehicle.add_child(cabin)


func _add_scooter_visual(vehicle: CharacterBody3D) -> void:
    var color := MIXED_COLORS[_spawn_serial % MIXED_COLORS.size()]
    var lower := _box_mesh(Vector3(0.58, 0.42, 1.30), color, Vector3(0.0, 0.18, 0.10))
    lower.name = "ScooterBody"
    vehicle.add_child(lower)

    var fairing := _box_mesh(Vector3(0.52, 0.72, 0.45), color.lightened(0.05), Vector3(0.0, 0.48, -0.58))
    fairing.name = "FrontFairing"
    vehicle.add_child(fairing)

    var seat := _box_mesh(Vector3(0.46, 0.14, 0.68), Color(0.07, 0.07, 0.08, 1.0), Vector3(0.0, 0.70, 0.35))
    seat.name = "Seat"
    vehicle.add_child(seat)

    vehicle.add_child(_wheel_mesh(0.27, 0.12, Vector3(0.0, -0.10, -0.72)))
    vehicle.add_child(_wheel_mesh(0.27, 0.12, Vector3(0.0, -0.10, 0.72)))

    var rider := _box_mesh(Vector3(0.38, 0.72, 0.30), Color(0.24, 0.28, 0.34, 1.0), Vector3(0.0, 1.05, 0.20))
    rider.name = "RiderBody"
    vehicle.add_child(rider)


func _add_motorcycle_visual(vehicle: CharacterBody3D) -> void:
    var color := MIXED_COLORS[_spawn_serial % MIXED_COLORS.size()]
    var frame := _box_mesh(Vector3(0.48, 0.42, 1.35), color, Vector3(0.0, 0.20, 0.05))
    frame.name = "MotorcycleFrame"
    vehicle.add_child(frame)

    var tank := _box_mesh(Vector3(0.56, 0.40, 0.62), color.lightened(0.06), Vector3(0.0, 0.55, -0.28))
    tank.name = "FuelTank"
    vehicle.add_child(tank)

    var seat := _box_mesh(Vector3(0.42, 0.14, 0.72), Color(0.06, 0.06, 0.07, 1.0), Vector3(0.0, 0.62, 0.38))
    seat.name = "Seat"
    vehicle.add_child(seat)

    vehicle.add_child(_wheel_mesh(0.34, 0.14, Vector3(0.0, -0.08, -0.86)))
    vehicle.add_child(_wheel_mesh(0.34, 0.14, Vector3(0.0, -0.08, 0.86)))

    var rider := _box_mesh(Vector3(0.40, 0.78, 0.32), Color(0.17, 0.19, 0.22, 1.0), Vector3(0.0, 1.04, 0.12))
    rider.name = "RiderBody"
    vehicle.add_child(rider)


func get_active_archetype_counts() -> Dictionary:
    var counts := {"car": 0, "scooter": 0, "motorcycle": 0}
    if _traffic_root == null:
        return counts
    for child: Node in _traffic_root.get_children():
        if child.is_queued_for_deletion() or not child.has_method("get_traffic_archetype"):
            continue
        var archetype := str(child.call("get_traffic_archetype"))
        counts[archetype] = int(counts.get(archetype, 0)) + 1
    return counts

extends Node3D

# LABO-only life layer for Anneessens. It deliberately adds visible activity without
# claiming authoritative lane/sidewalk placement. Geometry remains OSM/UrbIS-owned.
const CIVILIAN_VEHICLE_VISUAL := preload("res://game/scripts/civilian_vehicle_visual.gd")
const ANNEESSENS := Vector3(-272.04, 0.0, -217.07)
const BOURSE := Vector3(83.44, 0.0, -663.42)
const CORRIDOR_AXIS := Vector3(BOURSE.x - ANNEESSENS.x, 0.0, BOURSE.z - ANNEESSENS.z).normalized()
const SIDE_AXIS := Vector3(-CORRIDOR_AXIS.z, 0.0, CORRIDOR_AXIS.x)

@export var civilian_count: int = 10
@export var parked_vehicle_count: int = 6
@export var moving_vehicle_count: int = 4
@export var activation_radius_m: float = 150.0

var _player: Node3D
var _civilians: Array[Node3D] = []
var _civilian_progress: Array[float] = []
var _civilian_speed: Array[float] = []
var _civilian_side: Array[float] = []
var _moving: Array[Node3D] = []
var _moving_progress: Array[float] = []
var _moving_speed: Array[float] = []
var _moving_lane: Array[float] = []
var _parked: Array[Node3D] = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
    _rng.seed = 20260816
    _player = get_parent().get_node_or_null("Player") as Node3D
    _build_civilians()
    _build_parked_vehicles()
    _build_moving_vehicles()
    _sync_activation()
    print("ANNEESSENS_LAB_LIFE_READY: civilians=%d parked=%d moving=%d" % [_civilians.size(), _parked.size(), _moving.size()])

func _process(delta: float) -> void:
    _sync_activation()
    if not visible:
        return
    _animate_civilians(delta)
    _animate_vehicles(delta)

func get_counts() -> Dictionary:
    return {
        "civilians": _civilians.size(),
        "parked_vehicles": _parked.size(),
        "moving_vehicles": _moving.size(),
    }

func has_minimum_playable_life() -> bool:
    return _civilians.size() > 0 and _moving.size() > 0

func _sync_activation() -> void:
    if not is_instance_valid(_player):
        _player = get_parent().get_node_or_null("Player") as Node3D
    var active := is_instance_valid(_player) and Vector2(_player.global_position.x - ANNEESSENS.x, _player.global_position.z - ANNEESSENS.z).length() <= activation_radius_m
    visible = active
    set_process(active)

func _build_civilians() -> void:
    var clothing := [Color(0.12,0.15,0.20), Color(0.28,0.12,0.10), Color(0.14,0.23,0.15), Color(0.26,0.24,0.20), Color(0.20,0.11,0.24)]
    var skin := [Color(0.84,0.65,0.50), Color(0.65,0.45,0.31), Color(0.43,0.28,0.20), Color(0.29,0.19,0.14)]
    for i in range(civilian_count):
        var person := Node3D.new()
        person.name = "AnneessensCivilian_%02d" % i
        person.add_to_group("ambient_pedestrian")
        add_child(person)
        var jacket := _material(clothing[i % clothing.size()], 0.88)
        var pants := _material(clothing[i % clothing.size()].darkened(0.35), 0.92)
        var face := _material(skin[(i * 3) % skin.size()], 0.82)
        _box(person, Vector3(0.46,0.62,0.27), Vector3(0,1.14,0), jacket)
        _box(person, Vector3(0.16,0.66,0.19), Vector3(-0.12,0.47,0), pants)
        _box(person, Vector3(0.16,0.66,0.19), Vector3(0.12,0.47,0), pants)
        var head := MeshInstance3D.new()
        var sphere := SphereMesh.new()
        sphere.radius = 0.21
        sphere.height = 0.42
        head.mesh = sphere
        head.material_override = face
        head.position = Vector3(0,1.65,0)
        person.add_child(head)
        _civilians.append(person)
        _civilian_progress.append(-36.0 + float(i) * 8.0)
        _civilian_speed.append((0.9 + 0.08 * float(i % 5)) * (-1.0 if i % 3 == 0 else 1.0))
        _civilian_side.append(-5.8 if i % 2 == 0 else 5.8)
        _place_civilian(i)

func _build_parked_vehicles() -> void:
    var colors := [Color(0.08,0.10,0.13), Color(0.32,0.33,0.32), Color(0.45,0.44,0.40), Color(0.24,0.06,0.05), Color(0.10,0.18,0.26), Color(0.64,0.64,0.61)]
    for i in range(parked_vehicle_count):
        var car := _car("AnneessensParked_%02d" % i, colors[i % colors.size()])
        _parked.append(car)
        add_child(car)
        var direction := -1.0 if i % 2 == 0 else 1.0
        car.position = ANNEESSENS + CORRIDOR_AXIS * (-30.0 + float(i) * 12.0) + SIDE_AXIS * (4.6 * direction) + Vector3(0,0.46,0)
        var heading := CORRIDOR_AXIS * direction
        car.rotation.y = atan2(-heading.x, -heading.z)

func _build_moving_vehicles() -> void:
    var colors := [Color(0.07,0.13,0.20), Color(0.18,0.18,0.19), Color(0.50,0.49,0.46), Color(0.10,0.22,0.14)]
    for i in range(moving_vehicle_count):
        var car := _car("AnneessensTraffic_%02d" % i, colors[i % colors.size()])
        car.add_to_group("ambient_traffic")
        _moving.append(car)
        add_child(car)
        var direction := -1.0 if i % 2 == 0 else 1.0
        _moving_progress.append(-34.0 + float(i) * 22.0)
        _moving_speed.append((5.0 + float(i) * 0.7) * direction)
        _moving_lane.append(2.2 * direction)
        _place_vehicle(i)

func _animate_civilians(delta: float) -> void:
    for i in range(_civilians.size()):
        _civilian_progress[i] += _civilian_speed[i] * delta
        if _civilian_progress[i] > 42.0:
            _civilian_progress[i] = -42.0
        elif _civilian_progress[i] < -42.0:
            _civilian_progress[i] = 42.0
        _place_civilian(i)

func _animate_vehicles(delta: float) -> void:
    for i in range(_moving.size()):
        _moving_progress[i] += _moving_speed[i] * delta
        if _moving_progress[i] > 48.0:
            _moving_progress[i] = -48.0
        elif _moving_progress[i] < -48.0:
            _moving_progress[i] = 48.0
        _place_vehicle(i)

func _place_civilian(i: int) -> void:
    var person := _civilians[i]
    person.position = ANNEESSENS + CORRIDOR_AXIS * _civilian_progress[i] + SIDE_AXIS * _civilian_side[i] + Vector3(0,0.16,0)
    var heading := CORRIDOR_AXIS if _civilian_speed[i] >= 0.0 else -CORRIDOR_AXIS
    person.rotation.y = atan2(-heading.x, -heading.z)

func _place_vehicle(i: int) -> void:
    var car := _moving[i]
    car.position = ANNEESSENS + CORRIDOR_AXIS * _moving_progress[i] + SIDE_AXIS * _moving_lane[i] + Vector3(0,0.46,0)
    var heading := CORRIDOR_AXIS * signf(_moving_speed[i])
    car.rotation.y = atan2(-heading.x, -heading.z)

func _car(node_name: String, color: Color) -> Node3D:
    var car := Node3D.new()
    car.name = node_name
    var visual := Node3D.new()
    visual.name = "ProductionVisual"
    visual.set_script(CIVILIAN_VEHICLE_VISUAL)
    visual.set("paint_color", color)
    car.add_child(visual)
    return car

func _material(color: Color, roughness: float) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    return material

func _box(parent: Node3D, size: Vector3, position: Vector3, material: Material) -> void:
    var mesh_instance := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh_instance.mesh = mesh
    mesh_instance.material_override = material
    mesh_instance.position = position
    parent.add_child(mesh_instance)

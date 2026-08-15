extends Node3D

# Ambient dressing only. The authoritative road/building geometry remains
# UrbIS/OSM-driven; these objects add street-level life without redefining it.
const MIDI: Vector3 = Vector3(-668.5, 0.0, 627.84)
const FONSNY_AXIS: Vector3 = Vector3(-0.627, 0.0, 0.779)
const STATION_SIDE: Vector3 = Vector3(-0.779, 0.0, -0.627)
const ROAD_SIDE: Vector3 = Vector3(0.779, 0.0, 0.627)
const CIVILIAN_VEHICLE_VISUAL := preload("res://game/scripts/civilian_vehicle_visual.gd")

@export var pedestrian_count: int = 20
@export var parked_vehicle_count: int = 14
@export var moving_vehicle_count: int = 6

var _pedestrians: Array[Node3D] = []
var _pedestrian_progress: Array[float] = []
var _pedestrian_speed: Array[float] = []
var _pedestrian_side: Array[float] = []
var _moving_cars: Array[Node3D] = []
var _moving_progress: Array[float] = []
var _moving_speed: Array[float] = []
var _moving_lane: Array[float] = []
var _prop_count: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _metal_dark: StandardMaterial3D
var _metal_galvanized: StandardMaterial3D
var _bin_material: StandardMaterial3D
var _wood: StandardMaterial3D
var _rubber: StandardMaterial3D
var _glass: StandardMaterial3D
var _white_light: StandardMaterial3D
var _red_light: StandardMaterial3D
var _amber_light: StandardMaterial3D
var _green_light: StandardMaterial3D
var _shop_glow: StandardMaterial3D


func _ready() -> void:
    _rng.seed = 20260812
    _make_materials()
    _build_pedestrians()
    _build_parked_cars()
    _build_moving_traffic()
    _build_street_furniture()
    _build_shopfront_light()
    print(
        "Grand Bruxelles realism layer: %d pedestrians, %d parked cars, %d moving cars, %d props" %
        [_pedestrians.size(), parked_vehicle_count, _moving_cars.size(), _prop_count]
    )


func _process(delta: float) -> void:
    _animate_pedestrians(delta)
    _animate_traffic(delta)


func get_pedestrian_count() -> int:
    return _pedestrians.size()


func get_parked_vehicle_count() -> int:
    return parked_vehicle_count


func get_moving_vehicle_count() -> int:
    return _moving_cars.size()


func get_prop_count() -> int:
    return _prop_count


func _make_materials() -> void:
    _metal_dark = _material(Color(0.055, 0.06, 0.065, 1.0), 0.55, 0.42)
    _metal_galvanized = _material(Color(0.34, 0.37, 0.39, 1.0), 0.58, 0.55)
    _bin_material = _material(Color(0.105, 0.13, 0.12, 1.0), 0.86, 0.08)
    _wood = _material(Color(0.28, 0.17, 0.095, 1.0), 0.92)
    _rubber = _material(Color(0.018, 0.02, 0.022, 1.0), 0.88)
    _glass = _material(Color(0.035, 0.07, 0.09, 0.72), 0.16, 0.18)
    _glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    _white_light = _emissive(Color(0.92, 0.89, 0.75, 1.0), 1.4)
    _red_light = _emissive(Color(0.78, 0.025, 0.02, 1.0), 1.2)
    _amber_light = _emissive(Color(0.95, 0.38, 0.025, 1.0), 1.15)
    _green_light = _emissive(Color(0.04, 0.72, 0.22, 1.0), 1.1)
    _shop_glow = _emissive(Color(0.86, 0.63, 0.34, 1.0), 0.75)


func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = metallic
    return material


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
    var material: StandardMaterial3D = _material(color, 0.42)
    material.emission_enabled = true
    material.emission = color
    material.emission_energy_multiplier = energy
    return material


func _build_pedestrians() -> void:
    var clothing: Array[Color] = [
        Color(0.08, 0.09, 0.11, 1.0),
        Color(0.13, 0.19, 0.28, 1.0),
        Color(0.34, 0.16, 0.12, 1.0),
        Color(0.18, 0.24, 0.16, 1.0),
        Color(0.39, 0.37, 0.32, 1.0),
        Color(0.23, 0.12, 0.27, 1.0),
    ]
    var skin_tones: Array[Color] = [
        Color(0.86, 0.67, 0.52, 1.0),
        Color(0.68, 0.48, 0.34, 1.0),
        Color(0.47, 0.30, 0.21, 1.0),
        Color(0.31, 0.20, 0.15, 1.0),
        Color(0.74, 0.56, 0.42, 1.0),
    ]

    for index: int in range(pedestrian_count):
        var person: Node3D = Node3D.new()
        person.name = "AmbientPedestrian_%02d" % index
        person.add_to_group("ambient_pedestrian")
        add_child(person)

        var clothing_color: Color = clothing[index % clothing.size()]
        var skin_color: Color = skin_tones[(index * 3) % skin_tones.size()]
        var jacket: StandardMaterial3D = _material(clothing_color, 0.86)
        var pants: StandardMaterial3D = _material(clothing_color.darkened(0.38), 0.90)
        var skin: StandardMaterial3D = _material(skin_color, 0.80)

        _box(person, "Torso", Vector3(0.48, 0.62, 0.28), Vector3(0.0, 1.17, 0.0), jacket)
        _box(person, "LeftLeg", Vector3(0.17, 0.68, 0.20), Vector3(-0.13, 0.48, 0.0), pants)
        _box(person, "RightLeg", Vector3(0.17, 0.68, 0.20), Vector3(0.13, 0.48, 0.0), pants)
        _box(person, "LeftArm", Vector3(0.14, 0.62, 0.16), Vector3(-0.33, 1.14, 0.0), jacket)
        _box(person, "RightArm", Vector3(0.14, 0.62, 0.16), Vector3(0.33, 1.14, 0.0), jacket)
        _sphere(person, "Head", 0.22, Vector3(0.0, 1.67, 0.0), skin)

        if index % 4 == 0:
            var bag: StandardMaterial3D = _material(Color(0.09, 0.065, 0.045, 1.0), 0.9)
            _box(person, "Bag", Vector3(0.30, 0.38, 0.16), Vector3(0.38, 0.88, 0.05), bag)

        var progress: float = _rng.randf_range(-94.0, 94.0)
        var sidewalk_side: float = -1.0 if index % 2 == 0 else 1.0
        var lateral: float = 12.6 if sidewalk_side < 0.0 else 8.8
        var direction_sign: float = -1.0 if index % 3 == 0 else 1.0
        _pedestrians.append(person)
        _pedestrian_progress.append(progress)
        _pedestrian_speed.append(_rng.randf_range(0.85, 1.55) * direction_sign)
        _pedestrian_side.append(lateral * sidewalk_side)
        _place_pedestrian(index)


func _place_pedestrian(index: int) -> void:
    var person: Node3D = _pedestrians[index]
    var progress: float = _pedestrian_progress[index]
    var lateral: float = _pedestrian_side[index]
    person.position = MIDI + FONSNY_AXIS * progress + ROAD_SIDE * lateral + Vector3(0.0, 0.16, 0.0)
    var heading: Vector3 = FONSNY_AXIS if _pedestrian_speed[index] >= 0.0 else -FONSNY_AXIS
    person.rotation.y = atan2(-heading.x, -heading.z)


func _animate_pedestrians(delta: float) -> void:
    for index: int in range(_pedestrians.size()):
        var progress: float = _pedestrian_progress[index] + _pedestrian_speed[index] * delta
        if progress > 98.0:
            progress = -98.0
        elif progress < -98.0:
            progress = 98.0
        _pedestrian_progress[index] = progress
        _place_pedestrian(index)

        var person: Node3D = _pedestrians[index]
        var walk_phase: float = Time.get_ticks_msec() * 0.006 * signf(_pedestrian_speed[index]) + float(index)
        var swing: float = sin(walk_phase) * 0.38
        var left_leg: Node3D = person.get_node_or_null("LeftLeg") as Node3D
        var right_leg: Node3D = person.get_node_or_null("RightLeg") as Node3D
        var left_arm: Node3D = person.get_node_or_null("LeftArm") as Node3D
        var right_arm: Node3D = person.get_node_or_null("RightArm") as Node3D
        if left_leg != null:
            left_leg.rotation.x = swing
        if right_leg != null:
            right_leg.rotation.x = -swing
        if left_arm != null:
            left_arm.rotation.x = -swing
        if right_arm != null:
            right_arm.rotation.x = swing


func _build_parked_cars() -> void:
    var colors: Array[Color] = [
        Color(0.055, 0.065, 0.075, 1.0),
        Color(0.18, 0.20, 0.22, 1.0),
        Color(0.34, 0.35, 0.34, 1.0),
        Color(0.47, 0.46, 0.42, 1.0),
        Color(0.11, 0.18, 0.27, 1.0),
        Color(0.31, 0.075, 0.055, 1.0),
        Color(0.71, 0.71, 0.68, 1.0),
    ]

    for index: int in range(parked_vehicle_count):
        var vehicle: Node3D = _civilian_car("ParkedCar_%02d" % index, colors[index % colors.size()])
        add_child(vehicle)
        var side_sign: float = -1.0 if index % 2 == 0 else 1.0
        var progress: float = -88.0 + float(index) * 13.2
        var lateral: float = 5.4 * side_sign
        vehicle.position = MIDI + FONSNY_AXIS * progress + ROAD_SIDE * lateral + Vector3(0.0, 0.46, 0.0)
        var heading: Vector3 = FONSNY_AXIS * side_sign
        vehicle.rotation.y = atan2(-heading.x, -heading.z)


func _build_moving_traffic() -> void:
    var colors: Array[Color] = [
        Color(0.075, 0.105, 0.145, 1.0),
        Color(0.16, 0.17, 0.18, 1.0),
        Color(0.52, 0.51, 0.48, 1.0),
        Color(0.26, 0.07, 0.055, 1.0),
        Color(0.08, 0.14, 0.105, 1.0),
        Color(0.62, 0.62, 0.59, 1.0),
    ]

    for index: int in range(moving_vehicle_count):
        var vehicle: Node3D = _civilian_car("AmbientTraffic_%02d" % index, colors[index % colors.size()])
        vehicle.add_to_group("ambient_traffic")
        add_child(vehicle)
        var direction_sign: float = -1.0 if index % 2 == 0 else 1.0
        _moving_cars.append(vehicle)
        _moving_progress.append(-92.0 + float(index) * 31.0)
        _moving_speed.append(_rng.randf_range(5.0, 8.5) * direction_sign)
        _moving_lane.append(2.05 * direction_sign)
        _place_moving_car(index)


func _place_moving_car(index: int) -> void:
    var vehicle: Node3D = _moving_cars[index]
    var direction_sign: float = signf(_moving_speed[index])
    vehicle.position = (
        MIDI
        + FONSNY_AXIS * _moving_progress[index]
        + ROAD_SIDE * _moving_lane[index]
        + Vector3(0.0, 0.46, 0.0)
    )
    var heading: Vector3 = FONSNY_AXIS * direction_sign
    vehicle.rotation.y = atan2(-heading.x, -heading.z)


func _animate_traffic(delta: float) -> void:
    for index: int in range(_moving_cars.size()):
        var progress: float = _moving_progress[index] + _moving_speed[index] * delta
        if progress > 112.0:
            progress = -112.0
        elif progress < -112.0:
            progress = 112.0
        _moving_progress[index] = progress
        _place_moving_car(index)


func _civilian_car(name_value: String, color: Color) -> Node3D:
    var car: Node3D = Node3D.new()
    car.name = name_value
    var visual: Node3D = Node3D.new()
    visual.name = "ProductionVisual"
    visual.set_script(CIVILIAN_VEHICLE_VISUAL)
    visual.set("paint_color", color)
    car.add_child(visual)
    return car


func _build_street_furniture() -> void:
    for distance: float in [-82.0, -58.0, -34.0, -10.0, 14.0, 38.0, 62.0, 86.0]:
        var base: Vector3 = MIDI + FONSNY_AXIS * distance + STATION_SIDE * 11.2
        _bollard(base)
        _bollard(base + FONSNY_AXIS * 2.2)
        if int(distance) % 48 == 14:
            _bin(base + STATION_SIDE * 1.3)

    for distance: float in [-72.0, -24.0, 24.0, 72.0]:
        _bench(MIDI + FONSNY_AXIS * distance + STATION_SIDE * 13.8)
        _bike_rack(MIDI + FONSNY_AXIS * (distance + 6.0) + STATION_SIDE * 13.2)

    for distance: float in [-54.0, 2.0, 58.0]:
        _traffic_light(MIDI + FONSNY_AXIS * distance + ROAD_SIDE * 7.0)

    for distance: float in [-45.0, 48.0]:
        _utility_box(MIDI + FONSNY_AXIS * distance + STATION_SIDE * 14.2)


func _bollard(pos: Vector3) -> void:
    _cylinder(self, "StreetBollard", 0.07, 0.88, pos + Vector3(0.0, 0.44, 0.0), _metal_dark)
    _prop_count += 1


func _bin(pos: Vector3) -> void:
    _box(self, "StreetBin", Vector3(0.50, 0.92, 0.48), pos + Vector3(0.0, 0.46, 0.0), _bin_material)
    _box(self, "BinOpening", Vector3(0.32, 0.10, 0.05), pos + Vector3(0.0, 0.65, -0.25), _metal_dark)
    _prop_count += 1


func _bench(pos: Vector3) -> void:
    _box(self, "BenchSeat", Vector3(1.85, 0.12, 0.48), pos + Vector3(0.0, 0.48, 0.0), _wood)
    _box(self, "BenchBack", Vector3(1.85, 0.66, 0.10), pos + Vector3(0.0, 0.83, 0.22), _wood)
    _box(self, "BenchLegL", Vector3(0.10, 0.48, 0.42), pos + Vector3(-0.68, 0.24, 0.0), _metal_dark)
    _box(self, "BenchLegR", Vector3(0.10, 0.48, 0.42), pos + Vector3(0.68, 0.24, 0.0), _metal_dark)
    _prop_count += 1


func _bike_rack(pos: Vector3) -> void:
    for index: int in range(4):
        var rack: MeshInstance3D = _cylinder(self, "BikeRack", 0.035, 1.25, pos + FONSNY_AXIS * float(index) * 0.72 + Vector3(0.0, 0.46, 0.0), _metal_galvanized)
        rack.rotation.x = PI * 0.5
    _prop_count += 4


func _traffic_light(pos: Vector3) -> void:
    _cylinder(self, "TrafficPole", 0.065, 3.55, pos + Vector3(0.0, 1.78, 0.0), _metal_dark)
    _box(self, "TrafficHead", Vector3(0.36, 0.94, 0.30), pos + Vector3(0.0, 3.25, 0.0), _metal_dark)
    _sphere(self, "SignalRed", 0.105, pos + Vector3(0.0, 3.52, -0.17), _red_light)
    _sphere(self, "SignalAmber", 0.105, pos + Vector3(0.0, 3.25, -0.17), _amber_light)
    _sphere(self, "SignalGreen", 0.105, pos + Vector3(0.0, 2.98, -0.17), _green_light)
    _prop_count += 1


func _utility_box(pos: Vector3) -> void:
    _box(self, "UtilityCabinet", Vector3(0.72, 1.25, 0.48), pos + Vector3(0.0, 0.625, 0.0), _metal_galvanized)
    _prop_count += 1


func _build_shopfront_light() -> void:
    for distance: float in [-74.0, -52.0, -30.0, -8.0, 14.0, 36.0, 58.0, 80.0]:
        var panel: MeshInstance3D = _box(
            self,
            "WarmShopWindow",
            Vector3(4.2, 2.05, 0.10),
            MIDI + FONSNY_AXIS * distance + STATION_SIDE * 26.0 + Vector3(0.0, 1.25, 0.0),
            _shop_glow
        )
        panel.rotation.y = atan2(FONSNY_AXIS.x, FONSNY_AXIS.z)
        _prop_count += 1


func _box(parent: Node3D, name_value: String, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
    var mesh: BoxMesh = BoxMesh.new()
    mesh.size = size
    mesh.material = material
    var instance: MeshInstance3D = MeshInstance3D.new()
    instance.name = name_value
    instance.mesh = mesh
    instance.position = pos
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    parent.add_child(instance)
    return instance


func _sphere(parent: Node3D, name_value: String, radius: float, pos: Vector3, material: Material) -> MeshInstance3D:
    var mesh: SphereMesh = SphereMesh.new()
    mesh.radius = radius
    mesh.height = radius * 2.0
    mesh.radial_segments = 12
    mesh.rings = 6
    mesh.material = material
    var instance: MeshInstance3D = MeshInstance3D.new()
    instance.name = name_value
    instance.mesh = mesh
    instance.position = pos
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    parent.add_child(instance)
    return instance


func _cylinder(parent: Node3D, name_value: String, radius: float, height: float, pos: Vector3, material: Material) -> MeshInstance3D:
    var mesh: CylinderMesh = CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = height
    mesh.radial_segments = 12
    mesh.material = material
    var instance: MeshInstance3D = MeshInstance3D.new()
    instance.name = name_value
    instance.mesh = mesh
    instance.position = pos
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    parent.add_child(instance)
    return instance
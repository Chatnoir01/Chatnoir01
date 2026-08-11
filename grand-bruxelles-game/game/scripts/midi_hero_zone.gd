extends Node3D

const MIDI := Vector3(-668.5, 0.0, 627.84)
const FONSNY_AXIS := Vector3(-0.627, 0.0, 0.779)
const STATION_SIDE := Vector3(-0.779, 0.0, -0.627)
const ROAD_SIDE := Vector3(0.779, 0.0, 0.627)

var _stone: StandardMaterial3D
var _dark_stone: StandardMaterial3D
var _glass: StandardMaterial3D
var _metal: StandardMaterial3D
var _white: StandardMaterial3D
var _pole: StandardMaterial3D
var _lamp: StandardMaterial3D
var _tree_trunk: StandardMaterial3D
var _tree_leaf: StandardMaterial3D
var _shelter_glass: StandardMaterial3D
var _blue: StandardMaterial3D


func _ready() -> void:
    _make_materials()
    _build_station_mass()
    _build_station_entrance()
    _build_fonsny_crossing()
    _build_fonsny_street_furniture()
    _build_shelters()
    print("Grand Bruxelles hero zone: Bruxelles-Midi visual landmark active")


func _material(color: Color, roughness: float = 0.8, metallic: float = 0.0) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = metallic
    return material


func _make_materials() -> void:
    _stone = _material(Color(0.34, 0.32, 0.30, 1.0), 0.92)
    _dark_stone = _material(Color(0.17, 0.18, 0.19, 1.0), 0.88)
    _glass = _material(Color(0.055, 0.095, 0.12, 1.0), 0.18, 0.24)
    _metal = _material(Color(0.20, 0.22, 0.235, 1.0), 0.36, 0.66)
    _white = _material(Color(0.88, 0.87, 0.80, 1.0), 0.76)
    _pole = _material(Color(0.095, 0.105, 0.115, 1.0), 0.48, 0.46)
    _lamp = _material(Color(1.0, 0.78, 0.42, 1.0), 0.35)
    _tree_trunk = _material(Color(0.25, 0.17, 0.11, 1.0), 0.95)
    _tree_leaf = _material(Color(0.13, 0.23, 0.13, 1.0), 0.93)
    _shelter_glass = _material(Color(0.12, 0.20, 0.235, 0.72), 0.15, 0.10)
    _shelter_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    _blue = _material(Color(0.06, 0.16, 0.31, 1.0), 0.55)


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


func _add_cylinder(parent: Node3D, name: String, radius: float, height: float, position: Vector3, material: Material) -> MeshInstance3D:
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = height
    mesh.radial_segments = 8
    mesh.material = material
    var instance := MeshInstance3D.new()
    instance.name = name
    instance.mesh = mesh
    instance.position = position
    parent.add_child(instance)
    return instance


func _road_angle() -> float:
    return atan2(FONSNY_AXIS.x, FONSNY_AXIS.z)


func _build_station_mass() -> void:
    var station := Node3D.new()
    station.name = "BruxellesMidiStation"
    station.position = MIDI + STATION_SIDE * 35.0 + FONSNY_AXIS * 7.0
    station.rotation.y = _road_angle()
    add_child(station)

    _add_box(station, "StationLowerStone", Vector3(46.0, 5.2, 154.0), Vector3(0, 2.6, 0), _dark_stone)
    _add_box(station, "StationUpperStone", Vector3(45.0, 3.0, 152.0), Vector3(0, 6.7, 0), _stone)
    _add_box(station, "StationGlassBand", Vector3(45.4, 2.25, 151.0), Vector3(0, 9.2, 0), _glass)
    _add_box(station, "StationRoof", Vector3(50.0, 0.65, 160.0), Vector3(0, 10.65, 0), _metal)

    for local_z: float in [-58.0, -29.0, 0.0, 29.0, 58.0]:
        _add_box(station, "FacadePier", Vector3(0.70, 9.0, 1.05), Vector3(23.1, 5.0, local_z), _stone)

    for local_z: float in [-46.0, -15.0, 16.0, 47.0]:
        _add_box(station, "RoofRhythm", Vector3(49.0, 0.18, 1.2), Vector3(0, 10.98, local_z), _dark_stone)

    var station_label := Label3D.new()
    station_label.name = "StationName"
    station_label.text = "BRUXELLES-MIDI  ·  BRUSSEL-ZUID"
    station_label.font_size = 54
    station_label.outline_size = 8
    station_label.modulate = Color(0.96, 0.96, 0.92, 1.0)
    station_label.position = Vector3(24.0, 7.8, -11.0)
    station_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    station.add_child(station_label)


func _build_station_entrance() -> void:
    var entrance := Node3D.new()
    entrance.name = "MidiEntrance"
    entrance.position = MIDI + STATION_SIDE * 10.0 + FONSNY_AXIS * -6.0
    entrance.rotation.y = _road_angle()
    add_child(entrance)

    _add_box(entrance, "EntranceCanopy", Vector3(16.5, 0.42, 24.0), Vector3(-8.0, 4.35, 0), _metal)
    _add_box(entrance, "EntranceGlass", Vector3(0.28, 3.8, 19.0), Vector3(-14.5, 2.25, 0), _glass)

    for local_z: float in [-8.5, -2.8, 2.8, 8.5]:
        _add_cylinder(entrance, "EntranceColumn", 0.13, 4.15, Vector3(-13.7, 2.08, local_z), _metal)

    _add_box(entrance, "StationTotem", Vector3(0.55, 3.8, 1.45), Vector3(-16.5, 2.15, -10.5), _blue)


func _build_fonsny_crossing() -> void:
    var crossing_center := MIDI + FONSNY_AXIS * -18.0
    var angle := _road_angle()
    for stripe_index: int in range(9):
        var stripe := _add_box(
            self,
            "Crosswalk_%02d" % stripe_index,
            Vector3(11.5, 0.035, 0.46),
            crossing_center + FONSNY_AXIS * (float(stripe_index) - 4.0) * 0.88 + Vector3(0, 0.115, 0),
            _white
        )
        stripe.rotation.y = angle


func _build_fonsny_street_furniture() -> void:
    for distance: float in [-88.0, -66.0, -44.0, -22.0, 0.0, 22.0, 44.0, 66.0, 88.0]:
        _add_lamp(MIDI + FONSNY_AXIS * distance + STATION_SIDE * 8.3)
        if int(distance) % 44 == 0:
            _add_lamp(MIDI + FONSNY_AXIS * distance + ROAD_SIDE * 8.3)

    for distance: float in [-74.0, -37.0, 36.0, 73.0]:
        _add_tree(MIDI + FONSNY_AXIS * distance + ROAD_SIDE * 13.0)

    for distance: float in [-26.0, -22.0, -18.0, 18.0, 22.0, 26.0]:
        _add_bollard(MIDI + FONSNY_AXIS * distance + STATION_SIDE * 7.1)


func _add_lamp(position: Vector3) -> void:
    var lamp_root := Node3D.new()
    lamp_root.position = position
    add_child(lamp_root)
    _add_cylinder(lamp_root, "Pole", 0.075, 5.8, Vector3(0, 2.9, 0), _pole)
    _add_box(lamp_root, "Arm", Vector3(0.85, 0.07, 0.07), Vector3(0.34, 5.55, 0), _pole)
    _add_box(lamp_root, "Lamp", Vector3(0.30, 0.14, 0.22), Vector3(0.72, 5.48, 0), _lamp)


func _add_tree(position: Vector3) -> void:
    var tree := Node3D.new()
    tree.position = position
    add_child(tree)
    _add_cylinder(tree, "Trunk", 0.16, 2.8, Vector3(0, 1.4, 0), _tree_trunk)
    var crown_mesh := SphereMesh.new()
    crown_mesh.radius = 1.65
    crown_mesh.height = 3.2
    crown_mesh.radial_segments = 8
    crown_mesh.rings = 4
    crown_mesh.material = _tree_leaf
    var crown := MeshInstance3D.new()
    crown.mesh = crown_mesh
    crown.position = Vector3(0, 4.0, 0)
    tree.add_child(crown)


func _add_bollard(position: Vector3) -> void:
    var bollard := _add_cylinder(self, "Bollard", 0.09, 0.82, position + Vector3(0, 0.41, 0), _pole)
    bollard.rotation_degrees.z = 0.0


func _build_shelters() -> void:
    _add_shelter(MIDI + FONSNY_AXIS * 34.0 + ROAD_SIDE * 9.5)
    _add_shelter(MIDI + FONSNY_AXIS * -54.0 + STATION_SIDE * 9.5)


func _add_shelter(position: Vector3) -> void:
    var shelter := Node3D.new()
    shelter.position = position
    shelter.rotation.y = _road_angle()
    add_child(shelter)
    _add_box(shelter, "ShelterRoof", Vector3(2.2, 0.16, 4.8), Vector3(0, 2.55, 0), _metal)
    _add_box(shelter, "ShelterBack", Vector3(0.12, 2.2, 4.4), Vector3(-1.0, 1.4, 0), _shelter_glass)
    _add_box(shelter, "ShelterBench", Vector3(0.55, 0.12, 2.6), Vector3(-0.45, 0.72, 0), _stone)
    _add_box(shelter, "StopPanel", Vector3(0.16, 2.3, 0.55), Vector3(1.15, 1.45, -1.65), _blue)

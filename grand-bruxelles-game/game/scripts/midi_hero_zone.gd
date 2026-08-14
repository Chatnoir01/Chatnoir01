extends Node3D

# Bruxelles-Midi / Brussel-Zuid hero zone.
# Coordinates remain aligned with the committed OSM corridor. The station
# composition is a hand-built visual reconstruction pass informed by the
# Brussels architectural heritage inventory while the exact UrbIS 3D import
# pipeline is being prepared.

const MIDI: Vector3 = Vector3(-668.5, 0.0, 627.84)
const FONSNY_AXIS: Vector3 = Vector3(-0.627, 0.0, 0.779)
const STATION_SIDE: Vector3 = Vector3(-0.779, 0.0, -0.627)
const ROAD_SIDE: Vector3 = Vector3(0.779, 0.0, 0.627)
const FAUQUENBERG_BRICK_LENGTH_M := 0.24
const FAUQUENBERG_BRICK_HEIGHT_M := 0.04
const FAUQUENBERG_JOINT_WIDTH_M := 0.02
const FAUQUENBERG_TILE_WIDTH_M := 0.52
const FAUQUENBERG_TILE_HEIGHT_M := 0.12

var _brick_yellow: StandardMaterial3D
var _brick_shadow: StandardMaterial3D
var _blue_stone: StandardMaterial3D
var _concrete: StandardMaterial3D
var _glass: StandardMaterial3D
var _glass_block: StandardMaterial3D
var _metal: StandardMaterial3D
var _white: StandardMaterial3D
var _pole: StandardMaterial3D
var _lamp: StandardMaterial3D
var _tree_trunk: StandardMaterial3D
var _tree_leaf: StandardMaterial3D
var _shelter_glass: StandardMaterial3D
var _sign_blue: StandardMaterial3D
var _railing: StandardMaterial3D
var _paving: StandardMaterial3D


func _ready() -> void:
    _make_materials()
    _build_station_complex()
    _build_station_entrance()
    _build_fonsny_forecourt()
    _build_fonsny_crossing()
    _build_fonsny_street_furniture()
    _build_shelters()
    _build_tram_railings()
    print("Grand Bruxelles hero zone: Bruxelles-Midi Fonsny reconstruction active")


func _material(color: Color, roughness: float = 0.8, metallic: float = 0.0) -> StandardMaterial3D:
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = metallic
    return material


func _fill_image_rect(image: Image, x0: int, y0: int, x1: int, y1: int, color: Color) -> void:
    var min_x: int = clampi(x0, 0, image.get_width())
    var min_y: int = clampi(y0, 0, image.get_height())
    var max_x: int = clampi(x1, 0, image.get_width())
    var max_y: int = clampi(y1, 0, image.get_height())
    for y: int in range(min_y, max_y):
        for x: int in range(min_x, max_x):
            image.set_pixel(x, y, color)


func _fauquenberg_texture(shadow: bool) -> ImageTexture:
    const WIDTH := 256
    const HEIGHT := 128
    var image := Image.create_empty(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
    var mortar := Color(0.54, 0.51, 0.43, 1.0) if not shadow else Color(0.40, 0.37, 0.30, 1.0)
    var brick_a := Color(0.67, 0.58, 0.39, 1.0) if not shadow else Color(0.50, 0.42, 0.28, 1.0)
    var brick_b := Color(0.61, 0.52, 0.35, 1.0) if not shadow else Color(0.45, 0.37, 0.25, 1.0)
    image.fill(mortar)
    var horizontal_joint_px: int = maxi(1, int(round(float(WIDTH) * FAUQUENBERG_JOINT_WIDTH_M / FAUQUENBERG_TILE_WIDTH_M)))
    var vertical_joint_px: int = maxi(1, int(round(float(HEIGHT) * FAUQUENBERG_JOINT_WIDTH_M / FAUQUENBERG_TILE_HEIGHT_M)))
    var brick_width_px: int = int(round(float(WIDTH) * FAUQUENBERG_BRICK_LENGTH_M / FAUQUENBERG_TILE_WIDTH_M))
    var brick_height_px: int = int(round(float(HEIGHT) * FAUQUENBERG_BRICK_HEIGHT_M / FAUQUENBERG_TILE_HEIGHT_M))
    var course_height_px: int = brick_height_px + vertical_joint_px
    var half_module_px: int = (brick_width_px + horizontal_joint_px) / 2
    for course: int in range(2):
        var y0: int = course * course_height_px
        var y1: int = y0 + brick_height_px
        var offset: int = 0 if course == 0 else -half_module_px
        var brick_index := 0
        var x: int = offset
        while x < WIDTH:
            var color := brick_a if (brick_index + course) % 2 == 0 else brick_b
            _fill_image_rect(image, x, y0, x + brick_width_px, y1, color)
            x += brick_width_px + horizontal_joint_px
            brick_index += 1
    return ImageTexture.create_from_image(image)


func _fauquenberg_material(shadow: bool = false) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color.WHITE
    material.albedo_texture = _fauquenberg_texture(shadow)
    material.roughness = 0.95 if shadow else 0.92
    material.metallic = 0.0
    material.uv1_triplanar = true
    material.uv1_world_triplanar = false
    material.uv1_scale = Vector3(
        1.0 / FAUQUENBERG_TILE_WIDTH_M,
        1.0 / FAUQUENBERG_TILE_HEIGHT_M,
        1.0 / FAUQUENBERG_TILE_WIDTH_M
    )
    material.set_meta("source_brick_length_m", FAUQUENBERG_BRICK_LENGTH_M)
    material.set_meta("source_brick_height_m", FAUQUENBERG_BRICK_HEIGHT_M)
    material.set_meta("source_joint_width_m", FAUQUENBERG_JOINT_WIDTH_M)
    material.set_meta("procedural_original_asset", true)
    return material


func _make_materials() -> void:
    # Heritage inventory: yellow smooth Fauquenberg facing brick in a 24 x 4 x
    # 9 cm format with 2 cm joints, blue-stone bases/bands, concrete opening
    # frames and canopies, metal + extensive glazing.
    _brick_yellow = _fauquenberg_material(false)
    _brick_shadow = _fauquenberg_material(true)
    _blue_stone = _material(Color(0.235, 0.255, 0.27, 1.0), 0.86)
    _concrete = _material(Color(0.47, 0.48, 0.46, 1.0), 0.90)
    _glass = _material(Color(0.055, 0.085, 0.105, 1.0), 0.18, 0.20)
    _glass_block = _material(Color(0.32, 0.43, 0.45, 0.78), 0.26, 0.05)
    _glass_block.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    _metal = _material(Color(0.17, 0.19, 0.205, 1.0), 0.40, 0.62)
    _white = _material(Color(0.90, 0.89, 0.83, 1.0), 0.78)
    _pole = _material(Color(0.075, 0.085, 0.095, 1.0), 0.48, 0.44)
    _lamp = _material(Color(1.0, 0.80, 0.48, 1.0), 0.34)
    _tree_trunk = _material(Color(0.25, 0.17, 0.11, 1.0), 0.95)
    _tree_leaf = _material(Color(0.13, 0.23, 0.13, 1.0), 0.93)
    _shelter_glass = _material(Color(0.12, 0.20, 0.235, 0.68), 0.15, 0.10)
    _shelter_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    _sign_blue = _material(Color(0.055, 0.15, 0.31, 1.0), 0.55)
    _railing = _material(Color(0.07, 0.075, 0.08, 1.0), 0.48, 0.58)
    _paving = _material(Color(0.38, 0.37, 0.34, 1.0), 0.96)


func _add_box(parent: Node3D, name: String, size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
    var mesh: BoxMesh = BoxMesh.new()
    mesh.size = size
    mesh.material = material
    var instance: MeshInstance3D = MeshInstance3D.new()
    instance.name = name
    instance.mesh = mesh
    instance.position = position
    parent.add_child(instance)
    return instance


func _add_cylinder(parent: Node3D, name: String, radius: float, height: float, position: Vector3, material: Material) -> MeshInstance3D:
    var mesh: CylinderMesh = CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = height
    mesh.radial_segments = 8
    mesh.material = material
    var instance: MeshInstance3D = MeshInstance3D.new()
    instance.name = name
    instance.mesh = mesh
    instance.position = position
    parent.add_child(instance)
    return instance


func _road_angle() -> float:
    return atan2(FONSNY_AXIS.x, FONSNY_AXIS.z)


func _station_root() -> Node3D:
    var station: Node3D = Node3D.new()
    station.name = "BruxellesMidiStation"
    station.position = MIDI + STATION_SIDE * 34.0 + FONSNY_AXIS * 2.0
    station.rotation.y = _road_angle()
    add_child(station)
    return station


func _build_station_complex() -> void:
    var station: Node3D = _station_root()

    # Low station base / covered frontage running along Avenue Fonsny.
    _add_box(station, "StationBaseBlueStone", Vector3(45.0, 3.25, 171.0), Vector3(0.0, 1.625, 0.0), _blue_stone)
    _add_box(station, "StationLowerBrick", Vector3(44.6, 4.1, 170.0), Vector3(-0.1, 5.30, 0.0), _brick_yellow)
    _add_box(station, "StationLongGlassBand", Vector3(0.18, 2.0, 164.0), Vector3(22.40, 5.55, 0.0), _glass)
    _add_box(station, "StationRoofLine", Vector3(48.0, 0.55, 176.0), Vector3(0.0, 7.55, 0.0), _metal)

    # Distinct Fonsny administrative/postal volumes instead of one generic box.
    # The centre block is intentionally taller, reflecting the heritage facade
    # rhythm visible on Fonsny 47-49.
    _add_office_block(station, "FonsnyWingSouth", -57.0, 48.0, 6, false)
    _add_office_block(station, "FonsnyCentral", 0.0, 61.0, 7, true)
    _add_office_block(station, "FonsnyWingNorth", 60.0, 52.0, 6, false)

    # Break up the long station volume with vertical masonry joints.
    for local_z: float in [-82.0, -41.0, 39.0, 82.0]:
        _add_box(station, "StationMasonryJoint", Vector3(0.22, 6.0, 0.55), Vector3(22.56, 4.5, local_z), _brick_shadow)


func _add_office_block(parent: Node3D, name: String, local_z: float, length: float, floors: int, glass_tower: bool) -> void:
    var block: Node3D = Node3D.new()
    block.name = name
    block.position = Vector3(-1.8, 0.0, local_z)
    parent.add_child(block)

    var floor_height: float = 3.05
    var base_height: float = 3.15
    var upper_height: float = float(floors) * floor_height
    var total_height: float = base_height + upper_height
    var width: float = 41.0

    _add_box(block, "BlueStoneBase", Vector3(width, base_height, length), Vector3(0.0, base_height * 0.5, 0.0), _blue_stone)
    _add_box(block, "FauquenbergBrick", Vector3(width, upper_height, length), Vector3(0.0, base_height + upper_height * 0.5, 0.0), _brick_yellow)
    _add_box(block, "FlatRoof", Vector3(width + 1.1, 0.45, length + 1.1), Vector3(0.0, total_height + 0.225, 0.0), _metal)

    var front_x: float = width * 0.5 + 0.07
    var window_columns: int = maxi(6, int(floor(length / 3.15)))
    var bay_step: float = length / float(window_columns)

    # Strong horizontal concrete bands visible in the original modernist facade.
    for floor_index: int in range(floors + 1):
        var band_y: float = base_height + float(floor_index) * floor_height
        _add_box(block, "HorizontalBand_%02d" % floor_index, Vector3(0.16, 0.24, length - 0.35), Vector3(front_x, band_y, 0.0), _concrete)

    # Repetitive windows framed by concrete mullions and yellow brick infill.
    for column_index: int in range(window_columns):
        var z: float = -length * 0.5 + bay_step * (float(column_index) + 0.5)
        _add_box(block, "VerticalMullion_%02d" % column_index, Vector3(0.16, upper_height, 0.18), Vector3(front_x + 0.01, base_height + upper_height * 0.5, z - bay_step * 0.5), _concrete)
        for floor_index: int in range(floors):
            var y: float = base_height + float(floor_index) * floor_height + 1.62
            var window_depth: float = maxf(1.55, bay_step * 0.66)
            _add_box(block, "Window_%02d_%02d" % [column_index, floor_index], Vector3(0.12, 1.52, window_depth), Vector3(front_x + 0.10, y, z), _glass)

    # Ground-floor openings / storefront-like station offices.
    var ground_openings: int = maxi(4, int(floor(length / 7.8)))
    var ground_step: float = length / float(ground_openings)
    for opening_index: int in range(ground_openings):
        var opening_z: float = -length * 0.5 + ground_step * (float(opening_index) + 0.5)
        _add_box(block, "GroundOpening_%02d" % opening_index, Vector3(0.14, 2.18, minf(4.9, ground_step * 0.68)), Vector3(front_x + 0.11, 1.72, opening_z), _glass)

    if glass_tower:
        # Characteristic tall glazed/glass-block vertical bay on the central block.
        _add_box(block, "VerticalGlassTowerFrame", Vector3(0.20, upper_height + 0.45, 6.3), Vector3(front_x + 0.13, base_height + upper_height * 0.50, 0.0), _concrete)
        _add_box(block, "VerticalGlassTower", Vector3(0.13, upper_height - 0.65, 5.35), Vector3(front_x + 0.25, base_height + upper_height * 0.50, 0.0), _glass_block)


func _build_station_entrance() -> void:
    var entrance: Node3D = Node3D.new()
    entrance.name = "MidiMainEntranceFonsny"
    entrance.position = MIDI + STATION_SIDE * 10.5 + FONSNY_AXIS * -7.0
    entrance.rotation.y = _road_angle()
    add_child(entrance)

    _add_box(entrance, "EntranceBlueStoneWall", Vector3(0.34, 4.35, 23.0), Vector3(-14.8, 2.35, 0.0), _blue_stone)
    _add_box(entrance, "EntranceGlazing", Vector3(0.18, 3.65, 18.8), Vector3(-15.02, 2.15, 0.0), _glass)
    _add_box(entrance, "EntranceConcreteCanopy", Vector3(17.8, 0.48, 25.0), Vector3(-7.0, 4.55, 0.0), _concrete)
    _add_box(entrance, "CanopyMetalEdge", Vector3(18.0, 0.14, 25.3), Vector3(-7.0, 4.82, 0.0), _metal)

    for local_z: float in [-9.1, -3.1, 3.1, 9.1]:
        _add_cylinder(entrance, "EntranceColumn", 0.14, 4.25, Vector3(-13.9, 2.125, local_z), _metal)

    _add_box(entrance, "StationTotem", Vector3(0.62, 4.2, 1.55), Vector3(-16.75, 2.30, -11.2), _sign_blue)

    # SNCB/NMBS resolves the bilingual station identity and Fonsny 47 anchor.
    # Panel envelope, color and lettering remain authored presentation values.
    var identity_panel := _add_box(
        entrance,
        "StationIdentityPanel",
        Vector3(0.12, 1.55, 11.5),
        Vector3(-14.54, 3.48, -1.0),
        _sign_blue
    )
    identity_panel.set_meta("source_station_identity", "SNCB/NMBS Bruxelles-Midi / Brussel-Zuid")
    identity_panel.set_meta("surveyed_panel_dimensions", false)
    identity_panel.set_meta("sncb_logo_artwork_embedded", false)

    var station_fr := Label3D.new()
    station_fr.name = "StationIdentityFR"
    station_fr.text = "BRUXELLES-MIDI"
    station_fr.font_size = 48
    station_fr.pixel_size = 0.012
    station_fr.outline_size = 5
    station_fr.modulate = Color(0.97, 0.97, 0.94, 1.0)
    station_fr.billboard = BaseMaterial3D.BILLBOARD_DISABLED
    station_fr.rotation_degrees.y = -90.0
    station_fr.position = Vector3(0.08, 0.31, 0.0)
    identity_panel.add_child(station_fr)

    var station_nl := Label3D.new()
    station_nl.name = "StationIdentityNL"
    station_nl.text = "BRUSSEL-ZUID"
    station_nl.font_size = 42
    station_nl.pixel_size = 0.012
    station_nl.outline_size = 5
    station_nl.modulate = Color(0.97, 0.97, 0.94, 1.0)
    station_nl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
    station_nl.rotation_degrees.y = -90.0
    station_nl.position = Vector3(0.08, -0.34, 0.0)
    identity_panel.add_child(station_nl)


func _build_fonsny_forecourt() -> void:
    var forecourt: MeshInstance3D = _add_box(
        self,
        "FonsnyStationForecourt",
        Vector3(18.0, 0.10, 174.0),
        MIDI + STATION_SIDE * 15.5 + FONSNY_AXIS * 2.0 + Vector3(0.0, 0.13, 0.0),
        _paving
    )
    forecourt.rotation.y = _road_angle()


func _build_fonsny_crossing() -> void:
    var crossing_center: Vector3 = MIDI + FONSNY_AXIS * -18.0
    var angle: float = _road_angle()
    for stripe_index: int in range(10):
        var stripe: MeshInstance3D = _add_box(
            self,
            "Crosswalk_%02d" % stripe_index,
            Vector3(12.5, 0.035, 0.48),
            crossing_center + FONSNY_AXIS * (float(stripe_index) - 4.5) * 0.91 + Vector3(0.0, 0.16, 0.0),
            _white
        )
        stripe.rotation.y = angle


func _build_fonsny_street_furniture() -> void:
    for distance: float in [-88.0, -66.0, -44.0, -22.0, 0.0, 22.0, 44.0, 66.0, 88.0]:
        _add_lamp(MIDI + FONSNY_AXIS * distance + STATION_SIDE * 8.4)
        if int(distance) % 44 == 0:
            _add_lamp(MIDI + FONSNY_AXIS * distance + ROAD_SIDE * 8.6)

    for distance: float in [-76.0, -51.0, -26.0, 24.0, 49.0, 74.0]:
        _add_tree(MIDI + FONSNY_AXIS * distance + ROAD_SIDE * 13.1)

    for distance: float in [-28.0, -24.0, -20.0, 18.0, 22.0, 26.0]:
        _add_bollard(MIDI + FONSNY_AXIS * distance + STATION_SIDE * 7.2)


func _add_lamp(position: Vector3) -> void:
    var lamp_root: Node3D = Node3D.new()
    lamp_root.position = position
    add_child(lamp_root)
    _add_cylinder(lamp_root, "Pole", 0.075, 5.8, Vector3(0.0, 2.9, 0.0), _pole)
    _add_box(lamp_root, "Arm", Vector3(0.85, 0.07, 0.07), Vector3(0.34, 5.55, 0.0), _pole)
    _add_box(lamp_root, "Lamp", Vector3(0.30, 0.14, 0.22), Vector3(0.72, 5.48, 0.0), _lamp)


func _add_tree(position: Vector3) -> void:
    var tree: Node3D = Node3D.new()
    tree.position = position
    add_child(tree)
    _add_cylinder(tree, "Trunk", 0.16, 2.8, Vector3(0.0, 1.4, 0.0), _tree_trunk)
    var crown_mesh: SphereMesh = SphereMesh.new()
    crown_mesh.radius = 1.65
    crown_mesh.height = 3.2
    crown_mesh.radial_segments = 8
    crown_mesh.rings = 4
    crown_mesh.material = _tree_leaf
    var crown: MeshInstance3D = MeshInstance3D.new()
    crown.mesh = crown_mesh
    crown.position = Vector3(0.0, 4.0, 0.0)
    tree.add_child(crown)


func _add_bollard(position: Vector3) -> void:
    _add_cylinder(self, "Bollard", 0.09, 0.82, position + Vector3(0.0, 0.41, 0.0), _pole)


func _build_shelters() -> void:
    _add_shelter(MIDI + FONSNY_AXIS * 34.0 + ROAD_SIDE * 9.6)
    _add_shelter(MIDI + FONSNY_AXIS * -54.0 + STATION_SIDE * 9.6)


func _add_shelter(position: Vector3) -> void:
    var shelter: Node3D = Node3D.new()
    shelter.position = position
    shelter.rotation.y = _road_angle()
    add_child(shelter)
    _add_box(shelter, "ShelterRoof", Vector3(2.2, 0.16, 4.8), Vector3(0.0, 2.55, 0.0), _metal)
    _add_box(shelter, "ShelterBack", Vector3(0.12, 2.2, 4.4), Vector3(-1.0, 1.4, 0.0), _shelter_glass)
    _add_box(shelter, "ShelterBench", Vector3(0.55, 0.12, 2.6), Vector3(-0.45, 0.72, 0.0), _blue_stone)
    _add_box(shelter, "StopPanel", Vector3(0.16, 2.3, 0.55), Vector3(1.15, 1.45, -1.65), _sign_blue)


func _build_tram_railings() -> void:
    # Characteristic black railings separating the tram corridor / traffic edge.
    for side: float in [-1.0, 1.0]:
        var side_offset: Vector3 = STATION_SIDE * 5.3 if side < 0.0 else ROAD_SIDE * 5.3
        for distance_index: int in range(-18, 19):
            var distance: float = float(distance_index) * 5.0
            if absf(distance + 18.0) < 8.0:
                continue
            var base: Vector3 = MIDI + FONSNY_AXIS * distance + side_offset
            _add_cylinder(self, "RailingPost", 0.045, 1.12, base + Vector3(0.0, 0.56, 0.0), _railing)
            if distance_index < 18:
                var rail: MeshInstance3D = _add_box(self, "RailingTop", Vector3(0.07, 0.07, 5.0), base + FONSNY_AXIS * 2.5 + Vector3(0.0, 0.94, 0.0), _railing)
                rail.rotation.y = _road_angle()

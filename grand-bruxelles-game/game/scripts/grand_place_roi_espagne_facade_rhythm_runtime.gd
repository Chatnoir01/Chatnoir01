extends Node3D

const CONTRACT_PATH := "res://data/qa/grand_place_roi_espagne_facade_rhythm.json"
const WHITE_STONE := preload("res://game/scripts/brussels_white_stone_material.gd")
const BLUE_STONE := preload("res://game/scripts/brussels_blue_stone_material.gd")
const GLAZING := preload("res://game/scripts/brussels_architectural_glazing_material.gd")

var _register_count := 0
var _pilaster_count := 0
var _band_count := 0
var _opening_count := 0
var _central_projection_count := 0
var _dome_count := 0
var _visual_enabled := true
var _visual_root: Node3D
var _stone_material: Material
var _blue_material: Material
var _glass_material: Material
var _roof_material: StandardMaterial3D

func _ready() -> void:
    _build()

func _read_contract() -> Dictionary:
    if not FileAccess.file_exists(CONTRACT_PATH):
        push_error("Roi d'Espagne facade contract missing")
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Roi d'Espagne facade contract invalid")
        return {}
    var data := parsed as Dictionary
    if str(data.get("schema", "")) != "grand-bruxelles-roi-espagne-facade-rhythm-v1":
        push_error("Roi d'Espagne facade schema drifted")
        return {}
    if str(data.get("building_id", "")) != "1645616" or str(data.get("official_front_wall_face_id", "")) != "10878705":
        push_error("Roi d'Espagne source identity drifted")
        return {}
    if bool(data.get("runtime_approved", true)) or bool(data.get("realism_complete", true)):
        push_error("Roi d'Espagne candidate must remain provisional")
        return {}
    return data

func _vec2(raw: Variant) -> Vector2:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 2:
        return Vector2.ZERO
    return Vector2(float(raw[0]), float(raw[1]))

func _box(name_value: String, size_value: Vector3, position_value: Vector3, yaw: float, material: Material) -> CSGBox3D:
    var box := CSGBox3D.new()
    box.name = name_value
    box.size = size_value
    box.position = position_value
    box.rotation.y = yaw
    box.material = material
    box.use_collision = false
    _visual_root.add_child(box)
    return box

func _make_materials() -> void:
    _stone_material = WHITE_STONE.create(
        Color(0.73, 0.71, 0.66, 1.0),
        Color(0.86, 0.83, 0.75, 1.0),
        0.82,
        "Urban 31119 documents Euville white stone on Roi d'Espagne facade"
    )
    _blue_material = BLUE_STONE.create(
        Color(0.20, 0.22, 0.23, 1.0),
        Color(0.32, 0.34, 0.35, 1.0),
        0.86,
        "Urban 31119 documents blue-stone base on Roi d'Espagne facade"
    )
    _glass_material = GLAZING.create(
        "Urban 31119 documents seven facade bays; exact opening dimensions remain visualization convention"
    )
    _roof_material = StandardMaterial3D.new()
    _roof_material.albedo_color = Color(0.16, 0.18, 0.19, 1.0)
    _roof_material.roughness = 0.88
    _roof_material.set_meta("material_family", "roi_espagne_neutral_dome_visualization")
    _roof_material.set_meta("exact_material_source_backed", false)

func _build() -> void:
    var data := _read_contract()
    if data.is_empty():
        return
    var front: Dictionary = data.get("official_front_wall", {})
    var visual: Dictionary = data.get("provisional_visualization", {})
    var left_xz := _vec2(front.get("bottom_left_game_x_z", []))
    var right_xz := _vec2(front.get("bottom_right_game_x_z", []))
    var toward_xz := _vec2(front.get("toward_grand_place_x_z", []))
    var span := float(front.get("plane_span_m", 0.0))
    var tangent := Vector3(right_xz.x - left_xz.x, 0.0, right_xz.y - left_xz.y).normalized()
    var toward := Vector3(toward_xz.x, 0.0, toward_xz.y).normalized()
    if tangent.length_squared() < 0.99 or toward.length_squared() < 0.99 or span < 10.0:
        push_error("Roi d'Espagne facade basis invalid")
        return

    _make_materials()
    _visual_root = Node3D.new()
    _visual_root.name = "RoiEspagneFacadeVisual"
    add_child(_visual_root)

    var base_y := float(visual.get("facade_base_y_m", 0.75))
    var top_y := float(visual.get("facade_top_y_m", 16.75))
    var forward_offset := float(visual.get("forward_offset_m", 0.08))
    var register_gap := float(visual.get("register_gap_m", 0.24))
    var pilaster_width := float(visual.get("pilaster_width_m", 0.20))
    var pilaster_depth := float(visual.get("pilaster_depth_m", 0.16))
    var opening_margin := float(visual.get("opening_margin_ratio", 0.20))
    var opening_depth := float(visual.get("opening_depth_m", 0.10))
    var projection_depth := float(visual.get("central_projection_depth_m", 0.28))
    var center := Vector3((left_xz.x + right_xz.x) * 0.5, 0.0, (left_xz.y + right_xz.y) * 0.5)
    var yaw := atan2(toward.x, toward.z)

    var total_weight := 6.0 + 1.35
    var regular_width := span / total_weight
    var bay_widths: Array[float] = [regular_width, regular_width, regular_width, regular_width * 1.35, regular_width, regular_width, regular_width]
    var edges: Array[float] = [-span * 0.5]
    for width: float in bay_widths:
        edges.append(edges[-1] + width)

    var central_left := edges[3]
    var central_right := edges[4]
    var central_width := central_right - central_left
    var central_along := (central_left + central_right) * 0.5
    _box(
        "CentralBayProjection",
        Vector3(central_width, top_y - base_y, projection_depth),
        center + tangent * central_along + toward * (forward_offset + projection_depth * 0.5) + Vector3(0.0, (base_y + top_y) * 0.5, 0.0),
        yaw,
        _stone_material
    )
    _central_projection_count = 1

    var base_height := 0.70
    _box(
        "BlueStoneBase",
        Vector3(span, base_height, 0.20),
        center + toward * (forward_offset + 0.11) + Vector3(0.0, base_y + base_height * 0.5, 0.0),
        yaw,
        _blue_material
    )

    var available_height := top_y - base_y - base_height - register_gap * 2.0
    var register_height := available_height / 3.0
    for register_index: int in range(3):
        var register_bottom := base_y + base_height + float(register_index) * (register_height + register_gap)
        var register_center_y := register_bottom + register_height * 0.5
        for edge_index: int in range(edges.size()):
            var along := edges[edge_index]
            _box(
                "Register_%d_Pilaster_%02d" % [register_index, edge_index],
                Vector3(pilaster_width, register_height, pilaster_depth),
                center + tangent * along + toward * (forward_offset + pilaster_depth * 0.5 + 0.015) + Vector3(0.0, register_center_y, 0.0),
                yaw,
                _stone_material
            )
            _pilaster_count += 1

        for bay_index: int in range(7):
            var left_edge := edges[bay_index]
            var right_edge := edges[bay_index + 1]
            var width := right_edge - left_edge
            var along_center := (left_edge + right_edge) * 0.5
            var panel_width := width * (1.0 - opening_margin * 2.0)
            var panel_height := register_height * 0.63
            var extra_forward := projection_depth if bay_index == 3 else 0.0
            _box(
                "Register_%d_Bay_%02d" % [register_index, bay_index],
                Vector3(panel_width, panel_height, opening_depth),
                center + tangent * along_center + toward * (forward_offset + extra_forward + opening_depth * 0.55 + 0.02) + Vector3(0.0, register_center_y, 0.0),
                yaw,
                _glass_material
            )
            _opening_count += 1
        _register_count += 1

        if register_index < 2:
            var separator_y := register_bottom + register_height + register_gap * 0.5
            _box(
                "RegisterSeparator_%d" % register_index,
                Vector3(span, 0.18, 0.18),
                center + toward * (forward_offset + 0.10) + Vector3(0.0, separator_y, 0.0),
                yaw,
                _stone_material
            )
            _band_count += 1

    var dome_center_y := float(visual.get("dome_center_y_m", 21.0))
    var dome_width := float(visual.get("dome_width_m", 6.2))
    var dome_height := float(visual.get("dome_height_m", 5.4))
    var dome_depth := float(visual.get("dome_depth_m", 4.8))
    var dome_mesh := SphereMesh.new()
    dome_mesh.radius = 1.0
    dome_mesh.height = 2.0
    dome_mesh.radial_segments = 32
    dome_mesh.rings = 16
    var dome := MeshInstance3D.new()
    dome.name = "AxialDomeCue"
    dome.mesh = dome_mesh
    dome.material_override = _roof_material
    dome.position = center + tangent * central_along - toward * 0.75 + Vector3(0.0, dome_center_y, 0.0)
    dome.rotation.y = yaw
    dome.scale = Vector3(dome_width * 0.5, dome_height * 0.5, dome_depth * 0.5)
    _visual_root.add_child(dome)
    _dome_count = 1

    set_meta("runtime_approved", false)
    set_meta("realism_complete", false)
    set_meta("source_building_id", "1645616")
    set_meta("source_wall_face_id", "10878705")
    set_meta("heritage_bay_count", 7)
    set_meta("heritage_register_count", 3)
    set_meta("opening_proxy_count", _opening_count)
    print("Roi d'Espagne facade candidate: registers=%d pilasters=%d openings=%d bands=%d central=1 dome=1 runtime_approved=false" % [_register_count, _pilaster_count, _opening_count, _band_count])

func set_visual_enabled(enabled: bool) -> void:
    _visual_enabled = enabled
    if _visual_root != null:
        _visual_root.visible = enabled

func diagnostic_register_count() -> int:
    return _register_count

func diagnostic_pilaster_count() -> int:
    return _pilaster_count

func diagnostic_band_count() -> int:
    return _band_count

func diagnostic_opening_count() -> int:
    return _opening_count

func diagnostic_central_projection_count() -> int:
    return _central_projection_count

func diagnostic_dome_count() -> int:
    return _dome_count

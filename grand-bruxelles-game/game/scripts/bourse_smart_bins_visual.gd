extends Node3D

@export_file("*.json") var source_path: String = "res://data/provenance/bourse_smart_bins.json"
@export var build_on_ready: bool = true

var source_bin_count: int = 0
var rendered_bin_count: int = 0
var source_locations_are_official: bool = false
var visual_dimensions_are_authored: bool = false
var contains_bourse_stairs_pair: bool = false
var min_solar_panel_area_m2: float = 0.0

var _body_material: StandardMaterial3D
var _trim_material: StandardMaterial3D
var _opening_material: StandardMaterial3D
var _solar_material: StandardMaterial3D

func _ready() -> void:
    if build_on_ready:
        build()

func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = metallic
    return material

func _make_materials() -> void:
    # Authored presentation palette: no claim of measured manufacturer colors.
    _body_material = _material(Color(0.19, 0.215, 0.205, 1.0), 0.72, 0.06)
    _trim_material = _material(Color(0.095, 0.105, 0.10, 1.0), 0.62, 0.18)
    _opening_material = _material(Color(0.025, 0.03, 0.03, 1.0), 0.92)
    _solar_material = _material(Color(0.035, 0.075, 0.105, 1.0), 0.28, 0.14)

func _box(name: String, size: Vector3, position: Vector3, material: Material, parent: Node3D, rotation_degrees_value: Vector3 = Vector3.ZERO) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = size
    var node := MeshInstance3D.new()
    node.name = name
    node.mesh = mesh
    node.material_override = material
    node.position = position
    node.rotation_degrees = rotation_degrees_value
    parent.add_child(node)
    return node

func _build_bin(record: Dictionary, dims: Dictionary) -> Node3D:
    var bin := Node3D.new()
    bin.name = str(record.get("id", "SmartBin"))
    var game: Array = record.get("game", [])
    if game.size() == 3:
        bin.position = Vector3(float(game[0]), float(game[1]), float(game[2]))
    bin.rotation_degrees.y = float(record.get("yaw_degrees_authored", 0.0))
    bin.set_meta("source_label", str(record.get("source_label", "")))
    bin.set_meta("source_wgs84", record.get("wgs84", []))
    bin.set_meta("orientation_authored", true)

    var width := float(dims.get("enclosure_width_m", 0.72))
    var depth := float(dims.get("enclosure_depth_m", 0.72))
    var height := float(dims.get("enclosure_height_m", 1.18))
    var panel_width := float(dims.get("solar_panel_width_m", 0.64))
    var panel_depth := float(dims.get("solar_panel_depth_m", 0.43))
    var panel_thickness := float(dims.get("solar_panel_thickness_m", 0.06))

    _box("Enclosure", Vector3(width, height, depth), Vector3(0.0, height * 0.5, 0.0), _body_material, bin)
    _box("TopTrim", Vector3(width + 0.035, 0.085, depth + 0.035), Vector3(0.0, height + 0.012, 0.0), _trim_material, bin)
    _box("FrontOpening", Vector3(width * 0.58, height * 0.26, 0.026), Vector3(0.0, height * 0.72, -depth * 0.515), _opening_material, bin)
    _box("FrontFlapLip", Vector3(width * 0.66, 0.055, 0.065), Vector3(0.0, height * 0.58, -depth * 0.54), _trim_material, bin)
    _box("SolarPanel", Vector3(panel_width, panel_thickness, panel_depth), Vector3(0.0, height + 0.13, 0.015), _solar_material, bin, Vector3(7.0, 0.0, 0.0))
    _box("SolarFrame", Vector3(panel_width + 0.035, panel_thickness * 0.48, panel_depth + 0.035), Vector3(0.0, height + 0.105, 0.014), _trim_material, bin, Vector3(7.0, 0.0, 0.0))
    return bin

func build() -> bool:
    if not FileAccess.file_exists(source_path):
        push_error("Bourse smart-bin provenance missing: %s" % source_path)
        return false
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(source_path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Bourse smart-bin provenance invalid")
        return false
    var data: Dictionary = parsed
    var source: Dictionary = data.get("source", {})
    if str(source.get("publisher", "")).find("Ville de Bruxelles") < 0:
        push_error("Bourse smart-bin publisher contract missing")
        return false
    if str(source.get("license", "")) != "CC0-1.0":
        push_error("Bourse smart-bin source license drifted")
        return false
    var dims: Dictionary = data.get("authored_visual_values", {})
    visual_dimensions_are_authored = str(dims.get("note", "")).contains("authored presentation values")
    source_locations_are_official = true
    _make_materials()

    var placements: Array = data.get("placements", [])
    source_bin_count = placements.size()
    var ids: Dictionary = {}
    min_solar_panel_area_m2 = INF
    var panel_area := float(dims.get("solar_panel_width_m", 0.0)) * float(dims.get("solar_panel_depth_m", 0.0))
    for raw: Variant in placements:
        if typeof(raw) != TYPE_DICTIONARY:
            continue
        var record: Dictionary = raw
        var id := str(record.get("id", ""))
        ids[id] = true
        add_child(_build_bin(record, dims))
        rendered_bin_count += 1
        min_solar_panel_area_m2 = minf(min_solar_panel_area_m2, panel_area)
    contains_bourse_stairs_pair = ids.has("bourse_stairs_right") and ids.has("bourse_stairs_left")
    if min_solar_panel_area_m2 == INF:
        min_solar_panel_area_m2 = 0.0
    set_meta("source_dataset", "poubellesintelligentes")
    set_meta("source_license", "CC0-1.0")
    set_meta("visual_dimensions_authored", true)
    print("Bourse smart bins: %d/%d source-backed placements rendered" % [rendered_bin_count, source_bin_count])
    return rendered_bin_count == source_bin_count and source_bin_count > 0

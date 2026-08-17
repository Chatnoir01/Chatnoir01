extends Node3D

const PLAN_PATH := "res://data/qa/grand_place_brasseurs_photo_plan.json"
const FEATURES_PATH := "res://data/qa/grand_place_brasseurs_photo_features.json"
const VERTICAL_PATH := "res://data/qa/grand_place_brasseurs_wall_vertical.json"
const BUILDING_ID := "https://databrussels.be/id/building/1639974"
const WALL_ID := "https://databrussels.be/id/buildingface/10945501"
const SOURCE_SHA256 := "fff8d81aaca8b3dd82247ef8d171bdb61cb1e294d530185a16566298569ed322"
const EXPECTED_SPAN_M := 8.7490357183

var facade_ready := false
var building_id := BUILDING_ID
var source_wall_id := WALL_ID
var source_facade_span_m := EXPECTED_SPAN_M
var bay_count := 3
var column_offsets_m: Array = []
var photo_source_sha256 := SOURCE_SHA256
var raw_photo_pixels_shipped := false
var geometry_claimed_surveyed := false
var vertical_world_scale_source := "official_lod2_wall"
var feature_count := 0
var _features: Dictionary
var _root: Node3D
var _stone: StandardMaterial3D
var _dark: StandardMaterial3D

func _ready() -> void:
    call_deferred("_build")

func _json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return parsed as Dictionary if parsed is Dictionary else {}

func _build() -> void:
    var plan := _json(PLAN_PATH)
    _features = _json(FEATURES_PATH)
    var vertical := _json(VERTICAL_PATH)
    if plan.is_empty() or _features.is_empty() or vertical.is_empty():
        return
    var placement: Dictionary = plan.get("placement", {})
    var source: Dictionary = plan.get("source", {})
    var mapping: Dictionary = _features.get("mapping", {})
    if str(placement.get("building_id", "")) != "1639974" or str(placement.get("front_wall_id", "")) != "10945501":
        return
    if str(source.get("download_sha256", "")) != SOURCE_SHA256:
        return
    if str(vertical.get("vertical_world_scale_source", "")) != "official_lod2_wall":
        return
    if str(mapping.get("vertical_world_source", "")) != "official_lod2_wall_piecewise_anchors":
        return
    if str(mapping.get("vertical_mapping", "")) != "piecewise_ground_to_shoulder_then_shoulder_to_apex":
        return
    if bool(mapping.get("raw_photo_pixels_shipped", true)) or bool(mapping.get("photo_geometry_claimed_surveyed", true)):
        return
    column_offsets_m = (plan.get("derived_horizontal_world_constraints", {}).get("column_center_offsets_from_left_m", []) as Array).duplicate()
    if column_offsets_m.size() != 4:
        return
    _stone = StandardMaterial3D.new()
    _stone.albedo_color = Color(0.78, 0.71, 0.56, 1.0)
    _stone.roughness = 0.80
    _dark = StandardMaterial3D.new()
    _dark.albedo_color = Color(0.055, 0.05, 0.043, 1.0)
    _dark.roughness = 0.52
    _root = Node3D.new()
    _root.name = "BrasseursPhotoConstrainedFacade"
    add_child(_root)
    var verts: Array = vertical.get("unique_world_vertices", [])
    if verts.size() != 5:
        return
    var left := _v3(verts[0])
    var right := _v3(verts[3])
    var axis := Vector3(right.x-left.x, 0.0, right.z-left.z).normalized()
    var outward := Vector3(-axis.z, 0.0, axis.x)
    var player := Vector3(319.01, 1.72, -535.20)
    if outward.dot(player-left) < 0.0:
        outward = -outward
    _root.global_transform = Transform3D(Basis(axis, Vector3.UP, outward), left + outward * 0.055)
    _build_bands()
    _build_columns()
    _build_windows()
    _build_arcades()
    set_meta("building_id", BUILDING_ID)
    set_meta("source_wall_id", WALL_ID)
    set_meta("photo_source_sha256", SOURCE_SHA256)
    set_meta("vertical_world_scale_source", "official_lod2_wall")
    set_meta("vertical_mapping", "piecewise_official_anchors")
    set_meta("raw_photo_pixels_shipped", false)
    set_meta("geometry_claimed_surveyed", false)
    set_meta("depth_source", "bounded_visualization_convention_not_survey")
    set_meta("runtime_approved", false)
    set_meta("realism_complete", false)
    facade_ready = feature_count >= 24
    print("GRAND_PLACE_BRASSEURS_PHOTO_FACADE_READY: details=%d piecewise=true wall=10945501" % feature_count)

func _v3(raw: Variant) -> Vector3:
    if not (raw is Array) or (raw as Array).size() != 3:
        return Vector3.INF
    return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))

func _x(px: float) -> float:
    var mapping: Dictionary = _features["mapping"]
    return clampf((px-float(mapping["facade_left_px"]))/(float(mapping["facade_right_px"])-float(mapping["facade_left_px"])), 0.0, 1.0) * EXPECTED_SPAN_M

func _y(py: float) -> float:
    var mapping: Dictionary = _features["mapping"]
    var ground := float(mapping["facade_ground_y_px"])
    var shoulder_px := float(mapping["official_wall_shoulder_photo_y_px"])
    var apex_px := float(mapping["official_wall_apex_photo_y_px"])
    var shoulder_y := float(mapping["official_wall_shoulder_reference_y_m"])
    var apex_y := float(mapping["official_wall_apex_y_m"])
    if py >= shoulder_px:
        return clampf((ground-py)/(ground-shoulder_px), 0.0, 1.0) * shoulder_y
    return shoulder_y + clampf((shoulder_px-py)/(shoulder_px-apex_px), 0.0, 1.0) * (apex_y-shoulder_y)

func _box(name_value: String, x0: float, x1: float, y0: float, y1: float, z: float, material: Material) -> void:
    var node := MeshInstance3D.new()
    node.name = name_value
    var mesh := BoxMesh.new()
    mesh.size = Vector3(maxf(x1-x0, 0.03), maxf(y1-y0, 0.03), 0.08)
    mesh.material = material
    node.mesh = mesh
    node.position = Vector3((x0+x1)*0.5, (y0+y1)*0.5, z)
    _root.add_child(node)
    feature_count += 1

func _build_bands() -> void:
    for raw: Variant in _features["major_bands"]:
        var band := raw as Dictionary
        var y := _y(float(band["y_px"]))
        _box("Band_%s" % str(band["id"]), 0.0, EXPECTED_SPAN_M, y-0.10, y+0.10, 0.10, _stone)

func _build_columns() -> void:
    var order: Dictionary = _features["colossal_order"]
    var shaft_bottom := _y(float(order["shaft_bottom_y_px"]))
    var shaft_top := _y(float(order["shaft_top_y_px"]))
    var base_bottom := _y(float(order["base_bottom_y_px"]))
    var base_top := _y(float(order["base_top_y_px"]))
    var capital_bottom := _y(float(order["capital_bottom_y_px"]))
    var capital_top := _y(float(order["capital_top_y_px"]))
    for i: int in range(4):
        var x := float(column_offsets_m[i])
        var shaft := MeshInstance3D.new()
        shaft.name = "ColossalColumn_%d" % i
        var mesh := CylinderMesh.new()
        mesh.top_radius = 0.19
        mesh.bottom_radius = 0.23
        mesh.height = shaft_top-shaft_bottom
        mesh.radial_segments = 14
        mesh.material = _stone
        shaft.mesh = mesh
        shaft.position = Vector3(x, (shaft_top+shaft_bottom)*0.5, 0.15)
        _root.add_child(shaft)
        feature_count += 1
        _box("Base_%d" % i, x-0.29, x+0.29, base_bottom, base_top, 0.16, _stone)
        _box("Capital_%d" % i, x-0.33, x+0.33, capital_bottom, capital_top, 0.16, _stone)

func _build_windows() -> void:
    for raw: Variant in _features["principal_windows"]:
        var window := raw as Dictionary
        var x0 := _x(float(window["left_px"]))
        var x1 := _x(float(window["right_px"]))
        var bottom := _y(float(window["bottom_px"]))
        var top := _y(float(window["top_px"]))
        _box("Window_%s" % str(window["id"]), x0, x1, bottom, top, 0.075, _dark)
        _box("Lintel_%s" % str(window["id"]), x0-0.07, x1+0.07, top, top+0.16, 0.12, _stone)

func _build_arcades() -> void:
    for raw: Variant in _features["ground_arcades"]:
        var arcade := raw as Dictionary
        var x0 := _x(float(arcade["left_px"]))
        var x1 := _x(float(arcade["right_px"]))
        var bottom := _y(float(arcade["bottom_px"]))
        var top := _y(float(arcade["arch_top_y_px"]))
        _box("Arcade_%s" % str(arcade["id"]), x0, x1, bottom, top, 0.08, _dark)

func set_facade_visible(enabled: bool) -> void:
    visible = enabled

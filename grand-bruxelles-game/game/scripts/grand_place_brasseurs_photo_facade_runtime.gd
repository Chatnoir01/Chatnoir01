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

var _feature_root: Node3D
var _stone_material: StandardMaterial3D
var _dark_material: StandardMaterial3D
var _gold_material: StandardMaterial3D
var _detail_count := 0

func _ready() -> void:
    call_deferred("_build")

func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        push_error("Brasseurs photo facade: missing %s" % path)
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Brasseurs photo facade: invalid JSON %s" % path)
        return {}
    return parsed as Dictionary

func _build() -> void:
    var plan := _read_json(PLAN_PATH)
    var features := _read_json(FEATURES_PATH)
    var vertical := _read_json(VERTICAL_PATH)
    if plan.is_empty() or features.is_empty() or vertical.is_empty():
        return
    if not _validate_sources(plan, features, vertical):
        return

    var derived: Dictionary = plan.get("derived_horizontal_world_constraints", {})
    column_offsets_m = (derived.get("column_center_offsets_from_left_m", []) as Array).duplicate()

    _make_materials()
    _feature_root = Node3D.new()
    _feature_root.name = "BrasseursPhotoConstrainedFacade"
    add_child(_feature_root)

    var raw_vertices: Array = vertical.get("unique_world_vertices", [])
    var left := _vec3(raw_vertices[0])
    var right := _vec3(raw_vertices[3])
    var axis := Vector3(right.x - left.x, 0.0, right.z - left.z).normalized()
    if not axis.is_finite() or axis.length_squared() < 0.9:
        push_error("Brasseurs photo facade: invalid official wall axis")
        return
    var outward := Vector3(-axis.z, 0.0, axis.x)
    # Keep the overlay only centimetres off the source wall to avoid z-fighting;
    # the official UrbIS wall remains the world-position authority.
    _feature_root.global_transform = Transform3D(Basis(axis, Vector3.UP, outward), left + outward * 0.055)

    _build_major_bands(features)
    _build_principal_columns(features)
    _build_principal_windows(features)
    _build_ground_openings(features)
    _build_crowning(features)

    set_meta("building_id", BUILDING_ID)
    set_meta("source_wall_id", WALL_ID)
    set_meta("source_facade_span_m", EXPECTED_SPAN_M)
    set_meta("vertical_world_scale_source", vertical_world_scale_source)
    set_meta("photo_source_sha256", SOURCE_SHA256)
    set_meta("raw_photo_pixels_shipped", false)
    set_meta("geometry_claimed_surveyed", false)
    set_meta("runtime_approved", false)
    set_meta("realism_complete", false)
    set_meta("presentation_role", "photo_constrained_secondary_facade_articulation")
    facade_ready = true
    print("GRAND_PLACE_BRASSEURS_PHOTO_FACADE_READY: wall=10945501 bays=3 details=%d span=%.6f vertical_source=official_lod2_wall photo_pixels=false surveyed=false" % [_detail_count, source_facade_span_m])

func _validate_sources(plan: Dictionary, features: Dictionary, vertical: Dictionary) -> bool:
    var placement: Dictionary = plan.get("placement", {})
    var source: Dictionary = plan.get("source", {})
    if str(placement.get("building_id", "")) != "1639974":
        push_error("Brasseurs photo facade: plan building identity drifted")
        return false
    if str(placement.get("front_wall_id", "")) != "10945501":
        push_error("Brasseurs photo facade: plan wall identity drifted")
        return false
    if abs(float(placement.get("front_wall_span_m", 0.0)) - EXPECTED_SPAN_M) > 0.00001:
        push_error("Brasseurs photo facade: official wall span drifted")
        return false
    if str(source.get("download_sha256", "")) != SOURCE_SHA256:
        push_error("Brasseurs photo facade: photo provenance drifted")
        return false
    if str(vertical.get("building_id", "")) != "1639974" or str(vertical.get("front_wall_id", "")) != "10945501":
        push_error("Brasseurs photo facade: vertical witness identity drifted")
        return false
    if str(vertical.get("vertical_world_scale_source", "")) != "official_lod2_wall":
        push_error("Brasseurs photo facade: independent LoD2 vertical source missing")
        return false
    if abs(float(vertical.get("wall_vertical_extent_m", 0.0)) - 24.746) > 0.001:
        push_error("Brasseurs photo facade: official wall vertical extent drifted")
        return false
    var mapping: Dictionary = features.get("mapping", {})
    if bool(mapping.get("raw_photo_pixels_shipped", true)) or bool(mapping.get("photo_geometry_claimed_surveyed", true)):
        push_error("Brasseurs photo facade: source/presentation boundary drifted")
        return false
    if str(mapping.get("vertical_world_source", "")) != "official_lod2_wall":
        push_error("Brasseurs photo facade: feature vertical source drifted")
        return false
    return true

func _vec3(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or (raw as Array).size() != 3:
        return Vector3.INF
    var a := raw as Array
    return Vector3(float(a[0]), float(a[1]), float(a[2]))

func _make_materials() -> void:
    _stone_material = StandardMaterial3D.new()
    _stone_material.albedo_color = Color(0.80, 0.72, 0.52, 1.0)
    _stone_material.roughness = 0.78
    _dark_material = StandardMaterial3D.new()
    _dark_material.albedo_color = Color(0.09, 0.075, 0.055, 1.0)
    _dark_material.roughness = 0.58
    _gold_material = StandardMaterial3D.new()
    _gold_material.albedo_color = Color(0.72, 0.51, 0.16, 1.0)
    _gold_material.metallic = 0.55
    _gold_material.roughness = 0.42

func _px_x(px: float, features: Dictionary) -> float:
    var mapping: Dictionary = features.get("mapping", {})
    var left_px := float(mapping.get("facade_left_px", 590.0))
    var right_px := float(mapping.get("facade_right_px", 2245.0))
    return clampf((px - left_px) / maxf(right_px - left_px, 1.0), 0.0, 1.0) * source_facade_span_m

func _px_y(px: float, features: Dictionary) -> float:
    var mapping: Dictionary = features.get("mapping", {})
    var ground_px := float(mapping.get("facade_ground_y_px", 5360.0))
    var apex_px := float(mapping.get("official_wall_apex_photo_y_px", 1775.0))
    var height_m := float(mapping.get("official_wall_height_m", 24.746))
    return clampf((ground_px - px) / maxf(ground_px - apex_px, 1.0), 0.0, 1.0) * height_m

func _add_box(name_value: String, center: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = Vector3(maxf(size.x, 0.02), maxf(size.y, 0.02), maxf(size.z, 0.015))
    var instance := MeshInstance3D.new()
    instance.name = name_value
    instance.mesh = mesh
    instance.material_override = material
    instance.position = center
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    _feature_root.add_child(instance)
    _detail_count += 1
    return instance

func _build_major_bands(features: Dictionary) -> void:
    for raw: Variant in features.get("major_bands", []):
        if typeof(raw) != TYPE_DICTIONARY:
            continue
        var band := raw as Dictionary
        var y := _px_y(float(band.get("y_px", 0.0)), features)
        _add_box("Band_%s" % str(band.get("id", "band")), Vector3(source_facade_span_m * 0.5, y, 0.10), Vector3(source_facade_span_m, 0.24, 0.20), _stone_material)

func _build_principal_columns(features: Dictionary) -> void:
    var order: Dictionary = features.get("colossal_order", {})
    var top := _px_y(float(order.get("capital_top_y_px", 2440.0)), features)
    var bottom := _px_y(float(order.get("base_bottom_y_px", 4070.0)), features)
    var h := maxf(top - bottom, 0.5)
    for i: int in range(column_offsets_m.size()):
        var x := float(column_offsets_m[i])
        _add_box("ColossalColumn_%d" % i, Vector3(x, bottom + h * 0.5, 0.19), Vector3(0.34, h, 0.30), _stone_material)
        _add_box("ColumnCapital_%d" % i, Vector3(x, top - 0.16, 0.20), Vector3(0.58, 0.34, 0.34), _stone_material)
        _add_box("ColumnBase_%d" % i, Vector3(x, bottom + 0.16, 0.20), Vector3(0.52, 0.32, 0.34), _stone_material)

func _build_principal_windows(features: Dictionary) -> void:
    for raw: Variant in features.get("principal_windows", []):
        if typeof(raw) != TYPE_DICTIONARY:
            continue
        var window := raw as Dictionary
        var x0 := _px_x(float(window.get("left_px", 0.0)), features)
        var x1 := _px_x(float(window.get("right_px", 0.0)), features)
        var y_top := _px_y(float(window.get("top_px", 0.0)), features)
        var y_bottom := _px_y(float(window.get("bottom_px", 0.0)), features)
        var width := maxf(x1 - x0, 0.15)
        var height := maxf(y_top - y_bottom, 0.15)
        _add_box("Window_%s" % str(window.get("id", "window")), Vector3((x0 + x1) * 0.5, y_bottom + height * 0.5, 0.075), Vector3(width, height, 0.045), _dark_material)
        _add_box("WindowLintel_%s" % str(window.get("id", "window")), Vector3((x0 + x1) * 0.5, y_top + 0.09, 0.12), Vector3(width + 0.18, 0.18, 0.12), _stone_material)

func _build_ground_openings(features: Dictionary) -> void:
    for raw: Variant in features.get("ground_arcades", []):
        if typeof(raw) != TYPE_DICTIONARY:
            continue
        var opening := raw as Dictionary
        var x0 := _px_x(float(opening.get("left_px", 0.0)), features)
        var x1 := _px_x(float(opening.get("right_px", 0.0)), features)
        var y_top := _px_y(float(opening.get("arch_top_y_px", 0.0)), features)
        var y_bottom := _px_y(float(opening.get("bottom_px", 0.0)), features)
        var width := maxf(x1 - x0, 0.2)
        var height := maxf(y_top - y_bottom, 0.2)
        _add_box("GroundOpening_%s" % str(opening.get("id", "opening")), Vector3((x0 + x1) * 0.5, y_bottom + height * 0.5, 0.08), Vector3(width, height, 0.05), _dark_material)
        _add_box("GroundOpeningHeader_%s" % str(opening.get("id", "opening")), Vector3((x0 + x1) * 0.5, y_top + 0.12, 0.14), Vector3(width + 0.20, 0.24, 0.15), _stone_material)

func _build_crowning(features: Dictionary) -> void:
    var mapping: Dictionary = features.get("mapping", {})
    var center_x := _px_x(1375.0, features)
    var apex_y := float(mapping.get("official_wall_height_m", 24.746))
    var pediment_base_y := _px_y(2325.0, features)
    var pediment_h := maxf(apex_y - pediment_base_y, 0.6)
    _add_box("CrowningCentralBody", Vector3(center_x, pediment_base_y + pediment_h * 0.36, 0.16), Vector3(source_facade_span_m * 0.42, pediment_h * 0.72, 0.24), _stone_material)
    _add_box("CrowningAxis", Vector3(center_x, apex_y - 0.65, 0.22), Vector3(0.72, 1.30, 0.30), _gold_material)

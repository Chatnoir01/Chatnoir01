extends Node3D

const PLAN_PATH := "res://data/qa/grand_place_brasseurs_photo_plan.json"
const FEATURES_PATH := "res://data/qa/grand_place_brasseurs_photo_features.json"
const VERTICAL_PATH := "res://data/qa/grand_place_brasseurs_wall_vertical.json"

const BUILDING_ID := "https://databrussels.be/id/building/1639974"
const WALL_ID := "https://databrussels.be/id/buildingface/10945501"
const SOURCE_SHA256 := "fff8d81aaca8b3dd82247ef8d171bdb61cb1e294d530185a16566298569ed322"
const EXPECTED_SPAN_M := 8.7490357183
const EXPECTED_COLUMN_OFFSETS := [0.6872, 2.8278, 5.2337, 7.6396]
const WALL_OFFSET_M := 0.055
const RELIEF_DEPTH_M := 0.10
const SURROUND_WIDTH_M := 0.11
const ARCH_SEGMENTS := 18

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

var _features: Dictionary = {}
var _feature_root: Node3D
var _stone: StandardMaterial3D
var _recess: StandardMaterial3D

func _ready() -> void:
    call_deferred("_build")

func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        push_error("Brasseurs facade missing source input: %s" % path)
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not (parsed is Dictionary):
        push_error("Brasseurs facade invalid JSON: %s" % path)
        return {}
    return parsed as Dictionary

func _build() -> void:
    var plan := _read_json(PLAN_PATH)
    _features = _read_json(FEATURES_PATH)
    var vertical := _read_json(VERTICAL_PATH)
    if plan.is_empty() or _features.is_empty() or vertical.is_empty():
        return
    if not _validate_sources(plan, _features, vertical):
        return

    column_offsets_m = (plan.get("derived_horizontal_world_constraints", {}).get("column_center_offsets_from_left_m", []) as Array).duplicate()
    _make_materials()
    _feature_root = Node3D.new()
    _feature_root.name = "BrasseursPhotoConstrainedFacadeRelief"
    add_child(_feature_root)

    var verts: Array = vertical.get("unique_world_vertices", [])
    var left := _vec3(verts[0])
    var right := _vec3(verts[3])
    if not left.is_finite() or not right.is_finite():
        push_error("Brasseurs facade official wall vertices invalid")
        return
    var axis := Vector3(right.x - left.x, 0.0, right.z - left.z).normalized()
    if not axis.is_finite() or axis.length_squared() < 0.99:
        push_error("Brasseurs facade official wall axis invalid")
        return
    var outward := Vector3(-axis.z, 0.0, axis.x)
    var player_reference := Vector3(319.01, 1.72, -535.20)
    if outward.dot(player_reference - left) < 0.0:
        outward = -outward
    _feature_root.global_transform = Transform3D(Basis(axis, Vector3.UP, outward), left + outward * WALL_OFFSET_M)

    _build_major_bands()
    _build_colossal_order()
    _build_principal_windows()
    _build_ground_arcades()

    set_meta("building_id", BUILDING_ID)
    set_meta("source_wall_id", WALL_ID)
    set_meta("source_facade_span_m", EXPECTED_SPAN_M)
    set_meta("photo_source_sha256", SOURCE_SHA256)
    set_meta("vertical_world_scale_source", "official_lod2_wall")
    set_meta("vertical_mapping", "piecewise_official_anchors")
    set_meta("raw_photo_pixels_shipped", false)
    set_meta("geometry_claimed_surveyed", false)
    set_meta("relief_depth_source", "bounded_visualization_convention_not_survey")
    set_meta("surround_width_source", "bounded_visualization_convention_not_survey")
    set_meta("decorative_microdetail_encoded", false)
    set_meta("runtime_approved", false)
    set_meta("realism_complete", false)
    facade_ready = feature_count >= 45
    if facade_ready:
        print("GRAND_PLACE_BRASSEURS_PHOTO_FACADE_READY: wall=10945501 bays=3 details=%d curved_arcades=true photo_pixels=false surveyed=false" % feature_count)
    else:
        push_error("Brasseurs facade built insufficient source-constrained features: %d" % feature_count)

func _validate_sources(plan: Dictionary, features: Dictionary, vertical: Dictionary) -> bool:
    var placement: Dictionary = plan.get("placement", {})
    var source: Dictionary = plan.get("source", {})
    var derived: Dictionary = plan.get("derived_horizontal_world_constraints", {})
    var mapping: Dictionary = features.get("mapping", {})
    var feature_source: Dictionary = features.get("source", {})
    if str(placement.get("building_id", "")) != "1639974" or str(placement.get("front_wall_id", "")) != "10945501":
        push_error("Brasseurs facade plan identity drift")
        return false
    if abs(float(placement.get("front_wall_span_m", 0.0)) - EXPECTED_SPAN_M) > 0.00001:
        push_error("Brasseurs facade official horizontal span drift")
        return false
    if str(source.get("download_sha256", "")) != SOURCE_SHA256 or str(feature_source.get("download_sha256", "")) != SOURCE_SHA256:
        push_error("Brasseurs facade photo provenance drift")
        return false
    var offsets: Array = derived.get("column_center_offsets_from_left_m", [])
    if offsets.size() != EXPECTED_COLUMN_OFFSETS.size():
        push_error("Brasseurs facade requires four constrained column axes")
        return false
    for i: int in range(EXPECTED_COLUMN_OFFSETS.size()):
        if abs(float(offsets[i]) - float(EXPECTED_COLUMN_OFFSETS[i])) > 0.001:
            push_error("Brasseurs facade column axis drift at %d" % i)
            return false
    if str(vertical.get("building_id", "")) != "1639974" or str(vertical.get("front_wall_id", "")) != "10945501":
        push_error("Brasseurs facade LoD2 identity drift")
        return false
    if str(vertical.get("vertical_world_scale_source", "")) != "official_lod2_wall":
        push_error("Brasseurs facade requires independent official LoD2 vertical source")
        return false
    if abs(float(vertical.get("wall_vertical_extent_m", 0.0)) - 24.746) > 0.001:
        push_error("Brasseurs facade LoD2 vertical extent drift")
        return false
    if str(mapping.get("vertical_world_source", "")) != "official_lod2_wall_piecewise_anchors":
        push_error("Brasseurs facade piecewise vertical source drift")
        return false
    if str(mapping.get("vertical_mapping", "")) != "piecewise_ground_to_shoulder_then_shoulder_to_apex":
        push_error("Brasseurs facade piecewise mapping drift")
        return false
    if bool(mapping.get("raw_photo_pixels_shipped", true)) or bool(mapping.get("photo_geometry_claimed_surveyed", true)):
        push_error("Brasseurs facade source/presentation boundary violated")
        return false
    var uncertainty: Dictionary = features.get("uncertainty", {})
    if not bool(uncertainty.get("decorative_microdetail_not_encoded", false)):
        push_error("Brasseurs facade must keep decorative microdetail explicitly unresolved")
        return false
    return true

func _vec3(raw: Variant) -> Vector3:
    if not (raw is Array) or (raw as Array).size() != 3:
        return Vector3.INF
    var a := raw as Array
    return Vector3(float(a[0]), float(a[1]), float(a[2]))

func _make_materials() -> void:
    _stone = StandardMaterial3D.new()
    _stone.albedo_color = Color(0.80, 0.73, 0.59, 1.0)
    _stone.roughness = 0.82
    _recess = StandardMaterial3D.new()
    _recess.albedo_color = Color(0.050, 0.052, 0.048, 1.0)
    _recess.roughness = 0.46

func _mapping() -> Dictionary:
    return _features.get("mapping", {}) as Dictionary

func _x(px: float) -> float:
    var mapping := _mapping()
    var left_px := float(mapping.get("facade_left_px", 590.0))
    var right_px := float(mapping.get("facade_right_px", 2245.0))
    return clampf((px - left_px) / maxf(right_px - left_px, 1.0), 0.0, 1.0) * EXPECTED_SPAN_M

func _y(py: float) -> float:
    var mapping := _mapping()
    var ground := float(mapping.get("facade_ground_y_px", 5360.0))
    var shoulder_px := float(mapping.get("official_wall_shoulder_photo_y_px", 2395.0))
    var apex_px := float(mapping.get("official_wall_apex_photo_y_px", 1775.0))
    var shoulder_y := float(mapping.get("official_wall_shoulder_reference_y_m", 19.066))
    var apex_y := float(mapping.get("official_wall_apex_y_m", 24.746))
    if py >= shoulder_px:
        return clampf((ground - py) / maxf(ground - shoulder_px, 1.0), 0.0, 1.0) * shoulder_y
    return shoulder_y + clampf((shoulder_px - py) / maxf(shoulder_px - apex_px, 1.0), 0.0, 1.0) * (apex_y - shoulder_y)

func _add_box(name_value: String, x0: float, x1: float, y0: float, y1: float, z: float, depth: float, material: Material) -> void:
    var node := MeshInstance3D.new()
    node.name = name_value
    var mesh := BoxMesh.new()
    mesh.size = Vector3(maxf(x1 - x0, 0.025), maxf(y1 - y0, 0.025), maxf(depth, 0.02))
    mesh.material = material
    node.mesh = mesh
    node.position = Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, z)
    _feature_root.add_child(node)
    feature_count += 1

func _build_major_bands() -> void:
    for raw: Variant in _features.get("major_bands", []):
        if not (raw is Dictionary):
            continue
        var band := raw as Dictionary
        var y := _y(float(band.get("y_px", 0.0)))
        _add_box("Band_%s" % str(band.get("id", "band")), 0.0, EXPECTED_SPAN_M, y - 0.09, y + 0.09, RELIEF_DEPTH_M * 0.65, 0.12, _stone)

func _build_colossal_order() -> void:
    var order: Dictionary = _features.get("colossal_order", {})
    var shaft_bottom := _y(float(order.get("shaft_bottom_y_px", 3920.0)))
    var shaft_top := _y(float(order.get("shaft_top_y_px", 2590.0)))
    var base_bottom := _y(float(order.get("base_bottom_y_px", 4070.0)))
    var base_top := _y(float(order.get("base_top_y_px", 3890.0)))
    var capital_bottom := _y(float(order.get("capital_bottom_y_px", 2635.0)))
    var capital_top := _y(float(order.get("capital_top_y_px", 2440.0)))
    for i: int in range(column_offsets_m.size()):
        var x := float(column_offsets_m[i])
        var shaft := MeshInstance3D.new()
        shaft.name = "ColumnShaft_%d" % i
        var cylinder := CylinderMesh.new()
        cylinder.top_radius = 0.17
        cylinder.bottom_radius = 0.21
        cylinder.height = maxf(shaft_top - shaft_bottom, 0.2)
        cylinder.radial_segments = 20
        cylinder.rings = 4
        cylinder.material = _stone
        shaft.mesh = cylinder
        shaft.position = Vector3(x, (shaft_top + shaft_bottom) * 0.5, RELIEF_DEPTH_M * 1.25)
        _feature_root.add_child(shaft)
        feature_count += 1
        _add_box("ColumnBase_%d" % i, x - 0.28, x + 0.28, base_bottom, base_top, RELIEF_DEPTH_M * 1.15, 0.18, _stone)
        _add_box("ColumnCapital_%d" % i, x - 0.32, x + 0.32, capital_bottom, capital_top, RELIEF_DEPTH_M * 1.15, 0.18, _stone)

func _build_principal_windows() -> void:
    for raw: Variant in _features.get("principal_windows", []):
        if not (raw is Dictionary):
            continue
        var window := raw as Dictionary
        var x0 := _x(float(window.get("left_px", 0.0)))
        var x1 := _x(float(window.get("right_px", 0.0)))
        var bottom := _y(float(window.get("bottom_px", 0.0)))
        var top := _y(float(window.get("top_px", 0.0)))
        var id := str(window.get("id", "window"))
        _add_box("WindowRecess_%s" % id, x0, x1, bottom, top, RELIEF_DEPTH_M * 0.20, 0.035, _recess)
        _add_box("WindowLeft_%s" % id, x0 - SURROUND_WIDTH_M, x0, bottom, top + SURROUND_WIDTH_M, RELIEF_DEPTH_M, 0.10, _stone)
        _add_box("WindowRight_%s" % id, x1, x1 + SURROUND_WIDTH_M, bottom, top + SURROUND_WIDTH_M, RELIEF_DEPTH_M, 0.10, _stone)
        _add_box("WindowSill_%s" % id, x0 - SURROUND_WIDTH_M, x1 + SURROUND_WIDTH_M, bottom - SURROUND_WIDTH_M * 0.55, bottom, RELIEF_DEPTH_M, 0.10, _stone)
        _add_box("WindowHead_%s" % id, x0 - SURROUND_WIDTH_M, x1 + SURROUND_WIDTH_M, top, top + SURROUND_WIDTH_M, RELIEF_DEPTH_M, 0.10, _stone)

func _build_ground_arcades() -> void:
    for raw: Variant in _features.get("ground_arcades", []):
        if not (raw is Dictionary):
            continue
        var arcade := raw as Dictionary
        var x0 := _x(float(arcade.get("left_px", 0.0)))
        var x1 := _x(float(arcade.get("right_px", 0.0)))
        var bottom := _y(float(arcade.get("bottom_px", 0.0)))
        var spring := _y(float(arcade.get("spring_y_px", 0.0)))
        var apex := _y(float(arcade.get("arch_top_y_px", 0.0)))
        var id := str(arcade.get("id", "arcade"))
        _add_arch_fill("ArcadeRecess_%s" % id, x0, x1, bottom, spring, apex)
        _add_arch_ring("ArcadeArch_%s" % id, x0, x1, spring, apex)
        _add_box("ArcadeLeftJamb_%s" % id, x0 - SURROUND_WIDTH_M, x0, bottom, spring, RELIEF_DEPTH_M, 0.11, _stone)
        _add_box("ArcadeRightJamb_%s" % id, x1, x1 + SURROUND_WIDTH_M, bottom, spring, RELIEF_DEPTH_M, 0.11, _stone)

func _add_arch_fill(name_value: String, x0: float, x1: float, bottom: float, spring: float, apex: float) -> void:
    var cx := (x0 + x1) * 0.5
    var half_width := maxf((x1 - x0) * 0.5, 0.05)
    var rise := maxf(apex - spring, 0.05)
    var polygon := PackedVector2Array()
    polygon.append(Vector2(x0, bottom))
    polygon.append(Vector2(x1, bottom))
    polygon.append(Vector2(x1, spring))
    for i: int in range(ARCH_SEGMENTS + 1):
        var theta := float(i) / float(ARCH_SEGMENTS) * PI
        polygon.append(Vector2(cx + half_width * cos(theta), spring + rise * sin(theta)))
    polygon.append(Vector2(x0, spring))
    var indices := Geometry2D.triangulate_polygon(polygon)
    if indices.is_empty():
        push_error("Brasseurs facade failed to triangulate %s" % name_value)
        return
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    for idx: int in indices:
        var p := polygon[idx]
        surface.set_normal(Vector3(0.0, 0.0, 1.0))
        surface.add_vertex(Vector3(p.x, p.y, RELIEF_DEPTH_M * 0.18))
    var mesh := surface.commit()
    var node := MeshInstance3D.new()
    node.name = name_value
    node.mesh = mesh
    node.material_override = _recess
    _feature_root.add_child(node)
    feature_count += 1

func _add_arch_ring(name_value: String, x0: float, x1: float, spring: float, apex: float) -> void:
    var cx := (x0 + x1) * 0.5
    var inner_half := maxf((x1 - x0) * 0.5, 0.05)
    var inner_rise := maxf(apex - spring, 0.05)
    var outer_half := inner_half + SURROUND_WIDTH_M
    var outer_rise := inner_rise + SURROUND_WIDTH_M
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    for i: int in range(ARCH_SEGMENTS):
        var t0 := float(i) / float(ARCH_SEGMENTS) * PI
        var t1 := float(i + 1) / float(ARCH_SEGMENTS) * PI
        var i0 := Vector3(cx + inner_half * cos(t0), spring + inner_rise * sin(t0), RELIEF_DEPTH_M)
        var i1 := Vector3(cx + inner_half * cos(t1), spring + inner_rise * sin(t1), RELIEF_DEPTH_M)
        var o0 := Vector3(cx + outer_half * cos(t0), spring + outer_rise * sin(t0), RELIEF_DEPTH_M)
        var o1 := Vector3(cx + outer_half * cos(t1), spring + outer_rise * sin(t1), RELIEF_DEPTH_M)
        surface.set_normal(Vector3(0.0, 0.0, 1.0)); surface.add_vertex(i0)
        surface.set_normal(Vector3(0.0, 0.0, 1.0)); surface.add_vertex(o0)
        surface.set_normal(Vector3(0.0, 0.0, 1.0)); surface.add_vertex(o1)
        surface.set_normal(Vector3(0.0, 0.0, 1.0)); surface.add_vertex(i0)
        surface.set_normal(Vector3(0.0, 0.0, 1.0)); surface.add_vertex(o1)
        surface.set_normal(Vector3(0.0, 0.0, 1.0)); surface.add_vertex(i1)
    var mesh := surface.commit()
    var node := MeshInstance3D.new()
    node.name = name_value
    node.mesh = mesh
    node.material_override = _stone
    _feature_root.add_child(node)
    feature_count += 1

func set_facade_visible(enabled: bool) -> void:
    visible = enabled

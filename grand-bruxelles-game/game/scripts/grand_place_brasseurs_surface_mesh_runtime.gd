extends Node3D

const PLAN_PATH := "res://data/qa/grand_place_brasseurs_photo_plan.json"
const FEATURES_PATH := "res://data/qa/grand_place_brasseurs_photo_features.json"
const VERTICAL_PATH := "res://data/qa/grand_place_brasseurs_wall_vertical.json"
const BUILDING_ID := "https://databrussels.be/id/building/1639974"
const WALL_ID := "https://databrussels.be/id/buildingface/10945501"
const SOURCE_SHA256 := "fff8d81aaca8b3dd82247ef8d171bdb61cb1e294d530185a16566298569ed322"
const EXPECTED_SPAN_M := 8.7490357183
const DEPTH_M := 0.07

var facade_ready := false
var building_id := BUILDING_ID
var source_wall_id := WALL_ID
var source_facade_span_m := EXPECTED_SPAN_M
var bay_count := 3
var feature_mesh_count := 0
var raw_photo_pixels_shipped := false
var geometry_claimed_surveyed := false
var vertical_world_scale_source := "official_lod2_wall"

var _plan: Dictionary
var _features: Dictionary
var _vertical: Dictionary
var _origin := Vector3.ZERO
var _axis := Vector3.RIGHT
var _outward := Vector3.FORWARD
var _stone: StandardMaterial3D
var _dark: StandardMaterial3D
var _root: Node3D

func _ready() -> void:
    call_deferred("_build")

func _json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}

func _build() -> void:
    _plan = _json(PLAN_PATH)
    _features = _json(FEATURES_PATH)
    _vertical = _json(VERTICAL_PATH)
    if _plan.is_empty() or _features.is_empty() or _vertical.is_empty():
        return
    var placement: Dictionary = _plan.get("placement", {})
    var source: Dictionary = _plan.get("source", {})
    var mapping: Dictionary = _features.get("mapping", {})
    if str(placement.get("building_id", "")) != "1639974" or str(placement.get("front_wall_id", "")) != "10945501":
        return
    if absf(float(placement.get("front_wall_span_m", 0.0)) - EXPECTED_SPAN_M) > 0.000001:
        return
    if str(source.get("download_sha256", "")) != SOURCE_SHA256:
        return
    if str(_vertical.get("vertical_world_scale_source", "")) != "official_lod2_wall" or bool(_vertical.get("photo_used_for_vertical_scale", true)):
        return
    if str(mapping.get("vertical_world_source", "")) != "official_lod2_wall_piecewise_anchors":
        return
    if bool(mapping.get("raw_photo_pixels_shipped", true)) or bool(mapping.get("photo_geometry_claimed_surveyed", true)):
        return
    var verts: Array = _vertical.get("unique_world_vertices", [])
    if verts.size() != 5:
        return
    var left := _v3(verts[0])
    var right := _v3(verts[3])
    if not left.is_finite() or not right.is_finite():
        return
    _origin = left
    _axis = Vector3(right.x - left.x, 0.0, right.z - left.z).normalized()
    _outward = Vector3(-_axis.z, 0.0, _axis.x)
    var player_witness := Vector3(319.01, 1.72, -535.20)
    if _outward.dot(player_witness - left) < 0.0:
        _outward = -_outward
    _stone = StandardMaterial3D.new()
    _stone.albedo_color = Color(0.72, 0.66, 0.53, 1.0)
    _stone.roughness = 0.82
    _dark = StandardMaterial3D.new()
    _dark.albedo_color = Color(0.045, 0.05, 0.048, 1.0)
    _dark.roughness = 0.46
    _root = Node3D.new()
    _root.name = "BrasseursSourceBoundedSurfaceMesh"
    add_child(_root)
    _build_major_bands()
    _build_colossal_order()
    _build_principal_windows()
    _build_ground_arcades()
    set_meta("source_bounded_visualization_not_architectural_survey", true)
    set_meta("building_id", BUILDING_ID)
    set_meta("source_wall_id", WALL_ID)
    set_meta("photo_source_sha256", SOURCE_SHA256)
    set_meta("raw_photo_pixels_shipped", false)
    set_meta("geometry_claimed_surveyed", false)
    set_meta("vertical_world_scale_source", "official_lod2_wall")
    set_meta("decorative_microdetail_resolved", false)
    set_meta("depth_source", "bounded_visualization_convention_not_survey")
    set_meta("runtime_approved", false)
    set_meta("realism_complete", false)
    facade_ready = feature_mesh_count >= 20
    print("GRAND_PLACE_BRASSEURS_SURFACE_MESH_READY: features=%d span=%.6f primitive_family=false" % [feature_mesh_count, EXPECTED_SPAN_M])

func _v3(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return Vector3.INF
    return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))

func _x(px: float) -> float:
    var m: Dictionary = _features.get("mapping", {})
    var left := float(m.get("facade_left_px", 0.0))
    var right := float(m.get("facade_right_px", 1.0))
    return clampf((px - left) / maxf(right - left, 1.0), 0.0, 1.0) * EXPECTED_SPAN_M

func _y(py: float) -> float:
    var m: Dictionary = _features.get("mapping", {})
    var ground := float(m.get("facade_ground_y_px", 5360.0))
    var shoulder_px := float(m.get("official_wall_shoulder_photo_y_px", 2395.0))
    var apex_px := float(m.get("official_wall_apex_photo_y_px", 1775.0))
    var shoulder_y := float(m.get("official_wall_shoulder_reference_y_m", 19.066))
    var apex_y := float(m.get("official_wall_apex_y_m", 24.746))
    if py >= shoulder_px:
        return clampf((ground - py) / maxf(ground - shoulder_px, 1.0), 0.0, 1.0) * shoulder_y
    return shoulder_y + clampf((shoulder_px - py) / maxf(shoulder_px - apex_px, 1.0), 0.0, 1.0) * (apex_y - shoulder_y)

func _world(x: float, y: float, z: float) -> Vector3:
    return _origin + _axis * x + Vector3.UP * y + _outward * z

func _emit_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
    var n := (b - a).cross(c - a).normalized()
    if n.dot(_outward) < 0.0:
        var swap := b
        b = c
        c = swap
        n = -n
    for p: Vector3 in [a, b, c]:
        st.set_normal(n)
        st.add_vertex(p)

func _surface(name_value: String, material: Material, build_fn: Callable) -> void:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    st.set_material(material)
    build_fn.call(st)
    var mesh := st.commit()
    if mesh == null or mesh.get_surface_count() == 0:
        return
    var instance := MeshInstance3D.new()
    instance.name = name_value
    instance.mesh = mesh
    _root.add_child(instance)
    feature_mesh_count += 1

func _rect(name_value: String, x0: float, x1: float, y0: float, y1: float, z: float, material: Material) -> void:
    _surface(name_value, material, func(st: SurfaceTool) -> void:
        var a := _world(x0, y0, z)
        var b := _world(x1, y0, z)
        var c := _world(x1, y1, z)
        var d := _world(x0, y1, z)
        _emit_tri(st, a, b, c)
        _emit_tri(st, a, c, d)
    )

func _arched_panel(name_value: String, x0: float, x1: float, y0: float, spring_y: float, top_y: float, z: float, material: Material) -> void:
    _surface(name_value, material, func(st: SurfaceTool) -> void:
        var mid := (x0 + x1) * 0.5
        var radius_x := (x1 - x0) * 0.5
        var cap_h := maxf(top_y - spring_y, 0.08)
        var base_left := _world(x0, y0, z)
        var base_right := _world(x1, y0, z)
        var spring_right := _world(x1, spring_y, z)
        var spring_left := _world(x0, spring_y, z)
        _emit_tri(st, base_left, base_right, spring_right)
        _emit_tri(st, base_left, spring_right, spring_left)
        var center := _world(mid, spring_y, z)
        var previous := spring_right
        var segments := 14
        for i: int in range(1, segments + 1):
            var angle := PI * float(i) / float(segments)
            var x := mid + cos(angle) * radius_x
            var y := spring_y + sin(angle) * cap_h
            var current := _world(x, y, z)
            _emit_tri(st, center, previous, current)
            previous = current
    )

func _build_major_bands() -> void:
    for raw: Variant in _features.get("major_bands", []):
        if typeof(raw) != TYPE_DICTIONARY:
            continue
        var band := raw as Dictionary
        var y := _y(float(band.get("y_px", 0.0)))
        _rect("Band_%s" % str(band.get("id", "band")), 0.0, EXPECTED_SPAN_M, y - 0.09, y + 0.09, DEPTH_M + 0.015, _stone)

func _build_colossal_order() -> void:
    var order: Dictionary = _features.get("colossal_order", {})
    var centers: Array = order.get("column_center_x_px", [])
    var shaft_bottom := _y(float(order.get("shaft_bottom_y_px", 3920.0)))
    var shaft_top := _y(float(order.get("shaft_top_y_px", 2590.0)))
    var base_bottom := _y(float(order.get("base_bottom_y_px", 4070.0)))
    var base_top := _y(float(order.get("base_top_y_px", 3890.0)))
    var capital_bottom := _y(float(order.get("capital_bottom_y_px", 2635.0)))
    var capital_top := _y(float(order.get("capital_top_y_px", 2440.0)))
    for i: int in range(centers.size()):
        var x := _x(float(centers[i]))
        var shaft_half := 0.115
        _rect("Pilaster_%02d" % i, x - shaft_half, x + shaft_half, shaft_bottom, shaft_top, DEPTH_M + 0.035, _stone)
        _rect("PilasterBase_%02d" % i, x - 0.22, x + 0.22, base_bottom, base_top, DEPTH_M + 0.045, _stone)
        _rect("PilasterCapital_%02d" % i, x - 0.25, x + 0.25, capital_bottom, capital_top, DEPTH_M + 0.045, _stone)

func _build_principal_windows() -> void:
    for raw: Variant in _features.get("principal_windows", []):
        if typeof(raw) != TYPE_DICTIONARY:
            continue
        var w := raw as Dictionary
        var x0 := _x(float(w.get("left_px", 0.0)))
        var x1 := _x(float(w.get("right_px", 0.0)))
        var y0 := _y(float(w.get("bottom_px", 0.0)))
        var y1 := _y(float(w.get("top_px", 0.0)))
        _rect("Window_%s" % str(w.get("id", "window")), x0, x1, y0, y1, DEPTH_M + 0.01, _dark)
        _rect("WindowLintel_%s" % str(w.get("id", "window")), x0 - 0.06, x1 + 0.06, y1, y1 + 0.13, DEPTH_M + 0.03, _stone)

func _build_ground_arcades() -> void:
    for raw: Variant in _features.get("ground_arcades", []):
        if typeof(raw) != TYPE_DICTIONARY:
            continue
        var arcade := raw as Dictionary
        var x0 := _x(float(arcade.get("left_px", 0.0)))
        var x1 := _x(float(arcade.get("right_px", 0.0)))
        var y0 := _y(float(arcade.get("bottom_px", 0.0)))
        var spring := _y(float(arcade.get("spring_y_px", 0.0)))
        var top := _y(float(arcade.get("arch_top_y_px", 0.0)))
        _arched_panel("Arcade_%s" % str(arcade.get("id", "arcade")), x0, x1, y0, spring, top, DEPTH_M + 0.012, _dark)

func set_facade_visible(enabled: bool) -> void:
    visible = enabled

func facade_visible() -> bool:
    return visible

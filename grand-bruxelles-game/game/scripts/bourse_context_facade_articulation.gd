extends Node3D
class_name BourseContextFacadeArticulation

const ANCHOR := Vector2(81.54, -664.58)
const RADIUS := 145.0
const MAX_TRIMS := 320
var _buildings := 0
var _cornices: Array[Transform3D] = []
var _plinths: Array[Transform3D] = []
var _pilasters: Array[Transform3D] = []

func _ready() -> void: call_deferred("_build")

func _build() -> void:
    var city := get_parent().get_node_or_null("BrusselsOSM")
    if city == null: push_error("Bourse context facade: BrusselsOSM missing"); return
    var generated := city.get_node_or_null("GeneratedBuildings")
    if generated == null: await get_tree().process_frame; generated = city.get_node_or_null("GeneratedBuildings")
    if generated == null: push_error("Bourse context facade: GeneratedBuildings missing"); return
    var path := str(city.get("data_path"))
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
    if typeof(parsed) != TYPE_DICTIONARY: push_error("Bourse context facade: invalid source"); return

    var source_buildings: Array = (parsed as Dictionary).get("buildings", [])
    var replacements: Dictionary = city.call("_validated_hero_replacements") as Dictionary if city.has_method("_validated_hero_replacements") else {}
    var selected := _builder_selected_ids(source_buildings, replacements, int(city.get("max_buildings")))
    var near_count := 0
    for raw: Variant in source_buildings:
        if not raw is Dictionary: continue
        var building := raw as Dictionary
        var osm_id := int(building.get("osm_id", 0))
        var footprint: Array = building.get("footprint", [])
        if not selected.has(osm_id) or footprint.size() < 3 or not _near(footprint): continue
        near_count += 1
        var height := clampf(float(building.get("height", 10.5)), 2.8, 120.0)
        if height < 8.0: continue
        _queue(footprint, height); _buildings += 1
    _layer("ContextCornices", _cornices, Color(0.61, 0.56, 0.48, 1.0))
    _layer("ContextPlinths", _plinths, Color(0.40, 0.385, 0.35, 1.0))
    _layer("ContextCornerPilasters", _pilasters, Color(0.56, 0.515, 0.44, 1.0))
    print("BOURSE_CONTEXT_FACADE_READY: builder_selected=%d near=%d buildings=%d trims=%d source_geometry_unchanged=true collision=false duplicate_window_trim=false" % [selected.size(), near_count, _buildings, diagnostic_trim_count()])

func _builder_selected_ids(buildings: Array, replacements: Dictionary, limit: int) -> Dictionary:
    var selected := {}; var count := 0
    for raw: Variant in buildings:
        if count >= limit: break
        if not raw is Dictionary: continue
        var building := raw as Dictionary
        var osm_id := int(building.get("osm_id", 0)); var footprint: Array = building.get("footprint", [])
        if replacements.has(osm_id) or footprint.size() < 3: continue
        selected[osm_id] = true; count += 1
    return selected

func _center(points: Array) -> Vector2:
    var value := Vector2.ZERO
    for raw: Variant in points: value += Vector2(float(raw[0]), float(raw[1]))
    return value / float(points.size())

func _segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
    var edge := b-a; var length2 := edge.length_squared()
    return point.distance_to(a) if length2 <= 0.000001 else point.distance_to(a + edge * clampf((point-a).dot(edge)/length2, 0.0, 1.0))

func _near(points: Array) -> bool:
    for raw: Variant in points:
        if Vector2(float(raw[0]), float(raw[1])).distance_to(ANCHOR) <= RADIUS: return true
    for i: int in range(points.size()):
        var ra: Variant = points[i]; var rb: Variant = points[(i+1)%points.size()]
        if _segment_distance(ANCHOR, Vector2(float(ra[0]), float(ra[1])), Vector2(float(rb[0]), float(rb[1]))) <= RADIUS: return true
    return false

func _queue(points: Array, height: float) -> void:
    var center := _center(points)
    for i: int in range(points.size()):
        if diagnostic_trim_count() >= MAX_TRIMS: return
        var ra: Variant = points[i]; var rb: Variant = points[(i+1)%points.size()]
        var a := Vector2(float(ra[0]), float(ra[1])); var b := Vector2(float(rb[0]), float(rb[1])); var edge := b-a; var length := edge.length()
        if length < 5.0: continue
        var direction := edge/length; var midpoint := (a+b)*0.5; var offset := (midpoint-center).normalized()*0.10; var angle := atan2(-direction.y, direction.x)
        var horizontal_basis := Basis(Vector3.UP, angle)
        _cornices.append(Transform3D(horizontal_basis.scaled(Vector3(length*0.94, 0.22, 0.24)), Vector3(midpoint.x+offset.x, height-0.24, midpoint.y+offset.y)))
        _plinths.append(Transform3D(horizontal_basis.scaled(Vector3(length*0.94, 0.86, 0.20)), Vector3(midpoint.x+offset.x, 0.48, midpoint.y+offset.y)))
        var pilaster_height := maxf(height-1.0, 4.0)
        _pilasters.append(Transform3D(horizontal_basis.scaled(Vector3(0.38, pilaster_height, 0.22)), Vector3(a.x+offset.x, height*0.5-0.10, a.y+offset.y)))

func _layer(name: String, transforms: Array[Transform3D], color: Color) -> void:
    if transforms.is_empty(): return
    var material := StandardMaterial3D.new(); material.albedo_color = color; material.roughness = 0.91
    var mesh := BoxMesh.new(); mesh.size = Vector3.ONE; mesh.material = material
    var multimesh := MultiMesh.new(); multimesh.transform_format = MultiMesh.TRANSFORM_3D; multimesh.mesh = mesh; multimesh.instance_count = transforms.size()
    for i: int in range(transforms.size()): multimesh.set_instance_transform(i, transforms[i])
    var instance := MultiMeshInstance3D.new(); instance.name = name; instance.multimesh = multimesh; instance.set_meta("presentation_only", true); instance.set_meta("source_geometry_unchanged", true); add_child(instance)

func set_articulation_enabled(enabled: bool) -> void: visible = enabled
func diagnostic_building_count() -> int: return _buildings
func diagnostic_trim_count() -> int: return _cornices.size() + _plinths.size() + _pilasters.size()

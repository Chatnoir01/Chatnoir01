extends Node3D
class_name BourseContextFacadeArticulation

const ANCHOR := Vector2(81.54, -664.58)
const RADIUS := 145.0
const MAX_CORNICES := 260
const MAX_BANDS := 1800
var _buildings := 0
var _cornices: Array[Transform3D] = []
var _lintels: Array[Transform3D] = []
var _sills: Array[Transform3D] = []

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

    var rendered := {}
    for child: Node in generated.get_children():
        if child.name.begins_with("Building_"):
            var raw := child.name.trim_prefix("Building_")
            if raw.is_valid_int(): rendered[int(raw)] = true
    var replacements: Dictionary = city.call("_validated_hero_replacements") as Dictionary if city.has_method("_validated_hero_replacements") else {}
    for raw: Variant in (parsed as Dictionary).get("buildings", []):
        if not raw is Dictionary: continue
        var building := raw as Dictionary
        var osm_id := int(building.get("osm_id", 0))
        var footprint: Array = building.get("footprint", [])
        var height := clampf(float(building.get("height", 10.5)), 2.8, 120.0)
        if not rendered.has(osm_id) or replacements.has(osm_id) or footprint.size() < 3 or height < 8.0 or not _near(footprint): continue
        _queue(footprint, height); _buildings += 1
    _layer("ContextCornices", _cornices, Color(0.60, 0.555, 0.48, 1.0))
    _layer("ContextLintels", _lintels, Color(0.60, 0.555, 0.48, 1.0))
    _layer("ContextSills", _sills, Color(0.46, 0.44, 0.40, 1.0))
    print("BOURSE_CONTEXT_FACADE_READY: buildings=%d trims=%d source_geometry_unchanged=true collision=false" % [_buildings, diagnostic_trim_count()])

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
    var center := _center(points); var floors := clampi(int(floor(height/3.15))-1, 1, 6)
    for i: int in range(points.size()):
        var ra: Variant = points[i]; var rb: Variant = points[(i+1)%points.size()]
        var a := Vector2(float(ra[0]), float(ra[1])); var b := Vector2(float(rb[0]), float(rb[1])); var edge := b-a; var length := edge.length()
        if length < 5.0: continue
        var direction := edge/length; var midpoint := (a+b)*0.5; var offset := (midpoint-center).normalized()*0.11; var angle := atan2(-direction.y, direction.x)
        if _cornices.size() < MAX_CORNICES:
            _cornices.append(Transform3D(Basis(Vector3.UP, angle).scaled(Vector3(length*0.92, 0.16, 0.22)), Vector3(midpoint.x+offset.x, height-0.28, midpoint.y+offset.y)))
        var modules := clampi(int(length/3.4), 1, 14); var step := length/float(modules+1); var width := clampf(step*0.58, 1.0, 1.8)
        for module: int in range(modules):
            if _lintels.size() >= MAX_BANDS: return
            var point := a + direction*(step*float(module+1)) + offset
            for floor_index: int in range(floors):
                var y := 4.35 + float(floor_index)*3.05
                if y+0.85 >= height: break
                var basis := Basis(Vector3.UP, angle).scaled(Vector3(width, 0.10, 0.16))
                _lintels.append(Transform3D(basis, Vector3(point.x, y+0.78, point.y))); _sills.append(Transform3D(basis, Vector3(point.x, y-0.78, point.y)))

func _layer(name: String, transforms: Array[Transform3D], color: Color) -> void:
    if transforms.is_empty(): return
    var material := StandardMaterial3D.new(); material.albedo_color = color; material.roughness = 0.91
    var mesh := BoxMesh.new(); mesh.size = Vector3.ONE; mesh.material = material
    var multimesh := MultiMesh.new(); multimesh.transform_format = MultiMesh.TRANSFORM_3D; multimesh.mesh = mesh; multimesh.instance_count = transforms.size()
    for i: int in range(transforms.size()): multimesh.set_instance_transform(i, transforms[i])
    var instance := MultiMeshInstance3D.new(); instance.name = name; instance.multimesh = multimesh; instance.set_meta("presentation_only", true); instance.set_meta("source_geometry_unchanged", true); add_child(instance)

func set_articulation_enabled(enabled: bool) -> void: visible = enabled
func diagnostic_building_count() -> int: return _buildings
func diagnostic_trim_count() -> int: return _cornices.size() + _lintels.size() + _sills.size()

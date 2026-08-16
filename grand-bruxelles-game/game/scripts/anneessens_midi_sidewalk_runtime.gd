extends Node

const ANNEESSENS := Vector2(-272.04, -217.07)
const DETAIL_RADIUS_M := 150.0
const SIDEWALK_NARROW_M := 1.85
const SIDEWALK_WIDE_M := 2.55
const SIDEWALK_HEIGHT_M := 0.12
const SIDEWALK_GAP_M := 0.10

var _scene: Node3D = null
var _root: Node3D = null
var _sidewalk_count := 0
var _collision_count := 0

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    call_deferred("_try_bind_current_scene")

func _try_bind_current_scene() -> void:
    var current := get_tree().current_scene
    if current is Node3D:
        bind_scene(current as Node3D)

func bind_scene(scene: Node3D) -> void:
    if scene == null:
        return
    if is_instance_valid(_root):
        _root.queue_free()
    _scene = scene
    _sidewalk_count = 0
    _collision_count = 0
    _root = Node3D.new()
    _root.name = "AnneessensMidiSidewalkKit"
    _root.set_meta("zone", "anneessens")
    _root.set_meta("source", "OpenStreetMap road geometry already committed in vertical_slice_01.game.json")
    _root.set_meta("presentation_recipe", "Midi sidewalk dimensions/material family")
    _scene.add_child(_root)
    _build_from_existing_osm_roads()

func _build_from_existing_osm_roads() -> void:
    if not is_instance_valid(_scene) or not is_instance_valid(_root):
        return
    var roads := _scene.get_node_or_null("BrusselsOSM/GeneratedRoads")
    if roads == null:
        push_warning("Anneessens Midi sidewalk kit: GeneratedRoads unavailable")
        return

    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.40, 0.385, 0.36, 1.0)
    material.roughness = 0.92

    for child: Node in roads.get_children():
        if not child is CSGBox3D or not child.name.begins_with("Road_"):
            continue
        var road := child as CSGBox3D
        var center_2d := Vector2(road.global_position.x, road.global_position.z)
        if center_2d.distance_to(ANNEESSENS) > DETAIL_RADIUS_M:
            continue
        if road.size.z < 1.0 or road.size.x < 2.0:
            continue
        _add_sidewalk_pair(road, material)

func _add_sidewalk_pair(road: CSGBox3D, material: Material) -> void:
    var width := SIDEWALK_WIDE_M if road.size.x >= 8.5 else SIDEWALK_NARROW_M
    var offset := road.size.x * 0.5 + width * 0.5 + SIDEWALK_GAP_M
    var lateral := road.global_transform.basis.x.normalized()
    if lateral.length_squared() < 0.5:
        lateral = Vector3.RIGHT

    for side: float in [-1.0, 1.0]:
        var pavement := CSGBox3D.new()
        pavement.name = "AnneessensSidewalk_%s_%s" % [road.name, "L" if side < 0.0 else "R"]
        pavement.size = Vector3(width, SIDEWALK_HEIGHT_M, road.size.z)
        pavement.material = material
        pavement.use_collision = true
        pavement.set_meta("source_road", road.name)
        pavement.set_meta("source", "OpenStreetMap road geometry")
        pavement.set_meta("recipe", "Midi")
        _root.add_child(pavement)
        pavement.global_position = road.global_position + lateral * offset * side + Vector3(0.0, 0.06, 0.0)
        pavement.global_rotation = road.global_rotation
        _sidewalk_count += 1
        _collision_count += 1

func diagnostic_sidewalk_count() -> int:
    return _sidewalk_count

func diagnostic_collision_count() -> int:
    return _collision_count

func set_sidewalks_enabled(enabled: bool) -> void:
    if is_instance_valid(_root):
        _root.visible = enabled

extends Node

const ANNEESSENS := Vector2(-272.04, -217.07)
const DETAIL_RADIUS_M := 150.0
const SIDEWALK_NARROW_M := 1.85
const SIDEWALK_WIDE_M := 2.55
const SIDEWALK_HEIGHT_M := 0.12
const SIDEWALK_GAP_M := 0.10
const SOURCE_NAME := "OpenStreetMap contributors via Overpass API"
const SOURCE_LICENSE := "ODbL-1.0"

var _scene: Node3D = null
var _root: Node3D = null
var _sidewalk_count := 0
var _collision_count := 0
var _sidewalks_enabled := true
var _manual_binding := false
var _bind_scheduled := false
var _watching_tree := false
var _tearing_down := false

func _ready() -> void:
    _tearing_down = false
    process_mode = Node.PROCESS_MODE_ALWAYS
    _start_watching()
    _schedule_bind()

func _exit_tree() -> void:
    _tearing_down = true
    _bind_scheduled = false
    _stop_watching()
    _release_owned_root()
    _scene = null
    _manual_binding = false

func _start_watching() -> void:
    if _tearing_down or not is_inside_tree() or _manual_binding or _watching_tree:
        return
    var tree := get_tree()
    if tree == null:
        return
    if not tree.node_added.is_connected(_on_node_added):
        tree.node_added.connect(_on_node_added)
    if not tree.node_removed.is_connected(_on_node_removed):
        tree.node_removed.connect(_on_node_removed)
    _watching_tree = true

func _stop_watching() -> void:
    var tree := get_tree()
    if tree != null:
        if tree.node_added.is_connected(_on_node_added):
            tree.node_added.disconnect(_on_node_added)
        if tree.node_removed.is_connected(_on_node_removed):
            tree.node_removed.disconnect(_on_node_removed)
    _watching_tree = false

func _release_owned_root() -> void:
    if is_instance_valid(_root):
        var parent := _root.get_parent()
        if parent != null:
            parent.remove_child(_root)
        _root.queue_free()
    _root = null
    _sidewalk_count = 0
    _collision_count = 0

func _reset_scene_binding() -> void:
    _release_owned_root()
    _scene = null
    _manual_binding = false

func _on_node_added(_node: Node) -> void:
    if _tearing_down or _manual_binding or is_instance_valid(_scene):
        return
    _schedule_bind()

func _on_node_removed(node: Node) -> void:
    if _tearing_down or not is_inside_tree() or _manual_binding or not is_instance_valid(_scene) or node != _scene:
        return
    _reset_scene_binding()
    _start_watching()
    _schedule_bind()

func _schedule_bind() -> void:
    if _tearing_down or not is_inside_tree() or _bind_scheduled or _manual_binding or is_instance_valid(_scene):
        return
    _bind_scheduled = true
    call_deferred("_try_bind")

func _is_production_scene(candidate: Node3D) -> bool:
    if candidate == null:
        return false
    return candidate.get_node_or_null("BrusselsOSM") != null \
        and candidate.get_node_or_null("UrbISMidiExact") != null \
        and candidate.get_node_or_null("Player") != null

func _find_production_scene() -> Node3D:
    if _tearing_down or not is_inside_tree():
        return null
    var tree := get_tree()
    if tree == null:
        return null
    var current := tree.current_scene
    if current is Node3D and _is_production_scene(current as Node3D):
        return current as Node3D
    for child: Node in tree.root.get_children():
        if not child is Node3D:
            continue
        var candidate := child as Node3D
        if _is_production_scene(candidate):
            return candidate
    return null

func _try_bind() -> void:
    _bind_scheduled = false
    if _tearing_down or not is_inside_tree() or _manual_binding or is_instance_valid(_scene):
        return
    var candidate := _find_production_scene()
    if candidate == null or _tearing_down or not is_inside_tree():
        return
    _bind_scene(candidate, false)

func bind_scene(scene: Node3D) -> void:
    _bind_scene(scene, true)

func _bind_scene(scene: Node3D, manual: bool) -> void:
    if scene == null or (_tearing_down and not manual):
        return
    if is_instance_valid(_root):
        _release_owned_root()
    _manual_binding = manual
    _scene = scene
    _sidewalk_count = 0
    _collision_count = 0
    _root = Node3D.new()
    _root.name = "AnneessensMidiSidewalkKit"
    _root.visible = _sidewalks_enabled
    _root.set_meta("zone", "anneessens")
    _root.set_meta("source", SOURCE_NAME)
    _root.set_meta("license", SOURCE_LICENSE)
    _root.set_meta("road_alignment_source_backed", true)
    _root.set_meta("sidewalk_presence_source_backed", false)
    _root.set_meta("visual_dimensions_source_backed", false)
    _root.set_meta("vertical_profile_source_backed", false)
    _root.set_meta("material_identity_source_backed", false)
    _root.set_meta("authored_proxy", true)
    _root.set_meta("presentation_recipe", "authored_midi_sidewalk_proxy_from_osm_road_alignment")
    _scene.add_child(_root)
    _build_from_existing_osm_roads()
    if manual:
        _stop_watching()
    else:
        _start_watching()

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
        pavement.use_collision = _sidewalks_enabled
        pavement.set_meta("source_road", road.name)
        pavement.set_meta("source", SOURCE_NAME)
        pavement.set_meta("license", SOURCE_LICENSE)
        pavement.set_meta("road_alignment_source_backed", true)
        pavement.set_meta("sidewalk_presence_source_backed", false)
        pavement.set_meta("visual_dimensions_source_backed", false)
        pavement.set_meta("vertical_profile_source_backed", false)
        pavement.set_meta("material_identity_source_backed", false)
        pavement.set_meta("authored_proxy", true)
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
    _sidewalks_enabled = enabled
    if not is_instance_valid(_root):
        return
    _root.visible = enabled
    for child: Node in _root.get_children():
        if child is CSGBox3D:
            var pavement := child as CSGBox3D
            pavement.use_collision = enabled

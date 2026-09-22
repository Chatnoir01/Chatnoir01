extends Node

const ANNEESSENS := Vector2(-272.04, -217.07)
const DETAIL_RADIUS_M := 150.0
const SIDEWALK_NARROW_M := 1.85
const SIDEWALK_WIDE_M := 2.55
const SIDEWALK_HEIGHT_M := 0.12
const SIDEWALK_GAP_M := 0.10
const MUTATION_POLL_SECONDS := 0.25
const PROXY_SOURCE := "authored_proxy"
const PROXY_LICENSE := "project-authored"
const ALIGNMENT_REFERENCE := "rendered GeneratedRoads nodes (unverified source identity)"
const PROXY_RECIPE := "authored_midi_sidewalk_proxy_from_unverified_rendered_road_alignment"
const PROXY_MATERIAL_REVISION := 1
const PROXY_ALBEDO := Color(0.40, 0.385, 0.36, 1.0)
const PROXY_ROUGHNESS := 0.92
const CANONICAL_PRODUCTION_SCENE := "res://game/main.tscn"

var _scene: Node3D = null
var _root: Node3D = null
var _sidewalk_count := 0
var _collision_count := 0
var _sidewalks_enabled := true
var _manual_binding := false
var _bind_scheduled := false
var _watching_tree := false
var _tearing_down := false
var _alignment_road_instance_ids: Dictionary = {}
var _alignment_road_refs: Dictionary = {}
var _alignment_road_transforms: Dictionary = {}
var _alignment_road_sizes: Dictionary = {}
var _alignment_road_names: Dictionary = {}
var _alignment_road_visibilities: Dictionary = {}
var _mutation_poll_timer: Timer = null

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

func _ensure_mutation_poll_timer() -> void:
    if is_instance_valid(_mutation_poll_timer):
        if _mutation_poll_timer.is_stopped():
            _mutation_poll_timer.start()
        return
    _mutation_poll_timer = Timer.new()
    _mutation_poll_timer.name = "RoadMutationPoll"
    _mutation_poll_timer.wait_time = MUTATION_POLL_SECONDS
    _mutation_poll_timer.one_shot = false
    _mutation_poll_timer.timeout.connect(_poll_alignment_road_mutations)
    add_child(_mutation_poll_timer)
    _mutation_poll_timer.start()

func _stop_mutation_poll_timer() -> void:
    if is_instance_valid(_mutation_poll_timer):
        _mutation_poll_timer.stop()

func _poll_alignment_road_mutations() -> void:
    if _tearing_down or _manual_binding or not is_instance_valid(_scene):
        return
    for instance_id in _alignment_road_refs.keys():
        _on_alignment_road_mutated(instance_id)
        if not is_instance_valid(_scene):
            return

func _disconnect_alignment_road_mutation_watches() -> void:
    _stop_mutation_poll_timer()
    _alignment_road_refs.clear()
    _alignment_road_transforms.clear()
    _alignment_road_sizes.clear()
    _alignment_road_names.clear()
    _alignment_road_visibilities.clear()

func _release_owned_root() -> void:
    _disconnect_alignment_road_mutation_watches()
    if is_instance_valid(_root):
        var parent := _root.get_parent()
        if parent != null and not _tearing_down:
            parent.remove_child(_root)
        _root.queue_free()
    _root = null
    _sidewalk_count = 0
    _collision_count = 0
    _alignment_road_instance_ids.clear()

func _reset_scene_binding() -> void:
    _release_owned_root()
    _scene = null
    _manual_binding = false

func _is_generated_road_child(node: Node) -> bool:
    if node == null or not node is CSGBox3D or not node.name.begins_with("Road_") or not is_instance_valid(_scene):
        return false
    var roads := _scene.get_node_or_null("BrusselsOSM/GeneratedRoads")
    return roads != null and node.get_parent() == roads

func _on_node_added(node: Node) -> void:
    if _tearing_down or _manual_binding:
        return
    if is_instance_valid(_scene):
        if not _is_generated_road_child(node):
            return
        _watch_alignment_road_mutations(node as CSGBox3D)
        _reset_scene_binding()
        _start_watching()
    _schedule_bind()

func _on_node_removed(node: Node) -> void:
    if _tearing_down or not is_inside_tree() or _manual_binding or not is_instance_valid(_scene):
        return
    var invalidates_binding := node == _scene or _alignment_road_instance_ids.has(node.get_instance_id())
    if not invalidates_binding:
        return
    _reset_scene_binding()
    _start_watching()
    _schedule_bind()

func _watch_alignment_road_mutations(road: CSGBox3D) -> void:
    if road == null:
        return
    var instance_id := road.get_instance_id()
    if _alignment_road_refs.has(instance_id):
        return
    _alignment_road_refs[instance_id] = road
    _alignment_road_transforms[instance_id] = road.global_transform
    _alignment_road_sizes[instance_id] = road.size
    _alignment_road_names[instance_id] = road.name
    _alignment_road_visibilities[instance_id] = road.visible

func _on_alignment_road_mutated(instance_id: Variant) -> void:
    if _tearing_down or _manual_binding or not is_inside_tree() or not is_instance_valid(_scene):
        return
    if not _alignment_road_refs.has(instance_id):
        return
    var road_ref: Variant = _alignment_road_refs[instance_id]
    if not is_instance_valid(road_ref):
        _reset_scene_binding()
        _start_watching()
        _schedule_bind()
        return
    var road: CSGBox3D = road_ref as CSGBox3D
    if road == null:
        _reset_scene_binding()
        _start_watching()
        _schedule_bind()
        return
    if not _is_generated_road_child(road):
        _reset_scene_binding()
        _start_watching()
        _schedule_bind()
        return
    var name_changed: bool = not _alignment_road_names.has(instance_id) or road.name != _alignment_road_names[instance_id]
    if name_changed:
        _reset_scene_binding()
        _start_watching()
        _schedule_bind()
        return
    var visibility_changed: bool = not _alignment_road_visibilities.has(instance_id) or road.visible != _alignment_road_visibilities[instance_id]
    if visibility_changed:
        _reset_scene_binding()
        _start_watching()
        _schedule_bind()
        return
    var did_transform_change: bool = not _alignment_road_transforms.has(instance_id) or road.global_transform != _alignment_road_transforms[instance_id]
    var size_changed: bool = not _alignment_road_sizes.has(instance_id) or road.size != _alignment_road_sizes[instance_id]
    if not did_transform_change and not size_changed:
        return
    _reset_scene_binding()
    _start_watching()
    _schedule_bind()

func _schedule_bind() -> void:
    if _tearing_down or not is_inside_tree() or _bind_scheduled or _manual_binding or is_instance_valid(_scene):
        return
    _bind_scheduled = true
    call_deferred("_try_bind")

func _has_production_anchors(candidate: Node3D) -> bool:
    return candidate.get_node_or_null("BrusselsOSM") != null and candidate.get_node_or_null("UrbISMidiExact") != null and candidate.get_node_or_null("Player") is Node3D

func _is_production_scene(candidate: Node3D) -> bool:
    if candidate == null or not _has_production_anchors(candidate):
        return false
    var tree := get_tree()
    if tree != null and tree.current_scene == candidate:
        return true
    return candidate.scene_file_path == CANONICAL_PRODUCTION_SCENE

func _direct_viewport_main(viewport: Viewport) -> Node3D:
    if viewport == null:
        return null
    var main := viewport.get_node_or_null("Main")
    if main is Node3D and main.get_parent() == viewport and _is_production_scene(main as Node3D):
        return main as Node3D
    return null

func _find_production_scene() -> Node3D:
    if _tearing_down or not is_inside_tree():
        return null
    var tree := get_tree()
    if tree == null:
        return null
    var current := tree.current_scene
    if current is Node3D and _is_production_scene(current as Node3D):
        return current as Node3D
    var root := tree.root
    if root == null:
        return null
    for child: Node in root.get_children():
        if child is Node3D:
            var candidate := child as Node3D
            if _is_production_scene(candidate):
                return candidate
            continue
        if child is Viewport:
            var viewport_candidate := _direct_viewport_main(child as Viewport)
            if viewport_candidate != null:
                return viewport_candidate
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

func _apply_proxy_provenance_contract(target: Object) -> void:
    target.set_meta("source", PROXY_SOURCE)
    target.set_meta("license", PROXY_LICENSE)
    target.set_meta("presentation_recipe", PROXY_RECIPE)

func _apply_material_identity_contract(target: Object) -> void:
    target.set_meta("material_identity_source_backed", false)
    target.set_meta("material_identity_status", "generic_authored_proxy")
    target.set_meta("material_reuse_scope", "anneessens_proxy_only")
    target.set_meta("brussels_material_family_authorized", false)

func _apply_alignment_contract(target: Object) -> void:
    target.set_meta("alignment_reference", ALIGNMENT_REFERENCE)
    target.set_meta("road_alignment_source_backed", false)
    target.set_meta("road_alignment_provenance_status", "unverified_rendered_road")

func _apply_proxy_contract(node: Node) -> void:
    _apply_proxy_provenance_contract(node)
    _apply_alignment_contract(node)
    node.set_meta("sidewalk_presence_source_backed", false)
    node.set_meta("visual_dimensions_source_backed", false)
    node.set_meta("vertical_profile_source_backed", false)
    _apply_material_identity_contract(node)
    node.set_meta("collision_source_backed", false)
    node.set_meta("collision_authorized", false)
    node.set_meta("collision_policy", "disabled_until_source_backed_vertical_profile")
    node.set_meta("authored_proxy", true)

func _apply_proxy_material_contract(material: Material) -> void:
    _apply_proxy_provenance_contract(material)
    _apply_alignment_contract(material)
    _apply_material_identity_contract(material)
    material.set_meta("presentation_revision", PROXY_MATERIAL_REVISION)
    material.set_meta("presentation_albedo", PROXY_ALBEDO)
    material.set_meta("presentation_roughness", PROXY_ROUGHNESS)
    material.set_meta("presentation_parameters_source_backed", false)

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
    _apply_proxy_contract(_root)
    _scene.add_child(_root)
    if not _build_from_existing_osm_roads():
        _release_owned_root()
        _scene = null
        if manual:
            _stop_watching()
        else:
            _manual_binding = false
            _start_watching()
        return
    if manual:
        _stop_watching()
    else:
        _ensure_mutation_poll_timer()
        _start_watching()

func _build_from_existing_osm_roads() -> bool:
    if not is_instance_valid(_scene) or not is_instance_valid(_root):
        return false
    var roads := _scene.get_node_or_null("BrusselsOSM/GeneratedRoads")
    if roads == null:
        push_warning("Anneessens Midi sidewalk kit: GeneratedRoads unavailable")
        return false
    var material := StandardMaterial3D.new()
    material.albedo_color = PROXY_ALBEDO
    material.roughness = PROXY_ROUGHNESS
    _apply_proxy_material_contract(material)
    for child: Node in roads.get_children():
        if not child is CSGBox3D or not child.name.begins_with("Road_"):
            continue
        var road := child as CSGBox3D
        _watch_alignment_road_mutations(road)
        if not road.visible:
            continue
        var center_2d := Vector2(road.global_position.x, road.global_position.z)
        if center_2d.distance_to(ANNEESSENS) > DETAIL_RADIUS_M:
            continue
        if road.size.z < 1.0 or road.size.x < 2.0:
            continue
        _alignment_road_instance_ids[road.get_instance_id()] = true
        _add_sidewalk_pair(road, material)
    return _sidewalk_count > 0

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
        pavement.use_collision = false
        pavement.set_meta("source_road", road.name)
        pavement.set_meta("alignment_witness_road", road.name)
        pavement.set_meta("alignment_witness_transform", road.global_transform)
        pavement.set_meta("alignment_witness_size", road.size)
        pavement.set_meta("alignment_witness_source_backed", false)
        pavement.set_meta("placement_witness_width", width)
        pavement.set_meta("placement_witness_side", side)
        pavement.set_meta("placement_witness_lateral", lateral)
        pavement.set_meta("placement_witness_offset", offset)
        pavement.set_meta("placement_witness_source_backed", false)
        _apply_proxy_contract(pavement)
        _root.add_child(pavement)
        pavement.global_position = road.global_position + lateral * offset * side + Vector3(0.0, 0.06, 0.0)
        pavement.global_rotation = road.global_rotation
        pavement.set_meta("placement_witness_global_transform", pavement.global_transform)
        pavement.set_meta("placement_witness_global_transform_source_backed", false)
        pavement.set_meta("placement_witness_rendered_size", pavement.size)
        pavement.set_meta("placement_witness_rendered_size_source_backed", false)
        _sidewalk_count += 1

func set_sidewalks_enabled(enabled: bool) -> void:
    _sidewalks_enabled = enabled
    if is_instance_valid(_root):
        _root.visible = enabled
        for child: Node in _root.get_children():
            if child is CSGBox3D:
                var pavement := child as CSGBox3D
                pavement.use_collision = false

func diagnostic_collision_count() -> int:
    return _collision_count

func get_runtime_stats() -> Dictionary:
    return {
        "sidewalks": _sidewalk_count,
        "collisions": _collision_count,
        "enabled": _sidewalks_enabled,
        "source": PROXY_SOURCE,
        "license": PROXY_LICENSE,
        "presentation_recipe": PROXY_RECIPE,
        "material_identity_source_backed": false,
        "brussels_material_family_authorized": false,
        "alignment_reference": ALIGNMENT_REFERENCE,
        "road_alignment_source_backed": false,
        "sidewalk_presence_source_backed": false,
        "visual_dimensions_source_backed": false,
        "vertical_profile_source_backed": false,
        "collision_source_backed": false,
        "collision_authorized": false,
    }
extends SceneTree

const ANNEESSENS := Vector2(-272.04, -217.07)
const DETAIL_RADIUS_M := 150.0
const EXPECTED_SOURCE := "OpenStreetMap contributors via Overpass API"
const EXPECTED_LICENSE := "ODbL-1.0"
const EXPECTED_ALIGNMENT_STATUS := "unverified_rendered_road"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ANNEESSENS_MIDI_SIDEWALK_ROOT_BIND_FAIL: %s" % message)
    quit(1)

func _expected_sidewalk_count(scene: Node3D) -> int:
    var roads := scene.get_node_or_null("BrusselsOSM/GeneratedRoads")
    if roads == null:
        return -1
    var eligible := 0
    for child: Node in roads.get_children():
        if not child is CSGBox3D or not child.name.begins_with("Road_"):
            continue
        var road := child as CSGBox3D
        var center_2d := Vector2(road.global_position.x, road.global_position.z)
        if center_2d.distance_to(ANNEESSENS) > DETAIL_RADIUS_M:
            continue
        if road.size.z < 1.0 or road.size.x < 2.0:
            continue
        eligible += 1
    return eligible * 2

func _assert_proxy_contract(node: Node, label: String) -> bool:
    if str(node.get_meta("source", "")) != EXPECTED_SOURCE:
        _fail("%s source provenance mismatch" % label)
        return false
    if str(node.get_meta("license", "")) != EXPECTED_LICENSE:
        _fail("%s source license mismatch" % label)
        return false
    if bool(node.get_meta("road_alignment_source_backed", true)):
        _fail("%s unverified rendered-road alignment was promoted as source-backed" % label)
        return false
    if str(node.get_meta("road_alignment_provenance_status", "")) != EXPECTED_ALIGNMENT_STATUS:
        _fail("%s road-alignment provenance status mismatch" % label)
        return false
    for unsupported: String in ["sidewalk_presence_source_backed", "visual_dimensions_source_backed", "vertical_profile_source_backed", "material_identity_source_backed"]:
        if bool(node.get_meta(unsupported, true)):
            _fail("%s unsupported source claim enabled: %s" % [label, unsupported])
            return false
    if not bool(node.get_meta("authored_proxy", false)):
        _fail("%s authored-proxy contract missing" % label)
        return false
    return true

func _assert_collision_state(kit: Node, expected_enabled: bool, label: String) -> bool:
    for child: Node in kit.get_children():
        if not child is CSGBox3D:
            _fail("%s: non-CSG sidewalk child leaked into kit" % label)
            return false
        var pavement := child as CSGBox3D
        if pavement.use_collision != expected_enabled:
            _fail("%s: sidewalk collision state mismatch for %s: got=%s expected=%s" % [label, pavement.name, pavement.use_collision, expected_enabled])
            return false
    return true

func _assert_bound_scene(runtime: Node, scene: Node3D, expected: int, label: String) -> bool:
    var sidewalk_count := int(runtime.call("diagnostic_sidewalk_count"))
    var collision_count := int(runtime.call("diagnostic_collision_count"))
    if sidewalk_count != expected:
        _fail("%s: sidewalks=%d expected=%d" % [label, sidewalk_count, expected])
        return false
    if collision_count != expected:
        _fail("%s: collisions=%d expected=%d" % [label, collision_count, expected])
        return false
    var kit := scene.get_node_or_null("AnneessensMidiSidewalkKit")
    if kit == null:
        _fail("%s: AnneessensMidiSidewalkKit not mounted under production scene" % label)
        return false
    if kit.get_child_count() != expected:
        _fail("%s: mounted sidewalk child count mismatch" % label)
        return false
    if not _assert_proxy_contract(kit, "%s kit" % label):
        return false
    for child: Node in kit.get_children():
        if not child is CSGBox3D:
            _fail("%s: non-CSG sidewalk child leaked into kit" % label)
            return false
        var pavement := child as CSGBox3D
        if not pavement.use_collision:
            _fail("%s: sidewalk collision disabled: %s" % [label, pavement.name])
            return false
        if not _assert_proxy_contract(pavement, "%s %s" % [label, pavement.name]):
            return false
    return true

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("production main scene missing")
        return

    var scene := packed.instantiate() as Node3D
    if scene == null:
        _fail("production main scene did not instantiate as Node3D")
        return
    root.add_child(scene)

    if current_scene != null:
        _fail("harness unexpectedly assigned SceneTree.current_scene")
        return
    if scene.get_node_or_null("BrusselsOSM") == null or scene.get_node_or_null("UrbISMidiExact") == null or scene.get_node_or_null("Player") == null:
        _fail("production scene anchors missing")
        return

    var expected := _expected_sidewalk_count(scene)
    if expected <= 0:
        _fail("production Anneessens road selection unexpectedly empty")
        return

    var runtime := root.get_node_or_null("AnneessensMidiSidewalkRuntime")
    if runtime == null:
        _fail("AnneessensMidiSidewalkRuntime autoload missing")
        return

    for _frame: int in range(24):
        await process_frame

    if not _assert_bound_scene(runtime, scene, expected, "direct-root"):
        return

    var kit := scene.get_node_or_null("AnneessensMidiSidewalkKit")
    runtime.call("set_sidewalks_enabled", false)
    if kit.visible:
        _fail("disabled sidewalk kit remained visible")
        return
    if not _assert_collision_state(kit, false, "disabled"):
        return

    runtime.call("set_sidewalks_enabled", true)
    if not kit.visible:
        _fail("re-enabled sidewalk kit remained hidden")
        return
    if not _assert_collision_state(kit, true, "re-enabled"):
        return

    # Remove the first legitimate owner, then mount a fresh production Main directly
    # under a root-level SubViewport. This established development/render-harness
    # ownership shape must not leave authored sidewalk/collision state dormant.
    root.remove_child(scene)
    scene.queue_free()
    for _frame: int in range(12):
        await process_frame
    if int(runtime.call("diagnostic_sidewalk_count")) != 0 or int(runtime.call("diagnostic_collision_count")) != 0:
        _fail("runtime retained owned sidewalk state after direct-root owner removal")
        return

    var viewport := SubViewport.new()
    viewport.name = "SidewalkWitnessViewport"
    root.add_child(viewport)
    var viewport_scene := packed.instantiate() as Node3D
    if viewport_scene == null:
        _fail("SubViewport production main scene did not instantiate as Node3D")
        return
    viewport_scene.name = "Main"
    viewport.add_child(viewport_scene)

    var viewport_expected := _expected_sidewalk_count(viewport_scene)
    if viewport_expected != expected:
        _fail("SubViewport production road selection drifted: got=%d expected=%d" % [viewport_expected, expected])
        return

    for _frame: int in range(24):
        await process_frame

    if not _assert_bound_scene(runtime, viewport_scene, viewport_expected, "root-subviewport-main"):
        return

    print("ANNEESSENS_MIDI_SIDEWALK_ROOT_BIND_OK: direct_root=true root_subviewport_main=true sidewalks=%d collisions=%d toggle_collision_sync=true current_scene=null source=OSM license=ODbL-1.0 authored_proxy=true road_alignment_source_backed=false road_alignment_provenance_status=%s" % [viewport_expected, viewport_expected, EXPECTED_ALIGNMENT_STATUS])
    quit(0)

extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const ANNEESSENS_SPAWN := Vector3(-272.04, 1.05, -217.07)
const EXPECTED_TREE_IDS := [4672009403, 4672009414, 4672009415, 4672009416, 4672009417, 11929097332, 11929097333]
const COLLISION_POLICY := "disabled_until_source_backed_trunk_profile"
const EXPECTED_SHARED_MESH_RESOURCES := 3
const EXPECTED_SHARED_LEGACY_MESH_RESOURCES := 2
const EXPECTED_COVERAGE_POLICY := "preserve_existing_runtime_subset_v1"
const EXPECTED_COVERAGE_RADIUS_M := 130.0
const EXPECTED_UPSTREAM_SHA256 := "899bc73ee0eea3623d7cc45455a542c1704039ef0239c13c33b3c74b4a241398"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    print("ANNEESSENS_OSM_FURNITURE_FAIL: %s" % message)
    quit(1)

func _collect_mesh_resource_ids(root: Node, visual_name: String) -> Dictionary:
    var resources: Dictionary = {}
    for node: Node in get_nodes_in_group("osm_environment_furniture"):
        if not node is StaticBody3D or not node.is_visible_in_tree():
            continue
        var visual := node.get_node_or_null(visual_name) as Node3D
        if visual == null:
            _fail("tree visual root missing while collecting resources: %s/%s" % [node.name, visual_name])
            return {}
        for child: Node in visual.get_children():
            if child is MeshInstance3D:
                var mesh_instance := child as MeshInstance3D
                if mesh_instance.mesh == null:
                    _fail("tree visual mesh missing: %s/%s" % [node.name, child.name])
                    return {}
                resources[mesh_instance.mesh.get_instance_id()] = true
    return resources

func _run() -> void:
    var selector := get_root().get_node_or_null("ZoneSelectorRuntime")
    if selector == null:
        _fail("ZoneSelectorRuntime missing")
        return
    selector.call("_on_zone_pressed", "anneessens")

    var main: Node = null
    var player: CharacterBody3D = null
    for _frame: int in range(360):
        await process_frame
        main = current_scene
        if main == null or main.scene_file_path != MAIN_SCENE:
            continue
        player = main.get_node_or_null("Player") as CharacterBody3D
        if player != null and player.global_position.distance_to(ANNEESSENS_SPAWN) < 0.75:
            break
    if main == null or player == null:
        _fail("Anneessens spawn unavailable")
        return

    for _frame: int in range(30):
        await process_frame

    var root := main.get_node_or_null("AnneessensOsmFurniture") as Node3D
    if root == null or not root.visible:
        _fail("Anneessens OSM furniture root missing or inactive")
        return
    if bool(root.get_meta("collision_source_backed", true)):
        _fail("unsourced furniture root must not claim source-backed collision")
        return
    if bool(root.get_meta("collision_authorized", true)):
        _fail("unsourced furniture root collision must remain unauthorized")
        return
    if str(root.get_meta("collision_policy", "")) != COLLISION_POLICY:
        _fail("furniture root collision policy drifted")
        return
    if bool(root.get_meta("coverage_complete", true)):
        _fail("partial Anneessens OSM subset must remain coverage_complete=false")
        return
    if bool(root.get_meta("full_environment_coverage_claimed", true)):
        _fail("partial Anneessens OSM subset must not claim full environment coverage")
        return
    if str(root.get_meta("coverage_policy", "")) != EXPECTED_COVERAGE_POLICY:
        _fail("Anneessens OSM subset coverage policy missing or drifted")
        return
    if abs(float(root.get_meta("coverage_radius_m", -1.0)) - EXPECTED_COVERAGE_RADIUS_M) > 0.0001:
        _fail("Anneessens OSM subset coverage radius missing or drifted")
        return
    if str(root.get_meta("upstream_source_sha256", "")) != EXPECTED_UPSTREAM_SHA256:
        _fail("Anneessens OSM upstream source digest missing or drifted")
        return

    var found_ids: Array[int] = []
    var foliage_lobes_total := 0
    var collision_shape_count := 0
    var mesh_resources: Dictionary = {}
    for node: Node in get_nodes_in_group("osm_environment_furniture"):
        if not node is StaticBody3D:
            _fail("OSM furniture tree root must remain a StaticBody3D")
            return
        var tree := node as StaticBody3D
        if not tree.is_visible_in_tree():
            continue
        if str(tree.get_meta("license", "")) != "ODbL-1.0":
            _fail("OSM furniture provenance/license missing")
            return
        if str(tree.get_meta("asset_family", "")) != "brussels_street_tree_v1":
            _fail("shared Brussels street-tree asset family missing: %s" % tree.name)
            return
        if bool(tree.get_meta("source_dimensions_measured", true)):
            _fail("authored tree dimensions must not be presented as source measurements: %s" % tree.name)
            return
        if bool(tree.get_meta("collision_source_backed", true)):
            _fail("tree collision must not be presented as source-backed: %s" % tree.name)
            return
        if bool(tree.get_meta("collision_authorized", true)):
            _fail("tree collision must remain unauthorized while trunk profile is unsourced: %s" % tree.name)
            return
        if str(tree.get_meta("collision_policy", "")) != COLLISION_POLICY:
            _fail("tree collision policy drifted: %s" % tree.name)
            return
        for child: Node in tree.find_children("*", "CollisionShape3D", true, false):
            collision_shape_count += 1
        var visual := tree.get_node_or_null("StreetTreeVisual") as Node3D
        if visual == null:
            _fail("shared street-tree visual root missing: %s" % tree.name)
            return
        var lobe_count := 0
        for child: Node in visual.get_children():
            if child is MeshInstance3D:
                var mesh_instance := child as MeshInstance3D
                if mesh_instance.mesh == null:
                    _fail("tree visual mesh missing: %s/%s" % [tree.name, child.name])
                    return
                mesh_resources[mesh_instance.mesh.get_instance_id()] = true
            if child.name.begins_with("FoliageLobe_") and child is MeshInstance3D:
                lobe_count += 1
        if lobe_count < 5:
            _fail("tree crown still reads as a primitive; expected >=5 foliage lobes: %s" % tree.name)
            return
        foliage_lobes_total += lobe_count
        found_ids.append(int(tree.get_meta("osm_id", 0)))

    found_ids.sort()
    var expected := EXPECTED_TREE_IDS.duplicate()
    expected.sort()
    if found_ids != expected:
        _fail("expected seven exact OSM trees, got %s" % str(found_ids))
        return
    if collision_shape_count != 0:
        _fail("unsourced tree collision shapes must stay fail-closed; found %d" % collision_shape_count)
        return
    if foliage_lobes_total < 35:
        _fail("shared tree visual coverage unexpectedly low")
        return
    if mesh_resources.size() != EXPECTED_SHARED_MESH_RESOURCES:
        _fail("street-tree geometry must reuse 3 mesh resources (trunk/dark/light); found %d" % mesh_resources.size())
        return

    var runtime := get_root().get_node_or_null("AnneessensOsmFurnitureRuntime")
    if runtime == null:
        _fail("AnneessensOsmFurnitureRuntime missing")
        return
    runtime.call("set_enhanced_trees_enabled", false)
    for _frame: int in range(3):
        await process_frame
    var legacy_mesh_resources := _collect_mesh_resource_ids(root, "LegacyTreeVisual")
    if legacy_mesh_resources.size() != EXPECTED_SHARED_LEGACY_MESH_RESOURCES:
        _fail("legacy tree fallback must reuse 2 mesh resources (trunk/crown); found %d" % legacy_mesh_resources.size())
        return

    runtime.call("set_enhanced_trees_enabled", true)
    for _frame: int in range(3):
        await process_frame
    var restored_mesh_resources := _collect_mesh_resource_ids(root, "StreetTreeVisual")
    if restored_mesh_resources.size() != EXPECTED_SHARED_MESH_RESOURCES:
        _fail("enhanced tree mesh reuse must survive legacy round-trip; found %d" % restored_mesh_resources.size())
        return

    print("ANNEESSENS_OSM_FURNITURE_OK: trees=7 coverage_complete=false coverage_policy=%s coverage_radius_m=%.1f collisions=0 collision_policy=%s foliage_lobes=%d mesh_resources=%d legacy_mesh_resources=%d asset_family=brussels_street_tree_v1 source=OSM license=ODbL-1.0" % [EXPECTED_COVERAGE_POLICY, EXPECTED_COVERAGE_RADIUS_M, COLLISION_POLICY, foliage_lobes_total, mesh_resources.size(), legacy_mesh_resources.size()])
    quit(0)

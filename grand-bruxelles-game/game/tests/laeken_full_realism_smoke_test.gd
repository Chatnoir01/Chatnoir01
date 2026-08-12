extends SceneTree

const HEIGHTS_PATH := "res://data/urbis/laeken_jette/building_heights_dsm.game.json"
const OVERRIDES_PATH := "res://data/urbis/laeken_jette/building_height_landmark_overrides.game.json"
const TREES_PATH := "res://data/environment/laeken_jette/official_city_trees.game.json"
const ORTHO_PATH := "res://data/orthophoto/laeken_jette/phase1_ortho.jpg"
const MAX_READY_FRAMES := 120


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("LAEKEN_FULL_REALISM_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    for path in [HEIGHTS_PATH, OVERRIDES_PATH, TREES_PATH, ORTHO_PATH]:
        if not FileAccess.file_exists(path):
            _fail("required realism asset missing: %s" % path)
            return

    var packed := load("res://game/zones/laeken_jette/laeken_jette.tscn") as PackedScene
    if packed == null:
        _fail("Laeken scene failed to load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)

    var terrain = scene.get_node_or_null("LaekenTerrain")
    var height_pass = scene.get_node_or_null("BuildingHeightPass")
    var bridge = scene.get_node_or_null("BuildingDSMMaterialBridge")
    var ortho = scene.get_node_or_null("OrthophotoPass")
    var visual = scene.get_node_or_null("BuildingVisualPass")
    var trees = scene.get_node_or_null("OfficialTrees")
    var canopy = scene.get_node_or_null("TreeCanopyRefinement")
    if terrain == null or height_pass == null or bridge == null or ortho == null or visual == null or trees == null or canopy == null:
        _fail("one or more required realism nodes are missing")
        return

    var ready_frame := -1
    for frame_index in range(MAX_READY_FRAMES):
        var all_ready := (
            bool(terrain.get("terrain_loaded"))
            and bool(height_pass.get("height_mesh_ready"))
            and bool(bridge.get("material_bridged"))
            and bool(ortho.get("orthophoto_active"))
            and bool(visual.get("building_visual_active"))
            and bool(visual.get("orthophoto_roof_active"))
            and bool(trees.get("trees_loaded"))
            and bool(canopy.get("refinement_ready"))
        )
        if all_ready:
            ready_frame = frame_index
            break
        await process_frame
    if ready_frame < 0:
        _fail("realism stack not ready within %d frames terrain=%s heights=%s bridge=%s ortho=%s building_visual=%s ortho_roofs=%s trees=%s canopy=%s" % [
            MAX_READY_FRAMES,
            bool(terrain.get("terrain_loaded")),
            bool(height_pass.get("height_mesh_ready")),
            bool(bridge.get("material_bridged")),
            bool(ortho.get("orthophoto_active")),
            bool(visual.get("building_visual_active")),
            bool(visual.get("orthophoto_roof_active")),
            bool(trees.get("trees_loaded")),
            bool(canopy.get("refinement_ready")),
        ])
        return

    if int(terrain.get("width")) != 360 or int(terrain.get("height")) != 620:
        _fail("unexpected phase-1 terrain grid: %dx%d" % [int(terrain.get("width")), int(terrain.get("height"))])
        return
    var terrain_range := float(terrain.get("max_height_m")) - float(terrain.get("min_height_m"))
    if terrain_range < 40.0:
        _fail("terrain relief range too small: %.2fm" % terrain_range)
        return
    var terrain_mesh := scene.get_node_or_null("LaekenTerrain/OfficialDTMTerrainMesh") as MeshInstance3D
    var roads_mesh := scene.get_node_or_null("OfficialStreetSurfaces") as MeshInstance3D
    if terrain_mesh == null or roads_mesh == null:
        _fail("official terrain or road mesh missing")
        return
    if not terrain_mesh.material_override is ShaderMaterial or not roads_mesh.material_override is ShaderMaterial:
        _fail("orthophoto shader missing from terrain or roads")
        return

    var derived := int(height_pass.get("derived_buildings"))
    var fallback := int(height_pass.get("fallback_buildings"))
    var corrected := int(height_pass.get("landmark_corrected_buildings"))
    if derived != 9163 or fallback != 355:
        _fail("building height accounting changed: derived=%d fallback=%d" % [derived, fallback])
        return
    if corrected != 1:
        _fail("Atomium-overlap correction missing or duplicated: %d" % corrected)
        return
    var old_mesh := scene.get_node_or_null("OfficialBuildings") as MeshInstance3D
    var dsm_mesh := scene.get_node_or_null("OfficialBuildingsDSM") as MeshInstance3D
    if old_mesh == null or dsm_mesh == null or old_mesh.visible or not dsm_mesh.visible:
        _fail("DSM building replacement visibility is incorrect")
        return
    if dsm_mesh.mesh == null or dsm_mesh.mesh.get_aabb().size.y < 50.0:
        _fail("DSM building mesh lacks expected vertical variation")
        return
    if not dsm_mesh.material_override is ShaderMaterial:
        _fail("final DSM building ShaderMaterial missing")
        return

    var tree_total := int(trees.get("official_tree_count"))
    var grounded := int(trees.get("terrain_grounded_count"))
    var skipped := int(trees.get("skipped_count"))
    if tree_total < 8200 or grounded != tree_total or skipped > 50:
        _fail("official tree population unexpected: total=%d grounded=%d skipped=%d" % [tree_total, grounded, skipped])
        return
    var trunks := scene.get_node_or_null("OfficialTrees/OfficialTreeTrunks") as MultiMeshInstance3D
    if trunks == null or trunks.multimesh == null or trunks.multimesh.instance_count != tree_total:
        _fail("official tree MultiMesh/trunk count mismatch")
        return

    var refined_trees := int(canopy.get("refined_tree_count"))
    var broadleaf_lobes := int(canopy.get("broadleaf_lobe_instances"))
    var conifer_tiers := int(canopy.get("conifer_tier_instances"))
    if refined_trees < 8200:
        _fail("tree canopy refinement skipped too many sourced trees: %d" % refined_trees)
        return
    if broadleaf_lobes < 12000 or conifer_tiers < 1200:
        _fail("tree canopy refinement too sparse: broadleaf_lobes=%d conifer_tiers=%d" % [broadleaf_lobes, conifer_tiers])
        return
    var lobes := scene.get_node_or_null("TreeCanopyRefinement/BroadleafSecondaryLobes") as MultiMeshInstance3D
    if lobes == null or lobes.multimesh == null or lobes.multimesh.instance_count != broadleaf_lobes:
        _fail("broadleaf refinement MultiMesh count mismatch")
        return

    print("LAEKEN_FULL_REALISM_OK: ready_frame=%d terrain=360x620 relief=%.2fm buildings={derived:%d,fallback:%d,landmark_corrected:%d} trees={total:%d,skipped:%d,lobes:%d,conifer_tiers:%d} ortho=true" % [
        ready_frame,
        terrain_range,
        derived,
        fallback,
        corrected,
        tree_total,
        skipped,
        broadleaf_lobes,
        conifer_tiers,
    ])
    scene.queue_free()
    await process_frame
    quit(0)

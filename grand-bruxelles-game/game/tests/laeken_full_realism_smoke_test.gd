extends SceneTree

const HEIGHTS_PATH := "res://data/urbis/laeken_jette/building_heights_dsm.game.json"
const OVERRIDES_PATH := "res://data/urbis/laeken_jette/building_height_landmark_overrides.game.json"
const TREES_PATH := "res://data/environment/laeken_jette/official_city_trees.game.json"
const ORTHO_PATH := "res://data/orthophoto/laeken_jette/phase1_ortho.jpg"
const MAX_READY_FRAMES := 220


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
    var facade_detail = scene.get_node_or_null("FacadeDetailPass")
    var trees = scene.get_node_or_null("OfficialTrees")
    var canopy = scene.get_node_or_null("TreeCanopyRefinement")
    var cleanup = scene.get_node_or_null("SourceTruthCleanup")
    if terrain == null or height_pass == null or bridge == null or ortho == null or visual == null or facade_detail == null or trees == null or canopy == null or cleanup == null:
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
            and bool(facade_detail.get("detail_ready"))
            and bool(trees.get("trees_loaded"))
            and bool(canopy.get("refinement_ready"))
            and bool(cleanup.get("cleanup_ready"))
        )
        if all_ready:
            ready_frame = frame_index
            break
        await process_frame
    if ready_frame < 0:
        _fail("realism stack not ready within %d frames terrain=%s heights=%s bridge=%s ortho=%s building_visual=%s ortho_roofs=%s facade_detail=%s trees=%s canopy=%s cleanup=%s" % [
            MAX_READY_FRAMES,
            bool(terrain.get("terrain_loaded")),
            bool(height_pass.get("height_mesh_ready")),
            bool(bridge.get("material_bridged")),
            bool(ortho.get("orthophoto_active")),
            bool(visual.get("building_visual_active")),
            bool(visual.get("orthophoto_roof_active")),
            bool(facade_detail.get("detail_ready")),
            bool(trees.get("trees_loaded")),
            bool(canopy.get("refinement_ready")),
            bool(cleanup.get("cleanup_ready")),
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

    var facade_buildings := int(facade_detail.get("detailed_buildings"))
    var facade_halls := int(facade_detail.get("detailed_halls"))
    var facade_windows := int(facade_detail.get("window_instances"))
    var facade_sills := int(facade_detail.get("sill_instances"))
    var hall_ribs := int(facade_detail.get("hall_rib_instances"))
    if facade_buildings < 20 or facade_windows < 250 or facade_sills < 250:
        _fail("street-level residential facade detail too sparse: buildings=%d windows=%d sills=%d" % [facade_buildings, facade_windows, facade_sills])
        return
    if facade_halls < 1 or hall_ribs < 20:
        _fail("Heysel hall facade detail missing: halls=%d ribs=%d" % [facade_halls, hall_ribs])
        return
    var glass_panels := scene.get_node_or_null("FacadeDetailPass/FacadeGlassPanels") as MultiMeshInstance3D
    var stone_sills := scene.get_node_or_null("FacadeDetailPass/FacadeStoneSills") as MultiMeshInstance3D
    var rib_mesh := scene.get_node_or_null("FacadeDetailPass/HallVerticalRibs") as MultiMeshInstance3D
    if glass_panels == null or glass_panels.multimesh == null or glass_panels.multimesh.instance_count != facade_windows:
        _fail("facade glazing MultiMesh count mismatch")
        return
    if stone_sills == null or stone_sills.multimesh == null or stone_sills.multimesh.instance_count != facade_sills:
        _fail("facade sill MultiMesh count mismatch")
        return
    if rib_mesh == null or rib_mesh.multimesh == null or rib_mesh.multimesh.instance_count != hall_ribs:
        _fail("hall rib MultiMesh count mismatch")
        return

    var legacy_hidden := bool(cleanup.get("hidden_legacy_approach"))
    var removed_synthetic_trees := int(cleanup.get("removed_corridor_trees"))
    var removed_synthetic_dashes := int(cleanup.get("removed_corridor_dashes"))
    var kept_lamps := int(cleanup.get("kept_corridor_lamps"))
    if not legacy_hidden or removed_synthetic_trees <= 0 or removed_synthetic_dashes <= 0:
        _fail("legacy approach cleanup incomplete: hidden=%s trees=%d dashes=%d" % [legacy_hidden, removed_synthetic_trees, removed_synthetic_dashes])
        return
    if kept_lamps <= 0:
        _fail("provisional sourced-axis lamps unexpectedly missing after cleanup")
        return
    var legacy_root := scene.get_node_or_null("RealismPass/AtomiumApproachPhotoGuided") as Node3D
    if legacy_root == null or legacy_root.visible:
        _fail("legacy duplicate approach root is still visible")
        return
    var corridor := scene.get_node_or_null("AtomiumCorridor")
    if corridor == null:
        _fail("Atomium corridor missing")
        return
    for child in corridor.get_children():
        if str(child.name) in ["PhotoGuidedTree", "LaneDash"]:
            _fail("synthetic corridor duplicate survived cleanup: %s" % str(child.name))
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
    var primary_replaced := bool(canopy.get("primary_broadleaf_replaced"))
    if refined_trees < 8200:
        _fail("tree canopy refinement skipped too many sourced trees: %d" % refined_trees)
        return
    if not primary_replaced:
        _fail("single-sphere primary broadleaf crowns were not replaced")
        return
    if broadleaf_lobes < 19000 or conifer_tiers < 1200:
        _fail("tree canopy refinement too sparse: broadleaf_lobes=%d conifer_tiers=%d" % [broadleaf_lobes, conifer_tiers])
        return
    var primary_broadleaf := scene.get_node_or_null("OfficialTrees/OfficialBroadleafCrowns") as MultiMeshInstance3D
    if primary_broadleaf == null or primary_broadleaf.visible:
        _fail("old single-sphere broadleaf crown layer is still visible")
        return
    var lobes := scene.get_node_or_null("TreeCanopyRefinement/BroadleafReplacementLobes") as MultiMeshInstance3D
    if lobes == null or lobes.multimesh == null or lobes.multimesh.instance_count != broadleaf_lobes:
        _fail("broadleaf replacement MultiMesh count mismatch")
        return

    print("LAEKEN_FULL_REALISM_OK: ready_frame=%d terrain=360x620 relief=%.2fm buildings={derived:%d,fallback:%d,landmark_corrected:%d,street_detail:%d,windows:%d,halls:%d,ribs:%d} source_cleanup={trees:%d,dashes:%d,lamps:%d} trees={total:%d,skipped:%d,replacement_lobes:%d,conifer_tiers:%d,primary_replaced:%s} ortho=true" % [
        ready_frame,
        terrain_range,
        derived,
        fallback,
        corrected,
        facade_buildings,
        facade_windows,
        facade_halls,
        hall_ribs,
        removed_synthetic_trees,
        removed_synthetic_dashes,
        kept_lamps,
        tree_total,
        skipped,
        broadleaf_lobes,
        conifer_tiers,
        primary_replaced,
    ])
    scene.queue_free()
    await process_frame
    quit(0)

extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const FACADE_NAME := "GrandPlaceFacadePresentationRuntime"
const V2_NAME := "GrandPlaceFacadePresentationCorrectionV2"
const V3_NAME := "GrandPlaceFacadePresentationCoverageV3"
const V4_NAME := "GrandPlaceFacadePresentationRefinementV4"
const V5_NAME := "GrandPlaceFacadePresentationIntegratedV5"
const V7_NAME := "GrandPlaceMaisonDuRoiTowerDepthV7"
const CONTOUR_NAME := "GrandPlaceCompleteContourRuntime"
const CANONICAL_CAMERA := Vector3(319.01, 1.72, -535.20)
const MIN_TOWER_CUE_SURFACE_CLEARANCE_M := 0.03

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_FACADE_INTEGRATED_V5_FAIL: " + message)
    quit(1)

func _box_world_size(node: MeshInstance3D) -> Vector3:
    if node == null or node.mesh == null or not node.mesh is BoxMesh:
        return Vector3.ZERO
    var box := node.mesh as BoxMesh
    return Vector3(
        box.size.x * node.global_basis.x.length(),
        box.size.y * node.global_basis.y.length(),
        box.size.z * node.global_basis.z.length()
    )

func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    var facade := root.get_node_or_null(FACADE_NAME)
    var v2 := root.get_node_or_null(V2_NAME)
    var v3 := root.get_node_or_null(V3_NAME)
    var v4 := root.get_node_or_null(V4_NAME)
    var v5 := root.get_node_or_null(V5_NAME)
    var v7 := root.get_node_or_null(V7_NAME)
    var contour := root.get_node_or_null(CONTOUR_NAME)
    for _frame: int in range(1200):
        if facade != null and v2 != null and v3 != null and v4 != null and v5 != null and v7 != null and contour != null and bool(facade.get("built")) and bool(v2.get("built")) and bool(v3.get("built")) and bool(v4.get("built")) and bool(v5.get("built")) and bool(v7.get("built")) and bool(contour.get("geometry_loaded")):
            break
        await process_frame
        facade = root.get_node_or_null(FACADE_NAME)
        v2 = root.get_node_or_null(V2_NAME)
        v3 = root.get_node_or_null(V3_NAME)
        v4 = root.get_node_or_null(V4_NAME)
        v5 = root.get_node_or_null(V5_NAME)
        v7 = root.get_node_or_null(V7_NAME)
        contour = root.get_node_or_null(CONTOUR_NAME)
    if facade == null or v2 == null or v3 == null or v4 == null or v5 == null or v7 == null or contour == null:
        _fail("required runtimes missing"); return
    if bool(v5.get("failed")) or not bool(v5.get("built")):
        _fail("V5 did not build"); return
    if bool(v7.get("failed")) or not bool(v7.get("built")):
        _fail("Maison du Roi tower-depth V7 did not build"); return
    if str(v4.get_meta("human_review_status","")) != "rejected" or int(v4.get_meta("visual_geometry_count",-1)) != 0:
        _fail("human-rejected V4 was not neutralized"); return
    if int(v5.call("collision_object_count")) != 0 or int(contour.call("active_collision_count")) != 23:
        _fail("collision invariant drifted"); return
    for key: String in ["source_geometry_changed","source_collision_changed","camera_changed","threshold_changed"]:
        if bool(v5.get_meta(key,true)):
            _fail("forbidden mutation: %s" % key); return
    if bool(v5.get_meta("lateral_scale_rescue",true)):
        _fail("lateral scale rescue reintroduced"); return
    if int(v5.get("renard_baluster_count")) != 9:
        _fail("Renard baluster count drifted"); return
    if int(v5.get("maison_glazing_panel_count")) != 35 or int(v5.get("maison_structural_pier_count")) != 20:
        _fail("Maison integrated structure accounting drifted"); return
    if int(v5.get("maison_tower_cue_count")) != 3:
        _fail("Maison du Roi axial tower/lantern/spire cue accounting missing or drifted"); return
    if int(v5.get("brasseurs_signature_count")) != 11:
        _fail("Brasseurs sourced signature accounting drifted"); return
    if int(v5.get("rose_order_signature_count")) != 16:
        _fail("Rose sourced order accounting drifted"); return
    if int(v5.get("mont_thabor_signature_count")) != 5:
        _fail("Mont Thabor sourced gable accounting drifted"); return
    if int(v5.get_meta("signature_feature_count",-1)) != 32:
        _fail("frontage signature feature total drifted"); return
    for key: String in ["brasseurs_curved_pediment_cue","brasseurs_lower_doric_order_cue","rose_superposed_orders_cue","mont_thabor_gobertange_gable_cue"]:
        if not bool(v5.get_meta(key,false)):
            _fail("documented heritage cue missing: %s" % key); return
    for key: String in ["maison_axial_tower_documented","maison_octagonal_lantern_documented","maison_spire_documented"]:
        if not bool(v5.get_meta(key,false)):
            _fail("Maison du Roi documented vertical silhouette cue missing: %s" % key); return
    if bool(v5.get_meta("maison_tower_dimensions_surveyed",true)):
        _fail("Maison du Roi tower presentation dimensions mislabeled surveyed"); return
    if bool(v5.get_meta("signature_dimensions_surveyed",true)):
        _fail("authored signature dimensions mislabeled surveyed"); return
    if bool(v5.get_meta("renard_balcony_depth_surveyed",true)):
        _fail("authored balcony depth mislabeled surveyed"); return
    if bool(v5.get_meta("statuary_authored",true)) or bool(v5.get_meta("finished_perfect",true)):
        _fail("forbidden statuary/completion claim"); return
    var balcony := facade.get_node_or_null("GrandPlaceFacadePresentationDetails/Facade_1608851_Le_Renard/ContinuousBalconyCue") as MeshInstance3D
    if balcony == null or not balcony.scale.is_equal_approx(Vector3.ONE):
        _fail("native Renard balcony width was altered"); return
    var details := v5.get_node_or_null("GrandPlaceFacadeIntegratedRefinementV5Details") as Node3D
    if details == null or details.get_node_or_null("RenardBalconySlab") == null or details.get_node_or_null("RenardBalconyFrontRail") == null:
        _fail("integrated Renard balcony geometry missing"); return
    for required_name: String in ["MaisonDuRoiAxialTowerCue","MaisonDuRoiOctagonalLanternCue","MaisonDuRoiSpireCue","BrasseursCurvedPediment_3","BrasseursLowerDoricPier_1","RoseDoricCapital_1","RoseIonicCapital_1","RoseCompositeCapital_1","MontThaborGobertangeGable_4"]:
        if details.get_node_or_null(required_name) == null:
            _fail("frontage signature node missing: %s" % required_name); return

    var maison := v2.get_node_or_null("GrandPlaceFacadeCorrectionV2Details/MaisonDuRoiGroupedLancetsV2") as Node3D
    var axial_left := maison.get_node_or_null("AxialLeft") as MeshInstance3D if maison != null else null
    var axial_right := maison.get_node_or_null("AxialRight") as MeshInstance3D if maison != null else null
    var tower := details.get_node_or_null("MaisonDuRoiAxialTowerCue") as MeshInstance3D
    var lantern := details.get_node_or_null("MaisonDuRoiOctagonalLanternCue") as MeshInstance3D
    var spire := details.get_node_or_null("MaisonDuRoiSpireCue") as MeshInstance3D
    if axial_left == null or axial_right == null or tower == null or lantern == null or spire == null:
        _fail("Maison du Roi axial width/depth anchors missing"); return
    var axial_tangent := axial_left.global_basis.x.normalized()
    var axial_span := absf((axial_right.global_position - axial_left.global_position).dot(axial_tangent))
    var tower_size := _box_world_size(tower)
    var tower_width := tower_size.x
    if axial_span < 0.5:
        _fail("Maison du Roi axial bay span invalid: %.4f" % axial_span); return
    if tower_width < axial_span * 0.78 or tower_width > axial_span * 1.05:
        _fail("Maison du Roi tower width escaped axial bay: tower=%.4f axial=%.4f ratio=%.4f" % [tower_width,axial_span,tower_width/axial_span]); return
    var axial_midpoint := (axial_left.global_position + axial_right.global_position) * 0.5
    var center_error := absf((tower.global_position - axial_midpoint).dot(axial_tangent))
    if center_error > 0.05:
        _fail("Maison du Roi tower no longer centered on axial bay: error=%.4f" % center_error); return

    var tower_depth := tower_size.z
    var depth_ratio := tower_depth / tower_width
    if depth_ratio < 0.60 or depth_ratio > 0.85:
        _fail("Maison du Roi square-plan tower depth missing: width=%.4f depth=%.4f ratio=%.4f" % [tower_width,tower_depth,depth_ratio]); return
    if not bool(v7.get_meta("front_plane_preserved",false)):
        _fail("Maison du Roi V7 did not preserve the prior player-facing tower plane"); return
    if not bool(v7.get_meta("depth_extended_behind_facade",false)):
        _fail("Maison du Roi V7 depth was not constrained behind the prior front plane"); return
    if bool(v7.get_meta("source_geometry_changed",true)) or bool(v7.get_meta("source_collision_changed",true)):
        _fail("Maison du Roi V7 mutated source geometry/collision"); return
    var tower_normal := tower.global_basis.z.normalized()
    var lantern_axis_error := absf((lantern.global_position - tower.global_position).dot(tower_normal))
    var spire_axis_error := absf((spire.global_position - tower.global_position).dot(tower_normal))
    if lantern_axis_error > 0.01 or spire_axis_error > 0.01:
        _fail("Maison du Roi lantern/spire no longer centered on square tower depth axis: lantern=%.4f spire=%.4f" % [lantern_axis_error,spire_axis_error]); return

    for required_name: String in [
        "MaisonDuRoiTowerRoofBayFrontPanel",
        "MaisonDuRoiTowerRoofBayFrontPointedHead",
        "MaisonDuRoiTowerRoofBayLeftPanel",
        "MaisonDuRoiTowerRoofBayLeftPointedHead",
        "MaisonDuRoiTowerRoofBayRightPanel",
        "MaisonDuRoiTowerRoofBayRightPointedHead",
        "MaisonDuRoiTowerRoofBalustradeRail",
    ]:
        if details.get_node_or_null(required_name) == null:
            _fail("Maison du Roi documented tower-register cue missing: %s" % required_name); return
    if int(v7.get_meta("roof_register_bay_count", -1)) != 3 or not bool(v7.get_meta("roof_register_bays_documented", false)):
        _fail("Maison du Roi three-face roof-register bay contract drifted"); return
    if int(v7.get_meta("roof_balustrade_element_count", -1)) != 6 or not bool(v7.get_meta("roof_balustrade_documented", false)):
        _fail("Maison du Roi projecting balustrade contract drifted"); return
    if bool(v7.get_meta("roof_register_bay_dimensions_surveyed", true)) or bool(v7.get_meta("roof_balustrade_dimensions_surveyed", true)):
        _fail("Maison du Roi authored tower-register dimensions mislabeled surveyed"); return
    for index: int in range(5):
        if details.get_node_or_null("MaisonDuRoiTowerRoofBaluster_%02d" % index) == null:
            _fail("Maison du Roi openwork balustrade lost post %d" % index); return

    var front_panel := details.get_node_or_null("MaisonDuRoiTowerRoofBayFrontPanel") as MeshInstance3D
    if front_panel == null:
        _fail("Maison du Roi front roof-register panel missing"); return
    var camera_direction := Vector3(CANONICAL_CAMERA.x - front_panel.global_position.x, 0.0, CANONICAL_CAMERA.z - front_panel.global_position.z)
    if camera_direction.length_squared() < 0.01 or tower_normal.dot(camera_direction.normalized()) < 0.55:
        _fail("Maison du Roi front roof-register cue is not on the canonical player-facing tower face"); return
    var panel_size := _box_world_size(front_panel)
    var tower_front_plane := tower.global_position.dot(tower_normal) + tower_size.z * 0.5
    var panel_back_plane := front_panel.global_position.dot(tower_normal) - panel_size.z * 0.5
    var panel_surface_clearance := panel_back_plane - tower_front_plane
    if panel_surface_clearance < MIN_TOWER_CUE_SURFACE_CLEARANCE_M - 0.0001:
        _fail("Maison du Roi front bay is depth-buffer unsafe: clearance=%.4f required=%.4f" % [panel_surface_clearance,MIN_TOWER_CUE_SURFACE_CLEARANCE_M]); return

    # Urban Brussels 31143 explicitly states that the axial tower has four
    # levels. The player-frame still reads as one undifferentiated vertical
    # block, so require three authored/non-surveyed level-break cues that make
    # the exact four-level heritage fact visible without moving source geometry.
    if int(v7.get_meta("tower_level_count", -1)) != 4 or not bool(v7.get_meta("tower_four_levels_documented", false)):
        _fail("Maison du Roi documented four-level tower contract missing"); return
    if int(v7.get_meta("tower_level_separator_count", -1)) != 3:
        _fail("Maison du Roi four levels require exactly three visible level breaks"); return
    if bool(v7.get_meta("tower_level_separator_dimensions_surveyed", true)):
        _fail("Maison du Roi authored tower level breaks mislabeled surveyed"); return
    for index: int in range(3):
        var separator := details.get_node_or_null("MaisonDuRoiTowerLevelBreak_%02d" % index) as MeshInstance3D
        if separator == null:
            _fail("Maison du Roi four-level tower lost separator %d" % index); return
        var separator_size := _box_world_size(separator)
        if separator_size.x < tower_width * 0.95:
            _fail("Maison du Roi tower level break too narrow to read structurally: index=%d width=%.4f tower=%.4f" % [index,separator_size.x,tower_width]); return

    facade.call("set_presentation_visible",false)
    for _frame: int in range(4): await process_frame
    if details.visible:
        _fail("OFF toggle did not hide V5 details"); return
    if int(contour.call("active_collision_count")) != 23:
        _fail("OFF toggle changed collisions"); return
    facade.call("set_presentation_visible",true)
    for _frame: int in range(4): await process_frame
    if not details.visible:
        _fail("ON toggle did not restore V5 details"); return
    print("GRAND_PLACE_FACADE_INTEGRATED_V5_OK: v4_rejected=true lateral_stretch=false renard_balusters=9 maison_glazing=35 maison_piers=20 maison_tower_cues=3 maison_tower_axial_ratio=%.3f maison_tower_depth_ratio=%.3f maison_roof_bays=3 maison_balustrade=6 maison_front_bay_clearance=%.3f maison_tower_levels=4 maison_level_breaks=3 brasseurs=11 rose_orders=16 mont_thabor=5 collisions=23" % [tower_width/axial_span,depth_ratio,panel_surface_clearance])
    quit(0)
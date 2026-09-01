extends Node3D

const FACADE_NAME := "GrandPlaceFacadePresentationRuntime"
const V2_NAME := "GrandPlaceFacadePresentationCorrectionV2"
const V3_NAME := "GrandPlaceFacadePresentationCoverageV3"
const CONTOUR_NAME := "GrandPlaceCompleteContourRuntime"

const RENARD_BALCONY_DEPTH_M := 1.25
const RENARD_BALCONY_THICKNESS_M := 0.16
const RENARD_FRONT_RAIL_HEIGHT_M := 0.30
const OUTER_PILASTER_DEPTH_SCALE := 4.0
const MAISON_PIER_WIDTH_SCALE := 2.4
const MAISON_PIER_HEIGHT_SCALE := 2.25
const MAISON_PIER_DEPTH_SCALE := 2.2
const MAISON_TOWER_AXIAL_WIDTH_SCALE := 0.92
const MAISON_TOWER_HEIGHT_REGISTERS := 1.35
const MAISON_LANTERN_HEIGHT_REGISTERS := 0.48
const MAISON_SPIRE_HEIGHT_REGISTERS := 0.90

var built := false
var failed := false
var new_feature_count := 0
var renard_baluster_count := 0
var maison_glazing_panel_count := 0
var maison_structural_pier_count := 0
var maison_tower_cue_count := 0
var brasseurs_signature_count := 0
var rose_order_signature_count := 0
var mont_thabor_signature_count := 0
var _facade: Node = null
var _v2: Node = null
var _v3: Node = null
var _contour: Node = null
var _detail_root: Node3D = null
var _last_visible := true

func _ready() -> void:
    set_process(false)
    call_deferred("_build_when_ready")

func _fail(message: String) -> void:
    failed = true
    push_error("Grand-Place facade integrated refinement V5: %s" % message)

func _build_when_ready() -> void:
    for _frame: int in range(1200):
        _facade = get_tree().root.get_node_or_null(FACADE_NAME)
        _v2 = get_tree().root.get_node_or_null(V2_NAME)
        _v3 = get_tree().root.get_node_or_null(V3_NAME)
        _contour = get_tree().root.get_node_or_null(CONTOUR_NAME)
        if _facade != null and _v2 != null and _v3 != null and _contour != null and bool(_facade.get("built")) and bool(_v2.get("built")) and bool(_v3.get("built")) and bool(_contour.get("geometry_loaded")):
            break
        await get_tree().process_frame
    if _facade == null or _v2 == null or _v3 == null or _contour == null:
        _fail("required runtimes missing"); return
    if not bool(_facade.get("built")) or not bool(_v2.get("built")) or not bool(_v3.get("built")) or not bool(_contour.get("geometry_loaded")):
        _fail("required runtimes not ready"); return

    _detail_root = Node3D.new()
    _detail_root.name = "GrandPlaceFacadeIntegratedRefinementV5Details"
    add_child(_detail_root)

    if not _build_cornet_renard_depth(): return
    if not _build_maison_integrated_structure(): return
    if not _build_brasseurs_signature(): return
    if not _build_rose_orders(): return
    if not _build_mont_thabor_gable(): return
    if renard_baluster_count != 9:
        _fail("Renard baluster count drifted: %d" % renard_baluster_count); return
    if maison_glazing_panel_count != 35:
        _fail("Maison glazing panel count drifted: %d" % maison_glazing_panel_count); return
    if maison_structural_pier_count != 20:
        _fail("Maison structural pier count drifted: %d" % maison_structural_pier_count); return
    if maison_tower_cue_count != 3:
        _fail("Maison tower cue count drifted: %d" % maison_tower_cue_count); return
    if brasseurs_signature_count != 11:
        _fail("Brasseurs signature count drifted: %d" % brasseurs_signature_count); return
    if rose_order_signature_count != 16:
        _fail("Rose order signature count drifted: %d" % rose_order_signature_count); return
    if mont_thabor_signature_count != 5:
        _fail("Mont Thabor signature count drifted: %d" % mont_thabor_signature_count); return

    built = true
    set_meta("refinement_revision",5)
    set_meta("human_failed_v4_disabled",true)
    set_meta("lateral_scale_rescue",false)
    set_meta("renard_balcony_depth_m_authored",RENARD_BALCONY_DEPTH_M)
    set_meta("renard_balcony_depth_surveyed",false)
    set_meta("maison_structure_integrated",true)
    set_meta("maison_glazing_panel_count",maison_glazing_panel_count)
    set_meta("maison_structural_pier_count",maison_structural_pier_count)
    set_meta("maison_tower_cue_count",maison_tower_cue_count)
    set_meta("maison_axial_tower_documented",true)
    set_meta("maison_octagonal_lantern_documented",true)
    set_meta("maison_spire_documented",true)
    set_meta("maison_tower_dimensions_surveyed",false)
    set_meta("maison_tower_width_bound_to_axial_bay",true)
    set_meta("brasseurs_curved_pediment_cue",true)
    set_meta("brasseurs_lower_doric_order_cue",true)
    set_meta("rose_superposed_orders_cue",true)
    set_meta("mont_thabor_gobertange_gable_cue",true)
    set_meta("signature_feature_count",brasseurs_signature_count+rose_order_signature_count+mont_thabor_signature_count)
    set_meta("signature_dimensions_surveyed",false)
    set_meta("source_geometry_changed",false)
    set_meta("source_collision_changed",false)
    set_meta("camera_changed",false)
    set_meta("threshold_changed",false)
    set_meta("statuary_authored",false)
    set_meta("finished_perfect",false)
    _sync_visibility(true)
    set_process(true)
    print("GRAND_PLACE_FACADE_INTEGRATED_V5_READY: balcony_depth=%.2f balusters=%d maison_glazing=%d maison_piers=%d maison_tower_cues=%d brasseurs=%d rose_orders=%d mont_thabor=%d collisions=0 lateral_stretch=false" % [RENARD_BALCONY_DEPTH_M,renard_baluster_count,maison_glazing_panel_count,maison_structural_pier_count,maison_tower_cue_count,brasseurs_signature_count,rose_order_signature_count,mont_thabor_signature_count])

func _process(_delta: float) -> void:
    if not built or _facade == null: return
    var enabled := bool(_facade.get("presentation_visible"))
    if enabled != _last_visible: _sync_visibility(enabled)

func _sync_visibility(enabled: bool) -> void:
    _last_visible = enabled
    if _detail_root != null and is_instance_valid(_detail_root): _detail_root.visible = enabled

func _white_stone(label: String) -> Material:
    return BrusselsWhiteStoneMaterial.create(Color(0.68,0.66,0.61,1.0),Color(0.84,0.80,0.72,1.0),0.84,label)

func _glass_material() -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.035,0.075,0.095,1.0)
    mat.roughness = 0.30
    mat.metallic = 0.08
    mat.cull_mode = BaseMaterial3D.CULL_BACK
    mat.set_meta("material_family","authored_dark_glazing")
    mat.set_meta("exact_rgb_is_photometric_measurement",false)
    return mat

func _add_box(name_value: String, position: Vector3, tangent: Vector3, normal: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = Vector3(maxf(size.x,0.02),maxf(size.y,0.02),maxf(size.z,0.02))
    var node := MeshInstance3D.new()
    node.name = name_value
    node.mesh = mesh
    node.material_override = material
    _detail_root.add_child(node)
    node.global_position = position
    node.global_basis = Basis(tangent.normalized(),Vector3.UP,normal.normalized())
    node.set_meta("source_geometry",false)
    node.set_meta("presentation_dimension_surveyed",false)
    new_feature_count += 1
    return node

func _add_vertical_cylinder(name_value: String, position: Vector3, radius: float, height: float, material: Material, radial_segments: int, top_radius: float = -1.0) -> MeshInstance3D:
    var mesh := CylinderMesh.new()
    mesh.bottom_radius = maxf(radius,0.04)
    mesh.top_radius = maxf(top_radius if top_radius >= 0.0 else radius,0.0)
    mesh.height = maxf(height,0.08)
    mesh.radial_segments = maxi(radial_segments,3)
    var node := MeshInstance3D.new()
    node.name = name_value
    node.mesh = mesh
    node.material_override = material
    _detail_root.add_child(node)
    node.global_position = position
    node.set_meta("source_geometry",false)
    node.set_meta("presentation_dimension_surveyed",false)
    new_feature_count += 1
    return node

func _box_world_size(node: MeshInstance3D) -> Vector3:
    if node == null or node.mesh == null or not node.mesh is BoxMesh:
        return Vector3.ZERO
    var box := node.mesh as BoxMesh
    return Vector3(box.size.x*node.global_basis.x.length(),box.size.y*node.global_basis.y.length(),box.size.z*node.global_basis.z.length())

func _build_cornet_renard_depth() -> bool:
    var cornet := _facade.get_node_or_null("GrandPlaceFacadePresentationDetails/Facade_1608847_Le_Cornet") as Node3D
    var renard := _facade.get_node_or_null("GrandPlaceFacadePresentationDetails/Facade_1608851_Le_Renard") as Node3D
    var balcony := renard.get_node_or_null("ContinuousBalconyCue") as MeshInstance3D if renard != null else null
    if cornet == null or renard == null or balcony == null or balcony.mesh == null or not balcony.mesh is BoxMesh:
        _fail("Cornet/Renard integrated facade anchors missing"); return false

    var box := balcony.mesh as BoxMesh
    var tangent := balcony.global_basis.x.normalized()
    var normal := balcony.global_basis.z.normalized()
    var width := box.size.x * balcony.global_basis.x.length()
    var stone := _white_stone("Urban Brussels 31124: continuous balustraded balcony; depth authored as non-survey presentation")
    var slab_center := balcony.global_position + normal * (RENARD_BALCONY_DEPTH_M * 0.5) - Vector3.UP * 0.16
    _add_box("RenardBalconySlab",slab_center,tangent,normal,Vector3(width,RENARD_BALCONY_THICKNESS_M,RENARD_BALCONY_DEPTH_M),stone)
    var front_center := balcony.global_position + normal * (RENARD_BALCONY_DEPTH_M - 0.05) + Vector3.UP * 0.12
    _add_box("RenardBalconyFrontRail",front_center,tangent,normal,Vector3(width,RENARD_FRONT_RAIL_HEIGHT_M,0.10),stone)
    for i: int in range(9):
        var u := -width*0.43 + width*0.86*float(i)/8.0
        _add_box("RenardBalconyBaluster_%02d"%i,front_center+tangent*u+Vector3.UP*0.36,tangent,normal,Vector3(0.09,0.58,0.09),stone)
        renard_baluster_count += 1

    for pair: Array in [[cornet,"Pilaster_0"],[cornet,"Pilaster_3"],[renard,"Pilaster_0"],[renard,"Pilaster_4"]]:
        var node := (pair[0] as Node3D).get_node_or_null(str(pair[1])) as MeshInstance3D
        if node == null:
            _fail("outer documented pilaster missing: %s" % str(pair[1])); return false
        node.scale.z = OUTER_PILASTER_DEPTH_SCALE
        node.set_meta("depth_emphasis_authored_non_survey",true)
        node.set_meta("lateral_scale_changed",false)
    return true

func _build_maison_integrated_structure() -> bool:
    var maison := _v2.get_node_or_null("GrandPlaceFacadeCorrectionV2Details/MaisonDuRoiGroupedLancetsV2") as Node3D
    if maison == null:
        _fail("Maison du Roi V2 grouped facade missing"); return false
    var glass := _glass_material()
    for child: Node in maison.get_children():
        if not child is MeshInstance3D: continue
        var mesh_node := child as MeshInstance3D
        var n := mesh_node.name
        var lower_panel := n.begins_with("GroupedBay_") and not n.contains("Mullion")
        var upper_panel := n.begins_with("UpperGroupedBay_") and not n.contains("Mullion")
        if lower_panel or upper_panel:
            mesh_node.material_override = glass
            mesh_node.set_meta("glazing_recess_visual",true)
            maison_glazing_panel_count += 1
        elif n.begins_with("GalleryPier_"):
            mesh_node.scale.x = MAISON_PIER_WIDTH_SCALE
            mesh_node.scale.y = MAISON_PIER_HEIGHT_SCALE
            mesh_node.scale.z = MAISON_PIER_DEPTH_SCALE
            mesh_node.set_meta("structural_pier_emphasis_authored_non_survey",true)
            maison_structural_pier_count += 1
        elif n.begins_with("GalleryRail_"):
            mesh_node.scale.y = 2.1
            mesh_node.scale.z = 2.0
            mesh_node.set_meta("gallery_band_emphasis_authored_non_survey",true)
        elif n in ["AxialLeft","AxialRight"]:
            mesh_node.scale.x = 2.0
            mesh_node.scale.z = 2.2
            mesh_node.set_meta("axial_bay_emphasis_documented",true)
        elif n == "BlueStonePlinth":
            mesh_node.scale.y = 1.55
            mesh_node.scale.z = 1.8

    var rail0 := maison.get_node_or_null("GalleryRail_0") as MeshInstance3D
    var rail1 := maison.get_node_or_null("GalleryRail_1") as MeshInstance3D
    var plinth := maison.get_node_or_null("BlueStonePlinth") as MeshInstance3D
    var axial_left := maison.get_node_or_null("AxialLeft") as MeshInstance3D
    var axial_right := maison.get_node_or_null("AxialRight") as MeshInstance3D
    if rail0 == null or rail1 == null or plinth == null or axial_left == null or axial_right == null:
        _fail("Maison du Roi tower source-derived facade anchors missing"); return false
    var register_h := absf(rail1.global_position.y-rail0.global_position.y)
    var facade_width := _box_world_size(plinth).x
    if register_h < 0.5 or facade_width < 4.0:
        _fail("Maison du Roi tower source-derived facade frame invalid"); return false
    var tangent := plinth.global_basis.x.normalized()
    var normal := plinth.global_basis.z.normalized()
    var axial_span := absf((axial_right.global_position-axial_left.global_position).dot(tangent))
    if axial_span < 0.5:
        _fail("Maison du Roi tower axial span invalid"); return false
    var axial_midpoint := (axial_left.global_position+axial_right.global_position)*0.5
    var stone := _white_stone("Urban Brussels 31143: axial square tower above central gallery bay; authored non-survey silhouette from existing facade register")
    var slate := StandardMaterial3D.new()
    slate.albedo_color = Color(0.12,0.14,0.16,1.0)
    slate.roughness = 0.90
    slate.set_meta("source_label","Urban Brussels 31143: roof in batiere/pavilion forms covered with slate; exact RGB authored")
    slate.set_meta("exact_rgb_is_photometric_measurement",false)

    var tower_width := axial_span*MAISON_TOWER_AXIAL_WIDTH_SCALE
    var tower_height := register_h*MAISON_TOWER_HEIGHT_REGISTERS
    var tower_base_y := rail1.global_position.y+register_h*0.72
    var tower_center := Vector3(axial_midpoint.x,tower_base_y+tower_height*0.5,axial_midpoint.z)+normal*0.12
    var tower := _add_box("MaisonDuRoiAxialTowerCue",tower_center,tangent,normal,Vector3(tower_width,tower_height,0.42),stone)
    tower.set_meta("heritage_fact","axial_square_tower")
    tower.set_meta("tower_levels_exact_count_claimed",false)
    tower.set_meta("width_anchor","v2_axial_left_right")
    tower.set_meta("width_ratio_to_axial_span",MAISON_TOWER_AXIAL_WIDTH_SCALE)
    maison_tower_cue_count += 1

    var lantern_height := register_h*MAISON_LANTERN_HEIGHT_REGISTERS
    var lantern_radius := tower_width*0.28
    var lantern_center := tower_center+Vector3.UP*(tower_height*0.5+lantern_height*0.5)
    var lantern := _add_vertical_cylinder("MaisonDuRoiOctagonalLanternCue",lantern_center,lantern_radius,lantern_height,stone,8)
    lantern.set_meta("heritage_fact","octagonal_lantern")
    lantern.set_meta("plan_shape_documented",true)
    maison_tower_cue_count += 1

    var spire_height := register_h*MAISON_SPIRE_HEIGHT_REGISTERS
    var spire_center := lantern_center+Vector3.UP*(lantern_height*0.5+spire_height*0.5)
    var spire := _add_vertical_cylinder("MaisonDuRoiSpireCue",spire_center,lantern_radius*0.82,spire_height,slate,12,0.02)
    spire.set_meta("heritage_fact","spire_above_octagonal_lantern")
    spire.set_meta("piriform_profile_approximated",true)
    spire.set_meta("exact_spire_profile_claimed",false)
    maison_tower_cue_count += 1
    return true

func _build_brasseurs_signature() -> bool:
    var owner := _facade.get_node_or_null("GrandPlaceFacadePresentationDetails/Facade_1639974_La_Maison_des_Brasseurs") as Node3D
    if owner == null:
        _fail("Maison des Brasseurs owner missing"); return false
    var left := owner.get_node_or_null("ColossalOrder_0") as MeshInstance3D
    var right := owner.get_node_or_null("ColossalOrder_3") as MeshInstance3D
    var entablature := owner.get_node_or_null("PowerfulEntablature") as MeshInstance3D
    var plinth := owner.get_node_or_null("BlueStonePlinth") as MeshInstance3D
    if left == null or right == null or entablature == null or plinth == null:
        _fail("Maison des Brasseurs source-derived anchors missing"); return false
    var tangent := left.global_basis.x.normalized()
    var normal := left.global_basis.z.normalized()
    var delta := right.global_position-left.global_position
    if delta.dot(tangent) < 0.0: tangent = -tangent
    var span := absf(delta.dot(tangent))
    if span < 2.0:
        _fail("Maison des Brasseurs span invalid"); return false
    var center := (left.global_position+right.global_position)*0.5
    var stone := _white_stone("Urban Brussels 31127: curved pediment and lower Doric order; dimensions authored from existing source-derived facade span")
    var lower_y := (plinth.global_position.y+entablature.global_position.y)*0.5
    var lower_h := maxf(0.45,absf(entablature.global_position.y-plinth.global_position.y)*0.70)
    for i: int in range(4):
        var anchor := owner.get_node_or_null("ColossalOrder_%d"%i) as MeshInstance3D
        if anchor == null:
            _fail("Brasseurs colossal order anchor missing: %d" % i); return false
        var aw := _box_world_size(anchor).x
        var pier := _add_box("BrasseursLowerDoricPier_%d"%i,Vector3(anchor.global_position.x,lower_y,anchor.global_position.z)+normal*0.08,tangent,normal,Vector3(maxf(aw*1.35,0.20),lower_h,0.22),stone)
        pier.set_meta("heritage_fact","lower_doric_order")
        brasseurs_signature_count += 1
    var top_y := maxf(left.global_position.y+_box_world_size(left).y*0.5,right.global_position.y+_box_world_size(right).y*0.5)
    var segment_w := span/7.0*0.92
    for i: int in range(7):
        var centered := float(i)-3.0
        var normalized := absf(centered)/3.0
        var rise := (1.0-normalized*normalized)*1.55
        var pos := center+tangent*(centered*span/7.0)+Vector3.UP*(top_y-center.y+0.28+rise)+normal*0.10
        var seg := _add_box("BrasseursCurvedPediment_%d"%i,pos,tangent,normal,Vector3(segment_w,0.24,0.22),stone)
        seg.set_meta("heritage_fact","curved_pediment")
        seg.set_meta("curve_is_authored_cue",true)
        brasseurs_signature_count += 1
    return true

func _build_rose_orders() -> bool:
    var owner := _facade.get_node_or_null("GrandPlaceFacadePresentationDetails/Facade_1635485_La_Rose") as Node3D
    if owner == null:
        _fail("La Rose owner missing"); return false
    var left := owner.get_node_or_null("Pilaster_0") as MeshInstance3D
    var right := owner.get_node_or_null("Pilaster_3") as MeshInstance3D
    if left == null or right == null:
        _fail("La Rose pilaster anchors missing"); return false
    var tangent := left.global_basis.x.normalized()
    var normal := left.global_basis.z.normalized()
    var stone := _white_stone("Urban Brussels 31128: Doric/Ionic/Composite superposed orders; capital envelopes authored from existing pilaster rhythm")
    var width_scales := [1.35,1.72,2.05]
    var labels := ["doric","ionic","composite"]
    for level: int in range(3):
        var window := owner.get_node_or_null("Window_%d_0"%level) as MeshInstance3D
        if window == null:
            _fail("La Rose window register anchor missing: %d" % level); return false
        var cap_y := window.global_position.y+_box_world_size(window).y*0.58
        for i: int in range(4):
            var pilaster := owner.get_node_or_null("Pilaster_%d"%i) as MeshInstance3D
            if pilaster == null:
                _fail("La Rose pilaster missing: %d" % i); return false
            var pw := maxf(_box_world_size(pilaster).x,0.12)
            var cap := _add_box("Rose%sCapital_%d"%[str(labels[level]).capitalize(),i],Vector3(pilaster.global_position.x,cap_y,pilaster.global_position.z)+normal*0.08,tangent,normal,Vector3(pw*float(width_scales[level]),0.17+float(level)*0.03,0.20),stone)
            cap.set_meta("heritage_order",labels[level])
            rose_order_signature_count += 1
            if level == 2:
                var crown := _add_box("RoseCompositeCrown_%d"%i,cap.global_position+Vector3.UP*0.18,tangent,normal,Vector3(pw*2.35,0.12,0.20),stone)
                crown.set_meta("heritage_order","composite")
                rose_order_signature_count += 1
    return true

func _build_mont_thabor_gable() -> bool:
    var owner := _facade.get_node_or_null("GrandPlaceFacadePresentationDetails/Facade_1646728_Le_Mont_Thabor") as Node3D
    if owner == null:
        _fail("Le Mont Thabor owner missing"); return false
    var left := owner.get_node_or_null("Pilaster_0") as MeshInstance3D
    var right := owner.get_node_or_null("Pilaster_3") as MeshInstance3D
    var upper_window := owner.get_node_or_null("Window_2_1") as MeshInstance3D
    if left == null or right == null or upper_window == null:
        _fail("Mont Thabor source-derived anchors missing"); return false
    var tangent := left.global_basis.x.normalized()
    var normal := left.global_basis.z.normalized()
    var delta := right.global_position-left.global_position
    if delta.dot(tangent) < 0.0: tangent = -tangent
    var span := absf(delta.dot(tangent))
    var center := (left.global_position+right.global_position)*0.5
    var base_y := upper_window.global_position.y+_box_world_size(upper_window).y*0.72
    var stone := _white_stone("Urban Brussels 30907: Gobertange gable; stepped cue bounded to existing source-derived facade span")
    for i: int in range(5):
        var fraction := 1.0-float(i)*0.15
        var gable := _add_box("MontThaborGobertangeGable_%d"%i,Vector3(center.x,base_y+float(i)*0.30,center.z)+normal*0.09,tangent,normal,Vector3(span*fraction,0.18,0.20),stone)
        gable.set_meta("heritage_fact","gobertange_gable")
        mont_thabor_signature_count += 1
    return true

func collision_object_count() -> int:
    return 0
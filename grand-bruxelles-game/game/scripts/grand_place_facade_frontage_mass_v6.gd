extends Node3D

const FACADE_NAME := "GrandPlaceFacadePresentationRuntime"
const V5_NAME := "GrandPlaceFacadePresentationIntegratedV5"
const CONTOUR_NAME := "GrandPlaceCompleteContourRuntime"
const BRASSEURS_BACKING_CLEARANCE_M := 0.03
const ROSE_BACKING_CLEARANCE_M := 0.03
const MONT_THABOR_BACKING_CLEARANCE_M := 0.03

var built := false
var failed := false
var feature_count := 0
var cornet_renard_mass_count := 0
var brasseurs_mass_count := 0
var rose_mass_count := 0
var mont_thabor_mass_count := 0
var _facade: Node = null
var _v5: Node = null
var _contour: Node = null
var _root: Node3D = null
var _last_visible := true

func _ready() -> void:
    set_process(false)
    call_deferred("_build_when_ready")

func _fail(message: String) -> void:
    failed = true
    push_error("Grand-Place facade frontage mass V6: %s" % message)

func _build_when_ready() -> void:
    for _frame: int in range(1200):
        _facade = get_tree().root.get_node_or_null(FACADE_NAME)
        _v5 = get_tree().root.get_node_or_null(V5_NAME)
        _contour = get_tree().root.get_node_or_null(CONTOUR_NAME)
        if _facade != null and _v5 != null and _contour != null and bool(_facade.get("built")) and bool(_v5.get("built")) and bool(_contour.get("geometry_loaded")):
            break
        await get_tree().process_frame
    if _facade == null or _v5 == null or _contour == null:
        _fail("required runtimes missing"); return
    if not bool(_facade.get("built")) or not bool(_v5.get("built")) or not bool(_contour.get("geometry_loaded")):
        _fail("required runtimes not ready"); return

    _root = Node3D.new()
    _root.name = "GrandPlaceFacadeFrontageMassV6Details"
    add_child(_root)

    if not _build_cornet_renard_native_mass(): return
    if not _build_brasseurs_mass(): return
    if not _build_rose_mass(): return
    if not _build_mont_thabor_mass(): return

    if cornet_renard_mass_count != 8:
        _fail("Cornet/Renard mass count drifted: %d" % cornet_renard_mass_count); return
    if brasseurs_mass_count != 5:
        _fail("Brasseurs mass count drifted: %d" % brasseurs_mass_count); return
    if rose_mass_count != 6:
        _fail("Rose mass count drifted: %d" % rose_mass_count); return
    if mont_thabor_mass_count != 5:
        _fail("Mont Thabor mass count drifted: %d" % mont_thabor_mass_count); return

    built = true
    set_meta("refinement_revision",6)
    set_meta("native_owner_span_only",true)
    set_meta("lateral_endpoint_extension",false)
    set_meta("source_geometry_changed",false)
    set_meta("source_collision_changed",false)
    set_meta("new_collision_objects",0)
    set_meta("camera_changed",false)
    set_meta("fov_changed",false)
    set_meta("threshold_changed",false)
    set_meta("dimensions_surveyed",false)
    set_meta("statuary_authored",false)
    set_meta("finished_perfect",false)
    set_meta("brasseurs_backing_behind_authored_relief",true)
    set_meta("brasseurs_backing_front_clearance_m",BRASSEURS_BACKING_CLEARANCE_M)
    set_meta("rose_backing_behind_authored_relief",true)
    set_meta("rose_backing_front_clearance_m",ROSE_BACKING_CLEARANCE_M)
    set_meta("mont_thabor_backing_behind_authored_relief",true)
    set_meta("mont_thabor_backing_front_clearance_m",MONT_THABOR_BACKING_CLEARANCE_M)
    set_meta("three_second_goal","broad full-owner frontage mass and skyline readability without occluding authored relief")
    _sync_visibility(true)
    set_process(true)
    print("GRAND_PLACE_FACADE_FRONTAGE_MASS_V6_READY: cornet_renard=%d brasseurs=%d rose=%d mont_thabor=%d features=%d collisions=0 lateral_endpoint_extension=false brasseurs_relief_occlusion=false rose_relief_occlusion=false mont_thabor_relief_occlusion=false brasseurs_clearance_m=%.2f rose_clearance_m=%.2f mont_thabor_clearance_m=%.2f" % [cornet_renard_mass_count,brasseurs_mass_count,rose_mass_count,mont_thabor_mass_count,feature_count,BRASSEURS_BACKING_CLEARANCE_M,ROSE_BACKING_CLEARANCE_M,MONT_THABOR_BACKING_CLEARANCE_M])

func _process(_delta: float) -> void:
    if not built or _facade == null: return
    var enabled := bool(_facade.get("presentation_visible"))
    if enabled != _last_visible: _sync_visibility(enabled)

func _sync_visibility(enabled: bool) -> void:
    _last_visible = enabled
    if _root != null and is_instance_valid(_root): _root.visible = enabled

func _stone(label: String) -> Material:
    return BrusselsWhiteStoneMaterial.create(Color(0.66,0.64,0.58,1.0),Color(0.86,0.82,0.73,1.0),0.82,label)

func _add_box(name_value: String, position: Vector3, tangent: Vector3, normal: Vector3, size: Vector3, material: Material, fact: String) -> MeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = Vector3(maxf(size.x,0.02),maxf(size.y,0.02),maxf(size.z,0.02))
    var node := MeshInstance3D.new()
    node.name = name_value
    node.mesh = mesh
    node.material_override = material
    _root.add_child(node)
    node.global_position = position
    node.global_basis = Basis(tangent.normalized(),Vector3.UP,normal.normalized())
    node.set_meta("source_geometry",false)
    node.set_meta("presentation_dimension_surveyed",false)
    node.set_meta("heritage_constraint",fact)
    feature_count += 1
    return node

func _box_world_size(node: MeshInstance3D) -> Vector3:
    if node == null or node.mesh == null or not node.mesh is BoxMesh: return Vector3.ZERO
    var box := node.mesh as BoxMesh
    return Vector3(box.size.x*node.global_basis.x.length(),box.size.y*node.global_basis.y.length(),box.size.z*node.global_basis.z.length())

func _span_frame(left: MeshInstance3D, right: MeshInstance3D) -> Dictionary:
    var tangent := left.global_basis.x.normalized()
    var normal := left.global_basis.z.normalized()
    var delta := right.global_position-left.global_position
    if delta.dot(tangent) < 0.0: tangent = -tangent
    var span := absf(delta.dot(tangent))
    return {"tangent":tangent,"normal":normal,"span":span,"center":(left.global_position+right.global_position)*0.5}

func _backing_center_offset(reference: MeshInstance3D, backing_depth: float, clearance: float) -> float:
    var reference_depth := _box_world_size(reference).z
    return reference_depth*0.5-clearance-maxf(backing_depth,0.02)*0.5

func _build_cornet_renard_native_mass() -> bool:
    var cornet := _facade.get_node_or_null("GrandPlaceFacadePresentationDetails/Facade_1608847_Le_Cornet") as Node3D
    var renard := _facade.get_node_or_null("GrandPlaceFacadePresentationDetails/Facade_1608851_Le_Renard") as Node3D
    if cornet == null or renard == null:
        _fail("Cornet/Renard owners missing"); return false
    var stone := _stone("Urban Brussels 31123/31124: projecting cornice and pilaster/order rhythms; full-width bands stay inside existing owner anchors")
    for entry: Array in [[cornet,3,"Cornet"],[renard,4,"Renard"]]:
        var owner := entry[0] as Node3D
        var right_index := int(entry[1])
        var label := str(entry[2])
        var left := owner.get_node_or_null("Pilaster_0") as MeshInstance3D
        var right := owner.get_node_or_null("Pilaster_%d"%right_index) as MeshInstance3D
        if left == null or right == null:
            _fail("%s native span anchors missing"%label); return false
        var frame := _span_frame(left,right)
        var span := float(frame.span)
        if span < 1.0:
            _fail("%s native span invalid"%label); return false
        var tangent := frame.tangent as Vector3
        var normal := frame.normal as Vector3
        var center := frame.center as Vector3
        var h := maxf(_box_world_size(left).y,_box_world_size(right).y)
        var mid_y := (left.global_position.y+right.global_position.y)*0.5
        for level: int in range(3):
            var y := mid_y-h*0.33+h*0.32*float(level)
            _add_box("%sNativeFullWidthBand_%d"%[label,level],Vector3(center.x,y,center.z)+normal*(0.12+0.03*float(level)),tangent,normal,Vector3(span,0.22+0.04*float(level),0.26),stone,"native full-owner cornice/order band")
            cornet_renard_mass_count += 1
        _add_box("%sNativeCrownBand"%label,Vector3(center.x,mid_y+h*0.49,center.z)+normal*0.16,tangent,normal,Vector3(span*0.96,0.32,0.34),stone,"native owner crown band")
        cornet_renard_mass_count += 1
    return true

func _build_brasseurs_mass() -> bool:
    var owner := _facade.get_node_or_null("GrandPlaceFacadePresentationDetails/Facade_1639974_La_Maison_des_Brasseurs") as Node3D
    if owner == null:
        _fail("Brasseurs owner missing"); return false
    var left := owner.get_node_or_null("ColossalOrder_0") as MeshInstance3D
    var reference := owner.get_node_or_null("ColossalOrder_1") as MeshInstance3D
    var right := owner.get_node_or_null("ColossalOrder_3") as MeshInstance3D
    var entablature := owner.get_node_or_null("PowerfulEntablature") as MeshInstance3D
    if left == null or reference == null or right == null or entablature == null:
        _fail("Brasseurs mass anchors missing"); return false
    var frame := _span_frame(left,right)
    var span := float(frame.span)
    var tangent := frame.tangent as Vector3
    var normal := reference.global_basis.z.normalized()
    var frame_normal := frame.normal as Vector3
    if frame_normal.dot(normal) < 0.999:
        _fail("Brasseurs authored relief normal drifted"); return false
    var center := frame.center as Vector3
    var stone := _stone("Urban Brussels 31127: colossal classical order, fronton/attic/balustrade family; dimensions authored from native owner span")
    var base_y := minf(left.global_position.y,right.global_position.y)-_box_world_size(left).y*0.36
    var top_y := entablature.global_position.y
    var lower_depth := 0.38
    var entablature_depth := 0.42
    var attic_depth := 0.34
    var shoulder_depth := 0.36
    var crown_depth := 0.38
    _add_box("BrasseursFullWidthLowerOrder",Vector3(center.x,base_y,center.z)+normal*_backing_center_offset(reference,lower_depth,BRASSEURS_BACKING_CLEARANCE_M),tangent,normal,Vector3(span,0.46,lower_depth),stone,"full-width lower classical order backing behind authored relief")
    _add_box("BrasseursFullWidthEntablature",Vector3(center.x,top_y,center.z)+normal*_backing_center_offset(reference,entablature_depth,BRASSEURS_BACKING_CLEARANCE_M),tangent,normal,Vector3(span,0.58,entablature_depth),stone,"powerful full-width entablature backing behind authored relief")
    _add_box("BrasseursAtticMass",Vector3(center.x,top_y+0.72,center.z)+normal*_backing_center_offset(reference,attic_depth,BRASSEURS_BACKING_CLEARANCE_M),tangent,normal,Vector3(span*0.86,0.72,attic_depth),stone,"attic backing mass within native owner span")
    _add_box("BrasseursPedimentShoulder",Vector3(center.x,top_y+1.46,center.z)+normal*_backing_center_offset(reference,shoulder_depth,BRASSEURS_BACKING_CLEARANCE_M),tangent,normal,Vector3(span*0.68,0.42,shoulder_depth),stone,"fronton shoulder backing mass")
    _add_box("BrasseursPedimentCrown",Vector3(center.x,top_y+2.02,center.z)+normal*_backing_center_offset(reference,crown_depth,BRASSEURS_BACKING_CLEARANCE_M),tangent,normal,Vector3(span*0.38,0.48,crown_depth),stone,"fronton crown backing mass")
    brasseurs_mass_count = 5
    return true

func _build_rose_mass() -> bool:
    var owner := _facade.get_node_or_null("GrandPlaceFacadePresentationDetails/Facade_1635485_La_Rose") as Node3D
    var v5_details := _v5.get_node_or_null("GrandPlaceFacadeIntegratedRefinementV5Details") as Node3D if _v5 != null else null
    var reference := v5_details.get_node_or_null("RoseIonicCapital_0") as MeshInstance3D if v5_details != null else null
    if owner == null or reference == null:
        _fail("Rose owner/authored-order reference missing"); return false
    var left := owner.get_node_or_null("Pilaster_0") as MeshInstance3D
    var right := owner.get_node_or_null("Pilaster_3") as MeshInstance3D
    if left == null or right == null:
        _fail("Rose span anchors missing"); return false
    var frame := _span_frame(left,right)
    var span := float(frame.span)
    var tangent := frame.tangent as Vector3
    var normal := reference.global_basis.z.normalized()
    var frame_normal := frame.normal as Vector3
    if frame_normal.dot(normal) < 0.999:
        _fail("Rose authored relief normal drifted"); return false
    var center := frame.center as Vector3
    var stone := _stone("Urban Brussels 31128: Italianizing superposed orders; register bands use native owner span only")
    var h := maxf(_box_world_size(left).y,_box_world_size(right).y)
    var mid_y := (left.global_position.y+right.global_position.y)*0.5
    for level: int in range(3):
        var y := mid_y-h*0.30+h*0.30*float(level)
        var depth := 0.34
        _add_box("RoseFullWidthOrderBand_%d"%level,Vector3(center.x,y,center.z)+normal*_backing_center_offset(reference,depth,ROSE_BACKING_CLEARANCE_M),tangent,normal,Vector3(span,0.34+0.04*float(level),depth),stone,"superposed order register backing behind authored relief")
        rose_mass_count += 1
    for i: int in range(3):
        var y := mid_y-h*0.15+h*0.30*float(i)
        var depth := 0.42
        _add_box("RoseCentralOrderProjection_%d"%i,Vector3(center.x,y,center.z)+normal*_backing_center_offset(reference,depth,ROSE_BACKING_CLEARANCE_M),tangent,normal,Vector3(span*0.44,h*0.23,depth),stone,"central order backing projection behind authored relief within native owner span")
        rose_mass_count += 1
    return true

func _build_mont_thabor_mass() -> bool:
    var owner := _facade.get_node_or_null("GrandPlaceFacadePresentationDetails/Facade_1646728_Le_Mont_Thabor") as Node3D
    var v5_details := _v5.get_node_or_null("GrandPlaceFacadeIntegratedRefinementV5Details") as Node3D if _v5 != null else null
    var reference := v5_details.get_node_or_null("MontThaborGobertangeGable_0") as MeshInstance3D if v5_details != null else null
    if owner == null or reference == null:
        _fail("Mont Thabor owner/authored-gable reference missing"); return false
    var left := owner.get_node_or_null("Pilaster_0") as MeshInstance3D
    var right := owner.get_node_or_null("Pilaster_3") as MeshInstance3D
    var upper := owner.get_node_or_null("Window_2_1") as MeshInstance3D
    if left == null or right == null or upper == null:
        _fail("Mont Thabor mass anchors missing"); return false
    var frame := _span_frame(left,right)
    var span := float(frame.span)
    var tangent := frame.tangent as Vector3
    var normal := reference.global_basis.z.normalized()
    var frame_normal := frame.normal as Vector3
    if frame_normal.dot(normal) < 0.999:
        _fail("Mont Thabor authored gable normal drifted"); return false
    var center := frame.center as Vector3
    var stone := _stone("Urban Brussels 30907 / exact owner 1646728: sober classical frontage and documented Gobertange gable cue; backing mass stays behind authored gable and inside native facade span")
    var base_y := upper.global_position.y+_box_world_size(upper).y*0.62
    var widths := [1.0,0.82,0.64,0.46,0.28]
    var depth := 0.34
    var center_offset := _backing_center_offset(reference,depth,MONT_THABOR_BACKING_CLEARANCE_M)
    for i: int in range(5):
        _add_box("MontThaborFullGableMass_%d"%i,Vector3(center.x,base_y+0.34*float(i),center.z)+normal*center_offset,tangent,normal,Vector3(span*float(widths[i]),0.28,depth),stone,"stepped native-span gable backing behind authored Gobertange relief")
        mont_thabor_mass_count += 1
    return true

func collision_object_count() -> int:
    return 0

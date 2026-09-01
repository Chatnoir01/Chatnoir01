extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const FACADE_NAME := "GrandPlaceFacadePresentationRuntime"
const V5_NAME := "GrandPlaceFacadePresentationIntegratedV5"
const V6_NAME := "GrandPlaceFacadeFrontageMassV6"
const CONTOUR_NAME := "GrandPlaceCompleteContourRuntime"
const BACKING_CLEARANCE_M := 0.02

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_FACADE_FRONTAGE_MASS_V6_FAIL: " + message)
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
    var v5 := root.get_node_or_null(V5_NAME)
    var v6 := root.get_node_or_null(V6_NAME)
    var contour := root.get_node_or_null(CONTOUR_NAME)
    for _frame: int in range(1200):
        if facade != null and v5 != null and v6 != null and contour != null and bool(facade.get("built")) and bool(v5.get("built")) and bool(v6.get("built")) and bool(contour.get("geometry_loaded")):
            break
        await process_frame
        facade = root.get_node_or_null(FACADE_NAME)
        v5 = root.get_node_or_null(V5_NAME)
        v6 = root.get_node_or_null(V6_NAME)
        contour = root.get_node_or_null(CONTOUR_NAME)
    if facade == null or v5 == null or v6 == null or contour == null:
        _fail("required runtimes missing"); return
    if bool(v6.get("failed")) or not bool(v6.get("built")):
        _fail("V6 did not build"); return
    if int(v6.call("collision_object_count")) != 0 or int(contour.call("active_collision_count")) != 23:
        _fail("collision invariant drifted"); return
    for key: String in ["source_geometry_changed","source_collision_changed","camera_changed","fov_changed","threshold_changed","lateral_endpoint_extension"]:
        if bool(v6.get_meta(key,true)):
            _fail("forbidden mutation: %s" % key); return
    if not bool(v6.get_meta("native_owner_span_only",false)):
        _fail("native owner span rail missing"); return
    if bool(v6.get_meta("dimensions_surveyed",true)) or bool(v6.get_meta("statuary_authored",true)) or bool(v6.get_meta("finished_perfect",true)):
        _fail("forbidden surveyed/statuary/completion claim"); return
    if int(v6.get("cornet_renard_mass_count")) != 8:
        _fail("Cornet/Renard mass accounting drifted: %d" % int(v6.get("cornet_renard_mass_count"))); return
    if int(v6.get("brasseurs_mass_count")) != 5 or int(v6.get("rose_mass_count")) != 6 or int(v6.get("mont_thabor_mass_count")) != 5:
        _fail("contiguous frontage mass accounting drifted"); return
    if int(v6.get("feature_count")) != 24:
        _fail("total feature accounting drifted"); return
    var details := v6.get_node_or_null("GrandPlaceFacadeFrontageMassV6Details") as Node3D
    if details == null:
        _fail("V6 details root missing"); return
    for required_name: String in ["CornetNativeFullWidthBand_0","RenardNativeCrownBand","BrasseursFullWidthEntablature","BrasseursPedimentCrown","RoseFullWidthOrderBand_2","RoseCentralOrderProjection_1","MontThaborFullGableMass_4"]:
        if details.get_node_or_null(required_name) == null:
            _fail("required full-mass node missing: %s" % required_name); return

    # V6 is backing silhouette only. Compare actual outward faces, not centers.
    var brasseurs_owner := facade.get_node_or_null("GrandPlaceFacadePresentationDetails/Facade_1639974_La_Maison_des_Brasseurs") as Node3D
    var reference_order := brasseurs_owner.get_node_or_null("ColossalOrder_1") as MeshInstance3D if brasseurs_owner != null else null
    if reference_order == null:
        _fail("Brasseurs V1 relief reference missing"); return
    var outward := reference_order.global_basis.z.normalized()
    var reference_size := _box_world_size(reference_order)
    var reference_front := reference_order.global_position.dot(outward) + reference_size.z * 0.5
    for mass_name: String in ["BrasseursFullWidthLowerOrder","BrasseursFullWidthEntablature","BrasseursAtticMass","BrasseursPedimentShoulder","BrasseursPedimentCrown"]:
        var mass := details.get_node_or_null(mass_name) as MeshInstance3D
        if mass == null:
            _fail("Brasseurs backing mass missing: %s" % mass_name); return
        if mass.global_basis.z.normalized().dot(outward) < 0.999:
            _fail("Brasseurs backing normal drifted: %s" % mass_name); return
        var mass_size := _box_world_size(mass)
        var mass_front := mass.global_position.dot(outward) + mass_size.z * 0.5
        var clearance := reference_front - mass_front
        if clearance < BACKING_CLEARANCE_M - 0.0001:
            _fail("Brasseurs mass front occludes authored relief: %s clearance=%.4f required=%.4f" % [mass_name,clearance,BACKING_CLEARANCE_M]); return

    var v5_details := v5.get_node_or_null("GrandPlaceFacadeIntegratedRefinementV5Details") as Node3D
    var rose_reference := v5_details.get_node_or_null("RoseIonicCapital_0") as MeshInstance3D if v5_details != null else null
    if rose_reference == null:
        _fail("La Rose V5 authored-order reference missing"); return
    var rose_outward := rose_reference.global_basis.z.normalized()
    var rose_reference_size := _box_world_size(rose_reference)
    var rose_reference_front := rose_reference.global_position.dot(rose_outward) + rose_reference_size.z * 0.5
    for mass_name: String in ["RoseFullWidthOrderBand_0","RoseFullWidthOrderBand_1","RoseFullWidthOrderBand_2","RoseCentralOrderProjection_0","RoseCentralOrderProjection_1","RoseCentralOrderProjection_2"]:
        var mass := details.get_node_or_null(mass_name) as MeshInstance3D
        if mass == null:
            _fail("La Rose backing mass missing: %s" % mass_name); return
        if mass.global_basis.z.normalized().dot(rose_outward) < 0.999:
            _fail("La Rose backing normal drifted: %s" % mass_name); return
        var mass_size := _box_world_size(mass)
        var mass_front := mass.global_position.dot(rose_outward) + mass_size.z * 0.5
        var clearance := rose_reference_front - mass_front
        if clearance < BACKING_CLEARANCE_M - 0.0001:
            _fail("La Rose mass front occludes authored order: %s clearance=%.4f required=%.4f" % [mass_name,clearance,BACKING_CLEARANCE_M]); return

    # RED-first Mont Thabor regression. V5 already owns the documented
    # Gobertange stepped gable. V6 can support its silhouette, but its actual
    # outward faces must remain behind the authored V5 gable rather than cover it.
    var mont_reference := v5_details.get_node_or_null("MontThaborGobertangeGable_0") as MeshInstance3D if v5_details != null else null
    if mont_reference == null:
        _fail("Mont Thabor V5 authored-gable reference missing"); return
    var mont_outward := mont_reference.global_basis.z.normalized()
    var mont_reference_size := _box_world_size(mont_reference)
    var mont_reference_front := mont_reference.global_position.dot(mont_outward) + mont_reference_size.z * 0.5
    for i: int in range(5):
        var mass_name := "MontThaborFullGableMass_%d" % i
        var mass := details.get_node_or_null(mass_name) as MeshInstance3D
        if mass == null:
            _fail("Mont Thabor backing mass missing: %s" % mass_name); return
        if mass.global_basis.z.normalized().dot(mont_outward) < 0.999:
            _fail("Mont Thabor backing normal drifted: %s" % mass_name); return
        var mass_size := _box_world_size(mass)
        var mass_front := mass.global_position.dot(mont_outward) + mass_size.z * 0.5
        var clearance := mont_reference_front - mass_front
        if clearance < BACKING_CLEARANCE_M - 0.0001:
            _fail("Mont Thabor mass front occludes authored gable: %s clearance=%.4f required=%.4f" % [mass_name,clearance,BACKING_CLEARANCE_M]); return

    facade.call("set_presentation_visible",false)
    for _frame: int in range(4): await process_frame
    if details.visible:
        _fail("OFF toggle did not hide V6"); return
    if int(contour.call("active_collision_count")) != 23:
        _fail("OFF toggle changed collisions"); return
    facade.call("set_presentation_visible",true)
    for _frame: int in range(4): await process_frame
    if not details.visible:
        _fail("ON toggle did not restore V6"); return
    print("GRAND_PLACE_FACADE_FRONTAGE_MASS_V6_OK: cornet_renard=8 brasseurs=5 rose=6 mont_thabor=5 features=24 collisions=23 native_owner_span_only=true brasseurs_relief_front_clearance_m=%.2f rose_relief_front_clearance_m=%.2f mont_thabor_relief_front_clearance_m=%.2f" % [BACKING_CLEARANCE_M,BACKING_CLEARANCE_M,BACKING_CLEARANCE_M])
    quit(0)

extends Node3D

const FACADE_NAME := "GrandPlaceFacadePresentationRuntime"
const CORRECTION_V2_NAME := "GrandPlaceFacadePresentationCorrectionV2"
const CONTOUR_NAME := "GrandPlaceCompleteContourRuntime"

var built := false
var failed := false
var _facade: Node = null
var _v2: Node = null
var _contour: Node = null
var _cornet_roof: MeshInstance3D = null
var _renard_roof: MeshInstance3D = null
var _cornet_roof_material: Material = null
var _renard_roof_material: Material = null
var _last_visible := true

func _ready() -> void:
    set_process(false)
    call_deferred("_build_when_ready")

func _fail(message: String) -> void:
    failed = true
    push_error("Grand-Place facade coverage V3: %s" % message)

func _build_when_ready() -> void:
    for _frame: int in range(1000):
        _facade = get_tree().root.get_node_or_null(FACADE_NAME)
        _v2 = get_tree().root.get_node_or_null(CORRECTION_V2_NAME)
        _contour = get_tree().root.get_node_or_null(CONTOUR_NAME)
        if _facade != null and _v2 != null and _contour != null and bool(_facade.get("built")) and bool(_v2.get("built")) and bool(_contour.get("geometry_loaded")):
            break
        await get_tree().process_frame
    if _facade == null or _v2 == null or _contour == null or not bool(_facade.get("built")) or not bool(_v2.get("built")):
        _fail("required facade runtimes not ready")
        return

    var renard_balcony := _facade.get_node_or_null("GrandPlaceFacadePresentationDetails/Facade_1608851_Le_Renard/ContinuousBalconyCue") as MeshInstance3D
    var renard_cornice := _v2.get_node_or_null("GrandPlaceFacadeCorrectionV2Details/RenardCrownV2/ProfiledCorniceCue") as MeshInstance3D
    var renard_left := _v2.get_node_or_null("GrandPlaceFacadeCorrectionV2Details/RenardCrownV2/PedimentShoulderLeft") as MeshInstance3D
    var renard_right := _v2.get_node_or_null("GrandPlaceFacadeCorrectionV2Details/RenardCrownV2/PedimentShoulderRight") as MeshInstance3D
    var cornet_rail := _v2.get_node_or_null("GrandPlaceFacadeCorrectionV2Details/CornetCrownV2/RoofBalustradeRail") as MeshInstance3D
    if renard_balcony == null or renard_cornice == null or renard_left == null or renard_right == null or cornet_rail == null:
        _fail("documented crown/balcony presentation nodes missing")
        return

    # The original balcony cue occupies 86% of the source-derived facade frame.
    # 1.36x yields ~117% of that frame: a bounded presentation overhang, not a
    # source-geometry claim. The same rule is much smaller on the crown rails.
    renard_balcony.scale.x = 1.36
    renard_balcony.scale.z = 3.2
    renard_balcony.set_meta("continuous_balcony_documented", true)
    renard_balcony.set_meta("overhang_dimension_surveyed", false)
    renard_cornice.scale.x = 1.18
    renard_cornice.set_meta("profiled_cornice_documented", true)
    renard_cornice.set_meta("overhang_dimension_surveyed", false)
    cornet_rail.scale.x = 1.18
    cornet_rail.set_meta("roof_balustrade_documented", true)
    cornet_rail.set_meta("overhang_dimension_surveyed", false)

    var left_axis := renard_left.basis.x.normalized()
    var right_axis := renard_right.basis.x.normalized()
    renard_left.position -= left_axis * 0.32
    renard_right.position += right_axis * 0.32
    renard_left.set_meta("volute_wing_offset_surveyed", false)
    renard_right.set_meta("volute_wing_offset_surveyed", false)

    _cornet_roof = _contour.get_node_or_null("GrandPlaceContour_1608847_ROOFSURFACE") as MeshInstance3D
    _renard_roof = _contour.get_node_or_null("GrandPlaceContour_1608851_ROOFSURFACE") as MeshInstance3D
    if _cornet_roof == null or _renard_roof == null:
        _fail("official Cornet/Renard roof mesh missing")
        return

    _cornet_roof_material = _material(
        Color(0.31, 0.24, 0.20, 1.0),
        0.92,
        "Urban 31123 documents slate and tile roof coverings; broad unresolved mix only"
    )
    _cornet_roof_material.set_meta("covering_identity", "slate_and_tile_documented_spatial_mix_unresolved")
    _renard_roof_material = _material(
        Color(0.29, 0.25, 0.22, 1.0),
        0.93,
        "Urban 31124 documents adjoining gable roofs; covering colour authored, material identity not claimed"
    )
    _renard_roof_material.set_meta("covering_material_identity_claimed", false)

    built = true
    set_meta("coverage_revision", 3)
    set_meta("source_geometry_changed", false)
    set_meta("source_collision_changed", false)
    set_meta("camera_changed", false)
    set_meta("threshold_changed", false)
    set_meta("renard_continuous_balcony_documented", true)
    set_meta("renard_volute_wings_documented", true)
    set_meta("cornet_roof_covering_documented", true)
    set_meta("renard_roof_covering_material_claimed", false)
    set_meta("finished_perfect", false)
    _sync_visibility(true)
    set_process(true)
    print("GRAND_PLACE_FACADE_COVERAGE_V3_READY: source_geometry_changed=false collision_changed=false camera_changed=false thresholds_changed=false")

func _material(color: Color, roughness: float, source_label: String) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = roughness
    mat.cull_mode = BaseMaterial3D.CULL_BACK
    mat.set_meta("source_label", source_label)
    mat.set_meta("authored_presentation_only", true)
    mat.set_meta("exact_rgb_is_photometric_measurement", false)
    return mat

func _process(_delta: float) -> void:
    if not built or _facade == null:
        return
    var enabled := bool(_facade.get("presentation_visible"))
    if enabled != _last_visible:
        _sync_visibility(enabled)

func _sync_visibility(enabled: bool) -> void:
    _last_visible = enabled
    if _cornet_roof != null and is_instance_valid(_cornet_roof):
        _cornet_roof.material_override = _cornet_roof_material if enabled else null
        _cornet_roof.set_meta("presentation_identity", "Le Cornet" if enabled else "neutral_unregistered")
    if _renard_roof != null and is_instance_valid(_renard_roof):
        _renard_roof.material_override = _renard_roof_material if enabled else null
        _renard_roof.set_meta("presentation_identity", "Le Renard" if enabled else "neutral_unregistered")

func collision_object_count() -> int:
    return 0

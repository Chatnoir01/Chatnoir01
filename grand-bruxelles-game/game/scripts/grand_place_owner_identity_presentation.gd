extends Node3D

const CONTOUR_RUNTIME_NAME := "GrandPlaceCompleteContourRuntime"
const FOCUS_OWNER_IDS := ["1608847", "1608851"]
const WINDING_DIAGNOSTIC_OWNER_IDS := ["1654360"]
const NEUTRAL_WALL := Color(0.58, 0.56, 0.52, 1.0)
const NEUTRAL_ROOF := Color(0.20, 0.21, 0.22, 1.0)
const MIN_FOCUS_WALL_RGB_DELTA := 0.14
const MIN_FOCUS_ROOF_RGB_DELTA := 0.09
const FOCUS_EMISSION_ENERGY_MULTIPLIER := 0.18
const OWNER_PRESENTATION := {
    "1608847": {"label": "Le Cornet", "stone": Color(0.78, 0.68, 0.50, 1.0), "roof": Color(0.28, 0.20, 0.16, 1.0)},
    "1608851": {"label": "Le Renard", "stone": Color(0.66, 0.54, 0.40, 1.0), "roof": Color(0.14, 0.12, 0.11, 1.0)},
    "1639974": {"label": "Maison des Brasseurs", "stone": Color(0.64, 0.60, 0.52, 1.0), "roof": Color(0.19, 0.18, 0.17, 1.0)},
    "1635485": {"label": "La Rose", "stone": Color(0.73, 0.66, 0.56, 1.0), "roof": Color(0.21, 0.18, 0.17, 1.0)},
    "1646728": {"label": "Le Mont Thabor", "stone": Color(0.70, 0.66, 0.57, 1.0), "roof": Color(0.20, 0.19, 0.18, 1.0)},
    "1654360": {"label": "Maison du Roi", "stone": Color(0.61, 0.60, 0.57, 1.0), "roof": Color(0.16, 0.18, 0.19, 1.0)}
}

var built := false
var failed := false
var owner_surface_count := 0
var _contour: Node = null

func _ready() -> void:
    call_deferred("_apply_when_ready")

func _fail(message: String) -> void:
    failed = true
    push_error("Grand-Place owner identity presentation: %s" % message)

func _rgb_delta(a: Color, b: Color) -> float:
    return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()

func _focus_contrast_is_valid(owner_id: String, facts: Dictionary) -> bool:
    if owner_id not in FOCUS_OWNER_IDS:
        return true
    var wall_delta := _rgb_delta(facts["stone"], NEUTRAL_WALL)
    var roof_delta := _rgb_delta(facts["roof"], NEUTRAL_ROOF)
    if wall_delta < MIN_FOCUS_WALL_RGB_DELTA or roof_delta < MIN_FOCUS_ROOF_RGB_DELTA:
        _fail("focus owner presentation contrast regressed: %s wall=%.3f roof=%.3f" % [owner_id, wall_delta, roof_delta])
        return false
    return true

func _apply_when_ready() -> void:
    for _frame: int in range(1200):
        _contour = get_tree().root.get_node_or_null(CONTOUR_RUNTIME_NAME)
        if _contour != null and bool(_contour.get("geometry_loaded")):
            break
        await get_tree().process_frame
    if _contour == null or not bool(_contour.get("geometry_loaded")):
        _fail("official contour runtime missing or not ready")
        return

    var loaded_ids: Array = _contour.call("get_loaded_owner_ids")
    for owner_id: String in OWNER_PRESENTATION.keys():
        if owner_id not in loaded_ids:
            _fail("exact UrbIS owner missing from official contour: %s" % owner_id)
            return
        var facts: Dictionary = OWNER_PRESENTATION[owner_id]
        if not _focus_contrast_is_valid(owner_id, facts):
            return
        var wall := _contour.get_node_or_null("GrandPlaceContour_%s_WALLSURFACE" % owner_id) as MeshInstance3D
        var roof := _contour.get_node_or_null("GrandPlaceContour_%s_ROOFSURFACE" % owner_id) as MeshInstance3D
        if wall == null or roof == null:
            _fail("official owner surfaces missing: %s" % owner_id)
            return
        _apply_material(wall, owner_id, false)
        _apply_material(roof, owner_id, true)
        owner_surface_count += 2

    if owner_surface_count != OWNER_PRESENTATION.size() * 2:
        _fail("owner surface accounting drifted")
        return

    built = true
    set_meta("source_geometry_changed", false)
    set_meta("source_collision_changed", false)
    set_meta("owner_identity_exact", true)
    set_meta("presentation_dimensions_surveyed", false)
    set_meta("photometric_color_claimed", false)
    set_meta("focus_contrast_guarded", true)
    set_meta("focus_visibility_guarded", true)
    set_meta("source_winding_diagnostic_owner_ids", WINDING_DIAGNOSTIC_OWNER_IDS.duplicate())
    set_meta("source_winding_diagnostic_cull_mode", BaseMaterial3D.CULL_BACK)
    set_meta("source_winding_mitigation_enabled", false)
    set_meta("source_winding_mitigation_production_authorized", false)
    set_meta("finished_perfect", false)
    print("GRAND_PLACE_OWNER_IDENTITY_PRESENTATION_READY owners=%d surfaces=%d geometry_changed=false collisions_changed=false focus_contrast_guarded=true focus_visibility_guarded=true winding_default=cull_back" % [OWNER_PRESENTATION.size(), owner_surface_count])

func _apply_material(surface: MeshInstance3D, owner_id: String, is_roof: bool) -> void:
    var facts: Dictionary = OWNER_PRESENTATION[owner_id]
    var base_color: Color = facts["roof"] if is_roof else facts["stone"]
    var mat := StandardMaterial3D.new()
    mat.albedo_color = base_color
    mat.roughness = 0.90 if is_roof else 0.82
    mat.cull_mode = BaseMaterial3D.CULL_BACK
    if owner_id in FOCUS_OWNER_IDS:
        mat.emission_enabled = true
        mat.emission = base_color
        mat.emission_energy_multiplier = FOCUS_EMISSION_ENERGY_MULTIPLIER
    mat.set_meta("urbis_owner_id", owner_id)
    mat.set_meta("heritage_label", facts["label"])
    mat.set_meta("presentation_only", true)
    mat.set_meta("exact_rgb_is_photometric_measurement", false)
    mat.set_meta("focus_visibility_boost", owner_id in FOCUS_OWNER_IDS)
    mat.set_meta("source_winding_diagnostic_candidate", owner_id in WINDING_DIAGNOSTIC_OWNER_IDS)
    mat.set_meta("source_winding_diagnostic_cull_mode", BaseMaterial3D.CULL_BACK)
    mat.set_meta("source_winding_mitigation_enabled", false)
    surface.material_override = mat
    surface.set_meta("presentation_identity", facts["label"])
    surface.set_meta("source_geometry_unchanged", true)
    surface.set_meta("source_collision_unchanged", true)

func set_source_winding_diagnostic_cull_mode(mode: int) -> bool:
    if not built or _contour == null:
        _fail("source winding diagnostic cull mode requested before presentation readiness")
        return false
    if mode not in [BaseMaterial3D.CULL_BACK, BaseMaterial3D.CULL_FRONT, BaseMaterial3D.CULL_DISABLED]:
        _fail("unsupported source winding diagnostic cull mode: %d" % mode)
        return false
    for owner_id: String in WINDING_DIAGNOSTIC_OWNER_IDS:
        for suffix: String in ["WALLSURFACE", "ROOFSURFACE"]:
            var surface := _contour.get_node_or_null("GrandPlaceContour_%s_%s" % [owner_id, suffix]) as MeshInstance3D
            if surface == null:
                _fail("source winding diagnostic surface missing: %s %s" % [owner_id, suffix])
                return false
            var mat := surface.material_override as StandardMaterial3D
            if mat == null or str(mat.get_meta("urbis_owner_id", "")) != owner_id or not bool(mat.get_meta("source_winding_diagnostic_candidate", false)):
                _fail("source winding diagnostic material ownership drifted: %s %s" % [owner_id, suffix])
                return false
            mat.cull_mode = mode
            mat.set_meta("source_winding_diagnostic_cull_mode", mode)
            mat.set_meta("source_winding_mitigation_enabled", mode == BaseMaterial3D.CULL_DISABLED)
    set_meta("source_winding_diagnostic_cull_mode", mode)
    set_meta("source_winding_mitigation_enabled", mode == BaseMaterial3D.CULL_DISABLED)
    return true

func set_source_winding_mitigation_enabled(enabled: bool) -> bool:
    return set_source_winding_diagnostic_cull_mode(BaseMaterial3D.CULL_DISABLED if enabled else BaseMaterial3D.CULL_BACK)

func collision_object_count() -> int:
    return 0

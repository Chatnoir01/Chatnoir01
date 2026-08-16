extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/bourse_architectural_glazing_surface_runtime.gd")
const EXPECTED_NAMES := ["RearCentralEntry", "RearSideEntry_00", "RearSideEntry_01", "RearOvalLight_00", "RearOvalLight_01"]

func _initialize() -> void:
    var runtime: Node = RUNTIME_SCRIPT.new()
    var valid := _identity("BoursePorticoArticulation", EXPECTED_NAMES)
    if not runtime.call("_runtime_identity_allowed", valid):
        _fail("known-good production target contract rejected")
        return
    var wrong_node := _identity("DifferentBourseNode", EXPECTED_NAMES)
    if runtime.call("_runtime_identity_allowed", wrong_node):
        _fail("runtime_node drift accepted")
        return
    var drifted_names := EXPECTED_NAMES.duplicate()
    drifted_names[4] = "UnrelatedSurface"
    var wrong_surface := _identity("BoursePorticoArticulation", drifted_names)
    if runtime.call("_runtime_identity_allowed", wrong_surface):
        _fail("surface_names drift accepted with unchanged count")
        return
    print("BOURSE_GLAZING_TARGET_CONTRACT_OK")
    runtime.free()
    quit(0)

func _identity(runtime_node: String, surface_names: Array) -> Dictionary:
    return {"schema":"grand-bruxelles-material-identity-v1","target":{"runtime_node":runtime_node,"surface_names":surface_names,"expected_surface_count":5},"presentation_contract":{"material_identity":"architectural_glazing","runtime_approved":true,"geometry_changed":false,"surface_selection_changed":false,"pane_layout_authored":false,"mullions_authored":false,"interior_authored":false,"external_texture_asset":false}}

func _fail(message: String) -> void:
    push_error("BOURSE_GLAZING_TARGET_CONTRACT_FAIL: %s" % message)
    quit(1)

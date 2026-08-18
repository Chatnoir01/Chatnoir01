extends SceneTree

const RUNTIME_NAME := "GrandPlaceTownHallWindowRhythmRuntime"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_TOWN_HALL_WINDOW_CROSS_FAIL: " + message)
    quit(1)

func _run() -> void:
    var runtime := root.get_node_or_null(RUNTIME_NAME)
    if runtime == null:
        _fail("window rhythm runtime missing")
        return
    for _frame: int in range(480):
        await process_frame
        if bool(runtime.get("articulation_ready")):
            break
    if not bool(runtime.get("articulation_ready")):
        _fail("existing window rhythm did not become ready")
        return
    if int(runtime.get("east_bay_count")) != 10 or int(runtime.get("west_bay_count")) != 9:
        _fail("documented bay counts drifted")
        return
    if int(runtime.get("window_register_count")) != 2 or int(runtime.get("window_panel_count")) != 38:
        _fail("existing 19x2 panel rhythm drifted")
        return
    for method_name: String in ["cross_detail_count", "cross_strip_count", "set_cross_detail_visible", "cross_detail_visible", "cross_source_truth"]:
        if not runtime.has_method(method_name):
            _fail("cross-window implementation missing method: " + method_name)
            return
    if int(runtime.call("cross_detail_count")) != 20:
        _fail("expected explicit east-wing 10 bays x 2 registers only")
        return
    if int(runtime.call("cross_strip_count")) != 40:
        _fail("expected 20 mullions + 20 transoms")
        return
    var truth: Dictionary = runtime.call("cross_source_truth")
    if str(truth.get("heritage_record", "")) != "Urban Brussels 31125":
        _fail("heritage record drift")
        return
    if str(truth.get("window_identity", "")) != "fenetres_a_croisee":
        _fail("cross-window source identity drift")
        return
    if str(truth.get("placement_semantics", "")) != "existing_east_window_panels_only":
        _fail("cross details escaped explicit east-wing ownership")
        return
    if str(truth.get("dimensions_source", "")) != "visualization_convention_not_survey_dimensions":
        _fail("dimension truth boundary drift")
        return
    if not bool(truth.get("west_special_ordination_deferred", false)):
        _fail("west-wing exceptions must stay fail-closed")
        return
    if bool(truth.get("dimensions_claimed_surveyed", true)):
        _fail("authored cross dimensions claimed surveyed")
        return
    if bool(truth.get("urbis_mesh_modified", true)) or bool(truth.get("new_openings_authored", true)):
        _fail("official mesh/opening rail drift")
        return
    print("GRAND_PLACE_TOWN_HALL_WINDOW_CROSS_OK: panels=38 east_crosses=20 strips=40 west_deferred=true source=Urban31125 surveyed_dimensions=false")
    quit(0)

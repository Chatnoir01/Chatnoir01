extends SceneTree

const AUTOLOAD := "GrandPlaceTownHallWindowRhythmRuntime"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_TOWN_HALL_WINDOW_RHYTHM_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var runtime := root.get_node_or_null(AUTOLOAD)
    if runtime == null:
        _fail("runtime autoload missing")
        return
    for _frame: int in range(480):
        await process_frame
        if bool(runtime.get("articulation_ready")):
            break
    if not bool(runtime.get("articulation_ready")):
        _fail("articulation did not become ready")
        return
    if int(runtime.get("east_bay_count")) != 10:
        _fail("east wing must preserve documented 10 bays")
        return
    if int(runtime.get("west_bay_count")) != 9:
        _fail("west wing must preserve documented 9 bays")
        return
    if int(runtime.get("window_register_count")) != 2:
        _fail("facade must preserve documented two window registers")
        return
    if int(runtime.get("window_panel_count")) != 38:
        _fail("expected 19 bays x 2 registers = 38 panels")
        return
    if str(runtime.get("placement_semantics")) != "heritage_counts_on_official_lod2_visualization_convention_not_survey":
        _fail("placement provenance must remain explicit")
        return
    if bool(runtime.get("geometry_claimed_surveyed")):
        _fail("decorative articulation must not claim surveyed geometry")
        return
    var official := root.get_node_or_null("GrandPlaceOfficialLod2")
    if official == null or str(official.get_meta("building_id", "")) != "https://databrussels.be/id/building/1655673":
        _fail("official Town Hall LoD2 owner missing")
        return
    print("GRAND_PLACE_TOWN_HALL_WINDOW_RHYTHM_OK: east=10 west=9 registers=2 panels=38 surveyed=false")
    quit(0)

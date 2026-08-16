extends SceneTree

const AUTOLOAD := "GrandPlace1786758ThreeBayRuntime"
const CONTRACT_PATH := "res://data/qa/grand_place_1786758_three_bay_contract.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_1786758_THREE_BAY_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    if not FileAccess.file_exists(CONTRACT_PATH):
        _fail("source contract missing")
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("source contract invalid")
        return
    var contract := parsed as Dictionary
    if str(contract.get("schema", "")) != "grand-bruxelles-grand-place-1786758-three-bay-v1":
        _fail("contract schema drifted")
        return
    if str(contract.get("building_id", "")) != "https://databrussels.be/id/building/1786758":
        _fail("building identity drifted")
        return
    var semantics := contract.get("shared_discrete_semantics", {}) as Dictionary
    if int(semantics.get("main_bay_count", 0)) != 3:
        _fail("heritage contract must preserve three main bays")
        return
    if not bool(semantics.get("central_bay_emphasized", false)):
        _fail("central bay emphasis missing")
        return
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
    if int(runtime.get("bay_count")) != 3:
        _fail("runtime bay count must be three")
        return
    if int(runtime.get("window_register_count")) != 2 or int(runtime.get("window_panel_count")) != 6:
        _fail("expected two bounded registers / six panels")
        return
    if not bool(runtime.get("central_bay_emphasized")):
        _fail("runtime lost central emphasis")
        return
    if bool(runtime.get("geometry_claimed_surveyed")):
        _fail("visualization convention must not claim survey geometry")
        return
    if str(runtime.get("placement_semantics")) != "shared_heritage_three_bay_on_official_wall_face_visualization_convention_not_survey":
        _fail("placement semantics drifted")
        return
    if str(runtime.get_meta("building_id", "")) != "https://databrussels.be/id/building/1786758":
        _fail("runtime building metadata drifted")
        return
    if str(runtime.get_meta("official_wall_face_id", "")) != "https://databrussels.be/id/buildingface/11521730":
        _fail("official wall face provenance drifted")
        return
    if bool(runtime.get_meta("geometry_changed", true)):
        _fail("LoD2 geometry must remain untouched")
        return
    if bool(runtime.get_meta("runtime_approved", true)) or bool(runtime.get_meta("realism_complete", true)):
        _fail("candidate must remain explicitly incomplete")
        return
    print("GRAND_PLACE_1786758_THREE_BAY_OK: bays=3 registers=2 panels=6 central_emphasis=true surveyed=false")
    quit(0)

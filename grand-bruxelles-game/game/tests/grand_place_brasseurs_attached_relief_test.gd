extends SceneTree

const SKIN_AUTOLOAD := "GrandPlaceBrasseursWallSkinRuntime"
const CONTRACT_PATH := "res://data/qa/grand_place_brasseurs_attached_relief_contract.json"
const EXPECTED_COLUMNS := [0.6872, 2.8278, 5.2337, 7.6396]

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_BRASSEURS_ATTACHED_RELIEF_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    if not FileAccess.file_exists(CONTRACT_PATH):
        _fail("attached relief contract missing")
        return
    var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
    if not (raw is Dictionary):
        _fail("attached relief contract malformed")
        return
    var c := raw as Dictionary
    if str(c.get("building_id", "")) != "1639974": _fail("building drifted"); return
    if str(c.get("front_wall_id", "")) != "10945501": _fail("wall drifted"); return
    if int(c.get("bay_count", 0)) != 3: _fail("three-bay identity missing"); return
    if int(c.get("column_count", 0)) != 4: _fail("four-column photo rhythm missing"); return
    if c.get("column_center_offsets_m", []) != EXPECTED_COLUMNS: _fail("column axes drifted"); return
    if not bool(c.get("central_bay_projection", false)): _fail("central bay projection missing"); return
    if str(c.get("attachment_policy", "")) != "all_relief_children_of_coherent_skin_runtime_and_within_official_wall_envelope": _fail("attachment policy missing"); return
    if bool(c.get("free_standing_grid_allowed", true)): _fail("free-standing grid must remain forbidden"); return
    if bool(c.get("raw_photo_pixels_shipped", true)): _fail("raw photo pixels forbidden"); return
    if bool(c.get("exact_depths_claimed_surveyed", true)): _fail("depths must remain presentation conventions"); return
    if bool(c.get("curved_pediment_geometry_in_this_lot", true)): _fail("pediment is intentionally deferred"); return

    var skin := root.get_node_or_null(SKIN_AUTOLOAD)
    if skin == null:
        _fail("coherent skin prerequisite missing")
        return
    for _i: int in range(480):
        await process_frame
        if bool(skin.get("skin_ready")): break
    if not bool(skin.get("skin_ready")): _fail("coherent skin prerequisite not ready"); return
    if not bool(skin.get("relief_ready")):
        _fail("red-first witness: attached Brasseurs relief missing")
        return
    if int(skin.get("relief_column_count")) != 4: _fail("runtime must expose four attached half-columns"); return
    if int(skin.get("relief_bay_count")) != 3: _fail("runtime must expose three-bay hierarchy"); return
    if int(skin.get("attached_relief_count")) < 5: _fail("runtime relief hierarchy incomplete"); return
    if bool(skin.get("free_standing_grid_present")): _fail("free-standing grid reintroduced"); return
    if not bool(skin.get("all_relief_attached_to_skin")): _fail("relief detached from coherent skin"); return
    if bool(skin.get("raw_photo_pixels_shipped")): _fail("runtime shipped source pixels"); return
    if bool(skin.get("geometry_claimed_surveyed")): _fail("runtime overclaims survey accuracy"); return
    print("GRAND_PLACE_BRASSEURS_ATTACHED_RELIEF_OK: bays=3 columns=4 attached=true free_grid=false")
    quit(0)

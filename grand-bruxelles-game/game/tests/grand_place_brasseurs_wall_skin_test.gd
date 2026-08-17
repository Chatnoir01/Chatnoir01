extends SceneTree

const AUTOLOAD := "GrandPlaceBrasseursWallSkinRuntime"
const CONTRACT_PATH := "res://data/qa/grand_place_brasseurs_wall_skin_contract.json"
const EXPECTED_BUILDING := "1639974"
const EXPECTED_WALL := "10945501"
const EXPECTED_TRIANGLES := 3
const EXPECTED_SPAN := 8.7490357183
const EXPECTED_VERTICES := [
    [317.9358, 0.0, -487.4869],
    [317.9358, 19.166, -487.4869],
    [321.6678, 24.746, -485.7699],
    [325.8848, 0.0, -483.8319],
    [325.8848, 18.966, -483.8319]
]

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_BRASSEURS_WALL_SKIN_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    if not FileAccess.file_exists(CONTRACT_PATH):
        _fail("official wall skin contract missing")
        return
    var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
    if not (raw is Dictionary):
        _fail("wall skin contract malformed")
        return
    var c := raw as Dictionary
    if str(c.get("building_id", "")) != EXPECTED_BUILDING: _fail("building identity drifted"); return
    if str(c.get("front_wall_id", "")) != EXPECTED_WALL: _fail("wall identity drifted"); return
    if int(c.get("triangle_count", 0)) != EXPECTED_TRIANGLES: _fail("official wall must remain exactly 3 triangles"); return
    if abs(float(c.get("horizontal_span_m", 0.0)) - EXPECTED_SPAN) > 0.000001: _fail("official span drifted"); return
    if str(c.get("surface_policy", "")) != "one_continuous_official_wall_skin_before_relief": _fail("coherent-skin policy missing"); return
    if bool(c.get("free_standing_architectural_grid_allowed", true)): _fail("free-standing grid must remain forbidden"); return
    if bool(c.get("detail_relief_allowed_before_skin_ready", true)): _fail("relief must not precede coherent skin"); return
    if bool(c.get("raw_photo_pixels_shipped", true)): _fail("raw Commons pixels forbidden"); return
    if bool(c.get("photo_geometry_claimed_surveyed", true)): _fail("photo geometry must not claim survey accuracy"); return
    var verts: Array = c.get("world_vertices", [])
    if verts != EXPECTED_VERTICES: _fail("official wall vertices drifted"); return

    var runtime := root.get_node_or_null(AUTOLOAD)
    if runtime == null:
        _fail("red-first witness: coherent Brasseurs wall skin runtime missing")
        return
    for _i: int in range(480):
        await process_frame
        if bool(runtime.get("skin_ready")): break
    if not bool(runtime.get("skin_ready")): _fail("coherent wall skin did not become ready"); return
    if str(runtime.get("building_id")) != EXPECTED_BUILDING: _fail("runtime building drifted"); return
    if str(runtime.get("source_wall_id")) != EXPECTED_WALL: _fail("runtime wall drifted"); return
    if int(runtime.get("official_triangle_count")) != EXPECTED_TRIANGLES: _fail("runtime must expose exactly 3 official triangles"); return
    if abs(float(runtime.get("official_span_m")) - EXPECTED_SPAN) > 0.000001: _fail("runtime span drifted"); return
    if int(runtime.get("skin_surface_count")) != 1: _fail("runtime must expose one coherent facade skin"); return
    if int(runtime.get("detail_count")) != 0: _fail("skin lot must not smuggle architectural relief"); return
    if bool(runtime.get("free_standing_grid_present")): _fail("free-standing grid detected"); return
    if bool(runtime.get("geometry_claimed_surveyed")): _fail("presentation skin must not overclaim survey accuracy"); return
    print("GRAND_PLACE_BRASSEURS_WALL_SKIN_OK: building=1639974 wall=10945501 triangles=3 surfaces=1 details=0 span=8.749036")
    quit(0)

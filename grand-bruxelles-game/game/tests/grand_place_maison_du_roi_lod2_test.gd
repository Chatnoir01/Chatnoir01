extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const AUTOLOAD_NAME := "GrandPlaceMaisonDuRoiOfficialLod2"
const BUILDING_ID := "https://databrussels.be/id/building/1654360"
const PACKAGE_SHA256 := "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2"
const CITY_TOTAL_HEIGHT_M := 38.0
const LOD2_HEIGHT_M := 30.387
const EXPECTED_RENDER_TRIANGLES := 213

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    print("GRAND_PLACE_MAISON_DU_ROI_LOD2_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var root := get_root().get_node_or_null(AUTOLOAD_NAME)
    if root == null:
        _fail("Maison du Roi official LoD2 autoload missing")
        return

    for _frame: int in range(360):
        await process_frame
        if current_scene != null and current_scene.scene_file_path == MAIN_SCENE and bool(root.get("geometry_loaded")):
            break

    if not bool(root.get("geometry_loaded")):
        _fail("Maison du Roi official geometry did not load")
        return
    if str(root.get_meta("building_id", "")) != BUILDING_ID:
        _fail("building identity drifted")
        return
    if str(root.get_meta("package_sha256", "")) != PACKAGE_SHA256:
        _fail("UrbIS package digest drifted")
        return
    if int(root.get("render_triangle_count")) != EXPECTED_RENDER_TRIANGLES:
        _fail("expected 213 WALLSURFACE+ROOFSURFACE triangles, got %d" % int(root.get("render_triangle_count")))
        return
    if absf(float(root.get_meta("city_total_height_m", 0.0)) - CITY_TOTAL_HEIGHT_M) > 0.001:
        _fail("official City total height contract drifted")
        return
    if absf(float(root.get_meta("lod2_height_m", 0.0)) - LOD2_HEIGHT_M) > 0.001:
        _fail("official LoD2 height contract drifted")
        return
    if bool(root.get_meta("vertical_completeness", true)):
        _fail("LoD2 must remain explicitly vertically incomplete")
        return
    if bool(root.get_meta("geometry_rescaled", true)):
        _fail("official LoD2 geometry must not be rescaled to City height")
        return
    if bool(root.get_meta("openings_authored", true)):
        _fail("no openings may be authored on the coarse LoD2")
        return
    if bool(root.get_meta("runtime_approved", true)) or bool(root.get_meta("realism_complete", true)):
        _fail("coarse LoD2 must remain non-approved/incomplete")
        return
    if not bool(root.get_meta("official_collision_completed", false)):
        _fail("official wall collision missing")
        return

    print("GRAND_PLACE_MAISON_DU_ROI_LOD2_OK: building=1654360 render_triangles=213 city_height=38.0 lod2_height=30.387 vertically_complete=false")
    quit(0)

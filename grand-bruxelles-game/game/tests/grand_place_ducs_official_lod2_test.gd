extends SceneTree

const AUTOLOAD := "GrandPlaceDucsOfficialLod2"
const BUILDING_ID := "https://databrussels.be/id/building/1640085"
const PACKAGE_SHA256 := "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_DUCS_LOD2_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var runtime := root.get_node_or_null(AUTOLOAD)
    if runtime == null:
        _fail("runtime autoload missing")
        return
    for _frame: int in range(480):
        await process_frame
        if bool(runtime.get("geometry_loaded")):
            break
    if not bool(runtime.get("geometry_loaded")):
        _fail("official Ducs geometry did not load")
        return
    if str(runtime.get_meta("building_id", "")) != BUILDING_ID:
        _fail("official building identity drifted")
        return
    if str(runtime.get_meta("package_sha256", "")) != PACKAGE_SHA256:
        _fail("UrbIS3D package digest drifted")
        return
    if int(runtime.get_meta("source_solid_count", 0)) != 2:
        _fail("expected two official source solids")
        return
    if int(runtime.get_meta("source_face_count", 0)) != 146:
        _fail("expected 146 official source faces")
        return
    if int(runtime.get_meta("source_triangle_count", 0)) != 476:
        _fail("expected 476 official source triangles")
        return
    if int(runtime.get_meta("source_wall_face_count", 0)) != 93:
        _fail("expected 93 WALLSURFACE faces")
        return
    if int(runtime.get_meta("source_roof_face_count", 0)) != 51:
        _fail("expected 51 ROOFSURFACE faces")
        return
    if int(runtime.get_meta("source_ground_face_count", 0)) != 2:
        _fail("expected two GROUNDSURFACE faces")
        return
    if int(runtime.get("render_triangle_count")) != 441:
        _fail("runtime must render exact wall+roof triangles only")
        return
    if abs(float(runtime.get("source_height_m")) - 26.999) > 0.002:
        _fail("source LoD2 height drifted")
        return
    if int(runtime.get_meta("city_house_count", 0)) != 7:
        _fail("seven City Ducs records must resolve to this one official building")
        return
    if int(runtime.get_meta("heritage_bay_count", 0)) != 19:
        _fail("heritage common facade must retain documented 19-bay identity")
        return
    if str(runtime.get_meta("placement_semantics", "")) != "official_lod2_with_heritage_identity_no_surveyed_openings":
        _fail("placement semantics must not overclaim surveyed openings")
        return
    if bool(runtime.get_meta("openings_authored", true)):
        _fail("this lot must not invent facade openings")
        return
    if bool(runtime.get_meta("runtime_approved", true)) or bool(runtime.get_meta("realism_complete", true)):
        _fail("candidate must remain explicitly provisional")
        return
    if not bool(runtime.get_meta("official_collision_completed", false)):
        _fail("official wall collision missing")
        return
    print("GRAND_PLACE_DUCS_LOD2_OK: building=1640085 solids=2 faces=146 source_triangles=476 render_triangles=441 houses=7 bays=19 runtime_approved=false")
    quit(0)

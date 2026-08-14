extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const BEFORE_PATH := "res://artifacts/ixelles/ixelles_identity_before_1280x720.png"
const AFTER_PATH := "res://artifacts/ixelles/ixelles_identity_after_1280x720.png"
const EXPECTED_CELL_ID := "bxl-e149000-n169000-s500"
const EXPECTED_STREET_SURFACES := 309
const EXPECTED_STREET_AXES := 277
const EXPECTED_BUILDINGS := 260
const EXPECTED_SKIPPED_BUILDINGS := 460
const EXPECTED_ANCHOR := Vector3(735.808, 0.0, 926.900)
const ANCHOR_XZ_TOLERANCE_M := 0.001
const MIN_CHANGED_PIXELS := 300
const PIXEL_DELTA_THRESHOLD := 8.0 / 255.0
const WIDTH := 1280
const HEIGHT := 720

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("IXELLES_BILINGUAL_JUNCTION_SIGN_FAIL: %s" % message)
    quit(1)

func _capture(path: String) -> Image:
    for _frame: int in range(8):
        await process_frame
    RenderingServer.force_draw()
    await process_frame
    var image := root.get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        return null
    var absolute := ProjectSettings.globalize_path(path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    if image.save_png(absolute) != OK:
        return null
    return image

func _changed_pixels(before: Image, after: Image) -> int:
    var changed := 0
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) > PIXEL_DELTA_THRESHOLD:
                changed += 1
    return changed

func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    await process_frame

    var player := main.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        _fail("player missing")
        return
    player.call("_apply_direct_spawn_from_user_args", PackedStringArray(["spawn=ixelles"]))
    for _frame: int in range(12):
        await process_frame

    var slice := main.get_node_or_null("IxellesDirectMicroSlice")
    if slice == null or not bool(slice.get("runtime_loaded")):
        _fail("Ixelles direct micro-slice unavailable")
        return
    if str(slice.get("cell_id")) != EXPECTED_CELL_ID:
        _fail("cell id drifted")
        return
    if int(slice.get("street_surface_count")) != EXPECTED_STREET_SURFACES or int(slice.get("street_segment_count")) != EXPECTED_STREET_AXES:
        _fail("street invariants drifted")
        return
    if int(slice.get("building_count")) != EXPECTED_BUILDINGS or int(slice.get("skipped_unapproved_height_buildings")) != EXPECTED_SKIPPED_BUILDINGS:
        _fail("strong-height/no-invention invariants drifted")
        return
    if not bool(slice.get("identity_cue_built")) or int(slice.get("identity_cue_plaque_count")) != 2:
        _fail("bilingual junction cue did not build")
        return
    if bool(slice.get("identity_cue_mount_surveyed")):
        _fail("presentation mount must not claim surveyed placement")
        return

    var cue := slice.get_node_or_null("IxellesBilingualJunctionCue") as Node3D
    if cue == null:
        _fail("identity cue node missing")
        return
    if str(cue.get_meta("source_axis_stassart", "")) != "https://databrussels.be/id/streetaxe/71374:2":
        _fail("Rue de Stassart source axis drifted")
        return
    if str(cue.get_meta("source_axis_stephanie", "")) != "https://databrussels.be/id/streetaxe/71306:2":
        _fail("Place Stephanie source axis drifted")
        return
    var endpoint: Variant = cue.get_meta("source_shared_endpoint", Vector2(INF, INF))
    if not endpoint is Vector2 or (endpoint as Vector2).distance_to(Vector2(EXPECTED_ANCHOR.x, EXPECTED_ANCHOR.z)) > ANCHOR_XZ_TOLERANCE_M:
        _fail("authoritative shared junction endpoint drifted")
        return

    var stassart := cue.get_node_or_null("RueDeStassartPlaque")
    var stephanie := cue.get_node_or_null("PlaceStephaniePlaque")
    if stassart == null or stephanie == null:
        _fail("expected bilingual plaques missing")
        return
    if str(stassart.get("display_french")) != "RUE DE STASSART" or str(stassart.get("display_dutch")) != "DE STASSARTSTRAAT":
        _fail("Rue de Stassart bilingual plaque text drifted")
        return
    if str(stephanie.get("display_french")) != "PLACE STÉPHANIE" or str(stephanie.get("display_dutch")) != "STEFANIAPLEIN":
        _fail("Place Stephanie bilingual plaque text drifted")
        return

    var anchor: Vector3 = slice.get("identity_cue_anchor")
    if Vector2(anchor.x, anchor.z).distance_to(Vector2(EXPECTED_ANCHOR.x, EXPECTED_ANCHOR.z)) > ANCHOR_XZ_TOLERANCE_M:
        _fail("runtime identity anchor drifted")
        return

    cue.visible = false
    var before := await _capture(BEFORE_PATH)
    if before == null:
        _fail("before capture failed")
        return
    cue.visible = true
    var after := await _capture(AFTER_PATH)
    if after == null:
        _fail("after capture failed")
        return

    var changed := _changed_pixels(before, after)
    if changed < MIN_CHANGED_PIXELS:
        _fail("identity cue is too small in the accepted direct player frame: changed_pixels=%d" % changed)
        return

    print("IXELLES_BILINGUAL_JUNCTION_SIGN_OK: anchor=(%.3f,%.3f,%.3f) plaques=%d changed_pixels=%d before=%s after=%s" % [anchor.x, anchor.y, anchor.z, int(slice.get("identity_cue_plaque_count")), changed, BEFORE_PATH, AFTER_PATH])
    quit(0)

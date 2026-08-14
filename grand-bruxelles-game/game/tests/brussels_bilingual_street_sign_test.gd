extends SceneTree

const SIGN_SCRIPT := preload("res://game/scripts/brussels_bilingual_street_sign.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_BILINGUAL_STREET_SIGN_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var sign := SIGN_SCRIPT.new()
    sign.french_name = "RUE DE LA BOURSE"
    sign.dutch_name = "BEURSSTRAAT"
    root.add_child(sign)
    await process_frame

    if not bool(sign.get("visual_built")):
        _fail("visual did not build")
        return
    if int(sign.get("plaque_count")) != 1:
        _fail("expected exactly one plaque")
        return
    if int(sign.get("language_line_count")) != 2:
        _fail("street plaque must expose exactly two language lines")
        return
    if str(sign.get("display_french")) != "RUE DE LA BOURSE":
        _fail("French street name drifted")
        return
    if str(sign.get("display_dutch")) != "BEURSSTRAAT":
        _fail("Dutch street name drifted")
        return
    if not bool(sign.get("authored_geometry")):
        _fail("authored-geometry disclaimer missing")
        return
    if bool(sign.get("claims_surveyed_mount")):
        _fail("reusable plaque must not claim surveyed placement")
        return

    print("BRUSSELS_BILINGUAL_STREET_SIGN_OK: plaque=1 language_lines=2 fr=%s nl=%s" % [str(sign.get("display_french")), str(sign.get("display_dutch"))])
    quit(0)

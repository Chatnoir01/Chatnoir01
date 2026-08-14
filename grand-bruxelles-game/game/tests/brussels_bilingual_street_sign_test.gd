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

    var french_label := sign.get_node_or_null("FrenchStreetName") as Label3D
    var dutch_label := sign.get_node_or_null("DutchStreetName") as Label3D
    if french_label == null or dutch_label == null:
        _fail("bilingual labels missing")
        return
    if french_label.position.z >= -0.025 or dutch_label.position.z >= -0.025:
        _fail("labels must sit on the authored -Z readable panel face")
        return
    if absf(absf(french_label.rotation_degrees.y) - 180.0) > 0.01:
        _fail("French label must face out from the -Z panel face")
        return
    if absf(absf(dutch_label.rotation_degrees.y) - 180.0) > 0.01:
        _fail("Dutch label must face out from the -Z panel face")
        return

    print("BRUSSELS_BILINGUAL_STREET_SIGN_OK: plaque=1 language_lines=2 fr=%s nl=%s readable_face=-Z" % [str(sign.get("display_french")), str(sign.get("display_dutch"))])
    quit(0)

extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const ZONE_ID := "nord_machine_labo"
const EXPECTED_TOGGLE_TEXT := "CHANGER DE ZONE"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("NORD_ZONE_SELECTOR_BUTTON_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    if change_scene_to_file(MAIN_SCENE) != OK:
        _fail("main scene load failed")
        return

    var selector: Node = null
    for _attempt: int in range(360):
        await process_frame
        selector = root.get_node_or_null("ZoneSelectorRuntime")
        if selector != null and current_scene != null and current_scene.get_node_or_null("Player") != null:
            break
    if selector == null:
        _fail("ZoneSelectorRuntime autoload unavailable")
        return

    var toggle := selector.get_node_or_null("ZoneSelectorToggle") as Button
    var panel := selector.get_node_or_null("ZoneSelectorPanel") as PanelContainer
    if toggle == null or panel == null:
        _fail("production zone-change controls missing")
        return
    if toggle.text != EXPECTED_TOGGLE_TEXT:
        _fail("zone-change toggle label drifted: %s" % toggle.text)
        return
    if toggle.size.x < 160.0:
        _fail("zone-change toggle too narrow for explicit label")
        return

    selector.call("set_menu_open", true)
    await process_frame
    if not panel.visible:
        _fail("zone-change panel did not open")
        return

    var nord_button := selector.find_child("Zone_%s" % ZONE_ID, true, false) as Button
    if nord_button == null:
        _fail("Gare du Nord button missing from production zone menu")
        return
    if not nord_button.text.contains("Gare du Nord") or not nord_button.text.contains("LABO"):
        _fail("Gare du Nord button lost label/quality truth")
        return

    nord_button.pressed.emit()

    var loaded := false
    for _attempt: int in range(360):
        await process_frame
        if current_scene == null:
            continue
        var lab := current_scene.get_node_or_null("ZoneLab_%s" % ZONE_ID)
        var active_id := str(current_scene.get_meta("grand_bruxelles_active_zone_id", ""))
        if lab != null and active_id == ZONE_ID:
            loaded = true
            break
    if not loaded:
        _fail("clicking the production Nord button did not mount Nord")
        return

    print("NORD_ZONE_SELECTOR_BUTTON_OK toggle=%s nord_button=true quality=LABO click_mount=true" % toggle.text)
    quit(0)

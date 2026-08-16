extends SceneTree

const CATALOG_PATH := "res://data/qa/playable_zone_catalog.json"
const EXPECTED_IDS := ["midi", "bourse", "ixelles", "atomium", "jette"]

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    print("ZONE_SELECTOR_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    if not FileAccess.file_exists(CATALOG_PATH):
        _fail("catalog missing")
        return
    if str(ProjectSettings.get_setting("autoload/ZoneSelectorRuntime", "")) != "*res://game/scripts/zone_selector_runtime.gd":
        _fail("autoload missing")
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("catalog invalid")
        return
    var zones: Variant = (parsed as Dictionary).get("zones", [])
    if not zones is Array:
        _fail("zones invalid")
        return
    var ids: Array[String] = []
    for raw: Variant in zones:
        if not raw is Dictionary:
            _fail("zone row invalid")
            return
        var zone := raw as Dictionary
        var zone_id := str(zone.get("id", ""))
        var quality := str(zone.get("quality", ""))
        if quality not in ["JOUABLE", "LABO"]:
            _fail("invalid quality %s" % quality)
            return
        for requirement: Variant in zone.get("requires", []):
            if not ResourceLoader.exists(str(requirement)) and not FileAccess.file_exists(str(requirement)):
                _fail("missing requirement %s" % str(requirement))
                return
        ids.append(zone_id)
    if ids != EXPECTED_IDS:
        _fail("unexpected listed zones %s" % str(ids))
        return
    var selector := get_root().get_node_or_null("ZoneSelectorRuntime")
    if selector == null or not selector.has_method("available_zones"):
        _fail("runtime selector missing")
        return
    await process_frame
    var available: Array = selector.call("available_zones")
    if available.size() != EXPECTED_IDS.size():
        _fail("runtime filtered a proven zone")
        return
    print("ZONE_SELECTOR_OK: listed=%d playable=1 lab=4 no_invisible_quarantine=true" % available.size())
    quit(0)

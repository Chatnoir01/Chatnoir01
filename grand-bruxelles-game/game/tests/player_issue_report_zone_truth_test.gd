extends SceneTree

const SELECTOR_SCRIPT := preload("res://game/scripts/zone_selector_runtime.gd")

class FakeLocationLabel:
    extends Label
    func get_current_location_text() -> String:
        return text

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("PLAYER_ISSUE_REPORT_ZONE_TRUTH_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var selector := SELECTOR_SCRIPT.new()
    root.add_child(selector)
    await process_frame

    selector.set("_active_zone_id", "jette")
    var fake_main := Node3D.new()
    var location := FakeLocationLabel.new()
    location.name = "LocationLabel"
    location.text = "Bourse"
    fake_main.add_child(location)

    var inferred := str(selector.call("_infer_active_zone_id", fake_main))
    if inferred != "jette":
        _fail("active Jette was overwritten by stale LocationLabel: %s" % inferred)
        return

    var zone: Dictionary = selector.call("_zone_by_id", inferred)
    if str(zone.get("label", "")) != "Jette":
        _fail("canonical report header did not resolve to Jette")
        return

    print("PLAYER_ISSUE_REPORT_ZONE_TRUTH_OK: active=jette stale_header=Bourse resolved_id=%s resolved_label=%s" % [inferred, str(zone.get("label", ""))])
    quit(0)

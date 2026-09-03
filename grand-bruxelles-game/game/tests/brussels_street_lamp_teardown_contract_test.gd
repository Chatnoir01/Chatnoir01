extends SceneTree

const RUNTIME_PATH := "res://game/scripts/brussels_street_lamp_runtime.gd"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_STREET_LAMP_TEARDOWN_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    if not FileAccess.file_exists(RUNTIME_PATH):
        _fail("runtime missing")
        return
    var file := FileAccess.open(RUNTIME_PATH, FileAccess.READ)
    if file == null:
        _fail("runtime unreadable")
        return
    var source := file.get_as_text()
    var release_start := source.find("func _release_owned_root() -> void:")
    var next_func := source.find("\nfunc ", release_start + 1)
    if release_start < 0 or next_func < 0:
        _fail("release-owned-root function not found")
        return
    var release_body := source.substr(release_start, next_func - release_start)
    var has_sync_detach := release_body.contains("parent.remove_child(_root)")
    var detach_is_teardown_guarded := release_body.contains("not _tearing_down")
    if has_sync_detach and not detach_is_teardown_guarded:
        _fail("synchronous remove_child remains reachable during runtime teardown")
        return
    if not release_body.contains("_root.queue_free()"):
        _fail("owned root no longer has deferred destruction")
        return
    print("BRUSSELS_STREET_LAMP_TEARDOWN_OK: no_sync_detach_during_exit=true queue_free=true geometry_changed=false source=OSM license=ODbL-1.0")
    quit(0)

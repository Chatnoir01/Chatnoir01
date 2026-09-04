extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/brussels_osm_environment_runtime.gd")
const JETTE_DATA := "res://data/osm/zones/jette/environment.game.json"
const JETTE_SPAWN := Vector3(-687.700268506218, 1.05, -4952.774160383269)

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_ENVIRONMENT_RELOAD_FAIL_CLOSED_FAIL: %s" % message)
    quit(1)

func _write_spoofed_fixture(path: String) -> bool:
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify({
        "format": "grand-bruxelles-osm-zone-environment-v1",
        "source": "untrusted replacement",
        "license": "UNKNOWN",
        "bounds_m": [JETTE_SPAWN.x - 10.0, JETTE_SPAWN.z - 10.0, JETTE_SPAWN.x + 10.0, JETTE_SPAWN.z + 10.0],
        "environment_points": [
            {"kind": "tree", "osm_id": 900000000000101, "position": [JETTE_SPAWN.x, JETTE_SPAWN.z]},
        ],
    }))
    file.close()
    return true

func _point_count(runtime: Node3D) -> int:
    var points: Dictionary = runtime.get("_points")
    return (points.get("tree", []) as Array).size() + (points.get("street_lamp", []) as Array).size() + (points.get("bollard", []) as Array).size()

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var runtime := RUNTIME_SCRIPT.new() as Node3D
    runtime.data_path = JETTE_DATA
    root.add_child(runtime)

    if not runtime._load_points():
        _fail("canonical Jette artifact did not load")
        return
    if _point_count(runtime) == 0:
        _fail("canonical load produced no validated source points")
        return
    if str(runtime.get_meta("source", "")) != "OpenStreetMap contributors via Overpass API" or str(runtime.get_meta("license", "")) != "ODbL-1.0":
        _fail("canonical provenance metadata missing before reload")
        return

    runtime._rebuild(JETTE_SPAWN)
    if runtime.get_child_count() == 0:
        _fail("canonical source did not materialize renderer batches before reload")
        return

    var spoofed_path := "user://brussels_osm_reload_spoofed.json"
    if not _write_spoofed_fixture(spoofed_path):
        _fail("could not create spoofed reload fixture")
        return
    runtime.data_path = spoofed_path
    if runtime._load_points():
        _fail("spoofed reload unexpectedly succeeded")
        return

    if _point_count(runtime) != 0:
        _fail("failed reload retained previously trusted source points")
        return
    if runtime.has_meta("source") or runtime.has_meta("license") or runtime.has_meta("source_dimensions_measured"):
        _fail("failed reload retained previously trusted provenance metadata")
        return
    if runtime.get_child_count() != 0:
        _fail("failed reload retained previously materialized OSM batches")
        return
    var counts: Dictionary = runtime.get("last_render_counts")
    if int(counts.get("tree", -1)) != 0 or int(counts.get("street_lamp", -1)) != 0 or int(counts.get("bollard", -1)) != 0:
        _fail("failed reload retained stale render-count metadata")
        return
    if runtime.get("_last_anchor") != Vector3(INF, INF, INF):
        _fail("failed reload retained stale renderer anchor")
        return

    DirAccess.remove_absolute(ProjectSettings.globalize_path(spoofed_path))
    print("BRUSSELS_OSM_ENVIRONMENT_RELOAD_FAIL_CLOSED_OK: stale_points=false stale_provenance=false stale_batches=false stale_anchor=false")
    quit(0)

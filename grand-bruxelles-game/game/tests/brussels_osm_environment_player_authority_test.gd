extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/brussels_osm_environment_runtime.gd")
const JETTE_DATA := "res://data/osm/zones/jette/environment.game.json"
const JETTE_SPAWN := Vector3(-687.700268506218, 1.05, -4952.774160383269)
const STALE_SPAWN := Vector3(12000.0, 1.05, 12000.0)

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_ENVIRONMENT_PLAYER_AUTHORITY_FAIL: %s" % message)
    quit(1)

func _all_batches_visible(runtime: Node3D, expected: bool) -> bool:
    var seen := 0
    for child: Node in runtime.get_children():
        if child is MultiMeshInstance3D:
            seen += 1
            if (child as MultiMeshInstance3D).visible != expected:
                return false
    return seen > 0

func _first_batch_instance_id(runtime: Node3D) -> int:
    for child: Node in runtime.get_children():
        if child is MultiMeshInstance3D:
            return child.get_instance_id()
    return 0

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    if current_scene != null:
        _fail("script witness requires current_scene == null before setup")
        return

    var stale_world := Node3D.new()
    stale_world.name = "StaleWorld"
    root.add_child(stale_world)

    var stale_player := Node3D.new()
    stale_player.name = "Player"
    stale_player.add_to_group("player")
    stale_player.position = STALE_SPAWN
    stale_world.add_child(stale_player)

    var live_world := Node3D.new()
    live_world.name = "Main"
    root.add_child(live_world)
    current_scene = live_world

    var live_player := Node3D.new()
    live_player.name = "Player"
    live_player.add_to_group("player")
    live_player.position = JETTE_SPAWN
    live_world.add_child(live_player)

    var spoofed_path := "user://brussels_osm_spoofed_provenance.json"
    var spoofed_file := FileAccess.open(spoofed_path, FileAccess.WRITE)
    if spoofed_file == null:
        _fail("could not create spoofed provenance regression artifact")
        return
    spoofed_file.store_string(JSON.stringify({
        "format": "grand-bruxelles-osm-zone-environment-v1",
        "source": "untrusted replacement",
        "license": "UNKNOWN",
        "environment_points": [
            {"kind": "tree", "osm_id": 1, "position": [JETTE_SPAWN.x, JETTE_SPAWN.z]},
        ],
    }))
    spoofed_file.close()
    var spoofed_runtime := RUNTIME_SCRIPT.new() as Node3D
    spoofed_runtime.name = "BrusselsOsmEnvironmentSpoofedProvenanceProbe"
    spoofed_runtime.set("data_path", spoofed_path)
    live_world.add_child(spoofed_runtime)
    for _frame: int in range(4):
        await process_frame
    if spoofed_runtime.is_processing():
        _fail("spoofed OSM source/license did not disable shared OSM processing")
        return
    if spoofed_runtime.get_child_count() != 0:
        _fail("spoofed OSM source/license materialized render batches")
        return
    if spoofed_runtime.has_meta("source") or spoofed_runtime.has_meta("license"):
        _fail("spoofed OSM source/license was accepted as runtime provenance")
        return
    spoofed_runtime.queue_free()
    await process_frame
    DirAccess.remove_absolute(ProjectSettings.globalize_path(spoofed_path))

    var invalid_runtime := RUNTIME_SCRIPT.new() as Node3D
    invalid_runtime.name = "BrusselsOsmEnvironmentInvalidConfigProbe"
    invalid_runtime.set("data_path", JETTE_DATA)
    invalid_runtime.set("refresh_distance_m", -1.0)
    live_world.add_child(invalid_runtime)
    for _frame: int in range(4):
        await process_frame
    if invalid_runtime.is_processing():
        _fail("negative refresh_distance_m did not disable shared OSM processing")
        return
    if invalid_runtime.get_child_count() != 0:
        _fail("invalid shared OSM configuration materialized render batches")
        return
    if invalid_runtime.has_meta("source") or invalid_runtime.has_meta("license"):
        _fail("invalid shared OSM configuration accepted source provenance")
        return
    invalid_runtime.queue_free()
    await process_frame

    var runtime := RUNTIME_SCRIPT.new() as Node3D
    runtime.name = "BrusselsOsmEnvironmentPlayerAuthorityProbe"
    runtime.set("data_path", JETTE_DATA)
    live_world.add_child(runtime)

    for _frame: int in range(18):
        await process_frame

    var selected := runtime.call("_target") as Node3D
    if selected != live_player:
        _fail("renderer selected a stale out-of-scene grouped Player over current_scene/Player")
        return

    var counts: Dictionary = runtime.get("last_render_counts")
    if int(counts.get("tree", 0)) == 0 or int(counts.get("street_lamp", 0)) == 0:
        _fail("current-scene Player did not drive source-backed Jette environment rendering")
        return
    if not _all_batches_visible(runtime, true):
        _fail("current-scene Player baseline did not expose environment batches")
        return
    if str(runtime.get_meta("license", "")) != "ODbL-1.0":
        _fail("OSM provenance contract missing")
        return
    if bool(runtime.get_meta("source_dimensions_measured", true)):
        _fail("authored asset dimensions were misrepresented as source measurements")
        return

    var sentinel := Node3D.new()
    sentinel.name = "ExternalRuntimeSentinel"
    runtime.add_child(sentinel)
    runtime.call("_refresh", true)
    if sentinel.get_parent() != runtime or sentinel.is_queued_for_deletion():
        _fail("OSM refresh deleted a non-renderer runtime child")
        return

    var refresh_distance := float(runtime.get("refresh_distance_m"))
    var batch_id_before_vertical := _first_batch_instance_id(runtime)
    var anchor_before_vertical: Vector3 = runtime.get("_last_anchor")
    if batch_id_before_vertical == 0:
        _fail("baseline did not expose a batch identity for refresh regression")
        return
    live_player.position = JETTE_SPAWN + Vector3(0.0, refresh_distance + 5.0, 0.0)
    runtime.call("_refresh", false)
    if _first_batch_instance_id(runtime) != batch_id_before_vertical:
        _fail("vertical-only Player movement replaced horizontal OSM environment batches")
        return
    if runtime.get("_last_anchor") != anchor_before_vertical:
        _fail("vertical-only Player movement advanced the horizontal OSM refresh anchor")
        return

    live_player.position = JETTE_SPAWN + Vector3(refresh_distance + 5.0, 0.0, 0.0)
    runtime.call("_refresh", false)
    if _first_batch_instance_id(runtime) != batch_id_before_vertical:
        _fail("horizontal Player movement replaced reusable OSM environment batch identity")
        return
    if sentinel.get_parent() != runtime or sentinel.is_queued_for_deletion():
        _fail("horizontal OSM refresh deleted a non-renderer runtime child")
        return
    var anchor_after_horizontal: Vector3 = runtime.get("_last_anchor")
    if absf(anchor_after_horizontal.x - live_player.global_position.x) > 0.001 or absf(anchor_after_horizontal.z - live_player.global_position.z) > 0.001:
        _fail("horizontal OSM refresh did not advance the renderer anchor")
        return

    live_player.position = JETTE_SPAWN
    runtime.call("_refresh", true)

    var batch_count_before_invalid_anchor := runtime.get_child_count()
    var last_anchor_before_invalid: Vector3 = runtime.get("_last_anchor")
    live_player.position = Vector3(NAN, JETTE_SPAWN.y, JETTE_SPAWN.z)
    runtime.call("_refresh", false)
    if runtime.get_child_count() != batch_count_before_invalid_anchor:
        _fail("non-finite Player anchor rebuilt or purged valid environment batches")
        return
    if runtime.get("_last_anchor") != last_anchor_before_invalid:
        _fail("non-finite Player anchor poisoned the last known-good renderer anchor")
        return
    if not _all_batches_visible(runtime, false):
        _fail("environment batches remained visible for a non-finite Player anchor")
        return

    live_player.position = JETTE_SPAWN
    runtime.call("_refresh", false)
    if not _all_batches_visible(runtime, true):
        _fail("finite Player recovery did not restore existing environment batches")
        return

    live_player.queue_free()
    if runtime.call("_target") != null:
        _fail("renderer selected current_scene/Player after it was queued for deletion")
        return
    runtime.call("_refresh", false)
    if not _all_batches_visible(runtime, false):
        _fail("environment batches remained visible while current-scene Player was queued for deletion")
        return

    for _frame: int in range(8):
        await process_frame

    if runtime.call("_target") != null:
        _fail("renderer fell back to stale out-of-scene grouped Player after current-scene Player disappeared")
        return
    if not _all_batches_visible(runtime, false):
        _fail("environment batches remained visible without a legitimate current-scene Player")
        return

    print("BRUSSELS_OSM_ENVIRONMENT_PLAYER_AUTHORITY_OK: provenance_fail_closed=true config_fail_closed=true current_scene_authoritative=true reusable_batch_refresh=true horizontal_refresh_only=true nonfinite_anchor_rejected=true queued_player_rejected=true stale_group_rejected=true fail_closed=true source=%s license=%s" % [str(runtime.get_meta("source", "")), str(runtime.get_meta("license", ""))])
    quit(0)

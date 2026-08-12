extends SceneTree

const SCENE_PATH := "res://game/zones/laeken_jette/laeken_jette.tscn"
const PROVENANCE_PATH := "res://data/sources/laeken_jette/palais5_hero_provenance.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("LAEKEN_PALAIS5_HERO_FAIL: %s" % message)
    quit(1)

func _load_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var parsed = JSON.parse_string(file.get_as_text())
    return parsed as Dictionary if parsed is Dictionary else {}

func _run() -> void:
    var provenance := _load_json(PROVENANCE_PATH)
    if provenance.is_empty():
        _fail("Palais 5 provenance registry is missing or invalid")
        return
    var facts = provenance.get("architectural_facts", {})
    if not facts is Dictionary:
        _fail("architectural_facts missing from provenance")
        return

    var packed := load(SCENE_PATH) as PackedScene
    if packed == null:
        _fail("Laeken/Jette scene failed to load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    for _i in range(40):
        await process_frame

    var pass_node := scene.get_node_or_null("Palais5HeroPass")
    if pass_node == null:
        _fail("Palais5HeroPass is not wired into the zone scene")
        return
    if not bool(pass_node.get("hero_ready")):
        _fail("Palais 5 hero geometry did not become ready")
        return

    if absf(float(pass_node.get("source_height_m")) - float(facts.get("hall_height_m", -1.0))) > 0.001:
        _fail("runtime height diverges from sourced provenance")
        return
    if absf(float(pass_node.get("source_span_m")) - float(facts.get("structural_span_m", -1.0))) > 0.001:
        _fail("runtime span diverges from sourced provenance")
        return
    if int(pass_node.get("source_outline_vertices")) < 20:
        _fail("validated OSM outline was not loaded")
        return

    if int(pass_node.get("facade_pilasters")) != int(facts.get("front_pilaster_count", -1)):
        _fail("front pilaster count diverges from sourced provenance")
        return
    if int(pass_node.get("facade_statues")) != int(facts.get("transport_statue_count", -1)):
        _fail("transport statue count diverges from sourced provenance")
        return
    if int(pass_node.get("facade_glass_panels")) != int(facts.get("main_entrance_bay_count", -1)):
        _fail("entrance bay count diverges from sourced provenance")
        return
    if int(pass_node.get("side_windows")) != int(facts.get("side_low_window_count_each", -1)) * 2:
        _fail("lateral window rhythm diverges from sourced provenance")
        return
    if int(pass_node.get("arch_instances")) != int(facts.get("arch_count", -1)) * 22:
        _fail("roof arch segment count is inconsistent")
        return

    var hero := pass_node.get_node_or_null("Palais5HeroGeometry") as Node3D
    if hero == null:
        _fail("Palais5HeroGeometry root is missing")
        return
    var terrain = scene.get_node_or_null("LaekenTerrain")
    if terrain == null or not bool(terrain.get("terrain_loaded")):
        _fail("Laeken terrain unavailable for Palais 5 placement validation")
        return
    var sampled_y := float(terrain.call("sample_height", hero.global_position.x, hero.global_position.z))
    if absf(hero.global_position.y - sampled_y - 0.06) > 0.02:
        _fail("Palais 5 hero root is not terrain-anchored")
        return

    var arches := hero.get_node_or_null("TwelveSourcedRoofArches") as MultiMeshInstance3D
    if arches == null or arches.multimesh == null:
        _fail("sourced roof arch MultiMesh is missing")
        return
    if arches.multimesh.instance_count != int(facts.get("arch_count", -1)) * 22:
        _fail("roof arch MultiMesh instance count is wrong")
        return

    print("LAEKEN_PALAIS5_HERO_OK: height=%.1fm span=%.1fm arches=%d pilasters=%d statues=%d bays=%d side_windows=%d terrain_delta=%.3fm" % [
        float(pass_node.get("source_height_m")),
        float(pass_node.get("source_span_m")),
        int(facts.get("arch_count", 0)),
        int(pass_node.get("facade_pilasters")),
        int(pass_node.get("facade_statues")),
        int(pass_node.get("facade_glass_panels")),
        int(pass_node.get("side_windows")),
        hero.global_position.y - sampled_y,
    ])
    scene.queue_free()
    await process_frame
    quit(0)

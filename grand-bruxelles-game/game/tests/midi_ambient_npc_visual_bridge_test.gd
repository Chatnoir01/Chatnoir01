extends SceneTree

const EXPECTED_AMBIENT := 20
const EXPECTED_MATERIAL_CACHE_ENTRIES := 23
const EXPECTED_REUSED_MATERIAL_SURFACES := 240

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_AMBIENT_NPC_VISUAL_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    for _frame: int in range(6):
        await process_frame

    var urban_life := scene.get_node_or_null("MidiUrbanLife")
    if urban_life == null:
        _fail("production MidiUrbanLife missing")
        return

    var ambient := get_nodes_in_group("ambient_pedestrian")
    if ambient.size() != EXPECTED_AMBIENT:
        _fail("expected %d ambient pedestrians, got %d" % [EXPECTED_AMBIENT, ambient.size()])
        return

    var signatures := {}
    for raw: Node in ambient:
        var person := raw as Node3D
        if person == null:
            _fail("ambient pedestrian is not Node3D")
            return
        var proxy := person.get_node_or_null("ProfiledNpcProxy") as NpcAgent
        if proxy == null:
            _fail("%s has no production NpcAgent visual proxy" % person.name)
            return
        if proxy.process_mode != Node.PROCESS_MODE_DISABLED:
            _fail("%s proxy may compete with legacy ambient movement" % person.name)
            return
        var visual := proxy.get_node_or_null("VisualUpgrade") as Node3D
        if visual == null or not visual.has_method("visual_signature"):
            _fail("%s has no production humanoid visual" % person.name)
            return
        var signature := str(visual.call("visual_signature"))
        if signature.is_empty():
            _fail("%s production appearance signature is empty" % person.name)
            return
        signatures[signature] = true
        for legacy_name: String in ["Torso", "LeftLeg", "RightLeg", "LeftArm", "RightArm", "Head", "Bag"]:
            var legacy := person.get_node_or_null(legacy_name)
            if legacy is VisualInstance3D and (legacy as VisualInstance3D).visible:
                _fail("%s still exposes legacy primitive %s" % [person.name, legacy_name])
                return

    if signatures.size() < 8:
        _fail("ambient crowd variation is too repetitive: %d unique signatures" % signatures.size())
        return

    var material_runtime := root.get_node_or_null("MidiAmbientNpcVisualRuntime")
    if material_runtime == null or not material_runtime.has_method("material_cache_stats"):
        _fail("material-sharing runtime stats are unavailable")
        return
    var stats: Dictionary = material_runtime.call("material_cache_stats")
    var cache_entries := int(stats.get("entries", 0))
    var surfaces_reused := int(stats.get("surfaces_reused", 0))
    if cache_entries != EXPECTED_MATERIAL_CACHE_ENTRIES:
        _fail("expected %d exact material cache entries, got %d" % [EXPECTED_MATERIAL_CACHE_ENTRIES, cache_entries])
        return
    if surfaces_reused != EXPECTED_REUSED_MATERIAL_SURFACES:
        _fail("expected %d equivalent NPC material surfaces reused, got %d" % [EXPECTED_REUSED_MATERIAL_SURFACES, surfaces_reused])
        return

    print("MIDI_AMBIENT_NPC_VISUAL_OK: pedestrians=%d unique_signatures=%d material_cache_entries=%d material_surfaces_reused=%d" % [ambient.size(), signatures.size(), cache_entries, surfaces_reused])
    scene.queue_free()
    quit(0)

extends SceneTree

const EXPECTED_AMBIENT := 20
const EXPECTED_MATERIAL_CACHE_ENTRIES := 23
const EXPECTED_REUSED_MATERIAL_SURFACES := 240
const EXPECTED_LOD_SWITCH_DISTANCE := 48.0
const EXPECTED_LOD_MARGIN := 6.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_AMBIENT_NPC_VISUAL_FAIL: %s" % message)
    quit(1)

func _approx(actual: float, expected: float) -> bool:
    return absf(actual - expected) <= 0.001

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
    var detailed_lod_meshes := 0
    var legacy_lod_visuals := 0
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

        var person_detailed := 0
        for node: Node in visual.find_children("*", "MeshInstance3D", true, false):
            var mesh_instance := node as MeshInstance3D
            if mesh_instance == null:
                continue
            if not _approx(mesh_instance.visibility_range_end, EXPECTED_LOD_SWITCH_DISTANCE):
                _fail("%s detailed mesh %s has wrong LOD end %.3f" % [person.name, mesh_instance.name, mesh_instance.visibility_range_end])
                return
            if not _approx(mesh_instance.visibility_range_end_margin, EXPECTED_LOD_MARGIN):
                _fail("%s detailed mesh %s has wrong LOD margin %.3f" % [person.name, mesh_instance.name, mesh_instance.visibility_range_end_margin])
                return
            if mesh_instance.visibility_range_fade_mode != GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF:
                _fail("%s detailed mesh %s does not self-fade at LOD boundary" % [person.name, mesh_instance.name])
                return
            person_detailed += 1
        if person_detailed == 0:
            _fail("%s has no detailed meshes participating in distance LOD" % person.name)
            return
        detailed_lod_meshes += person_detailed

        var person_legacy := 0
        for legacy_name: String in ["Torso", "LeftLeg", "RightLeg", "LeftArm", "RightArm", "Head", "Bag"]:
            var legacy := person.get_node_or_null(legacy_name)
            if not (legacy is VisualInstance3D):
                continue
            var legacy_visual := legacy as VisualInstance3D
            if not legacy_visual.visible:
                _fail("%s legacy LOD primitive %s must stay enabled for distance fallback" % [person.name, legacy_name])
                return
            if not _approx(legacy_visual.visibility_range_begin, EXPECTED_LOD_SWITCH_DISTANCE):
                _fail("%s legacy primitive %s has wrong LOD begin %.3f" % [person.name, legacy_name, legacy_visual.visibility_range_begin])
                return
            if not _approx(legacy_visual.visibility_range_begin_margin, EXPECTED_LOD_MARGIN):
                _fail("%s legacy primitive %s has wrong LOD margin %.3f" % [person.name, legacy_name, legacy_visual.visibility_range_begin_margin])
                return
            if legacy_visual.visibility_range_fade_mode != GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF:
                _fail("%s legacy primitive %s does not self-fade at LOD boundary" % [person.name, legacy_name])
                return
            person_legacy += 1
        if person_legacy == 0:
            _fail("%s has no legacy visuals participating in distance LOD" % person.name)
            return
        legacy_lod_visuals += person_legacy

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

    if not material_runtime.has_method("lod_stats"):
        _fail("distance-LOD runtime stats are unavailable")
        return
    var lod_stats: Dictionary = material_runtime.call("lod_stats")
    if int(lod_stats.get("detailed_meshes", -1)) != detailed_lod_meshes:
        _fail("distance-LOD detailed mesh count disagrees with runtime stats")
        return
    if int(lod_stats.get("legacy_visuals", -1)) != legacy_lod_visuals:
        _fail("distance-LOD legacy visual count disagrees with runtime stats")
        return
    if not _approx(float(lod_stats.get("switch_distance_m", 0.0)), EXPECTED_LOD_SWITCH_DISTANCE):
        _fail("distance-LOD switch distance stats mismatch")
        return

    print("MIDI_AMBIENT_NPC_VISUAL_OK: pedestrians=%d unique_signatures=%d material_cache_entries=%d material_surfaces_reused=%d lod_detailed_meshes=%d lod_legacy_visuals=%d lod_switch_m=%.1f" % [ambient.size(), signatures.size(), cache_entries, surfaces_reused, detailed_lod_meshes, legacy_lod_visuals, EXPECTED_LOD_SWITCH_DISTANCE])
    scene.queue_free()
    quit(0)

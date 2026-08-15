extends SceneTree

var _failed := false

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene missing")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    current_scene = scene
    for _frame in range(8):
        await process_frame

    var midi := scene.get_node_or_null("MidiHeroZone") as Node3D
    if midi == null:
        _fail("MidiHeroZone missing")
        return

    var pbr_instances := 0
    for candidate: Node in midi.find_children("*", "MeshInstance3D", true, false):
        var mesh_instance := candidate as MeshInstance3D
        if mesh_instance == null or mesh_instance.mesh == null or mesh_instance.mesh.get_surface_count() < 1:
            continue
        var material := mesh_instance.mesh.surface_get_material(0) as StandardMaterial3D
        if material == null or not bool(material.get_meta("photoreal_normal_map", false)):
            continue
        if not material.normal_enabled or material.normal_texture == null:
            _fail("tagged PBR material missing normal texture")
            return
        if material.roughness_texture == null:
            _fail("tagged PBR material missing roughness texture")
            return
        if str(material.get_meta("pbr_maps_source", "")) != "derived_from_existing_authored_albedo":
            _fail("PBR map provenance contract missing")
            return
        pbr_instances += 1

    if pbr_instances < 4:
        _fail("expected repeated visible Midi PBR surfaces, got %d" % pbr_instances)
        return

    var profile_script := load("res://game/scripts/photorealism_runtime.gd")
    if profile_script == null:
        _fail("photorealism profile script missing")
        return
    var profile := profile_script.new()
    var environment := Environment.new()
    environment.fog_enabled = true
    environment.fog_density = 0.01
    environment.fog_sky_affect = 1.0
    profile.call("_apply_shared_profile", environment)
    if environment.tonemap_mode != Environment.TONE_MAPPER_ACES:
        _fail("shared profile must use ACES tonemapping")
        return
    if not environment.glow_enabled:
        _fail("shared profile must expose restrained compatibility glow")
        return
    if environment.fog_density > 0.00221:
        _fail("shared profile did not bound heavy fog")
        return

    var renderer := str(ProjectSettings.get_setting("rendering/renderer/rendering_method", ""))
    if renderer != "gl_compatibility":
        _fail("playable Web contract unexpectedly changed renderer: %s" % renderer)
        return

    print("PHOTOREALISM_FOUNDATION_OK: pbr_instances=%d renderer=%s" % [pbr_instances, renderer])
    quit(0)

func _fail(message: String) -> void:
    if _failed:
        return
    _failed = true
    push_error(message)
    print("PHOTOREALISM_FOUNDATION_FAIL: %s" % message)
    quit(1)

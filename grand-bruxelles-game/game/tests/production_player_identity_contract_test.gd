extends SceneTree

const VISUAL_SCRIPT := preload("res://game/scripts/humanoid_visual.gd")
const EXPECTED_PINK := Color(0.93, 0.12, 0.58, 1.0)

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("PRODUCTION_PLAYER_IDENTITY_FAIL: %s" % message)
    quit(1)

func _assert_visual_contract(visual: Node3D, context: String) -> bool:
    if visual.call("is_using_authored_character"):
        _fail("%s unexpectedly loaded an authored asset" % context)
        return false
    if str(visual.call("visual_signature")) != "pink_tracksuit_procedural_v1":
        _fail("%s does not expose canonical pink identity: %s" % [context, str(visual.call("visual_signature"))])
        return false

    for required_name: String in ["CropTop", "LeftTrouserStripe", "RightTrouserStripe", "ShoulderBag", "BagStrap", "Phone", "HairBun"]:
        if visual.get_node_or_null(required_name) == null:
            _fail("%s missing canonical identity detail: %s" % [context, required_name])
            return false

    var torso := visual.get_node_or_null("Torso") as MeshInstance3D
    var hips := visual.get_node_or_null("Hips") as MeshInstance3D
    if torso == null or hips == null:
        _fail("%s fallback body missing" % context)
        return false
    if not torso.mesh is ArrayMesh or not hips.mesh is ArrayMesh:
        _fail("%s must preserve profiled ArrayMesh body from #368" % context)
        return false

    var torso_material := (torso.mesh as ArrayMesh).surface_get_material(0) as StandardMaterial3D
    if torso_material == null:
        _fail("%s torso material missing" % context)
        return false
    var actual := torso_material.albedo_color
    var pink_delta := maxf(absf(actual.r - EXPECTED_PINK.r), maxf(absf(actual.g - EXPECTED_PINK.g), maxf(absf(actual.b - EXPECTED_PINK.b), absf(actual.a - EXPECTED_PINK.a))))
    if pink_delta > 0.01:
        _fail("%s torso is not canonical pink: %s" % [context, str(actual)])
        return false
    return true

func _run() -> void:
    var main_source := FileAccess.get_file_as_string("res://game/main.tscn")
    if main_source.is_empty():
        _fail("main.tscn could not be read")
        return
    if 'path="res://game/scripts/humanoid_visual.gd"' not in main_source:
        _fail("production player is no longer wired through humanoid_visual.gd")
        return

    var actor := CharacterBody3D.new()
    actor.name = "Player"
    root.add_child(actor)
    var legacy := MeshInstance3D.new()
    legacy.name = "MeshInstance3D"
    legacy.mesh = CapsuleMesh.new()
    actor.add_child(legacy)
    var isolated_visual := VISUAL_SCRIPT.new()
    isolated_visual.name = "VisualUpgrade"
    isolated_visual.authored_scene_path = "res://assets/characters/player/does-not-exist.glb"
    isolated_visual.allow_authored_fallback_paths = false
    actor.add_child(isolated_visual)
    await process_frame
    if not _assert_visual_contract(isolated_visual, "isolated production renderer"):
        return
    actor.queue_free()

    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("production main scene did not load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    await process_frame
    await process_frame

    var production_visual := scene.get_node_or_null("Player/VisualUpgrade") as Node3D
    var production_legacy := scene.get_node_or_null("Player/MeshInstance3D") as MeshInstance3D
    if production_visual == null or production_legacy == null:
        _fail("production player visual path missing")
        return
    if not _assert_visual_contract(production_visual, "main.tscn Player/VisualUpgrade"):
        return
    if production_legacy.visible:
        _fail("production legacy capsule remains visible over canonical identity")
        return

    print("PRODUCTION_PLAYER_IDENTITY_OK: canonical pink tracksuit identity is active on real production player; legacy capsule hidden")
    scene.queue_free()
    quit(0)

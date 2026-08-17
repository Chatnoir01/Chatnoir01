extends SceneTree

const BADGE := preload("res://game/scripts/player_identity_badge_runtime.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("PLAYER_IDENTITY_BADGE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    if BADGE.runtime_visual_ready(null):
        _fail("missing current scene must not be treated as a ready procedural player")
        return

    var fake_scene := Node3D.new()
    fake_scene.name = "Main"
    var fake_player := CharacterBody3D.new()
    fake_player.name = "Player"
    fake_scene.add_child(fake_player)
    var fake_visual := Node3D.new()
    fake_visual.name = "VisualUpgrade"
    fake_player.add_child(fake_visual)

    if BADGE.runtime_visual_ready(fake_scene):
        _fail("visual outside the SceneTree must not be considered runtime-ready")
        return

    root.add_child(fake_scene)
    await process_frame
    if not BADGE.runtime_visual_ready(fake_scene):
        _fail("ready Player/VisualUpgrade must unlock identity publication")
        fake_scene.queue_free()
        return
    if BADGE.resolve_runtime_scene(self) != fake_scene:
        _fail("runtime scene resolver must find instantiated Main when current_scene is unset")
        fake_scene.queue_free()
        return
    fake_scene.queue_free()
    await process_frame

    var kaykit := {
        "regime": "PLAYER_FALLBACK",
        "resolved_path": "res://assets/characters/player_character.glb",
        "authored": true,
        "fallback_kind": "authored",
    }
    var kaykit_text := BADGE.badge_text_for_identity(kaykit)
    if "PLAYER FALLBACK" not in kaykit_text or "KAYKIT ROGUE" not in kaykit_text:
        _fail("KayKit fallback must be named clearly, got '%s'" % kaykit_text)
        return

    var procedural := {
        "regime": "PLAYER_FALLBACK",
        "resolved_path": "",
        "authored": false,
        "fallback_kind": "procedural",
    }
    var procedural_text := BADGE.badge_text_for_identity(procedural)
    if "PLAYER FALLBACK" not in procedural_text or "PROCEDURAL" not in procedural_text:
        _fail("procedural fallback must be disclosed, got '%s'" % procedural_text)
        return

    var production := {
        "regime": "PLAYER_PRODUCTION",
        "resolved_path": "res://assets/characters/player/thandi/Thandi.glb",
        "authored": true,
        "production": true,
    }
    if not BADGE.badge_text_for_identity(production).is_empty():
        _fail("production identity must not show a fallback badge")
        return

    print("PLAYER_IDENTITY_BADGE_OK: runtime scene resolved; fallback explicit; production silent")
    quit(0)

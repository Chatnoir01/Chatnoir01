extends SceneTree

const BADGE := preload("res://game/scripts/player_identity_badge_runtime.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("PLAYER_IDENTITY_BADGE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
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

    print("PLAYER_IDENTITY_BADGE_OK: fallback is explicit; production is silent")
    quit(0)

extends SceneTree

const IDENTITY := preload("res://game/scripts/player_identity_resolver.gd")
const THANDI_GLB := "res://assets/characters/player/thandi/Thandi.glb"
const THANDI_FBX := "res://assets/characters/player/thandi/Thandi.fbx"
const AUTHORED_FALLBACK := "res://assets/characters/player_character.glb"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("PLAYER_IDENTITY_CONTRACT_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    if ResourceLoader.exists(THANDI_GLB) or ResourceLoader.exists(THANDI_FBX):
        _fail("test assumptions drifted: Thandi is now present; update expected production regime")
        return
    if not ResourceLoader.exists(AUTHORED_FALLBACK):
        _fail("real authored KayKit fallback is missing")
        return
    var resolution: Dictionary = IDENTITY.resolve_default_player_identity()
    if String(resolution.get("regime", "")) != IDENTITY.PLAYER_FALLBACK:
        _fail("expected PLAYER_FALLBACK while Thandi is absent")
        return
    if String(resolution.get("resolved_path", "")) != AUTHORED_FALLBACK:
        _fail("expected KayKit authored fallback path")
        return
    if not bool(resolution.get("authored", false)) or bool(resolution.get("production", true)):
        _fail("KayKit must be authored fallback, never production")
        return
    var no_authored: Dictionary = IDENTITY.resolve_player_identity("res://assets/characters/player/definitely_missing.glb", false, [])
    if String(no_authored.get("regime", "")) != IDENTITY.PLAYER_FALLBACK or bool(no_authored.get("authored", true)):
        _fail("missing authored assets must fail closed to procedural PLAYER_FALLBACK")
        return
    print("PLAYER_IDENTITY_CONTRACT_OK regime=%s path=%s fallback=%s" % [String(resolution.get("regime", "")), String(resolution.get("resolved_path", "")), String(resolution.get("fallback_kind", ""))])
    quit(0)

extends Node

const PLAYER_PRODUCTION := "PLAYER_PRODUCTION"
const PLAYER_FALLBACK := "PLAYER_FALLBACK"

const THANDI_GLB := "res://assets/characters/player/thandi/Thandi.glb"
const THANDI_FBX := "res://assets/characters/player/thandi/Thandi.fbx"
const AUTHORED_FALLBACK := "res://assets/characters/player_character.glb"
const PRODUCTION_PATHS: Array[String] = [THANDI_GLB, THANDI_FBX]
const DEFAULT_AUTHORED_FALLBACK_PATHS: Array[String] = [AUTHORED_FALLBACK]

var _runtime_identity: Dictionary = {}

func _ready() -> void:
    call_deferred("refresh_runtime_identity")

static func _candidate_paths(primary_path: String, allow_fallback: bool, authored_fallback_paths: Array) -> Array[String]:
    var candidates: Array[String] = []
    if not primary_path.is_empty():
        candidates.append(primary_path)
    if primary_path == THANDI_GLB and THANDI_FBX not in candidates:
        candidates.append(THANDI_FBX)
    if allow_fallback:
        for raw_path: Variant in authored_fallback_paths:
            var path := String(raw_path)
            if not path.is_empty() and path not in candidates:
                candidates.append(path)
    return candidates

static func _loaded_scene(path: String) -> PackedScene:
    if not ResourceLoader.exists(path):
        return null
    var resource := ResourceLoader.load(path)
    if resource is PackedScene:
        return resource as PackedScene
    return null

static func _identity_for_loaded_path(path: String) -> Dictionary:
    var production := path in PRODUCTION_PATHS
    return {
        "regime": PLAYER_PRODUCTION if production else PLAYER_FALLBACK,
        "resolved_path": path,
        "authored": true,
        "production": production,
        "fallback_kind": "" if production else "authored",
        "fallback_reason": "" if production else "preferred_production_asset_unavailable",
    }

static func resolve_player_identity(primary_path: String, allow_fallback: bool, authored_fallback_paths: Array) -> Dictionary:
    for candidate: String in _candidate_paths(primary_path, allow_fallback, authored_fallback_paths):
        if _loaded_scene(candidate) != null:
            return _identity_for_loaded_path(candidate)
    return {
        "regime": PLAYER_FALLBACK,
        "resolved_path": "",
        "authored": false,
        "production": false,
        "fallback_kind": "procedural",
        "fallback_reason": "no_valid_authored_player_asset",
    }

static func resolve_default_player_identity() -> Dictionary:
    return resolve_player_identity(THANDI_GLB, true, DEFAULT_AUTHORED_FALLBACK_PATHS)

static func classify_runtime_visual(visual: Node) -> Dictionary:
    if visual == null:
        return {
            "regime": PLAYER_FALLBACK,
            "resolved_path": "",
            "authored": false,
            "production": false,
            "fallback_kind": "procedural",
            "fallback_reason": "player_visual_unavailable",
        }
    if visual.has_method("is_using_authored_character") and bool(visual.call("is_using_authored_character")):
        var path := ""
        if visual.has_method("resolved_authored_scene_path"):
            path = String(visual.call("resolved_authored_scene_path"))
        if not path.is_empty():
            return _identity_for_loaded_path(path)
    return {
        "regime": PLAYER_FALLBACK,
        "resolved_path": "",
        "authored": false,
        "production": false,
        "fallback_kind": "procedural",
        "fallback_reason": "runtime_visual_used_procedural_body",
    }

func refresh_runtime_identity() -> Dictionary:
    var scene := get_tree().current_scene
    var visual: Node = null
    if scene != null:
        visual = scene.get_node_or_null("Player/VisualUpgrade")
    _runtime_identity = classify_runtime_visual(visual)
    set_meta("player_identity_regime", String(_runtime_identity.get("regime", PLAYER_FALLBACK)))
    set_meta("player_identity_path", String(_runtime_identity.get("resolved_path", "")))
    set_meta("player_identity_fallback_kind", String(_runtime_identity.get("fallback_kind", "")))
    return _runtime_identity.duplicate(true)

func current_identity() -> Dictionary:
    if _runtime_identity.is_empty():
        return refresh_runtime_identity()
    return _runtime_identity.duplicate(true)

func current_regime() -> String:
    return String(current_identity().get("regime", PLAYER_FALLBACK))

func is_fallback_active() -> bool:
    return current_regime() == PLAYER_FALLBACK

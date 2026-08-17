extends Node

const PLAYER_PRODUCTION := "PLAYER_PRODUCTION"
const PLAYER_FALLBACK := "PLAYER_FALLBACK"
const THANDI_GLB := "res://assets/characters/player/thandi/Thandi.glb"
const THANDI_FBX := "res://assets/characters/player/thandi/Thandi.fbx"
const AUTHORED_FALLBACK := "res://assets/characters/player_character.glb"
const PRODUCTION_PATHS: Array[String] = [THANDI_GLB, THANDI_FBX]
const DEFAULT_AUTHORED_FALLBACK_PATHS: Array[String] = [AUTHORED_FALLBACK]
var _runtime_identity: Dictionary = {}
func _ready() -> void: call_deferred("refresh_runtime_identity")
static func _loaded_scene(path: String) -> PackedScene:
    if not ResourceLoader.exists(path): return null
    var resource := ResourceLoader.load(path)
    return resource as PackedScene if resource is PackedScene else null
static func _classify_loaded(path: String) -> Dictionary:
    var production := path in PRODUCTION_PATHS
    return {"regime": PLAYER_PRODUCTION if production else PLAYER_FALLBACK, "resolved_path": path, "authored": true, "production": production, "fallback_kind": "" if production else "authored", "fallback_reason": "" if production else "preferred_production_asset_unavailable"}
static func resolve_player_identity(primary_path: String, allow_fallback: bool, authored_fallback_paths: Array) -> Dictionary:
    var candidates: Array[String] = []
    if not primary_path.is_empty(): candidates.append(primary_path)
    if primary_path == THANDI_GLB: candidates.append(THANDI_FBX)
    if allow_fallback:
        for raw_path: Variant in authored_fallback_paths:
            var path := String(raw_path)
            if not path.is_empty() and path not in candidates: candidates.append(path)
    for candidate: String in candidates:
        if _loaded_scene(candidate) != null: return _classify_loaded(candidate)
    return {"regime": PLAYER_FALLBACK, "resolved_path": "", "authored": false, "production": false, "fallback_kind": "procedural", "fallback_reason": "no_valid_authored_player_asset"}
static func resolve_default_player_identity() -> Dictionary:
    return resolve_player_identity(THANDI_GLB, true, DEFAULT_AUTHORED_FALLBACK_PATHS)
static func classify_runtime_visual(visual: Node) -> Dictionary:
    if visual != null and visual.has_method("is_using_authored_character") and bool(visual.call("is_using_authored_character")):
        var path := String(visual.call("resolved_authored_scene_path")) if visual.has_method("resolved_authored_scene_path") else ""
        if not path.is_empty(): return _classify_loaded(path)
    return {"regime": PLAYER_FALLBACK, "resolved_path": "", "authored": false, "production": false, "fallback_kind": "procedural", "fallback_reason": "runtime_visual_used_procedural_body"}
func refresh_runtime_identity() -> Dictionary:
    var scene := get_tree().current_scene
    var visual: Node = scene.get_node_or_null("Player/VisualUpgrade") if scene != null else null
    _runtime_identity = classify_runtime_visual(visual)
    return _runtime_identity.duplicate(true)
func current_identity() -> Dictionary: return refresh_runtime_identity() if _runtime_identity.is_empty() else _runtime_identity.duplicate(true)
func current_regime() -> String: return String(current_identity().get("regime", PLAYER_FALLBACK))
func is_fallback_active() -> bool: return current_regime() == PLAYER_FALLBACK

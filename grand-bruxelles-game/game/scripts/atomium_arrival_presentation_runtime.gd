extends Node

## Atomium-only arrival presentation guard.
##
## The normal zone-selector Atomium visit keeps the production third-person camera
## but the avatar can occupy the landmark's lower centre. Hide only the two player
## presentation meshes once AtomiumDirectHero is actually mounted. Player position,
## collision, movement state and camera values remain untouched. A later camera-view
## cycle may restore the avatar normally because this runtime does not re-hide after
## its one initial application.

const HERO_NODE_NAME := "AtomiumDirectHero"
const PLAYER_NODE_NAME := "Player"
const BASE_VISUAL_PATH := "MeshInstance3D"
const UPGRADE_VISUAL_PATH := "VisualUpgrade"

var _enhanced_enabled := true
var _player: CharacterBody3D = null
var _base_visual: Node3D = null
var _upgrade_visual: Node3D = null
var _base_default_visible := true
var _upgrade_default_visible := true
var _bound_player_id := 0
var _applied := false
var _ready_complete := false

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    set_process(true)

func _process(_delta: float) -> void:
    if _player != null and not is_instance_valid(_player):
        _reset_binding()
    if is_instance_valid(_player):
        return

    var scene := get_tree().current_scene
    if scene == null:
        return
    var hero := scene.get_node_or_null(HERO_NODE_NAME)
    if hero == null or not bool(hero.get("hero_built")):
        return
    var player := scene.get_node_or_null(PLAYER_NODE_NAME) as CharacterBody3D
    if player == null:
        return
    _bind_player(player)
    if _enhanced_enabled:
        _apply_occluder_suppression()
    else:
        _restore_baseline()
    _ready_complete = true

func _bind_player(player: CharacterBody3D) -> void:
    _player = player
    _bound_player_id = player.get_instance_id()
    _base_visual = player.get_node_or_null(BASE_VISUAL_PATH) as Node3D
    _upgrade_visual = player.get_node_or_null(UPGRADE_VISUAL_PATH) as Node3D
    if is_instance_valid(_base_visual):
        _base_default_visible = _base_visual.visible
    if is_instance_valid(_upgrade_visual):
        _upgrade_default_visible = _upgrade_visual.visible
    _applied = false

func _apply_occluder_suppression() -> void:
    if not is_instance_valid(_player):
        return
    if is_instance_valid(_base_visual):
        _base_visual.visible = false
    if is_instance_valid(_upgrade_visual):
        _upgrade_visual.visible = false
    _player.set_meta("atomium_arrival_avatar_hidden", true)
    _player.set_meta("atomium_arrival_camera_changed", false)
    _player.set_meta("atomium_arrival_position_changed", false)
    _player.set_meta("atomium_arrival_collision_changed", false)
    _applied = true
    print("ATOMIUM_ARRIVAL_PRESENTATION_READY: avatar_hidden=true camera_changed=false position_changed=false collision_changed=false")

func _restore_baseline() -> void:
    if not is_instance_valid(_player):
        return
    if is_instance_valid(_base_visual):
        _base_visual.visible = _base_default_visible
    if is_instance_valid(_upgrade_visual):
        _upgrade_visual.visible = _upgrade_default_visible
    _player.set_meta("atomium_arrival_avatar_hidden", false)
    _applied = false

func _reset_binding() -> void:
    _player = null
    _base_visual = null
    _upgrade_visual = null
    _bound_player_id = 0
    _applied = false
    _ready_complete = false
    _base_default_visible = true
    _upgrade_default_visible = true

func set_enhanced_enabled(enabled: bool) -> void:
    _enhanced_enabled = enabled
    if not is_instance_valid(_player):
        return
    if enabled:
        _apply_occluder_suppression()
    else:
        _restore_baseline()

func enhanced_enabled() -> bool:
    return _enhanced_enabled

func ready_complete() -> bool:
    return _ready_complete

func applied() -> bool:
    return _applied

func bound_player_id() -> int:
    return _bound_player_id

func baseline_visible_visual_count() -> int:
    var count := 0
    if is_instance_valid(_base_visual) and _base_default_visible:
        count += 1
    if is_instance_valid(_upgrade_visual) and _upgrade_default_visible:
        count += 1
    return count

func current_visible_visual_count() -> int:
    var count := 0
    if is_instance_valid(_base_visual) and _base_visual.visible:
        count += 1
    if is_instance_valid(_upgrade_visual) and _upgrade_visual.visible:
        count += 1
    return count

func camera_changed() -> bool:
    return false

func source_position_changed() -> bool:
    return false

func collision_changed() -> bool:
    return false

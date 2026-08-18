extends Node

const AUTHORED_CANDIDATES: Array[String] = [
	"res://assets/characters/player/thandi/Thandi.glb",
	"res://assets/characters/player/thandi/Thandi.fbx",
	"res://assets/characters/player_character.glb",
]
const AUTHORED_NODE_NAME := &"AuthoredNpcCharacter"
const APPLIED_META := &"authored_npc_visual_runtime_v1"
const SOURCE_META := &"authored_npc_source_path"
const BLEND_SECONDS := 0.12
const IDLE_ENTER_SPEED_MPS := 0.12
const IDLE_EXIT_SPEED_MPS := 0.22
const RUN_ENTER_SPEED_MPS := 3.80
const RUN_EXIT_SPEED_MPS := 3.20
const WALK_REFERENCE_SPEED_MPS := 1.70
const RUN_REFERENCE_SPEED_MPS := 4.50
const WALK_PLAYBACK_MIN := 0.68
const WALK_PLAYBACK_MAX := 1.55
const RUN_PLAYBACK_MIN := 0.82
const RUN_PLAYBACK_MAX := 1.28
const TRANSFORM_TELEPORT_GUARD_M := 6.0
const TRANSFORM_SPEED_MAX_MPS := 8.0
const REJECT_ACTION_TOKENS: Array[String] = [
	"attack", "combat", "melee", "sword", "staff", "bow", "gun", "shoot",
	"hit", "hurt", "death", "jump", "roll", "cast", "spell"
]
const POLICE_DIRECT_KEEP: Array[StringName] = [
	&"HiVisVest", &"PoliceCap", &"PoliceCapPeak", &"PoliceQualityDetails"
]

var _packed_scene: PackedScene
var _resolved_source_path := ""
var _bindings: Dictionary = {}


func _ready() -> void:
	_resolve_authored_scene()
	if get_tree() != null and not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)
	call_deferred("_scan_existing")


func _exit_tree() -> void:
	if get_tree() != null and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	_bindings.clear()


func _process(delta: float) -> void:
	if _bindings.is_empty():
		return
	for raw_id: Variant in _bindings.keys().duplicate():
		var actor_id := int(raw_id)
		var binding_value: Variant = _bindings.get(actor_id)
		if not (binding_value is Dictionary):
			_bindings.erase(actor_id)
			continue
		var binding: Dictionary = binding_value
		var actor := binding.get("actor") as CharacterBody3D
		var animation_player := binding.get("animation_player") as AnimationPlayer
		if not is_instance_valid(actor) or not is_instance_valid(animation_player):
			_bindings.erase(actor_id)
			continue
		_update_binding(binding, delta)


func _resolve_authored_scene() -> bool:
	if _packed_scene != null:
		return true
	for candidate: String in AUTHORED_CANDIDATES:
		if not ResourceLoader.exists(candidate):
			continue
		var resource := load(candidate)
		if resource is PackedScene:
			_packed_scene = resource as PackedScene
			_resolved_source_path = candidate
			set_meta(SOURCE_META, candidate)
			return true
	push_warning("Authored NPC visual runtime: no authored rig scene is available; procedural fallback stays active")
	return false


func _scan_existing() -> void:
	var scene := get_tree().current_scene if get_tree() != null else null
	if scene == null:
		return
	_scan_node(scene)


func _scan_node(node: Node) -> void:
	if node is NpcAgent:
		apply_to_actor(node)
	for child: Node in node.get_children():
		_scan_node(child)


func _on_node_added(node: Node) -> void:
	if node == null:
		return
	if node is NpcAgent:
		call_deferred("apply_to_actor", node)
		return
	var parent := node.get_parent()
	if parent is NpcAgent and node.name in [&"VisualUpgrade", &"HumanoidVisual"]:
		call_deferred("apply_to_actor", parent)


func apply_to_actor(raw_actor: Node) -> bool:
	if not (raw_actor is NpcAgent):
		return false
	var actor := raw_actor as NpcAgent
	if not is_instance_valid(actor):
		return false
	if actor.get_meta(APPLIED_META, false) == true and _bindings.has(actor.get_instance_id()):
		return true
	if not _resolve_authored_scene():
		return false

	var visual := _find_visual(actor)
	if visual == null:
		return false

	var authored := visual.get_node_or_null(NodePath(str(AUTHORED_NODE_NAME))) as Node3D
	if authored == null:
		var instance := _packed_scene.instantiate()
		if not (instance is Node3D):
			push_warning("Authored NPC visual runtime: authored scene root is not Node3D")
			return false
		authored = instance as Node3D
		authored.name = AUTHORED_NODE_NAME
		authored.position = Vector3(0.0, -0.90, 0.0)
		authored.rotation_degrees = Vector3(0.0, 180.0, 0.0)
		var stature_scale := _stature_scale(actor.variation_seed)
		authored.scale = Vector3.ONE * stature_scale
		visual.add_child(authored)

	var animation_player := _find_animation_player(authored)
	if animation_player == null:
		if authored.get_parent() == visual:
			authored.queue_free()
		push_warning("Authored NPC visual runtime: no AnimationPlayer found in %s" % _resolved_source_path)
		return false
	var locomotion := _resolve_locomotion(animation_player)
	if String(locomotion.get("idle", "")).is_empty() or String(locomotion.get("walk", "")).is_empty() or String(locomotion.get("run", "")).is_empty():
		if authored.get_parent() == visual:
			authored.queue_free()
		push_warning("Authored NPC visual runtime: idle/walk/run clips unresolved in %s" % _resolved_source_path)
		return false

	_configure_locomotion_loops(animation_player, locomotion)
	_hide_procedural_visuals(visual, authored, actor.role == NpcBehaviorModel.Role.POLICE)
	var motion_source := _motion_source_for(actor)
	var binding := {
		"actor": actor,
		"visual": visual,
		"authored": authored,
		"animation_player": animation_player,
		"locomotion": locomotion,
		"state": "idle",
		"animation": "",
		"motion_source": motion_source,
		"observe_transform_delta": motion_source != actor,
		"last_motion_position": motion_source.global_position,
	}
	_bindings[actor.get_instance_id()] = binding
	actor.set_meta(APPLIED_META, true)
	actor.set_meta(SOURCE_META, _resolved_source_path)
	actor.set_meta("authored_npc_motion_source", "parent_transform" if motion_source != actor else "actor_velocity")
	_update_binding(binding, 0.0)
	return true


func _find_visual(actor: Node) -> Node3D:
	for candidate: StringName in [&"VisualUpgrade", &"HumanoidVisual"]:
		var visual := actor.get_node_or_null(NodePath(str(candidate))) as Node3D
		if visual != null:
			return visual
	return null


func _motion_source_for(actor: NpcAgent) -> Node3D:
	var parent := actor.get_parent() as Node3D
	if actor.process_mode == Node.PROCESS_MODE_DISABLED and actor.name == &"ProfiledNpcProxy" and parent != null and parent.is_in_group("ambient_pedestrian"):
		return parent
	return actor


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _resolve_locomotion(animation_player: AnimationPlayer) -> Dictionary:
	var names := animation_player.get_animation_list()
	return {
		"idle": _choose_animation(names, ["idle"]),
		"walk": _choose_animation(names, ["walk"]),
		"run": _choose_animation(names, ["run"]),
	}


func _choose_animation(names: PackedStringArray, required_tokens: Array[String]) -> String:
	var fallback := ""
	for animation_name: String in names:
		if animation_name == "RESET":
			continue
		var lowered := animation_name.to_lower()
		var required := true
		for token: String in required_tokens:
			if not lowered.contains(token):
				required = false
				break
		if not required:
			continue
		if fallback.is_empty():
			fallback = animation_name
		var rejected := false
		for token: String in REJECT_ACTION_TOKENS:
			if lowered.contains(token):
				rejected = true
				break
		if not rejected:
			return animation_name
	return fallback


func _configure_locomotion_loops(animation_player: AnimationPlayer, locomotion: Dictionary) -> void:
	for key: String in ["idle", "walk", "run"]:
		var animation_name := String(locomotion.get(key, ""))
		if animation_name.is_empty() or not animation_player.has_animation(animation_name):
			continue
		var animation := animation_player.get_animation(animation_name)
		if animation != null:
			animation.loop_mode = Animation.LOOP_LINEAR


func _hide_procedural_visuals(visual: Node3D, authored: Node3D, police: bool) -> void:
	for child: Node in visual.get_children():
		if child == authored:
			continue
		if child is Label3D:
			(child as Label3D).visible = false
			continue
		if police and child.name in POLICE_DIRECT_KEEP:
			continue
		_hide_geometry_recursive(child)
	var label := visual.get_node_or_null("UniformPoliceLabel") as Label3D
	if label != null:
		label.visible = false


func _hide_geometry_recursive(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).visible = false
	if node is Label3D:
		(node as Label3D).visible = false
	for child: Node in node.get_children():
		_hide_geometry_recursive(child)


func _stature_scale(seed_value: int) -> float:
	var bucket := posmod(seed_value * 37 + 11, 9)
	return 0.96 + float(bucket) * 0.01


func _resolve_state(previous_state: String, speed: float) -> String:
	match previous_state:
		"run":
			if speed < RUN_EXIT_SPEED_MPS:
				return "idle" if speed < IDLE_ENTER_SPEED_MPS else "walk"
			return "run"
		"walk":
			if speed >= RUN_ENTER_SPEED_MPS:
				return "run"
			if speed < IDLE_ENTER_SPEED_MPS:
				return "idle"
			return "walk"
		_:
			if speed >= RUN_ENTER_SPEED_MPS:
				return "run"
			if speed > IDLE_EXIT_SPEED_MPS:
				return "walk"
			return "idle"


func _playback_scale(state: String, speed: float) -> float:
	match state:
		"walk":
			return clampf(speed / WALK_REFERENCE_SPEED_MPS, WALK_PLAYBACK_MIN, WALK_PLAYBACK_MAX)
		"run":
			return clampf(speed / RUN_REFERENCE_SPEED_MPS, RUN_PLAYBACK_MIN, RUN_PLAYBACK_MAX)
		_:
			return 1.0


func _speed_for_binding(binding: Dictionary, delta: float) -> float:
	var actor := binding.get("actor") as CharacterBody3D
	if actor == null:
		return 0.0
	if not bool(binding.get("observe_transform_delta", false)):
		return Vector2(actor.velocity.x, actor.velocity.z).length()
	var source := binding.get("motion_source") as Node3D
	if not is_instance_valid(source):
		return 0.0
	var current := source.global_position
	var previous_value: Variant = binding.get("last_motion_position")
	binding["last_motion_position"] = current
	if delta <= 0.0 or not (previous_value is Vector3):
		return 0.0
	var previous: Vector3 = previous_value
	var displacement := Vector2(current.x - previous.x, current.z - previous.z).length()
	if displacement > TRANSFORM_TELEPORT_GUARD_M:
		return 0.0
	return clampf(displacement / delta, 0.0, TRANSFORM_SPEED_MAX_MPS)


func _update_binding(binding: Dictionary, delta: float = 0.0) -> void:
	var actor := binding.get("actor") as CharacterBody3D
	var animation_player := binding.get("animation_player") as AnimationPlayer
	if actor == null or animation_player == null:
		return
	var locomotion_value: Variant = binding.get("locomotion")
	if not (locomotion_value is Dictionary):
		return
	var locomotion: Dictionary = locomotion_value
	var speed := _speed_for_binding(binding, delta)
	var previous_state := String(binding.get("state", "idle"))
	var target_state := _resolve_state(previous_state, speed)
	var target_animation := String(locomotion.get(target_state, ""))
	if target_animation.is_empty():
		return
	animation_player.speed_scale = _playback_scale(target_state, speed)
	var previous_animation := String(binding.get("animation", ""))
	if previous_animation != target_animation or animation_player.current_animation != target_animation or not animation_player.is_playing():
		animation_player.play(target_animation, BLEND_SECONDS)
	binding["state"] = target_state
	binding["animation"] = target_animation


func update_actor_now(actor: NpcAgent, delta: float = 0.0) -> void:
	if actor == null:
		return
	var value: Variant = _bindings.get(actor.get_instance_id())
	if value is Dictionary:
		var binding: Dictionary = value
		_update_binding(binding, delta)


func is_actor_authored(actor: NpcAgent) -> bool:
	if actor == null:
		return false
	return actor.get_meta(APPLIED_META, false) == true and _bindings.has(actor.get_instance_id())


func binding_count() -> int:
	return _bindings.size()


func resolved_source_path() -> String:
	return _resolved_source_path

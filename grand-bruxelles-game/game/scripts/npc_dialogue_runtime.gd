class_name NpcDialogueRuntime
extends Node

const HUMANOID_VISUAL_SCRIPT := preload("res://game/scripts/humanoid_visual.gd")
const SAMIR_ID := "npc-midi-samir"
const SAMIR_NAME := "Samir"
const SAMIR_NEIGHBORHOOD := "Saint-Gilles"
const SAMIR_SPAWN := Vector3(-647.8, 0.90, 620.2)

@export var player_path: NodePath = NodePath("../Player")
@export var interaction_range_m: float = 6.0

var _player: CharacterBody3D = null
var _agent: NpcAgent = null
var _client: NpcLlmClient = null
var _session: NpcDialogueSession = null
var _prompt_label: Label = null
var _panel: Control = null
var _output_label: Label = null
var _input: LineEdit = null
var _dialogue_open: bool = false
var _busy: bool = false


func _ready() -> void:
	_player = get_node_or_null(player_path) as CharacterBody3D
	_client = NpcLlmClient.new()
	_client.name = "NpcLlmClient"
	var endpoint_override := OS.get_environment("GB_NPC_LLM_ENDPOINT")
	if not endpoint_override.is_empty():
		_client.endpoint = endpoint_override
	var model_override := OS.get_environment("GB_NPC_LLM_MODEL")
	if not model_override.is_empty():
		_client.model_name = model_override
	add_child(_client)
	_session = NpcDialogueSession.new(SAMIR_ID, SAMIR_NAME, SAMIR_NEIGHBORHOOD)
	_spawn_dialogue_npc()
	_build_dialogue_ui()
	set_process_input(true)
	print("NPC_DIALOGUE_RUNTIME_READY npc_id=%s" % SAMIR_ID)


func _process(_delta: float) -> void:
	if _prompt_label == null or not is_instance_valid(_agent) or not is_instance_valid(_player):
		return
	var nearby := _player.global_position.distance_to(_agent.global_position) <= interaction_range_m
	_prompt_label.visible = nearby and not _dialogue_open
	if nearby:
		_prompt_label.text = "SAMIR · F pour parler"
	elif _dialogue_open:
		_close_dialogue()


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F and not _dialogue_open and can_player_talk():
		_open_dialogue()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and _dialogue_open:
		_close_dialogue()
		get_viewport().set_input_as_handled()


func can_player_talk() -> bool:
	return (
		is_instance_valid(_agent)
		and is_instance_valid(_player)
		and _agent.active
		and _player.global_position.distance_to(_agent.global_position) <= interaction_range_m
	)


func dialogue_agent() -> NpcAgent:
	return _agent


func dialogue_session() -> NpcDialogueSession:
	return _session


func build_blackboard() -> Dictionary:
	if not is_instance_valid(_agent) or not is_instance_valid(_player):
		return {
			"threat": 0.0,
			"hp": 100.0,
			"police": false,
			"distance": 9999.0,
			"zone": "Midi",
			"combat_enabled": false,
			"aggression": 0.20,
		}
	return {
		"threat": clampf(_agent.behavior.alert_level / 100.0, 0.0, 1.0),
		"hp": clampf(float(_agent.get_meta("hp", 100.0)), 0.0, 100.0),
		"police": bool(_agent.get_meta("police_nearby", false)),
		"distance": _player.global_position.distance_to(_agent.global_position),
		"zone": "Midi",
		"combat_enabled": bool(_agent.get_meta("combat_enabled", false)),
		"aggression": clampf(float(_agent.get_meta("aggression", 0.20)), 0.0, 1.0),
	}


func apply_decision_to_agent(agent: NpcAgent, decision: Dictionary, blackboard: Dictionary, player_position: Vector3) -> bool:
	if not is_instance_valid(agent):
		return false
	var action := String(decision.get("action", "")).strip_edges().to_lower()
	if not NpcDialogueRules.allowed_actions(blackboard).has(action):
		return false

	agent.set_meta("dialogue_action", action)
	match action:
		"idle":
			agent.behavior.calm_down(100.0)
			agent.behavior.state = NpcBehaviorModel.State.IDLE
			agent.movement_held = true
		"walk":
			agent.movement_held = false
			var home_value: Variant = agent.get_meta("dialogue_home", agent.get_world_position())
			var home := home_value as Vector3 if home_value is Vector3 else agent.get_world_position()
			agent.set_destination(home + Vector3(2.0, 0.0, -1.5))
		"alert":
			agent.behavior.apply_stimulus(25.0, player_position)
			agent.movement_held = true
		"flee":
			agent.movement_held = false
			agent.behavior.apply_stimulus(60.0, player_position)
		"hurt":
			# Dialogue may describe pain, but damage/hit resolution is never delegated to the LLM.
			agent.movement_held = true
			agent.set_meta("dialogue_reaction", "hurt")
		"defend", "fight":
			# Combat runtime consumes this validated intent in Lot 3; no hit/damage is applied here.
			agent.set_meta("dialogue_combat_intent", action)
		_:
			return false
	return true


func submit_text_for_test(player_text: String) -> Dictionary:
	return await _request_dialogue(player_text)


func _request_dialogue(player_text: String) -> Dictionary:
	var clean_text := player_text.strip_edges()
	if clean_text.is_empty() or _client == null or _session == null or not is_instance_valid(_agent):
		return {}
	var blackboard := build_blackboard()
	var decision: Dictionary = await _client.request_decision(_session, clean_text, blackboard)
	if not apply_decision_to_agent(_agent, decision, blackboard, _player.global_position if is_instance_valid(_player) else _agent.global_position):
		decision = NpcDialogueRules.fallback(blackboard, "fallback_apply_reject")
		apply_decision_to_agent(_agent, decision, blackboard, _player.global_position if is_instance_valid(_player) else _agent.global_position)
	return decision


func _on_text_submitted(player_text: String) -> void:
	if _busy:
		return
	var clean_text := player_text.strip_edges()
	if clean_text.is_empty():
		return
	_busy = true
	_input.editable = false
	_output_label.text = "VOUS — %s\nSAMIR — …" % clean_text
	var decision: Dictionary = await _request_dialogue(clean_text)
	var line := String(decision.get("line", "…"))
	var action := String(decision.get("action", "idle")).to_upper()
	var source := "LLM" if bool(decision.get("accepted", false)) else "OFFLINE"
	_output_label.text = "VOUS — %s\nSAMIR — %s\n[%s · %s]" % [clean_text, line, action, source]
	_input.clear()
	_input.editable = true
	_input.grab_focus()
	_busy = false


func _open_dialogue() -> void:
	_dialogue_open = true
	_panel.visible = true
	_prompt_label.visible = false
	_output_label.text = "SAMIR — Ouais ?"
	_input.clear()
	_input.grab_focus()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_player_locked(true)


func _close_dialogue() -> void:
	_dialogue_open = false
	_busy = false
	if _panel != null:
		_panel.visible = false
	if _input != null:
		_input.release_focus()
	_set_player_locked(false)
	if not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _set_player_locked(locked: bool) -> void:
	if not is_instance_valid(_player):
		return
	_player.set_physics_process(not locked)
	_player.set_process_unhandled_input(not locked)
	if locked:
		_player.velocity = Vector3.ZERO


func _spawn_dialogue_npc() -> void:
	var world := get_parent() as Node3D
	if world == null:
		return
	_agent = NpcAgent.new()
	_agent.name = "NpcDialogueSamir"
	_agent.add_to_group("npc_dialogue_target")
	_agent.set_spawn_context(NpcBehaviorModel.Role.CIVILIAN, 3101, SAMIR_SPAWN)
	_agent.set_meta("npc_id", SAMIR_ID)
	_agent.set_meta("dialogue_home", SAMIR_SPAWN)
	_agent.set_meta("hp", 100.0)
	_agent.set_meta("combat_enabled", false)
	_agent.set_meta("aggression", 0.20)
	_agent.movement_held = true

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.78
	collision.shape = capsule
	_agent.add_child(collision)

	var visual := Node3D.new()
	visual.name = "VisualUpgrade"
	visual.set_script(HUMANOID_VISUAL_SCRIPT)
	_agent.add_child(visual)

	var name_label := Label3D.new()
	name_label.name = "DialogueNameLabel"
	name_label.position = Vector3(0.0, 2.18, 0.0)
	name_label.text = "SAMIR"
	name_label.font_size = 28
	name_label.outline_size = 8
	_agent.add_child(name_label)

	world.add_child(_agent)


func _build_dialogue_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "NpcDialogueLayer"
	add_child(layer)

	_prompt_label = Label.new()
	_prompt_label.name = "NpcDialoguePrompt"
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_label.position = Vector2(-120.0, -92.0)
	_prompt_label.size = Vector2(240.0, 34.0)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.theme_override_font_sizes.font_size = 18
	_prompt_label.visible = false
	layer.add_child(_prompt_label)

	_panel = VBoxContainer.new()
	_panel.name = "NpcDialoguePanel"
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.position = Vector2(-330.0, -210.0)
	_panel.size = Vector2(660.0, 150.0)
	_panel.visible = false
	layer.add_child(_panel)

	_output_label = Label.new()
	_output_label.name = "NpcDialogueOutput"
	_output_label.custom_minimum_size = Vector2(660.0, 82.0)
	_output_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_output_label.theme_override_font_sizes.font_size = 18
	_panel.add_child(_output_label)

	_input = LineEdit.new()
	_input.name = "NpcDialogueInput"
	_input.placeholder_text = "Parle à Samir… puis Entrée"
	_input.max_length = 180
	_input.text_submitted.connect(_on_text_submitted)
	_panel.add_child(_input)

	var hint := Label.new()
	hint.name = "NpcDialogueHint"
	hint.text = "Entrée · envoyer    Échap · fermer"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.theme_override_font_sizes.font_size = 13
	_panel.add_child(hint)

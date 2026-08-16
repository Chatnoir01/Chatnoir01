extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var world := Node3D.new()
	world.name = "Main"
	root.add_child(world)
	var player := CharacterBody3D.new()
	player.name = "Player"
	player.position = Vector3(-652.0, 1.05, 621.0)
	world.add_child(player)
	var runtime := NpcDialogueRuntime.new()
	runtime.name = "NpcDialogueRuntime"
	world.add_child(runtime)
	await process_frame

	var agent := runtime.dialogue_agent()
	if not is_instance_valid(agent) or String(agent.get_meta("npc_id", "")) != NpcDialogueRuntime.SAMIR_ID:
		_fail("Samir dialogue NPC was not spawned")
		return
	if not runtime.can_player_talk():
		_fail("player spawn is not inside Samir interaction range")
		return
	if runtime.get_node_or_null("NpcDialogueLayer/NpcDialoguePanel") == null:
		_fail("playable dialogue panel was not created")
		return

	agent.behavior.alert_level = 30.0
	var board := runtime.build_blackboard()
	if bool(board.get("combat_enabled", true)):
		_fail("Lot 1 dialogue NPC must not enable combat")
		return
	var decision := NpcDialogueRules.filter_output("action: alert\nline: Hé, doucement là.", board)
	if not bool(decision.get("accepted", false)):
		_fail("valid alert response was not accepted")
		return
	if not runtime.apply_decision_to_agent(agent, decision, board, player.global_position):
		_fail("accepted dialogue action was not applied to NPC")
		return
	if String(agent.get_meta("dialogue_action", "")) != "alert":
		_fail("NPC did not record applied alert action")
		return

	var illegal := {"action": "fight", "line": "Viens.", "accepted": true, "source": "llm"}
	if runtime.apply_decision_to_agent(agent, illegal, board, player.global_position):
		_fail("out-of-rules fight reached NPC runtime")
		return

	print("NPC_DIALOGUE_RUNTIME_OK npc_id=%s action=%s" % [agent.get_meta("npc_id"), agent.get_meta("dialogue_action")])
	quit(0)

func _fail(message: String) -> void:
	printerr("NPC_DIALOGUE_RUNTIME_FAIL: %s" % message)
	quit(1)

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

	var decision: Dictionary = await runtime.submit_text_for_test("Bonsoir, ça va ?")
	if not bool(decision.get("accepted", false)):
		_fail("playable runtime did not receive accepted real-model response: %s" % str(decision))
		return
	var agent := runtime.dialogue_agent()
	var action := String(decision.get("action", ""))
	if not NpcDialogueRules.allowed_actions(runtime.build_blackboard()).has(action):
		_fail("playable runtime real-model action violates current rules")
		return
	if String(agent.get_meta("dialogue_action", "")) != action:
		_fail("real-model decision was not applied to Samir")
		return
	if not NpcDialogueRules.line_allowed(String(decision.get("line", ""))):
		_fail("playable runtime returned forbidden line")
		return

	print("NPC_DIALOGUE_RUNTIME_LIVE_OK npc_id=%s action=%s line=%s" % [agent.get_meta("npc_id"), action, decision.get("line")])
	quit(0)

func _fail(message: String) -> void:
	printerr("NPC_DIALOGUE_RUNTIME_LIVE_FAIL: %s" % message)
	quit(1)

extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/authored_npc_visual_runtime.gd")


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	push_error("AUTHORED_NPC_VISUAL_RUNTIME_FAIL: %s" % message)
	quit(1)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	_fail(message)
	return false


func _make_actor(actor_name: String, role_value: int, seed_value: int) -> NpcAgent:
	var actor := NpcAgent.new()
	actor.name = actor_name
	actor.role = role_value
	actor.variation_seed = seed_value
	var visual := Node3D.new()
	visual.name = "VisualUpgrade"
	actor.add_child(visual)
	var procedural := MeshInstance3D.new()
	procedural.name = "Torso"
	procedural.mesh = BoxMesh.new()
	visual.add_child(procedural)
	return actor


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _run() -> void:
	var runtime := RUNTIME_SCRIPT.new()
	root.add_child(runtime)
	await process_frame

	var civilian := _make_actor("AuthoredCivilian", NpcBehaviorModel.Role.CIVILIAN, 17)
	root.add_child(civilian)
	await process_frame
	if not _expect(runtime.apply_to_actor(civilian), "civilian should accept the committed authored rig"):
		return
	var civilian_visual := civilian.get_node_or_null("VisualUpgrade") as Node3D
	var civilian_authored := civilian_visual.get_node_or_null("AuthoredNpcCharacter") as Node3D
	if not _expect(civilian_authored != null, "civilian authored character node is missing"):
		return
	if not _expect(not (civilian_visual.get_node("Torso") as MeshInstance3D).visible, "procedural civilian torso must be hidden after authored rig binds"):
		return
	var skeletons := civilian_authored.find_children("*", "Skeleton3D", true, false)
	if not _expect(not skeletons.is_empty(), "civilian authored character must contain a Skeleton3D"):
		return
	var animation_player := _find_animation_player(civilian_authored)
	if not _expect(animation_player != null, "civilian authored character must expose AnimationPlayer"):
		return
	civilian.velocity = Vector3(1.7, 0.0, 0.0)
	runtime.update_actor_now(civilian)
	if not _expect(animation_player.is_playing(), "authored civilian locomotion should play when the NPC moves"):
		return
	if not _expect(animation_player.current_animation.to_lower().contains("walk"), "moving civilian should resolve a walk clip"):
		return
	if not _expect(String(civilian.get_meta("authored_npc_motion_source", "")) == "actor_velocity", "normal NpcAgent locomotion must remain velocity-driven"):
		return
	var before_count := runtime.binding_count()
	if not _expect(runtime.apply_to_actor(civilian), "authored application should be idempotent"):
		return
	if not _expect(runtime.binding_count() == before_count, "idempotent authored application must not duplicate bindings"):
		return

	var ambient_parent := Node3D.new()
	ambient_parent.name = "AmbientPedestrian_Test"
	ambient_parent.add_to_group("ambient_pedestrian")
	var ambient_proxy := _make_actor("ProfiledNpcProxy", NpcBehaviorModel.Role.CIVILIAN, 23)
	ambient_proxy.process_mode = Node.PROCESS_MODE_DISABLED
	ambient_parent.add_child(ambient_proxy)
	root.add_child(ambient_parent)
	await process_frame
	if not _expect(runtime.apply_to_actor(ambient_proxy), "disabled Midi profiled proxy should accept the authored rig"):
		return
	if not _expect(String(ambient_proxy.get_meta("authored_npc_motion_source", "")) == "parent_transform", "Midi profiled proxy must observe its moving ambient parent"):
		return
	if not _expect(ambient_proxy.velocity.is_zero_approx(), "Midi visual proxy should not need to own gameplay velocity"):
		return
	var ambient_visual := ambient_proxy.get_node("VisualUpgrade") as Node3D
	var ambient_authored := ambient_visual.get_node_or_null("AuthoredNpcCharacter") as Node3D
	if not _expect(ambient_authored != null, "Midi ambient proxy authored character node is missing"):
		return
	var ambient_animation_player := _find_animation_player(ambient_authored)
	if not _expect(ambient_animation_player != null, "Midi ambient proxy authored character must expose AnimationPlayer"):
		return
	ambient_parent.position += Vector3(0.03, 0.0, 0.0)
	runtime.update_actor_now(ambient_proxy, 1.0 / 60.0)
	if not _expect(ambient_animation_player.is_playing(), "moving Midi ambient parent should drive authored proxy locomotion"):
		return
	if not _expect(ambient_animation_player.current_animation.to_lower().contains("walk"), "moving Midi ambient parent should resolve a walk clip instead of idle"):
		return

	var police := _make_actor("AuthoredPolice", NpcBehaviorModel.Role.POLICE, 31)
	var police_visual := police.get_node("VisualUpgrade") as Node3D
	var vest := MeshInstance3D.new()
	vest.name = "HiVisVest"
	vest.mesh = BoxMesh.new()
	police_visual.add_child(vest)
	var label := Label3D.new()
	label.name = "UniformPoliceLabel"
	label.text = "POLICE"
	police_visual.add_child(label)
	root.add_child(police)
	await process_frame
	if not _expect(runtime.apply_to_actor(police), "police should accept the committed authored rig"):
		return
	if not _expect(police_visual.get_node_or_null("AuthoredNpcCharacter") != null, "police authored character node is missing"):
		return
	if not _expect(vest.visible, "police identity vest should stay visible over the authored body"):
		return
	if not _expect(not label.visible, "floating police label must remain hidden"):
		return

	print("AUTHORED_NPC_VISUAL_RUNTIME_OK: source=%s bindings=%d civilian_clip=%s ambient_clip=%s" % [runtime.resolved_source_path(), runtime.binding_count(), animation_player.current_animation, ambient_animation_player.current_animation])
	civilian.queue_free()
	ambient_parent.queue_free()
	police.queue_free()
	runtime.queue_free()
	quit(0)

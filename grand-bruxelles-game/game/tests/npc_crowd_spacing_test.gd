extends SceneTree

func _init() -> void:
	var spacing := NpcCrowdSpacing.new()
	spacing.personal_space_m = 0.95
	spacing.detour_forward_m = 0.85
	spacing.detour_side_m = 0.72

	var a_pos := Vector3(0.0, 0.0, 0.0)
	var b_pos := Vector3(0.55, 0.0, 0.0)
	var target := Vector3(0.0, 0.0, -8.0)
	if not spacing.needs_spacing(a_pos, b_pos):
		_fail("agents inside personal-space threshold must trigger spacing")
		return

	var a_detour := spacing.detour_target(a_pos, target, b_pos, 11, 22)
	var b_detour := spacing.detour_target(b_pos, target, a_pos, 22, 11)
	if absf(a_detour.x - b_detour.x) < 0.9:
		_fail("paired civilians must receive opposing lateral detours")
		return
	if a_detour.z >= a_pos.z or b_detour.z >= b_pos.z:
		_fail("spacing detour must preserve forward progress toward destination")
		return

	var repeat := spacing.detour_target(a_pos, target, b_pos, 11, 22)
	if repeat != a_detour:
		_fail("same seeds and geometry must produce deterministic spacing")
		return

	var far_peer := Vector3(2.0, 0.0, 0.0)
	if spacing.needs_spacing(a_pos, far_peer):
		_fail("agents outside personal-space threshold must not be detoured")
		return

	print("NPC_CROWD_SPACING_OK")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	print("NPC_CROWD_SPACING_FAIL: %s" % message)
	quit(1)

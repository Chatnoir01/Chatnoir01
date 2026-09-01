extends SceneTree

const SOURCE_PATH := "res://scripts/automatic_road_direct_spawn.gd"

func _init() -> void:
	var source := FileAccess.get_file_as_string(SOURCE_PATH)
	if source.is_empty():
		_fail("automatic road direct-spawn source missing")
		return

	# The startup resolver must never choose an arbitrary recursively discovered
	# Player. Shared-environment ownership is limited to the canonical production
	# Main, including the validated root-level Viewport -> Main mount.
	if source.contains("get_tree().root.find_child(\"Player\", true, false)"):
		_fail("recursive root Player lookup can capture a foreign nested Player")
		return
	if not source.contains("_authoritative_player"):
		_fail("automatic road spawn has no explicit authoritative Player resolver")
		return

	print("AUTOMATIC_ROAD_PLAYER_AUTHORITY_OK")
	quit(0)

func _fail(message: String) -> void:
	push_error("AUTOMATIC_ROAD_PLAYER_AUTHORITY_FAIL: %s" % message)
	quit(1)

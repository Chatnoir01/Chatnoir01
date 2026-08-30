extends SceneTree

const TARGET_PATH := "res://data/qa/brussels_region_playability_target.json"
const EXPECTED_NISCODES := [
	"21001", "21002", "21003", "21004", "21005", "21006", "21007", "21008", "21009", "21010",
	"21011", "21012", "21013", "21014", "21015", "21016", "21017", "21018", "21019"
]
const REQUIRED_ANCHORS := ["midi", "anneessens", "bourse", "grand_place", "rogier", "gare_du_nord", "ixelles", "atomium", "jette"]

func _init() -> void:
	var payload := _load_json(TARGET_PATH)
	if payload.is_empty():
		return
	if payload.get("schema") != "grand-bruxelles-region-playability-target-v1":
		_fail("schema drift")
		return
	if payload.get("completion_claimed") != false:
		_fail("Brussels Region cannot be claimed complete without runtime proof")
		return

	var policy: Dictionary = payload.get("policy", {})
	for key in [
		"all_19_municipalities_required",
		"single_connected_gameplay_network_required",
		"continuous_ground_or_explicit_runtime_transport_required",
		"collision_required",
		"stable_spawn_required",
		"load_without_crash_required",
		"visual_runtime_evidence_required",
		"no_isolated_listable_zone",
		"no_source_free_geometry_promotion"
	]:
		if policy.get(key) != true:
			_fail("missing regional policy gate: %s" % key)
			return

	var municipalities: Array = payload.get("required_municipalities", [])
	if municipalities.size() != 19:
		_fail("expected exactly 19 Brussels municipalities")
		return
	var niscodes: Array[String] = []
	var ids: Dictionary = {}
	for row_value in municipalities:
		if not row_value is Dictionary:
			_fail("malformed municipality row")
			return
		var row: Dictionary = row_value
		var nis := str(row.get("niscode", ""))
		var municipality_id := str(row.get("id", ""))
		if nis.is_empty() or municipality_id.is_empty() or str(row.get("name", "")).is_empty():
			_fail("incomplete municipality identity")
			return
		if ids.has(municipality_id):
			_fail("duplicate municipality id: %s" % municipality_id)
			return
		ids[municipality_id] = true
		niscodes.append(nis)
	if niscodes != EXPECTED_NISCODES:
		_fail("Brussels 19-municipality NIS coverage drift")
		return

	var anchors: Array = payload.get("required_city_network_anchors", [])
	for anchor in REQUIRED_ANCHORS:
		if not anchors.has(anchor):
			_fail("missing required city network anchor: %s" % anchor)
			return

	var gate: Dictionary = payload.get("promotion_gate", {})
	var requirements: Array = gate.get("municipality_may_be_marked_playable_only_when", [])
	if requirements.size() < 7:
		_fail("regional playable promotion gate is incomplete")
		return

	print("BRUSSELS_REGION_PLAYABILITY_TARGET_OK: municipalities=19 anchors=%d completion_claimed=false" % anchors.size())
	quit(0)

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_fail("missing file: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("cannot open file: %s" % path)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_fail("invalid JSON object: %s" % path)
		return {}
	return parsed

func _fail(message: String) -> void:
	push_error("BRUSSELS_REGION_PLAYABILITY_TARGET_FAIL: %s" % message)
	quit(1)

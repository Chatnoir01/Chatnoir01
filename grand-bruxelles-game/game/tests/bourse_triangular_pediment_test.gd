extends SceneTree
const SCRIPT := preload("res://game/scripts/bourse_triangular_pediment_runtime.gd")
const CANDIDATE_PATH := "res://data/qa/bourse_triangular_pediment_candidate.json"
func _initialize() -> void: call_deferred("_run")
func _fail(message: String) -> void: push_error("BOURSE_TRIANGULAR_PEDIMENT_FAIL: %s" % message); quit(1)
func _run() -> void:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CANDIDATE_PATH))
    if typeof(parsed) != TYPE_DICTIONARY: _fail("candidate JSON invalid"); return
    var data: Dictionary = parsed as Dictionary
    if str(data.get("schema", "")) != "grand-bruxelles-bourse-triangular-pediment-candidate-v2": _fail("schema drifted"); return
    var source: Dictionary = data.get("source_contract", {}) as Dictionary
    var fact := str(source.get("heritage_fact", ""))
    if not fact.contains("six Corinthian columns") or not fact.contains("triangular pediment"): _fail("heritage fact missing"); return
    var env: Dictionary = data.get("authoritative_front_envelope", {}) as Dictionary
    var vis: Dictionary = data.get("provisional_visualization", {}) as Dictionary
    var span := float(env.get("span_m", 0.0)); var y_max := float(env.get("y_max_m", 0.0)); var width := float(vis.get("pediment_width_m", 0.0)); var rise := float(vis.get("pediment_rise_m", 0.0)); var base_y := float(vis.get("pediment_base_y_m", 0.0))
    if width <= 20.0 or width >= span or rise <= 0.0 or base_y + rise >= y_max: _fail("candidate escapes envelope"); return
    var runtime := SCRIPT.new(); root.add_child(runtime); await process_frame; await process_frame
    if runtime.diagnostic_pediment_count() != 1: _fail("expected one pediment"); return
    if bool(runtime.get_meta("runtime_approved", true)) or bool(runtime.get_meta("realism_complete", true)): _fail("candidate claims approval"); return
    var pediment := runtime.get_node_or_null("BourseTriangularPediment") as MeshInstance3D
    if pediment == null or pediment.mesh == null or pediment.material_override == null: _fail("pediment missing"); return
    if str(pediment.material_override.get_meta("material_family", "")) != "brussels_source_verified_white_stone": _fail("material family drifted"); return
    print("BOURSE_TRIANGULAR_PEDIMENT_OK: count=1 width=%.3f rise=%.3f top_y=%.3f y_max=%.3f" % [width, rise, base_y + rise, y_max]); quit(0)

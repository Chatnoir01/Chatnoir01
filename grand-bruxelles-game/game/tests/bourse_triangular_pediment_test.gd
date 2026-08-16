extends SceneTree

const SCRIPT := preload("res://game/scripts/bourse_triangular_pediment_runtime.gd")
const CANDIDATE_PATH := "res://data/qa/bourse_triangular_pediment_candidate.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_TRIANGULAR_PEDIMENT_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    if not FileAccess.file_exists(CANDIDATE_PATH):
        _fail("candidate JSON missing")
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CANDIDATE_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("candidate JSON invalid")
        return
    var data := parsed as Dictionary
    if str(data.get("schema", "")) != "grand-bruxelles-bourse-triangular-pediment-candidate-v1":
        _fail("candidate schema drifted")
        return
    if bool(data.get("runtime_approved", true)) or bool(data.get("realism_complete", true)):
        _fail("provisional candidate claims approval")
        return

    var source_contract: Dictionary = data.get("source_contract", {})
    var heritage_fact := str(source_contract.get("heritage_fact", ""))
    if not heritage_fact.contains("six Corinthian columns"):
        _fail("six-column source fact missing")
        return
    if not heritage_fact.contains("triangular pediment"):
        _fail("triangular-pediment source fact missing")
        return

    var envelope: Dictionary = data.get("authoritative_front_envelope", {})
    var visual: Dictionary = data.get("provisional_visualization", {})
    var span := float(envelope.get("span_m", 0.0))
    var y_max := float(envelope.get("y_max_m", 0.0))
    var width := float(visual.get("pediment_width_m", 0.0))
    var rise := float(visual.get("pediment_rise_m", 0.0))
    var base_y := float(visual.get("pediment_base_y_m", 0.0))
    var depth := float(visual.get("pediment_depth_m", 0.0))
    if span <= 30.0 or span >= 33.0:
        _fail("authoritative span drifted")
        return
    if width <= 20.0 or width >= span:
        _fail("pediment width is not bounded by authoritative span")
        return
    if rise <= 0.0 or depth <= 0.0:
        _fail("pediment rise/depth invalid")
        return
    if base_y + rise >= y_max:
        _fail("pediment exceeds authoritative vertical envelope")
        return

    var runtime := SCRIPT.new()
    runtime.name = "BourseTriangularPedimentTest"
    root.add_child(runtime)
    await process_frame
    await process_frame

    if runtime.diagnostic_pediment_count() != 1:
        _fail("expected exactly one triangular pediment")
        return
    if bool(runtime.get_meta("runtime_approved", true)):
        _fail("runtime_approved must remain false")
        return
    if bool(runtime.get_meta("realism_complete", true)):
        _fail("realism_complete must remain false")
        return
    if str(runtime.get_meta("source_identity", "")) != "triangular_pediment":
        _fail("source identity metadata drifted")
        return
    if abs(float(runtime.get_meta("pediment_width_m", 0.0)) - width) > 0.001:
        _fail("runtime width differs from candidate")
        return
    if float(runtime.get_meta("pediment_top_y_m", 999.0)) >= y_max:
        _fail("runtime pediment top escapes envelope")
        return

    var pediment := runtime.get_node_or_null("BourseTriangularPediment") as MeshInstance3D
    if pediment == null or pediment.mesh == null:
        _fail("pediment mesh missing")
        return
    if pediment.mesh.get_surface_count() != 1:
        _fail("pediment should remain one simple surface")
        return
    if pediment.material_override == null:
        _fail("source-verified white-stone material missing")
        return
    if str(pediment.material_override.get_meta("material_family", "")) != "brussels_source_verified_white_stone":
        _fail("pediment material family drifted")
        return
    if bool(pediment.material_override.get_meta("masonry_joints_authored", true)):
        _fail("pediment must not invent masonry joints")
        return
    if bool(pediment.material_override.get_meta("openings_authored", true)):
        _fail("pediment must not invent openings")
        return

    print(
        "BOURSE_TRIANGULAR_PEDIMENT_OK: count=1 width=%.3f rise=%.3f top_y=%.3f y_max=%.3f runtime_approved=false" %
        [width, rise, base_y + rise, y_max]
    )
    runtime.queue_free()
    quit(0)

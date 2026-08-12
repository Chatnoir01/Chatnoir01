extends SceneTree

const SCRIPT := preload("res://game/scripts/bourse_portico_articulation.gd")
const CANDIDATE_PATH := "res://data/qa/bourse_portico_articulation_candidate.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_PORTICO_ARTICULATION_FAIL: %s" % message)
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
    if str(data.get("schema", "")) != "grand-bruxelles-bourse-portico-articulation-candidate-v1":
        _fail("candidate schema drifted")
        return
    if bool(data.get("runtime_approved", true)) or bool(data.get("realism_complete", true)):
        _fail("provisional candidate claims approval")
        return

    var source_contract: Dictionary = data.get("source_contract", {})
    if not str(source_contract.get("heritage_front_fact", "")).contains("six Corinthian columns"):
        _fail("six-column heritage fact missing")
        return
    var rear_fact := str(source_contract.get("heritage_rear_fact", ""))
    if not rear_fact.contains("pilasters"):
        _fail("rear pilaster heritage fact missing")
        return
    if not rear_fact.contains("clock"):
        _fail("rear clock heritage fact missing")
        return
    if not rear_fact.contains("oval lights"):
        _fail("rear oval-light heritage fact missing")
        return

    var articulation := SCRIPT.new()
    articulation.name = "BoursePorticoArticulationTest"
    root.add_child(articulation)
    await process_frame
    await process_frame

    if articulation.diagnostic_column_count() != 6:
        _fail("expected six source-backed columns, got %d" % articulation.diagnostic_column_count())
        return
    if articulation.diagnostic_step_count() != 16:
        _fail("expected sixteen bounded stair treads, got %d" % articulation.diagnostic_step_count())
        return
    if articulation.diagnostic_pilaster_count() != 4:
        _fail("expected four provisional rear pilasters, got %d" % articulation.diagnostic_pilaster_count())
        return
    if articulation.diagnostic_opening_count() != 3:
        _fail("expected central plus two side opening proxies, got %d" % articulation.diagnostic_opening_count())
        return
    if articulation.diagnostic_oval_light_count() != 2:
        _fail("expected two source-backed oval-light proxies, got %d" % articulation.diagnostic_oval_light_count())
        return
    if articulation.diagnostic_entablature_count() != 1:
        _fail("expected one entablature proxy")
        return
    if articulation.diagnostic_clock_count() != 1:
        _fail("expected one source-backed clock proxy")
        return
    if bool(articulation.get_meta("runtime_approved", true)):
        _fail("runtime_approved must remain false")
        return
    if bool(articulation.get_meta("realism_complete", true)):
        _fail("realism_complete must remain false")
        return

    var envelope: Dictionary = data.get("authoritative_front_envelope", {})
    var visual: Dictionary = data.get("provisional_visualization", {})
    var span := float(envelope.get("span_m", 0.0))
    var y_max := float(envelope.get("y_max_m", 0.0))
    var stair_width := float(visual.get("stair_width_m", 0.0))
    var column_top := (
        float(visual.get("column_base_y_m", 0.0))
        + float(visual.get("column_base_height_m", 0.0))
        + float(visual.get("column_shaft_height_m", 0.0))
        + float(visual.get("column_capital_height_m", 0.0))
    )
    var entablature_top := (
        float(visual.get("entablature_center_y_m", 0.0))
        + float(visual.get("entablature_height_m", 0.0)) * 0.5
    )
    var rear_pilaster_top := (
        float(visual.get("rear_detail_base_y_m", 0.0))
        + float(visual.get("rear_pilaster_height_m", 0.0))
    )
    var clock_top := float(visual.get("clock_center_y_m", 0.0)) + float(visual.get("clock_radius_m", 0.0))
    var oval_top := float(visual.get("oval_light_center_y_m", 0.0)) + float(visual.get("oval_light_radius_y_m", 0.0))
    if span <= 30.0 or span >= 33.0:
        _fail("authoritative front span drifted: %.3f" % span)
        return
    if stair_width >= span or stair_width < 20.0:
        _fail("stair width is outside authoritative front envelope")
        return
    if column_top >= y_max:
        _fail("column candidate exceeds authoritative front Y envelope")
        return
    if entablature_top >= y_max:
        _fail("entablature exceeds authoritative front Y envelope")
        return
    if rear_pilaster_top >= column_top:
        _fail("rear pilasters should remain subordinate to front colonnade")
        return
    if clock_top >= column_top:
        _fail("clock proxy exceeds source-bounded colonnade height")
        return
    if oval_top >= column_top:
        _fail("oval-light proxy exceeds source-bounded colonnade height")
        return

    var shaft_count := 0
    var base_count := 0
    var capital_count := 0
    var stair_nodes := 0
    var pilaster_nodes := 0
    var entry_nodes := 0
    var oval_nodes := 0
    var entablature_nodes := 0
    var clock_nodes := 0
    for child: Node in articulation.get_children():
        if child.name.contains("_Shaft"):
            shaft_count += 1
        elif child.name.contains("_Base"):
            base_count += 1
        elif child.name.contains("_Capital"):
            capital_count += 1
        elif child.name.begins_with("MonumentalStair_"):
            stair_nodes += 1
        elif child.name.begins_with("RearPilaster_"):
            pilaster_nodes += 1
        elif child.name == "RearCentralEntry" or child.name.begins_with("RearSideEntry_"):
            entry_nodes += 1
        elif child.name.begins_with("RearOvalLight_"):
            oval_nodes += 1
        elif child.name == "PorticoEntablature":
            entablature_nodes += 1
        elif child.name == "RearFacadeClock":
            clock_nodes += 1
    if shaft_count != 6 or base_count != 6 or capital_count != 6 or stair_nodes != 16:
        _fail("front portico generated node counts drifted")
        return
    if pilaster_nodes != 4 or entry_nodes != 3 or oval_nodes != 2 or entablature_nodes != 1 or clock_nodes != 1:
        _fail("rear facade generated node counts drifted")
        return

    print(
        "BOURSE_PORTICO_ARTICULATION_OK: columns=6 steps=16 pilasters=4 openings=3 ovals=2 entablature=1 clock=1 span=%.3f stair_width=%.3f column_top=%.3f runtime_approved=false" %
        [span, stair_width, column_top]
    )
    articulation.queue_free()
    quit(0)

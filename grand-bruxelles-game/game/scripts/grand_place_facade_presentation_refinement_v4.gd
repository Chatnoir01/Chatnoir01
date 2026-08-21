extends Node3D

const V5_NAME := "GrandPlaceFacadePresentationIntegratedV5"

var built := false
var failed := false

func _ready() -> void:
    call_deferred("_wait_for_v5")

func _wait_for_v5() -> void:
    for _frame: int in range(1200):
        var v5 := get_tree().root.get_node_or_null(V5_NAME)
        if v5 != null and bool(v5.get("built")) and not bool(v5.get("failed")):
            built = true
            set_meta("human_review_status","rejected")
            set_meta("superseded_by","V5")
            set_meta("visual_geometry_count",0)
            set_meta("source_geometry_changed",false)
            set_meta("source_collision_changed",false)
            set_meta("finished_perfect",false)
            print("GRAND_PLACE_FACADE_REFINEMENT_V4_SUPERSEDED: visual_geometry=0 v5_ready=true")
            return
        await get_tree().process_frame
    failed = true
    push_error("Grand-Place V4 supersession marker: V5 did not become ready")

func collision_object_count() -> int:
    return 0

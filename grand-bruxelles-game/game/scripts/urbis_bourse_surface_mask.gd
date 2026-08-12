extends Node

@export_file("*.json") var data_path: String = "res://data/urbis/bourse_street_surfaces.game.json"

const EXPECTED_IDS := [
    "https://databrussels.be/id/streetsurface/151495",
    "https://databrussels.be/id/streetsurface/152281",
    "https://databrussels.be/id/streetsurface/22358",
]

var _hidden_axis: int = 0


func _ready() -> void:
    call_deferred("_apply_mask")


func _validate_scope() -> bool:
    if not FileAccess.file_exists(data_path):
        push_error("Bourse surface mask data missing: %s" % data_path)
        return false
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Invalid Bourse surface mask data: %s" % data_path)
        return false
    var data := parsed as Dictionary
    if str(data.get("schema", "")) != "grand-bruxelles-urbis-bourse-surfaces-v1":
        push_error("Unsupported Bourse surface mask schema")
        return false
    var actual_ids: Array = data.get("target_inspire_ids", []) as Array
    actual_ids.sort()
    return actual_ids == EXPECTED_IDS


func _apply_mask() -> void:
    if not _validate_scope():
        return
    var axis := get_node_or_null("../UrbISBourseAxisContext")
    if axis != null:
        for child: Node in axis.get_children():
            if child is Node3D:
                (child as Node3D).visible = false
                _hidden_axis += 1
    print(
        "Bourse surface mask: %d superseded diagnostic axis strips hidden" % _hidden_axis
    )


func diagnostic_axis_hidden_count() -> int:
    return _hidden_axis

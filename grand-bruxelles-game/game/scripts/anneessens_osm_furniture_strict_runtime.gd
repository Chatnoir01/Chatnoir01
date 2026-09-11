extends "res://game/scripts/anneessens_osm_furniture_runtime.gd"

# Production boundary hardening for source/provenance identities. The pinned
# derived artifact already carries exact bytes; this guard keeps the runtime
# validator fail-closed if it is ever fed decoded data through another path.

func _collect_validated_tree_points(data: Dictionary) -> Variant:
    var environment_points: Variant = data.get("environment_points", null)
    if not environment_points is Array:
        push_error("Anneessens OSM furniture environment_points invalid")
        return null
    for raw: Variant in environment_points as Array:
        if not raw is Dictionary:
            push_error("Anneessens OSM furniture point invalid")
            return null
        var point := raw as Dictionary
        if str(point.get("kind", "")) != "tree":
            continue
        if typeof(point.get("osm_id", null)) != TYPE_INT:
            push_error("Anneessens OSM tree osm_id must be an integer source identity")
            return null
    return super._collect_validated_tree_points(data)

func _validate_selection_integrity(data: Dictionary, tree_points: Array) -> Variant:
    var selection_value: Variant = data.get("selection", null)
    if not selection_value is Dictionary:
        push_error("Anneessens OSM furniture selection contract missing")
        return null
    var selected_value: Variant = (selection_value as Dictionary).get("osm_ids", null)
    if not selected_value is Array:
        push_error("Anneessens OSM furniture selection osm_ids invalid")
        return null
    for raw_id: Variant in selected_value as Array:
        if typeof(raw_id) != TYPE_INT:
            push_error("Anneessens OSM furniture selection osm_id must be an integer source identity")
            return null
    return super._validate_selection_integrity(data, tree_points)

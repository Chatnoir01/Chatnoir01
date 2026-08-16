extends Node

const MIDI_RUNTIME_PATH := "res://data/urbis/midi/midi_runtime.game.json"
const MIDI_STATION_BUILDING_ID := "https://databrussels.be/id/building/1633645"
const TEMPORARY_HEIGHT_SOURCE := "temporary_area_heuristic"


static func source_station_footprint() -> PackedVector2Array:
    var footprint := PackedVector2Array()
    if not FileAccess.file_exists(MIDI_RUNTIME_PATH):
        push_error("Midi source runtime missing: %s" % MIDI_RUNTIME_PATH)
        return footprint

    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MIDI_RUNTIME_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Invalid Midi source runtime")
        return footprint

    var data: Dictionary = parsed
    var accuracy := data.get("accuracy", {}) as Dictionary
    if str(accuracy.get("plan_geometry", "")) != "official_urbis":
        push_error("Midi station plan requires official UrbIS geometry")
        return footprint
    if not str(accuracy.get("building_heights", "")).begins_with(TEMPORARY_HEIGHT_SOURCE):
        push_error("Unexpected Midi runtime height provenance")
        return footprint

    for raw_feature: Variant in data.get("buildings", []):
        if typeof(raw_feature) != TYPE_DICTIONARY:
            continue
        var feature: Dictionary = raw_feature
        if str(feature.get("id", "")) != MIDI_STATION_BUILDING_ID:
            continue
        if str(feature.get("height_source", "")) != TEMPORARY_HEIGHT_SOURCE:
            push_error("Unexpected Midi station height provenance")
            return PackedVector2Array()
        for raw_point: Variant in feature.get("footprint", []):
            if typeof(raw_point) != TYPE_ARRAY or raw_point.size() < 2:
                continue
            footprint.append(Vector2(float(raw_point[0]), float(raw_point[1])))
        if footprint.size() >= 2 and footprint[0].is_equal_approx(footprint[footprint.size() - 1]):
            footprint.remove_at(footprint.size() - 1)
        return footprint

    push_error("Official Midi station footprint missing: %s" % MIDI_STATION_BUILDING_ID)
    return footprint

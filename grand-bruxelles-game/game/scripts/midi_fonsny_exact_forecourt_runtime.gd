extends Node

## Presentation-only cleanup for the Avenue Fonsny arrival ground.
## The authored 18 x 174 m forecourt slab is disabled so the already-rendered
## official UrbIS street-level surfaces remain visible. No source polygon,
## placement, level or collision is changed by this runtime.

const LEGACY_NAME := "FonsnyStationForecourt"
const REQUIRED_EXACT := ["ExactRoadCarriageways", "ExactSidewalks"]
const OPTIONAL_EXACT := ["ExactTrafficIslands", "ExactPavedAreas", "ExactOtherStreetSurfaces"]

var _legacy: Node3D
var _original_visible := true
var _ready_complete := false
var _failed := false
var _exact_enabled := true
var _exact_nodes: Array[Node3D] = []

func _ready() -> void:
    call_deferred("_apply_when_ready")

func _apply_when_ready() -> void:
    for _attempt: int in range(180):
        await get_tree().process_frame
        var legacy := get_tree().root.find_child(LEGACY_NAME, true, false) as Node3D
        if legacy == null:
            continue
        var found: Array[Node3D] = []
        var required_ok := true
        for exact_name: String in REQUIRED_EXACT:
            var exact := get_tree().root.find_child(exact_name, true, false) as Node3D
            if exact == null:
                required_ok = false
                break
            found.append(exact)
        if not required_ok:
            continue
        for exact_name: String in OPTIONAL_EXACT:
            var exact := get_tree().root.find_child(exact_name, true, false) as Node3D
            if exact != null:
                found.append(exact)
        if found.size() < 3:
            continue
        _legacy = legacy
        _exact_nodes = found
        _original_visible = _legacy.visible
        _legacy.set_meta("presentation_superseded_by", "official_urbis_street_level_surfaces")
        _legacy.set_meta("source_geometry_mutated", false)
        _legacy.set_meta("collision_added_by_exact_forecourt_runtime", false)
        set_exact_enabled(true)
        _ready_complete = true
        print("MIDI_FONSNY_EXACT_FORECOURT_READY: exact_surfaces=%d legacy_visible=false source_geometry_changed=false collisions_added=0" % _exact_nodes.size())
        return
    _failed = true
    _ready_complete = true
    push_error("Midi Fonsny exact forecourt: legacy slab or exact UrbIS public-realm surfaces missing")

func set_exact_enabled(enabled: bool) -> void:
    _exact_enabled = enabled
    if is_instance_valid(_legacy):
        _legacy.visible = not enabled if _original_visible else false

func exact_enabled() -> bool:
    return _exact_enabled

func ready_complete() -> bool:
    return _ready_complete

func failed() -> bool:
    return _failed

func exact_surface_count() -> int:
    return _exact_nodes.size() if _ready_complete and not _failed else 0

func legacy_forecourt() -> Node3D:
    return _legacy

func legacy_hidden() -> bool:
    return is_instance_valid(_legacy) and not _legacy.visible

func collision_count_added() -> int:
    return 0

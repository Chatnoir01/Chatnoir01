extends Node

## Remove legacy photo-guided stand-ins once authoritative layers are available.
##
## Official City tree positions now provide vegetation and the official 2024
## orthophoto already carries real surface markings. Keeping the older generated
## approach trees/dashes on top would double-count features and reduce spatial
## fidelity. Provisional lamps remain until a sourced lighting inventory exists.

var cleanup_ready: bool = false
var hidden_legacy_approach: bool = false
var removed_corridor_trees: int = 0
var removed_corridor_dashes: int = 0
var kept_corridor_lamps: int = 0


func _ready() -> void:
    call_deferred("_cleanup")


func _cleanup() -> void:
    # The legacy generators are deferred too. Give them a small bounded window to
    # finish before removing only the superseded visual children.
    for _frame in range(12):
        await get_tree().process_frame

    var zone := get_parent()
    var realism := zone.get_node_or_null("RealismPass")
    if realism != null:
        var legacy := realism.get_node_or_null("AtomiumApproachPhotoGuided") as Node3D
        if legacy != null:
            legacy.visible = false
            hidden_legacy_approach = true

    var corridor := zone.get_node_or_null("AtomiumCorridor")
    if corridor != null:
        for child in corridor.get_children():
            var node_name := str(child.name)
            if node_name == "PhotoGuidedTree":
                removed_corridor_trees += 1
                child.queue_free()
            elif node_name == "LaneDash":
                removed_corridor_dashes += 1
                child.queue_free()
            elif node_name == "PhotoGuidedLamp":
                kept_corridor_lamps += 1

    await get_tree().process_frame
    cleanup_ready = hidden_legacy_approach and (removed_corridor_trees > 0 or removed_corridor_dashes > 0)
    print("LAEKEN_SOURCE_TRUTH_CLEANUP_READY: legacy_hidden=%s removed_trees=%d removed_dashes=%d kept_lamps=%d" % [
        hidden_legacy_approach,
        removed_corridor_trees,
        removed_corridor_dashes,
        kept_corridor_lamps,
    ])

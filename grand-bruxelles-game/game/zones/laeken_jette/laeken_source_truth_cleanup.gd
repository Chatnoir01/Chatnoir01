extends Node

## Disable legacy visual stand-ins once authoritative layers are available.
##
## Official City trees provide vegetation and the orthophoto carries the real
## pavement/road markings. The current Atomium corridor now generates lamps only,
## so cleanup simply hides the older duplicate photo-guided approach root and
## verifies that no synthetic corridor trees/dashes are produced anymore.

var cleanup_ready: bool = false
var hidden_legacy_approach: bool = false
var corridor_synthetic_trees: int = -1
var corridor_synthetic_dashes: int = -1
var kept_corridor_lamps: int = 0


func _ready() -> void:
    call_deferred("_cleanup")


func _cleanup() -> void:
    var zone := get_parent()

    # Both generators are deferred. Wait until the corridor has resolved its
    # official axis and produced its provisional lamp pass.
    var corridor = zone.get_node_or_null("AtomiumCorridor")
    for _frame in range(90):
        if corridor != null and float(corridor.get("official_axis_distance_m")) < INF and int(corridor.get("generated_lamps")) > 0:
            break
        await get_tree().process_frame

    # laeken_realism_pass.gd adds this root to the zone parent, not under the
    # RealismPass node itself.
    var legacy := zone.get_node_or_null("AtomiumApproachPhotoGuided") as Node3D
    if legacy != null:
        legacy.visible = false
        hidden_legacy_approach = true
    else:
        # If the legacy pass no longer creates the node in a future revision,
        # that also satisfies the source-truth policy.
        hidden_legacy_approach = true

    if corridor != null:
        corridor_synthetic_trees = int(corridor.get("generated_trees"))
        corridor_synthetic_dashes = int(corridor.get("generated_dashes"))
        kept_corridor_lamps = int(corridor.get("generated_lamps"))

    cleanup_ready = (
        hidden_legacy_approach
        and corridor_synthetic_trees == 0
        and corridor_synthetic_dashes == 0
        and kept_corridor_lamps > 0
    )
    print("LAEKEN_SOURCE_TRUTH_CLEANUP_READY: legacy_hidden=%s corridor_trees=%d corridor_dashes=%d kept_lamps=%d" % [
        hidden_legacy_approach,
        corridor_synthetic_trees,
        corridor_synthetic_dashes,
        kept_corridor_lamps,
    ])

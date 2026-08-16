extends Node

## Race-safe synchronizer between OfficialTrees and TreeCanopyRefinement.
## Both source passes are deferred; this small bridge waits until the authoritative
## primary crown MultiMesh and the replacement-lobe MultiMesh both exist before
## hiding the old sphere layer. No source positions or tree counts are changed.

const MAX_WAIT_FRAMES := 120

var synchronized: bool = false
var waited_frames: int = 0


func _ready() -> void:
    call_deferred("_synchronize")


func _synchronize() -> void:
    var zone := get_parent()
    for frame_index in range(MAX_WAIT_FRAMES):
        waited_frames = frame_index + 1
        var official = zone.get_node_or_null("OfficialTrees")
        var refinement = zone.get_node_or_null("TreeCanopyRefinement")
        var primary := zone.get_node_or_null("OfficialTrees/OfficialBroadleafCrowns") as MultiMeshInstance3D
        var replacement := zone.get_node_or_null("TreeCanopyRefinement/BroadleafReplacementLobes") as MultiMeshInstance3D
        if (
            official != null
            and bool(official.get("trees_loaded"))
            and refinement != null
            and primary != null
            and primary.multimesh != null
            and replacement != null
            and replacement.multimesh != null
        ):
            primary.visible = false
            refinement.set("primary_broadleaf_replaced", true)
            refinement.set("refinement_ready", true)
            synchronized = true
            print("LAEKEN_TREE_CANOPY_SYNC_READY: waited_frames=%d primary_instances=%d replacement_instances=%d" % [
                waited_frames,
                primary.multimesh.instance_count,
                replacement.multimesh.instance_count,
            ])
            return
        await get_tree().process_frame
    push_warning("LaekenTreeCanopySync: source/replacement crowns unavailable after %d frames" % MAX_WAIT_FRAMES)

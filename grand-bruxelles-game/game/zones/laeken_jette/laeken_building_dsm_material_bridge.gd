extends Node

## Bridge the already-validated building ShaderMaterial onto the DSM-height mesh.
## BuildingVisualPass remains the single source of facade/roof appearance; this
## node only redirects that material from the hidden uniform-height mesh to the
## replacement official-footprint + DSM-height mesh.

const MAX_WAIT_FRAMES := 60

var material_bridged: bool = false
var waited_frames: int = 0


func _ready() -> void:
    call_deferred("_bridge")


func _bridge() -> void:
    # HeightPass parses 9,518 height records and BuildingVisualPass may also load
    # the 2024 orthophoto. Their deferred work does not have a guaranteed order,
    # especially in headless CI/Web. Retry for a bounded number of frames instead
    # of assuming one frame is sufficient and permanently giving up.
    var zone := get_parent()
    for frame_index in range(MAX_WAIT_FRAMES):
        waited_frames = frame_index + 1
        var source := zone.get_node_or_null("OfficialBuildings") as MeshInstance3D
        var target := zone.get_node_or_null("OfficialBuildingsDSM") as MeshInstance3D
        if source != null and target != null and source.material_override != null:
            target.material_override = source.material_override
            material_bridged = true
            print("LAEKEN_BUILDING_DSM_MATERIAL_READY: waited_frames=%d" % waited_frames)
            return
        await get_tree().process_frame
    push_warning("LaekenBuildingDSMMaterialBridge: DSM mesh/material unavailable after %d frames" % MAX_WAIT_FRAMES)

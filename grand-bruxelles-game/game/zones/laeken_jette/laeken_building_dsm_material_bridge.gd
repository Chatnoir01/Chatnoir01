extends Node

## Bridge the already-validated building ShaderMaterial onto the DSM-height mesh.
## BuildingVisualPass remains the single source of facade/roof appearance; this
## node only redirects that material from the hidden uniform-height mesh to the
## replacement official-footprint + DSM-height mesh.

var material_bridged: bool = false


func _ready() -> void:
    call_deferred("_bridge")


func _bridge() -> void:
    # HeightPass and BuildingVisualPass are both deferred from _ready(). One
    # extra process frame guarantees both replacement mesh and material exist.
    await get_tree().process_frame
    var zone := get_parent()
    var source := zone.get_node_or_null("OfficialBuildings") as MeshInstance3D
    var target := zone.get_node_or_null("OfficialBuildingsDSM") as MeshInstance3D
    if source == null or target == null:
        push_warning("LaekenBuildingDSMMaterialBridge: source or DSM target missing")
        return
    if source.material_override == null:
        push_warning("LaekenBuildingDSMMaterialBridge: validated source material missing")
        return
    target.material_override = source.material_override
    material_bridged = true
    print("LAEKEN_BUILDING_DSM_MATERIAL_READY")

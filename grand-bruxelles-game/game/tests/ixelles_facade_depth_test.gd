extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const EXPECTED_FAMILY := "ixelles_authored_facade_depth_v1"
const EXPECTED_BUILDINGS := 260
const MIN_DIRECT_RECESS_PANELS := 320
const MIN_STREAMED_CONTEXT_CELLS := 2
const MIN_TOTAL_RECESS_PANELS := 600
const STASSART_124_BUILDING_ID := "https://databrussels.be/id/building/1737877"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("IXELLES_FACADE_DEPTH_FAIL: %s" % message)
    quit(1)

func _expect(condition: bool, message: String) -> bool:
    if not condition:
        _fail(message)
        return false
    return true

func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    await process_frame

    var player := main.get_node_or_null("Player") as CharacterBody3D
    if not _expect(player != null, "player missing"):
        return
    player.call("_apply_direct_spawn_from_user_args", PackedStringArray(["spawn=ixelles"]))
    for _frame: int in range(45):
        await process_frame

    var slice := main.get_node_or_null("IxellesDirectMicroSlice")
    if not _expect(slice != null and bool(slice.get("runtime_loaded")), "Ixelles source runtime did not load"):
        return
    if not _expect(int(slice.get("building_count")) == EXPECTED_BUILDINGS, "source-backed building count drifted"):
        return
    if not _expect(slice.has_method("facade_depth_contract"), "Ixelles facade depth contract missing"):
        return

    var raw_contract: Variant = slice.call("facade_depth_contract")
    if not _expect(raw_contract is Dictionary, "Ixelles facade depth contract invalid"):
        return
    var contract := raw_contract as Dictionary
    if not _expect(str(contract.get("family", "")) == EXPECTED_FAMILY, "Ixelles facade depth family drifted"):
        return
    if not _expect(bool(contract.get("enabled", false)), "Ixelles facade depth is not enabled"):
        return
    if not _expect(bool(contract.get("presentation_only", false)) and bool(contract.get("renderer_only", false)), "Ixelles facade depth is not renderer-only presentation"):
        return
    if not _expect(not bool(contract.get("source_geometry_changed", true)) and not bool(contract.get("collision_changed", true)), "Ixelles facade depth changed source geometry or collision"):
        return
    if not _expect(not bool(contract.get("surveyed_openings_claimed", true)), "authored recess rhythm is presented as surveyed openings"):
        return
    if not _expect(not bool(contract.get("exact_depth_claimed", true)), "authored relief depth is presented as surveyed depth"):
        return
    if not _expect(not bool(contract.get("floor_count_claimed", true)) and not bool(contract.get("building_material_claimed", true)), "authored facade detail claims unsupported architecture/material"):
        return
    if not _expect(int(contract.get("source_backed_buildings", 0)) == EXPECTED_BUILDINGS, "facade depth contract lost source-backed building coverage"):
        return
    if not _expect(int(contract.get("direct_recess_panels", 0)) >= MIN_DIRECT_RECESS_PANELS, "too few direct source-wall recess panels"):
        return
    if not _expect(int(contract.get("streamed_context_cells", 0)) >= MIN_STREAMED_CONTEXT_CELLS, "visible streamed Ixelles context did not receive facade depth"):
        return
    if not _expect(int(contract.get("total_recess_panels", 0)) >= MIN_TOTAL_RECESS_PANELS, "facade depth is too sparse to affect the player view"):
        return
    if not _expect(not bool(contract.get("new_building_footprints_added", true)), "facade depth added a building footprint"):
        return

    var depth_root := slice.get_node_or_null("IxellesAuthoredFacadeDepth")
    if not _expect(depth_root != null, "direct facade depth root missing"):
        return
    if not _expect(bool(depth_root.get_meta("presentation_only", false)) and bool(depth_root.get_meta("renderer_only", false)), "direct depth root provenance missing"):
        return
    if not _expect(str(depth_root.get_meta("family", "")) == EXPECTED_FAMILY, "direct depth root family missing"):
        return
    if not _expect(depth_root.get_node_or_null("RecessPanels") is MultiMeshInstance3D, "batched recess panels missing"):
        return
    if not _expect(depth_root.get_node_or_null("Headers") is MultiMeshInstance3D, "batched headers missing"):
        return
    if not _expect(depth_root.get_node_or_null("Jambs") is MultiMeshInstance3D, "batched jambs missing"):
        return

    var stassart := slice.get_node_or_null("Stassart124BlueStoneGroundFloor")
    if not _expect(stassart != null, "Stassart 124 identity cue disappeared"):
        return
    if not _expect(str(stassart.get_meta("source_building_id", "")) == STASSART_124_BUILDING_ID, "Stassart 124 source identity drifted"):
        return

    print("IXELLES_FACADE_DEPTH_OK: zone=ixelles status=LABO buildings=%d direct_panels>=%d total_panels>=%d context_cells>=%d family=%s presentation_only=true renderer_only=true source_geometry_changed=false collision_changed=false surveyed_openings_claimed=false exact_depth_claimed=false" % [EXPECTED_BUILDINGS, MIN_DIRECT_RECESS_PANELS, MIN_TOTAL_RECESS_PANELS, MIN_STREAMED_CONTEXT_CELLS, EXPECTED_FAMILY])
    quit(0)

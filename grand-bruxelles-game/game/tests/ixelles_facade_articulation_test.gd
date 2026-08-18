extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const EXPECTED_FAMILY := "ixelles_source_facade_articulation_v1"
const EXPECTED_BUILDINGS := 260
const EXPECTED_PALETTE_PROFILES := 3
const STASSART_124_BUILDING_ID := "https://databrussels.be/id/building/1737877"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("IXELLES_FACADE_ARTICULATION_FAIL: %s" % message)
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
    for _frame: int in range(30):
        await process_frame

    var slice := main.get_node_or_null("IxellesDirectMicroSlice")
    if not _expect(slice != null and bool(slice.get("runtime_loaded")), "Ixelles source runtime did not load"):
        return
    if not _expect(int(slice.get("building_count")) == EXPECTED_BUILDINGS, "source-backed building count drifted"):
        return
    if not _expect(slice.has_method("facade_presentation_contract"), "Ixelles facade presentation contract missing"):
        return

    var contract: Variant = slice.call("facade_presentation_contract")
    if not _expect(contract is Dictionary, "Ixelles facade presentation contract invalid"):
        return
    var facade := contract as Dictionary
    if not _expect(str(facade.get("material_family", "")) == EXPECTED_FAMILY, "Ixelles facade material family missing"):
        return
    if not _expect(bool(facade.get("presentation_only", false)), "Ixelles facade pass is not presentation-only"):
        return
    if not _expect(not bool(facade.get("geometry_changed", true)) and not bool(facade.get("collision_changed", true)), "Ixelles facade pass changed source geometry/collision"):
        return
    if not _expect(not bool(facade.get("building_material_claimed", true)), "Ixelles facade pass incorrectly claims real building materials"):
        return
    if not _expect(not bool(facade.get("window_geometry_claimed", true)) and not bool(facade.get("floor_count_claimed", true)), "Ixelles authored facade rhythm is being presented as surveyed architecture"):
        return
    if not _expect(int(facade.get("source_backed_buildings", 0)) == EXPECTED_BUILDINGS, "facade contract lost source-backed building coverage"):
        return
    if not _expect(int(facade.get("palette_profiles", 0)) == EXPECTED_PALETTE_PROFILES, "facade palette profile count drifted"):
        return

    var buildings_root := slice.get_node_or_null("StrongSourceBackedIxellesBuildings")
    if not _expect(buildings_root != null, "source-backed Ixelles building root missing"):
        return
    var material_nodes := 0
    for child: Node in buildings_root.get_children():
        if not child is MeshInstance3D:
            continue
        var instance := child as MeshInstance3D
        if instance.mesh == null or instance.mesh.get_surface_count() <= 0:
            continue
        var material := instance.mesh.surface_get_material(0)
        if not _expect(material is ShaderMaterial, "Ixelles strong-height building still uses flat legacy material"):
            return
        if not _expect(str(material.get_meta("material_family", "")) == EXPECTED_FAMILY, "Ixelles building material provenance missing"):
            return
        if not _expect(bool(material.get_meta("presentation_only", false)) and not bool(material.get_meta("geometry_changed", true)), "Ixelles material contract is not renderer-only"):
            return
        material_nodes += 1
    if not _expect(material_nodes == EXPECTED_PALETTE_PROFILES, "expected one rendered mesh per deterministic facade palette profile"):
        return

    var stassart := slice.get_node_or_null("Stassart124BlueStoneGroundFloor")
    if not _expect(stassart != null, "Stassart 124 identity cue disappeared"):
        return
    if not _expect(str(stassart.get_meta("source_building_id", "")) == STASSART_124_BUILDING_ID, "Stassart 124 source identity drifted"):
        return

    print("IXELLES_FACADE_ARTICULATION_OK: zone=ixelles status=LABO buildings=%d palette_profiles=%d family=%s presentation_only=true geometry_changed=false collision_changed=false building_material_claimed=false window_geometry_claimed=false stassart124_preserved=true" % [EXPECTED_BUILDINGS, EXPECTED_PALETTE_PROFILES, EXPECTED_FAMILY])
    quit(0)

extends SceneTree

const TERRAIN_SCRIPT := preload("res://game/zones/laeken_jette/atomium_dtm_terrain.gd")
const HERO_SCRIPT := preload("res://game/zones/laeken_jette/atomium_hero_core.gd")
const EVIDENCE_PATH := "res://data/sources/laeken_jette/atomium_hero_core_evidence.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ATOMIUM_SPHERE_SKIN_SEMANTICS_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    if not FileAccess.file_exists(EVIDENCE_PATH):
        _fail("hero evidence missing")
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EVIDENCE_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("hero evidence invalid")
        return
    var evidence := parsed as Dictionary
    var status := evidence.get("status", {}) as Dictionary
    var rendering := evidence.get("rendering_contract", {}) as Dictionary
    var semantics := rendering.get("sphere_panel_semantics", {}) as Dictionary
    var integration := evidence.get("integration_contract", {}) as Dictionary
    if not bool(status.get("sphere_skin_material_resolved", false)):
        _fail("stainless skin source contract missing")
        return
    if not bool(status.get("sphere_panel_topology_semantics_resolved", false)):
        _fail("panel semantics source contract missing")
        return
    if bool(status.get("sphere_panel_exact_runtime_layout_resolved", true)):
        _fail("exact seam layout must remain unresolved")
        return
    if int(semantics.get("large_spherical_triangles_per_sphere", 0)) != 48 or int(semantics.get("small_triangles_per_large_panel", 0)) != 15:
        _fail("official panel semantics drifted")
        return
    if bool(semantics.get("exact_runtime_seam_layout_allowed", true)):
        _fail("exact runtime seam layout was incorrectly allowed")
        return
    if not bool(integration.get("no_invented_panel_seams_without_layout_source", false)):
        _fail("no-invented-seams integration gate missing")
        return

    var terrain := TERRAIN_SCRIPT.new()
    terrain.build_collision = false
    root.add_child(terrain)
    await process_frame
    await process_frame
    if not bool(terrain.get("terrain_loaded")):
        _fail("terrain did not load")
        return

    var hero := HERO_SCRIPT.new()
    root.add_child(hero)
    if not bool(hero.call("build_on_terrain", terrain)):
        _fail("hero did not build")
        return

    var detailed_spheres := 0
    for child: Node in hero.get_children():
        if not child is MeshInstance3D or not child.name.begins_with("Sphere_"):
            continue
        var instance := child as MeshInstance3D
        if not instance.mesh is SphereMesh:
            _fail("sphere presentation mesh changed type")
            return
        var sphere := instance.mesh as SphereMesh
        if not sphere.material is StandardMaterial3D:
            _fail("sphere stainless material changed type")
            return
        var material := sphere.material as StandardMaterial3D
        if material.albedo_texture == null:
            _fail("panel-semantics surface cue texture missing")
            return
        if not bool(material.get_meta("atomium_panel_semantics_only", false)):
            _fail("surface cue is not marked semantics-only")
            return
        if bool(material.get_meta("atomium_exact_seam_layout", true)):
            _fail("surface cue falsely claims exact seam layout")
            return
        if str(material.get_meta("atomium_skin_source", "")) != "official-restoration-and-construction":
            _fail("surface cue source tag missing")
            return
        detailed_spheres += 1

    if detailed_spheres != 9:
        _fail("expected 9 detailed spheres, got %d" % detailed_spheres)
        return
    if int(hero.get("sphere_count")) != 9 or int(hero.get("tube_count")) != 20:
        _fail("hero topology drifted")
        return
    if int(hero.get("unresolved_support_pillars")) != 3:
        _fail("support-pillar blocker drifted")
        return

    print("ATOMIUM_SPHERE_SKIN_SEMANTICS_OK: spheres=%d exact_layout=false support_pillars_unresolved=%d" % [detailed_spheres, int(hero.get("unresolved_support_pillars"))])
    quit(0)

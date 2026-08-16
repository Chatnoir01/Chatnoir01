from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "game" / "scripts" / "midi_ambient_npc_visual_runtime.gd"


def test_midi_profiled_npcs_share_equivalent_materials() -> None:
    source = SCRIPT.read_text(encoding="utf-8")

    assert "var _shared_materials: Dictionary = {}" in source
    assert "func _deduplicate_proxy_materials(" in source
    assert "func _material_key(" in source
    assert "material.albedo_color.to_rgba32()" in source
    assert "mesh.surface_set_material(surface_index, shared)" in source
    assert "_deduplicate_proxy_materials(visual)" in source
    assert '"material_sharing": "exact-equivalent StandardMaterial3D reuse"' in source

    # The bridge must preserve its visual-only ownership contract: sharing
    # materials cannot enable simulation/collision or change movement owner.
    assert '"simulation_proxy_disabled": true' in source
    assert '"movement_owner": "midi_urban_life.gd legacy ambient path remains authoritative"' in source

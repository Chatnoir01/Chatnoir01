from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "game" / "scripts" / "humanoid_visual.gd"


def test_profiled_npcs_use_shared_material_cache() -> None:
    source = SCRIPT.read_text(encoding="utf-8")

    assert "static var _shared_npc_material_cache" in source
    assert "func _shared_npc_material(" in source
    assert "color.to_rgba32()" in source
    assert "_shared_npc_material_cache[key]" in source

    profiled_start = source.index("func _build_profiled_npc(")
    profiled_end = source.index("func _build_profiled_hair(")
    profiled = source[profiled_start:profiled_end]

    # The six per-NPC base materials must be cache-backed so dense crowds do
    # not allocate duplicate StandardMaterial3D resources for identical looks.
    assert profiled.count("_shared_npc_material(") >= 6
    assert "var skin := _material(" not in profiled
    assert "var hair := _material(" not in profiled
    assert "var upper := _material(" not in profiled
    assert "var lower := _material(" not in profiled
    assert "var accent := _material(" not in profiled
    assert "var shoes := _material(" not in profiled

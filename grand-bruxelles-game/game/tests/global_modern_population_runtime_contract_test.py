from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "project.godot"
RUNTIME = ROOT / "game" / "scripts" / "global_modern_population_runtime.gd"


def test_global_modern_population_runtime_contract() -> None:
    project = PROJECT.read_text(encoding="utf-8")
    runtime = RUNTIME.read_text(encoding="utf-8")

    assert 'GlobalModernPopulationRuntime="*res://game/scripts/global_modern_population_runtime.gd"' in project

    # New production vehicle visual is the only replacement visual installed by
    # this migration bridge. Legacy nodes may remain as hidden compatibility
    # children until all dependent tests/assets are retired separately.
    assert 'preload("res://game/scripts/rgsdev_vehicle_visual.gd")' in runtime
    assert 'legacy.name != "RgsdevVisual"' in runtime
    assert 'modern_vehicle_visual", "rgsdev"' in runtime

    # Ambient pedestrians in every loaded zone are upgraded through the shared
    # profiled NPC visual path, not only the historical Midi node.
    assert 'spatial.is_in_group("ambient_pedestrian")' in runtime
    assert 'preload("res://game/scripts/humanoid_visual.gd")' in runtime
    assert 'modern_population_visual", "profiled_npc"' in runtime

    # Density increases are bounded and still owned by the canonical managers.
    assert "const MIN_TRAFFIC_VEHICLES := 18" in runtime
    assert "const MIN_PARKED_VEHICLES := 12" in runtime
    assert "const MIN_CIVILIAN_BUDGET := 64" in runtime
    assert 'manager.call_deferred("_apply_density_now")' not in runtime
    assert 'child.call_deferred("_apply_density_now")' in runtime


if __name__ == "__main__":
    test_global_modern_population_runtime_contract()
    print("GLOBAL_MODERN_POPULATION_RUNTIME_CONTRACT_GREEN")

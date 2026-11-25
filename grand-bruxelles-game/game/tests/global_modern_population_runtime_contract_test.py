from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "project.godot"
RUNTIME = ROOT / "game" / "scripts" / "global_modern_population_runtime.gd"


def test_global_modern_population_runtime_contract() -> None:
    project = PROJECT.read_text(encoding="utf-8")
    runtime = RUNTIME.read_text(encoding="utf-8")

    assert 'GlobalModernPopulationRuntime="*res://game/scripts/global_modern_population_runtime.gd"' in project

    # Canonical RGSDEV is the replacement visual; legacy local traffic builders
    # are switched off before their _ready() can instantiate duplicate cars.
    assert 'preload("res://game/scripts/rgsdev_vehicle_visual.gd")' in runtime
    assert 'node.set("moving_vehicle_count", 0)' in runtime
    assert 'node.set("parked_vehicle_count", 0)' in runtime
    assert 'legacy_local_vehicle_generator_suppressed' in runtime
    assert 'modern_vehicle_visual", "rgsdev"' in runtime

    # Ambient pedestrians in every loaded zone are upgraded through the shared
    # profiled NPC visual path, not only the historical Midi node.
    assert 'spatial.is_in_group("ambient_pedestrian")' in runtime
    assert 'preload("res://game/scripts/humanoid_visual.gd")' in runtime
    assert 'modern_population_visual", "profiled_npc"' in runtime

    # Density increases are bounded and still owned by the canonical managers.
    assert "const MIN_TRAFFIC_VEHICLES := 18" in runtime
    assert "const MIN_PARKED_VEHICLES := 12" in runtime
    assert "const MIN_DELIVERY_VEHICLES := 3" in runtime
    assert "const MIN_CIVILIAN_BUDGET := 64" in runtime
    assert "const MIN_POLICE_BUDGET := 12" in runtime
    assert 'child.call_deferred("_apply_density_now")' in runtime
    assert 'child.call_deferred("_replenish_traffic")' in runtime


if __name__ == "__main__":
    test_global_modern_population_runtime_contract()
    print("GLOBAL_MODERN_POPULATION_RUNTIME_CONTRACT_GREEN")

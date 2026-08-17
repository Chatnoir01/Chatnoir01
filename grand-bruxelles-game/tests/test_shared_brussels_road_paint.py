from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "game/scripts/brussels_shared_road_paint_runtime.gd"
PROJECT = ROOT / "project.godot"


def main() -> None:
    assert RUNTIME.exists(), "RED: shared Brussels road-paint runtime missing"
    runtime = RUNTIME.read_text(encoding="utf-8")
    project = PROJECT.read_text(encoding="utf-8")
    for needle in [
        'const MATERIAL_FAMILY := "brussels_road_paint_presentation_v1"',
        'const SOURCE_GEOMETRY_CHANGED := false',
        'const SOURCE_PHOTOMETRY_CLAIMED := false',
        'const TARGET_WIDTH_M := 0.12',
        'const TARGET_THICKNESS_M := 0.025',
        'procedural_original_asset',
        'geometry_changed_by_road_paint_runtime',
        'GeneratedRoads',
    ]:
        assert needle in runtime, f"missing road-paint contract: {needle}"
    assert 'BrusselsSharedRoadPaintRuntime="*res://game/scripts/brussels_shared_road_paint_runtime.gd"' in project
    print("SHARED_BRUSSELS_ROAD_PAINT_CONTRACT_OK")


if __name__ == "__main__":
    main()

from pathlib import Path

RUNTIME = Path(__file__).resolve().parents[1] / "scripts" / "brussels_osm_environment_runtime.gd"


def test_refresh_threshold_uses_squared_distance_without_sqrt():
    source = RUNTIME.read_text(encoding="utf-8")
    start = source.index("func _refresh(force: bool) -> void:")
    end = source.index("\nfunc _nearby", start)
    refresh = source[start:end]

    assert "horizontal_delta.length_squared() < refresh_distance_m * refresh_distance_m" in refresh
    assert "horizontal_delta.length() < refresh_distance_m" not in refresh

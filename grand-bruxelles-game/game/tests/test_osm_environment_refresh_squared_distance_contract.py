from pathlib import Path

RUNTIME = Path(__file__).resolve().parents[1] / "scripts" / "brussels_osm_environment_runtime.gd"


def verify_refresh_threshold_uses_squared_distance_without_sqrt() -> None:
    source = RUNTIME.read_text(encoding="utf-8")
    start = source.index("func _refresh(force: bool) -> void:")
    end = source.index("\nfunc _nearby", start)
    refresh = source[start:end]

    assert "var horizontal_distance_sq := horizontal_delta.length_squared()" in refresh
    assert "if horizontal_distance_sq == 0.0:" in refresh
    assert "if horizontal_distance_sq < refresh_distance_m * refresh_distance_m:" in refresh
    assert refresh.count("horizontal_delta.length_squared()") == 1
    assert "horizontal_delta.length() < refresh_distance_m" not in refresh


if __name__ == "__main__":
    verify_refresh_threshold_uses_squared_distance_without_sqrt()
    print("OSM_REFRESH_SQUARED_DISTANCE_OK")

from pathlib import Path

RUNTIME = Path(__file__).resolve().parents[1] / "scripts" / "brussels_osm_environment_runtime.gd"


def verify_refresh_threshold_uses_scalar_squared_distance_without_temp_vector() -> None:
    source = RUNTIME.read_text(encoding="utf-8")
    start = source.index("func _refresh(force: bool) -> void:")
    end = source.index("\nfunc _nearby", start)
    refresh = source[start:end]

    assert "var horizontal_dx := anchor.x - _last_anchor.x" in refresh
    assert "var horizontal_dz := anchor.z - _last_anchor.z" in refresh
    assert "var horizontal_distance_sq := horizontal_dx * horizontal_dx + horizontal_dz * horizontal_dz" in refresh
    assert "if horizontal_distance_sq == 0.0:" in refresh
    assert "if horizontal_distance_sq < refresh_distance_m * refresh_distance_m:" in refresh
    assert "Vector2(" not in refresh
    assert ".length_squared()" not in refresh
    assert ".length()" not in refresh


if __name__ == "__main__":
    verify_refresh_threshold_uses_scalar_squared_distance_without_temp_vector()
    print("OSM_REFRESH_SCALAR_SQUARED_DISTANCE_OK")

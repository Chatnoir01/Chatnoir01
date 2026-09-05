from pathlib import Path

RUNTIME = Path(__file__).resolve().parents[1] / "scripts" / "brussels_osm_environment_runtime.gd"


def verify_nearby_selection_is_bounded_and_deterministic() -> None:
    source = RUNTIME.read_text(encoding="utf-8")

    assert "func _nearby_candidate_is_better(a: Dictionary, b: Dictionary) -> bool:" in source
    assert "func _nearby_heap_sift_up(rows: Array, index: int) -> void:" in source
    assert "func _nearby_heap_sift_down(rows: Array, index: int) -> void:" in source
    assert "func _push_nearby_candidate(rows: Array, candidate: Dictionary, limit: int) -> void:" in source

    start = source.index("func _nearby(kind: String, anchor: Vector3, limit: int) -> Array:")
    end = source.index("\nfunc _clear_owned_batches", start)
    nearby = source[start:end]

    assert "_push_nearby_candidate(rows, candidate, limit)" in nearby
    assert "if rows.size() > limit:" not in nearby
    assert "rows.resize(limit)" not in nearby
    assert "rows.sort_custom" in nearby
    assert 'float(a["distance_sq"]) == float(b["distance_sq"])' in nearby
    assert 'int(a["osm_id"]) < int(b["osm_id"])' in nearby

    push_start = source.index("func _push_nearby_candidate(rows: Array, candidate: Dictionary, limit: int) -> void:")
    push_end = source.index("\nfunc _nearby(kind: String", push_start)
    push = source[push_start:push_end]
    assert "if rows.size() < limit:" in push
    assert "rows.append(candidate)" in push
    assert "_nearby_heap_sift_up(rows, rows.size() - 1)" in push
    assert "if not _nearby_candidate_is_better(candidate, rows[0] as Dictionary):" in push
    assert "rows[0] = candidate" in push
    assert "_nearby_heap_sift_down(rows, 0)" in push


if __name__ == "__main__":
    verify_nearby_selection_is_bounded_and_deterministic()
    print("OSM_BOUNDED_NEARBY_SELECTION_OK")

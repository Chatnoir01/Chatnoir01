from pathlib import Path

RUNTIME = Path(__file__).resolve().parents[1] / "scripts" / "brussels_osm_environment_runtime.gd"


def verify_nearby_rejects_worse_candidates_before_dictionary_allocation() -> None:
    source = RUNTIME.read_text(encoding="utf-8")

    start = source.index("func _nearby(kind: String, anchor: Vector3, limit: int) -> Array:")
    end = source.index("\nfunc _clear_owned_batches", start)
    nearby = source[start:end]

    assert "rows.size() >= limit" in nearby
    assert "rows[0] as Dictionary" in nearby
    assert "distance_sq" in nearby
    assert "osm_id" in nearby

    candidate_allocation = 'var candidate := {"osm_id": item["osm_id"], "position": p, "distance_sq": distance_sq}'
    assert candidate_allocation in nearby

    reject_guard = "if rows.size() >= limit:"
    assert reject_guard in nearby
    assert nearby.index(reject_guard) < nearby.index(candidate_allocation), (
        "worse in-radius OSM points must be rejected against the bounded heap root "
        "before allocating a candidate Dictionary"
    )

    guard_start = nearby.index(reject_guard)
    allocation_start = nearby.index(candidate_allocation)
    guard = nearby[guard_start:allocation_start]
    assert "rows[0]" in guard
    assert "continue" in guard


if __name__ == "__main__":
    verify_nearby_rejects_worse_candidates_before_dictionary_allocation()
    print("OSM_NEARBY_ALLOCATION_PREFILTER_OK")

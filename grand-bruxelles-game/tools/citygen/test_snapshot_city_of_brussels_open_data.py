#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path

MODULE = Path(__file__).with_name("snapshot_city_of_brussels_open_data.py")
spec = importlib.util.spec_from_file_location("snapshot_city_open_data", MODULE)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

RETIRED = "pandemie-covid-19-nombre-de-cas-confirmes-par-date-age-et-genre-belgique"


def test_safe_id() -> None:
    assert mod.safe_id("abc-def_01") == "abc-def_01"
    assert mod.safe_id("a b/c") == "a_b_c"
    assert mod.safe_id("...") != ""


def test_shards_are_exact_partition() -> None:
    rows = [{"dataset_id": f"dataset-{i:03d}"} for i in range(209)]
    shards = [mod.shard_rows(rows, i, 8) for i in range(8)]
    flattened = [row["dataset_id"] for shard in shards for row in shard]
    assert len(flattened) == 209
    assert len(set(flattened)) == 209
    assert set(flattened) == {row["dataset_id"] for row in rows}
    sizes = [len(shard) for shard in shards]
    assert max(sizes) - min(sizes) <= 1


def test_sharding_is_order_independent() -> None:
    rows = [{"dataset_id": name} for name in ["c", "a", "d", "b"]]
    reverse = list(reversed(rows))
    for index in range(3):
        left = [r["dataset_id"] for r in mod.shard_rows(rows, index, 3)]
        right = [r["dataset_id"] for r in mod.shard_rows(reverse, index, 3)]
        assert left == right


def test_invalid_shard_rejected() -> None:
    rows = [{"dataset_id": "x"}]
    for index, count in [(-1, 8), (8, 8), (0, 0)]:
        try:
            mod.shard_rows(rows, index, count)
        except ValueError:
            pass
        else:
            raise AssertionError((index, count))


def test_non_federated_has_only_city_export() -> None:
    row = {"dataset_id": "local", "metas": {"default": {"federated": False}}}
    candidates = mod.export_candidates(row)
    assert candidates == [
        {
            "api_base": "https://opendata.brussels.be/api/explore/v2.1",
            "dataset_id": "local",
            "federated_fallback": False,
        }
    ]


def test_federated_fallback_is_exact_city_domain_identity() -> None:
    row = {"dataset_id": "remote", "metas": {"default": {"federated": True}}}
    candidates = mod.export_candidates(row)
    assert len(candidates) == 2
    assert candidates[0]["dataset_id"] == "remote"
    assert candidates[0]["federated_fallback"] is False
    assert candidates[1] == {
        "api_base": "https://data.opendatasoft.com/api/explore/v2.1",
        "dataset_id": "remote@bruxellesdata",
        "federated_fallback": True,
    }
    assert "/records" not in mod._export_url(candidates[1]["api_base"], candidates[1]["dataset_id"])
    assert "/exports/json" in mod._export_url(candidates[1]["api_base"], candidates[1]["dataset_id"])


def test_retired_hold_is_exact_and_has_no_substitute_alias() -> None:
    assert mod.KNOWN_RETIRED_FEDERATED_EXPORTS == {RETIRED}
    row = {"dataset_id": RETIRED, "metas": {"default": {"federated": True}}}
    candidates = mod.export_candidates(row)
    assert [item["dataset_id"] for item in candidates] == [RETIRED, RETIRED + "@bruxellesdata"]
    assert all("@public" not in item["dataset_id"] for item in candidates)


def main() -> int:
    test_safe_id()
    test_shards_are_exact_partition()
    test_sharding_is_order_independent()
    test_invalid_shard_rejected()
    test_non_federated_has_only_city_export()
    test_federated_fallback_is_exact_city_domain_identity()
    test_retired_hold_is_exact_and_has_no_substitute_alias()
    print("CITY_OPEN_DATA_SNAPSHOT_TESTS_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

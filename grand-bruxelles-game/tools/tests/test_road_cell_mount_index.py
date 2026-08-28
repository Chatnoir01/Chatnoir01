#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "build_road_cell_mount_index.py"
READINESS = ROOT / "data" / "provenance" / "brussels_road_destination_readiness_catalog.json"

spec = importlib.util.spec_from_file_location("mount_index", SCRIPT)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def expect_fail(fragment: str, fn) -> None:
    try:
        fn()
    except SystemExit as exc:
        assert fragment in str(exc), (fragment, str(exc))
    else:
        raise AssertionError(f"expected failure containing {fragment!r}")


def resign(readiness: dict) -> dict:
    value = copy.deepcopy(readiness)
    value.pop("semantic_sha256", None)
    value["semantic_sha256"] = module.sha256_json(value)
    return value


def main() -> int:
    readiness = json.loads(READINESS.read_text(encoding="utf-8"))
    index_a = module.build_index(readiness)
    module.validate_index(index_a)
    index_b = module.build_index(readiness)
    assert index_a == index_b

    assert index_a["destination_count"] == 96
    assert index_a["cell_count"] == 4
    assert index_a["authorized_mount_count"] == 0
    assert index_a["authorized_mounts"] == []
    assert index_a["runtime_directory_scan_authorized"] is False
    assert index_a["deterministic_manifest_lookup_required"] is True
    assert all(not row["mount_authorized"] for row in index_a["road_index"].values())
    assert all(not row["mount_authorized"] for row in index_a["cells"].values())

    tampered_semantic = copy.deepcopy(readiness)
    tampered_semantic["destinations"][0]["road_name"] = "tampered"
    expect_fail("readiness semantic drift", lambda: module.build_index(tampered_semantic))

    opened_catalog = copy.deepcopy(readiness)
    opened_catalog["authorization"]["runtime_directory_scan_authorized"] = True
    opened_catalog = resign(opened_catalog)
    expect_fail("readiness catalog opened runtime_directory_scan_authorized", lambda: module.build_index(opened_catalog))

    opened_destination = copy.deepcopy(readiness)
    opened_destination["destinations"][0]["runtime_mount_authorized"] = True
    opened_destination = resign(opened_destination)
    expect_fail("opened runtime_mount_authorized", lambda: module.build_index(opened_destination))

    fake_ready = copy.deepcopy(readiness)
    fake_ready["destinations"][0]["readiness"] = "JOUABLE"
    fake_ready = resign(fake_ready)
    expect_fail("readiness drift", lambda: module.build_index(fake_ready))

    duplicate = copy.deepcopy(readiness)
    duplicate["destinations"].append(copy.deepcopy(duplicate["destinations"][0]))
    duplicate["destination_count"] += 1
    duplicate = resign(duplicate)
    expect_fail("invalid/duplicate road", lambda: module.build_index(duplicate))

    inconsistent_cell = copy.deepcopy(readiness)
    target_cell = inconsistent_cell["destinations"][0]["cell_id"]
    target = next(row for row in inconsistent_cell["destinations"][1:] if row["cell_id"] == target_cell)
    target["cell_manifest_sha256"] = "0" * 64
    inconsistent_cell = resign(inconsistent_cell)
    expect_fail("inconsistent cell identity", lambda: module.build_index(inconsistent_cell))

    corrupted_index = copy.deepcopy(index_a)
    corrupted_index["authorized_mount_count"] = 1
    corrupted_index["authorized_mounts"] = [next(iter(corrupted_index["cells"]))]
    expect_fail("unauthorized mount materialized", lambda: module.validate_index(corrupted_index))

    print(
        "ROAD_CELL_MOUNT_INDEX_TEST_OK "
        f"destinations={index_a['destination_count']} cells={index_a['cell_count']} authorized_mounts=0"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "build_road_destination_catalog.py"
spec = importlib.util.spec_from_file_location("road_catalog_json_contract", SCRIPT)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def write_document(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps({
            "format": "grand-bruxelles-osm-v1",
            "roads": [{
                "osm_id": 42,
                "name": "Rue Test",
                "class": "tertiary",
                "width": 7.0,
                "drivable": True,
                "points": [[0.0, 0.0], [10.0, 0.0]],
            }],
            "buildings": [],
        }),
        encoding="utf-8",
    )


def resign(catalog: dict) -> None:
    catalog["catalog_sha256"] = module.catalog_semantic_sha256(catalog)


def expect_fail(catalog: dict, needle: str) -> None:
    resign(catalog)
    try:
        module.validate_contract(catalog)
    except SystemExit as exc:
        assert needle in str(exc), str(exc)
    else:
        raise AssertionError(f"expected fail-closed rejection containing {needle!r}")


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "data" / "osm"
        write_document(root / "a.game.json")
        base = module.build_catalog(root)
        module.validate_contract(base)

        count_string = json.loads(json.dumps(base))
        count_string["entry_count"] = str(count_string["entry_count"])
        expect_fail(count_string, "JSON type drift entry_count")

        road_record_underflow = json.loads(json.dumps(base))
        road_record_underflow["road_record_count"] = 0
        expect_fail(road_record_underflow, "road/drivable accounting drift")

        entry_id_string = json.loads(json.dumps(base))
        entry_id_string["entries"]["42"]["osm_id"] = "42"
        expect_fail(entry_id_string, "JSON type drift entry osm_id")

        point_count_float = json.loads(json.dumps(base))
        point_count_float["entries"]["42"]["point_count"] = 2.0
        expect_fail(point_count_float, "JSON type drift point_count")

        source_count_string = json.loads(json.dumps(base))
        source_count_string["entries"]["42"]["source_file_count"] = "1"
        expect_fail(source_count_string, "JSON type drift source_file_count")

        digest_number = json.loads(json.dumps(base))
        digest_number["entries"]["42"]["geometry_sha256"] = 0
        expect_fail(digest_number, "JSON type drift geometry_sha256")

        name_number = json.loads(json.dumps(base))
        name_number["entries"]["42"]["name"] = 42
        expect_fail(name_number, "JSON type drift entry name")

        class_number = json.loads(json.dumps(base))
        class_number["entries"]["42"]["class"] = 7
        expect_fail(class_number, "JSON type drift entry class")

        width_string = json.loads(json.dumps(base))
        width_string["entries"]["42"]["width"] = "7.0"
        expect_fail(width_string, "JSON type drift entry width")

        width_bool = json.loads(json.dumps(base))
        width_bool["entries"]["42"]["width"] = True
        expect_fail(width_bool, "JSON type drift entry width")

        width_nan = json.loads(json.dumps(base))
        width_nan["entries"]["42"]["width"] = float("nan")
        expect_fail(width_nan, "non-finite entry width")

        top_level_parallel_semantic = json.loads(json.dumps(base))
        top_level_parallel_semantic["safe_spawn_ready"] = True
        expect_fail(top_level_parallel_semantic, "catalog field set drift")

        entry_parallel_semantic = json.loads(json.dumps(base))
        entry_parallel_semantic["entries"]["42"]["rendered"] = True
        expect_fail(entry_parallel_semantic, "entry field set drift")

        authorization_parallel_semantic = json.loads(json.dumps(base))
        authorization_parallel_semantic["authorization"]["playable"] = True
        expect_fail(authorization_parallel_semantic, "authorization field set drift")

    print("ROAD_DESTINATION_CATALOG_JSON_CONTRACT_TEST_GREEN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

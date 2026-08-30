#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "build_road_destination_catalog.py"
spec = importlib.util.spec_from_file_location("road_catalog_json_contract", SCRIPT)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def write_document(
    path: Path,
    *,
    name: str = "Rue Test",
    road_class: str = "tertiary",
    width: float = 7.0,
    points: Any = None,
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps({
            "format": "grand-bruxelles-osm-v1",
            "roads": [{
                "osm_id": 42,
                "name": name,
                "class": road_class,
                "width": width,
                "drivable": True,
                "points": points if points is not None else [[0.0, 0.0], [10.0, 0.0]],
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


def expect_build_fail(root: Path, needle: str) -> None:
    try:
        module.build_catalog(root)
    except SystemExit as exc:
        assert needle in str(exc), str(exc)
    else:
        raise AssertionError(f"expected source build rejection containing {needle!r}")


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

        duplicate_without_source_multiplicity = json.loads(json.dumps(base))
        duplicate_without_source_multiplicity["duplicate_record_count"] = 1
        duplicate_without_source_multiplicity["eligible_record_count"] = 2
        duplicate_without_source_multiplicity["drivable_record_count"] = 2
        duplicate_without_source_multiplicity["road_record_count"] = 2
        expect_fail(duplicate_without_source_multiplicity, "duplicate/source multiplicity accounting drift")

        entry_id_string = json.loads(json.dumps(base))
        entry_id_string["entries"]["42"]["osm_id"] = "42"
        expect_fail(entry_id_string, "JSON type drift entry osm_id")

        leading_zero_key = json.loads(json.dumps(base))
        leading_zero_key["entries"]["00042"] = leading_zero_key["entries"].pop("42")
        expect_fail(leading_zero_key, "non-canonical OSM id key")

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

        width_zero = json.loads(json.dumps(base))
        width_zero["entries"]["42"]["width"] = 0.0
        expect_fail(width_zero, "non-positive entry width")

        width_negative = json.loads(json.dumps(base))
        width_negative["entries"]["42"]["width"] = -7.0
        expect_fail(width_negative, "non-positive entry width")

        top_level_parallel_semantic = json.loads(json.dumps(base))
        top_level_parallel_semantic["safe_spawn_ready"] = True
        expect_fail(top_level_parallel_semantic, "catalog field set drift")

        entry_parallel_semantic = json.loads(json.dumps(base))
        entry_parallel_semantic["entries"]["42"]["rendered"] = True
        expect_fail(entry_parallel_semantic, "entry field set drift")

        authorization_parallel_semantic = json.loads(json.dumps(base))
        authorization_parallel_semantic["authorization"]["playable"] = True
        expect_fail(authorization_parallel_semantic, "authorization field set drift")

        # Source identity fields must be exact; the factory must never silently trim
        # source values before hashing/indexing them into the derived catalog.
        write_document(root / "a.game.json", name=" Rue Test")
        expect_build_fail(root, "non-canonical source name")
        write_document(root / "a.game.json", road_class="tertiary ")
        expect_build_fail(root, "non-canonical source class")

        # Width is geometry-adjacent source truth. Zero/negative widths must not be
        # indexed as valid destination-road metadata and must not survive re-signing.
        write_document(root / "a.game.json", width=0.0)
        expect_build_fail(root, "non-positive source width")
        write_document(root / "a.game.json", width=-7.0)
        expect_build_fail(root, "non-positive source width")

        # A source point must be exactly the locked 2D [x,z] tuple. Extra dimensions
        # must never be silently dropped before geometry hashing/catalog materialization.
        write_document(root / "a.game.json", points=[[0.0, 0.0, 99.0], [10.0, 0.0]])
        expect_build_fail(root, "non-canonical source point dimension")

        # Malformed point records are source corruption, not ordinary ineligibility.
        # A drivable road with an object/scalar point must therefore fail closed.
        write_document(root / "a.game.json", points=[[0.0, 0.0], {"x": 10.0, "z": 0.0}])
        expect_build_fail(root, "malformed source point points[1]")

        # The points container itself is source truth. A drivable road must not turn
        # a malformed container or an underspecified one-point geometry into an
        # ordinary rejected/ineligible record.
        write_document(root / "a.game.json", points={"start": [0.0, 0.0], "end": [10.0, 0.0]})
        expect_build_fail(root, "malformed source points container")
        write_document(root / "a.game.json", points=[[0.0, 0.0]])
        expect_build_fail(root, "insufficient source points")

        # Geometry evidence must never be computed from a rounded representation of
        # the source JSON number. This integer cannot be represented exactly as float.
        write_document(root / "a.game.json", points=[[9007199254740993, 0.0], [10.0, 0.0]])
        expect_build_fail(root, "lossy source number points[0][0]")

    print("ROAD_DESTINATION_CATALOG_JSON_CONTRACT_TEST_GREEN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

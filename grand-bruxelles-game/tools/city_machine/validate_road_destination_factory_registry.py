#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

EXPECTED_SCHEMA = "grand-bruxelles-missing-road-source-registry-v1"
EXPECTED_SCOPE = "Brussels-Capital Region"
EXPECTED_REGISTERED = ["21001", "21004", "21013"]
EXPECTED_SOURCE = {
    "provider": "OpenStreetMap contributors via Overpass API",
    "license": "ODbL-1.0",
    "endpoint": "https://overpass-api.de/api/interpreter",
    "relation_reference": "OpenStreetMap WikiProject Belgium/Boundaries Brussels-Capital Region",
}
EXPECTED_GAME_FRAME = {
    "origin_lat": 50.8419,
    "origin_lon": 4.348,
    "axes": "X=east, Y=up, Z=south",
    "units": "metres",
}
EXPECTED_MUNICIPALITIES = [
    {"niscode": "21002", "id": "auderghem", "name": "Auderghem / Oudergem", "osm_relation_id": 58263},
    {"niscode": "21003", "id": "berchem_sainte_agathe", "name": "Berchem-Sainte-Agathe / Sint-Agatha-Berchem", "osm_relation_id": 60140},
    {"niscode": "21005", "id": "etterbeek", "name": "Etterbeek", "osm_relation_id": 58252},
    {"niscode": "21006", "id": "evere", "name": "Evere", "osm_relation_id": 60144},
    {"niscode": "21007", "id": "forest", "name": "Forest / Vorst", "osm_relation_id": 58249},
    {"niscode": "21008", "id": "ganshoren", "name": "Ganshoren", "osm_relation_id": 58257},
    {"niscode": "21009", "id": "ixelles", "name": "Ixelles / Elsene", "osm_relation_id": 58250},
    {"niscode": "21010", "id": "jette", "name": "Jette", "osm_relation_id": 58258},
    {"niscode": "21011", "id": "koekelberg", "name": "Koekelberg", "osm_relation_id": 58256},
    {"niscode": "21012", "id": "molenbeek_saint_jean", "name": "Molenbeek-Saint-Jean / Sint-Jans-Molenbeek", "osm_relation_id": 58255},
    {"niscode": "21014", "id": "saint_josse_ten_noode", "name": "Saint-Josse-ten-Noode / Sint-Joost-ten-Node", "osm_relation_id": 58262},
    {"niscode": "21015", "id": "schaerbeek", "name": "Schaerbeek / Schaarbeek", "osm_relation_id": 58260},
    {"niscode": "21016", "id": "uccle", "name": "Uccle / Ukkel", "osm_relation_id": 58253},
    {"niscode": "21017", "id": "watermael_boitsfort", "name": "Watermael-Boitsfort / Watermaal-Bosvoorde", "osm_relation_id": 58264},
    {"niscode": "21018", "id": "woluwe_saint_lambert", "name": "Woluwe-Saint-Lambert / Sint-Lambrechts-Woluwe", "osm_relation_id": 60167},
    {"niscode": "21019", "id": "woluwe_saint_pierre", "name": "Woluwe-Saint-Pierre / Sint-Pieters-Woluwe", "osm_relation_id": 60168},
]
BASELINE_KEYS = {"registered_niscodes", "missing_niscodes"}
REGISTRY_ROOT_KEYS = {
    "schema",
    "scope",
    "evidence_baseline",
    "source",
    "game_frame",
    "municipalities",
    "authorization",
}
DOWNSTREAM_AUTH_KEYS = {
    "source_registration_authorized",
    "road_cell_mapping_authorized",
    "render_authorized",
    "collision_authorized",
    "runtime_mount_authorized",
    "safe_spawn_authorized",
    "jouable_authorized",
}
REGISTRY_AUTH_KEYS = DOWNSTREAM_AUTH_KEYS | {"source_acquisition_authorized"}


def reject_duplicate_object_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON object key {key}")
        result[key] = value
    return result


def strict_json_loads(text: str) -> Any:
    return json.loads(text, object_pairs_hook=reject_duplicate_object_keys)


def read_registry(path: Path) -> dict[str, Any]:
    try:
        registry = strict_json_loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as exc:
        raise SystemExit(f"DESTINATION_FACTORY_REGISTRY_FAIL: invalid registry JSON: {exc}") from exc
    if not isinstance(registry, dict):
        raise SystemExit("DESTINATION_FACTORY_REGISTRY_FAIL: registry must be an object")
    return registry


def validate_registry_scope_baseline(registry: dict[str, Any]) -> None:
    if set(registry) != REGISTRY_ROOT_KEYS:
        raise SystemExit("DESTINATION_FACTORY_REGISTRY_FAIL: registry root schema drift")
    if registry.get("schema") != EXPECTED_SCHEMA:
        raise SystemExit("DESTINATION_FACTORY_REGISTRY_FAIL: registry schema drift")
    if registry.get("scope") != EXPECTED_SCOPE:
        raise SystemExit("DESTINATION_FACTORY_REGISTRY_FAIL: registry scope drift")

    source = registry.get("source")
    if not isinstance(source, dict) or source != EXPECTED_SOURCE:
        raise SystemExit("DESTINATION_FACTORY_REGISTRY_FAIL: registry source contract drift")

    game_frame = registry.get("game_frame")
    if not isinstance(game_frame, dict) or game_frame != EXPECTED_GAME_FRAME:
        raise SystemExit("DESTINATION_FACTORY_REGISTRY_FAIL: registry game frame drift")

    authorization = registry.get("authorization")
    if not isinstance(authorization, dict) or set(authorization) != REGISTRY_AUTH_KEYS:
        raise SystemExit("DESTINATION_FACTORY_REGISTRY_FAIL: registry authorization schema drift")
    if authorization.get("source_acquisition_authorized") is not True:
        raise SystemExit("DESTINATION_FACTORY_REGISTRY_FAIL: registry source acquisition authorization closed")
    if any(authorization.get(key) is not False for key in DOWNSTREAM_AUTH_KEYS):
        raise SystemExit("DESTINATION_FACTORY_REGISTRY_FAIL: registry downstream authorization opened")

    baseline = registry.get("evidence_baseline")
    if not isinstance(baseline, dict) or set(baseline) != BASELINE_KEYS:
        raise SystemExit("DESTINATION_FACTORY_REGISTRY_FAIL: evidence baseline schema drift")
    registered = baseline.get("registered_niscodes")
    missing = baseline.get("missing_niscodes")
    if not isinstance(registered, list) or not isinstance(missing, list):
        raise SystemExit("DESTINATION_FACTORY_REGISTRY_FAIL: evidence baseline schema drift")
    if any(not isinstance(nis, str) for nis in registered + missing):
        raise SystemExit("DESTINATION_FACTORY_REGISTRY_FAIL: evidence baseline schema drift")
    registered_set = set(registered)
    missing_set = set(missing)
    if len(registered_set) != len(registered) or len(missing_set) != len(missing):
        raise SystemExit("DESTINATION_FACTORY_REGISTRY_FAIL: evidence baseline partition drift")
    if registered_set != set(EXPECTED_REGISTERED) or registered_set & missing_set:
        raise SystemExit("DESTINATION_FACTORY_REGISTRY_FAIL: evidence baseline partition drift")

    municipalities = registry.get("municipalities")
    if municipalities != EXPECTED_MUNICIPALITIES:
        raise SystemExit("DESTINATION_FACTORY_REGISTRY_FAIL: municipality identity drift")
    municipality_niscodes = [row["niscode"] for row in EXPECTED_MUNICIPALITIES]
    if missing_set != set(municipality_niscodes):
        raise SystemExit("DESTINATION_FACTORY_REGISTRY_FAIL: evidence baseline partition drift")
    if registered != EXPECTED_REGISTERED or missing != municipality_niscodes:
        raise SystemExit("DESTINATION_FACTORY_REGISTRY_FAIL: evidence baseline order drift")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--registry", type=Path, required=True)
    args = parser.parse_args()
    registry = read_registry(args.registry)
    validate_registry_scope_baseline(registry)
    print("DESTINATION_FACTORY_REGISTRY_GREEN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

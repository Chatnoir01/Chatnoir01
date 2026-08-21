#!/usr/bin/env python3
from __future__ import annotations

import audit_zone_readiness as readiness


def main() -> int:
    jette = readiness.audit("jette")
    assert jette["status"] == "READY", jette
    assert jette["blockers"] == []
    assert jette["evidence"]["profile_registered"] is True
    assert jette["evidence"]["arrival_contract"]["mode"] == "catalog_spawn"

    midi = readiness.audit("midi")
    assert midi["status"] == "BLOCKED"
    required_midi = {
        "city_machine_profile_missing",
        "source_crs_contract_missing_or_invalid",
        "source_license_contract_missing",
        "game_origin_contract_missing_or_invalid",
        "source_bounded_arrival_position_unresolved",
        "validator_contract_missing",
        "runtime_finish_contract_missing",
        "full_zone_osm_cache_missing",
        "full_zone_osm_runtime_missing",
    }
    assert required_midi <= set(midi["blockers"]), midi["blockers"]
    assert midi["evidence"]["legacy_crs_evidence"] == "EPSG:31370"
    assert midi["evidence"]["catalog_mode"] == "fast_travel"

    anneessens = readiness.audit("anneessens")
    bourse = readiness.audit("bourse")
    for result in (anneessens, bourse):
        assert result["status"] == "BLOCKED"
        assert "partial_osm_environment_not_eligible" in result["blockers"]
        assert "full_zone_osm_runtime_contract_invalid" in result["blockers"]

    missing = readiness.audit("not-a-zone")
    assert missing["status"] == "BLOCKED"
    assert missing["blockers"] == ["catalog_zone_missing"]

    assert readiness.audit("midi") == midi
    print("CITY_MACHINE_ZONE_READINESS_TEST_OK jette=READY midi=BLOCKED partial_views_rejected=true deterministic=true")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

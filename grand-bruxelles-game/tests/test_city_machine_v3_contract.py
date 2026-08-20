#!/usr/bin/env python3
from __future__ import annotations

import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MACHINE = ROOT / "tools/city_machine"


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> int:
    registry = load(MACHINE / "registry.json")
    finish = load(MACHINE / "finish_registry.json")
    inventory = load(MACHINE / "generator_inventory.json")
    materials = load(MACHINE / "finish_materials_catalog.json")
    sidecar = load(ROOT / "data/runtime/city_machine/jette/finish_materials.game.json")
    manifest = load(ROOT / "data/urbis/laeken_jette/jette_phase2/manifest.json")

    require(registry["version"] == 3, "registry must be v3")
    require(registry["pilot_zone"] == "jette", "Jette pilot must stay locked")
    profile = registry["zone_profiles"]["jette"]
    require(profile["zone_id"] == "jette", "generic zone profile must carry zone_id")
    require(profile["crs"] == "EPSG:31370", "Jette profile CRS mismatch")
    require(profile["runtime_scene"].endswith("jette_phase2.tscn"), "runtime scene missing")
    require(profile["streaming"]["status"] == "contract_only", "streaming must not be falsely wired")
    require(profile["streaming"]["runtime_mount_authorized"] is False, "streaming mount must remain unauthorized")

    slugs = profile["materialized_slugs"]
    require("tram_network" in slugs, "tram_network must be rebuilt, not inherited as stale output")
    tram_layers = [row for row in registry["layers"] if row.get("layer_id") == "materialize_tram_network_runtime"]
    require(len(tram_layers) == 1, "exactly one tram materialization layer required")
    require(tram_layers[0].get("slug") == "tram_network", "tram materialization slug mismatch")
    require("jette" in tram_layers[0].get("enabled_zones", []), "tram layer must be enabled for Jette")

    families = {row["family_id"]: row for row in finish["families"]}
    require(families["finish_materials"]["status"] == "wired", "finish_materials must be wired")
    require("G6_finish_materials" in families["finish_materials"]["gates"], "G6 must protect finish materials")
    require(families["life"]["status"] == "disabled", "life must remain honestly disabled")
    require("G6_finish_materials" in families["proof"]["gates"], "proof must rerun G6")
    require(finish["auto_jouable"] is False, "factory must never auto-promote JOUABLE")

    require(materials["policy"] == "AUTHORED_OVERRIDE_GT_GENERATED_BASE", "authored override policy missing")
    require(materials["geometry_mutation_allowed"] is False, "material pass must not mutate geometry")
    unsupported = materials["unsupported_without_source"]
    for key in ("sidewalk", "roof", "glass", "concrete", "brick_stone", "vegetation_surface"):
        require(key in unsupported, f"missing explicit unsupported material family: {key}")

    require(sidecar["format"] == "grand-bruxelles-city-machine-finish-materials-v1", "sidecar format mismatch")
    require(sidecar["policy"] == "AUTHORED_OVERRIDE_GT_GENERATED_BASE", "sidecar policy mismatch")
    require(sidecar["geometry_mutated"] is False, "sidecar claims geometry mutation")
    require(sidecar["authored_overrides_preserved"] is True, "authored overrides not preserved")
    require(sidecar["zone"] == "jette", "sidecar zone mismatch")

    by_slug = {
        row["source_slug"]: row
        for row in sidecar["assignments"]
        if row.get("source_slug") is not None
    }
    for slug in ("buildings", "street_surfaces", "tram_network", "train_network"):
        require(slug in by_slug, f"finish material assignment missing source layer: {slug}")
        expected = int(manifest["layers"][slug]["features"])
        require(by_slug[slug]["feature_count"] == expected, f"feature count mismatch: {slug}")
        require(by_slug[slug]["geometry_mutated"] is False, f"material assignment mutates geometry: {slug}")

    assigned_layers = {row["layer"] for row in sidecar["assignments"]}
    require("sidewalk" not in assigned_layers, "Jette sidewalk must not be invented")
    skipped = {row["family"]: row["status"] for row in sidecar["skips"]}
    require(skipped.get("sidewalk") == "missing_source", "Jette sidewalk gap must be explicit")
    require(sidecar["authored_overrides"], "at least one Jette authored override must be protected")

    require(inventory["legacy_registry_entries_before_lot"] == 40, "legacy inventory measurement changed")
    require(inventory["unique_generators_before_lot"] == 39, "legacy duplicate correction must stay explicit")
    require(inventory["duplicate_legacy_entries"] == ["tools/city_machine/build_osm_environment_zone.py"], "unexpected legacy duplicate")
    rows = inventory["generators"]
    require(len(rows) == inventory["unique_generators_after_lot"] == 41, "generator inventory total mismatch")
    ids = [row["id"] for row in rows]
    paths = [row["path"] for row in rows]
    require(len(ids) == len(set(ids)), "generator IDs must be unique")
    require(len(paths) == len(set(paths)), "generator paths must be unique")
    for path in paths:
        require((ROOT / path).is_file(), f"inventoried generator does not exist: {path}")
    statuses = Counter(row["status"] for row in rows)
    require(sum(statuses.values()) == 41, "status accounting must cover every unique generator exactly once")
    require(set(statuses) <= {"wired", "partial", "candidate_only", "disabled", "obsolete", "duplicate"}, "unknown inventory status")

    pipeline_text = (MACHINE / "finish_pipeline.py").read_text(encoding="utf-8")
    proof_text = (MACHINE / "finish_proof_stage.py").read_text(encoding="utf-8")
    require("MATERIALS_STAGE" in pipeline_text and "finish_materials_stage.py" in pipeline_text, "pipeline does not execute material stage")
    require("fm.gate(zone_id)" in proof_text, "proof does not execute real G6")

    print(
        "CITY_MACHINE_V3_CONTRACT_OK "
        f"generators={len(rows)} statuses={dict(sorted(statuses.items()))} "
        f"buildings={manifest['layers']['buildings']['features']} "
        f"streets={manifest['layers']['street_surfaces']['features']} "
        f"tram={manifest['layers']['tram_network']['features']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

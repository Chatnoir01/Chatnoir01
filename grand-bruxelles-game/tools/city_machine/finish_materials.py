#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

import city_machine as cm

HERE = Path(__file__).resolve().parent
CATALOG_PATH = HERE / "finish_materials_catalog.json"
FORMAT = "grand-bruxelles-city-machine-finish-materials-v1"
GATE = "G6_finish_materials"


class FinishMaterialsError(cm.MachineError):
    pass


def _catalog() -> dict[str, Any]:
    value = cm.read_json(CATALOG_PATH)
    if value.get("schema") != "grand-bruxelles-city-machine-finish-materials-catalog-v1":
        raise FinishMaterialsError("unsupported finish materials catalog")
    if value.get("policy") != "AUTHORED_OVERRIDE_GT_GENERATED_BASE":
        raise FinishMaterialsError("authored override policy must remain fail-closed")
    if value.get("geometry_mutation_allowed") is not False:
        raise FinishMaterialsError("finish materials must not mutate source geometry")
    return value


def _binding_path(binding: str) -> Path:
    parts = binding.split("::", 1)
    raw = parts[0].strip()
    symbol = parts[1].strip() if len(parts) == 2 else ""
    if not raw:
        raise FinishMaterialsError(f"empty runtime binding: {binding!r}")
    path = cm.p(raw)
    if not path.is_file():
        raise FinishMaterialsError(f"runtime binding missing: {raw}")
    if symbol:
        text = path.read_text(encoding="utf-8")
        if symbol not in text:
            raise FinishMaterialsError(f"runtime binding symbol missing: {raw}::{symbol}")
    return path


def _zone_context(zone_id: str) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
    registry = cm.load_registry()
    profile = (registry.get("zone_profiles") or {}).get(zone_id)
    if not isinstance(profile, dict):
        raise FinishMaterialsError(f"zone '{zone_id}' is not enabled in city_machine")
    config = profile.get("finish_materials")
    if not isinstance(config, dict):
        raise FinishMaterialsError(f"zone '{zone_id}' has no finish_materials profile")
    manifest = cm.source_contract(profile)
    return profile, config, manifest


def build_payload(zone_id: str) -> tuple[dict[str, Any], Path]:
    profile, config, manifest = _zone_context(zone_id)
    catalog = _catalog()
    families = catalog.get("families")
    if not isinstance(families, dict):
        raise FinishMaterialsError("finish materials families missing")

    assignments: list[dict[str, Any]] = []
    seen_layers: set[str] = set()
    rows = config.get("assignments")
    if not isinstance(rows, list) or not rows:
        raise FinishMaterialsError("finish_materials assignments must be a non-empty list")

    manifest_layers = manifest.get("layers") or {}
    source_root = cm.p(profile["source_root"])
    for row in rows:
        if not isinstance(row, dict):
            raise FinishMaterialsError("finish_materials assignment must be an object")
        layer = str(row.get("layer", "")).strip()
        family_id = str(row.get("family", "")).strip()
        source_slug = str(row.get("source_slug", "")).strip()
        if not layer or layer in seen_layers:
            raise FinishMaterialsError(f"invalid or duplicate material layer: {layer!r}")
        seen_layers.add(layer)
        family = families.get(family_id)
        if not isinstance(family, dict):
            raise FinishMaterialsError(f"unknown material family '{family_id}' for layer '{layer}'")
        binding = str(family.get("runtime_binding", "")).strip()
        _binding_path(binding)

        feature_count = 1
        source_path = None
        if source_slug:
            source_meta = manifest_layers.get(source_slug)
            if not isinstance(source_meta, dict):
                raise FinishMaterialsError(f"manifest layer missing: {source_slug}")
            source_path = source_root / f"{source_slug}.game.json"
            if not source_path.is_file():
                raise FinishMaterialsError(f"runtime source missing: {source_slug}.game.json")
            feature_count = cm.feature_count(source_path)
            declared = int(source_meta.get("features", -1))
            if feature_count != declared:
                raise FinishMaterialsError(
                    f"feature count mismatch for {source_slug}: runtime={feature_count} manifest={declared}"
                )

        assignments.append(
            {
                "layer": layer,
                "family": family_id,
                "feature_count": feature_count,
                "runtime_binding": binding,
                "source_slug": source_slug or None,
                "source_runtime": str(source_path.relative_to(cm.PROJECT)) if source_path else None,
                "source_claim": str(family.get("source_claim", "")),
                "geometry_mutated": False,
            }
        )

    unsupported = catalog.get("unsupported_without_source")
    if not isinstance(unsupported, dict):
        raise FinishMaterialsError("unsupported_without_source must be an object")
    skips = [
        {"family": str(key), "status": "missing_source", "reason": str(reason)}
        for key, reason in sorted(unsupported.items())
    ]

    authored = config.get("authored_overrides", [])
    if not isinstance(authored, list):
        raise FinishMaterialsError("authored_overrides must be a list")
    authored_rows: list[dict[str, str]] = []
    for raw in authored:
        if not isinstance(raw, dict):
            raise FinishMaterialsError("authored override must be an object")
        owner = str(raw.get("owner", "")).strip()
        selector = str(raw.get("selector", "")).strip()
        if not owner or not selector:
            raise FinishMaterialsError("authored override owner/selector missing")
        _binding_path(owner)
        authored_rows.append({"owner": owner, "selector": selector})

    payload: dict[str, Any] = {
        "format": FORMAT,
        "zone": zone_id,
        "source_crs": manifest.get("source_crs"),
        "source_license": manifest.get("source_license"),
        "policy": catalog["policy"],
        "geometry_mutated": False,
        "authored_overrides_preserved": True,
        "assignments": assignments,
        "skips": skips,
        "authored_overrides": authored_rows,
    }
    output = cm.p(str(config.get("output", "")))
    if output == cm.PROJECT:
        raise FinishMaterialsError("finish materials output path missing")
    return payload, output


def canonical_text(payload: dict[str, Any]) -> str:
    return json.dumps(payload, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def digest(payload: dict[str, Any]) -> str:
    return hashlib.sha256(
        json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    ).hexdigest()


def materialize(zone_id: str, dry_run: bool = False) -> dict[str, Any]:
    payload, output = build_payload(zone_id)
    text = canonical_text(payload)
    if not dry_run:
        output.parent.mkdir(parents=True, exist_ok=True)
        if not output.is_file() or output.read_text(encoding="utf-8") != text:
            output.write_text(text, encoding="utf-8")
    print(
        "CITY_MACHINE_FINISH_MATERIALS "
        f"zone={zone_id} assignments={len(payload['assignments'])} "
        f"skips={len(payload['skips'])} digest={digest(payload)} "
        f"mode={'dry-run' if dry_run else 'write'}"
    )
    return payload


def gate(zone_id: str) -> dict[str, str]:
    expected, output = build_payload(zone_id)
    if not output.is_file():
        raise cm.GateError(GATE, f"finish materials output missing: {output.relative_to(cm.PROJECT)}")
    actual = cm.read_json(output)
    if actual != expected:
        raise cm.GateError(GATE, "finish materials output differs from deterministic source/profile result")
    if actual.get("policy") != "AUTHORED_OVERRIDE_GT_GENERATED_BASE":
        raise cm.GateError(GATE, "authored override policy missing")
    if actual.get("geometry_mutated") is not False or actual.get("authored_overrides_preserved") is not True:
        raise cm.GateError(GATE, "geometry/authored override safety contract violated")
    detail = (
        f"assignments={len(actual.get('assignments', []))} "
        f"skips={len(actual.get('skips', []))} digest={digest(actual)[:16]}"
    )
    print(f"CITY_MACHINE_GATE PASS {GATE} detail={detail}")
    return {"gate": GATE, "status": "PASS", "detail": detail}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--zone", required=True)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--gate", action="store_true")
    args = parser.parse_args()
    try:
        if args.gate:
            gate(args.zone)
        else:
            materialize(args.zone, args.dry_run)
        return 0
    except cm.GateError as exc:
        print(f"CITY_MACHINE_GATE FAIL {exc.gate} detail={exc.detail}", file=sys.stderr)
        return 3
    except (OSError, json.JSONDecodeError, cm.MachineError) as exc:
        print(f"CITY_MACHINE_FINISH_MATERIALS_FAIL {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Fail-closed compatibility and reuse-terms gate for Data Factory processors."""
from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--contracts", type=Path, required=True)
    parser.add_argument("--queue", type=Path, required=True)
    args = parser.parse_args()

    contracts_doc = json.loads(args.contracts.read_text(encoding="utf-8"))
    queue_doc = json.loads(args.queue.read_text(encoding="utf-8"))

    if contracts_doc.get("runtime_authorized") is not False or contracts_doc.get("production_authorized") is not False:
        raise SystemExit("processing contract gate failed: contracts must not authorize runtime/production")
    if queue_doc.get("runtime_authorized") is not False or queue_doc.get("jouable_promotion_authorized") is not False:
        raise SystemExit("processing contract gate failed: queue must not authorize runtime/JOUABLE")

    contracts = {c["family"]: c for c in contracts_doc.get("contracts", [])}
    queue = {q["family"]: q for q in queue_doc.get("queue", [])}
    required_families = {
        "urbis_addresses",
        "stib_surface_network",
        "stib_static_schedule",
        "mobiris_traffic_counts",
        "planning_permit_change_signals",
        "statbel_building_period_context",
        "ibsa_building_age_context",
        "impervious_surface_context",
        "heat_island_context",
    }
    missing_families = sorted(required_families - contracts.keys())
    if missing_families:
        raise SystemExit("processing contract gate failed: missing contracts: " + ", ".join(missing_families))

    for family in sorted(required_families):
        contract = contracts[family]
        q = queue.get(family)
        if q is None:
            raise SystemExit(f"processing contract gate failed: {family} missing from queue")
        provided = set(contract.get("provided_artifacts", []))
        required = set(contract.get("processor_required_artifacts", []))
        calculated_missing = sorted(required - provided)
        declared_missing = sorted(contract.get("missing_artifacts", []))
        if calculated_missing != declared_missing:
            raise SystemExit(
                f"processing contract gate failed: {family} missing-artifact declaration drift: "
                f"calculated={calculated_missing} declared={declared_missing}"
            )
        compatible = not calculated_missing
        if bool(contract.get("compatible")) != compatible:
            raise SystemExit(f"processing contract gate failed: {family} compatibility flag is false truth")
        state = str(q.get("state", ""))
        if compatible:
            if "CONTRACT_MISMATCH" in state:
                raise SystemExit(f"processing contract gate failed: compatible {family} marked CONTRACT_MISMATCH")
            if not q.get("processor"):
                raise SystemExit(f"processing contract gate failed: compatible {family} has no processor")
        else:
            if "CONTRACT_MISMATCH" not in state:
                raise SystemExit(
                    f"processing contract gate failed: incompatible {family} must be visibly CONTRACT_MISMATCH"
                )
            if "READY" in state:
                raise SystemExit(f"processing contract gate failed: incompatible {family} may not be marked READY")

        reuse_resolved = contract.get("reuse_terms_resolved")
        if reuse_resolved is False and "TERMS_BLOCKED" not in state:
            raise SystemExit(f"processing contract gate failed: unresolved reuse terms for {family} must remain TERMS_BLOCKED")
        if reuse_resolved is True and "TERMS_BLOCKED" in state:
            raise SystemExit(f"processing contract gate failed: resolved reuse terms for {family} are incorrectly TERMS_BLOCKED")

    print("DATA_FACTORY_PROCESSING_CONTRACTS_OK: P0/P1 compatibility and reuse terms are fail-closed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

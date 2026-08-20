#!/usr/bin/env python3
"""Fail-closed compatibility gate between intake outputs and data-factory processors."""
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

    print("DATA_FACTORY_PROCESSING_CONTRACTS_OK: P0 compatibility truth is fail-closed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

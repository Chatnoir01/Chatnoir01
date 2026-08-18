#!/usr/bin/env python3
"""Fail-closed validator for LABO -> JOUABLE zone promotion evidence."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CONTRACT = REPO_ROOT / "grand-bruxelles-game/data/qa/zone_promotion_contract.json"


class PromotionValidationError(RuntimeError):
    pass


def _load_json(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise PromotionValidationError(f"missing JSON: {path}") from exc
    except json.JSONDecodeError as exc:
        raise PromotionValidationError(f"invalid JSON {path}: {exc}") from exc
    if not isinstance(data, dict):
        raise PromotionValidationError(f"expected JSON object: {path}")
    return data


def _safe_repo_file(repo_root: Path, raw_path: str) -> Path:
    if not isinstance(raw_path, str) or not raw_path.strip():
        raise PromotionValidationError("evidence path must be a non-empty string")
    rel = Path(raw_path)
    if rel.is_absolute() or ".." in rel.parts:
        raise PromotionValidationError(f"unsafe evidence path: {raw_path}")
    candidate = repo_root / rel
    if not candidate.is_file():
        raise PromotionValidationError(f"broken evidence path: {raw_path}")
    return candidate


def validate_repository(repo_root: Path, contract_path: Path | None = None) -> dict[str, Any]:
    repo_root = repo_root.resolve()
    contract_path = contract_path or (repo_root / "grand-bruxelles-game/data/qa/zone_promotion_contract.json")
    contract = _load_json(contract_path)
    if contract.get("schema") != "grand-bruxelles-zone-promotion-contract-v1":
        raise PromotionValidationError("unsupported promotion contract schema")

    policy = contract.get("policy")
    if not isinstance(policy, dict):
        raise PromotionValidationError("promotion policy missing")
    required_true = (
        "human_only_promotion",
        "jouable_requires_proof",
        "jouable_requires_human_pass",
        "labo_data_ready_is_not_jouable",
        "missing_or_broken_evidence_fails_closed",
    )
    for key in required_true:
        if policy.get(key) is not True:
            raise PromotionValidationError(f"policy must keep {key}=true")
    if policy.get("city_machine_may_promote") is not False:
        raise PromotionValidationError("City Machine must not be allowed to promote zones")
    if policy.get("labo_may_hold_approved_jouable_decision") is not False:
        raise PromotionValidationError("LABO must not carry approved JOUABLE decisions")

    catalog_rel = contract.get("catalog_path")
    proof_dir_rel = contract.get("proof_directory")
    if not isinstance(catalog_rel, str) or not isinstance(proof_dir_rel, str):
        raise PromotionValidationError("catalog/proof directory paths missing")
    catalog = _load_json(repo_root / catalog_rel)
    if catalog.get("schema") != "grand-bruxelles-playable-zone-catalog-v2":
        raise PromotionValidationError("unexpected playable zone catalog schema")

    zones = catalog.get("zones")
    if not isinstance(zones, list) or not zones:
        raise PromotionValidationError("catalog zones missing")
    allowed_qualities = set(contract.get("allowed_catalog_qualities", []))
    approved_decisions = set(contract.get("approved_jouable_decisions", []))
    required_stages = contract.get("required_stages")
    if not allowed_qualities or not approved_decisions or not isinstance(required_stages, list) or not required_stages:
        raise PromotionValidationError("contract quality/decision/stage lists incomplete")

    zone_by_id: dict[str, dict[str, Any]] = {}
    for zone in zones:
        if not isinstance(zone, dict):
            raise PromotionValidationError("catalog zone must be an object")
        zone_id = zone.get("id")
        quality = zone.get("quality")
        if not isinstance(zone_id, str) or not zone_id:
            raise PromotionValidationError("catalog zone id missing")
        if zone_id in zone_by_id:
            raise PromotionValidationError(f"duplicate zone id: {zone_id}")
        if quality not in allowed_qualities:
            raise PromotionValidationError(f"unsupported quality {quality!r} for {zone_id}")
        zone_by_id[zone_id] = zone

    proof_dir = repo_root / proof_dir_rel
    proof_files = sorted(proof_dir.glob("*.json")) if proof_dir.is_dir() else []
    proofs: dict[str, dict[str, Any]] = {}
    for proof_file in proof_files:
        proof = _load_json(proof_file)
        zone_id = proof.get("zone_id")
        if not isinstance(zone_id, str) or not zone_id:
            raise PromotionValidationError(f"proof missing zone_id: {proof_file}")
        if zone_id not in zone_by_id:
            raise PromotionValidationError(f"proof targets unknown zone: {zone_id}")
        if zone_id in proofs:
            raise PromotionValidationError(f"duplicate proof for zone: {zone_id}")
        proofs[zone_id] = proof

    jouable = []
    labo = []
    approved = []
    for zone_id, zone in zone_by_id.items():
        quality = zone["quality"]
        proof = proofs.get(zone_id)
        if quality == "JOUABLE":
            jouable.append(zone_id)
            if proof is None:
                raise PromotionValidationError(f"JOUABLE zone missing proof: {zone_id}")
            _validate_jouable_proof(repo_root, contract, zone_id, proof, approved_decisions, required_stages)
            approved.append(zone_id)
        else:
            labo.append(zone_id)
            if proof is not None and proof.get("decision") in approved_decisions:
                raise PromotionValidationError(f"LABO zone carries approved JOUABLE decision: {zone_id}")

    if not jouable:
        raise PromotionValidationError("catalog has no JOUABLE baseline")
    return {"jouable": jouable, "labo": labo, "approved": approved}


def _validate_jouable_proof(
    repo_root: Path,
    contract: dict[str, Any],
    zone_id: str,
    proof: dict[str, Any],
    approved_decisions: set[Any],
    required_stages: list[Any],
) -> None:
    if proof.get("schema") != contract.get("proof_schema"):
        raise PromotionValidationError(f"proof schema mismatch: {zone_id}")
    if proof.get("catalog_quality") != "JOUABLE":
        raise PromotionValidationError(f"proof quality must be JOUABLE: {zone_id}")
    if proof.get("decision") not in approved_decisions:
        raise PromotionValidationError(f"JOUABLE decision not approved: {zone_id}")
    if proof.get("realism_complete") is not False:
        raise PromotionValidationError(f"proof must not claim realism complete: {zone_id}")
    stages = proof.get("stages")
    if not isinstance(stages, dict):
        raise PromotionValidationError(f"proof stages missing: {zone_id}")
    for stage_name in required_stages:
        stage = stages.get(stage_name)
        if not isinstance(stage, dict):
            raise PromotionValidationError(f"missing required stage {stage_name}: {zone_id}")
        if stage.get("status") != "PASS":
            raise PromotionValidationError(f"stage {stage_name} is not PASS: {zone_id}")
        evidence = stage.get("evidence")
        if not isinstance(evidence, list) or not evidence:
            raise PromotionValidationError(f"stage {stage_name} has no evidence: {zone_id}")
        for evidence_path in evidence:
            _safe_repo_file(repo_root, evidence_path)
    human = stages.get("human_visual_verdict", {})
    if human.get("verdict") != "PASS" or not isinstance(human.get("scope"), str) or not human.get("scope").strip():
        raise PromotionValidationError(f"human visual PASS missing: {zone_id}")
    if human.get("realism_complete") is not False:
        raise PromotionValidationError(f"human verdict must not claim overall realism complete: {zone_id}")


def main() -> int:
    try:
        result = validate_repository(REPO_ROOT, DEFAULT_CONTRACT)
    except PromotionValidationError as exc:
        print(f"ZONE_PROMOTION_GATE_FAIL {exc}", file=sys.stderr)
        return 1
    print(
        "ZONE_PROMOTION_GATE_OK "
        f"jouable={len(result['jouable'])} labo={len(result['labo'])} "
        f"approved={','.join(result['approved'])}"
    )
    for zone_id in result["jouable"]:
        print(f"ZONE_STATUS {zone_id}=JOUABLE_PROOF_OK")
    for zone_id in result["labo"]:
        print(f"ZONE_STATUS {zone_id}=LABO_NOT_PROMOTED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

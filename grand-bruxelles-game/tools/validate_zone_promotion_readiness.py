#!/usr/bin/env python3
"""Fail-closed validator for LABO -> JOUABLE hard evidence.

Promotion is blocked only by the hard technical stages in the contract. Visual
review stages remain reportable post-integration and never substitute for hard
source/runtime/collision/export proof.
"""

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
        "jouable_requires_proof",
        "hard_failures_block_promotion",
        "labo_data_ready_is_not_jouable",
        "missing_or_broken_hard_evidence_fails_closed",
    )
    for key in required_true:
        if policy.get(key) is not True:
            raise PromotionValidationError(f"policy must keep {key}=true")
    required_false = (
        "human_only_promotion",
        "jouable_requires_human_pass",
        "visual_findings_block_promotion",
        "city_machine_may_promote",
        "labo_may_hold_approved_jouable_decision",
    )
    for key in required_false:
        if policy.get(key) is not False:
            raise PromotionValidationError(f"policy must keep {key}=false")
    if policy.get("visual_review_mode") != "post_integration":
        raise PromotionValidationError("visual review must remain post_integration")

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
    hard_required_stages = contract.get("hard_required_stages")
    visual_review_stages = contract.get("visual_review_stages")
    if not allowed_qualities or not approved_decisions:
        raise PromotionValidationError("contract quality/decision lists incomplete")
    if not isinstance(hard_required_stages, list) or not hard_required_stages:
        raise PromotionValidationError("hard required stages missing")
    if not isinstance(visual_review_stages, list):
        raise PromotionValidationError("visual review stages missing")
    if set(hard_required_stages) & set(visual_review_stages):
        raise PromotionValidationError("hard and visual stages must be disjoint")

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

    jouable: list[str] = []
    labo: list[str] = []
    approved: list[str] = []
    visual_findings: dict[str, list[str]] = {}
    for zone_id, zone in zone_by_id.items():
        quality = zone["quality"]
        proof = proofs.get(zone_id)
        if quality == "JOUABLE":
            jouable.append(zone_id)
            if proof is None:
                raise PromotionValidationError(f"JOUABLE zone missing proof: {zone_id}")
            findings = _validate_jouable_proof(
                repo_root,
                contract,
                zone_id,
                proof,
                approved_decisions,
                hard_required_stages,
                visual_review_stages,
            )
            approved.append(zone_id)
            if findings:
                visual_findings[zone_id] = findings
        else:
            labo.append(zone_id)
            if proof is not None and proof.get("decision") in approved_decisions:
                raise PromotionValidationError(f"LABO zone carries approved JOUABLE decision: {zone_id}")

    if not jouable:
        raise PromotionValidationError("catalog has no JOUABLE baseline")
    return {"jouable": jouable, "labo": labo, "approved": approved, "visual_findings": visual_findings}


def _validate_jouable_proof(
    repo_root: Path,
    contract: dict[str, Any],
    zone_id: str,
    proof: dict[str, Any],
    approved_decisions: set[Any],
    hard_required_stages: list[Any],
    visual_review_stages: list[Any],
) -> list[str]:
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

    for stage_name in hard_required_stages:
        stage = stages.get(stage_name)
        if not isinstance(stage, dict):
            raise PromotionValidationError(f"missing hard stage {stage_name}: {zone_id}")
        if stage.get("status") != "PASS":
            raise PromotionValidationError(f"hard stage {stage_name} is not PASS: {zone_id}")
        evidence = stage.get("evidence")
        if not isinstance(evidence, list) or not evidence:
            raise PromotionValidationError(f"hard stage {stage_name} has no evidence: {zone_id}")
        for evidence_path in evidence:
            _safe_repo_file(repo_root, evidence_path)

    # Visual stages are deliberately advisory. Missing/failed visual review is
    # surfaced as debt, never converted into a technical promotion failure.
    findings: list[str] = []
    for stage_name in visual_review_stages:
        stage = stages.get(stage_name)
        if not isinstance(stage, dict):
            findings.append(f"{stage_name}:NOT_REVIEWED")
            continue
        status = str(stage.get("status", "NOT_REVIEWED")).strip().upper() or "NOT_REVIEWED"
        if status != "PASS":
            findings.append(f"{stage_name}:{status}")
        if stage_name == "human_visual_verdict":
            verdict = str(stage.get("verdict", "NOT_REVIEWED")).strip().upper() or "NOT_REVIEWED"
            if verdict != "PASS" and f"{stage_name}:{verdict}" not in findings:
                findings.append(f"{stage_name}:{verdict}")
    return findings


def main() -> int:
    try:
        result = validate_repository(REPO_ROOT, DEFAULT_CONTRACT)
    except PromotionValidationError as exc:
        print(f"ZONE_PROMOTION_GATE_FAIL {exc}", file=sys.stderr)
        return 1
    finding_count = sum(len(items) for items in result["visual_findings"].values())
    print(
        "ZONE_PROMOTION_GATE_OK "
        f"jouable={len(result['jouable'])} labo={len(result['labo'])} "
        f"approved={','.join(result['approved'])} visual_findings={finding_count} review=POST_INTEGRATION"
    )
    for zone_id in result["jouable"]:
        print(f"ZONE_STATUS {zone_id}=JOUABLE_HARD_PROOF_OK")
    for zone_id in result["labo"]:
        print(f"ZONE_STATUS {zone_id}=LABO_NOT_PROMOTED")
    for zone_id, findings in sorted(result["visual_findings"].items()):
        print(f"ZONE_VISUAL_DEBT {zone_id}={','.join(findings)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

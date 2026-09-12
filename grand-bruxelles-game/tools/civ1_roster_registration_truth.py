#!/usr/bin/env python3
from __future__ import annotations

import argparse, hashlib, json
from pathlib import Path

SCHEMA = "grand-bruxelles-civ1-roster-registration-truth-v8"
REGISTRY_SCHEMA = "grand-bruxelles-civ1-roster-registry-v1"
REQUIRED = {"asset_path", "role", "sha256", "source_url", "license"}
ALLOWED_ROLES = {"civilian", "police"}
CHARACTER_PREFIX = "grand-bruxelles-game/assets/characters/"
PLAYER_ASSET = CHARACTER_PREFIX + "player_character.glb"


def validate_entry(entry: object, repo_root: Path, player_sha: str | None) -> dict[str, object]:
    reasons: list[str] = []
    if not isinstance(entry, dict):
        return {"valid": False, "blocking_reasons": ["entry_not_object"], "roster_eligible": False}
    missing = sorted(k for k in REQUIRED if not isinstance(entry.get(k), str) or not entry.get(k, "").strip())
    reasons.extend(f"missing_or_empty_{k}" for k in missing)
    asset_path = str(entry.get("asset_path", ""))
    role = str(entry.get("role", ""))
    if role not in ALLOWED_ROLES:
        reasons.append("role_not_explicit_civilian_or_police")
    if asset_path == PLAYER_ASSET:
        reasons.append("player_reuse_forbidden")
    if not asset_path.startswith(CHARACTER_PREFIX) or ".." in Path(asset_path).parts or "\\" in asset_path:
        reasons.append("asset_path_not_canonically_confined")
    path = (repo_root / asset_path).resolve()
    character_root = (repo_root / CHARACTER_PREFIX).resolve()
    try:
        path.relative_to(character_root)
    except ValueError:
        reasons.append("asset_path_not_canonically_confined")
    sha = str(entry.get("sha256", "")).lower()
    if len(sha) != 64 or any(c not in "0123456789abcdef" for c in sha):
        reasons.append("sha256_invalid")
    actual_sha = None
    if path.is_file() and "asset_path_not_canonically_confined" not in reasons:
        actual_sha = hashlib.sha256(path.read_bytes()).hexdigest()
        if sha != actual_sha:
            reasons.append("sha256_mismatch")
        if player_sha is not None and actual_sha == player_sha:
            reasons.append("player_content_reuse_forbidden")
    elif "asset_path_not_canonically_confined" not in reasons:
        reasons.append("asset_missing")
    source = str(entry.get("source_url", ""))
    if source and not source.startswith("https://"):
        reasons.append("source_url_https_required")
    license_value = str(entry.get("license", "")).strip()
    if license_value.lower() in {"unknown", "tbd", "todo", "n/a", "none"}:
        reasons.append("license_not_resolved")
    reasons = sorted(set(reasons))
    valid = not reasons
    return {"asset_path": asset_path or None, "role": role or None, "declared_sha256": sha or None, "actual_sha256": actual_sha, "source_url": source or None, "license": license_value or None, "valid": valid, "blocking_reasons": reasons, "roster_eligible": valid}


def build_payload(registry: object, repo_root: Path) -> dict[str, object]:
    top_reasons: list[str] = []
    registry_schema = registry.get("schema") if isinstance(registry, dict) else None
    if registry_schema != REGISTRY_SCHEMA:
        top_reasons.append("registry_schema_invalid")
    entries = registry.get("entries", []) if isinstance(registry, dict) else []
    if not isinstance(registry, dict):
        top_reasons.append("registry_not_object")
        entries = []
    elif not isinstance(entries, list):
        top_reasons.append("entries_not_array")
        entries = []
    player_path = repo_root / PLAYER_ASSET
    player_sha = hashlib.sha256(player_path.read_bytes()).hexdigest() if player_path.is_file() else None
    results = [validate_entry(entry, repo_root, player_sha) for entry in entries]
    if any(item.get("valid") is not True for item in results):
        top_reasons.append("invalid_entries_present")
    by_path: dict[str, list[int]] = {}
    by_content: dict[str, list[int]] = {}
    for i, item in enumerate(results):
        if item.get("asset_path"):
            by_path.setdefault(str(item["asset_path"]), []).append(i)
        if item.get("actual_sha256"):
            by_content.setdefault(str(item["actual_sha256"]), []).append(i)
    for reason, groups in (("duplicate_asset_path", by_path), ("duplicate_content_sha256", by_content)):
        for indices in groups.values():
            if len(indices) > 1:
                top_reasons.append(reason)
                for i in indices:
                    results[i]["valid"] = False
                    results[i]["roster_eligible"] = False
                    results[i]["blocking_reasons"] = sorted(set([*results[i]["blocking_reasons"], reason]))
    eligible = [x for x in results if x.get("roster_eligible") is True]
    return {"schema": SCHEMA, "registry_parse_valid": True, "registry_schema": registry_schema, "registry_schema_valid": registry_schema == REGISTRY_SCHEMA, "registration_count": len(results), "eligible_count": len(eligible), "invalid_entry_count": sum(x.get("valid") is not True for x in results), "civilian_count": sum(x.get("role") == "civilian" for x in eligible), "police_count": sum(x.get("role") == "police" for x in eligible), "blocking_reasons": sorted(set(top_reasons)), "invalid_entries_fail_closed": True, "roster_authorized": False, "runtime_authorized": False, "visual_approval_claimed": False, "entries": results}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("registry", type=Path)
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    try:
        registry = json.loads(args.registry.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        registry = {"schema": None, "entries": []}
        parse_error = True
    else:
        parse_error = False
    payload = build_payload(registry, args.repo_root)
    if parse_error:
        payload["registry_parse_valid"] = False
        payload["blocking_reasons"] = sorted(set([*payload["blocking_reasons"], "registry_unreadable_or_invalid_json"]))
    text = json.dumps(payload, indent=2, sort_keys=True) + "\n"
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text, encoding="utf-8")
    print(json.dumps(payload, sort_keys=True))
    return 2 if payload["blocking_reasons"] else 0

if __name__ == "__main__":
    raise SystemExit(main())

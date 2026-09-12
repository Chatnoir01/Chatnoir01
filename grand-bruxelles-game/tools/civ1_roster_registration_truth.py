#!/usr/bin/env python3
from __future__ import annotations

import argparse, hashlib, json
from pathlib import Path

SCHEMA = "grand-bruxelles-civ1-roster-registration-truth-v1"
PLAYER_ASSET = "grand-bruxelles-game/assets/characters/player_character.glb"
ALLOWED_ROLES = {"civilian", "police"}
REQUIRED = {"asset_path", "role", "sha256", "source_url", "license"}


def _norm(value: str) -> str:
    return Path(value).as_posix().lstrip("./")


def validate_entry(entry: object, repo_root: Path) -> dict[str, object]:
    reasons: list[str] = []
    if not isinstance(entry, dict):
        return {"valid": False, "blocking_reasons": ["entry_not_object"], "roster_eligible": False}
    missing = sorted(k for k in REQUIRED if not isinstance(entry.get(k), str) or not entry.get(k, "").strip())
    if missing:
        reasons += [f"missing_or_empty_{k}" for k in missing]
    asset_path = _norm(str(entry.get("asset_path", "")))
    role = str(entry.get("role", ""))
    if role not in ALLOWED_ROLES:
        reasons.append("role_not_explicit_civilian_or_police")
    if asset_path == PLAYER_ASSET:
        reasons.append("player_reuse_forbidden")
    if asset_path and not asset_path.startswith("grand-bruxelles-game/assets/characters/"):
        reasons.append("asset_path_outside_character_root")
    sha = str(entry.get("sha256", "")).lower()
    if len(sha) != 64 or any(c not in "0123456789abcdef" for c in sha):
        reasons.append("sha256_invalid")
    path = repo_root / asset_path if asset_path else None
    actual_sha = None
    if path is None or not path.is_file():
        reasons.append("asset_missing")
    else:
        actual_sha = hashlib.sha256(path.read_bytes()).hexdigest()
        if sha != actual_sha:
            reasons.append("sha256_mismatch")
    source = str(entry.get("source_url", ""))
    if source and not source.startswith(("https://", "http://")):
        reasons.append("source_url_not_http")
    license_value = str(entry.get("license", "")).strip()
    if license_value.lower() in {"unknown", "tbd", "todo", "n/a", "none"}:
        reasons.append("license_not_resolved")
    valid = not reasons
    return {
        "asset_path": asset_path,
        "role": role or None,
        "declared_sha256": sha or None,
        "actual_sha256": actual_sha,
        "source_url": source or None,
        "license": license_value or None,
        "valid": valid,
        "blocking_reasons": sorted(set(reasons)),
        "roster_eligible": valid,
    }


def build_payload(registry: object, repo_root: Path) -> dict[str, object]:
    entries = registry.get("entries", []) if isinstance(registry, dict) else []
    top_reasons: list[str] = []
    if not isinstance(registry, dict):
        top_reasons.append("registry_not_object")
        entries = []
    elif not isinstance(entries, list):
        top_reasons.append("entries_not_array")
        entries = []
    results = [validate_entry(x, repo_root) for x in entries]
    paths = [x.get("asset_path") for x in results if x.get("asset_path")]
    if len(paths) != len(set(paths)):
        top_reasons.append("duplicate_asset_path")
        for x in results:
            if paths.count(x.get("asset_path")) > 1:
                x["valid"] = False; x["roster_eligible"] = False
                x["blocking_reasons"] = sorted(set([*x.get("blocking_reasons", []), "duplicate_asset_path"]))
    eligible = [x for x in results if x.get("roster_eligible") is True]
    return {
        "schema": SCHEMA,
        "registration_count": len(results),
        "eligible_count": len(eligible),
        "civilian_count": sum(x.get("role") == "civilian" for x in eligible),
        "police_count": sum(x.get("role") == "police" for x in eligible),
        "blocking_reasons": sorted(set(top_reasons)),
        "explicit_registration_required": True,
        "source_license_hash_required": True,
        "filename_role_inference_forbidden": True,
        "player_reuse_as_roster_forbidden": True,
        "roster_authorized": False,
        "runtime_authorized": False,
        "visual_approval_claimed": False,
        "entries": results,
    }


def main() -> int:
    p=argparse.ArgumentParser()
    p.add_argument("registry", type=Path)
    p.add_argument("--repo-root", type=Path, default=Path("."))
    p.add_argument("--out", type=Path)
    a=p.parse_args()
    try: registry=json.loads(a.registry.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError): registry={"entries": []}; parse_error=True
    else: parse_error=False
    payload=build_payload(registry, a.repo_root)
    if parse_error: payload["blocking_reasons"]=[*payload["blocking_reasons"], "registry_unreadable_or_invalid_json"]
    text=json.dumps(payload, indent=2, sort_keys=True)+"\n"
    if a.out: a.out.parent.mkdir(parents=True, exist_ok=True); a.out.write_text(text, encoding="utf-8")
    print(json.dumps(payload, sort_keys=True))
    return 0

if __name__ == "__main__": raise SystemExit(main())

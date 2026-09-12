#!/usr/bin/env python3
from __future__ import annotations

import argparse, hashlib, ipaddress, json
from pathlib import Path, PurePosixPath
from urllib.parse import urlsplit

SCHEMA = "grand-bruxelles-civ1-roster-registration-truth-v7"
REGISTRY_SCHEMA = "grand-bruxelles-civ1-roster-registry-v1"
PLAYER_ASSET = "grand-bruxelles-game/assets/characters/player_character.glb"
CHARACTER_ROOT = PurePosixPath("grand-bruxelles-game/assets/characters")
ALLOWED_ROLES = {"civilian", "police"}
REQUIRED = {"asset_path", "role", "sha256", "source_url", "license"}


def _resolve_character_asset(value: str, repo_root: Path) -> tuple[str, Path | None]:
    raw = value.strip()
    posix_raw = raw.replace("\\", "/")
    pure = PurePosixPath(posix_raw)
    normalized = pure.as_posix()
    root_parts = CHARACTER_ROOT.parts
    canonically_spelled = bool(raw) and raw == posix_raw == normalized
    lexically_confined = (
        not pure.is_absolute()
        and ".." not in pure.parts
        and len(pure.parts) > len(root_parts)
        and pure.parts[:len(root_parts)] == root_parts
    )
    if not canonically_spelled or not lexically_confined:
        return normalized, None

    resolved_repo = repo_root.resolve()
    resolved_root = (resolved_repo / Path(*root_parts)).resolve()
    candidate = (resolved_repo / Path(*pure.parts)).resolve()
    try:
        candidate.relative_to(resolved_root)
    except ValueError:
        return normalized, None
    return normalized, candidate


def _player_content_sha256(repo_root: Path) -> str | None:
    asset_path, player = _resolve_character_asset(PLAYER_ASSET, repo_root)
    if asset_path != PLAYER_ASSET or player is None or not player.is_file():
        return None
    return hashlib.sha256(player.read_bytes()).hexdigest()


def _source_url_reasons(value: str) -> list[str]:
    reasons: list[str] = []
    raw = value.strip()
    if not raw:
        return reasons
    if raw != value or any(ch.isspace() or ord(ch) < 32 for ch in raw) or "\\" in raw:
        reasons.append("source_url_not_canonical")
    try:
        parsed = urlsplit(raw)
        _ = parsed.port
    except ValueError:
        return [*reasons, "source_url_invalid"]
    if parsed.scheme.lower() != "https":
        reasons.append("source_url_https_required")
    if not parsed.hostname:
        reasons.append("source_url_host_missing")
    if parsed.username is not None or parsed.password is not None:
        reasons.append("source_url_credentials_forbidden")
    if parsed.fragment:
        reasons.append("source_url_fragment_forbidden")
    host = (parsed.hostname or "").rstrip(".").lower()
    if host == "localhost" or host.endswith(".localhost"):
        reasons.append("source_url_localhost_forbidden")
    if host:
        try:
            address = ipaddress.ip_address(host)
        except ValueError:
            pass
        else:
            if not address.is_global:
                reasons.append("source_url_non_global_ip_forbidden")
    return sorted(set(reasons))


def validate_entry(entry: object, repo_root: Path) -> dict[str, object]:
    reasons: list[str] = []
    if not isinstance(entry, dict):
        return {"valid": False, "blocking_reasons": ["entry_not_object"], "roster_eligible": False}
    missing = sorted(k for k in REQUIRED if not isinstance(entry.get(k), str) or not entry.get(k, "").strip())
    if missing:
        reasons += [f"missing_or_empty_{k}" for k in missing]

    asset_path, path = _resolve_character_asset(str(entry.get("asset_path", "")), repo_root)
    role = str(entry.get("role", ""))
    if role not in ALLOWED_ROLES:
        reasons.append("role_not_explicit_civilian_or_police")
    if asset_path == PLAYER_ASSET:
        reasons.append("player_reuse_forbidden")
    if path is None:
        reasons.append("asset_path_not_canonically_confined")

    sha = str(entry.get("sha256", "")).lower()
    if len(sha) != 64 or any(c not in "0123456789abcdef" for c in sha):
        reasons.append("sha256_invalid")
    actual_sha = None
    if path is not None:
        if not path.is_file():
            reasons.append("asset_missing")
        else:
            actual_sha = hashlib.sha256(path.read_bytes()).hexdigest()
            if sha != actual_sha:
                reasons.append("sha256_mismatch")
            player_sha = _player_content_sha256(repo_root)
            if player_sha is not None and actual_sha == player_sha:
                reasons.append("player_content_reuse_forbidden")

    source = str(entry.get("source_url", ""))
    reasons.extend(_source_url_reasons(source))
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


def _invalidate(results: list[dict[str, object]], indices: list[int], reason: str) -> None:
    for i in indices:
        item = results[i]
        item["valid"] = False
        item["roster_eligible"] = False
        item["blocking_reasons"] = sorted(set([*item.get("blocking_reasons", []), reason]))


def build_payload(registry: object, repo_root: Path) -> dict[str, object]:
    entries = registry.get("entries", []) if isinstance(registry, dict) else []
    top_reasons: list[str] = []
    registry_schema = registry.get("schema") if isinstance(registry, dict) else None
    registry_schema_valid = registry_schema == REGISTRY_SCHEMA
    if not registry_schema_valid:
        top_reasons.append("registry_schema_invalid")
    if not isinstance(registry, dict):
        top_reasons.append("registry_not_object")
        entries = []
    elif not isinstance(entries, list):
        top_reasons.append("entries_not_array")
        entries = []
    results = [validate_entry(x, repo_root) for x in entries]

    by_path: dict[object, list[int]] = {}
    for i, item in enumerate(results):
        path = item.get("asset_path")
        if path:
            by_path.setdefault(path, []).append(i)
    for indices in by_path.values():
        if len(indices) > 1:
            top_reasons.append("duplicate_asset_path")
            _invalidate(results, indices, "duplicate_asset_path")

    by_content: dict[object, list[int]] = {}
    for i, item in enumerate(results):
        actual_sha = item.get("actual_sha256")
        if actual_sha:
            by_content.setdefault(actual_sha, []).append(i)
    for indices in by_content.values():
        if len(indices) > 1:
            top_reasons.append("duplicate_content_sha256")
            _invalidate(results, indices, "duplicate_content_sha256")

    eligible = [x for x in results if x.get("roster_eligible") is True]
    return {
        "schema": SCHEMA,
        "registry_parse_valid": True,
        "registry_schema": registry_schema,
        "registry_schema_valid": registry_schema_valid,
        "registration_count": len(results),
        "eligible_count": len(eligible),
        "civilian_count": sum(x.get("role") == "civilian" for x in eligible),
        "police_count": sum(x.get("role") == "police" for x in eligible),
        "blocking_reasons": sorted(set(top_reasons)),
        "explicit_registration_required": True,
        "registry_schema_contract_required": True,
        "source_license_hash_required": True,
        "source_url_structural_provenance_required": True,
        "source_url_https_required": True,
        "source_url_local_network_forbidden": True,
        "canonical_character_path_confinement_required": True,
        "unique_content_identity_required": True,
        "filename_role_inference_forbidden": True,
        "player_reuse_as_roster_forbidden": True,
        "player_content_identity_reuse_forbidden": True,
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
    try:
        registry=json.loads(a.registry.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        registry={"schema": None, "entries": []}
        parse_error=True
    else:
        parse_error=False
    payload=build_payload(registry, a.repo_root)
    if parse_error:
        payload["registry_parse_valid"]=False
        payload["blocking_reasons"]=sorted(set([*payload["blocking_reasons"], "registry_unreadable_or_invalid_json"]))
    text=json.dumps(payload, indent=2, sort_keys=True)+"\n"
    if a.out:
        a.out.parent.mkdir(parents=True, exist_ok=True)
        a.out.write_text(text, encoding="utf-8")
    print(json.dumps(payload, sort_keys=True))
    return 2 if parse_error or payload["registry_schema_valid"] is not True else 0

if __name__ == "__main__": raise SystemExit(main())

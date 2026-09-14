#!/usr/bin/env python3
from __future__ import annotations

# v39 is a deliberately thin policy layer over the previously qualified v38
# parser/structural validator. Keeping the v38 core immutable makes the
# provenance delta reviewable while binding the local-network gate directly to
# roster eligibility.
import civ1_roster_registration_truth_v38 as _v38
from civ1_roster_local_network_provenance import is_local_network_source

SCHEMA = "grand-bruxelles-civ1-roster-registration-truth-v39"
REGISTRY_SCHEMA = _v38.REGISTRY_SCHEMA
PLAYER_ASSET = _v38.PLAYER_ASSET
CHARACTER_ROOT = _v38.CHARACTER_ROOT
ALLOWED_ROLES = _v38.ALLOWED_ROLES
REQUIRED = _v38.REQUIRED
ALLOWED_LICENSES = _v38.ALLOWED_LICENSES
DuplicateJSONKeyError = _v38.DuplicateJSONKeyError
NonStandardJSONConstantError = _v38.NonStandardJSONConstantError

_base_source_reasons = _v38._source_reasons
_base_build_payload = _v38.build_payload


def _source_reasons(value: str) -> list[str]:
    reasons = list(_base_source_reasons(value))
    if isinstance(value, str) and value.strip() and is_local_network_source(value):
        reasons.append("source_url_local_network_forbidden")
    return sorted(set(reasons))


# The v38 functions resolve globals in their defining module. Patch only the
# two policy hooks intentionally changed by v39; all structural behavior stays
# byte-for-byte in the qualified v38 core.
_v38._source_reasons = _source_reasons
_v38.SCHEMA = SCHEMA

validate_entry = _v38.validate_entry


def build_payload(registry, repo_root):
    payload = _base_build_payload(registry, repo_root)
    payload["schema"] = SCHEMA
    payload["source_url_local_network_integrated_required"] = True
    return payload


_v38.build_payload = build_payload


def main() -> int:
    return _v38.main()


if __name__ == "__main__":
    raise SystemExit(main())

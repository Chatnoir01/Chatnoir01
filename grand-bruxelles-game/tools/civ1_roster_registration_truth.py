#!/usr/bin/env python3
from __future__ import annotations

# v46 is a deliberately thin policy layer over the previously qualified v38
# parser/structural validator. Keeping the v38 core immutable makes each
# provenance delta reviewable while binding newer policy gates directly to
# roster eligibility.
import ipaddress
from urllib.parse import urlsplit

import civ1_roster_registration_truth_v38 as _v38
from civ1_roster_local_network_provenance import is_local_network_source

SCHEMA = "grand-bruxelles-civ1-roster-registration-truth-v46"
REGISTRY_SCHEMA = _v38.REGISTRY_SCHEMA
PLAYER_ASSET = _v38.PLAYER_ASSET
CHARACTER_ROOT = _v38.CHARACTER_ROOT
ALLOWED_ROLES = _v38.ALLOWED_ROLES
REQUIRED = _v38.REQUIRED
ALLOWED_LICENSES = _v38.ALLOWED_LICENSES
DuplicateJSONKeyError = _v38.DuplicateJSONKeyError
NonStandardJSONConstantError = _v38.NonStandardJSONConstantError
SPECIAL_USE_DNS_SUFFIXES = ("alt", "onion")
PRIVATE_USE_DNS_SUFFIXES = ("internal",)

_base_source_reasons = _v38._source_reasons
_base_build_payload = _v38.build_payload


def _parsed_ip(value: str):
    try:
        host = urlsplit(value).hostname
    except ValueError:
        return None
    if not host:
        return None
    try:
        return ipaddress.ip_address(host)
    except ValueError:
        return None


def _uses_ipv4_compatible_ipv6(value: str) -> bool:
    """Reject the deprecated ::/96 IPv4-compatible IPv6 provenance space."""
    address = _parsed_ip(value)
    return isinstance(address, ipaddress.IPv6Address) and (int(address) >> 32) == 0


def _uses_ipv4_mapped_ipv6(value: str) -> bool:
    """Reject ::ffff:0:0/96 aliases so one IPv4 endpoint has one source identity."""
    address = _parsed_ip(value)
    return isinstance(address, ipaddress.IPv6Address) and address.ipv4_mapped is not None


def _uses_ipv6_scope(value: str) -> bool:
    """Reject interface-scoped IPv6 locators as immutable public provenance."""
    address = _parsed_ip(value)
    return isinstance(address, ipaddress.IPv6Address) and address.scope_id is not None


def _uses_ipv6_transition(value: str) -> bool:
    """Reject IPv6 transition locators that embed or derive a second IPv4 identity.

    6to4 encodes an IPv4 address in 2002::/16 and Teredo encodes server/client IPv4
    identities in 2001::/32. For immutable asset provenance, accepting those aliases
    would let one network origin be represented by multiple source identities.
    """
    address = _parsed_ip(value)
    return isinstance(address, ipaddress.IPv6Address) and (
        address.sixtofour is not None or address.teredo is not None
    )


def _normalized_dns_host(value: str) -> str:
    try:
        return (urlsplit(value).hostname or "").rstrip(".").lower()
    except ValueError:
        return ""


def _matches_dns_namespace(host: str, suffixes: tuple[str, ...]) -> bool:
    return any(host == suffix or host.endswith("." + suffix) for suffix in suffixes)


def _uses_special_use_namespace(value: str) -> bool:
    """Reject non-public special-use DNS namespaces as ordinary HTTPS provenance."""
    host = _normalized_dns_host(value)
    return bool(host) and _matches_dns_namespace(host, SPECIAL_USE_DNS_SUFFIXES)


def _uses_private_use_namespace(value: str) -> bool:
    """Reject DNS namespaces permanently reserved for private/internal use."""
    host = _normalized_dns_host(value)
    return bool(host) and _matches_dns_namespace(host, PRIVATE_USE_DNS_SUFFIXES)


def _uses_ambiguous_dotted_numeric_host(value: str) -> bool:
    """Reject numeric dotted hosts that are not canonical IP literals.

    A host such as 999.999.999.999 or 8.8.8.08 satisfies the generic LDH DNS
    grammar after ipaddress parsing fails. Treating it as ordinary DNS creates
    an unstable provenance identity because URL/network stacks may interpret
    numeric-looking hosts differently. Canonical public IPv4 literals are
    accepted earlier by ipaddress and therefore do not match this gate.
    """
    host = _normalized_dns_host(value)
    if not host or "." not in host:
        return False
    labels = host.split(".")
    if not all(label.isascii() and label.isdigit() for label in labels):
        return False
    try:
        ipaddress.ip_address(host)
    except ValueError:
        return True
    return False


def _source_reasons(value: str) -> list[str]:
    reasons = list(_base_source_reasons(value))
    if isinstance(value, str) and value.strip():
        if is_local_network_source(value):
            reasons.append("source_url_local_network_forbidden")
        if _uses_ipv4_compatible_ipv6(value):
            reasons.append("source_url_ipv4_compatible_ipv6_forbidden")
        if _uses_ipv4_mapped_ipv6(value):
            reasons.append("source_url_ipv4_mapped_ipv6_forbidden")
        if _uses_ipv6_scope(value):
            reasons.append("source_url_ipv6_scope_forbidden")
        if _uses_ipv6_transition(value):
            reasons.append("source_url_ipv6_transition_forbidden")
        if _uses_special_use_namespace(value):
            reasons.append("source_url_special_use_namespace_forbidden")
        if _uses_private_use_namespace(value):
            reasons.append("source_url_private_use_namespace_forbidden")
        if _uses_ambiguous_dotted_numeric_host(value):
            reasons.append("source_url_ambiguous_dotted_numeric_host_forbidden")
    return sorted(set(reasons))


# The v38 functions resolve globals in their defining module. Patch only the
# policy hooks intentionally changed by the thin v46 layer; all structural
# parsing/asset behavior stays byte-for-byte in the qualified v38 core.
_v38._source_reasons = _source_reasons
_v38.SCHEMA = SCHEMA

validate_entry = _v38.validate_entry


def build_payload(registry, repo_root):
    payload = _base_build_payload(registry, repo_root)
    payload["schema"] = SCHEMA
    payload["source_url_local_network_integrated_required"] = True
    payload["source_url_ipv4_compatible_ipv6_forbidden"] = True
    payload["source_url_ipv4_mapped_ipv6_forbidden"] = True
    payload["source_url_ipv6_scope_forbidden"] = True
    payload["source_url_ipv6_transition_forbidden"] = True
    payload["source_url_special_use_namespace_forbidden"] = True
    payload["source_url_private_use_namespace_forbidden"] = True
    payload["source_url_ambiguous_dotted_numeric_host_forbidden"] = True
    return payload


_v38.build_payload = build_payload


def main() -> int:
    return _v38.main()


if __name__ == "__main__":
    raise SystemExit(main())

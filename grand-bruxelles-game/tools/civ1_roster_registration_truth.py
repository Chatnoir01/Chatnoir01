#!/usr/bin/env python3
from __future__ import annotations

# v48 is a deliberately thin policy layer over the previously qualified v38
# parser/structural validator. Keeping the v38 core immutable makes each
# provenance delta reviewable while binding newer policy gates directly to
# roster eligibility.
import ipaddress
from urllib.parse import urlsplit

import civ1_roster_registration_truth_v38 as _v38
from civ1_roster_local_network_provenance import is_local_network_source

SCHEMA = "grand-bruxelles-civ1-roster-registration-truth-v48"
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
DNS_INFRASTRUCTURE_SUFFIXES = ("arpa",)
NAT64_TRANSLATION_PREFIXES = (
    ipaddress.ip_network("64:ff9b::/96"),
    ipaddress.ip_network("64:ff9b:1::/48"),
)

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
    """Reject IPv6 transition locators that embed or derive a second IPv4 identity."""
    address = _parsed_ip(value)
    return isinstance(address, ipaddress.IPv6Address) and (
        address.sixtofour is not None or address.teredo is not None
    )


def _uses_ipv6_nat64(value: str) -> bool:
    """Reject standardized IPv4/IPv6 translation prefixes as provenance aliases."""
    address = _parsed_ip(value)
    return isinstance(address, ipaddress.IPv6Address) and any(
        address in prefix for prefix in NAT64_TRANSLATION_PREFIXES
    )


def _normalized_dns_host(value: str) -> str:
    try:
        return (urlsplit(value).hostname or "").rstrip(".").lower()
    except ValueError:
        return ""


def _matches_dns_namespace(host: str, suffixes: tuple[str, ...]) -> bool:
    return any(host == suffix or host.endswith("." + suffix) for suffix in suffixes)


def _uses_special_use_namespace(value: str) -> bool:
    host = _normalized_dns_host(value)
    return bool(host) and _matches_dns_namespace(host, SPECIAL_USE_DNS_SUFFIXES)


def _uses_private_use_namespace(value: str) -> bool:
    host = _normalized_dns_host(value)
    return bool(host) and _matches_dns_namespace(host, PRIVATE_USE_DNS_SUFFIXES)


def _uses_dns_infrastructure_namespace(value: str) -> bool:
    """Reject ARPA infrastructure names as ordinary public asset provenance."""
    host = _normalized_dns_host(value)
    return bool(host) and _matches_dns_namespace(host, DNS_INFRASTRUCTURE_SUFFIXES)


def _uses_ambiguous_dotted_numeric_host(value: str) -> bool:
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
        if _uses_ipv6_nat64(value):
            reasons.append("source_url_ipv6_nat64_forbidden")
        if _uses_special_use_namespace(value):
            reasons.append("source_url_special_use_namespace_forbidden")
        if _uses_private_use_namespace(value):
            reasons.append("source_url_private_use_namespace_forbidden")
        if _uses_dns_infrastructure_namespace(value):
            reasons.append("source_url_dns_infrastructure_namespace_forbidden")
        if _uses_ambiguous_dotted_numeric_host(value):
            reasons.append("source_url_ambiguous_dotted_numeric_host_forbidden")
    return sorted(set(reasons))


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
    payload["source_url_ipv6_nat64_forbidden"] = True
    payload["source_url_special_use_namespace_forbidden"] = True
    payload["source_url_private_use_namespace_forbidden"] = True
    payload["source_url_dns_infrastructure_namespace_forbidden"] = True
    payload["source_url_ambiguous_dotted_numeric_host_forbidden"] = True
    return payload


_v38.build_payload = build_payload


def main() -> int:
    return _v38.main()


if __name__ == "__main__":
    raise SystemExit(main())

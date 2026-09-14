#!/usr/bin/env python3
from __future__ import annotations
import hashlib, json, struct, tempfile
from pathlib import Path
from civ1_roster_registration_truth import build_payload, validate_entry
from civ1_roster_local_network_provenance import is_local_network_source, violating_sources

def minimal_glb(payload=b"{}  "):
    total=20+len(payload)
    return struct.pack("<4sII",b"glTF",2,total)+struct.pack("<I4s",len(payload),b"JSON")+payload

def candidate(path,sha,source,role="civilian"):
    return {"asset_path":path,"role":role,"sha256":sha,"source_url":source,"license":"CC0-1.0"}

def main():
    with tempfile.TemporaryDirectory() as td:
        root=Path(td)
        rel="grand-bruxelles-game/assets/characters/civilian_fixture.glb"
        asset=root/rel; asset.parent.mkdir(parents=True); asset.write_bytes(minimal_glb())
        sha=hashlib.sha256(asset.read_bytes()).hexdigest()
        good=validate_entry(candidate(rel,sha,"https://xn--exmple-cua.com/source/civilian.glb"),root)
        assert good["roster_eligible"] is True, good
        for source in ("https://xn--abc.com/source/civilian.glb","https://xn--a.com/source/civilian.glb","https://xn--0.com/source/civilian.glb"):
            bad=validate_entry(candidate(rel,sha,source),root)
            assert "source_url_idna_label_invalid" in bad["blocking_reasons"], (source,bad)
            assert bad["roster_eligible"] is False
        dns_bad=validate_entry(candidate(rel,sha,"https://xn--invalid-.com/source/civilian.glb"),root)
        assert "source_url_dns_host_invalid" in dns_bad["blocking_reasons"], dns_bad
        assert "source_url_idna_label_invalid" not in dns_bad["blocking_reasons"], dns_bad
        assert dns_bad["roster_eligible"] is False
        for source,reason in (("https://assets.character-fixtures.com/source/civilian.glb?","source_url_query_forbidden"),("https://assets.character-fixtures.com/source/civilian.glb#","source_url_fragment_forbidden"),("https://assets.character-fixtures.com/source/civilian.glb?x=1","source_url_query_forbidden"),("https://assets.character-fixtures.com/source/civilian.glb#frag","source_url_fragment_forbidden"),("https://assets.character-fixtures.com/source/civilian.glb?#","source_url_query_forbidden")):
            bad=validate_entry(candidate(rel,sha,source),root); assert reason in bad["blocking_reasons"], (source,bad); assert bad["roster_eligible"] is False
        for source in ("https://example.invalid/source/civilian.glb","https://assets.invalid/source/civilian.glb","https://assets.test/source/civilian.glb","https://assets.example/source/civilian.glb","https://example.com/source/civilian.glb","https://example.net/source/civilian.glb","https://example.org/source/civilian.glb","https://assets.example.com/source/civilian.glb","https://cdn.assets.example.net/source/civilian.glb","https://characters.example.org/source/civilian.glb"):
            bad=validate_entry(candidate(rel,sha,source),root); assert "source_url_reserved_host_forbidden" in bad["blocking_reasons"], (source,bad); assert bad["roster_eligible"] is False
        local_sources=("https://assets.local/source/civilian.glb","https://cdn.assets.local/source/civilian.glb","https://home.arpa/source/civilian.glb","https://cdn.home.arpa/source/civilian.glb","https://localhost/source/civilian.glb","https://assets.localhost/source/civilian.glb")
        for source in local_sources:
            assert is_local_network_source(source) is True, source
            bad=validate_entry(candidate(rel,sha,source),root); assert "source_url_local_network_forbidden" in bad["blocking_reasons"], (source,bad); assert bad["roster_eligible"] is False, (source,bad)
        public_source="https://assets.character-fixtures.com/source/civilian.glb"; assert is_local_network_source(public_source) is False
        public=validate_entry(candidate(rel,sha,public_source),root); assert "source_url_local_network_forbidden" not in public["blocking_reasons"], public; assert public["roster_eligible"] is True, public
        synthetic_registry={"schema":"grand-bruxelles-civ1-roster-registry-v1","entries":[candidate(rel,sha,s) for s in local_sources]}; assert violating_sources(synthetic_registry)==list(local_sources)
        for source in ("https://assets.alt/source/civilian.glb","https://cdn.assets.alt/source/civilian.glb","https://assets.onion/source/civilian.glb","https://cdn.assets.onion/source/civilian.glb"):
            bad=validate_entry(candidate(rel,sha,source),root); assert "source_url_special_use_namespace_forbidden" in bad["blocking_reasons"], (source,bad); assert bad["roster_eligible"] is False, (source,bad)
        for source in ("https://assets.internal/source/civilian.glb","https://cdn.assets.internal/source/civilian.glb"):
            bad=validate_entry(candidate(rel,sha,source),root); assert "source_url_private_use_namespace_forbidden" in bad["blocking_reasons"], (source,bad); assert bad["roster_eligible"] is False, (source,bad)
        for source in ("https://[::7f00:1]/source/civilian.glb","https://[::a00:1]/source/civilian.glb","https://[::c0a8:101]/source/civilian.glb"):
            bad=validate_entry(candidate(rel,sha,source),root); assert "source_url_ipv4_compatible_ipv6_forbidden" in bad["blocking_reasons"], (source,bad); assert bad["roster_eligible"] is False, (source,bad)
        public_ipv6=validate_entry(candidate(rel,sha,"https://[2606:4700:4700::1111]/source/civilian.glb"),root); assert "source_url_ipv4_compatible_ipv6_forbidden" not in public_ipv6["blocking_reasons"], public_ipv6; assert public_ipv6["roster_eligible"] is True, public_ipv6
        for source in ("https://[::ffff:8.8.8.8]/source/civilian.glb","https://[::ffff:1.1.1.1]/source/civilian.glb"):
            bad=validate_entry(candidate(rel,sha,source),root); assert "source_url_ipv4_mapped_ipv6_forbidden" in bad["blocking_reasons"], (source,bad); assert bad["roster_eligible"] is False, (source,bad)
        for source in ("https://[2606:4700:4700::1111%25eth0]/source/civilian.glb","https://[2606:4700:4700::1111%25en0]/source/civilian.glb"):
            bad=validate_entry(candidate(rel,sha,source),root); assert "source_url_ipv6_scope_forbidden" in bad["blocking_reasons"], (source,bad); assert bad["roster_eligible"] is False, (source,bad)
        for source in ("https://999.999.999.999/source/civilian.glb","https://8.8.8.08/source/civilian.glb","https://256.1.1.1/source/civilian.glb"):
            bad=validate_entry(candidate(rel,sha,source),root); assert "source_url_ambiguous_dotted_numeric_host_forbidden" in bad["blocking_reasons"], (source,bad); assert bad["roster_eligible"] is False, (source,bad)
        canonical_ipv4=validate_entry(candidate(rel,sha,"https://8.8.8.8/source/civilian.glb"),root)
        assert "source_url_ambiguous_dotted_numeric_host_forbidden" not in canonical_ipv4["blocking_reasons"], canonical_ipv4
        assert canonical_ipv4["roster_eligible"] is True, canonical_ipv4
        for source in ("https://[2002:808:808::]/source/civilian.glb","https://[2002:7f00:1::]/source/civilian.glb","https://[2001:0:4136:e378:8000:63bf:3fff:fdd2]/source/civilian.glb"):
            bad=validate_entry(candidate(rel,sha,source),root); assert "source_url_ipv6_transition_forbidden" in bad["blocking_reasons"], (source,bad); assert bad["roster_eligible"] is False, (source,bad)
        canonical_ipv6=validate_entry(candidate(rel,sha,"https://[2606:4700:4700::1111]/source/civilian.glb"),root)
        assert "source_url_ipv6_transition_forbidden" not in canonical_ipv6["blocking_reasons"], canonical_ipv6
        assert canonical_ipv6["roster_eligible"] is True, canonical_ipv6
        canonical_registry_path=Path("grand-bruxelles-game/qa/civ1_roster_registry.json")
        if canonical_registry_path.is_file():
            canonical_registry=json.loads(canonical_registry_path.read_text(encoding="utf-8")); assert violating_sources(canonical_registry)==[], violating_sources(canonical_registry)
        rel_copy="grand-bruxelles-game/assets/characters/civilian_fixture_copy.glb"; copy_asset=root/rel_copy; copy_asset.write_bytes(asset.read_bytes())
        duplicate_content=build_payload({"schema":"grand-bruxelles-civ1-roster-registry-v1","entries":[candidate(rel,sha,"https://assets.character-fixtures.com/source/civilian-a.glb"),candidate(rel_copy,sha,"https://assets.character-fixtures.com/source/civilian-b.glb")]},root)
        assert duplicate_content["eligible_count"]==0 and "duplicate_content_sha256" in duplicate_content["blocking_reasons"] and duplicate_content["invalid_entry_count"]==2
        assert all("duplicate_content_sha256" in e["blocking_reasons"] for e in duplicate_content["entries"]); assert duplicate_content["unique_content_identity_required"] is True
        rel_other="grand-bruxelles-game/assets/characters/police_fixture.glb"; other_asset=root/rel_other; other_asset.write_bytes(minimal_glb(b"{ } ")); other_sha=hashlib.sha256(other_asset.read_bytes()).hexdigest(); assert other_sha!=sha
        duplicate_source=build_payload({"schema":"grand-bruxelles-civ1-roster-registry-v1","entries":[candidate(rel,sha,"https://assets.character-fixtures.com/source/shared.glb"),candidate(rel_other,other_sha,"https://assets.character-fixtures.com/source/shared.glb",role="police")]},root)
        assert duplicate_source["eligible_count"]==0 and "duplicate_source_url" in duplicate_source["blocking_reasons"] and duplicate_source["invalid_entry_count"]==2
        assert all("duplicate_source_url" in e["blocking_reasons"] for e in duplicate_source["entries"])
        payload=build_payload({"schema":"grand-bruxelles-civ1-roster-registry-v1","entries":[]},root)
        assert payload["schema"]=="grand-bruxelles-civ1-roster-registration-truth-v46"
        assert payload["blocking_reasons"]==[] and payload["registration_count"]==0 and payload["eligible_count"]==0
        for flag in ("source_url_idna_alabel_roundtrip_required","source_url_query_forbidden","source_url_fragment_forbidden","source_url_empty_delimiters_forbidden","source_url_reserved_host_forbidden","source_url_reserved_domain_subdomains_forbidden","source_url_local_network_forbidden","source_url_local_network_integrated_required","source_url_ipv4_compatible_ipv6_forbidden","source_url_ipv4_mapped_ipv6_forbidden","source_url_ipv6_scope_forbidden","source_url_ipv6_transition_forbidden","source_url_special_use_namespace_forbidden","source_url_private_use_namespace_forbidden","source_url_ambiguous_dotted_numeric_host_forbidden","unique_content_identity_required","unique_source_provenance_required"):
            assert payload[flag] is True, (flag,payload)
        assert payload["roster_authorized"] is False and payload["runtime_authorized"] is False and payload["visual_approval_claimed"] is False
    print("CIV1_ROSTER_REGISTRATION_TRUTH_V46_IPV6_TRANSITION_GREEN")
if __name__=="__main__": main()

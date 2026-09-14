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
        for source in (
            "https://xn--abc.com/source/civilian.glb",
            "https://xn--a.com/source/civilian.glb",
            "https://xn--0.com/source/civilian.glb",
        ):
            bad=validate_entry(candidate(rel,sha,source),root)
            assert "source_url_idna_label_invalid" in bad["blocking_reasons"], (source,bad)
            assert bad["roster_eligible"] is False

        dns_bad=validate_entry(candidate(rel,sha,"https://xn--invalid-.com/source/civilian.glb"),root)
        assert "source_url_dns_host_invalid" in dns_bad["blocking_reasons"], dns_bad
        assert "source_url_idna_label_invalid" not in dns_bad["blocking_reasons"], dns_bad
        assert dns_bad["roster_eligible"] is False

        for source,reason in (
            ("https://assets.character-fixtures.com/source/civilian.glb?","source_url_query_forbidden"),
            ("https://assets.character-fixtures.com/source/civilian.glb#","source_url_fragment_forbidden"),
            ("https://assets.character-fixtures.com/source/civilian.glb?x=1","source_url_query_forbidden"),
            ("https://assets.character-fixtures.com/source/civilian.glb#frag","source_url_fragment_forbidden"),
            ("https://assets.character-fixtures.com/source/civilian.glb?#","source_url_query_forbidden"),
        ):
            bad=validate_entry(candidate(rel,sha,source),root)
            assert reason in bad["blocking_reasons"], (source,bad)
            assert bad["roster_eligible"] is False

        for source in (
            "https://example.invalid/source/civilian.glb",
            "https://assets.invalid/source/civilian.glb",
            "https://assets.test/source/civilian.glb",
            "https://assets.example/source/civilian.glb",
            "https://example.com/source/civilian.glb",
            "https://example.net/source/civilian.glb",
            "https://example.org/source/civilian.glb",
            "https://assets.example.com/source/civilian.glb",
            "https://cdn.assets.example.net/source/civilian.glb",
            "https://characters.example.org/source/civilian.glb",
        ):
            bad=validate_entry(candidate(rel,sha,source),root)
            assert "source_url_reserved_host_forbidden" in bad["blocking_reasons"], (source,bad)
            assert bad["roster_eligible"] is False

        local_sources=(
            "https://assets.local/source/civilian.glb",
            "https://cdn.assets.local/source/civilian.glb",
            "https://home.arpa/source/civilian.glb",
            "https://cdn.home.arpa/source/civilian.glb",
            "https://localhost/source/civilian.glb",
            "https://assets.localhost/source/civilian.glb",
        )
        for source in local_sources:
            assert is_local_network_source(source) is True, source
        assert is_local_network_source("https://assets.character-fixtures.com/source/civilian.glb") is False
        synthetic_registry={"schema":"grand-bruxelles-civ1-roster-registry-v1","entries":[candidate(rel,sha,s) for s in local_sources]}
        assert violating_sources(synthetic_registry)==list(local_sources)

        canonical_registry_path=Path("grand-bruxelles-game/qa/civ1_roster_registry.json")
        if canonical_registry_path.is_file():
            canonical_registry=json.loads(canonical_registry_path.read_text(encoding="utf-8"))
            assert violating_sources(canonical_registry)==[], violating_sources(canonical_registry)

        rel_copy="grand-bruxelles-game/assets/characters/civilian_fixture_copy.glb"
        copy_asset=root/rel_copy; copy_asset.write_bytes(asset.read_bytes())
        duplicate_content=build_payload(
            {"schema":"grand-bruxelles-civ1-roster-registry-v1","entries":[
                candidate(rel,sha,"https://assets.character-fixtures.com/source/civilian-a.glb"),
                candidate(rel_copy,sha,"https://assets.character-fixtures.com/source/civilian-b.glb"),
            ]},root)
        assert duplicate_content["eligible_count"]==0, duplicate_content
        assert "duplicate_content_sha256" in duplicate_content["blocking_reasons"], duplicate_content
        assert duplicate_content["invalid_entry_count"]==2, duplicate_content
        assert all("duplicate_content_sha256" in e["blocking_reasons"] for e in duplicate_content["entries"]), duplicate_content
        assert duplicate_content["unique_content_identity_required"] is True

        rel_other="grand-bruxelles-game/assets/characters/police_fixture.glb"
        other_asset=root/rel_other; other_asset.write_bytes(minimal_glb(b"{ } "))
        other_sha=hashlib.sha256(other_asset.read_bytes()).hexdigest()
        assert other_sha!=sha
        duplicate_source=build_payload(
            {"schema":"grand-bruxelles-civ1-roster-registry-v1","entries":[
                candidate(rel,sha,"https://assets.character-fixtures.com/source/shared.glb"),
                candidate(rel_other,other_sha,"https://assets.character-fixtures.com/source/shared.glb",role="police"),
            ]},root)
        assert duplicate_source["eligible_count"]==0, duplicate_source
        assert "duplicate_source_url" in duplicate_source["blocking_reasons"], duplicate_source
        assert duplicate_source["invalid_entry_count"]==2, duplicate_source
        assert all("duplicate_source_url" in e["blocking_reasons"] for e in duplicate_source["entries"]), duplicate_source

        payload=build_payload({"schema":"grand-bruxelles-civ1-roster-registry-v1","entries":[]},root)
        assert payload["schema"]=="grand-bruxelles-civ1-roster-registration-truth-v38"
        assert payload["blocking_reasons"]==[]
        assert payload["registration_count"]==0 and payload["eligible_count"]==0
        assert payload["source_url_idna_alabel_roundtrip_required"] is True
        assert payload["source_url_query_forbidden"] is True
        assert payload["source_url_fragment_forbidden"] is True
        assert payload["source_url_empty_delimiters_forbidden"] is True
        assert payload["source_url_reserved_host_forbidden"] is True
        assert payload["source_url_reserved_domain_subdomains_forbidden"] is True
        assert payload["source_url_local_network_forbidden"] is True
        assert payload["unique_content_identity_required"] is True
        assert payload["unique_source_provenance_required"] is True
        assert payload["roster_authorized"] is False
        assert payload["runtime_authorized"] is False
        assert payload["visual_approval_claimed"] is False
    print("CIV1_ROSTER_REGISTRATION_TRUTH_V38_LOCAL_NETWORK_GATE_GREEN")
if __name__=="__main__": main()

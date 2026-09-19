#!/usr/bin/env python3
from __future__ import annotations
import json, tempfile
from pathlib import Path
from civ1_roster_source_readiness import _canonical_path_text, blocking_entries, source_ready


def main():
    assert _canonical_path_text("assets/characters/civilians/civ1/source/café.glb") == "assets/characters/civilians/civ1/source/café.glb", "NFC Unicode provenance names must remain portable"
    assert _canonical_path_text("assets/characters/civilians/civ1/source/body\ue000.glb") is None, "private-use Unicode must not create opaque provenance identities"
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        status = root / "grand-bruxelles-game/assets/characters/civilians/civ1/source_status.json"
        status.parent.mkdir(parents=True)
        registry = {"schema":"grand-bruxelles-civ1-roster-registry-v1","entries":[{"asset_path":"grand-bruxelles-game/assets/characters/civilians/civ1/civ1.glb"}]}
        blocked_status = {"production_authorized":False,"activation_ready":False,"source_package_present":False,"blocker":"source_not_ready"}
        status.write_text(json.dumps(blocked_status),encoding="utf-8")
        assert source_ready(root) is False
        assert blocking_entries(registry,root)==["grand-bruxelles-game/assets/characters/civilians/civ1/civ1.glb"]

        source_path="assets/characters/civilians/civ1/source/body.glb"
        source_file=root/"grand-bruxelles-game"/source_path
        source_file.parent.mkdir(parents=True); source_file.write_bytes(b"civ1-source-body")
        ready_status={"candidate_id":"CIV-1","production_authorized":True,"activation_ready":True,"source_package_present":True,"blocker":None,"character_source":{"license_evidence":{"unresolved_components":[]}},"source_paths":[source_path],"source_manifest":{source_path:{"upstream_path":"godot_project/body.glb","license_scope_verified":True,"license":"CC0-1.0","git_blob_sha1":"3914b89458e542b73f0168b0bf80c8e356e78f9c","size_bytes":16}}}
        status.write_text(json.dumps(ready_status),encoding="utf-8")
        assert source_ready(root) is True
        assert blocking_entries(registry,root)==[]

        duplicate_ready=json.dumps(ready_status).replace('"production_authorized": true','"production_authorized": false, "production_authorized": true',1)
        status.write_text(duplicate_ready,encoding="utf-8"); assert source_ready(root) is False,"CIV-1 readiness must reject duplicate keys"
        status.write_text(json.dumps(ready_status),encoding="utf-8")
        status_backing=status.with_name("source_status-backing.json"); status.unlink(); status_backing.write_text(json.dumps(ready_status),encoding="utf-8"); status.symlink_to(status_backing.name)
        assert source_ready(root) is False,"CIV-1 readiness must reject a symlinked canonical status"
        status.unlink(); status_backing.unlink(); status.write_text(json.dumps(ready_status),encoding="utf-8")
        backing_file=source_file.with_name("body-backing.glb"); source_file.unlink(); backing_file.write_bytes(b"civ1-source-body"); source_file.symlink_to(backing_file.name)
        status.write_text(json.dumps(ready_status),encoding="utf-8"); assert source_ready(root) is False,"CIV-1 readiness must reject symlinked source paths"
        source_file.unlink(); backing_file.unlink(); source_file.write_bytes(b"civ1-source-body")
        source_file.unlink(); status.write_text(json.dumps(ready_status),encoding="utf-8"); assert source_ready(root) is False,"source_package_present=true must be grounded in an actual source file"
        source_file.write_bytes(b"civ1-source-body")
        source_file.write_bytes(b"tampered-civ1-source"); status.write_text(json.dumps(ready_status),encoding="utf-8"); assert source_ready(root) is False,"readiness must bind each source file to declared blob identity and size"
        source_file.write_bytes(b"civ1-source-body")

        missing_integrity=json.loads(json.dumps(ready_status)); del missing_integrity["source_manifest"][source_path]["git_blob_sha1"]; status.write_text(json.dumps(missing_integrity),encoding="utf-8"); assert source_ready(root) is False,"every ready source record must carry immutable Git blob identity"
        missing_upstream=json.loads(json.dumps(ready_status)); del missing_upstream["source_manifest"][source_path]["upstream_path"]; status.write_text(json.dumps(missing_upstream),encoding="utf-8"); assert source_ready(root) is False,"every ready source record must identify its upstream path"
        traversal_upstream=json.loads(json.dumps(ready_status)); traversal_upstream["source_manifest"][source_path]["upstream_path"]="../body.glb"; status.write_text(json.dumps(traversal_upstream),encoding="utf-8"); assert source_ready(root) is False,"upstream source identity must reject traversal paths"
        degenerate_upstream=json.loads(json.dumps(ready_status)); degenerate_upstream["source_manifest"][source_path]["upstream_path"]="."; status.write_text(json.dumps(degenerate_upstream),encoding="utf-8"); assert source_ready(root) is False,"upstream source identity must name a file rather than the current-directory pseudo-path"
        second_source_path="assets/characters/civilians/civ1/source/hair.glb"; second_source_file=root/"grand-bruxelles-game"/second_source_path; second_source_file.write_bytes(b"civ1-source-hair")
        duplicate_upstream=json.loads(json.dumps(ready_status)); duplicate_upstream["source_paths"].append(second_source_path); duplicate_upstream["source_manifest"][second_source_path]={"upstream_path":"GODOT_PROJECT/BODY.GLB","license_scope_verified":True,"license":"CC0-1.0","git_blob_sha1":"5e075645ed61930f05dad4c28ce707754794a53e","size_bytes":16}; status.write_text(json.dumps(duplicate_upstream),encoding="utf-8"); assert source_ready(root) is False,"distinct local source files must not alias the same case-insensitive upstream identity"
        missing_license=json.loads(json.dumps(ready_status)); del missing_license["source_manifest"][source_path]["license"]; status.write_text(json.dumps(missing_license),encoding="utf-8"); assert source_ready(root) is False,"license_scope_verified=true must not substitute for an explicit license identity"
        unresolved_license_id=json.loads(json.dumps(ready_status)); unresolved_license_id["source_manifest"][source_path]["license"]="UNKNOWN"; status.write_text(json.dumps(unresolved_license_id),encoding="utf-8"); assert source_ready(root) is False,"ready source records must use an explicitly allowed license identity"
        unresolved_license=json.loads(json.dumps(ready_status)); unresolved_license["character_source"]["license_evidence"]["unresolved_components"]=["body.glb#embedded_animation_payload"]; status.write_text(json.dumps(unresolved_license),encoding="utf-8"); assert source_ready(root) is False,"CIV-1 must remain blocked while license evidence has unresolved components"
        unverified_manifest=json.loads(json.dumps(ready_status)); unverified_manifest["source_manifest"][source_path]["license_scope_verified"]=False; status.write_text(json.dumps(unverified_manifest),encoding="utf-8"); assert source_ready(root) is False,"every source manifest item must have verified license scope"
        wrong_candidate=json.loads(json.dumps(ready_status)); wrong_candidate["candidate_id"]="OTHER"; status.write_text(json.dumps(wrong_candidate),encoding="utf-8"); assert source_ready(root) is False,"readiness status must be bound to CIV-1 identity"
        stale_blocker=json.loads(json.dumps(ready_status)); stale_blocker["blocker"]="independently_licensed_idle_walk_run_not_verified"; status.write_text(json.dumps(stale_blocker),encoding="utf-8"); assert source_ready(root) is False,"ready flags must not override an active blocker"
        manifest_mismatch=json.loads(json.dumps(ready_status)); manifest_mismatch["source_paths"].append("assets/characters/civilians/civ1/source/hair.glb"); status.write_text(json.dumps(manifest_mismatch),encoding="utf-8"); assert source_ready(root) is False,"source_paths and source_manifest must match exactly"
    print("CIV1_ROSTER_SOURCE_READINESS_GREEN")

if __name__=="__main__": main()

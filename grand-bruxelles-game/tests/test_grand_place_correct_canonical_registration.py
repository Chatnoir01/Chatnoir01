#!/usr/bin/env python3
import copy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGET = "bxl-e148500-n170500-s500"
MANIFEST_REL = f"data/cell_manifests/{TARGET}.json"
INDEX_REL = "data/provenance/brussels_registered_cell_manifest_index.json"
CONTRACT_REL = "data/qa/grand_place_correct_canonical_registration.contract.json"
REVIEW_REL = "data/provenance/grand_place_correct_canonical_registration.review.json"
SOURCE_REL = f"data/urbis/remaining_brussels/cells/{TARGET}/manifest.json"
MATURITY_REL = f"data/urbis/remaining_brussels/cells/{TARGET}/maturity.json"


def load(rel):
    return json.loads((ROOT / rel).read_text())


def sha_file(rel):
    return hashlib.sha256((ROOT / rel).read_bytes()).hexdigest()


def semantic_index_sha(index):
    basis = copy.deepcopy(index)
    basis.pop("semantic_sha256", None)
    # production_base_sha is continuity metadata, not registered-cell identity.
    basis.pop("production_base_sha", None)
    payload = json.dumps(basis, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(payload).hexdigest()


contract = load(CONTRACT_REL)
review = load(REVIEW_REL)
source = load(SOURCE_REL)
maturity = load(MATURITY_REL)
manifest = load(MANIFEST_REL)
index = load(INDEX_REL)

assert contract["target_cell_id"] == TARGET
assert review["semantic_sha256"] == contract["preflight_review_semantic_sha256"]
assert review["status"] == "READY_FOR_CANONICAL_MANIFEST_REVIEW"
assert review["registered_cell_index"]["target_present"] is False
assert review["municipality_evidence"]["coverage_ratio"] == 1.0
assert review["municipality_evidence"]["niscode"] == "21004"
assert review["municipality_evidence"]["semantic_sha256"] == contract["municipality_semantic_sha256"]
assert review["source_evidence"]["source_semantic_sha256"] == contract["source_semantic_sha256"]

assert source["cell_id"] == TARGET
assert source["crs"] == "EPSG:31370"
assert source["bbox"] == [148500.0, 170500.0, 149000.0, 171000.0]
assert maturity["maturity"]["state"] == "data_ready"
assert maturity["maturity"]["gates"]["runtime_geometry"] is False
assert maturity["maturity"]["gates"]["collisions"] is False
assert maturity["maturity"]["gates"]["streaming"] is False

assert sha_file(MANIFEST_REL) == contract["canonical_manifest_sha256"]
assert manifest["cell_id"] == TARGET
assert manifest["bbox"] == source["bbox"]
assert manifest["crs"] == source["crs"]
assert manifest["geometry"]["authoritative_geometry_ready"] is True
assert manifest["geometry"]["layer_feature_counts"] == {
    "buildings": 1110,
    "street_axes": 180,
    "street_surfaces": 598,
    "train_network": 12,
    "tram_network": 12,
}
assert manifest["provenance"]["source_semantic_sha256"] == contract["source_semantic_sha256"]
assert manifest["provenance"]["municipality_niscode"] == "21004"
assert manifest["provenance"]["municipality_coverage_ratio"] == 1.0
assert manifest["maturity"]["state"] == "data_ready"
for key in ["runtime_geometry", "collisions", "streaming", "performance", "photo_match"]:
    assert manifest["maturity"]["gates"][key] is False, key

# The contract records the historical registration transition. The global index is
# monotone and may legitimately gain later evidence-only cells. Preserve the local
# Grand-Place proof while independently validating the current index schema/hash.
entries = index.get("entries")
assert isinstance(entries, list) and entries
assert index["registered_cell_count"] == len(entries)
assert index["registered_cell_count"] >= contract["registered_cell_count"]
ids = [entry["cell_id"] for entry in entries]
assert ids == sorted(ids)
assert len(ids) == len(set(ids))
assert TARGET in ids
entry = next(e for e in entries if e["cell_id"] == TARGET)
assert entry["manifest_path"] == MANIFEST_REL
assert entry["manifest_sha256"] == contract["canonical_manifest_sha256"]
assert entry["bbox"] == source["bbox"]
assert entry["crs"] == "EPSG:31370"
assert entry["maturity_state"] == "data_ready"
assert entry["evidence_only"] is True
for key in ["runtime_mount_authorized", "rendered_geometry_authorized", "collision_authorized", "safe_spawn_authorized", "jouable_promotion_authorized"]:
    assert entry[key] is False, key

assert semantic_index_sha(index) == index["semantic_sha256"]
# The historical index semantic is provenance for the registration event, not a
# freeze on future cells. It must remain a well-formed immutable digest.
assert isinstance(contract["registered_index_semantic_sha256"], str)
assert len(contract["registered_index_semantic_sha256"]) == 64
assert contract["registered_index_semantic_sha256"] != index["semantic_sha256"] or index["registered_cell_count"] == contract["registered_cell_count"]
assert index["destination_readiness"] == "REGISTERED_CELL_INDEX_EVIDENCE_ONLY"
assert index["road_crosswalk_authorized"] is False
assert index["runtime_directory_scan_authorized"] is False
for key in ["runtime_mount_authorized", "rendered_geometry_authorized", "collision_authorized", "safe_spawn_authorized", "jouable_promotion_authorized"]:
    assert index[key] is False, key

auth = contract["authorization"]
assert auth["canonical_registration"] is True
assert auth["municipality_assignment"] is True
for key in ["road_to_cell_mapping", "runtime_directory_scan", "runtime_mount", "rendered_geometry", "collision", "safe_spawn", "jouable_promotion"]:
    assert auth[key] is False, key

print(
    "GRAND_PLACE_CORRECT_CANONICAL_REGISTRATION_OK "
    f"cell={TARGET} manifest_sha={contract['canonical_manifest_sha256']} "
    f"index_semantic={index['semantic_sha256']} registered={index['registered_cell_count']} "
    f"historical_registered={contract['registered_cell_count']} "
    "readiness=REGISTERED_NOT_RENDERED runtime_rails_closed=true"
)
#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-civ1-quaternius-material-integrity.yml"
SOURCE_RECORD = ROOT / "evidence" / "character" / "quaternius_material_source_integrity.json"


def require(text: str, token: str) -> None:
    assert token in text, f"missing material-integrity contract token: {token}"


def main() -> None:
    assert WORKFLOW.exists(), "Quaternius material-integrity workflow missing"
    workflow = WORKFLOW.read_text(encoding="utf-8")
    for token in (
        "Godot_v4.7.1-stable_linux.x86_64.zip",
        "c7ff14fd28472c8d4f193043de30278dcf7e5241a1dcf7566b02e27addaa33ba",
        "f868b316facd04d7686784b254f6f1bbcd7e14bc06f3ec70f92a3144dc462767",
        "creative commons zero",
        "T_Hair_1_Normal_png.png",
        "T_Eye_Normal_png.png",
        "T_Hair_1_Normal.png",
        "T_Eye_Normal.png",
        "Can't open file from path",
        "MATERIAL_SOURCE_INCOMPLETE",
        "SOURCE_REFERENCE_TYPO_CONFIRMED",
        "broken-reference-analysis.txt",
        "canonical_sibling_present",
        "referencing_files",
        "material-inventory.txt",
        "diagnostic_only=true",
        "runtime_authorized=false",
        "visual_approval_claimed=false",
        "PROJECT_BOOTSTRAP=ephemeral",
        "config/name=\"CIV1MaterialIntegrity\"",
        "project_bootstrap=%s",
        # Graph-level proof: a malformed image URI only blocks promotion if a
        # material used by an actual mesh primitive reaches that image through
        # glTF material -> texture -> image references.
        "images = doc.get('images', [])",
        "textures = doc.get('textures', [])",
        "materials = doc.get('materials', [])",
        "meshes = doc.get('meshes', [])",
        "surface_material_indices",
        "material_texture_indices",
        "texture_source_indices",
        "surface_bound_broken_files",
        "BROKEN_REFERENCE_NOT_SURFACE_BOUND",
        "surface_bound=true",
    ):
        require(workflow, token)
    for forbidden in (
        "cp \"$HAIR_SOURCE\"",
        "cp \"$EYE_SOURCE\"",
        "MATERIAL_IMPORT_CLEAN",
        "T_Hair_1_Normal.png T_Hair_1_Normal_png.png",
        "T_Eye_Normal.png T_Eye_Normal_png.png",
    ):
        assert forbidden not in workflow, f"material gate must not synthesize/claim clean source: {forbidden}"

    # Durable provenance must record exactly what the exact-source Godot 4.7.1
    # artifact proved, without converting that evidence into a synthetic repair.
    assert SOURCE_RECORD.exists(), "durable Quaternius source-integrity record missing"
    record = json.loads(SOURCE_RECORD.read_text(encoding="utf-8"))
    assert record["format"] == "grand-bruxelles-quaternius-material-source-integrity-v1"
    assert record["source_sha256"] == "f868b316facd04d7686784b254f6f1bbcd7e14bc06f3ec70f92a3144dc462767"
    assert record["license"] == "CC0-1.0"
    assert record["godot"] == "4.7.1.stable.official.a13da4feb"
    assert record["classification"] == "SOURCE_REFERENCE_TYPO_CONFIRMED"
    assert record["promotion_blocked"] is True
    assert record["synthetic_repair_authorized"] is False
    assert record["runtime_authorized"] is False
    assert record["visual_approval_claimed"] is False
    assert record["evidence"]["workflow_run_id"] == 33476376222
    assert record["evidence"]["artifact_id"] == 9788311554
    assert record["evidence"]["artifact_digest"] == "sha256:681a109eef909c96d8afb17b10a09122f4d1479b2b03de4c8af382bc7cecc16d"

    refs = {item["broken_reference"]: item for item in record["broken_references"]}
    assert set(refs) == {"T_Hair_1_Normal_png.png", "T_Eye_Normal_png.png"}
    hair = refs["T_Hair_1_Normal_png.png"]
    eye = refs["T_Eye_Normal_png.png"]
    assert hair["canonical_sibling"] == "T_Hair_1_Normal.png"
    assert hair["canonical_sibling_present"] is True and hair["broken_file_present"] is False
    assert hair["surface_bound"] is True
    assert hair["referencing_files"] == ["addons/quaternius_ik_rigged/Godot - UE/Superhero_Male_FullBody.gltf"]
    assert hair["bound_surfaces"] == [{"gltf": "Superhero_Male_FullBody.gltf", "mesh": 0, "primitive": 0, "material": 0, "texture": 0, "image": 0}]

    assert eye["canonical_sibling"] == "T_Eye_Normal.png"
    assert eye["canonical_sibling_present"] is True and eye["broken_file_present"] is False
    assert eye["surface_bound"] is True
    assert eye["referencing_files"] == [
        "addons/quaternius_ik_rigged/Godot - UE/Superhero_Female_FullBody.gltf",
        "addons/quaternius_ik_rigged/Godot - UE/Superhero_Male_FullBody.gltf",
    ]
    assert eye["bound_surfaces"] == [
        {"gltf": "Superhero_Female_FullBody.gltf", "mesh": 1, "primitive": 0, "material": 1, "texture": 2, "image": 2},
        {"gltf": "Superhero_Male_FullBody.gltf", "mesh": 1, "primitive": 0, "material": 1, "texture": 2, "image": 2},
    ]

    print("CIV1_QUATERNIUS_MATERIAL_INTEGRITY_CONTRACT_OK")


if __name__ == "__main__":
    main()

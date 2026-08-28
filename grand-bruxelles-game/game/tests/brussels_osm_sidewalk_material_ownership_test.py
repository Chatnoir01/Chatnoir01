from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT / "game" / "scripts" / "brussels_osm_sidewalk_surface_runtime.gd"
OWNER_META = "shared_sidewalk_material_owner"
OWNER_VALUE = "brussels_osm_sidewalk_surface_runtime"


def fail(message: str) -> None:
    raise AssertionError(message)


def function_body(source: str, function_name: str) -> str:
    lines = source.splitlines()
    marker = f"func {function_name}("
    start = None
    for index, line in enumerate(lines):
        if line.startswith(marker):
            start = index + 1
            break
    if start is None:
        return ""
    body: list[str] = []
    for line in lines[start:]:
        if line and not line[0].isspace() and not line.lstrip().startswith("#"):
            break
        body.append(line)
    return "\n".join(body)


def main() -> None:
    if not RUNTIME.is_file():
        fail("Brussels OSM sidewalk runtime missing")
    source = RUNTIME.read_text(encoding="utf-8")

    if f'const MATERIAL_OWNER_META := &"{OWNER_META}"' not in source:
        fail("shared sidewalk material owner metadata key is not locked")
    if f'const MATERIAL_OWNER_VALUE := "{OWNER_VALUE}"' not in source:
        fail("shared sidewalk material owner identity is not locked")

    foreign_body = function_body(source, "_has_foreign_material_owner")
    if not foreign_body:
        fail("foreign material owner detector missing")
    for token in ("has_meta(MATERIAL_OWNER_META)", "get_meta(MATERIAL_OWNER_META", "MATERIAL_OWNER_VALUE"):
        if token not in foreign_body:
            fail(f"foreign material owner detector incomplete: missing {token}")

    owns_body = function_body(source, "_owns_material_metadata")
    if not owns_body or "get_meta(MATERIAL_OWNER_META" not in owns_body or "MATERIAL_OWNER_VALUE" not in owns_body:
        fail("owned material metadata identity check missing")

    claim_body = function_body(source, "_claim_generated_material")
    if not claim_body:
        fail("generated sidewalk material claim helper missing")
    for token in (
        "_has_foreign_material_owner(sidewalk)",
        "return false",
        "set_meta(MATERIAL_OWNER_META, MATERIAL_OWNER_VALUE)",
        "sidewalk.material = _material",
    ):
        if token not in claim_body:
            fail(f"generated material claim is not fail-closed: missing {token}")

    official_claim_body = function_body(source, "_claim_official_material")
    if not official_claim_body:
        fail("official sidewalk material claim helper missing")
    for token in (
        "_has_foreign_material_owner(instance)",
        "return false",
        "set_meta(MATERIAL_OWNER_META, MATERIAL_OWNER_VALUE)",
        "instance.material_override = _official_material",
    ):
        if token not in official_claim_body:
            fail(f"official material claim is not fail-closed: missing {token}")

    state_body = function_body(source, "_set_material_state")
    if "_claim_generated_material(sidewalk)" not in state_body:
        fail("enhanced re-enable bypasses generated sidewalk owner claim")
    if "_claim_official_material(instance)" not in state_body:
        fail("enhanced re-enable bypasses official sidewalk owner claim")
    if state_body.count("_owns_material_metadata(") < 2:
        fail("disable path can restore material without proving current ownership")

    release_body = function_body(source, "_release_material_ownership")
    if release_body.count("_owns_material_metadata(") < 2:
        fail("teardown can restore material without proving current ownership")
    if release_body.count("remove_meta(MATERIAL_OWNER_META)") < 2:
        fail("teardown does not release generated and official owner metadata")

    ready_body = function_body(source, "_ready")
    if "get_tree().node_removed.is_connected(_on_node_removed)" not in ready_body or "get_tree().node_removed.connect(_on_node_removed)" not in ready_body:
        fail("sidewalk runtime does not subscribe to individual node removal")

    exit_body = function_body(source, "_exit_tree")
    if "tree.node_removed.is_connected(_on_node_removed)" not in exit_body or "tree.node_removed.disconnect(_on_node_removed)" not in exit_body:
        fail("sidewalk runtime does not disconnect node removal watcher on teardown")

    removed_body = function_body(source, "_on_node_removed")
    if not removed_body:
        fail("individual sidewalk node removal cleanup helper missing")
    for token in (
        "_sidewalks.erase(node)",
        "_legacy_materials.erase(instance_id)",
        "_owned_materials.erase(instance_id)",
        "_original_transforms.erase(instance_id)",
        "_original_sizes.erase(instance_id)",
        "_official_sidewalks.erase(instance_id)",
        "_official_legacy_materials.erase(instance_id)",
        "_official_owned_materials.erase(instance_id)",
    ):
        if token not in removed_body:
            fail(f"individual sidewalk removal leaves stale lifecycle state: missing {token}")

    print("BRUSSELS_OSM_SIDEWALK_MATERIAL_OWNERSHIP_OK: foreign_owner_preserved=true reenable_owner_aware=true teardown_owner_aware=true node_removal_cleanup=true")


if __name__ == "__main__":
    main()

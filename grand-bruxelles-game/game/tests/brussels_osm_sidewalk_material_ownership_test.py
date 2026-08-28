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

    claim_body = function_body(source, "_claim_generated_material")
    if not claim_body:
        fail("generated sidewalk material claim helper missing")
    required_claim_tokens = (
        "has_meta(MATERIAL_OWNER_META)",
        "get_meta(MATERIAL_OWNER_META",
        "MATERIAL_OWNER_VALUE",
        "set_meta(MATERIAL_OWNER_META, MATERIAL_OWNER_VALUE)",
        "sidewalk.material = _material",
    )
    for token in required_claim_tokens:
        if token not in claim_body:
            fail(f"generated material claim is not fail-closed: missing {token}")
    if "return false" not in claim_body:
        fail("generated material claim cannot reject a foreign owner")

    official_claim_body = function_body(source, "_claim_official_material")
    if not official_claim_body:
        fail("official sidewalk material claim helper missing")
    for token in required_claim_tokens[:-1]:
        if token not in official_claim_body:
            fail(f"official material claim is not fail-closed: missing {token}")
    if "instance.material_override = _official_material" not in official_claim_body:
        fail("official material claim does not install the owned material")
    if "return false" not in official_claim_body:
        fail("official material claim cannot reject a foreign owner")

    state_body = function_body(source, "_set_material_state")
    if "_claim_generated_material(sidewalk)" not in state_body:
        fail("enhanced re-enable bypasses generated sidewalk owner claim")
    if "_claim_official_material(instance)" not in state_body:
        fail("enhanced re-enable bypasses official sidewalk owner claim")

    release_body = function_body(source, "_release_material_ownership")
    if "remove_meta(MATERIAL_OWNER_META)" not in release_body:
        fail("teardown does not release shared sidewalk owner metadata")
    if "get_meta(MATERIAL_OWNER_META" not in release_body:
        fail("teardown does not verify owner identity before metadata cleanup")

    print("BRUSSELS_OSM_SIDEWALK_MATERIAL_OWNERSHIP_OK: foreign_owner_preserved=true reenable_owner_aware=true teardown_owner_aware=true")


if __name__ == "__main__":
    main()

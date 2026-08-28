from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROJECT_PATH = ROOT / "project.godot"
LIFECYCLE_PATH = ROOT / "data" / "qa" / "shared_environment_lifecycle_contract.json"
CLASSIFICATION_PATH = ROOT / "data" / "qa" / "shared_environment_autoload_classification.json"

AUTOLOAD_RE = re.compile(r'^\s*(?P<name>[A-Za-z0-9_]+)\s*=\s*"\*res://(?P<path>game/scripts/[^"\n]+\.gd)"\s*$', re.MULTILINE)
MARKERS = ("SurfaceRuntime","PavingRuntime","GranitePaving","FurnitureRuntime","SidewalkRuntime","BollardRuntime","StreetLampRuntime","TreeRuntime","FacadeArticulationRuntime","WindowRhythmRuntime","SchoolHero")

def fail(message: str) -> None:
    raise AssertionError(message)

def main() -> None:
    if not PROJECT_PATH.is_file() or not LIFECYCLE_PATH.is_file(): fail("project/lifecycle inputs missing")
    if not CLASSIFICATION_PATH.is_file(): fail("shared Environment autoload classification contract missing")
    project = PROJECT_PATH.read_text(encoding="utf-8")
    pairs = [(m.group("name"), m.group("path")) for m in AUTOLOAD_RE.finditer(project)]
    autoload_map = dict(pairs)
    discovered = {name for name, _ in pairs if any(marker in name for marker in MARKERS)}
    lifecycle = json.loads(LIFECYCLE_PATH.read_text(encoding="utf-8"))
    registered = {entry["autoload_name"]: entry["path"] for entry in lifecycle.get("runtimes", []) if isinstance(entry, dict)}
    contract = json.loads(CLASSIFICATION_PATH.read_text(encoding="utf-8"))
    if contract.get("schema") != "grand-bruxelles-shared-environment-autoload-classification-v1": fail("autoload classification schema mismatch")
    if contract.get("all_discovered_environment_autoloads_classified") is not True: fail("autoload classification completeness rail missing")
    if contract.get("nearest_owner_inference_authorized") is not False: fail("classification contract must not infer ownership")
    exclusions = contract.get("explicit_exclusions")
    if not isinstance(exclusions, list): fail("explicit exclusion list missing")
    excluded: dict[str, str] = {}
    allowed_exact_scopes = {"grand_place_exact", "bourse_exact", "anneessens_exact"}
    for entry in exclusions:
        if not isinstance(entry, dict): fail("malformed exclusion entry")
        name, path = entry.get("autoload_name"), entry.get("path")
        if not isinstance(name, str) or not isinstance(path, str): fail("invalid exclusion identity")
        if name in excluded: fail(f"duplicate excluded autoload: {name}")
        if autoload_map.get(name) != path: fail(f"excluded autoload identity drifted: {name}")
        if entry.get("reason") != "exact_location_owner_outside_shared_environment": fail(f"excluded autoload reason drifted: {name}")
        if entry.get("owner_scope") not in allowed_exact_scopes: fail(f"excluded autoload owner scope invalid: {name}")
        excluded[name] = path
    overlap = set(registered) & set(excluded)
    if overlap: fail(f"autoload cannot be both shared and exact-location excluded: {sorted(overlap)}")
    classified = set(registered) | set(excluded)
    unknown = sorted(discovered - classified)
    if unknown: fail(f"unclassified production Environment autoloads detected: {unknown}")
    stale = sorted(classified - discovered)
    if stale: fail(f"classified autoloads no longer match Environment discovery policy: {stale}")
    for name, path in registered.items():
        if autoload_map.get(name) != path: fail(f"registered shared Environment autoload drifted: {name}")
    if contract.get("classified_autoload_count") != len(classified): fail("classified autoload count metadata mismatch")
    if contract.get("shared_runtime_count") != len(registered): fail("shared runtime count metadata mismatch")
    if contract.get("explicit_exclusion_count") != len(excluded): fail("explicit exclusion count metadata mismatch")
    print(f"SHARED_ENVIRONMENT_AUTOLOAD_CLASSIFICATION_OK: discovered={len(discovered)} shared={len(registered)} excluded={len(excluded)} unknown=0")

if __name__ == "__main__": main()

#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
RUNTIME = PROJECT / "game/scripts/brussels_urbis_finish_runtime.gd"
MATERIAL = PROJECT / "game/scripts/brussels_urbis_finish_material.gd"
PROJECT_GODOT = PROJECT / "project.godot"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--zone", required=True)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    if args.zone != "jette":
        print(f"CITY_MACHINE_FAMILY FAIL finish_materials zone={args.zone} reason=pilot_locked_to_jette")
        return 2
    print("CITY_MACHINE_FAMILY START finish_materials zone=jette", flush=True)
    for path in (RUNTIME, MATERIAL, PROJECT_GODOT):
        if not path.exists():
            print(f"CITY_MACHINE_FAMILY FAIL finish_materials zone=jette reason=missing:{path.relative_to(PROJECT)}", flush=True)
            return 3
    runtime = RUNTIME.read_text(encoding="utf-8")
    material = MATERIAL.read_text(encoding="utf-8")
    project = PROJECT_GODOT.read_text(encoding="utf-8")
    required = [
        (runtime, "JetteOfficialStreetSurfaces"),
        (runtime, "JetteOfficialBuildings"),
        (runtime, "BrusselsUrbisFinishMaterial"),
        (material, "brussels_urbis_finish_v1"),
        (material, "geometry_source"),
        (project, 'BrusselsUrbisFinishRuntime="*res://game/scripts/brussels_urbis_finish_runtime.gd"'),
    ]
    for text, token in required:
        if token not in text:
            print(f"CITY_MACHINE_FAMILY FAIL finish_materials zone=jette reason=missing_contract:{token}", flush=True)
            return 4
    if "material_identity_claimed\", true" in runtime or "material_identity_claimed\", true" in material:
        print("CITY_MACHINE_FAMILY FAIL finish_materials zone=jette reason=material_identity_overclaim", flush=True)
        return 5
    print("CITY_MACHINE_FAMILY END finish_materials zone=jette status=wired runtime=brussels_urbis_finish_v1 geometry_changed=false", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

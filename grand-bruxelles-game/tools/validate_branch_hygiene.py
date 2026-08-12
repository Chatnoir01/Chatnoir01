from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Result:
    errors: tuple[str, ...]
    warnings: tuple[str, ...]

    @property
    def ok(self) -> bool:
        return not self.errors


def classify(branch: str) -> str:
    if branch.startswith("zone-"):
        return "geographic"
    if branch in {"vehicles-traffic", "systems-vehicles-traffic"} or branch.startswith("systems-vehicles-"):
        return "vehicles"
    if branch.startswith("systems-npc-") or branch.startswith("systems-police-"):
        return "npc_police"
    if branch.startswith("integration/"):
        return "integration"
    return "other"


def check(head: str, base: str, changed: list[str], ahead: int = 0, behind: int = 0) -> Result:
    errors: list[str] = []
    warnings: list[str] = []
    kind = classify(head)

    if kind in {"geographic", "vehicles", "npc_police", "integration"} and base != "main":
        errors.append(
            f"{kind} branch {head!r} must target main, not {base!r}; "
            "cross-workstream stacking is forbidden"
        )

    shared = {
        "grand-bruxelles-game/game/main.tscn",
        "grand-bruxelles-game/project.godot",
    }
    if kind in {"geographic", "vehicles", "npc_police"}:
        for path in changed:
            if path in shared:
                errors.append(f"{kind} branch owns shared integration file: {path}")

    patterns: dict[str, tuple[str, ...]] = {
        "geographic": (
            r"^grand-bruxelles-game/game/(police|scripts/(police_|wanted_system\.gd|npc_|traffic_))",
            r"^grand-bruxelles-game/data/traffic/",
        ),
        "vehicles": (
            r"^grand-bruxelles-game/game/zones/",
            r"^grand-bruxelles-game/data/urbis/(laeken_jette|remaining_brussels)/",
            r"^grand-bruxelles-game/game/(police|scripts/(police_|wanted_system\.gd|npc_))",
        ),
        "npc_police": (
            r"^grand-bruxelles-game/game/zones/",
            r"^grand-bruxelles-game/data/urbis/(laeken_jette|remaining_brussels)/",
            r"^grand-bruxelles-game/game/scripts/traffic_",
            r"^grand-bruxelles-game/data/traffic/",
        ),
    }
    for path in changed:
        for pattern in patterns.get(kind, ()):
            if re.search(pattern, path):
                errors.append(f"{kind} branch contains cross-workstream path: {path}")
                break

    if kind != "integration" and ahead > 50:
        errors.append(
            f"{head} is {ahead} commits ahead of {base}; extract a coherent lot onto current main "
            "instead of wholesale merge"
        )
    if kind != "integration" and behind > 15:
        errors.append(f"{head} is {behind} commits behind {base}; refresh/extract before integration")
    if kind == "integration" and (ahead > 30 or behind > 5):
        warnings.append(
            f"integration branch drift is high ({ahead} ahead/{behind} behind); keep integration lots short-lived"
        )

    return Result(tuple(dict.fromkeys(errors)), tuple(dict.fromkeys(warnings)))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Grand Bruxelles branch ownership hard gate")
    parser.add_argument("--head", required=True)
    parser.add_argument("--base", required=True)
    parser.add_argument("--changed-file-list", type=Path, required=True)
    parser.add_argument("--ahead", type=int, default=0)
    parser.add_argument("--behind", type=int, default=0)
    args = parser.parse_args(argv)

    changed = [
        line.strip()
        for line in args.changed_file_list.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    result = check(args.head, args.base, changed, args.ahead, args.behind)
    for warning in result.warnings:
        print(f"WARNING: {warning}")
    for error in result.errors:
        print(f"ERROR: {error}")
    return 0 if result.ok else 1


if __name__ == "__main__":
    raise SystemExit(main())

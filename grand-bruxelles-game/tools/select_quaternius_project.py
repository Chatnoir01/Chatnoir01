#!/usr/bin/env python3
from __future__ import annotations
import argparse
from pathlib import Path

SOURCE_BASENAME = 'UAL1_Standard.glb'
SCENE_BASENAME = 'Master_Rigged.tscn'


def _nearest_project(path: Path, root: Path) -> Path | None:
    current = path.parent
    while current == root or root in current.parents:
        if (current / 'project.godot').is_file():
            return current.resolve()
        if current == root:
            break
        current = current.parent
    return None


def _owned(root: Path, basename: str) -> dict[Path, list[Path]]:
    owners: dict[Path, list[Path]] = {}
    for p in sorted(root.rglob(basename)):
        owner = _nearest_project(p.resolve(), root)
        if owner is not None:
            owners.setdefault(owner, []).append(p.resolve())
    return owners


def select_project_root(archive_root: Path) -> Path:
    root = archive_root.resolve()
    if not root.is_dir():
        raise ValueError('archive root missing')
    source_owners = _owned(root, SOURCE_BASENAME)
    scene_owners = _owned(root, SCENE_BASENAME)
    candidates = sorted(set(source_owners) & set(scene_owners))
    if len(candidates) != 1:
        raise ValueError(f'expected exactly one project owning both pinned source and scene, found {len(candidates)}')
    project_root = candidates[0]
    if len(source_owners[project_root]) != 1:
        raise ValueError('selected project must own exactly one UAL1_Standard.glb')
    if len(scene_owners[project_root]) != 1:
        raise ValueError('selected project must own exactly one Master_Rigged.tscn')
    return project_root


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('archive_root')
    args = ap.parse_args()
    print(select_project_root(Path(args.archive_root)))


if __name__ == '__main__':
    main()

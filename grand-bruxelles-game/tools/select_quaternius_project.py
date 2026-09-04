#!/usr/bin/env python3
from __future__ import annotations
import argparse
import os
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


def _exactly_one(root: Path, basename: str) -> Path:
    matches = [p.resolve() for p in sorted(root.rglob(basename))]
    if len(matches) != 1:
        raise ValueError(f'expected exactly one {basename}, found {len(matches)}')
    return matches[0]


def _common_asset_root(source: Path, scene: Path, root: Path) -> Path:
    common = Path(os.path.commonpath([source.parent, scene.parent])).resolve()
    if common != root and root not in common.parents:
        raise ValueError('asset common root escapes archive root')
    if common == root:
        raise ValueError('source and scene only share archive root; refusing broad ephemeral project')
    return common


def select_project_root(archive_root: Path) -> Path:
    root = archive_root.resolve()
    if not root.is_dir():
        raise ValueError('archive root missing')

    source = _exactly_one(root, SOURCE_BASENAME)
    scene = _exactly_one(root, SCENE_BASENAME)
    source_owner = _nearest_project(source, root)
    scene_owner = _nearest_project(scene, root)

    if source_owner is not None or scene_owner is not None:
        if source_owner is None or scene_owner is None or source_owner != scene_owner:
            raise ValueError('pinned source and scene do not share one existing Godot project owner')
        return source_owner

    # The pinned Quaternius archive is an addon snapshot and intentionally has
    # no project.godot. Use the narrowest common asset directory as an
    # ephemeral diagnostic project root; the workflow creates project.godot
    # there only in /tmp, never in canonical repository/runtime content.
    return _common_asset_root(source, scene, root)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('archive_root')
    args = ap.parse_args()
    print(select_project_root(Path(args.archive_root)))


if __name__ == '__main__':
    main()

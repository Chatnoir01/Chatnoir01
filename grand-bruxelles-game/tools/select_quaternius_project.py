#!/usr/bin/env python3
from __future__ import annotations
import argparse
from pathlib import Path

SCENE_SUFFIX = Path('Models_with_rigging/Master_Rigged.tscn')


def _scene_matches(root: Path) -> list[Path]:
    return sorted(p.resolve() for p in root.rglob('Master_Rigged.tscn') if tuple(p.parts[-len(SCENE_SUFFIX.parts):]) == SCENE_SUFFIX.parts)


def select_project_root(archive_root: Path) -> Path:
    root = archive_root.resolve()
    if not root.is_dir():
        raise ValueError('archive root missing')
    scenes = _scene_matches(root)
    if len(scenes) != 1:
        raise ValueError(f'expected exactly one pinned Master_Rigged scene, found {len(scenes)}')
    scene = scenes[0]
    current = scene.parent
    candidates: list[Path] = []
    while current == root or root in current.parents:
        if (current / 'project.godot').is_file():
            candidates.append(current)
        if current == root:
            break
        current = current.parent
    if not candidates:
        raise ValueError('Master_Rigged scene has no ancestor project.godot')
    project_root = candidates[0]
    scoped = _scene_matches(project_root)
    if scoped != [scene]:
        raise ValueError('selected project does not uniquely own pinned Master_Rigged scene')
    return project_root


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('archive_root')
    args = ap.parse_args()
    print(select_project_root(Path(args.archive_root)))


if __name__ == '__main__':
    main()

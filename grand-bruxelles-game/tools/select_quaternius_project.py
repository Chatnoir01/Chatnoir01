#!/usr/bin/env python3
from __future__ import annotations
import argparse, os
from pathlib import Path
SOURCE_BASENAME='UAL1_Standard.glb'; SCENE_BASENAME='Master_Rigged.tscn'
def _nearest_project(path,root):
    cur=path.parent
    while cur==root or root in cur.parents:
        if (cur/'project.godot').is_file(): return cur.resolve()
        if cur==root: break
        cur=cur.parent
    return None
def _one(root,name):
    m=[p.resolve() for p in sorted(root.rglob(name))]
    if len(m)!=1: raise ValueError(f'expected exactly one {name}, found {len(m)}')
    return m[0]
def select_project_root(archive_root:Path)->Path:
    root=archive_root.resolve()
    if not root.is_dir(): raise ValueError('archive root missing')
    source=_one(root,SOURCE_BASENAME); scene=_one(root,SCENE_BASENAME)
    so=_nearest_project(source,root); co=_nearest_project(scene,root)
    if so is not None or co is not None:
        if so is None or co is None or so!=co: raise ValueError('pinned source and scene do not share one existing Godot project owner')
        return so
    common=Path(os.path.commonpath([source.parent,scene.parent])).resolve()
    if common==root: raise ValueError('source and scene only share archive root; refusing broad ephemeral project')
    if root not in common.parents: raise ValueError('asset common root escapes archive root')
    return common
def main():
    ap=argparse.ArgumentParser(); ap.add_argument('archive_root'); a=ap.parse_args(); print(select_project_root(Path(a.archive_root)))
if __name__=='__main__': main()

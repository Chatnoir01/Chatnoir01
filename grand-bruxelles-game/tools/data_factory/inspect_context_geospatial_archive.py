#!/usr/bin/env python3
"""Safely inventory geospatial archive contents used as visual/environment context.

This stage validates archive structure and provenance only. It does not interpret raster values,
reproject coordinates, mutate geometry, or grant runtime/production authorization.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import stat
import zipfile
from pathlib import Path, PurePosixPath
from typing import Any

FORMAT = "grand-bruxelles-context-geospatial-archive-inventory-v1"
GEOSPATIAL_SUFFIXES = {".tif", ".tiff", ".shp", ".dbf", ".shx", ".prj", ".gpkg", ".geojson", ".gml", ".vrt", ".tfw", ".asc"}


def sha256_file(path: Path) -> str:
    h=hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda:f.read(1024*1024),b""):
            h.update(chunk)
    return h.hexdigest()


def safe_member(info: zipfile.ZipInfo) -> PurePosixPath:
    path=PurePosixPath(info.filename)
    if path.is_absolute() or ".." in path.parts:
        raise SystemExit(f"context archive gate failed: unsafe member {info.filename}")
    if info.flag_bits & 0x1:
        raise SystemExit(f"context archive gate failed: encrypted member {info.filename}")
    mode=(info.external_attr>>16)&0xFFFF
    if mode and stat.S_ISLNK(mode):
        raise SystemExit(f"context archive gate failed: symlink member {info.filename}")
    return path


def inspect(path: Path) -> dict[str,Any]:
    if not zipfile.is_zipfile(path):
        raise SystemExit(f"context archive gate failed: not ZIP {path}")
    members=[]; geo=[]; total=0
    with zipfile.ZipFile(path) as zf:
        for info in zf.infolist():
            member=safe_member(info)
            if info.is_dir():
                continue
            total+=int(info.file_size)
            row={"path":info.filename,"bytes":int(info.file_size),"suffix":member.suffix.lower()}
            members.append(row)
            if member.suffix.lower() in GEOSPATIAL_SUFFIXES:
                geo.append(row)
    if not geo:
        raise SystemExit(f"context archive gate failed: no recognized geospatial members in {path}")
    return {
        "file":path.name,
        "sha256":sha256_file(path),
        "archive_bytes":path.stat().st_size,
        "uncompressed_bytes":total,
        "member_count":len(members),
        "geospatial_member_count":len(geo),
        "geospatial_members":geo,
        "members_digest":hashlib.sha256("\n".join(sorted(row["path"] for row in members)).encode("utf-8")).hexdigest(),
    }


def main() -> int:
    parser=argparse.ArgumentParser()
    parser.add_argument("--archive",type=Path,action="append",required=True)
    parser.add_argument("--output",type=Path,required=True)
    parser.add_argument("--publisher",required=True)
    parser.add_argument("--license",required=True)
    parser.add_argument("--semantic-role",required=True)
    args=parser.parse_args()

    archives=[inspect(path) for path in args.archive]
    output={
        "format":FORMAT,
        "source":{"publisher":args.publisher,"license":args.license,"semantic_role":args.semantic_role},
        "stats":{"archive_count":len(archives),"geospatial_member_count":sum(a["geospatial_member_count"] for a in archives)},
        "archives":archives,
        "runtime_authorized":False,
        "production_authorized":False,
        "semantic_rules":[
            "Archive inventory is evidence only and does not validate raster/vector values.",
            "No coordinate reprojection or geometry mutation occurs in this stage.",
            "Context layers cannot override exact UrbIS/building-specific geometry.",
            "Temporal indicators must not be relabeled as current conditions unless their source explicitly says so."
        ]
    }
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(output,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(f"CONTEXT_GEOSPATIAL_ARCHIVE_OK: {len(archives)} archives -> {args.output}")
    return 0


if __name__=="__main__":
    raise SystemExit(main())

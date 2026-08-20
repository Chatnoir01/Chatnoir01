#!/usr/bin/env python3
"""Lock C01 30k final world-Y datum from the existing Lambert72 world anchor.

world_y = source_z + owner_rigid_shift_m - anchor_dtm_elevation_m

The datum is sampled from the official UrbIS DTM at the exact Lambert72 origin
already used by the production X/Z transform. This tool is artifact-only: it
never mounts geometry, terrain or collisions.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import shutil
import zipfile
from pathlib import Path


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def quantile(values: list[float], q: float) -> float:
    xs = sorted(values)
    if not xs:
        raise RuntimeError("empty quantile input")
    if len(xs) == 1:
        return xs[0]
    pos = (len(xs) - 1) * q
    lo, hi = int(math.floor(pos)), int(math.ceil(pos))
    if lo == hi:
        return xs[lo]
    t = pos - lo
    return xs[lo] * (1.0 - t) + xs[hi] * t


def validate_contract(c: dict) -> None:
    if c.get("schema") != "grand-bruxelles-region-lod2-c01-world-y-datum-lock-v1":
        raise RuntimeError("unexpected schema")
    if c.get("campaign_id") != "region-lod2-C01-30000":
        raise RuntimeError("unexpected campaign")
    if int(c.get("expected", {}).get("owners", -1)) != 30000:
        raise RuntimeError("world-Y lock must cover exactly 30,000 owners")
    if int(c.get("expected", {}).get("dtm_tile", -1)) != 147169:
        raise RuntimeError("datum must use the locked 147169 DTM tile")

    anchor = c.get("world_anchor", {})
    if anchor.get("crs") != "EPSG:31370":
        raise RuntimeError("world anchor CRS must remain EPSG:31370")
    if [float(x) for x in anchor.get("lambert72_origin", [])] != [147868.29422791934, 169538.62414926197]:
        raise RuntimeError("Lambert72 origin drifted from production X/Z transform")
    if [float(x) for x in anchor.get("world_origin", [])] != [-668.5, 0.0, 627.84]:
        raise RuntimeError("game world origin drifted from production X/Z transform")
    if anchor.get("datum_rule") != "official_dtm_ground_at_exact_lambert72_origin_maps_to_world_y_0":
        raise RuntimeError("vertical datum rule drifted")

    formula = c.get("formula", {})
    if formula.get("world_y") != "source_z + owner_rigid_shift_m - anchor_dtm_elevation_m":
        raise RuntimeError("world-Y formula drifted")
    if formula.get("owner_translation") != "owner_rigid_shift_m - anchor_dtm_elevation_m":
        raise RuntimeError("owner translation formula drifted")

    dtm = c.get("dtm_tile_lock", {})
    if dtm.get("archive_sha256") != "b2bb34689ff35f080cb060fb8091e5d347342615575a24eedad89fe70467f803":
        raise RuntimeError("DTM archive hash drifted")
    if dtm.get("raster_sha256") != "f7312e66081eb8f99f35793a55cf346364f76c7b0b6c915b6d25b057caf189a6":
        raise RuntimeError("DTM raster hash drifted")
    if float(dtm.get("resolution_m", 0.0)) != 0.5:
        raise RuntimeError("DTM resolution drifted")

    rigid = c.get("rigid_anchor_lock", {})
    if int(rigid.get("artifact_id", 0)) != 9387662517:
        raise RuntimeError("rigid-anchor artifact drifted")
    if rigid.get("archive_sha256") != "05e4dcb02385a3e50ee492b87a83191e65ae65fe60694157903eea944cd1adc1":
        raise RuntimeError("rigid-anchor archive hash drifted")
    locked = {
        "dtm_rigid_anchor_locked.json": "89bb084a67f737bc508c4e4050e79f8b747c4e720698eee11b622948d1e5e725",
        "dtm_tile_locks.json": "1d4eb721f5c5f1d5d296da540e93d1ed760581596137f4ecfbd15b835a6af785",
        "rigid_anchor_selected_by_owner.json": "29b347fde2022282c19db4c2a8b7959218544baf9ce37cc7f4be7d289421bfb4",
        "rigid_anchor_selected_per_owner.csv": "0670e072eea4739e73531c0d5c0f7e3493d7a80df07c38f5af56560f8609bc7e",
    }
    if rigid.get("files_sha256") != locked:
        raise RuntimeError("rigid-anchor locked output hashes drifted")

    rules = c.get("hard_rules", {})
    for key in ["runtime_authorized", "runtime_mount_authorized", "collision_authorized", "terrain_runtime_authorized", "source_geometry_modified", "jouable_promotion_authorized"]:
        if rules.get(key) is not False:
            raise RuntimeError(f"{key} must remain false")
    if rules.get("owner_rigid_translation_only") is not True or rules.get("artifact_only") is not True:
        raise RuntimeError("rigid-only artifact rules must remain true")

    expected_datum = c.get("expected", {}).get("anchor_dtm_elevation_m")
    final_y = rules.get("final_world_y_authorized")
    if expected_datum is None:
        if final_y is not False:
            raise RuntimeError("unmeasured datum cannot authorize final world Y")
    else:
        value = float(expected_datum)
        if not math.isfinite(value) or not (0.0 < value < 200.0):
            raise RuntimeError("invalid expected anchor DTM elevation")
        if final_y is not True:
            raise RuntimeError("locked expected datum must authorize artifact final world Y")


def extract_single_tiff(archive: Path, out_dir: Path) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    found: list[Path] = []
    with zipfile.ZipFile(archive) as zf:
        for info in zf.infolist():
            name = Path(info.filename)
            if info.is_dir():
                continue
            if name.is_absolute() or ".." in name.parts:
                raise RuntimeError("unsafe DTM archive member")
            target = out_dir / name
            target.parent.mkdir(parents=True, exist_ok=True)
            with zf.open(info) as src, target.open("wb") as dst:
                shutil.copyfileobj(src, dst)
            if target.suffix.lower() in {".tif", ".tiff"}:
                found.append(target)
    if len(found) != 1:
        raise RuntimeError(f"expected one TIFF, got {len(found)}")
    return found[0]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--contract", type=Path, required=True)
    ap.add_argument("--rigid-anchor-dir", type=Path)
    ap.add_argument("--dtm-archive", type=Path)
    ap.add_argument("--output-dir", type=Path)
    ap.add_argument("--validate-only", action="store_true")
    args = ap.parse_args()
    try:
        contract = json.loads(args.contract.read_text(encoding="utf-8"))
        validate_contract(contract)
        if args.validate_only:
            print("C01_WORLD_Y_DATUM_CONTRACT_OK")
            return 0
        if not args.rigid_anchor_dir or not args.dtm_archive or not args.output_dir:
            raise RuntimeError("rigid-anchor-dir, dtm-archive and output-dir are required")
        if sha256_file(args.dtm_archive) != contract["dtm_tile_lock"]["archive_sha256"]:
            raise RuntimeError("official DTM archive SHA-256 mismatch")

        for name, expected_sha in contract["rigid_anchor_lock"]["files_sha256"].items():
            path = args.rigid_anchor_dir / name
            if not path.is_file() or sha256_file(path) != expected_sha:
                raise RuntimeError(f"locked rigid-anchor file mismatch: {name}")
        owners = json.loads((args.rigid_anchor_dir / "rigid_anchor_selected_by_owner.json").read_text(encoding="utf-8"))
        if len(owners) != 30000:
            raise RuntimeError(f"expected 30000 owners, got {len(owners)}")

        import rasterio
        tif = extract_single_tiff(args.dtm_archive, args.output_dir / "dtm-extracted")
        if sha256_file(tif) != contract["dtm_tile_lock"]["raster_sha256"]:
            raise RuntimeError("official DTM raster SHA-256 mismatch")
        with rasterio.open(tif) as src:
            if abs(float(src.res[0]) - 0.5) > 1e-9 or abs(float(src.res[1]) - 0.5) > 1e-9:
                raise RuntimeError(f"unexpected DTM resolution {src.res}")
            e, n = [float(v) for v in contract["world_anchor"]["lambert72_origin"]]
            b = src.bounds
            if not (float(b.left) <= e < float(b.right) and float(b.bottom) < n <= float(b.top)):
                raise RuntimeError("production Lambert72 origin is outside locked DTM raster bounds")
            sample = next(src.sample([(e, n)], masked=True))[0]
            if hasattr(sample, "mask") and bool(sample.mask):
                raise RuntimeError("DTM datum sample is nodata")
            datum = float(sample)
            if src.nodata is not None and datum == float(src.nodata):
                raise RuntimeError("DTM datum sample equals nodata")
            if not math.isfinite(datum):
                raise RuntimeError("non-finite DTM datum sample")
            raster_meta = {"filename": tif.name, "bounds": [float(b.left), float(b.bottom), float(b.right), float(b.top)], "resolution": [float(src.res[0]), float(src.res[1])], "width": int(src.width), "height": int(src.height), "nodata": float(src.nodata) if src.nodata is not None else None}

        expected_datum = contract["expected"].get("anchor_dtm_elevation_m")
        if expected_datum is not None and abs(datum - float(expected_datum)) > 5e-10:
            raise RuntimeError(f"anchor DTM elevation drifted: measured={datum:.9f} expected={float(expected_datum):.9f}")

        offsets: dict[str, dict[str, float | int]] = {}
        values: list[float] = []
        for owner_id in sorted(owners, key=lambda x: int(x)):
            row = owners[owner_id]
            shift = float(row["rigid_shift_m"])
            offset = shift - datum
            offsets[str(owner_id)] = {"sample_count": int(row["sample_count"]), "rigid_shift_m": shift, "world_y_offset_m": offset}
            values.append(offset)
        stats = {"min": min(values), "p05": quantile(values, 0.05), "median": quantile(values, 0.50), "p95": quantile(values, 0.95), "max": max(values)}
        rules = dict(contract["hard_rules"])
        report = {
            "schema": "grand-bruxelles-region-lod2-c01-world-y-datum-locked-v1" if expected_datum is not None else "grand-bruxelles-region-lod2-c01-world-y-datum-candidate-v1",
            "campaign_id": contract["campaign_id"], "production_base_sha": contract["production_base_sha"], "source_lock_merge_sha": contract["source_lock_merge_sha"], "owners": len(owners),
            "world_anchor": contract["world_anchor"],
            "dtm": {"dataset": contract["dtm"]["dataset"], "dataset_id": contract["dtm"]["dataset_id"], "tile": contract["expected"]["dtm_tile"], "archive_sha256": contract["dtm_tile_lock"]["archive_sha256"], "raster_sha256": contract["dtm_tile_lock"]["raster_sha256"], "anchor_absolute_elevation_m": datum, "raster": raster_meta},
            "formula": contract["formula"], "owner_world_y_offset_m": stats, **rules,
        }

        args.output_dir.mkdir(parents=True, exist_ok=True)
        report_path = args.output_dir / "world_y_datum_locked.json"
        owner_json = args.output_dir / "owner_world_y_offset_by_owner.json"
        owner_csv = args.output_dir / "owner_world_y_offset_per_owner.csv"
        report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        owner_json.write_text(json.dumps(offsets, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        with owner_csv.open("w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f); writer.writerow(["building_id", "sample_count", "rigid_shift_m", "world_y_offset_m"])
            for owner_id in sorted(offsets, key=lambda x: int(x)):
                row = offsets[owner_id]
                writer.writerow([owner_id, row["sample_count"], f"{float(row['rigid_shift_m']):.12f}", f"{float(row['world_y_offset_m']):.12f}"])
        hashes = {p.name: sha256_file(p) for p in [report_path, owner_json, owner_csv]}
        (args.output_dir / "result.sha256.json").write_text(json.dumps(hashes, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"C01_WORLD_Y_DATUM_OK: owners={len(owners)} datum={datum:.9f}m offset_median={stats['median']:.9f} final_world_y={rules['final_world_y_authorized']}")
        return 0
    except Exception as exc:
        print(f"C01_WORLD_Y_DATUM_ERROR: {exc}", flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

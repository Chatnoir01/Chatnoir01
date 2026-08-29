#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import zipfile
from pathlib import Path

PACK_METADATA_PATH = "packs/makehuman_system_assets.json"
GENERIC_GROUPS = ("skins", "hair", "clothes", "eyebrows", "eyelashes", "teeth")


def sha256_path(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_deterministic_zip(path: Path, entries: dict[str, bytes]) -> None:
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as archive:
        for name, payload in sorted(entries.items()):
            info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            archive.writestr(info, payload)


def build_subset(source: Path, selection_path: Path, output: Path, manifest_path: Path) -> dict:
    selection = json.loads(selection_path.read_text(encoding="utf-8"))
    expected_size = int(selection["source"]["size_bytes"])
    expected_sha256 = str(selection["source"]["sha256"])

    if source.stat().st_size != expected_size:
        raise ValueError(
            f"source size mismatch: expected {expected_size}, got {source.stat().st_size}"
        )
    actual_source_sha256 = sha256_path(source)
    if actual_source_sha256 != expected_sha256:
        raise ValueError(
            f"source sha256 mismatch: expected {expected_sha256}, got {actual_source_sha256}"
        )

    with zipfile.ZipFile(source, "r") as source_zip:
        bad_source_member = source_zip.testzip()
        if bad_source_member is not None:
            raise ValueError(f"source ZIP CRC failure: {bad_source_member}")

        source_names = set(source_zip.namelist())
        pack_metadata = json.loads(source_zip.read(PACK_METADATA_PATH))
        groups = selection["groups"]
        selected: list[tuple[str, str, str | None, list[str] | None]] = []

        for group in GENERIC_GROUPS:
            for asset_name in groups.get(group, []):
                selected.append((asset_name, group, f"{group}/{asset_name}/", None))

        for asset_name in groups.get("eyes", []):
            selected.append((asset_name, "eyes", f"eyes/{asset_name}/", None))

        for asset_name in groups.get("eyes_materials", []):
            selected.append(
                (
                    asset_name,
                    "eyes",
                    None,
                    [
                        f"eyes/materials/{asset_name}.mhmat",
                        f"eyes/materials/{asset_name}.thumb",
                        f"eyes/materials/{asset_name}_eye.png",
                    ],
                )
            )

        selected_names = [item[0] for item in selected]
        if len(selected_names) != len(set(selected_names)):
            raise ValueError("duplicate asset names in Gate-8 selection")

        output_entries: dict[str, bytes] = {}
        for asset_name, expected_type, prefix, explicit_files in selected:
            metadata = pack_metadata.get(asset_name)
            if not isinstance(metadata, dict):
                raise ValueError(f"pack metadata missing for {asset_name}")
            if str(metadata.get("license", "")).upper() != "CC0":
                raise ValueError(f"selected asset is not CC0: {asset_name}")
            if metadata.get("type") != expected_type:
                raise ValueError(
                    f"asset type mismatch for {asset_name}: "
                    f"expected {expected_type}, got {metadata.get('type')}"
                )

            if explicit_files is not None:
                candidates = explicit_files
            else:
                candidates = sorted(
                    name
                    for name in source_names
                    if prefix is not None and name.startswith(prefix) and not name.endswith("/")
                )
            if not candidates:
                raise ValueError(f"selected asset has no files: {asset_name}")

            for name in candidates:
                if name not in source_names:
                    raise ValueError(f"selected asset dependency is missing: {name}")
                output_entries[name] = source_zip.read(name)

        filtered_metadata = {name: pack_metadata[name] for name in selected_names}
        output_entries[PACK_METADATA_PATH] = (
            json.dumps(filtered_metadata, indent=2, sort_keys=True) + "\n"
        ).encode("utf-8")
        output_entries["grand_bruxelles_gate8_provenance.json"] = (
            json.dumps(
                {
                    "schema_version": 1,
                    "purpose": selection["purpose"],
                    "license": "CC0",
                    "source_sha256": actual_source_sha256,
                    "source_size_bytes": source.stat().st_size,
                    "selected_asset_count": len(selected_names),
                    "selected_assets": selected_names,
                },
                indent=2,
                sort_keys=True,
            )
            + "\n"
        ).encode("utf-8")

    output.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    write_deterministic_zip(output, output_entries)

    with zipfile.ZipFile(output, "r") as subset_zip:
        bad_subset_member = subset_zip.testzip()
        if bad_subset_member is not None:
            raise ValueError(f"subset ZIP CRC failure: {bad_subset_member}")
        if PACK_METADATA_PATH not in subset_zip.namelist():
            raise ValueError("subset is not an MPFB asset pack: pack metadata missing")

    subset_size = output.stat().st_size
    max_subset_bytes = int(selection.get("limits", {}).get("max_subset_bytes", 0))
    if max_subset_bytes and subset_size > max_subset_bytes:
        raise ValueError(
            f"Gate-8 subset exceeds size gate: {subset_size} > {max_subset_bytes}"
        )

    manifest = {
        "schema_version": 1,
        "source_sha256": actual_source_sha256,
        "subset_sha256": sha256_path(output),
        "subset_size_bytes": subset_size,
        "file_count": len(output_entries),
        "selected_asset_count": len(selected_names),
        "selected_assets": selected_names,
    }
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Build the bounded CC0 MakeHuman System Assets subset used by Grand Bruxelles Gate-8"
    )
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--selection", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()

    try:
        manifest = build_subset(args.source, args.selection, args.output, args.manifest)
        print(
            "MAKEHUMAN_GATE8_SUBSET_OK "
            f"bytes={manifest['subset_size_bytes']} "
            f"files={manifest['file_count']} "
            f"assets={manifest['selected_asset_count']} "
            f"sha256={manifest['subset_sha256']}"
        )
        return 0
    except (OSError, ValueError, KeyError, json.JSONDecodeError, zipfile.BadZipFile) as exc:
        print(f"MAKEHUMAN_GATE8_SUBSET_FAIL: {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

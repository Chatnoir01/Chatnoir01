#!/usr/bin/env python3
"""Normalize planning-permit exports into review-only recent-change signals.

The output never assigns a permit to a building automatically. Candidate addresses/dates are
extracted only to support human/exact-crosswalk review; all source fields remain preserved.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path
from typing import Any

FORMAT = "grand-bruxelles-planning-permit-signals-v1"


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def ci_get(props: dict[str, Any], *keys: str) -> Any:
    index = {str(k).lower().replace(" ", "_"): v for k, v in props.items()}
    for key in keys:
        value = index.get(key.lower().replace(" ", "_"))
        if value not in (None, ""):
            return value
    return None


def clean(value: Any) -> str | None:
    if value in (None, ""):
        return None
    text = str(value).strip()
    return text or None


def load_rows(path: Path) -> list[dict[str, Any]]:
    if path.suffix.lower() == ".csv":
        with path.open("r", encoding="utf-8-sig", newline="") as f:
            return [dict(row) for row in csv.DictReader(f)]
    value = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(value, list):
        return [row for row in value if isinstance(row, dict)]
    if isinstance(value, dict):
        if isinstance(value.get("results"), list):
            return [row for row in value["results"] if isinstance(row, dict)]
        if isinstance(value.get("records"), list):
            return [row for row in value["records"] if isinstance(row, dict)]
        if value.get("type") == "FeatureCollection" and isinstance(value.get("features"), list):
            out=[]
            for feature in value["features"]:
                if not isinstance(feature, dict):
                    continue
                props = feature.get("properties") if isinstance(feature.get("properties"), dict) else {}
                row=dict(props)
                if isinstance(feature.get("geometry"), dict):
                    row["_source_geometry"] = feature["geometry"]
                if feature.get("id") not in (None, ""):
                    row["_source_feature_id"] = feature.get("id")
                out.append(row)
            return out
    raise SystemExit(f"unsupported planning-permit export: {path}")


def signal(row: dict[str, Any], source_file: str, index: int) -> dict[str, Any]:
    permit_id = clean(ci_get(row, "id", "permit_id", "numero_dossier", "num_dossier", "dossier", "reference", "référence"))
    address = clean(ci_get(row, "adresse", "address", "adresse_du_bien", "localisation", "lieu"))
    street = clean(ci_get(row, "rue", "street", "nom_de_rue"))
    number = clean(ci_get(row, "numero", "numéro", "number", "house_number", "no"))
    postal = clean(ci_get(row, "code_postal", "postcode", "postal_code", "zip"))
    date = clean(ci_get(row, "date", "date_decision", "date_décision", "date_demande", "date_octroi", "date_delivrance", "date_délivrance"))
    object_text = clean(ci_get(row, "objet", "object", "description", "type_permis", "type_de_permis"))
    if address is None and street:
        address = " ".join(v for v in (street, number, postal) if v)
    return {
        "signal_id": permit_id or f"{source_file}:{index}",
        "source_file": source_file,
        "permit_id": permit_id,
        "candidate_address": address,
        "candidate_date": date,
        "candidate_object": object_text,
        "exact_building_crosswalk": False,
        "requires_review": True,
        "source_properties": row,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, action="append", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--license", default="CC0 1.0")
    parser.add_argument("--min-signals", type=int, default=1)
    args = parser.parse_args()

    signals=[]; source_files=[]
    for path in args.input:
        rows=load_rows(path)
        source_files.append({"file":path.name,"sha256":sha256_file(path),"row_count":len(rows)})
        signals.extend(signal(row,path.name,i) for i,row in enumerate(rows))
    if len(signals) < args.min_signals:
        raise SystemExit(f"planning-permit signal gate failed: {len(signals)} < {args.min_signals}")

    output={
        "format":FORMAT,
        "source":{"publisher":"City of Brussels / Urban Development","license":args.license,"files":source_files},
        "stats":{"signal_count":len(signals)},
        "signals":signals,
        "runtime_authorized":False,
        "production_authorized":False,
        "semantic_rules":[
            "A permit is a recent-change signal, not geometry truth.",
            "No permit is assigned to a building without an explicit exact crosswalk.",
            "Candidate address/date extraction is for review only; source properties remain authoritative."
        ]
    }
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(output,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(f"PLANNING_PERMIT_SIGNALS_OK: {len(signals)} signals -> {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

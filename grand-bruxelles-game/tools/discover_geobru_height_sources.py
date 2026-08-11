#!/usr/bin/env python3
"""Search the official Geobru CSW catalogue for DSM/MNS/LiDAR height sources."""

from __future__ import annotations

import json
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

CSW = "https://geobru.irisnet.be/geonetwork/srv/eng/csw"
OUTPUT = Path("data/sources/laeken_jette/geobru_height_source_discovery.json")
TERMS = ["DSM", "digital surface model", "surface model", "MNS", "LiDAR", "point cloud"]
USER_AGENT = "Grand-Bruxelles-Game/1.0 (official Geobru height-source discovery)"

NS = {
    "csw": "http://www.opengis.net/cat/csw/2.0.2",
    "dc": "http://purl.org/dc/elements/1.1/",
    "dct": "http://purl.org/dc/terms/",
    "ows": "http://www.opengis.net/ows",
}


def request_records(term: str) -> tuple[bytes, str]:
    constraint = f"AnyText LIKE '%{term.replace("'", "''")}%'"
    params = {
        "service": "CSW",
        "version": "2.0.2",
        "request": "GetRecords",
        "resultType": "results",
        "typeNames": "csw:Record",
        "elementSetName": "full",
        "outputSchema": "http://www.opengis.net/cat/csw/2.0.2",
        "constraintLanguage": "CQL_TEXT",
        "constraint_language_version": "1.1.0",
        "constraint": constraint,
        "maxRecords": "100",
    }
    url = CSW + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=60) as response:
        return response.read(), url


def texts(record: ET.Element, tag: str) -> list[str]:
    values: list[str] = []
    for node in record.findall(tag, NS):
        text = (node.text or "").strip()
        if text:
            values.append(text)
    return values


def parse_records(raw: bytes) -> list[dict]:
    root = ET.fromstring(raw)
    records: list[dict] = []
    for record in root.findall(".//csw:Record", NS):
        identifiers = texts(record, "dc:identifier")
        titles = texts(record, "dc:title")
        subjects = texts(record, "dc:subject")
        descriptions = texts(record, "dct:abstract") + texts(record, "dc:description")
        references = texts(record, "dct:references")
        formats = texts(record, "dc:format")
        types = texts(record, "dc:type")
        records.append({
            "identifiers": identifiers,
            "titles": titles,
            "subjects": subjects,
            "descriptions": descriptions,
            "references": references,
            "formats": formats,
            "types": types,
        })
    return records


def canonical_key(record: dict) -> str:
    if record["identifiers"]:
        return record["identifiers"][0]
    if record["titles"]:
        return record["titles"][0]
    return json.dumps(record, sort_keys=True)


def main() -> int:
    by_key: dict[str, dict] = {}
    queries = []
    for term in TERMS:
        try:
            raw, url = request_records(term)
            parsed = parse_records(raw)
            queries.append({"term": term, "url": url, "bytes": len(raw), "records": len(parsed)})
            for record in parsed:
                key = canonical_key(record)
                stored = by_key.setdefault(key, record | {"matched_terms": []})
                if term not in stored["matched_terms"]:
                    stored["matched_terms"].append(term)
        except Exception as exc:
            queries.append({"term": term, "error": repr(exc)})

    candidates = []
    for record in by_key.values():
        haystack = " ".join(
            record.get("titles", [])
            + record.get("subjects", [])
            + record.get("descriptions", [])
            + record.get("formats", [])
        ).lower()
        score = 0
        for token in ("digital surface", "dsm", "mns", "lidar", "point cloud", "nuage de points", "surface model"):
            if token in haystack:
                score += 1
        record["height_source_score"] = score
        if score > 0:
            candidates.append(record)
    candidates.sort(key=lambda item: (-item["height_source_score"], item.get("titles", [""])[0] if item.get("titles") else ""))

    output = {
        "schema": 1,
        "source": "Geobru official GeoNetwork CSW catalogue",
        "csw_endpoint": CSW,
        "fetched_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "queries": queries,
        "candidate_count": len(candidates),
        "candidates": candidates,
        "policy": "No height is consumed automatically. A candidate must explicitly document metric surface/LiDAR elevation, public access, CRS and redistribution/reuse conditions before entering the building-height pipeline.",
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(output, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("GEOBRU_HEIGHT_DISCOVERY_OK", {"unique_records": len(by_key), "candidates": len(candidates)})
    for candidate in candidates:
        print("HEIGHT_CANDIDATE", candidate["height_source_score"], candidate.get("titles"), candidate.get("formats"), candidate.get("references")[:5])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

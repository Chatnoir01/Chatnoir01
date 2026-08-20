#!/usr/bin/env python3
"""Extract XLSX sheet/cell evidence using only the Python standard library.

This preserves statistical tables for later review. It does not infer an individual building's
construction period from municipality/sector statistics and never authorizes runtime use.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path
from typing import Any

FORMAT = "grand-bruxelles-statistical-xlsx-evidence-v1"
NS_MAIN = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
NS_REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
NS_PKG_REL = "http://schemas.openxmlformats.org/package/2006/relationships"
CELL_RE = re.compile(r"^([A-Z]+)(\d+)$")


def sha256_file(path: Path) -> str:
    h=hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda:f.read(1024*1024),b""):
            h.update(chunk)
    return h.hexdigest()


def column_index(ref: str) -> int:
    match=CELL_RE.match(ref)
    if not match:
        return -1
    result=0
    for char in match.group(1):
        result=result*26+(ord(char)-64)
    return result-1


def shared_strings(zf: zipfile.ZipFile) -> list[str]:
    if "xl/sharedStrings.xml" not in zf.namelist():
        return []
    root=ET.fromstring(zf.read("xl/sharedStrings.xml"))
    values=[]
    for si in root.findall(f"{{{NS_MAIN}}}si"):
        parts=[node.text or "" for node in si.iter(f"{{{NS_MAIN}}}t")]
        values.append("".join(parts))
    return values


def workbook_sheets(zf: zipfile.ZipFile) -> list[tuple[str,str]]:
    wb=ET.fromstring(zf.read("xl/workbook.xml"))
    rels=ET.fromstring(zf.read("xl/_rels/workbook.xml.rels"))
    targets={rel.attrib.get("Id"):rel.attrib.get("Target") for rel in rels.findall(f"{{{NS_PKG_REL}}}Relationship")}
    out=[]
    for sheet in wb.findall(f".//{{{NS_MAIN}}}sheet"):
        name=sheet.attrib.get("name") or ""
        rid=sheet.attrib.get(f"{{{NS_REL}}}id")
        target=targets.get(rid)
        if not target:
            continue
        target=target.lstrip("/")
        if not target.startswith("xl/"):
            target="xl/"+target
        out.append((name,target))
    return out


def cell_text(cell: ET.Element, shared: list[str]) -> Any:
    ctype=cell.attrib.get("t")
    if ctype=="inlineStr":
        return "".join(node.text or "" for node in cell.iter(f"{{{NS_MAIN}}}t"))
    v=cell.find(f"{{{NS_MAIN}}}v")
    if v is None or v.text is None:
        return None
    raw=v.text
    if ctype=="s":
        try:
            return shared[int(raw)]
        except (ValueError,IndexError):
            return raw
    if ctype in ("str","e","b"):
        return raw
    try:
        number=float(raw)
        return int(number) if number.is_integer() else number
    except ValueError:
        return raw


def extract_sheet(zf: zipfile.ZipFile, name: str, target: str, shared: list[str], max_rows: int) -> dict[str,Any]:
    root=ET.fromstring(zf.read(target))
    rows=[]
    for row in root.findall(f".//{{{NS_MAIN}}}row"):
        row_number=int(row.attrib.get("r") or len(rows)+1)
        cells={}
        for cell in row.findall(f"{{{NS_MAIN}}}c"):
            ref=cell.attrib.get("r") or ""
            idx=column_index(ref)
            if idx<0:
                continue
            value=cell_text(cell,shared)
            if value not in (None,""):
                cells[str(idx)]={"ref":ref,"value":value}
        if cells:
            rows.append({"row":row_number,"cells":cells})
        if max_rows>0 and len(rows)>=max_rows:
            break
    return {"name":name,"source_path":target,"non_empty_row_count":len(rows),"rows":rows}


def main() -> int:
    parser=argparse.ArgumentParser()
    parser.add_argument("--xlsx",type=Path,action="append",required=True)
    parser.add_argument("--output",type=Path,required=True)
    parser.add_argument("--publisher",required=True)
    parser.add_argument("--license",required=True)
    parser.add_argument("--max-rows-per-sheet",type=int,default=5000)
    args=parser.parse_args()

    files=[]
    total_sheets=0
    for path in args.xlsx:
        if not zipfile.is_zipfile(path):
            raise SystemExit(f"XLSX gate failed: not a ZIP-based XLSX: {path}")
        with zipfile.ZipFile(path) as zf:
            if "xl/workbook.xml" not in zf.namelist():
                raise SystemExit(f"XLSX gate failed: workbook.xml missing: {path}")
            shared=shared_strings(zf)
            sheets=[]
            for name,target in workbook_sheets(zf):
                if target not in zf.namelist():
                    raise SystemExit(f"XLSX gate failed: missing sheet target {target}")
                sheets.append(extract_sheet(zf,name,target,shared,args.max_rows_per_sheet))
            total_sheets+=len(sheets)
            files.append({"file":path.name,"sha256":sha256_file(path),"sheet_count":len(sheets),"sheets":sheets})
    if total_sheets==0:
        raise SystemExit("XLSX gate failed: no sheets extracted")
    output={
        "format":FORMAT,
        "source":{"publisher":args.publisher,"license":args.license,"files":files},
        "stats":{"file_count":len(files),"sheet_count":total_sheets},
        "runtime_authorized":False,
        "production_authorized":False,
        "semantic_rules":[
            "Extracted cells preserve statistical evidence only.",
            "Municipality/sector statistics must not be assigned to an individual building as exact age.",
            "Exact building-specific evidence always outranks statistical priors."
        ]
    }
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(output,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(f"STATISTICAL_XLSX_EVIDENCE_OK: {len(files)} files, {total_sheets} sheets -> {args.output}")
    return 0


if __name__=="__main__":
    raise SystemExit(main())

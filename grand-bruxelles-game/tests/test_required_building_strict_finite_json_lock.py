#!/usr/bin/env python3
"""Regression lock: Bourse authority JSON must reject duplicate/non-finite numbers."""
from __future__ import annotations
import json, subprocess, sys, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; VALIDATOR=ROOT/"tools"/"validate_required_building_urbis_crosswalk_lock.py"; SOURCE=ROOT/"data"/"osm"/"vertical_slice_01.game.json"
def run(path): return subprocess.run([sys.executable,str(VALIDATOR),"--source",str(path)],cwd=ROOT,text=True,capture_output=True)
def require_fail(path,label):
 result=run(path)
 if result.returncode==0: raise SystemExit(f"{label}: validator unexpectedly accepted malformed authority JSON")
 if "BOURSE_URBIS_CROSSWALK_LOCK_FAIL" not in (result.stdout+result.stderr): raise SystemExit(f"{label}: missing fail-close marker")
def main():
 baseline=run(SOURCE)
 if baseline.returncode!=0: raise SystemExit(baseline.stdout+baseline.stderr)
 text=SOURCE.read_text(encoding="utf-8"); payload=json.loads(text)
 with tempfile.TemporaryDirectory() as tmp:
  tmp=Path(tmp)
  duplicate=tmp/"duplicate.json"; duplicate.write_text(text.replace('"corridor": {','"corridor": {},\n  "corridor": {',1),encoding="utf-8"); require_fail(duplicate,"duplicate key")
  for token in ("NaN","Infinity","-Infinity","1e309"):
   bad=tmp/(token.replace("-","neg_")+".json"); bad.write_text(json.dumps(payload,allow_nan=False).replace('"schema_version": 1',f'"schema_version": {token}',1),encoding="utf-8"); require_fail(bad,f"non-finite {token}")
 print("REQUIRED_BUILDING_STRICT_FINITE_JSON_LOCK_OK")
 return 0
if __name__=="__main__": raise SystemExit(main())

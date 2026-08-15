#!/usr/bin/env python3
import importlib.util,json,tempfile
from pathlib import Path
p=Path(__file__).with_name("city_compiler.py"); s=importlib.util.spec_from_file_location("cc",p); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
def cell(i): return {"cell_id":i,"crs":"EPSG:31370","bbox":[1,2,3,4],"maturity":{"gates":{n:True for n in m.REQUIRED_GATES}},"provenance":{"source_records_present":True,"primary":"UrbIS"},"geometry":{"authoritative_geometry_ready":True,"source_manifest":"official.json"},"heights":{"status":"validated"}}
with tempfile.TemporaryDirectory() as d:
 r=Path(d); a=cell("approved"); q=cell("rejected"); q["heights"]["status"]="invalidated"; q["maturity"]["gates"]["performance"]=False
 (r/"b.json").write_text(json.dumps(q)); (r/"a.json").write_text(json.dumps(a)); x=m.compile_cells(r); y=m.compile_cells(r)
 assert x==y; assert x["summary"]=={"processed":2,"approved":1,"quarantined":1}; assert [c["cell_id"] for c in x["cells"]]==["approved","rejected"]
 assert "height_evidence_not_accepted" in x["cells"][1]["reasons"] and "gate_performance_not_passed" in x["cells"][1]["reasons"]
 print("CITY_COMPILER_GUARDRAILS_OK processed=2 approved=1 quarantined=1 deterministic=true")

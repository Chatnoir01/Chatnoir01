#!/usr/bin/env python3
import importlib.util, json, subprocess, sys, tempfile
from pathlib import Path
p=Path(__file__).with_name('build_mapillary_catalog.py'); s=importlib.util.spec_from_file_location('m',p); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
r=m.normalize({'id':'42','captured_at':123,'computed_geometry':{'coordinates':[4.35,50.85]},'compass_angle':91.5,'thumb_2048_url':'https://example/img.jpg','sequence':{'id':'seq'}})
assert r['source']=='Mapillary' and r['source_id']=='42' and r['lat']==50.85 and r['lon']==4.35 and r['heading']==91.5 and r['sequence_id']=='seq' and r['usage_class']=='REFERENCE_ONLY'
with tempfile.TemporaryDirectory() as d:
 out=Path(d)/'blocked.json'; cp=subprocess.run([sys.executable,str(p),'--output',str(out)],capture_output=True,text=True)
 assert cp.returncode==3 and 'BLOCKED_EXTERNAL_KEY' in cp.stdout
 payload=json.loads(out.read_text()); assert payload['status']=='BLOCKED_EXTERNAL_KEY' and payload['images']==[]
print('MAPILLARY_CONNECTOR_GUARDRAILS_OK normalization=true external_key_fail_closed=true')

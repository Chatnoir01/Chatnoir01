#!/usr/bin/env python3
import importlib.util
from pathlib import Path
p=Path(__file__).with_name('build_kartaview_catalog.py'); s=importlib.util.spec_from_file_location('k',p); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
payload={'status':{'apiCode':600},'result':{'data':[{'id':7,'lat':'50.85','lng':'4.35','sequenceId':11,'heading':182,'fileUrlProc':'https://example/7.jpg'}]}}
rows=m.extract_rows(payload); assert len(rows)==1
r=m.normalize(rows[0]); assert r['source']=='KartaView' and r['source_id']=='7' and r['lat']==50.85 and r['lon']==4.35 and r['sequence_id']=='11' and r['heading']==182 and r['url'].endswith('7.jpg') and r['usage_class']=='REFERENCE_ONLY'
print('KARTAVIEW_CONNECTOR_GUARDRAILS_OK parse=true normalize=true reference_only=true')

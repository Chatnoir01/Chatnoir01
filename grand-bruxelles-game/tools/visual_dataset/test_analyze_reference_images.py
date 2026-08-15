#!/usr/bin/env python3
import importlib.util, tempfile
from pathlib import Path
from PIL import Image, ImageDraw
p=Path(__file__).with_name('analyze_reference_images.py'); s=importlib.util.spec_from_file_location('a',p); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
with tempfile.TemporaryDirectory() as d:
 root=Path(d); img=Image.new('RGB',(320,240),(180,160,140)); draw=ImageDraw.Draw(img)
 for x in (60,120,180,240): draw.rectangle((x,0,x+4,239),fill=(20,20,20))
 for y in (60,120,180): draw.rectangle((0,y,319,y+4),fill=(245,245,245))
 path=root/'grid.png'; img.save(path); r=m.analyze(path)
 assert r['quality_status']=='USABLE'
 assert r['vertical_edge_density']>0 and r['horizontal_edge_density']>0
 assert r['strong_vertical_bands'] and r['strong_horizontal_bands']
 assert abs(sum(c['fraction'] for c in r['palette'])-1.0)<0.02
 rows=m.process_catalog({'images':[{'source_id':'x','local_file':'grid.png'},{'source_id':'missing'}]},root)
 assert rows[0]['visual_analysis']['quality_status']=='USABLE'
 assert rows[1]['visual_analysis']['quality_status']=='NO_LOCAL_IMAGE'
 print('REFERENCE_IMAGE_ANALYSIS_GUARDRAILS_OK measurable_only=true grid_detected=true missing_fail_closed=true')

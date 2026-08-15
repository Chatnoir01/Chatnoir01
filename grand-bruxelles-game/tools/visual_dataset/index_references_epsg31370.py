#!/usr/bin/env python3
"""Project visual references to EPSG:31370 and assign existing cell manifests."""
from __future__ import annotations
import argparse, json
from pathlib import Path
from pyproj import Transformer

TRANSFORMER=Transformer.from_crs("EPSG:4326","EPSG:31370",always_xy=True)

def load_cells(root:Path):
    cells=[]
    for path in sorted(root.glob('*.json')):
        p=json.loads(path.read_text(encoding='utf-8')); bbox=p.get('bbox')
        if isinstance(bbox,list) and len(bbox)==4:
            cells.append({'cell_id':p.get('cell_id',path.stem),'bbox':[float(v) for v in bbox],'source':path.as_posix()})
    return cells

def locate(x,y,cells):
    hits=[c for c in cells if c['bbox'][0] <= x < c['bbox'][2] and c['bbox'][1] <= y < c['bbox'][3]]
    return sorted(c['cell_id'] for c in hits)

def index_records(records,cells):
    out=[]
    for row in records:
        item=dict(row); lat=row.get('lat'); lon=row.get('lon')
        if lat is None or lon is None:
            item.update({'easting_31370':None,'northing_31370':None,'cell_ids':[],'spatial_status':'MISSING_COORDINATES'})
        else:
            x,y=TRANSFORMER.transform(float(lon),float(lat)); ids=locate(x,y,cells)
            item.update({'easting_31370':round(x,3),'northing_31370':round(y,3),'cell_ids':ids,'spatial_status':'INDEXED' if ids else 'OUTSIDE_LOADED_CELLS'})
        out.append(item)
    return sorted(out,key=lambda r:str(r.get('canonical_id') or r.get('source_id') or r.get('pageid') or ''))

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--input',required=True); ap.add_argument('--cells',default='grand-bruxelles-game/data/cell_manifests'); ap.add_argument('--output',required=True); a=ap.parse_args()
    payload=json.loads(Path(a.input).read_text(encoding='utf-8')); records=payload.get('records') or payload.get('images') or []; cells=load_cells(Path(a.cells)); indexed=index_records(records,cells)
    out={'format':'grand-bruxelles-reference-spatial-index-v1','crs':'EPSG:31370','summary':{'records':len(indexed),'indexed':sum(x['spatial_status']=='INDEXED' for x in indexed),'outside_loaded_cells':sum(x['spatial_status']=='OUTSIDE_LOADED_CELLS' for x in indexed),'missing_coordinates':sum(x['spatial_status']=='MISSING_COORDINATES' for x in indexed),'loaded_cells':len(cells)},'records':indexed}
    Path(a.output).write_text(json.dumps(out,indent=2,sort_keys=True,ensure_ascii=False)+'\n',encoding='utf-8'); print('REFERENCE_SPATIAL_INDEX_OK',out['summary'])
if __name__=='__main__': main()

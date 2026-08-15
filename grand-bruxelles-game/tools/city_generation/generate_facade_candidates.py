#!/usr/bin/env python3
"""Generate deterministic facade candidate recipes from UrbIS + visual consensus.

This stage never mutates runtime. It carries official footprint identity and only
turns READY multi-view measurements into normalized facade articulation recipes.
Physical height and street-facing edge remain blocked unless separately proven.
"""
from __future__ import annotations
import argparse, hashlib, json, math
from pathlib import Path

MIN_VISUAL_CONFIDENCE=0.72
MAX_BANDS=12

def digest(value):
    return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()

def building_index(cell_root:Path):
    out={}
    for path in sorted(cell_root.glob('*/raw/buildings.geojson')):
        fc=json.loads(path.read_text(encoding='utf-8'))
        cell_id=path.parents[1].name
        for f in fc.get('features',[]):
            props=f.get('properties') or {}; bid=props.get('INSPIRE_ID')
            geom=f.get('geometry') or {}
            if not bid or geom.get('type')!='Polygon' or not geom.get('coordinates'): continue
            ring=geom['coordinates'][0]
            if len(ring)<4: continue
            footprint=[[round(float(p[0]),3),round(float(p[1]),3)] for p in ring]
            out[str(bid)]={'building_id':str(bid),'cell_id':cell_id,'area_m2':props.get('AREA'),'footprint_31370':footprint,'footprint_digest':digest(footprint)}
    return out

def edge_lengths(footprint):
    pts=footprint[:-1] if footprint and footprint[0]==footprint[-1] else footprint
    out=[]
    for i,a in enumerate(pts):
        b=pts[(i+1)%len(pts)]; out.append(round(math.hypot(b[0]-a[0],b[1]-a[1]),3))
    return out

def band_positions(consensus,key):
    return [float(x['position']) for x in (consensus.get(key) or []) if 0.03<float(x.get('position',0))<0.97][:MAX_BANDS]

def primary_color(consensus):
    palette=consensus.get('palette_consensus') or []
    if not palette: return None
    rgb=palette[0].get('rgb'); return [int(v) for v in rgb] if isinstance(rgb,list) and len(rgb)==3 else None

def recipe_for(consensus,geometry):
    reasons=[]
    if consensus.get('status')!='READY': reasons.append('visual_consensus_not_ready')
    if float(consensus.get('visual_confidence',0))<MIN_VISUAL_CONFIDENCE: reasons.append('visual_confidence_below_threshold')
    if geometry is None: reasons.append('urbis_building_geometry_missing')
    color=primary_color(consensus)
    if color is None: reasons.append('dominant_color_missing')
    vertical=band_positions(consensus,'vertical_band_consensus')
    horizontal=band_positions(consensus,'horizontal_band_consensus')
    # We intentionally do not assign a street-facing edge here.
    recipe={'building_id':consensus.get('building_id'),'state':'QUARANTINE' if reasons else 'CANDIDATE','reasons':reasons,'visual_confidence':consensus.get('visual_confidence',0),'evidence':{'view_count':consensus.get('view_count',0),'independent_source_count':consensus.get('independent_source_count',0),'reference_ids':consensus.get('reference_ids',[])},'style_recipe':{'base_color_rgb':color,'vertical_rhythm_normalized':vertical,'horizontal_rhythm_normalized':horizontal,'mean_luminance':(consensus.get('measured_consensus',{}).get('mean_luminance') or {}).get('value'),'edge_density':{'vertical':(consensus.get('measured_consensus',{}).get('vertical_edge_density') or {}).get('value'),'horizontal':(consensus.get('measured_consensus',{}).get('horizontal_edge_density') or {}).get('value')},'semantic_elements':[],'height_m':None,'street_facing_edge':None}}
    if geometry:
        recipe['geometry']={**geometry,'edge_lengths_m':edge_lengths(geometry['footprint_31370'])}
    recipe['recipe_digest']=digest({k:v for k,v in recipe.items() if k!='recipe_digest'})
    return recipe

def generate(consensus_payload,geometry_index):
    recipes=[recipe_for(c,geometry_index.get(str(c.get('building_id')))) for c in sorted(consensus_payload.get('buildings') or [],key=lambda x:str(x.get('building_id')))]
    return {'format':'grand-bruxelles-facade-candidate-recipes-v1','authority':{'geometry':'UrbIS raw EPSG:31370 building footprints','visual':'multi-view measured consensus'},'hard_blocks':['physical_height_requires_validated_source','street_facing_edge_requires_street_relation','semantic_windows_doors_require_proven_semantic_analysis'],'summary':{'buildings':len(recipes),'candidates':sum(r['state']=='CANDIDATE' for r in recipes),'quarantined':sum(r['state']=='QUARANTINE' for r in recipes)},'recipes':recipes}

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--consensus',required=True); ap.add_argument('--cell-root',default='grand-bruxelles-game/data/urbis/remaining_brussels/cells'); ap.add_argument('--output',required=True); a=ap.parse_args(); c=json.loads(Path(a.consensus).read_text(encoding='utf-8')); out=generate(c,building_index(Path(a.cell_root))); Path(a.output).write_text(json.dumps(out,indent=2,sort_keys=True,ensure_ascii=False)+'\n',encoding='utf-8'); print('FACADE_CANDIDATES_OK',out['summary'])
if __name__=='__main__': main()

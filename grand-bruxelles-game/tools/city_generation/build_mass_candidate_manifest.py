#!/usr/bin/env python3
"""Build a deterministic mass-generation candidate manifest over all known UrbIS buildings.

This stage is fail-closed and never mutates runtime. Every authoritative building
appears exactly once. Only buildings with a CANDIDATE facade recipe advance to
READY_FOR_QA; all others remain QUARANTINE with explicit reasons.
"""
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path

def digest(value):
    return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()

def load_buildings(cell_root:Path):
    out={}
    for path in sorted(cell_root.glob('*/raw/buildings.geojson')):
        fc=json.loads(path.read_text(encoding='utf-8')); cell_id=path.parents[1].name
        for feature in fc.get('features',[]):
            props=feature.get('properties') or {}; bid=props.get('INSPIRE_ID'); geom=feature.get('geometry') or {}
            if not bid or geom.get('type')!='Polygon' or not geom.get('coordinates'): continue
            ring=geom['coordinates'][0]
            if len(ring)<4: continue
            key=str(bid)
            if key in out: raise ValueError(f'duplicate INSPIRE_ID: {key}')
            out[key]={'building_id':key,'cell_id':cell_id,'area_m2':props.get('AREA'),'vertex_count':len(ring)}
    return out

def load_recipes(path:Path):
    payload=json.loads(path.read_text(encoding='utf-8'))
    if payload.get('format')!='grand-bruxelles-facade-candidate-recipes-v1': raise ValueError('unsupported facade recipe format')
    out={}
    for recipe in payload.get('recipes') or []:
        bid=str(recipe.get('building_id'))
        if bid in out: raise ValueError(f'duplicate recipe: {bid}')
        out[bid]=recipe
    return out

def build(buildings,recipes):
    rows=[]
    for bid in sorted(buildings):
        building=buildings[bid]; recipe=recipes.get(bid); reasons=[]
        if recipe is None: reasons.append('facade_recipe_missing')
        elif recipe.get('state')!='CANDIDATE': reasons.extend(recipe.get('reasons') or ['facade_recipe_not_candidate'])
        if recipe and not recipe.get('recipe_digest'): reasons.append('recipe_digest_missing')
        state='READY_FOR_QA' if not reasons else 'QUARANTINE'
        row={**building,'state':state,'reasons':sorted(set(reasons)),'recipe_digest':recipe.get('recipe_digest') if recipe else None}
        row['candidate_digest']=digest(row); rows.append(row)
    orphan=sorted(set(recipes)-set(buildings))
    summary={'authoritative_buildings':len(buildings),'ready_for_qa':sum(r['state']=='READY_FOR_QA' for r in rows),'quarantined':sum(r['state']=='QUARANTINE' for r in rows),'orphan_recipes':len(orphan),'total_vertices':sum(r['vertex_count'] for r in rows)}
    out={'format':'grand-bruxelles-mass-candidate-manifest-v1','authority':'UrbIS raw EPSG:31370 buildings','promotion':'candidate_only_no_runtime_mutation','summary':summary,'orphan_recipe_ids':orphan,'buildings':rows}
    out['manifest_digest']=digest(out); return out

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--cell-root',default='grand-bruxelles-game/data/urbis/remaining_brussels/cells'); ap.add_argument('--recipes',required=True); ap.add_argument('--output',required=True); a=ap.parse_args()
    out=build(load_buildings(Path(a.cell_root)),load_recipes(Path(a.recipes))); Path(a.output).write_text(json.dumps(out,indent=2,sort_keys=True,ensure_ascii=False)+'\n',encoding='utf-8'); print('MASS_CANDIDATE_MANIFEST_OK',out['summary'],out['manifest_digest']); return 2 if out['summary']['orphan_recipes'] else 0
if __name__=='__main__': raise SystemExit(main())

#!/usr/bin/env python3
"""Apply deterministic, evidence-preserving correction rules to facade candidates.

This stage never mutates UrbIS geometry and never invents semantic windows/doors,
physical height, or street-facing orientation. It normalizes noisy measured
rhythms/colors into reproducible recipes and quarantines physically dubious output.
"""
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path

MIN_GAP=0.055
MAX_BANDS=10
MIN_EDGE_M=1.2
MAX_EDGE_M=180.0


def digest(value):
    raw=json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()
    return hashlib.sha256(raw).hexdigest()


def normalize_bands(values):
    clean=sorted({round(float(v),4) for v in values if 0.04 <= float(v) <= 0.96})
    out=[]
    for v in clean:
        if not out or v-out[-1] >= MIN_GAP:
            out.append(v)
    return out[:MAX_BANDS]


def clamp_rgb(rgb):
    if not isinstance(rgb,list) or len(rgb)!=3: return None
    return [max(0,min(255,int(round(float(v))))) for v in rgb]


def correct(recipe):
    out=json.loads(json.dumps(recipe))
    reasons=list(out.get('reasons') or [])
    changes=[]
    style=out.setdefault('style_recipe',{})
    for key in ('vertical_rhythm_normalized','horizontal_rhythm_normalized'):
        before=list(style.get(key) or [])
        after=normalize_bands(before)
        if after!=before:
            style[key]=after; changes.append(key+'_normalized')
    before_color=style.get('base_color_rgb')
    after_color=clamp_rgb(before_color)
    if after_color!=before_color:
        style['base_color_rgb']=after_color; changes.append('base_color_rgb_clamped')
    geometry=out.get('geometry') or {}
    lengths=[float(v) for v in geometry.get('edge_lengths_m') or []]
    if not lengths:
        reasons.append('edge_lengths_missing')
    elif min(lengths)<MIN_EDGE_M:
        reasons.append('implausibly_short_footprint_edge')
    elif max(lengths)>MAX_EDGE_M:
        reasons.append('implausibly_long_footprint_edge')
    if style.get('height_m') is not None:
        reasons.append('unvalidated_height_present')
        style['height_m']=None; changes.append('unvalidated_height_removed')
    if style.get('street_facing_edge') is not None:
        reasons.append('unvalidated_street_facing_edge_present')
        style['street_facing_edge']=None; changes.append('unvalidated_street_facing_edge_removed')
    if style.get('semantic_elements'):
        reasons.append('unvalidated_semantic_elements_present')
        style['semantic_elements']=[]; changes.append('unvalidated_semantics_removed')
    reasons=sorted(set(reasons))
    out['reasons']=reasons
    out['state']='CORRECTED_CANDIDATE' if not reasons else 'QUARANTINE'
    out['correction']={'rule_version':'facade-correction-v1','changes':sorted(changes),'input_digest':recipe.get('recipe_digest') or digest(recipe)}
    out['corrected_digest']=digest({k:v for k,v in out.items() if k!='corrected_digest'})
    return out


def apply(payload):
    recipes=[correct(r) for r in payload.get('recipes') or []]
    return {'format':'grand-bruxelles-facade-corrected-recipes-v1','source_format':payload.get('format'),'rules':{'min_gap_normalized':MIN_GAP,'max_bands':MAX_BANDS,'edge_range_m':[MIN_EDGE_M,MAX_EDGE_M]},'summary':{'recipes':len(recipes),'corrected_candidates':sum(r['state']=='CORRECTED_CANDIDATE' for r in recipes),'quarantined':sum(r['state']=='QUARANTINE' for r in recipes),'changed':sum(bool(r['correction']['changes']) for r in recipes)},'recipes':recipes}


def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--input',required=True); ap.add_argument('--output',required=True); a=ap.parse_args(); payload=json.loads(Path(a.input).read_text(encoding='utf-8')); out=apply(payload); Path(a.output).write_text(json.dumps(out,indent=2,sort_keys=True,ensure_ascii=False)+'\n',encoding='utf-8'); print('FACADE_RULE_CORRECTION_OK',out['summary'])
if __name__=='__main__': main()

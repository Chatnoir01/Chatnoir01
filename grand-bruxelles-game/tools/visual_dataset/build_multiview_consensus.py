#!/usr/bin/env python3
"""Build robust multi-view visual consensus per authoritative UrbIS building.

Only high-confidence building associations and measurable image features participate.
Single-view evidence, strong disagreement and weak source diversity remain blocked.
"""
from __future__ import annotations
import argparse, json, math, statistics
from collections import defaultdict
from pathlib import Path

ASSOCIATION_MIN=0.75
QUALITY_WEIGHT={'USABLE':1.0,'LOW_CONFIDENCE':0.35}
BAND_TOLERANCE=0.035

def weight_for(row):
    analysis=row.get('visual_analysis') or {}; quality=QUALITY_WEIGHT.get(analysis.get('quality_status'),0.0)
    candidates=row.get('building_candidates') or []
    if not candidates or float(candidates[0].get('confidence',0.0))<ASSOCIATION_MIN: return 0.0
    return quality*float(candidates[0]['confidence'])

def weighted_median(pairs):
    pairs=sorted((float(v),float(w)) for v,w in pairs if w>0)
    if not pairs: return None
    total=sum(w for _,w in pairs); acc=0.0
    for value,w in pairs:
        acc+=w
        if acc>=total/2: return value
    return pairs[-1][0]

def weighted_mad(pairs,center):
    if center is None: return None
    return weighted_median([(abs(float(v)-center),w) for v,w in pairs])

def robust_scalar(rows,field):
    pairs=[]
    for row in rows:
        a=row['visual_analysis']; w=row['_weight']; v=a.get(field)
        if v is not None: pairs.append((float(v),w))
    center=weighted_median(pairs); mad=weighted_mad(pairs,center)
    if center is None: return {'value':None,'mad':None,'support':0}
    if mad is None or mad<1e-9: filtered=pairs
    else: filtered=[(v,w) for v,w in pairs if abs(v-center)<=3.5*mad]
    value=weighted_median(filtered); return {'value':None if value is None else round(value,4),'mad':None if mad is None else round(mad,4),'support':len(filtered),'outliers':len(pairs)-len(filtered)}

def cluster_bands(rows,field):
    observations=[]
    for row in rows:
        for pos in (row['visual_analysis'].get(field) or []): observations.append((float(pos),row['_weight'],row['_view_id']))
    clusters=[]
    for pos,w,vid in sorted(observations):
        target=None
        for c in clusters:
            if abs(pos-c['center'])<=BAND_TOLERANCE: target=c; break
        if target is None:
            target={'values':[],'views':set(),'center':pos}; clusters.append(target)
        target['values'].append((pos,w)); target['views'].add(vid); target['center']=weighted_median(target['values'])
    total_views=max(1,len(rows)); out=[]
    for c in clusters:
        support=len(c['views'])
        if support<2: continue
        out.append({'position':round(float(c['center']),4),'support_views':support,'support_fraction':round(support/total_views,3)})
    return sorted(out,key=lambda x:x['position'])

def palette_consensus(rows):
    # Quantize measured colors into broad 32-level RGB bins, then weight by image
    # association/quality and per-image palette fraction. No semantic material label.
    bins=defaultdict(float)
    for row in rows:
        for c in row['visual_analysis'].get('palette') or []:
            rgb=c.get('rgb') or [0,0,0]; key=tuple(int(round(int(v)/32)*32) for v in rgb)
            bins[key]+=row['_weight']*float(c.get('fraction',0.0))
    total=sum(bins.values()) or 1.0
    return [{'rgb':[min(255,v) for v in rgb],'weight_fraction':round(w/total,4)} for rgb,w in sorted(bins.items(),key=lambda kv:(-kv[1],kv[0]))[:6]]

def source_key(row):
    source=str(row.get('source') or 'unknown'); seq=str(row.get('sequence_id') or '')
    return source+(':'+seq if seq else '')

def consensus_for_building(building_id,rows):
    usable=[]
    for i,row in enumerate(rows):
        w=weight_for(row)
        if w<=0: continue
        item=dict(row); item['_weight']=w; item['_view_id']=str(row.get('canonical_id') or row.get('source_id') or row.get('pageid') or i); usable.append(item)
    sources={source_key(r) for r in usable}; scalar_fields=('mean_luminance','mean_channel_stddev','vertical_edge_density','horizontal_edge_density')
    scalars={f:robust_scalar(usable,f) for f in scalar_fields}
    disagreement=0.0
    for f in ('vertical_edge_density','horizontal_edge_density'):
        s=scalars[f]
        if s['value'] not in (None,0) and s['mad'] is not None: disagreement=max(disagreement,min(1.0,s['mad']/max(0.02,abs(s['value']))))
    status='READY'
    reasons=[]
    if len(usable)<2: reasons.append('fewer_than_two_usable_views')
    if len(sources)<2: reasons.append('insufficient_independent_source_diversity')
    if disagreement>0.65: reasons.append('strong_measured_feature_disagreement')
    if reasons: status='INSUFFICIENT_EVIDENCE' if 'strong_measured_feature_disagreement' not in reasons else 'CONFLICT'
    confidence=0.0
    if usable:
        view_factor=min(1.0,len(usable)/4.0); source_factor=min(1.0,len(sources)/3.0); agreement=1.0-disagreement
        confidence=round(0.38*view_factor+0.32*source_factor+0.30*agreement,4)
        if status!='READY': confidence=min(confidence,0.69)
    return {'building_id':building_id,'status':status,'reasons':reasons,'view_count':len(usable),'independent_source_count':len(sources),'visual_confidence':confidence,'measured_consensus':scalars,'palette_consensus':palette_consensus(usable),'vertical_band_consensus':cluster_bands(usable,'strong_vertical_bands'),'horizontal_band_consensus':cluster_bands(usable,'strong_horizontal_bands'),'disagreement_score':round(disagreement,4),'reference_ids':sorted(r['_view_id'] for r in usable)}

def build(records):
    groups=defaultdict(list); skipped=0
    for row in records:
        candidates=row.get('building_candidates') or []
        if not candidates or float(candidates[0].get('confidence',0))<ASSOCIATION_MIN: skipped+=1; continue
        groups[str(candidates[0]['building_id'])].append(row)
    buildings=[consensus_for_building(bid,groups[bid]) for bid in sorted(groups)]
    return {'format':'grand-bruxelles-multiview-consensus-v1','rules':{'association_min':ASSOCIATION_MIN,'minimum_usable_views':2,'minimum_independent_sources':2,'band_tolerance':BAND_TOLERANCE},'summary':{'input_records':len(records),'associated_records':len(records)-skipped,'skipped_low_association':skipped,'buildings':len(buildings),'ready':sum(b['status']=='READY' for b in buildings),'conflict':sum(b['status']=='CONFLICT' for b in buildings),'insufficient':sum(b['status']=='INSUFFICIENT_EVIDENCE' for b in buildings)},'buildings':buildings}

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--input',required=True); ap.add_argument('--output',required=True); a=ap.parse_args(); p=json.loads(Path(a.input).read_text(encoding='utf-8')); out=build(p.get('records') or []); Path(a.output).write_text(json.dumps(out,indent=2,sort_keys=True,ensure_ascii=False)+'\n',encoding='utf-8'); print('MULTIVIEW_CONSENSUS_OK',out['summary'])
if __name__=='__main__': main()

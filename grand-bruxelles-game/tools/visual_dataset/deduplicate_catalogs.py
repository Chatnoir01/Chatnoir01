#!/usr/bin/env python3
"""Deterministically merge Grand Bruxelles visual-reference catalogs.

Exact duplicates collapse only on trustworthy identifiers/content hashes. Spatially
near references are preserved and merely grouped as possible duplicate candidates.
"""
from __future__ import annotations
import argparse, hashlib, json, math
from pathlib import Path
from typing import Any

EARTH_M=6371008.8

def load_rows(path:Path)->list[dict[str,Any]]:
    payload=json.loads(path.read_text(encoding='utf-8'))
    return list(payload.get('images') or [])

def exact_keys(row):
    keys=[]; source=str(row.get('source') or '')
    sid=str(row.get('source_id') or row.get('pageid') or '')
    if source and sid: keys.append('id:'+source+':'+sid)
    for field in ('sha256','commons_sha1'):
        if row.get(field): keys.append(field+':'+str(row[field]).lower())
    return keys

def canonical_sort_key(row):
    return (str(row.get('source') or ''),str(row.get('source_id') or row.get('pageid') or ''),str(row.get('url') or ''),str(row.get('title') or ''))

def canonical_id(row):
    material='|'.join(map(str,canonical_sort_key(row)))
    return hashlib.sha256(material.encode()).hexdigest()[:20]

def haversine_m(a,b):
    lat1,lon1,lat2,lon2=map(math.radians,(a[0],a[1],b[0],b[1])); dlat=lat2-lat1; dlon=lon2-lon1
    q=math.sin(dlat/2)**2+math.cos(lat1)*math.cos(lat2)*math.sin(dlon/2)**2
    return 2*EARTH_M*math.asin(math.sqrt(q))

def merge_exact(rows):
    groups=[]; key_to_group={}
    for row in sorted(rows,key=canonical_sort_key):
        matches={key_to_group[k] for k in exact_keys(row) if k in key_to_group}
        if not matches:
            idx=len(groups); groups.append([row])
        else:
            idx=min(matches); groups[idx].append(row)
            for other in sorted(matches-{idx},reverse=True):
                groups[idx].extend(groups[other]); groups[other]=[]
        for member in groups[idx]:
            for k in exact_keys(member): key_to_group[k]=idx
    return [g for g in groups if g]

def summarize_group(group):
    ordered=sorted(group,key=canonical_sort_key); primary=dict(ordered[0])
    primary['canonical_id']=canonical_id(primary)
    primary['aliases']=[{'source':x.get('source'),'source_id':x.get('source_id') or x.get('pageid'),'url':x.get('url')} for x in ordered]
    primary['exact_duplicate_count']=len(ordered)-1
    primary['usage_classes']=sorted({str(x.get('usage_class') or 'REFERENCE_ONLY') for x in ordered})
    return primary

def candidate_groups(records,distance_m=3.0):
    edges=[]
    for i,a in enumerate(records):
        if a.get('lat') is None or a.get('lon') is None: continue
        for j in range(i+1,len(records)):
            b=records[j]
            if b.get('lat') is None or b.get('lon') is None: continue
            if a.get('source')==b.get('source'): continue
            d=haversine_m((float(a['lat']),float(a['lon'])),(float(b['lat']),float(b['lon'])))
            if d<=distance_m: edges.append((i,j,round(d,3)))
    return edges

def deduplicate(rows):
    records=[summarize_group(g) for g in merge_exact(rows)]
    records=sorted(records,key=lambda r:r['canonical_id'])
    candidates=candidate_groups(records)
    return {'format':'grand-bruxelles-reference-dedup-v1','summary':{'input':len(rows),'canonical':len(records),'exact_duplicates_removed':len(rows)-len(records),'possible_cross_source_pairs':len(candidates)},'records':records,'possible_duplicate_pairs':[{'a':records[i]['canonical_id'],'b':records[j]['canonical_id'],'distance_m':d} for i,j,d in candidates]}

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('catalogs',nargs='+'); ap.add_argument('--output',required=True); args=ap.parse_args()
    rows=[]
    for name in sorted(args.catalogs): rows.extend(load_rows(Path(name)))
    out=deduplicate(rows); Path(args.output).write_text(json.dumps(out,indent=2,sort_keys=True,ensure_ascii=False)+'\n',encoding='utf-8'); print('REFERENCE_DEDUP_OK',out['summary'])
if __name__=='__main__': main()

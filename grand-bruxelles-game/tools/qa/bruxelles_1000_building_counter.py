#!/usr/bin/env python3
from __future__ import annotations
import argparse,csv,hashlib,json,os,re,tempfile,time,urllib.error,urllib.parse,urllib.request,zipfile
from collections import defaultdict
from pathlib import Path
import shapefile
from pyproj import Transformer
from shapely.geometry import shape as S
from shapely.ops import transform,unary_union
from shapely.prepared import prep

WFS_ENDPOINTS=(
 'https://geoservices-urbis.irisnet.be/geoserver/urbisvector/wfs',
 'https://geoservices-urbis.irisnet.be/geoserver/urbisvector/ows',
 'https://geoservices-urbis.irisnet.be/geoserver/ows',
)
LAYER='urbisvector:Buildings'; CRS='EPSG:31370'; UA='Grand-Bruxelles-1000-Counter/1.4'
URLID=re.compile(r'https?://databrussels\.be/id/building/(\d+)',re.I)
NUM=re.compile(r'(?<!\d)(\d{4,10})(?!\d)')
GP={'1601883','1601884','1608847','1608851','1611166','1613517','1635455','1635485','1637695','1637729','1639985','1643344','1645578','1645580','1646728','1647834','1647943','1649069','1653185','1661439','1781508'}
B01_03={'anderlecht-E145500_N169000-B01','anderlecht-E145500_N169000-B02','anderlecht-E145500_N169000-B03'}
PAGE=5000

def get(url,token=''):
 h={'User-Agent':UA,'Accept':'*/*'}
 if token:h.update({'Authorization':f'Bearer {token}','Accept':'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28'})
 last=None
 for n in range(4):
  try:
   with urllib.request.urlopen(urllib.request.Request(url,headers=h),timeout=180) as r:return r.read()
  except urllib.error.HTTPError as e:
   body=e.read().decode('utf-8','replace')[:1800]
   last=RuntimeError(f'HTTP {e.code}: {body}')
   if e.code < 500 and e.code != 429:break
   time.sleep(min(2**n,8))
  except Exception as e:
   last=e;time.sleep(min(2**n,8))
 raise RuntimeError(f'GET failed {url}: {last}')

def rcsv(p):
 with p.open(encoding='utf-8',newline='') as f:return list(csv.DictReader(f))
def ids(row):return [x for x in row['building_ids'].split(';') if x]
def digest(a):return hashlib.sha256(('\n'.join(a)+'\n').encode()).hexdigest()

def postal(zip_path):
 raw=zip_path.read_bytes(); zsha=hashlib.sha256(raw).hexdigest(); cand=[]
 with zipfile.ZipFile(zip_path) as z,tempfile.TemporaryDirectory() as d:
  z.extractall(d)
  for p in Path(d).rglob('*.shp'):
   try:r=shapefile.Reader(str(p),encoding='utf-8',encodingErrors='replace')
   except Exception:continue
   fields=[x[0] for x in r.fields[1:]]; score0=5*('post' in p.name.lower())+sum(2 for f in fields if 'post' in f.lower() or 'zip' in f.lower())
   for sr in r.iterShapeRecords():
    if sr.shape.shapeType not in {5,15,25,31}:continue
    vals=sr.record.as_dict(); keys=[k for k,v in vals.items() if str(v).strip()=='1000']
    if not keys:continue
    try:g=S(sr.shape.__geo_interface__)
    except Exception:continue
    if g.is_empty:continue
    score=score0+max(5 if ('post' in k.lower() or 'zip' in k.lower()) else 1 for k in keys)
    cand.append((score,p.name,g))
 if not cand:raise RuntimeError('NGI archive: no postcode 1000 polygon')
 best=max(x[0] for x in cand); cand=[x for x in cand if x[0]==best]; names={x[1] for x in cand}
 if len(names)!=1:raise RuntimeError(f'NGI postcode layer ambiguous: {names}')
 g=unary_union([x[2] for x in cand]); tr=Transformer.from_crs('EPSG:4326',CRS,always_xy=True); g=transform(tr.transform,g)
 if g.is_empty or not g.is_valid:raise RuntimeError('invalid postcode geometry')
 return g,{'archive_sha256':zsha,'shapefile':next(iter(names)),'feature_count':len(cand),'bounds':list(g.bounds),'area_m2':g.area}

def nid(f):
 p=f.get('properties') or {}
 for k,v in p.items():
  if k.lower() in {'bu_id','building_id','building_2d_id','urbis_building_id','source_building_id','id','inspire_id'}:
   m=URLID.search(str(v))
   if m:return m.group(1)
   if str(v).strip().isdigit():return str(int(str(v).strip()))
 m=URLID.search(json.dumps(p))
 if m:return m.group(1)
 m=re.search(r'(?:Buildings?|building)[._:/-](\d+)$',str(f.get('id','')),re.I)
 return m.group(1) if m else None

def _discovery_profiles(box):
 bbox=f'{box[0]:.3f},{box[1]:.3f},{box[2]:.3f},{box[3]:.3f}'
 common={'service':'WFS','request':'GetFeature','outputformat':'json'}
 for endpoint in WFS_ENDPOINTS:
  yield endpoint,{**common,'version':'2.0.0','typename':LAYER,'srsName':CRS,'bbox':bbox+','+CRS,'count':str(PAGE)},'wfs2-crs-bbox'
  yield endpoint,{**common,'version':'2.0.0','typename':LAYER,'srsName':CRS,'bbox':bbox,'count':str(PAGE)},'wfs2-native-bbox'
 for endpoint in WFS_ENDPOINTS:
  yield endpoint,{**common,'version':'1.1.0','typeName':LAYER,'srsName':CRS,'bbox':bbox,'maxFeatures':str(PAGE)},'wfs11-native-bbox'
  yield endpoint,{**common,'version':'1.0.0','typeName':LAYER,'srsName':CRS,'bbox':bbox,'maxFeatures':str(PAGE)},'wfs10-native-bbox'

def _page(endpoint,q):
 data=json.loads(get(endpoint+'?'+urllib.parse.urlencode(q)))
 if not isinstance(data,dict) or not isinstance(data.get('features'),list):
  raise RuntimeError(f'not a GeoJSON FeatureCollection: {list(data) if isinstance(data,dict) else type(data)}')
 return data

def _stable_sort_field(features):
 if not features:raise RuntimeError('cannot discover sort field from empty UrbIS response')
 keys=list((features[0].get('properties') or {}).keys())
 by_lower={k.lower():k for k in keys}
 preferred=('bu_id','building_id','building_2d_id','urbis_building_id','source_building_id','objectid','object_id','gid','fid','id')
 candidates=[by_lower[x] for x in preferred if x in by_lower]
 candidates += [k for k in keys if 'id' in k.lower() and k not in candidates]
 for k in candidates:
  vals=[(f.get('properties') or {}).get(k) for f in features]
  if vals and all(v is not None and str(v)!='' for v in vals) and len({str(v) for v in vals})==len(vals):return k
 raise RuntimeError(f'no unique sortable owner field found; properties={keys}')

def buildings(boundary):
 box=boundary.bounds; P=prep(boundary); errors=[]; selected=None; probe=None; template=None
 for endpoint,q,label in _discovery_profiles(box):
  try:
   probe=_page(endpoint,q); selected={'endpoint':endpoint,'profile':label,'version':q['version']}; template=(endpoint,q,label); break
  except Exception as e:errors.append(f'{label} @ {endpoint}: {e}')
 if probe is None:raise RuntimeError('all UrbIS Buildings WFS profiles failed:\n'+'\n'.join(errors))
 fs_probe=probe.get('features') or []; sort_field=_stable_sort_field(fs_probe)
 endpoint,base_q,label=template
 base_q=dict(base_q); base_q['sortBy']=sort_field
 out={}; pages=0; bbox_features=0; start=0; prior_signature=None; matched=None
 while True:
  q=dict(base_q)
  if start:q['startIndex']=str(start)
  data=_page(endpoint,q); fs=data.get('features') or []
  if matched is None:matched=data.get('numberMatched',data.get('totalFeatures'))
  pages+=1; bbox_features+=len(fs)
  signature=hashlib.sha256(json.dumps([(f.get('id'),(f.get('properties') or {}).get(sort_field)) for f in fs[:8]],sort_keys=True,default=str).encode()).hexdigest() if fs else None
  if start and fs and signature==prior_signature:raise RuntimeError(f'UrbIS WFS pagination repeated page at startIndex={start}')
  prior_signature=signature
  for f in fs:
   if not f.get('geometry'):continue
   g=S(f['geometry']); pt=g.representative_point()
   if not P.covers(pt):continue
   x=nid(f)
   if not x:raise RuntimeError(f'building without BU_ID: {f.get("id")} {list((f.get("properties") or {}).keys())}')
   out.setdefault(x,(pt.x,pt.y))
  n=len(fs)
  if n<PAGE:break
  start+=n
  if pages>100:raise RuntimeError('UrbIS WFS pagination exceeded 100 pages')
 if isinstance(matched,(int,float)) and int(matched)!=bbox_features:raise RuntimeError(f'UrbIS Buildings WFS incomplete: matched={matched} fetched={bbox_features}')
 if not out:raise RuntimeError('zero buildings in 1000')
 selected['sort_field']=sort_field
 return out,{'wfs':selected,'pages':pages,'bbox_features':bbox_features,'number_matched':matched,'owners':len(out),'owner_sha256':digest(sorted(out,key=int))}

def campaigns(plan,c01c,c02c):
 bs=rcsv(plan/'source_batches.csv'); aa=rcsv(plan/'missing_owner_assignments.csv'); by={r['building_id']:r for r in aa}
 def ok(x,m,rev):
  r=by.get(x)
  if not r or r['assignment_status']!='assigned' or r['municipality_slug']!=m or r['revision_dates']!=rev:raise RuntimeError(f'planner drift {x}')
  return ';' not in r['distribution_keys']
 rev=c01c['source']['revision']; c01=[]
 for b in bs:
  if b['assignment_status']=='assigned' and b['municipality_slug']=='anderlecht' and b['batch_id'] not in B01_03:
   for x in ids(b):
    if not ok(x,'anderlecht',rev):raise RuntimeError('C01 multi-distribution Anderlecht')
    c01.append(x)
 for b in bs:
  if len(c01)>=30000:break
  if b['assignment_status']=='assigned' and b['municipality_slug']=='bruxelles':
   for x in ids(b):
    if len(c01)>=30000:break
    if x not in GP and ok(x,'bruxelles',rev):c01.append(x)
 if len(c01)!=30000 or digest(c01)!=c01c['expected']['owner_sequence_sha256']:raise RuntimeError('C01 mismatch')
 c1=set(c01); c02=[]; rev=c02c['source']['revision']
 for m in ('bruxelles','uccle'):
  for b in bs:
   if len(c02)>=30000:break
   if b['assignment_status']=='assigned' and b['municipality_slug']==m:
    for x in ids(b):
     if len(c02)>=30000:break
     if x in c1 or (m=='bruxelles' and x in GP):continue
     if ok(x,m,rev):c02.append(x)
  if len(c02)>=30000:break
 if len(c02)!=30000 or digest(c02)!=c02c['expected']['owner_sequence_sha256'] or c1&set(c02):raise RuntimeError('C02 mismatch')
 return c1,set(c02),{r['building_id'] for r in aa}

def repo_refs(root,official):
 data=set(); run=set(); exts={'.json','.geojson','.gd','.tscn','.tres','.cfg','.md'}
 for base in (root/'grand-bruxelles-game/data',root/'grand-bruxelles-game/game'):
  for p in base.rglob('*') if base.exists() else []:
   if not p.is_file() or p.suffix.lower() not in exts:continue
   try:t=p.read_text(encoding='utf-8')
   except Exception:continue
   m=(set(URLID.findall(t))|{x for x in NUM.findall(t) if x in official})&official
   if '/game/' in p.as_posix() or '/runtime/' in p.as_posix():run|=m
   else:data|=m
 return data,run

def pr_refs(official,ignore):
 tok=os.getenv('GITHUB_TOKEN',''); repo=os.getenv('GITHUB_REPOSITORY',''); out=defaultdict(set)
 if not tok or not repo:return {}
 pulls=json.loads(get(f'https://api.github.com/repos/{repo}/pulls?state=open&per_page=100',tok))
 head=os.getenv('GITHUB_HEAD_REF','')
 for pr in pulls:
  n=int(pr['number']); txt=(str(pr.get('title') or '')+'\n'+str(pr.get('body') or ''))
  low=txt.lower()
  if n==ignore or (pr.get('head') or {}).get('ref')==head or any(x in low for x in ('source-only','source only','planning only','evidence-only','qa/planning only')):continue
  for x in set(NUM.findall(txt))&official:out[x].add(n)
  files=json.loads(get(f'https://api.github.com/repos/{repo}/pulls/{n}/files?per_page=100',tok))
  for f in files:
   blob=str(f.get('filename',''))+'\n'+str(f.get('patch',''))
   for x in set(NUM.findall(blob))&official:out[x].add(n)
 return {k:sorted(v) for k,v in out.items()}

def main():
 ap=argparse.ArgumentParser()
 for n in ('repo-root','contract','planner-dir','ngi-postal-zip','c01-contract','c02-contract','output-json','output-csv'):ap.add_argument('--'+n,type=Path,required=True)
 a=ap.parse_args(); c=json.loads(a.contract.read_text()); boundary,bmeta=postal(a.ngi_postal_zip)
 print('NGI_POSTAL_1000_OK '+json.dumps(bmeta,sort_keys=True))
 off,wmeta=buildings(boundary); O=set(off)
 print('URBIS_1000_BUILDINGS_OK '+json.dumps(wmeta,sort_keys=True))
 c1,c2,missing=campaigns(a.planner_dir,json.loads(a.c01_contract.read_text()),json.loads(a.c02_contract.read_text()))
 data,run=repo_refs(a.repo_root,O); prs=pr_refs(O,int(c['campaigns']['active_source_draft_pr']))
 finished=set(); ledger=a.repo_root/'grand-bruxelles-game/data/qa/bruxelles_1000_building_completion_ledger.json'
 if ledger.exists():
  for e in json.loads(ledger.read_text()).get('owners',[]):
   if e.get('status')=='finished_perfect' and str(e.get('building_id')) in O:finished.add(str(e['building_id']))
 counts=defaultdict(int); rows=[]
 for x in sorted(O,key=int):
  if x in finished:s='finished_perfect'
  elif x in prs:s='started_open_pr'
  elif x in run:s='started_main_runtime'
  elif x in c1 or x in data:s='source_registered_main'
  elif x in c2:s='source_draft'
  elif x in missing:s='unstarted'
  else:s='unresolved'
  counts[s]+=1; rows.append({'building_id':x,'status':s,'open_prs':';'.join(map(str,prs.get(x,[]))),'repo_data':str(x in data).lower(),'repo_runtime':str(x in run).lower(),'c01':str(x in c1).lower(),'c02':str(x in c2).lower(),'planner_missing':str(x in missing).lower(),'x':f'{off[x][0]:.3f}','y':f'{off[x][1]:.3f}'})
 total=len(O)
 exclusive=('finished_perfect','started_open_pr','started_main_runtime','source_registered_main','source_draft','unstarted','unresolved')
 report={'schema':'grand-bruxelles-postcode-building-counter-v2','scope':'1000 Bruxelles / Brussel','production_base_sha':c['production_base_sha'],'postal_boundary':{**c['postal_boundary'],**bmeta},'buildings':{**c['building_source'],**wmeta},'evidence':{'planner_missing_inside_1000':len(O&missing),'c01_inside_1000':len(O&c1),'c02_inside_1000':len(O&c2),'repo_data_refs':len(O&data),'repo_runtime_refs':len(O&run),'open_pr_refs':len(set(prs))},'counts':{'official_building_owner_total':total,'finished_perfect':counts['finished_perfect'],'started_open_pr':counts['started_open_pr'],'started_main_runtime':counts['started_main_runtime'],'started_total':counts['started_open_pr']+counts['started_main_runtime'],'source_registered_main':counts['source_registered_main'],'source_draft':counts['source_draft'],'unstarted':counts['unstarted'],'unresolved':counts['unresolved'],'remaining_to_perfect':total-len(finished)},'status_rules':c['status_rules'],'runtime_authorized':False,'geometry_modified':False}
 if sum(counts[k] for k in exclusive)!=total:raise RuntimeError('accounting drift')
 a.output_json.parent.mkdir(parents=True,exist_ok=True);a.output_json.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
 with a.output_csv.open('w',newline='',encoding='utf-8') as f:w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
 print('BRUXELLES_1000_BUILDING_COUNTER_OK '+json.dumps(report['counts'],sort_keys=True)+f" boundary_sha256={bmeta['archive_sha256']}")
if __name__=='__main__':main()

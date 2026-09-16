#!/usr/bin/env python3
from __future__ import annotations
import argparse, copy, hashlib, importlib.util, json, tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]; SCRIPT=ROOT/'tools'/'build_road_runtime_index.py'
spec=importlib.util.spec_from_file_location('road_runtime_index',SCRIPT); assert spec and spec.loader
module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
def write_lock(source_root:Path)->None:
 repo_root=source_root.parent.parent; documents={p.relative_to(repo_root).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(source_root.rglob('*.game.json')) if p.is_file()}
 (source_root/'road_destination_sources.lock.json').write_text(json.dumps({'format':'grand-bruxelles-road-destination-source-lock-v1','source_format':'grand-bruxelles-osm-v1','source':'OpenStreetMap contributors via Overpass API','license':'ODbL-1.0','evidence_artifact_id':9733298021,'evidence_catalog_sha256':'786c9cbf3b420a658066bcdc809343abb463bd242b4aef432ab2c7975fa1baef','documents':documents}),encoding='utf-8')
def write_document(path:Path,roads:list[dict])->str:
 path.parent.mkdir(parents=True,exist_ok=True); text=json.dumps({'format':'grand-bruxelles-osm-v1','roads':roads,'buildings':[]},ensure_ascii=False); path.write_text(text,encoding='utf-8'); source_root=next(p for p in path.parents if p.name=='osm' and p.parent.name=='data'); write_lock(source_root); return hashlib.sha256(text.encode()).hexdigest()
def road(osm_id:int,name:str='Teststraat - Rue Test')->dict:return {'osm_id':osm_id,'name':name,'class':'tertiary','width':7.0,'drivable':True,'points':[[0.0,0.0],[10.0,0.0]]}
def assert_contract_rejects(index,fragment,sha):
 try: module.validate_contract(index,expected_catalog_sha256=sha)
 except SystemExit as exc: assert fragment in str(exc),str(exc)
 else: raise AssertionError(fragment)
def synthetic():
 with tempfile.TemporaryDirectory() as tmp:
  root=Path(tmp)/'data'/'osm'; expected=write_document(root/'slice.game.json',[road(20),road(10)]); catalog=module._catalog_module.build_catalog(root); a=module.build_runtime_index(catalog); b=module.build_runtime_index(catalog); assert a==b; d=a['documents'][0]; assert d['sha256']==expected and d['road_ids']==[10,20]
def duplicate():
 with tempfile.TemporaryDirectory() as tmp:
  root=Path(tmp)/'data'/'osm'; write_document(root/'a.game.json',[road(42)]); write_document(root/'b.game.json',[road(42)]); catalog=module._catalog_module.build_catalog(root)
  try: module.build_runtime_index(catalog)
  except SystemExit as exc: assert 'exactly one runtime source document' in str(exc)
  else: raise AssertionError('duplicate runtime source ownership accepted')
def json_contract():
 with tempfile.TemporaryDirectory() as tmp:
  root=Path(tmp)/'data'/'osm'; write_document(root/'slice.game.json',[road(42)]); catalog=module._catalog_module.build_catalog(root); index=module.build_runtime_index(catalog); sha=index['catalog_sha256']
  x=copy.deepcopy(index); x['safe_spawn_ready']=True; assert_contract_rejects(x,'field set drift',sha)
  x=copy.deepcopy(index); x['authorization']['rendered']=True; assert_contract_rejects(x,'authorization field set drift',sha)
  x=copy.deepcopy(index); x['documents'][0]['municipality']='Bruxelles'; assert_contract_rejects(x,'descriptor field set drift',sha)
  x=copy.deepcopy(index); x['documents'][0]['road_ids']=['42']; assert_contract_rejects(x,'JSON type drift road id',sha)
  x=copy.deepcopy(index); x['catalog_sha256']=42; assert_contract_rejects(x,'JSON type drift catalog_sha256',sha)
def identity():
 catalog=module._catalog_module.build_catalog(ROOT/'data'/'osm'); module._catalog_module.validate_contract(catalog); index=module.build_runtime_index(catalog); x=copy.deepcopy(index); x['catalog_sha256']='0'*64
 try: module.validate_contract(x)
 except SystemExit as exc: assert 'catalog identity drift' in str(exc),str(exc)
 else: raise AssertionError('unbound catalog identity accepted')
def real_slice():
 catalog=module._catalog_module.build_catalog(ROOT/'data'/'osm'); module._catalog_module.validate_contract(catalog); index=module.build_runtime_index(catalog); module.validate_contract(index); d=index['documents'][0]; assert d['path']=='data/osm/vertical_slice_01.game.json'; assert {359177328,487501805,1382734012}<=set(d['road_ids']); assert index['catalog_sha256']==catalog['catalog_sha256']
STAGES={'synthetic-determinism-source-binding':synthetic,'duplicate-source-ownership':duplicate,'json-contract-fail-closed':json_contract,'catalog-identity-binding':identity,'real-locked-slice':real_slice}
def main():
 p=argparse.ArgumentParser(); p.add_argument('--stage',choices=STAGES); a=p.parse_args(); selected=[a.stage] if a.stage else list(STAGES)
 for name in selected: print(f'ROAD_RUNTIME_INDEX_STAGE_START: {name}',flush=True); STAGES[name](); print(f'ROAD_RUNTIME_INDEX_STAGE_OK: {name}',flush=True)
 print('ROAD_RUNTIME_INDEX_TEST_OK'); return 0
if __name__=='__main__': raise SystemExit(main())

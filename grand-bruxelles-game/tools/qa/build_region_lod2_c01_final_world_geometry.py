#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, math
from pathlib import Path
from collections import Counter

def sha256_file(path: Path) -> str:
    h=hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda:f.read(1024*1024), b''):
            h.update(chunk)
    return h.hexdigest()

def quantize(v: float, decimals:int)->float:
    return round(v, decimals)

def validate_contract(c:dict)->None:
    if c.get('schema')!='grand-bruxelles-region-lod2-c01-final-world-geometry-lock-v1':
        raise RuntimeError('unexpected schema')
    if c.get('campaign_id')!='region-lod2-C01-30000':
        raise RuntimeError('unexpected campaign')
    e=c['expected']
    exp={'owners':30000,'spatial_cells':132,'solids':30944,'faces':532211,'points':3273027,'parts':534100,'source_payload_bytes':222598504}
    for k,v in exp.items():
        if int(e.get(k,-1))!=v: raise RuntimeError(f'expected {k} drift')
    if c['source_materialization']['archive_sha256']!='6d5358ed20ac100e091a9ebca38cd5da4f43c89f1741f7cbc236ad0b55b28601':
        raise RuntimeError('source materialization archive hash drift')
    if c['source_materialization']['index_sha256']!='288ff7815900d1cb07e0980168b8375c024a18be02144275a63918ae991e17a3':
        raise RuntimeError('source materialization index hash drift')
    wy=c['world_y_lock']
    if wy['archive_sha256']!='1c5d5371efe6c284011b93e6844d822cdeebfc3d8ff91fa5d95c8ae53f83dbac':
        raise RuntimeError('world-Y artifact archive hash drift')
    expected_files={
      'world_y_datum_locked.json':'28ccea014fcfba136e5322db78a0a37394b27bc088e7c449c2e1f706001bbd0e',
      'owner_world_y_offset_by_owner.json':'4cee5e94bb18b615af7c2aca4d64e6ef01ee133a95edacb2cddda39e851fe0a9',
      'owner_world_y_offset_per_owner.csv':'cc0dd2b9e382a2617348f05dadc4ea090b96bc97dd046e4903ef54d69e0d4e9a',
    }
    if wy.get('files_sha256')!=expected_files: raise RuntimeError('world-Y locked file hashes drift')
    t=c['transform']
    if [float(x) for x in t['lambert72_origin']] != [147868.29422791934,169538.62414926197]:
        raise RuntimeError('Lambert72 origin drift')
    if [float(x) for x in t['world_origin']] != [-668.5,0.0,627.84]:
        raise RuntimeError('world origin drift')
    if float(t['anchor_dtm_elevation_m'])!=21.712554931640625:
        raise RuntimeError('world-Y datum drift')
    if t['world_y_formula']!='source_z + owner_rigid_shift_m - anchor_dtm_elevation_m':
        raise RuntimeError('world-Y formula drift')
    if int(t['quantization_decimals'])!=3: raise RuntimeError('quantization drift')
    hard=c['hard_rules']
    if hard.get('final_world_y_authorized') is not True: raise RuntimeError('final world-Y must be authorized')
    if hard.get('world_geometry_artifact_authorized') is not True: raise RuntimeError('world geometry artifact must be authorized')
    for key in ['runtime_authorized','runtime_mount_authorized','collision_authorized','terrain_runtime_authorized','source_geometry_modified','jouable_promotion_authorized']:
        if hard.get(key) is not False: raise RuntimeError(f'{key} must remain false')
    if hard.get('owner_rigid_translation_only') is not True or hard.get('artifact_only') is not True:
        raise RuntimeError('artifact/rigid rules drift')

def main()->int:
    ap=argparse.ArgumentParser()
    ap.add_argument('--contract',type=Path,required=True)
    ap.add_argument('--source-dir',type=Path)
    ap.add_argument('--world-y-dir',type=Path)
    ap.add_argument('--output-dir',type=Path)
    ap.add_argument('--validate-only',action='store_true')
    args=ap.parse_args()
    try:
        c=json.loads(args.contract.read_text())
        validate_contract(c)
        if args.validate_only:
            print('C01_FINAL_WORLD_GEOMETRY_CONTRACT_OK'); return 0
        if not args.source_dir or not args.world_y_dir or not args.output_dir:
            raise RuntimeError('source-dir, world-y-dir and output-dir required')
        source_index_path=args.source_dir/'source_materialization_index.json'
        if sha256_file(source_index_path)!=c['source_materialization']['index_sha256']:
            raise RuntimeError('source materialization index SHA drift')
        sidx=json.loads(source_index_path.read_text())
        if sidx.get('campaign_id')!=c['campaign_id'] or sidx.get('selection',{}).get('owner_count')!=30000 or sidx.get('selection',{}).get('spatial_cell_count')!=132:
            raise RuntimeError('source index campaign/accounting drift')
        sm=sidx['source_metrics']
        for key,exp_key in [('solid_count','solids'),('face_count','faces'),('point_count','points'),('part_count','parts'),('canonical_payload_bytes','source_payload_bytes')]:
            if int(sm[key])!=int(c['expected'][exp_key]): raise RuntimeError(f'source metric {key} drift')
        wy_files=c['world_y_lock']['files_sha256']
        for name,expected_hash in wy_files.items():
            p=args.world_y_dir/name
            if not p.is_file() or sha256_file(p)!=expected_hash: raise RuntimeError(f'world-Y file drift: {name}')
        wy_report=json.loads((args.world_y_dir/'world_y_datum_locked.json').read_text())
        if wy_report.get('final_world_y_authorized') is not True or int(wy_report.get('owners',0))!=30000:
            raise RuntimeError('world-Y report not finalized for 30k')
        offsets=json.loads((args.world_y_dir/'owner_world_y_offset_by_owner.json').read_text())
        if len(offsets)!=30000: raise RuntimeError('world-Y owner count drift')
        origin_e,origin_n=[float(v) for v in c['transform']['lambert72_origin']]
        anchor_x,_,anchor_z=[float(v) for v in c['transform']['world_origin']]
        datum=float(c['transform']['anchor_dtm_elevation_m'])
        decimals=int(c['transform']['quantization_decimals'])
        qlimit=0.5*(10**(-decimals))+1e-12
        out_root=args.output_dir
        cells_root=out_root/'cells'; cells_root.mkdir(parents=True,exist_ok=True)
        out_cells={}
        owners=set(); solids=set(); face_ids=set(); face_types=Counter()
        face_count=point_count=part_count=0
        max_x_err=max_y_err=max_z_err=0.0
        minx=miny=minz=math.inf; maxx=maxy=maxz=-math.inf
        source_bytes=0
        chain=hashlib.sha256()
        for cell_id in sorted(sidx['cells']):
            meta=sidx['cells'][cell_id]
            src=args.source_dir/meta['relative_path']
            if sha256_file(src)!=meta['sha256']: raise RuntimeError(f'source cell SHA drift: {cell_id}')
            if src.stat().st_size!=int(meta['bytes']): raise RuntimeError(f'source cell byte drift: {cell_id}')
            source_bytes += src.stat().st_size
            out_dir=cells_root/cell_id; out_dir.mkdir(parents=True,exist_ok=True)
            out_path=out_dir/'world.ndjson'
            c_owners=set(); c_solids=set(); c_faces=set(); c_points=c_parts=0; c_types=Counter()
            with src.open('r',encoding='utf-8') as inf, out_path.open('w',encoding='utf-8',newline='\n') as outf:
                for ln,line in enumerate(inf,1):
                    if not line.strip(): continue
                    row=json.loads(line)
                    bid=str(row.get('building_id','')); sid=str(row.get('solid_id','')); fid=str(row.get('face_id','')); ft=str(row.get('face_type',''))
                    if not all([bid,sid,fid,ft]): raise RuntimeError(f'missing source identity {cell_id}:{ln}')
                    if bid not in offsets: raise RuntimeError(f'missing world-Y offset for owner {bid}')
                    if fid in face_ids: raise RuntimeError(f'duplicate face id {fid}')
                    off=float(offsets[bid]['world_y_offset_m'])
                    shift=float(offsets[bid]['rigid_shift_m'])
                    if abs((shift-datum)-off)>1e-10: raise RuntimeError(f'world-Y offset formula drift for {bid}')
                    parts=[]
                    for part in row.get('parts',[]):
                        verts=[]; c_parts+=1; part_count+=1
                        for raw in part.get('vertices',[]):
                            if not isinstance(raw,list) or len(raw)<3 or raw[2] is None: raise RuntimeError(f'invalid vertex {fid}')
                            e,n,z=map(float,raw[:3])
                            wx_exact=e-origin_e+anchor_x
                            wy_exact=z+off
                            wz_exact=-(n-origin_n)+anchor_z
                            wx,wy,wz=quantize(wx_exact,decimals),quantize(wy_exact,decimals),quantize(wz_exact,decimals)
                            max_x_err=max(max_x_err,abs(wx-wx_exact)); max_y_err=max(max_y_err,abs(wy-wy_exact)); max_z_err=max(max_z_err,abs(wz-wz_exact))
                            minx=min(minx,wx); maxx=max(maxx,wx); miny=min(miny,wy); maxy=max(maxy,wy); minz=min(minz,wz); maxz=max(maxz,wz)
                            verts.append([wx,wy,wz]); c_points+=1; point_count+=1
                        parts.append({'part_type':part.get('part_type'),'vertices':verts})
                    out={'building_id':bid,'solid_id':sid,'face_id':fid,'face_type':ft,'parts':parts}
                    outf.write(json.dumps(out,ensure_ascii=False,separators=(',',':'))+'\n')
                    owners.add(bid); solids.add(sid); face_ids.add(fid); face_types[ft]+=1; face_count+=1
                    c_owners.add(bid); c_solids.add(sid); c_faces.add(fid); c_types[ft]+=1
            if len(c_owners)!=int(meta['owner_count']) or len(c_solids)!=int(meta['solid_count']) or len(c_faces)!=int(meta['face_count']) or c_points!=int(meta['point_count']) or c_parts!=int(meta['part_count']):
                raise RuntimeError(f'cell accounting drift: {cell_id}')
            oh=sha256_file(out_path); obytes=out_path.stat().st_size
            out_meta={
                'owner_count':len(c_owners),'solid_count':len(c_solids),'face_count':len(c_faces),'point_count':c_points,'part_count':c_parts,
                'face_type_counts':dict(sorted(c_types.items())),'bytes':obytes,'sha256':oh,'relative_path':f'cells/{cell_id}/world.ndjson',
                'coordinate_space':'game world XYZ','source_sha256':meta['sha256'],'source_bytes':int(meta['bytes'])
            }
            out_cells[cell_id]=out_meta
            chain.update(f"{cell_id}\t{oh}\t{obytes}\t{len(c_owners)}\t{len(c_faces)}\t{c_points}\n".encode())
        e=c['expected']
        actual={'owners':len(owners),'spatial_cells':len(out_cells),'solids':len(solids),'faces':face_count,'points':point_count,'parts':part_count,'source_payload_bytes':source_bytes}
        for k,v in actual.items():
            if int(e[k])!=int(v): raise RuntimeError(f'global accounting drift {k}: {v} != {e[k]}')
        for qerr,name in [(max_x_err,'X'),(max_y_err,'Y'),(max_z_err,'Z')]:
            if qerr>qlimit: raise RuntimeError(f'{name} quantization error exceeded bound: {qerr}')
        idx={
            'schema':'grand-bruxelles-region-lod2-c01-final-world-geometry-v1','campaign_id':c['campaign_id'],
            'source_materialization':{'artifact_id':c['source_materialization']['artifact_id'],'archive_sha256':c['source_materialization']['archive_sha256'],'index_sha256':c['source_materialization']['index_sha256']},
            'world_y_lock':{'artifact_id':c['world_y_lock']['artifact_id'],'archive_sha256':c['world_y_lock']['archive_sha256'],'datum_m':datum},
            'transform':c['transform'],'accounting':actual,'face_type_counts':dict(sorted(face_types.items())),
            'world_extent_m':{'min_x':minx,'max_x':maxx,'min_y':miny,'max_y':maxy,'min_z':minz,'max_z':maxz},
            'max_quantization_error_m':{'x':max_x_err,'y':max_y_err,'z':max_z_err},
            'cell_payload_chain_sha256':chain.hexdigest(),'cells':out_cells,
            'final_world_y_authorized':True,'world_geometry_artifact_authorized':True,'runtime_authorized':False,'runtime_mount_authorized':False,'collision_authorized':False,'terrain_runtime_authorized':False,'source_geometry_modified':False,'owner_rigid_translation_only':True,'jouable_promotion_authorized':False,'artifact_only':True,
        }
        idx_path=out_root/'world_geometry_index.json'
        idx_path.write_text(json.dumps(idx,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
        result={'world_geometry_index.json':sha256_file(idx_path),'cell_payload_chain_sha256':chain.hexdigest()}
        (out_root/'result.sha256.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
        expected_hashes=c.get('expected_output_sha256',{})
        if expected_hashes:
            for k,v in result.items():
                exp=expected_hashes.get(k)
                if exp is not None and exp!=v: raise RuntimeError(f'locked output hash drift {k}: {v} != {exp}')
        print('C01_FINAL_WORLD_GEOMETRY_OK: '+ ' '.join(f'{k}={v}' for k,v in actual.items()) + f" index_sha={result['world_geometry_index.json']} chain_sha={chain.hexdigest()} qerr=({max_x_err:.9f},{max_y_err:.9f},{max_z_err:.9f})")
        return 0
    except Exception as exc:
        print(f'C01_FINAL_WORLD_GEOMETRY_ERROR: {exc}',flush=True)
        return 1
if __name__=='__main__': raise SystemExit(main())

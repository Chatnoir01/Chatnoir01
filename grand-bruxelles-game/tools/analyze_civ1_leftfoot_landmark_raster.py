#!/usr/bin/env python3
"""Measure the diagnostic magenta LeftFoot landmark in real Godot rasters.

The marker is emitted by the witness from the actual Skeleton3D LeftFoot pose only
after Skin/Skeleton integrity is verified. This analyzer never infers foot identity
from the character silhouette.
"""
from __future__ import annotations
import json, math, struct, sys, zlib
from pathlib import Path

PNG_SIG=b"\x89PNG\r\n\x1a\n"
DISTANCES=(2,4,8)
SAMPLES=(114,115,116,117,118)
MAX_CENTROID_ERROR_PX=1.5
MAX_PATH_REL_ERROR=0.25
MIN_MARKER_WEIGHT=1000.0


def _paeth(a:int,b:int,c:int)->int:
    p=a+b-c; pa=abs(p-a); pb=abs(p-b); pc=abs(p-c)
    return a if pa<=pb and pa<=pc else b if pb<=pc else c

def read_png(path:Path):
    raw=path.read_bytes()
    if not raw.startswith(PNG_SIG): raise ValueError('not PNG')
    pos=len(PNG_SIG); width=height=color_type=bit_depth=interlace=None; payload=bytearray()
    while pos+12<=len(raw):
        n=struct.unpack('>I',raw[pos:pos+4])[0]; kind=raw[pos+4:pos+8]; data=raw[pos+8:pos+8+n]; pos+=12+n
        if kind==b'IHDR': width,height,bit_depth,color_type,_,_,interlace=struct.unpack('>IIBBBBB',data)
        elif kind==b'IDAT': payload.extend(data)
        elif kind==b'IEND': break
    if not width or not height or bit_depth!=8 or color_type not in (2,6) or interlace!=0: raise ValueError('unsupported PNG')
    channels=3 if color_type==2 else 4; stride=width*channels; decoded=zlib.decompress(bytes(payload)); rows=[]; prev=bytearray(stride); off=0
    for _ in range(height):
        f=decoded[off]; off+=1; src=decoded[off:off+stride]; off+=stride; cur=bytearray(stride)
        for i,x in enumerate(src):
            a=cur[i-channels] if i>=channels else 0; b=prev[i]; c=prev[i-channels] if i>=channels else 0
            if f==0:v=x
            elif f==1:v=(x+a)&255
            elif f==2:v=(x+b)&255
            elif f==3:v=(x+((a+b)//2))&255
            elif f==4:v=(x+_paeth(a,b,c))&255
            else: raise ValueError('unsupported PNG filter')
            cur[i]=v
        rows.append(bytes(cur)); prev=cur
    return width,height,rows

def marker_centroid(path:Path)->dict:
    width,height,rows=read_png(path); channels=len(rows[0])//width
    total=0.0; sx=0.0; sy=0.0; count=0
    for y,row in enumerate(rows):
        for x in range(width):
            i=x*channels; r,g,b=row[i],row[i+1],row[i+2]
            chroma=float(min(r,b)-g)
            if r>=128 and b>=128 and chroma>=64:
                w=chroma; total+=w; sx+=x*w; sy+=y*w; count+=1
    if total<MIN_MARKER_WEIGHT or count<3: raise ValueError(f'insufficient magenta landmark in {path}: count={count} weight={total}')
    return {'centroid_x_px':sx/total,'centroid_y_px':sy/total,'marker_pixel_count':count,'marker_weight':total}

def _path(xs): return sum(abs(xs[i]-xs[i-1]) for i in range(1,len(xs)))
def _signed(xs): return xs[-1]-xs[0]
def _rel(a,b): return abs(a-b)/max(abs(b),1e-12)
def assess(observed:list[float],expected:list[float])->dict:
    if len(observed)!=len(expected) or len(observed)<2: raise ValueError('series length')
    errors=[abs(a-b) for a,b in zip(observed,expected)]
    op=_path(observed); ep=_path(expected); os=_signed(observed); es=_signed(expected)
    direction=(abs(os)>1e-9 and abs(es)>1e-9 and ((os>0)==(es>0)))
    return {'observed_path_px':op,'expected_path_px':ep,'path_relative_error':_rel(op,ep),
            'max_centroid_error_px':max(errors),'signed_observed_px':os,'signed_expected_px':es,
            'direction_match':direction,'passed':max(errors)<=MAX_CENTROID_ERROR_PX and _rel(op,ep)<=MAX_PATH_REL_ERROR and direction}

def analyze(report:dict,capture_dir:Path)->dict:
    if report.get('schema')!='grand-bruxelles-civ1-leftfoot-landmark-witness-v1': raise ValueError('witness schema')
    if report.get('diagnostic_only') is not True or report.get('landmark_semantic')!='leftfoot_bone_pose_with_verified_same_skeleton_skin': raise ValueError('witness semantic')
    if report.get('resolution')!=[1280,720] or float(report.get('vertical_fov_deg',0))!=45.0: raise ValueError('camera contract')
    integ=report.get('skin_integrity',{})
    for key in ('mesh_instance_count','surface_count','skinned_mesh_count','skin_bind_count','same_skeleton_skin_count'):
        if int(integ.get(key,0))<1: raise ValueError('skin integrity '+key)
    for key in ('perceptual_2_8m_claimed','planted_contact_claimed','animation_correction_authorized','runtime_authorized','visual_approval_claimed','player_view_claimed'):
        if report.get(key) is not False: raise ValueError('claim rail '+key)
    cmap={(int(c['distance_m']),int(c['sample_index'])):c for c in report.get('captures',[]) if isinstance(c,dict)}
    if set(cmap)!={(d,s) for d in DISTANCES for s in SAMPLES}: raise ValueError('capture matrix')
    measurements=[]
    for d in DISTANCES:
        records=[]
        for s in SAMPLES:
            c=cmap[(d,s)]; path=capture_dir/Path(c['png']).name
            m=marker_centroid(path); expected=c['expected_screen_xy_px']
            records.append({'sample_index':s,**m,'expected_screen_x_px':float(expected[0]),'expected_screen_y_px':float(expected[1]),
                            'centroid_error_px':math.hypot(m['centroid_x_px']-float(expected[0]),m['centroid_y_px']-float(expected[1]))})
        quality=assess([r['centroid_x_px'] for r in records],[r['expected_screen_x_px'] for r in records])
        measurements.append({'distance_m':d,'records':records,**quality})
    all_pass=all(m['passed'] for m in measurements)
    return {'schema':'grand-bruxelles-civ1-leftfoot-landmark-raster-analysis-v1','diagnostic_only':True,
            'landmark_semantic':'magenta_raster_of_verified_leftfoot_bone_pose','samples':list(SAMPLES),'distances_m':list(DISTANCES),
            'max_centroid_error_px':MAX_CENTROID_ERROR_PX,'max_path_relative_error':MAX_PATH_REL_ERROR,'measurements':measurements,
            'single_leftfoot_identity_preserved_2_4_8m':all_pass,'quantitative_landmark_candidate':all_pass,
            'perceptual_2_8m_claimed':False,'planted_contact_claimed':False,'animation_correction_authorized':False,
            'runtime_authorized':False,'visual_approval_claimed':False,'player_view_claimed':False,
            'verdict':'AMELIORER_LEFTFOOT_LANDMARK_IDENTITY_PRESERVED_NO_PROMOTION' if all_pass else 'JETER_LEFTFOOT_LANDMARK_RASTER_DRIFT'}

def main(argv):
    if len(argv)!=4:
        print('usage: analyze_civ1_leftfoot_landmark_raster.py WITNESS.json CAPTURE_DIR OUT.json',file=sys.stderr); return 2
    try:
        report=json.loads(Path(argv[1]).read_text(encoding='utf-8')); out=analyze(report,Path(argv[2])); Path(argv[3]).write_text(json.dumps(out,indent=2)+'\n',encoding='utf-8')
    except Exception as exc:
        print(f'CIV1_LEFTFOOT_LANDMARK_ANALYSIS_FAIL: {exc}',file=sys.stderr); return 3
    print('CIV1_LEFTFOOT_LANDMARK_ANALYSIS_OK',[(m['distance_m'],m['observed_path_px'],m['expected_path_px'],m['path_relative_error'],m['direction_match']) for m in out['measurements']],out['verdict'])
    return 0
if __name__=='__main__': raise SystemExit(main(sys.argv))

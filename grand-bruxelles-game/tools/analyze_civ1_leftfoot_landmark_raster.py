#!/usr/bin/env python3
"""Measure the diagnostic magenta LeftFoot landmark in real Godot rasters."""
from __future__ import annotations
import json, math, struct, sys, zlib
from pathlib import Path
PNG_SIG=b"\x89PNG\r\n\x1a\n"; DISTANCES=(2,4,8); SAMPLES=(114,115,116,117,118)
MAX_CENTROID_ERROR_PX=1.5; MAX_PATH_REL_ERROR=0.25; MIN_MARKER_WEIGHT=1000.0

def _paeth(a,b,c):
 p=a+b-c; pa=abs(p-a); pb=abs(p-b); pc=abs(p-c); return a if pa<=pb and pa<=pc else b if pb<=pc else c

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
   v=x if f==0 else (x+a)&255 if f==1 else (x+b)&255 if f==2 else (x+((a+b)//2))&255 if f==3 else (x+_paeth(a,b,c))&255 if f==4 else (_ for _ in ()).throw(ValueError('unsupported PNG filter'))
   cur[i]=v
  rows.append(bytes(cur)); prev=cur
 return width,height,rows

def marker_centroid(path:Path)->dict:
 width,height,rows=read_png(path); channels=len(rows[0])//width; total=sx=sy=0.0; count=0
 for y,row in enumerate(rows):
  for x in range(width):
   i=x*channels; r,g,b=row[i],row[i+1],row[i+2]; chroma=float(min(r,b)-g)
   if r>=128 and b>=128 and chroma>=64: total+=chroma; sx+=x*chroma; sy+=y*chroma; count+=1
 if total<MIN_MARKER_WEIGHT or count<3: raise ValueError(f'insufficient magenta landmark in {path}: count={count} weight={total}')
 return {'centroid_x_px':sx/total,'centroid_y_px':sy/total,'marker_pixel_count':count,'marker_weight':total}

def _path(xs): return sum(abs(xs[i]-xs[i-1]) for i in range(1,len(xs)))
def _signed(xs): return xs[-1]-xs[0]
def _rel(a,b): return abs(a-b)/max(abs(b),1e-12)
def assess(observed,expected):
 errors=[abs(a-b) for a,b in zip(observed,expected)]; op=_path(observed); ep=_path(expected); os=_signed(observed); es=_signed(expected); direction=abs(os)>1e-9 and abs(es)>1e-9 and ((os>0)==(es>0))
 return {'observed_path_px':op,'expected_path_px':ep,'path_relative_error':_rel(op,ep),'max_centroid_error_px':max(errors),'signed_observed_px':os,'signed_expected_px':es,'direction_match':direction,'passed':max(errors)<=MAX_CENTROID_ERROR_PX and _rel(op,ep)<=MAX_PATH_REL_ERROR and direction}

def analyze(report,capture_dir):
 if report.get('schema')!='grand-bruxelles-civ1-leftfoot-landmark-witness-v1': raise ValueError('witness schema')
 cmap={(int(c['distance_m']),int(c['sample_index'])):c for c in report.get('captures',[]) if isinstance(c,dict)}
 measurements=[]
 for d in DISTANCES:
  records=[]
  for s in SAMPLES:
   c=cmap[(d,s)]; m=marker_centroid(capture_dir/Path(c['png']).name); e=c['expected_screen_xy_px']; records.append({'sample_index':s,**m,'expected_screen_x_px':float(e[0]),'expected_screen_y_px':float(e[1]),'centroid_error_px':math.hypot(m['centroid_x_px']-float(e[0]),m['centroid_y_px']-float(e[1]))})
  measurements.append({'distance_m':d,'records':records,**assess([r['centroid_x_px'] for r in records],[r['expected_screen_x_px'] for r in records])})
 all_pass=all(m['passed'] for m in measurements)
 return {'schema':'grand-bruxelles-civ1-leftfoot-landmark-raster-analysis-v1','diagnostic_only':True,'landmark_semantic':'magenta_raster_of_verified_leftfoot_bone_pose','samples':list(SAMPLES),'distances_m':list(DISTANCES),'max_centroid_error_px':MAX_CENTROID_ERROR_PX,'max_path_relative_error':MAX_PATH_REL_ERROR,'measurements':measurements,'single_leftfoot_identity_preserved_2_4_8m':all_pass,'quantitative_landmark_candidate':all_pass,'perceptual_2_8m_claimed':False,'planted_contact_claimed':False,'animation_correction_authorized':False,'runtime_authorized':False,'visual_approval_claimed':False,'player_view_claimed':False,'verdict':'AMELIORER_LEFTFOOT_LANDMARK_IDENTITY_PRESERVED_NO_PROMOTION' if all_pass else 'JETER_LEFTFOOT_LANDMARK_RASTER_DRIFT'}

def main(argv):
 if len(argv)!=4:return 2
 try:
  out=analyze(json.loads(Path(argv[1]).read_text()),Path(argv[2])); Path(argv[3]).write_text(json.dumps(out,indent=2)+'\n')
 except Exception as exc: print(f'CIV1_LEFTFOOT_LANDMARK_ANALYSIS_FAIL: {exc}',file=sys.stderr); return 3
 print('CIV1_LEFTFOOT_LANDMARK_ANALYSIS_OK',out['verdict']); return 0
if __name__=='__main__': raise SystemExit(main(sys.argv))

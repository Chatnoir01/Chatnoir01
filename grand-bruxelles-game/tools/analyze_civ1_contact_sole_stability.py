#!/usr/bin/env python3
from __future__ import annotations
import json, math, struct, sys, zlib
from pathlib import Path

PNG_SIG=b"\x89PNG\r\n\x1a\n"
DISTANCES=(2,4,8)
SAMPLES=(118,119,0,1,2)
MIN_STABLE_COMMON_SAMPLES=3
ROI_RADIUS_MULT=4.0
MIN_ROI_HALF_WIDTH_PX=8


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


def observe(path:Path)->dict:
    width,height,rows=read_png(path); channels=len(rows[0])//width
    sx=sy=weight=0.0; count=0
    for y,row in enumerate(rows):
        for x in range(width):
            i=x*channels; r,g,b=row[i],row[i+1],row[i+2]; chroma=float(min(r,b)-g)
            if r>=128 and b>=128 and chroma>=64:
                sx+=x*chroma; sy+=y*chroma; weight+=chroma; count+=1
    if count<3 or weight<1000: raise ValueError('missing landmark')
    cx=sx/weight; cy=sy/weight; radius=math.sqrt(count/math.pi); roi=max(MIN_ROI_HALF_WIDTH_PX,int(math.ceil(ROI_RADIUS_MULT*radius)))
    white=[]
    for y in range(max(0,int(cy-roi)),min(height-1,int(cy+roi))+1):
        row=rows[y]
        for x in range(max(0,int(cx-roi)),min(width-1,int(cx+roi))+1):
            i=x*channels; r,g,b=row[i],row[i+1],row[i+2]
            if r>=220 and g>=220 and b>=220: white.append((x,y))
    if not white: raise ValueError('missing local sole')
    bottom=max(y for _,y in white); xs=[x for x,y in white if y==bottom]; bx=sum(xs)/len(xs)
    norm=(bx-cx)/radius; side=1 if norm>0 else -1 if norm<0 else 0
    return {'marker_x_px':cx,'marker_y_px':cy,'marker_radius_px':radius,'local_bottom_y_px':bottom,'local_bottom_x_px':bx,'normalized_offset_x':norm,'side':side}


def analyze(witness:dict,capture_dir:Path)->dict:
    if witness.get('schema')!='grand-bruxelles-civ1-leftfoot-landmark-witness-v1': raise ValueError('schema')
    if witness.get('sample_indices')!=list(SAMPLES) or witness.get('resolution')!=[1280,720]: raise ValueError('capture contract')
    for k in ('planted_contact_claimed','animation_correction_authorized','runtime_authorized','visual_approval_claimed','player_view_claimed'):
        if witness.get(k) is not False: raise ValueError('claim rail '+k)
    cmap={(int(c['distance_m']),int(c['sample_index'])):c for c in witness.get('captures',[]) if isinstance(c,dict)}
    if set(cmap)!={(d,s) for d in DISTANCES for s in SAMPLES}: raise ValueError('capture matrix')
    records={}
    for s in SAMPLES:
        records[s]={}
        for d in DISTANCES:
            p=capture_dir/Path(cmap[(d,s)]['png']).name
            records[s][d]=observe(p)
    common=[]
    for s in SAMPLES:
        sides={records[s][d]['side'] for d in DISTANCES}
        if len(sides)==1 and 0 not in sides: common.append(s)
    longest=[]; cur=[]
    for s in SAMPLES:
        if s in common: cur.append(s)
        else:
            if len(cur)>len(longest): longest=cur[:]
            cur=[]
    if len(cur)>len(longest): longest=cur[:]
    stable=len(longest)>=MIN_STABLE_COMMON_SAMPLES
    return {'schema':'grand-bruxelles-civ1-contact-sole-stability-v1','diagnostic_only':True,'samples':list(SAMPLES),'distances_m':list(DISTANCES),
            'records':records,'common_same_side_samples':common,'longest_common_stable_window':longest,'minimum_stable_common_samples':MIN_STABLE_COMMON_SAMPLES,
            'contact_sole_identity_stable':stable,'quantitative_foot_slide_candidate':False,'planted_contact_claimed':False,
            'animation_correction_authorized':False,'runtime_authorized':False,'visual_approval_claimed':False,'player_view_claimed':False,
            'verdict':'AMELIORER_CONTACT_SOLE_WINDOW_STABLE_NO_SLIDE_PROMOTION' if stable else 'AMELIORER_CONTACT_SOLE_IDENTITY_BREAKS_BEFORE_QUANTITATIVE_SLIDE'}


def main(argv:list[str])->int:
    if len(argv)!=4:
        print('usage: analyze_civ1_contact_sole_stability.py WITNESS.json CAPTURE_DIR OUT.json',file=sys.stderr); return 2
    try:
        w=json.loads(Path(argv[1]).read_text()); out=analyze(w,Path(argv[2])); Path(argv[3]).write_text(json.dumps(out,indent=2)+'\n')
    except Exception as exc:
        print('CIV1_CONTACT_SOLE_STABILITY_FAIL:',exc,file=sys.stderr); return 3
    print('CIV1_CONTACT_SOLE_STABILITY_OK',out['common_same_side_samples'],out['longest_common_stable_window'],out['verdict'])
    return 0

if __name__=='__main__': raise SystemExit(main(sys.argv))

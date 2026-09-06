#!/usr/bin/env python3
"""Diagnostic same-bottom-row subpixel estimator for CIV-1 2/4/8 m rasters.

The semantic anchor is unchanged: the bottom-most row containing near-white CIV-1
pixels (RGB >= 220). Subpixel position is estimated only on that same row and only
inside the primary support expanded by one pixel, using anti-aliased luminance
weights above a conservative 180 floor. No other row/component/body region may
contribute. This is evidence tooling only; it cannot promote runtime/animation/
contact/player-view/visual approval.
"""
from __future__ import annotations
import json, math, struct, sys, zlib
from pathlib import Path

PNG_SIG=b"\x89PNG\r\n\x1a\n"; DISTANCES=(2,4,8); SAMPLES=(115,116,117,118)
WHITE=220; WEIGHT_FLOOR=180; SUPPORT_PAD_PX=1; MIN_NEAR_WHITE_PIXELS=15
MAX_NEAR_SCALE_REL_ERROR=0.25; MAX_FAR_SCALE_REL_ERROR=0.25; EPS=1e-9
POSITION_ROW_SEMANTIC="same_bottom_most_near_white_row"

def _paeth(a,b,c):
    p=a+b-c; pa,pb,pc=abs(p-a),abs(p-b),abs(p-c)
    return a if pa<=pb and pa<=pc else b if pb<=pc else c

def read_png(path:Path):
    raw=path.read_bytes()
    if not raw.startswith(PNG_SIG): raise ValueError("not PNG")
    pos=8; width=height=depth=ctype=interlace=None; payload=bytearray()
    while pos+12<=len(raw):
        n=struct.unpack(">I",raw[pos:pos+4])[0]; kind=raw[pos+4:pos+8]; data=raw[pos+8:pos+8+n]; pos+=12+n
        if kind==b"IHDR": width,height,depth,ctype,_,_,interlace=struct.unpack(">IIBBBBB",data)
        elif kind==b"IDAT": payload.extend(data)
        elif kind==b"IEND": break
    if not width or not height or depth!=8 or ctype not in (2,6) or interlace!=0: raise ValueError("unsupported PNG")
    ch=3 if ctype==2 else 4; stride=width*ch; dec=zlib.decompress(bytes(payload)); rows=[]; prev=bytearray(stride); off=0
    for _ in range(height):
        f=dec[off]; off+=1; src=dec[off:off+stride]; off+=stride; cur=bytearray(stride)
        for i,x in enumerate(src):
            a=cur[i-ch] if i>=ch else 0; b=prev[i]; c=prev[i-ch] if i>=ch else 0
            if f==0:v=x
            elif f==1:v=(x+a)&255
            elif f==2:v=(x+b)&255
            elif f==3:v=(x+((a+b)//2))&255
            elif f==4:v=(x+_paeth(a,b,c))&255
            else: raise ValueError("unsupported PNG filter")
            cur[i]=v
        rows.append(bytes(cur)); prev=cur
    return width,height,rows

def observation(path:Path):
    width,_,rows=read_png(path); ch=len(rows[0])//width; bottom=-1; primary=[]
    for y,row in enumerate(rows):
        xs=[]
        for x in range(width):
            i=x*ch
            if row[i]>=WHITE and row[i+1]>=WHITE and row[i+2]>=WHITE: xs.append(x)
        if xs: bottom=y; primary=xs
    if bottom<0 or len(primary)<MIN_NEAR_WHITE_PIXELS: raise ValueError(f"under-sampled bottom row: {path}")
    lo=max(0,min(primary)-SUPPORT_PAD_PX); hi=min(width-1,max(primary)+SUPPORT_PAD_PX); row=rows[bottom]
    weighted=[]
    for x in range(lo,hi+1):
        i=x*ch; lum=(row[i]+row[i+1]+row[i+2])/3.0; w=max(0.0,lum-WEIGHT_FLOOR)
        if w>0: weighted.append((x,w))
    total=sum(w for _,w in weighted)
    if total<=0: raise ValueError("no weighted same-row support")
    return {"bottom_y_px":bottom,"position_row_semantic":POSITION_ROW_SEMANTIC,
            "primary_min_x_px":min(primary),"primary_max_x_px":max(primary),"primary_pixel_count":len(primary),
            "integer_centroid_x_px":sum(primary)/len(primary),"subpixel_centroid_x_px":sum(x*w for x,w in weighted)/total,
            "weighted_support_min_x_px":min(x for x,_ in weighted),"weighted_support_max_x_px":max(x for x,_ in weighted),"weighted_support_count":len(weighted)}

def _path(xs):
    v=sum(abs(xs[i]-xs[i-1]) for i in range(1,len(xs)))
    if not math.isfinite(v): raise ValueError("non-finite path")
    return v

def scale_calibration(measurements):
    by={d["distance_m"]:d["subpixel_path_px"] for d in measurements}; p2,p4=by[2],by[4]
    expected4=p2*0.5; rel=abs(p4-expected4)/max(abs(expected4),EPS); near_ok=rel<=MAX_NEAR_SCALE_REL_ERROR
    p8=by[8]; non_increasing=p8<=p4+EPS
    expected8=p4*0.5; rel8=abs(p8-expected8)/max(abs(expected8),EPS); far_scale_ok=rel8<=MAX_FAR_SCALE_REL_ERROR
    return {"near_2_to_4_expected_half":expected4,"near_2_to_4_relative_error":rel,"near_calibration_passed":near_ok,
            "far_4_to_8_expected_half":expected8,"far_4_to_8_relative_error":rel8,"far_non_increasing":non_increasing,
            "far_scale_calibration_passed":far_scale_ok,"quantitative_8m_candidate": bool(near_ok and non_increasing and far_scale_ok)}

def analyze(capture_dir:Path):
    ms=[]
    for d in DISTANCES:
        rec=[]
        for s in SAMPLES:
            p=capture_dir/f"civ1-distance-{d}m-{s}.png"
            if not p.is_file(): raise ValueError(f"missing capture d={d} sample={s}")
            rec.append({"sample_index":s,**observation(p)})
        ms.append({"distance_m":d,"records":rec,"integer_path_px":_path([r["integer_centroid_x_px"] for r in rec]),
                   "subpixel_path_px":_path([r["subpixel_centroid_x_px"] for r in rec])})
    scale=scale_calibration(ms)
    verdict="AMELIORER_SUBPIXEL_8M_CANDIDATE_NO_PROMOTION" if scale["quantitative_8m_candidate"] else "AMELIORER_SUBPIXEL_DISTANCE_SCALE_REJECTED_NO_PROMOTION"
    return {"schema":"grand-bruxelles-civ1-bottomrow-subpixel-v3","diagnostic_only":True,
            "source_semantic":"actual_godot_1280x720_same_bottom_most_row_luminance_weighted",
            "position_row_semantic":POSITION_ROW_SEMANTIC,
            "distances_m":list(DISTANCES),"samples":list(SAMPLES),"white_threshold":WHITE,"weight_floor":WEIGHT_FLOOR,
            "support_pad_px":SUPPORT_PAD_PX,"distance_measurements":ms,"distance_scale_calibration":scale,
            "perceptual_2_8m_claimed":False,"planted_contact_claimed":False,"animation_correction_authorized":False,
            "runtime_authorized":False,"visual_approval_claimed":False,"player_view_claimed":False,"verdict":verdict}

def main(argv):
    if len(argv)!=3: print("usage: analyze_civ1_bottomrow_subpixel.py CAPTURE_DIR OUT.json",file=sys.stderr); return 2
    try:
        r=analyze(Path(argv[1])); Path(argv[2]).write_text(json.dumps(r,indent=2)+"\n",encoding="utf-8")
    except Exception as e: print(f"CIV1_BOTTOMROW_SUBPIXEL_FAIL: {e}",file=sys.stderr); return 3
    print("CIV1_BOTTOMROW_SUBPIXEL_OK", {d['distance_m']:d['subpixel_path_px'] for d in r['distance_measurements']}, r['distance_scale_calibration'])
    return 0
if __name__=="__main__": raise SystemExit(main(sys.argv))

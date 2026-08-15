#!/usr/bin/env python3
"""Extract deterministic low-level facade-reference features from local images.

This deliberately does not claim semantic window/door recognition. It emits only
measurable palette, luminance, edge and structural-band observations that later
consensus/generation stages may use under confidence gates.
"""
from __future__ import annotations
import argparse, json, math
from pathlib import Path
from PIL import Image, ImageStat

MAX_SIDE=512
EDGE_THRESHOLD=28

def resize_rgb(path:Path):
    im=Image.open(path).convert('RGB'); original=im.size
    im.thumbnail((MAX_SIDE,MAX_SIDE),Image.Resampling.LANCZOS)
    return im,original

def palette(im,count=6):
    q=im.quantize(colors=count,method=Image.Quantize.MEDIANCUT).convert('RGB')
    colors=q.getcolors(maxcolors=im.width*im.height) or []
    total=max(1,sum(n for n,_ in colors)); ranked=sorted(colors,reverse=True)
    return [{'rgb':list(rgb),'fraction':round(n/total,4)} for n,rgb in ranked[:count]]

def luminance(rgb): return 0.2126*rgb[0]+0.7152*rgb[1]+0.0722*rgb[2]
def edge_features(im):
    px=im.load(); w,h=im.size; vertical=[0]*(w-1); horizontal=[0]*(h-1); v_hits=h_hits=0
    for y in range(h):
        for x in range(w-1):
            a=px[x,y]; b=px[x+1,y]; d=sum(abs(a[i]-b[i]) for i in range(3))/3
            if d>=EDGE_THRESHOLD: vertical[x]+=1; v_hits+=1
    for y in range(h-1):
        for x in range(w):
            a=px[x,y]; b=px[x,y+1]; d=sum(abs(a[i]-b[i]) for i in range(3))/3
            if d>=EDGE_THRESHOLD: horizontal[y]+=1; h_hits+=1
    v_density=v_hits/max(1,(w-1)*h); h_density=h_hits/max(1,w*(h-1))
    v_bands=[round((i+0.5)/w,4) for i,n in enumerate(vertical) if n/max(1,h)>=0.32]
    h_bands=[round((i+0.5)/h,4) for i,n in enumerate(horizontal) if n/max(1,w)>=0.32]
    return {'vertical_edge_density':round(v_density,4),'horizontal_edge_density':round(h_density,4),'strong_vertical_bands':v_bands[:40],'strong_horizontal_bands':h_bands[:40]}
def analyze(path:Path):
    im,original=resize_rgb(path); stat=ImageStat.Stat(im); means=stat.mean[:3]; std=stat.stddev[:3]
    lum=luminance(means); contrast=sum(std)/3
    status='USABLE'
    reasons=[]
    if min(original)<160: reasons.append('low_resolution')
    if lum<18: reasons.append('too_dark')
    if lum>240: reasons.append('too_bright')
    if contrast<8: reasons.append('low_contrast')
    if reasons: status='LOW_CONFIDENCE'
    result={'analysis_version':'low_level_v1','file':path.name,'original_size':list(original),'analysis_size':list(im.size),'mean_rgb':[round(v,2) for v in means],'mean_luminance':round(lum,2),'mean_channel_stddev':round(contrast,2),'palette':palette(im),'quality_status':status,'quality_reasons':reasons}
    result.update(edge_features(im)); return result

def process_catalog(payload,root:Path):
    rows=[]
    for raw in payload.get('records') or payload.get('images') or []:
        item=dict(raw); name=raw.get('local_file')
        if not name or not (root/name).exists(): item['visual_analysis']={'analysis_version':'low_level_v1','quality_status':'NO_LOCAL_IMAGE','quality_reasons':['local_file_missing']}
        else: item['visual_analysis']=analyze(root/name)
        rows.append(item)
    return rows

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--input',required=True); ap.add_argument('--image-root',required=True); ap.add_argument('--output',required=True); a=ap.parse_args(); payload=json.loads(Path(a.input).read_text(encoding='utf-8')); rows=process_catalog(payload,Path(a.image_root)); usable=sum(r['visual_analysis']['quality_status']=='USABLE' for r in rows)
    out={'format':'grand-bruxelles-reference-image-analysis-v1','semantics':'low-level measurable features only','summary':{'records':len(rows),'usable':usable,'low_confidence':sum(r['visual_analysis']['quality_status']=='LOW_CONFIDENCE' for r in rows),'missing_images':sum(r['visual_analysis']['quality_status']=='NO_LOCAL_IMAGE' for r in rows)},'records':rows}; Path(a.output).write_text(json.dumps(out,indent=2,sort_keys=True,ensure_ascii=False)+'\n',encoding='utf-8'); print('REFERENCE_IMAGE_ANALYSIS_OK',out['summary'])
if __name__=='__main__': main()

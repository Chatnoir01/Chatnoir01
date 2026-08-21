#!/usr/bin/env python3
from __future__ import annotations
import argparse,json
from pathlib import Path
from PIL import Image


def main() -> int:
    ap=argparse.ArgumentParser()
    ap.add_argument('--gate',required=True)
    ap.add_argument('--before-dir',required=True)
    ap.add_argument('--after-dir',required=True)
    ap.add_argument('--output',required=True)
    args=ap.parse_args()
    gate=json.loads(Path(args.gate).read_text())
    if gate.get('schema')!='grand-bruxelles-grand-place-facade-visual-gate-v2':
        raise SystemExit('GRAND_PLACE_FACADE_MULTIVIEW_FAIL: gate schema')
    resolution=gate.get('resolution',[1280,720])
    if not isinstance(resolution,list) or len(resolution)!=2:
        raise SystemExit('GRAND_PLACE_FACADE_MULTIVIEW_FAIL: gate resolution')
    width,height=int(resolution[0]),int(resolution[1])
    if width<=0 or height<=0:
        raise SystemExit('GRAND_PLACE_FACADE_MULTIVIEW_FAIL: gate resolution')
    rows=[]
    failed_views=[]
    for view in gate['views']:
        vid=view['id']
        before=Image.open(Path(args.before_dir)/f'{vid}_before.png').convert('RGB')
        after=Image.open(Path(args.after_dir)/f'{vid}_after.png').convert('RGB')
        if before.size!=(width,height) or after.size!=(width,height):
            raise SystemExit(f'GRAND_PLACE_FACADE_MULTIVIEW_FAIL: size {vid}')
        changed3=changed8=0
        min_x,min_y=width,height
        max_x=max_y=-1
        bp=before.load(); apx=after.load()
        for y in range(height):
            for x in range(width):
                a=bp[x,y]; b=apx[x,y]
                d=max(abs(a[0]-b[0]),abs(a[1]-b[1]),abs(a[2]-b[2]))
                if d>3: changed3+=1
                if d>8:
                    changed8+=1
                    min_x=min(min_x,x); min_y=min(min_y,y); max_x=max(max_x,x); max_y=max(max_y,y)
        total=width*height
        p3=100.0*changed3/total
        p8=100.0*changed8/total
        bw=max_x-min_x+1 if max_x>=min_x else 0
        bh=max_y-min_y+1 if max_y>=min_y else 0
        failed_thresholds=[]
        if p3<float(view['minimum_gt3_percent']): failed_thresholds.append('minimum_gt3_percent')
        if p8<float(view['minimum_gt8_percent']): failed_thresholds.append('minimum_gt8_percent')
        if bw<int(view['minimum_bbox_width']): failed_thresholds.append('minimum_bbox_width')
        if bh<int(view['minimum_bbox_height']): failed_thresholds.append('minimum_bbox_height')
        row={'id':vid,'pass':not failed_thresholds,'failed_thresholds':failed_thresholds,'changed_gt3_percent':p3,'changed_gt8_percent':p8,'bbox_gt8':[min_x,min_y,max_x,max_y],'bbox_width':bw,'bbox_height':bh,'thresholds':{'minimum_gt3_percent':view['minimum_gt3_percent'],'minimum_gt8_percent':view['minimum_gt8_percent'],'minimum_bbox_width':view['minimum_bbox_width'],'minimum_bbox_height':view['minimum_bbox_height']}}
        rows.append(row)
        print(f'GRAND_PLACE_FACADE_MULTIVIEW_METRIC: {vid} >3={p3:.6f}% >8={p8:.6f}% bbox={bw}x{bh} pass={row["pass"]}')
        if failed_thresholds:
            failed_views.append(vid)
    payload={'schema':'grand-bruxelles-grand-place-facade-multiview-result-v1','pass':not failed_views,'camera_position_fixed':True,'fov_fixed':True,'thresholds_frozen_before_first_render':True,'human_full_frame_pass_required':True,'finished_perfect':False,'failed_views':failed_views,'views':rows}
    Path(args.output).write_text(json.dumps(payload,indent=2)+'\n')
    if failed_views:
        print('GRAND_PLACE_FACADE_MULTIVIEW_EVIDENCE_COMPLETE: views=%d failed_views=%s human_review_required=true' % (len(rows),','.join(failed_views)))
        print('GRAND_PLACE_FACADE_MULTIVIEW_FAIL: views=%s'%','.join(failed_views))
        return 1
    print('GRAND_PLACE_FACADE_MULTIVIEW_OK: views=%d human_review_required=true finished_perfect=false'%len(rows))
    return 0

if __name__=='__main__':
    raise SystemExit(main())

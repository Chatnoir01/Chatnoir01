#!/usr/bin/env python3
from __future__ import annotations
import argparse, importlib.util, json
from pathlib import Path
from typing import Any
HERE=Path(__file__).resolve().parent
SPEC=importlib.util.spec_from_file_location('build_manual_frontier_review', HERE/'build_manual_frontier_review.py')
review_mod=importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(review_mod)

def collect(source_root: Path, output_dir: Path) -> dict[str, Any]:
    output_dir.mkdir(parents=True, exist_ok=True)
    ready=[]; pending=[]; failed=[]
    for cell_dir in sorted(p for p in source_root.iterdir() if p.is_dir()):
        h=cell_dir/'building_height_candidates.json'; t=cell_dir/'terrain_lod_evidence.json'
        if not h.exists() or not t.exists():
            pending.append(cell_dir.name); continue
        try:
            result=review_mod.build(h,t)
        except Exception as exc:
            failed.append({'cell_id':cell_dir.name,'error':str(exc)}); continue
        (output_dir/f'{cell_dir.name}.json').write_text(json.dumps(result,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
        ready.append(cell_dir.name)
    return {'format':'grand-bruxelles-citygen-manual-frontier-batch-v1','ready_count':len(ready),'pending_count':len(pending),'failed_count':len(failed),'ready_cells':ready,'pending_cells':pending,'failed_cells':failed,'runtime_promotion_allowed':False}

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--source-root',type=Path,required=True); ap.add_argument('--output-dir',type=Path,required=True); ap.add_argument('--report',type=Path,required=True); args=ap.parse_args()
    report=collect(args.source_root,args.output_dir); args.report.parent.mkdir(parents=True,exist_ok=True); args.report.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    print('CITYGEN_BATCH_MANUAL_FRONTIER_REVIEWS_OK',report['ready_count'],report['pending_count'],report['failed_count'])
if __name__=='__main__': main()

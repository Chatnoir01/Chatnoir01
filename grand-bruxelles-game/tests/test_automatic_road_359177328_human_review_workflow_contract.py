#!/usr/bin/env python3
from pathlib import Path
P=Path(__file__).resolve().parents[1]
W=P.parent/'.github/workflows/grand-bruxelles-automatic-road-359177328-human-review-veto.yml'
PIN='actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2'
def r(c,m):
    if not c: raise SystemExit('HUMAN_REVIEW_WORKFLOW_CONTRACT_FAIL: '+m)
def main():
    t=W.read_text()
    r(PIN in t,'checkout must be immutable-SHA pinned')
    r('actions/checkout@v' not in t,'mutable checkout tag forbidden')
    r('workflow_dispatch:' in t,'manual dispatch missing')
    r('fetch-depth: 0' in t,'full history missing')
    r('git fetch origin main --no-tags' in t,'live main fetch missing')
    r('test "$merge_base" = "$live_main"' in t,'exact live-main merge-base missing')
    r(t.index('- name: Require exact live-main merge base') < t.index('- name: Enforce immutable human REJECT'),'provenance must precede veto')
    print('AUTOMATIC_ROAD_359177328_HUMAN_REVIEW_WORKFLOW_CONTRACT_OK immutable_actions=true')
    return 0
if __name__=='__main__': raise SystemExit(main())

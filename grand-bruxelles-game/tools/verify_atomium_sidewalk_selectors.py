#!/usr/bin/env python3
import json, pathlib

FIRST_E=148002.07966029973
FIRST_N=176998.12603718086
STEP_E=3.8910505836538505
STEP_N=-3.8910505836538505
WIDTH=257
HEIGHT=257
SOURCE=pathlib.Path('artifacts/atomium/atomium_sidewalk_source_lock.game.json')
RUNTIME=pathlib.Path('data/environment/laeken_jette/atomium_sidewalk_context.game.json')

def polygons(g):
    if not isinstance(g,dict): return []
    if g.get('type')=='Polygon': return [g.get('coordinates',[])]
    if g.get('type')=='MultiPolygon': return g.get('coordinates',[])
    return []

def point_in_ring(p,ring):
    x,y=p; inside=False; j=len(ring)-1
    for i in range(len(ring)):
        xi,yi=ring[i][0],ring[i][1]; xj,yj=ring[j][0],ring[j][1]
        if ((yi>y)!=(yj>y)) and x < (xj-xi)*(y-yi)/((yj-yi) if abs(yj-yi)>1e-12 else 1e-12)+xi: inside=not inside
        j=i
    return inside

def point_in_geom(p,g):
    return any(poly and point_in_ring(p,poly[0]) and not any(point_in_ring(p,h) for h in poly[1:]) for poly in polygons(g))

source=json.loads(SOURCE.read_text(encoding='utf-8'))
runtime=json.loads(RUNTIME.read_text(encoding='utf-8'))
if runtime.get('schema') != 1 or runtime.get('format') != 'grand-bruxelles-atomium-sidewalk-dtm-triangle-selectors-v1':
    raise SystemExit('runtime selector schema drift')
sha=source['source']['canonical_geometry_sha256']
if runtime.get('source_geometry_sha256') != sha or runtime.get('source_feature_count') != source.get('feature_count'):
    raise SystemExit('runtime source lock drift')
features=source['features']
expected=[]
for row in range(HEIGHT-1):
    n0=FIRST_N+row*STEP_N; n1=FIRST_N+(row+1)*STEP_N
    for col in range(WIDTH-1):
        e0=FIRST_E+col*STEP_E; e1=FIRST_E+(col+1)*STEP_E
        centroids=[((e0+e0+e1)/3.0,(n0+n1+n0)/3.0),((e1+e0+e1)/3.0,(n0+n1+n1)/3.0)]
        for half,centroid in enumerate(centroids):
            if any(point_in_geom(centroid,f['geometry']) for f in features): expected.append([row,col,half])
actual=runtime.get('selectors',[])
if actual != expected:
    raise SystemExit(f'selector drift: committed={len(actual)} source-derived={len(expected)}')
print(f'ATOMIUM_SIDEWALK_SELECTORS_OK: selectors={len(actual)} sha256={sha}')

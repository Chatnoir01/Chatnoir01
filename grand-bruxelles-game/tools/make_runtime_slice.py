#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, math
from pathlib import Path
from typing import Any
EARTH_RADIUS_M=6_378_137.0
ROAD_PRIORITY={"primary":0,"secondary":1,"tertiary":2,"residential":3,"living_street":4,"service":5,"unclassified":6,"pedestrian":7,"cycleway":8,"footway":9,"path":10}
def project(lat,lon,origin_lat,origin_lon):
    lat0=math.radians(origin_lat); return math.radians(lon-origin_lon)*EARTH_RADIUS_M*math.cos(lat0), -math.radians(lat-origin_lat)*EARTH_RADIUS_M
def point_segment_distance(point,start,end):
    px,pz=point; ax,az=start; bx,bz=end; dx=bx-ax; dz=bz-az; den=dx*dx+dz*dz
    if den<=1e-9:return math.hypot(px-ax,pz-az)
    t=max(0.0,min(1.0,((px-ax)*dx+(pz-az)*dz)/den)); qx=ax+t*dx; qz=az+t*dz; return math.hypot(px-qx,pz-qz)
def corridor_distance(point,anchors): return min(point_segment_distance(point,anchors[i],anchors[i+1]) for i in range(len(anchors)-1))
def min_feature_distance(points,anchors): return min(corridor_distance((float(p[0]),float(p[1])),anchors) for p in points)
def selected_bounds(features):
    points=[]
    for f in features:
        points.extend(f.get("points",[])); points.extend(f.get("footprint",[])); pos=f.get("position")
        if isinstance(pos,list) and len(pos)>=2: points.append(pos)
    if not points:return [0.0,0.0,0.0,0.0]
    xs=[float(p[0]) for p in points]; zs=[float(p[1]) for p in points]; return [round(min(xs),2),round(min(zs),2),round(max(xs),2),round(max(zs),2)]
def select_environment_points(source_points,anchors,radius,max_points):
    candidates=[]
    for point in source_points:
        pos=point.get("position"); kind=str(point.get("kind",""))
        if not isinstance(pos,list) or len(pos)<2 or kind not in {"tree","street_lamp","bollard"}: continue
        distance=corridor_distance((float(pos[0]),float(pos[1])),anchors)
        if distance<=radius: candidates.append(((round(distance,4),kind,int(point.get("osm_id") or 0)),point))
    candidates.sort(key=lambda item:item[0]); return [item[1] for item in candidates[:max_points]]
def select_buildings(source_buildings,anchors,building_radius,max_buildings,required_osm_ids):
    candidates=[]
    for building in source_buildings:
        footprint=building.get("footprint",[])
        if not footprint: continue
        center=(sum(float(p[0]) for p in footprint)/len(footprint),sum(float(p[1]) for p in footprint)/len(footprint)); distance=corridor_distance(center,anchors)
        if distance<=building_radius:candidates.append(((round(distance,4),-float(building.get("area",0.0)),int(building.get("osm_id") or 0)),building))
    candidates.sort(key=lambda item:item[0]); required_ids=list(dict.fromkeys(int(x) for x in required_osm_ids))
    if len(required_ids)>max_buildings: raise ValueError("required hero buildings exceed max-buildings")
    by_id={int(b.get("osm_id") or 0):(k,b) for k,b in candidates}; missing=[x for x in required_ids if x not in by_id]
    if missing: raise ValueError("required OSM hero buildings are absent from the source/corridor: "+", ".join(map(str,missing)))
    req=set(required_ids); selected=[by_id[x] for x in required_ids]+[item for item in candidates if int(item[1].get("osm_id") or 0) not in req]; selected=selected[:max_buildings]; selected.sort(key=lambda item:item[0]); return [item[1] for item in selected]
def required_hero_building_ids(controls): return list(dict.fromkeys(int(r["osm_id"]) for r in controls.get("required_buildings",[])))
def main():
    p=argparse.ArgumentParser(); p.add_argument("--input",type=Path,required=True); p.add_argument("--control-points",type=Path,required=True); p.add_argument("--output",type=Path,required=True); p.add_argument("--road-radius",type=float,default=170.0); p.add_argument("--building-radius",type=float,default=130.0); p.add_argument("--rail-radius",type=float,default=180.0); p.add_argument("--environment-radius",type=float,default=130.0); p.add_argument("--max-roads",type=int,default=140); p.add_argument("--max-buildings",type=int,default=140); p.add_argument("--max-railways",type=int,default=30); p.add_argument("--max-environment-points",type=int,default=1000); args=p.parse_args()
    full=json.loads(args.input.read_text()); controls=json.loads(args.control_points.read_text()); origin_lat=float(full["origin"]["lat"]); origin_lon=float(full["origin"]["lon"]); anchors=[]; anchor_records=[]
    for item in controls.get("points",[]):
        x,z=project(float(item["lat"]),float(item["lon"]),origin_lat,origin_lon); anchors.append((x,z)); anchor_records.append({"id":item["id"],"name":item["name"],"x":round(x,2),"z":round(z,2)})
    if len(anchors)<2: raise SystemExit("need at least two corridor control points")
    rc=[]
    for road in full.get("roads",[]):
        pts=road.get("points",[])
        if pts:
            d=min_feature_distance(pts,anchors)
            if d<=args.road_radius: rc.append(((0 if road.get("drivable") else 1,ROAD_PRIORITY.get(str(road.get("class","")),50),round(d,4),int(road.get("osm_id") or 0)),road))
    rc.sort(key=lambda x:x[0]); roads=[x[1] for x in rc[:args.max_roads]]; buildings=select_buildings(full.get("buildings",[]),anchors,args.building_radius,args.max_buildings,required_hero_building_ids(controls)); rail=[]
    for railway in full.get("railways",[]):
        pts=railway.get("points",[])
        if pts:
            d=min_feature_distance(pts,anchors)
            if d<=args.rail_radius: rail.append(((round(d,4),int(railway.get("osm_id") or 0)),railway))
    rail.sort(key=lambda x:x[0]); railways=[x[1] for x in rail[:args.max_railways]]; env=select_environment_points(full.get("environment_points",[]),anchors,args.environment_radius,args.max_environment_points)
    subset={"format":full.get("format","grand-bruxelles-osm-v1"),"source":full.get("source","OpenStreetMap contributors via Overpass API"),"license":full.get("license","ODbL-1.0"),"origin":full["origin"],"corridor":{"name":"Midi -> Anneessens -> Bourse -> Grand-Place","anchors":anchor_records,"required_buildings":controls.get("required_buildings",[]),"selection_radius_m":{"roads":args.road_radius,"buildings":args.building_radius,"railways":args.rail_radius,"environment_points":args.environment_radius}},"source_stats":full.get("stats",{}),"stats":{"roads":len(roads),"drivable_roads":sum(1 for r in roads if r.get("drivable")),"buildings":len(buildings),"railways":len(railways),"environment_points":len(env)},"roads":roads,"buildings":buildings,"railways":railways,"environment_points":env}; subset["bounds_m"]=selected_bounds(roads+buildings+railways+env); args.output.parent.mkdir(parents=True,exist_ok=True); args.output.write_text(json.dumps(subset,ensure_ascii=False,separators=(",",":"))); print("runtime slice stats:",subset["stats"]); return 0
if __name__=="__main__": raise SystemExit(main())

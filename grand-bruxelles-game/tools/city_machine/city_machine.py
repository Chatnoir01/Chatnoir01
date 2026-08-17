#!/usr/bin/env python3
"""Fail-closed Grand Bruxelles zone rebuild orchestrator."""
from __future__ import annotations
import argparse, hashlib, json, subprocess, sys
from collections import Counter
from pathlib import Path
from typing import Any

HERE=Path(__file__).resolve().parent
PROJECT=HERE.parents[1]
REGISTRY=HERE/"registry.json"
CATALOG=PROJECT/"data/qa/playable_zone_catalog.json"
OSM_SOURCE="OpenStreetMap contributors via Overpass API"
OSM_LICENSE="ODbL-1.0"
OSM_KINDS={"tree","street_lamp","bollard"}

class MachineError(RuntimeError): pass
class GateError(MachineError):
    def __init__(self,gate:str,detail:str): super().__init__(detail); self.gate=gate; self.detail=detail

def read_json(path:Path)->dict[str,Any]:
    try: value=json.loads(path.read_text(encoding="utf-8"))
    except (OSError,json.JSONDecodeError) as exc: raise MachineError(f"cannot read {path}: {exc}") from exc
    if not isinstance(value,dict): raise MachineError(f"expected object: {path}")
    return value

def p(raw:str)->Path:
    path=(PROJECT/raw).resolve(); root=PROJECT.resolve()
    if path!=root and root not in path.parents: raise MachineError(f"path escapes project: {raw}")
    return path

def sha(path:Path)->str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def canonical_digest(value:dict[str,Any])->str:
    raw=json.dumps(value,sort_keys=True,separators=(",",":"),ensure_ascii=False).encode()
    return hashlib.sha256(raw).hexdigest()

def load_registry()->dict[str,Any]:
    r=read_json(REGISTRY)
    if r.get("schema")!="grand-bruxelles-city-machine-registry-v1": raise MachineError("unsupported registry")
    orders=[int(x["order"]) for x in r.get("layers",[])]
    if not orders or orders!=sorted(orders) or len(orders)!=len(set(orders)): raise MachineError("invalid layer order")
    return r

def resolve_zone(catalog:dict[str,Any],zone_id:str)->dict[str,Any]:
    for zone in catalog.get("zones",[]):
        if isinstance(zone,dict) and zone.get("id")==zone_id: return zone
    raise MachineError(f"unknown zone '{zone_id}'")

def source_contract(profile:dict[str,Any])->dict[str,Any]:
    root=p(profile["source_root"]); m=read_json(root/"manifest.json")
    origin=m.get("game_origin") or {}
    if m.get("source_crs")!="EPSG:31370": raise GateError("G1_sources_crs","source CRS is not EPSG:31370")
    if not str(m.get("source_license","")).strip(): raise GateError("G1_sources_crs","source license missing")
    if origin.get("units")!="metres" or origin.get("axes")!="X=east, Y=up, Z=south":
        raise GateError("G1_sources_crs",f"bad game origin {origin}")
    for slug in profile["materialized_slugs"]:
        if not (root/f"{slug}.geojson").is_file(): raise GateError("G1_sources_crs",f"cached source missing: {slug}.geojson")
    return m

def run(command:list[str],label:str)->str:
    r=subprocess.run(command,cwd=PROJECT,text=True,capture_output=True)
    text="\n".join(x.strip() for x in (r.stdout,r.stderr) if x.strip())
    if r.returncode: raise MachineError(f"{label} rc={r.returncode}: {text}")
    if text: print(text)
    return text

def materialize(layer:dict[str,Any],profile:dict[str,Any],m:dict[str,Any])->None:
    root=p(profile["source_root"]); slug=layer["slug"]; origin=m["game_origin"]
    run([sys.executable,str(p(layer["script"])),str(root/f"{slug}.geojson"),str(root/f"{slug}.game.json"),
         "--origin-e",str(origin["e"]),"--origin-n",str(origin["n"]),"--origin-altitude",str(origin["altitude"])],
        f"materialize:{slug}")

def materialize_osm(layer:dict[str,Any],profile:dict[str,Any],zone_id:str)->None:
    env=profile["osm_environment"]
    run([sys.executable,str(p(layer["script"])),
         "--manifest",str(p(profile["source_root"])/"manifest.json"),
         "--zone",zone_id,
         "--raw-cache",str(p(env["cache"])),
         "--output",str(p(env["runtime"]))],
        "materialize:osm_environment")

def gate_g1(layer:dict[str,Any],profile:dict[str,Any])->dict[str,str]:
    r=subprocess.run([sys.executable,str(p(layer["script"])),str(p(profile["source_root"]))],cwd=PROJECT,text=True,capture_output=True)
    text="\n".join(x.strip() for x in (r.stdout,r.stderr) if x.strip())
    if r.returncode: raise GateError("G1_sources_crs",f"existing validator rc={r.returncode}: {text}")
    detail=text.splitlines()[-1] if text else "validator_ok"
    print(f"CITY_MACHINE_GATE PASS G1_sources_crs detail={detail}")
    return {"gate":"G1_sources_crs","status":"PASS","detail":detail}

def game_bounds(m:dict[str,Any])->tuple[float,float,float,float]:
    b=[float(v) for v in m["bbox"]]; o=m["game_origin"]
    xs=(b[0]-float(o["e"]),b[2]-float(o["e"])); zs=(-(b[1]-float(o["n"])),-(b[3]-float(o["n"])))
    return min(xs),min(zs),max(xs),max(zs)

def gate_spawn(zone:dict[str,Any],profile:dict[str,Any],m:dict[str,Any])->dict[str,str]:
    s=zone.get("spawn")
    if not isinstance(s,list) or len(s)<3: raise GateError("G2_spawn_ground","catalog spawn missing")
    x,y,z=map(float,s[:3]); xmin,zmin,xmax,zmax=game_bounds(m)
    if not (xmin<=x<=xmax and zmin<=z<=zmax):
        raise GateError("G2_spawn_ground",f"spawn ({x:.2f},{z:.2f}) outside ({xmin:.2f},{zmin:.2f})..({xmax:.2f},{zmax:.2f})")
    ground=float(profile["ground_contract"]["ground_y"]); clearance=y-ground
    if not .05<=clearance<=5: raise GateError("G2_spawn_ground",f"spawn clearance={clearance:.2f}m")
    detail=f"spawn=({x:.2f},{y:.2f},{z:.2f}) ground_y={ground:.2f} bounds=({xmin:.2f},{zmin:.2f})..({xmax:.2f},{zmax:.2f})"
    print(f"CITY_MACHINE_GATE PASS G2_spawn_ground detail={detail}")
    return {"gate":"G2_spawn_ground","status":"PASS","detail":detail}

def feature_count(path:Path)->int:
    d=read_json(path)
    if d.get("type")!="FeatureCollection" or not isinstance(d.get("features"),list): raise MachineError(f"not FeatureCollection: {path}")
    return len(d["features"])

def gate_content(profile:dict[str,Any],root:Path|None=None)->dict[str,str]:
    root=root or p(profile["source_root"]); mins=profile["content_minimums"]
    b=feature_count(root/"buildings.game.json"); s=feature_count(root/"street_surfaces.game.json")
    if b<int(mins["buildings"]): raise GateError("G3_buildings_streets",f"buildings={b}")
    if s<int(mins["street_surfaces"]): raise GateError("G3_buildings_streets",f"street_surfaces={s}")
    detail=f"buildings={b} street_surfaces={s}"; print(f"CITY_MACHINE_GATE PASS G3_buildings_streets detail={detail}")
    return {"gate":"G3_buildings_streets","status":"PASS","detail":detail}

def gate_finish(layer:dict[str,Any])->dict[str,str]:
    text=p(layer["script"]).read_text(encoding="utf-8")
    missing=[x for x in ("func _make_materials","func _build_ground_reference","func _build_official_geometry") if x not in text]
    if missing: raise GateError("G4_runtime_finish",f"missing hooks {missing}")
    detail=f"runtime={layer['script']} materials+ground+geometry hooks present"
    print(f"CITY_MACHINE_GATE PASS G4_runtime_finish detail={detail}")
    return {"gate":"G4_runtime_finish","status":"PASS","detail":detail}

def gate_osm_environment(zone_id:str,profile:dict[str,Any],m:dict[str,Any],cache_path:Path|None=None,runtime_path:Path|None=None)->dict[str,str]:
    env=profile["osm_environment"]
    cache=read_json(cache_path or p(env["cache"])); runtime=read_json(runtime_path or p(env["runtime"]))
    if cache.get("format")!="grand-bruxelles-osm-zone-environment-cache-v1": raise GateError("G5_osm_environment","bad cache format")
    if runtime.get("format")!="grand-bruxelles-osm-zone-environment-v1": raise GateError("G5_osm_environment","bad runtime format")
    if cache.get("source")!=OSM_SOURCE or runtime.get("source")!=OSM_SOURCE: raise GateError("G5_osm_environment","OSM source mismatch")
    if cache.get("license")!=OSM_LICENSE or runtime.get("license")!=OSM_LICENSE: raise GateError("G5_osm_environment","OSM ODbL license missing")
    if runtime.get("zone")!=zone_id or runtime.get("projection_crs")!="EPSG:31370": raise GateError("G5_osm_environment","zone/projection mismatch")
    if [float(v) for v in runtime.get("bbox_31370",[])]!=[float(v) for v in m["bbox"]]: raise GateError("G5_osm_environment","runtime bbox differs from Jette source bbox")
    expected_digest=canonical_digest(cache)
    if runtime.get("source_digest")!=expected_digest: raise GateError("G5_osm_environment","cache/runtime source digest mismatch")
    points=runtime.get("environment_points")
    if not isinstance(points,list): raise GateError("G5_osm_environment","environment_points missing")
    counts:Counter[str]=Counter()
    xmin,zmin,xmax,zmax=game_bounds(m); tolerance=float(env["bounds_tolerance_m"])
    for point in points:
        if not isinstance(point,dict) or point.get("kind") not in OSM_KINDS: raise GateError("G5_osm_environment","unsupported environment point")
        pos=point.get("position")
        if not isinstance(pos,list) or len(pos)<2: raise GateError("G5_osm_environment","environment point position missing")
        x,z=map(float,pos[:2])
        if not (xmin-tolerance<=x<=xmax+tolerance and zmin-tolerance<=z<=zmax+tolerance):
            raise GateError("G5_osm_environment",f"point {point.get('osm_id')} outside Jette bounds+tolerance")
        counts[str(point["kind"])]+=1
    stats=runtime.get("stats") or {}
    if int(stats.get("total",-1))!=len(points): raise GateError("G5_osm_environment","runtime total/count mismatch")
    for kind in OSM_KINDS:
        if int(stats.get(kind,-1))!=counts[kind] or int((cache.get("counts") or {}).get(kind,-1))!=counts[kind]:
            raise GateError("G5_osm_environment",f"{kind} count mismatch")
    if counts["tree"]<int(env["minimum_trees"]): raise GateError("G5_osm_environment",f"trees={counts['tree']}")
    detail=f"trees={counts['tree']} lamps={counts['street_lamp']} bollards={counts['bollard']} total={len(points)} digest={expected_digest[:16]} bounds_tolerance={tolerance:.1f}m"
    print(f"CITY_MACHINE_GATE PASS G5_osm_environment detail={detail}")
    return {"gate":"G5_osm_environment","status":"PASS","detail":detail}

def runtime_outputs(profile:dict[str,Any])->list[dict[str,Any]]:
    root=p(profile["source_root"])
    outputs=[{"path":str((root/f"{s}.game.json").relative_to(PROJECT)),"sha256":sha(root/f"{s}.game.json"),
              "features":feature_count(root/f"{s}.game.json")} for s in profile["materialized_slugs"]]
    env_path=p(profile["osm_environment"]["runtime"]); env=read_json(env_path)
    outputs.append({"path":str(env_path.relative_to(PROJECT)),"sha256":sha(env_path),"environment_points":int((env.get("stats") or {}).get("total",0)),"trees":int((env.get("stats") or {}).get("tree",0))})
    return outputs

def receipt(zone:dict[str,Any],registry:dict[str,Any],profile:dict[str,Any],m:dict[str,Any],gates:list[dict[str,str]],layers:list[str],out:Path)->Path:
    outputs=runtime_outputs(profile)
    seed={"zone":zone["id"],"registry_version":registry["version"],"manifest":sha(p(profile["source_root"])/"manifest.json"),"runtime_outputs":outputs,"gates":gates}
    build_id=hashlib.sha256(json.dumps(seed,sort_keys=True,separators=(",",":")).encode()).hexdigest()[:16]
    payload={"format":"grand-bruxelles-city-machine-build-v1","build_id":build_id,"zone":zone["id"],"catalog_quality":zone.get("quality"),"result":"LABO_DATA_READY","promotion_performed":False,"registry_version":registry["version"],"source":{"format":m.get("format"),"crs":m.get("source_crs"),"license":m.get("source_license"),"bbox":m.get("bbox")},"executed_layers":layers,"gates":gates,"runtime_outputs":outputs,"disabled_layers":[{"layer_id":x["layer_id"],"reason":x.get("disabled_reason")} for x in registry["layers"] if zone["id"] not in x.get("enabled_zones",[])]}
    out.mkdir(parents=True,exist_ok=True); path=out/f"build-{build_id}.json"
    path.write_text(json.dumps(payload,indent=2,sort_keys=True,ensure_ascii=False)+"\n",encoding="utf-8"); return path

def build(zone_id:str,dry:bool=False,out:Path|None=None)->Path|None:
    registry=load_registry(); catalog=read_json(CATALOG); zone=resolve_zone(catalog,zone_id)
    profile=(registry.get("zone_profiles") or {}).get(zone_id)
    if not profile: raise MachineError(f"zone '{zone_id}' known but not enabled in machine v{registry['version']}")
    m=source_contract(profile); gates=[]; done=[]
    for layer in registry["layers"]:
        if zone_id not in layer.get("enabled_zones",[]): continue
        lid=layer["layer_id"]; kind=layer["kind"]; print(f"CITY_MACHINE_LAYER START {lid}")
        if kind=="resolve_zone": pass
        elif kind=="materialize_geojson":
            if not dry: materialize(layer,profile,m)
        elif kind=="materialize_osm_environment":
            if not dry: materialize_osm(layer,profile,zone_id)
        elif kind=="validate_existing": gates.append(gate_g1(layer,profile))
        elif kind=="gate_spawn_ground": gates.append(gate_spawn(zone,profile,m))
        elif kind=="gate_runtime_content": gates.append(gate_content(profile))
        elif kind=="gate_finish_contract": gates.append(gate_finish(layer))
        elif kind=="gate_osm_environment": gates.append(gate_osm_environment(zone_id,profile,m))
        else: raise MachineError(f"unsupported layer kind '{kind}'")
        done.append(lid); print(f"CITY_MACHINE_LAYER END {lid}")
    if dry:
        print(f"CITY_MACHINE_OK zone={zone_id} mode=dry-run gates={len(gates)} promotion=false"); return None
    path=receipt(zone,registry,profile,m,gates,done,out or PROJECT/"artifacts/city_machine"/zone_id)
    print(f"CITY_MACHINE_OK zone={zone_id} mode=build result=LABO_DATA_READY receipt={path} promotion=false"); return path

def main()->int:
    ap=argparse.ArgumentParser(); sub=ap.add_subparsers(dest="command",required=True); b=sub.add_parser("build")
    b.add_argument("--zone",required=True); b.add_argument("--dry-run",action="store_true"); b.add_argument("--output-dir",type=Path)
    a=ap.parse_args()
    try: build(a.zone,a.dry_run,a.output_dir); return 0
    except GateError as exc: print(f"CITY_MACHINE_GATE FAIL {exc.gate} detail={exc.detail}",file=sys.stderr); return 3
    except MachineError as exc: print(f"CITY_MACHINE_FAIL {exc}",file=sys.stderr); return 2

if __name__=="__main__": raise SystemExit(main())

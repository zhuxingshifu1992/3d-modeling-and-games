"""Validate the actual game collision exports against the building manifest.

Run with Blender, not system Python::

  Blender/blender.exe --background --python tests/validate_regions.py -- --allow-stale

Without --allow-stale, an export older than its generator is a validation
failure. This imports the shipped *_collision.glb meshes. A fresh in-memory
regional model supplies diagnostic mesh names and stair-route samples only;
it is never substituted for exported collision in any physics assertion.
"""
import argparse
import ast
import importlib
import json
import math
import sys
from collections import Counter
from pathlib import Path

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/model'))
MODULES = {'FR_Paris': 'france', 'IT_Rome': 'italy',
           'CH_Alps': 'switzerland', 'DE_Bavaria': 'germany'}


def serial_point(p):
    return [round(float(v), 5) for v in p]


class Surface:
    def __init__(self, vertices, faces, labels):
        self.labels = labels
        self.tree = BVHTree.FromPolygons(vertices, faces, epsilon=.00001)

    def cast(self, origin, direction, distance):
        p, n, index, length = self.tree.ray_cast(Vector(origin), Vector(direction), distance)
        if p is None:
            return None
        return {'point': p, 'normal': n, 'distance': length,
                'mesh': self.labels[index]}

    def segment(self, a, b):
        a, b = Vector(a), Vector(b)
        d = b-a
        if d.length < .000001:
            return None
        return self.cast(a, d.normalized(), d.length)

    def support_down(self, origin, distance):
        hit=self.cast(origin,(0,0,-1),distance)
        if hit and abs(hit['normal'].z)<.05:
            # At an exact tread/floor seam, BVH can report the vertical edge
            # face. A standing capsule is supported by the adjacent surface.
            # Only resolve this zero-normal ambiguity; downward-facing ramps
            # remain failures and are never silently accepted.
            candidates=[]
            for dx,dy in ((.008,0),(-.008,0),(0,.008),(0,-.008)):
                q=self.cast(Vector(origin)+Vector((dx,dy,0)),(0,0,-1),distance)
                if q and abs(q['normal'].z)>.05 and abs(q['point'].z-hit['point'].z)<.045:
                    candidates.append(q)
            if candidates:
                hit=max(candidates,key=lambda q:q['normal'].z)
        return hit


def from_objects(objects):
    vertices, faces, labels = [], [], []
    counts = {}
    for ob in objects:
        if ob.type != 'MESH':
            continue
        offset = len(vertices)
        vertices.extend(ob.matrix_world @ v.co for v in ob.data.vertices)
        faces.extend(tuple(i+offset for i in p.vertices) for p in ob.data.polygons)
        labels.extend([ob.name]*len(ob.data.polygons))
        counts[ob.name] = sum(len(p.vertices)-2 for p in ob.data.polygons)
    if not faces:
        raise RuntimeError('Collision export contains no mesh faces')
    if not all(math.isfinite(c) for p in vertices for c in p):
        raise RuntimeError('Collision export contains non-finite coordinates')
    stats = {'meshes': len(counts), 'vertices': len(vertices),
             'triangles': sum(counts.values()),
             'bounds': [[min(p[k] for p in vertices), max(p[k] for p in vertices)] for k in range(3)],
             'mesh_triangles': counts}
    return Surface(vertices, faces, labels), stats


def from_groups(groups):
    vertices, faces, labels = [], [], []
    for name, g in groups.items():
        if name.startswith('COL_'):
            continue
        offset = len(vertices)
        vertices.extend(g['v'])
        faces.extend(tuple(i+offset for i in f) for f in g['f'])
        labels.extend([name]*len(g['f']))
    return Surface(vertices, faces, labels)


def structural_filter():
    tree = ast.parse((ROOT/'tools/build_world.py').read_text(encoding='utf-8-sig'))
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'structural' for t in node.targets):
            return ast.literal_eval(node.value)
    return {}


def main():
    args = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--allow-stale', action='store_true')
    parser.add_argument('--regions', nargs='*', choices=list(MODULES))
    parser.add_argument('--output', type=Path, default=ROOT/'tests/validate_regions_result.json')
    options = parser.parse_args(args)
    manifest = json.loads((ROOT/'assets/world_manifest.json').read_text(encoding='utf-8-sig'))
    filters = structural_filter()
    report = {'method': 'Imported game collision GLBs; source visual BVH is diagnostic only.',
              'allow_stale': options.allow_stale, 'regions': [], 'failures': []}
    manifest_ids = [b['id'] for b in manifest['buildings']]
    if len(set(manifest_ids)) != len(manifest_ids):
        report['failures'].append({'kind': 'duplicate_building_id'})

    for region in manifest['regions']:
        rid = region['id']
        if options.regions and rid not in options.regions:
            continue
        module_name = MODULES[rid]
        export = ROOT/region['collision'].replace('res://', '')
        checks = {'door_rays': 0, 'wall_flanks': 0, 'support': 0,
                  'headroom_rays': 0, 'stair_flights': 0, 'route_samples': 0}
        record = {'region': rid, 'export': str(export), 'checks': checks,
                  'failures': [], 'visual_advisories': []}
        report['regions'].append(record)

        def fail(kind, label, **data):
            item = {'kind': kind, 'label': label, **data}
            record['failures'].append(item)
            report['failures'].append({'region': rid, **item})

        source_paths = [ROOT/'tools/build_world.py', ROOT/'tools/model/interiors.py',
                        ROOT/'tools/model'/f'{module_name}.py', ROOT/'tools/model/geometry.py']
        newer = [p.name for p in source_paths if p.stat().st_mtime > export.stat().st_mtime]
        record['newer_sources'] = newer
        if newer and not options.allow_stale:
            fail('stale_export', rid, newer_sources=newer)
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=str(export))
        collision, record['collision'] = from_objects(list(bpy.context.scene.objects))

        from geometry import Builder
        class AnyMaterials(dict):
            def __contains__(self, key):
                return True
        builder = Builder(None, AnyMaterials())
        importlib.import_module(module_name).build(builder)
        visual = from_groups(builder.groups)
        source_ids = sorted(b['id'] for b in builder.buildings)
        buildings = [b for b in manifest['buildings'] if b['region'] == rid]
        record['buildings'] = len(buildings)
        if source_ids != sorted(b['id'] for b in buildings):
            fail('catalog_mismatch', rid, source=source_ids, exported=sorted(b['id'] for b in buildings))
        record['copy_filter'] = filters.get(module_name, [])
        expected_groups = ['COL_'+n for n in builder.groups
                           if not n.startswith(('COL_', 'IN_', 'EX_')) and
                           any(k.lower() in n.lower() for k in record['copy_filter'])]
        exported_names = record['collision']['mesh_triangles']
        missing_groups = [n for n in expected_groups if not any(x == n or x.startswith(n+'.') for x in exported_names)]
        record['expected_copy_groups_missing_from_export'] = missing_groups
        if missing_groups:
            fail('collision_groups_missing', rid, groups=missing_groups)

        off = Vector((region['position'][0], -region['position'][2], region['position'][1]))
        def local(p):
            return Vector((p[0], -p[2], p[1]))-off

        def diagnostic(p):
            h = visual.cast(Vector(p)+Vector((0, 0, .35)), (0, 0, -1), 2.5)
            return None if h is None else {'mesh': h['mesh'], 'height': round(h['point'].z, 5)}

        def support(label, p, head=True):
            p = Vector(p)
            checks['support'] += 1
            h = collision.support_down(p+Vector((0, 0, .35)), 2.5)
            if h is None or p.z-h['point'].z > .36 or h['point'].z-p.z > .25:
                fail('unsupported_position', label, point=serial_point(p),
                     collision=None if h is None else {'mesh': h['mesh'], 'height': round(h['point'].z, 5)},
                     visual_source=diagnostic(p))
            elif h['normal'].z < math.cos(math.radians(50)):
                fail('unwalkable_support_slope', label, point=serial_point(p), mesh=h['mesh'],normal_z=round(h['normal'].z,6))
            if head:
                for dx, dy in ((0, 0), (.22, 0), (-.22, 0), (0, .22), (0, -.22)):
                    a=p+Vector((dx,dy,.31)); b=p+Vector((dx,dy,1.84))
                    checks['headroom_rays'] += 1
                    hit = collision.segment(a,b)
                    if hit:
                        fail('blocked_headroom',label,point=serial_point(p),mesh=hit['mesh'])
                        break
                vh=visual.segment(p+Vector((0,0,.31)),p+Vector((0,0,1.84)))
                if vh:
                    record['visual_advisories'].append({'kind':'visual_headroom','label':label,'mesh':vh['mesh'],'point':serial_point(p)})
            return h

        for b in buildings:
            center=local(b['center'])
            for level,floor_z in enumerate(b.get('floor_levels',[])):
                support(b['id']+'_floor_center_'+str(level),Vector((center.x,center.y,floor_z-off.z+.05)))
            if b.get('access') != 'lift':
                a,q=local(b['entrance']),local(b['inside']);delta=q-a
                normal=Vector((-delta.y,delta.x,0)).normalized()
                for lateral in (-.72,0,.72):
                    for height in (.55,1.55,2.55):
                        aa=a+normal*lateral+Vector((0,0,height));bb=q+normal*lateral+Vector((0,0,height))
                        checks['door_rays']+=1;hit=collision.segment(aa,bb)
                        if hit:fail('blocked_door',b['id'],lateral=lateral,height=height,mesh=hit['mesh'])
                for side in (-1,1):
                    checks['wall_flanks']+=1
                    hit=collision.segment(a+normal*(side*1.45)+Vector((0,0,.45)),q+normal*(side*1.45)+Vector((0,0,.45)))
                    if not hit:fail('door_flank_has_no_wall_collision',b['id'],side=side)
                for k in range(9):support(b['id']+'_entry_'+str(k),a+(q-a)*(k/8),head=False)
            else:
                support(b['id']+'_room',local(b['inside']))
            for index,p in enumerate(b.get('stair_landings',[])):
                support(b['id']+'_landing_'+str(index),local(p))

        interactions=[i for i in manifest['interactions'] if i.get('region')==rid and i.get('kind') in ('lift','elevator')]
        record['lift_interactions']=len(interactions)
        for i in interactions:
            support(i['id']+'_source',local(i['position']))
            support(i['id']+'_target',local(i['target']))

        # Source COL stair quads provide route locations; every support/ray
        # assertion below queries only the re-imported collision export.
        for name,g in builder.groups.items():
            if not(name.startswith('COL_') and name.endswith('_Stairs')):
                continue
            for face in g['f']:
                v=[Vector(g['v'][i]) for i in face]
                if len(v)!=4 or max(p.z for p in v)-min(p.z for p in v)<.5:
                    continue
                a=(v[0]+v[1])/2;q=(v[2]+v[3])/2;checks['stair_flights']+=1
                hit=collision.segment(a+Vector((0,0,.95)),q+Vector((0,0,.95)))
                if hit:fail('blocked_stair_flight',name,mesh=hit['mesh'])
                for k in range(6):support(name+'_flight_'+str(k),a+(q-a)*(k/5)+Vector((0,0,.035)),head=False)

        routes=[]
        if rid=='FR_Paris':
            routes=[('Paris_bridge',[(-42,-59.95,.12),(-42,-56.8,1.425),(-42,-44,1.425),(-42,-40.8,.26)])]
        elif rid=='IT_Rome':
            routes=[('Arena_south',[(0,-28,.28),(0,8,.28)]),
                    ('Arena_west',[(-40,8,.28),(0,8,.28)]),
                    ('Arena_east',[(40,8,.28),(0,8,.28)])]
        elif rid=='CH_Alps':
            routes=[('Alpine_bridge',[(46,-20,.08),(49.5,-20,1.12),(60.5,-20,1.12),(64,-20,.08)])]
        elif rid=='DE_Bavaria':
            routes=[('Castle_approach',[(-17,-55,.20),(7,-49,.85),(30,-44,2.65),(43,-34,5.15),(45,-20,7.65),(37,-16,9.35),(31,-24,10.55),(23,-31,11.35),(12,-31,11.95),(8,-27,12.16),(8,-19,12.34)])]
        for label,points in routes:
            previous=None
            for a,q in zip(points,points[1:]):
                a,q=Vector(a),Vector(q);steps=max(2,math.ceil((q-a).length/.4))
                for k in range(steps):
                    p=a+(q-a)*(k/steps);checks['route_samples']+=1
                    h=collision.support_down(p+Vector((0,0,1.5)),3)
                    if not h or abs(h['point'].z-p.z)>.9:
                        fail('route_support_missing',label,point=serial_point(p));continue
                    if h['normal'].z<math.cos(math.radians(50)):
                        fail('route_support_normal',label,point=serial_point(h['point']),mesh=h['mesh'],normal_z=round(h['normal'].z,6))
                    if previous and (h['point']-previous).length>.01:
                        dz=abs(h['point'].z-previous.z)
                        run=math.hypot(h['point'].x-previous.x,h['point'].y-previous.y)
                        if dz>.30 and dz/max(run,.001)>1.1:
                            fail('route_height_discontinuity',label,point=serial_point(h['point']),height_change=round(dz,4))
                        obstacle=collision.segment(previous+Vector((0,0,.95)),h['point']+Vector((0,0,.95)))
                        if obstacle:
                            fail('route_obstruction',label,point=serial_point(h['point']),mesh=obstacle['mesh'])
                    previous=h['point']
        print('REGION_COLLISION_QA',rid,json.dumps({'buildings':len(buildings),'checks':checks,'failures':len(record['failures'])}),flush=True)

    report['passed']=not report['failures']
    report['checked_buildings']=sum(r['buildings'] for r in report['regions'])
    options.output.parent.mkdir(exist_ok=True,parents=True)
    options.output.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print('VALIDATION_REPORT',str(options.output),'PASS' if report['passed'] else 'FAIL',flush=True)
    if report['failures']:
        print('FAILURE_SUMMARY',json.dumps(dict(Counter(x['kind'] for x in report['failures']))),flush=True)
        print('FIRST_FAILURES',json.dumps(report['failures'][:12],ensure_ascii=True),flush=True)
        raise SystemExit(1)


if __name__=='__main__':
    main()

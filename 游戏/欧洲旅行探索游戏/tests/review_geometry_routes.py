"""Independent exported-GLB check of route support, spawns and Eiffel lift.

Run using Blender --background --factory-startup --python-exit-code 1
    --python tests/review_geometry_routes.py
No model, manifest or exported asset is modified.
"""
import contextlib
import io
import json
from pathlib import Path

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT / 'assets/world_manifest.json').read_text(encoding='utf-8'))
vertices, polygons, owners = [], [], []
sources = [(r['collision'], (r['position'][0], -r['position'][2], r['position'][1]))
           for r in manifest['regions']]
sources.append((manifest['world_collision'], (0, 0, 0)))
for relative, offset in sources:
    previous = set(bpy.data.objects)
    with contextlib.redirect_stdout(io.StringIO()):
        bpy.ops.import_scene.gltf(filepath=str(ROOT / relative.removeprefix('res://')))
    for obj in set(bpy.data.objects) - previous:
        if obj.type != 'MESH':
            continue
        start = len(vertices)
        vertices.extend(tuple(obj.matrix_world @ v.co + Vector(offset))
                        for v in obj.data.vertices)
        polygons.extend(tuple(start + i for i in p.vertices) for p in obj.data.polygons)
        owners.extend([obj.name] * len(obj.data.polygons))

tree = BVHTree.FromPolygons(vertices, polygons)
failures = []
results = {'spawns': [], 'stamps': [], 'routes': [], 'lift': None}


def feet_support(game_point):
    point = Vector((game_point[0], -game_point[2], game_point[1]))
    hit = tree.ray_cast(point + Vector((0, 0, 3)), Vector((0, 0, -1)), 8)
    return {'feet': list(game_point), 'ground': hit[0].z if hit[0] else None,
            'gap': point.z - hit[0].z if hit[0] else None,
            'mesh': owners[hit[2]] if hit[0] else None}


for name, p in [('new_game', manifest['spawn'])] + [(r['id'], r['spawn']) for r in manifest['regions']]:
    item = feet_support(p)
    item['id'] = name
    results['spawns'].append(item)
    if item['gap'] is None or not -.005 <= item['gap'] <= .35:
        failures.append(('spawn_support', item))

for stamp in manifest['landmarks']:
    item = feet_support(stamp['position'])
    item['id'] = stamp['id']
    results['stamps'].append(item)
    if item['gap'] is None or not -.005 <= item['gap'] <= .4:
        failures.append(('stamp_support', item))

# World Blender coordinates; the Seine route includes both sloping bridge ends.
routes = [('FR_Seine_connection', -132, 20, 45), ('CH_south_connection', -90, -147, -136),
          ('IT_south_connection', 90, 23, 36), ('DE_south_connection', 73, -147, -137)]
for name, x, begin, end in routes:
    points = []
    for index in range(round((end - begin) * 4) + 1):
        y = begin + index / 4
        hit = tree.ray_cast(Vector((x, y, 5)), Vector((0, 0, -1)), 7)
        if hit[0] is None:
            failures.append(('road_no_collision', name, x, y))
        else:
            points.append((y, hit[0].z))
    steps = [abs(a[1] - b[1]) for a, b in zip(points, points[1:])]
    item = {'id': name, 'samples': len(points), 'max_quarter_meter_height_change': max(steps),
            'minimum_z': min(p[1] for p in points), 'maximum_z': max(p[1] for p in points)}
    results['routes'].append(item)
    if max(steps) > .261:
        failures.append(('road_height_jump', item))

lift = next(i for i in manifest['interactions'] if i['id'] == 'fr_tower_lift')
results['lift'] = feet_support(lift['target'])
if results['lift']['gap'] is None or not -.005 <= results['lift']['gap'] <= .20:
    failures.append(('eiffel_lift_no_landing', results['lift']))

results['failures'] = failures
print('EXPORTED_ROUTE_REVIEW ' + json.dumps(results, ensure_ascii=False))
assert not failures, failures

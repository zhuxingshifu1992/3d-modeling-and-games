"""Read an acquired model without running its embedded scripts; no source edits."""
import bpy
import json
import argparse
import sys
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=ROOT / 'source/external/rx78_blendkit/Gundam_RX-78-2_AnonmalyFound.blend')
parser.add_argument('--output-dir', type=Path, default=ROOT / 'previews/external_rx78')
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
OUT = args.output_dir
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(args.source), use_scripts=False)
report = {'source': str(args.source), 'objects': [], 'images': [], 'materials': [], 'embedded_text_names': list(bpy.data.texts.keys()), 'libraries': [{'path': x.filepath, 'missing': x.is_missing} for x in bpy.data.libraries]}
for obj in bpy.data.objects:
    row = {'name': obj.name, 'type': obj.type, 'location': list(obj.location), 'rotation': list(obj.rotation_euler), 'scale': list(obj.scale), 'dimensions': list(obj.dimensions), 'parent': obj.parent.name if obj.parent else None}
    if obj.type == 'MESH':
        obj.data.calc_loop_triangles()
        pts = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
        row.update(vertices=len(obj.data.vertices), polygons=len(obj.data.polygons), triangles=len(obj.data.loop_triangles), uv_layers=list(obj.data.uv_layers.keys()), materials=[m.name if m else None for m in obj.data.materials], bounds_min=[min(p[i] for p in pts) for i in range(3)], bounds_max=[max(p[i] for p in pts) for i in range(3)], modifiers=[{'name':m.name,'type':m.type} for m in obj.modifiers])
    elif obj.type == 'ARMATURE':
        row['bones'] = list(obj.data.bones.keys())
    report['objects'].append(row)
for img in bpy.data.images:
    report['images'].append({'name': img.name, 'size': list(img.size), 'packed': bool(img.packed_file), 'path': img.filepath, 'source': img.source})
for mat in bpy.data.materials:
    row = {'name': mat.name, 'use_nodes': mat.use_nodes}
    if mat.node_tree:
        row['nodes'] = [{'name': n.name, 'type': n.type, 'image': n.image.name if n.type == 'TEX_IMAGE' and n.image else None} for n in mat.node_tree.nodes]
        row['links'] = [{'from': l.from_node.name + ':' + l.from_socket.name, 'to': l.to_node.name + ':' + l.to_socket.name} for l in mat.node_tree.links]
    report['materials'].append(row)
(OUT / 'inspection.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print('MODEL_INSPECTION_COMPLETE', OUT / 'inspection.json')

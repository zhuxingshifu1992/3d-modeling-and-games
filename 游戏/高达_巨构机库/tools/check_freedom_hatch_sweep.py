"""CPU hatch sweep against the actual exported game: body, bridge and cabin."""
from pathlib import Path
import bpy, json, math, hashlib
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[1]
ASSET=ROOT/'assets/models/freedom_refined.glb'
REPORT=ROOT/'previews/refined_freedom/full_body_hatch_sweep.json'
manifest=json.loads((ROOT/'previews/refined_freedom_game/export_manifest.json').read_text(encoding='utf-8'))
assert manifest['source_model_sha256']==hashlib.sha256(ASSET.read_bytes()).hexdigest()
assert manifest['catalog_sha256']==hashlib.sha256((ROOT/'scripts/catalog.gd').read_bytes()).hexdigest()
assert manifest['bay_script_sha256']==hashlib.sha256((ROOT/'scripts/bay.gd').read_bytes()).hexdigest()
profile=manifest['cockpit']
def state_path(name):
    record=manifest['states'][name]
    p=ROOT/record['glb_path'].removeprefix('res://')
    assert hashlib.sha256(p.read_bytes()).hexdigest()==record['glb_sha256']
    return p
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(state_path('closed')))
hatch=next(o for o in bpy.context.scene.objects if o.type=='MESH' and o.name.startswith('CockpitHatch'))
def triangles(o):
    o.data.calc_loop_triangles()
    return [tuple(t.vertices) for t in o.data.loop_triangles]
def fixed_geometry(excluded):
    vertices=[];faces=[]
    for o in bpy.context.scene.objects:
        if o.type!='MESH' or o==excluded:continue
        offset=len(vertices);vertices.extend(o.matrix_world@v.co for v in o.data.vertices)
        faces.extend(tuple(offset+i for i in t) for t in triangles(o))
    return vertices,faces
bodyverts,bodytris=fixed_geometry(hatch)
hatchtris=triangles(hatch)
fixed=BVHTree.FromPolygons(bodyverts,bodytris,all_triangles=True,epsilon=0)
rest=hatch.matrix_world.copy();rows=[];examples=[]
for i in range(181):
    amount=i/180
    extension=profile['hatch_travel']*min(amount/.25,1)
    angle=math.radians(profile['hatch_angle'])*max(0,min((amount-.25)/.75,1))
    matrix=rest@Matrix.Translation((0,extension,0))@Matrix.Rotation(angle,4,'X')
    vertices=[matrix@v.co for v in hatch.data.vertices]
    moving=BVHTree.FromPolygons(vertices,hatchtris,all_triangles=True,epsilon=0)
    pairs=moving.overlap(fixed)
    rows.append({'amount':round(amount,6),'overlap_pairs':len(pairs)})
    if pairs and (i in [0,45,90,135,180] or (amount>=.25 and len(examples)<5)):
        h,b=pairs[0]
        examples.append({'amount':amount,'hatch_triangle':[list(vertices[j]) for j in hatchtris[h]],'body_triangle':[list(bodyverts[j]) for j in bodytris[b]]})
after=[r for r in rows if r['amount']>=.25 and r['overlap_pairs']]
moving_contacts=[r for r in rows if r['amount']>0 and r['overlap_pairs']]
# The retractable docking step appears only after the hatch is fully open.
# Use the actual exported open state to include that geometry in its one
# production-visible pose, instead of treating it as fixed during the sweep.
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(state_path('open')))
open_hatch=next(o for o in bpy.context.scene.objects if o.type=='MESH' and o.name.startswith('CockpitHatch'))
ov,of=fixed_geometry(open_hatch)
open_pairs=BVHTree.FromPolygons([open_hatch.matrix_world@v.co for v in open_hatch.data.vertices],triangles(open_hatch),all_triangles=True).overlap(BVHTree.FromPolygons(ov,of,all_triangles=True))
report={'asset_sha256':hashlib.sha256(ASSET.read_bytes()).hexdigest(),'profile':profile,
        'catalog_sha256':manifest['catalog_sha256'],'bay_script_sha256':manifest['bay_script_sha256'],
        'method':'181 sampled positions against actual exported game fixed meshes, including bridge and cabin. Fully open state additionally includes docking step. Initial authored closed contacts reported separately.',
        'limitations':['Discrete poses do not prove continuous clearance between samples.','Does not test an articulated driver; separate Godot capsule and transfer tests cover that scope.'],
        'initial_closed_contacts':rows[0]['overlap_pairs'],'moving_contact_poses':len(moving_contacts),'after_slide_contact_poses':len(after),
        'final_open_contacts':len(open_pairs),'samples':rows,'examples':examples,
        'status':'passed' if not moving_contacts and not open_pairs else 'failed'}
REPORT.write_text(json.dumps(report,indent=2),encoding='utf-8')
print('FREEDOM_FULL_BODY_HATCH_SWEEP',report['status'],'initial',report['initial_closed_contacts'],'moving_poses',len(moving_contacts),'after_slide',len(after),'final',report['final_open_contacts'],flush=True)
if moving_contacts or open_pairs:raise RuntimeError('Hatch intersects game geometry while moving; inspect report.')

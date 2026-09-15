import bpy, json
from pathlib import Path
BASE=Path(__file__).resolve().parents[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
for cat,name in [('Professions','Sports_Female_01'),('Adults','Female_Adult_17'),('Adults','Female_Adult_12')]:
    p=BASE/'source/rider/originals'/cat/name/'Export'/f'{name}.fbx'
    if not p.exists(): continue
    before=set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=str(p),use_anim=False)
    objs=[o for o in bpy.data.objects if o not in before]
    data=[]
    for o in objs:
        d={'name':o.name,'type':o.type,'loc':list(o.location),'scale':list(o.scale),'rot':list(o.rotation_euler),'dimensions':list(o.dimensions)}
        if o.type=='MESH':
            d.update(vertices=len(o.data.vertices),polys=len(o.data.polygons),materials=[m.name for m in o.data.materials],bounds=[list(v) for v in o.bound_box])
        if o.type=='ARMATURE':
            d['bones']=[{'name':b.name,'head':list(b.head_local),'tail':list(b.tail_local),'parent':b.parent.name if b.parent else None} for b in o.data.bones]
        data.append(d)
    (BASE/'source/rider'/f'{name}_inspect.json').write_text(json.dumps(data,indent=2))
    for o in objs:o.name=name+'__'+o.name
bpy.ops.wm.save_as_mainfile(filepath=str(BASE/'source/rider/inspection.blend'))
print('INSPECTION_DONE')

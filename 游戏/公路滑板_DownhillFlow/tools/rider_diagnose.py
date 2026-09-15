import bpy,json
from pathlib import Path
BASE=Path(__file__).resolve().parents[1]
code=(BASE/'tools/rider_build.py').read_text().split('def png_image')[0]
exec(code)
report={}
for arm,obj in [(rig,body),(tee_rig,tee),(shorts_rig,shorts)]:
    groups={g.index:g.name for g in obj.vertex_groups}
    stats={}
    for v in obj.data.vertices:
        if not v.groups:continue
        g=groups[max(v.groups,key=lambda g:g.weight).group]
        stats.setdefault(g,[]).append(list(v.co))
    report[obj.name]={'materials':[m.name for m in obj.data.materials], 'material_counts':{i:sum(p.material_index==i for p in obj.data.polygons) for i in range(len(obj.data.materials))}, 'bones':{b.name:[list(b.head_local),list(b.tail_local)] for b in arm.data.bones},'groups':{k:{'n':len(v),'min':list(np.min(v,axis=0)),'max':list(np.max(v,axis=0))} for k,v in stats.items()}}
(BASE/'source/rider/diagnosis.json').write_text(json.dumps(report,indent=2))
print('DIAGNOSIS_DONE')
for ob in bpy.context.scene.objects:
    if ob not in [body,rig]:ob.hide_render=True
for i,part in enumerate(['body','head']):
    mat=bpy.data.materials.new(part);mat.use_nodes=True
    tex=mat.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image=bpy.data.images.load(str(BASE/'source/rider/originals/Professions/Sports_Female_01/Textures'/f'f021_{part}_color.png'))
    mat.node_tree.links.new(tex.outputs['Color'],mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
    body.data.materials[i]=mat
s=bpy.context.scene;s.render.engine='CYCLES';s.cycles.device='CPU';s.cycles.samples=12;s.cycles.use_denoising=True
s.render.resolution_x=520;s.render.resolution_y=700;s.render.resolution_percentage=100
s.world=bpy.data.worlds.new('DiagnosticWorld');s.world.color=(.5,.5,.5)
for loc in [(3,-4,5),(-3,4,4)]:
    bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.data.energy=500;o.data.size=4;o.rotation_euler=(Vector((0,0,.8))-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add();cam=bpy.context.object;s.camera=cam;cam.data.lens=65
for side in [-1,1]:
    cam.location=(.2,side*3.4,1.3);cam.rotation_euler=(Vector((0,.02,.95))-cam.location).to_track_quat('-Z','Y').to_euler()
    s.render.filepath=str(BASE/'source/rider'/f'rest_{side}.png');bpy.ops.render.render(write_still=True)

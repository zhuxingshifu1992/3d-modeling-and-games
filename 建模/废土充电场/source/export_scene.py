"""Export evaluated geometry, grouped by component, without altering the .blend."""
import bpy,json,sys,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'废土充电场.blend'))
bpy.context.view_layer.update();dep=bpy.context.evaluated_depsgraph_get()
out=bpy.data.collections.new('GLB delivery geometry');bpy.context.scene.collection.children.link(out)
groups={}
sources=[o for o in bpy.context.scene.objects if o.type in ('MESH','CURVE','FONT') and not o.hide_render and o.name!='Horizon ground']
for index,ob in enumerate(sources):
    if index%300==0:print('CONVERT',index,'/',len(sources),flush=True)
    ev=ob.evaluated_get(dep)
    me=bpy.data.meshes.new_from_object(ev,preserve_all_data_layers=True,depsgraph=dep)
    if not me.vertices:bpy.data.meshes.remove(me);continue
    clone=bpy.data.objects.new(ob.name,me);out.objects.link(clone);clone.matrix_world=ob.matrix_world.copy()
    group=ob.users_collection[0].name if ob.users_collection else 'Other'
    groups.setdefault(group,[]).append(clone)
bpy.ops.object.select_all(action='DESELECT')
joined=[]
for name,obs in groups.items():
    for o in obs:o.select_set(True)
    bpy.context.view_layer.objects.active=obs[0]
    bpy.ops.object.join();combined=bpy.context.object;combined.name=name
    combined['component']=name;joined.append(combined)
    bpy.ops.object.select_all(action='DESELECT')
for ob in joined:ob.select_set(True)
path=ROOT/'exports'/'废土充电场.glb'
bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_cameras=False,export_lights=False,export_extras=True,export_image_format='AUTO',export_materials='EXPORT')
print('GLB_EXPORT_OK',path.stat().st_size,'bytes',len(joined),'component meshes',flush=True)

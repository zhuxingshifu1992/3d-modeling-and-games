"""Build, save and export the reference-based 3D environment reproducibly."""
import bpy,sys,math,json,time
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'source'))
from common import *

def camera(name,loc,target,lens):
    data=bpy.data.cameras.new(name);ob=bpy.data.objects.new(name,data);bpy.context.scene.collection.objects.link(ob)
    ob.location=loc;ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler();data.lens=lens;data.clip_end=3000
    return ob

def area(name,loc,target,color,power,size):
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.color=color;data.shape='DISK';data.size=size
    ob=bpy.data.objects.new(name,data);bpy.context.scene.collection.objects.link(ob);ob.location=loc;ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler()
    return ob

bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
for c in list(bpy.data.collections):
    if not c.objects:bpy.data.collections.remove(c)
scene=bpy.context.scene;scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
scene.render.engine='CYCLES';scene.cycles.samples=32;scene.cycles.use_denoising=True
scene.cycles.max_bounces=5;scene.cycles.diffuse_bounces=3;scene.cycles.glossy_bounces=3
scene.render.resolution_x=1600;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.film_transparent=False
scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast';scene.view_settings.exposure=.2
scene.render.threads_mode='FIXED';scene.render.threads=8
print('BUILD materials',flush=True);create_materials()
for name in ['architecture','equipment','vehicles','environment']:
    print('BUILD '+name,flush=True);module=__import__(name);module.build()

collection('08_Lighting and photographic cameras')
world=bpy.data.worlds.new('Late afternoon dust haze');world.use_nodes=True;scene.world=world
nt=world.node_tree;bg=nt.nodes.get('Background');bg.inputs['Strength'].default_value=.22
sky=nt.nodes.new('ShaderNodeTexSky');sky.sky_type='MULTIPLE_SCATTERING';sky.sun_elevation=math.radians(17);sky.sun_rotation=math.radians(215);sky.sun_disc=False
nt.links.new(sky.outputs['Color'],bg.inputs['Color'])
ld=bpy.data.lights.new('Warm sun through dusty clouds','SUN');ld.energy=3.0;ld.angle=.14;ld.color=(1,.82,.64)
lo=bpy.data.objects.new('Warm sun through dusty clouds',ld);scene.collection.objects.link(lo);lo.rotation_euler=(math.radians(58),math.radians(-24),math.radians(-40))
area('Soft open sky fill',(0,-7,18),(0,4,0),(.80,.84,.86),1200,22)
area('Last working canopy tube',(-7,1,3.6),(-7,1,0),(.30,1,.74),55,2.2)
area('Vending spill',(-7,-3,1.6),(-4,-4,0),(.38,.8,1),24,1)
area('Office security light',(10,-2.65,3),(10,-7,0),(1,.55,.20),45,1)
cameras={
    '01_总览':((33,-43,27),(0,4,1.7),41),
    '02_入口复刻':((0,-25,3.1),(3.5,3,2.4),31),
    '03_充电区':((1,-8,3.3),(-8,5.8,1.7),35),
    '04_工程车':((22,-7,4.2),(12,13,1.7),40),
    '05_生活角落':((-3.2,-9,2.9),(-8,-2.6,1.2),43),
}
for key,(loc,target,lens) in cameras.items():camera(key,loc,target,lens)
scene.camera=bpy.data.objects['01_总览']
# Reference photographs are omitted from the public edition.
scene['project_title']='最后一度电 · 废土充电场'
scene['reference_notes']='Public stylized industrial scene; approximate dimensions.'
scene['source_folder']='//source'
for ob in bpy.context.selected_objects:ob.select_set(False)
for screen in bpy.data.screens:
    for ar in screen.areas:
        if ar.type=='VIEW_3D':
            ar.spaces.active.region_3d.view_perspective='CAMERA';ar.spaces.active.clip_end=3000
            ar.spaces.active.shading.type='SOLID';ar.spaces.active.shading.color_type='MATERIAL'
            ar.spaces.active.shading.light='STUDIO';ar.spaces.active.shading.show_cavity=True
            ar.spaces.active.overlay.show_overlays=False
bpy.ops.file.pack_all()
scene.render.filepath=str(ROOT/'renders'/'01_总览.png')
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'废土充电场.blend'))
print('SAVED NATIVE',flush=True)
stats={'objects':len(scene.objects),'mesh_objects':sum(o.type=='MESH' for o in scene.objects),'vertices':sum(len(o.data.vertices) for o in scene.objects if o.type=='MESH'),'faces':sum(len(o.data.polygons) for o in scene.objects if o.type=='MESH'),'materials':len(bpy.data.materials),'cameras':list(cameras),'reference_images':0}
(ROOT/'docs'/'scene_stats.json').write_text(json.dumps(stats,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(stats,ensure_ascii=False),flush=True)
if '--export' in sys.argv:
    bpy.ops.object.select_all(action='DESELECT')
    for ob in scene.objects:
        if ob.type in ('MESH','CURVE','FONT') and not ob.hide_render and ob.name!='Horizon ground':
            ob.hide_set(False);ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(ROOT/'exports'/'废土充电场.glb'),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_cameras=False,export_lights=False,export_extras=True)
    print('EXPORTED GLB',flush=True)
print('BUILD COMPLETE',flush=True)

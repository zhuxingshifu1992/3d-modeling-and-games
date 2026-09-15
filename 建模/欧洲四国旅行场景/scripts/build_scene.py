"""Run: blender --background --python scripts/build_scene.py -- [--quick] [--only france]."""
import bpy, sys, math, json, struct, importlib, time, argparse
from pathlib import Path
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
from geometry import Builder, material_library

parser=argparse.ArgumentParser();parser.add_argument('--only',default='');parser.add_argument('--quick',action='store_true');parser.add_argument('--skip-render',action='store_true')
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
REGIONS=[('france','FR_Paris',(-80,72,0)),('italy','IT_Rome',(80,72,0)),('switzerland','CH_Alps',(-80,-72,0)),('germany','DE_Bavaria',(80,-72,0))]
if args.only:REGIONS=[(a,b,(0,0,0)) for a,b,c in REGIONS if a==args.only]

def log(s):print('EUROPE | '+s,flush=True)
def collection(name):
    c=bpy.data.collections.new(name);bpy.context.scene.collection.children.link(c);return c
def select(objects):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects:ob.select_set(True)
    if objects:bpy.context.view_layer.objects.active=objects[0]
def triangles(obs):
    return sum(sum(max(0,len(p.vertices)-2) for p in o.data.polygons) for o in obs if o.type=='MESH')
def exported_triangles(path):
    with open(path,'rb') as f:
        f.read(12);size,kind=struct.unpack('<II',f.read(8));doc=json.loads(f.read(size))
    return sum(doc['accessors'][p['indices']]['count']//3 for mesh in doc.get('meshes',[]) for p in mesh['primitives'] if p.get('mode',4)==4)
def point_camera(ob,target):ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler()
def camera(name,loc,target,lens=48,ortho=None):
    data=bpy.data.cameras.new(name);ob=bpy.data.objects.new(name,data);bpy.context.scene.collection.objects.link(ob);ob.location=loc;point_camera(ob,target)
    data.lens=lens;data.clip_end=3000
    if ortho:data.type='ORTHO';data.ortho_scale=ortho
    return ob
def export_glb(obs,path):
    select(obs)
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_texcoords=True,export_normals=True,export_materials='EXPORT',export_extras=True,export_cameras=False,export_lights=False,export_yup=True)
def export_fbx(obs,path):
    select(obs)
    bpy.ops.export_scene.fbx(filepath=str(path),use_selection=True,object_types={'MESH'},apply_unit_scale=True,apply_scale_options='FBX_SCALE_UNITS',axis_forward='-Z',axis_up='Y',bake_anim=False,path_mode='COPY',embed_textures=True,use_mesh_modifiers=True)

start=time.time();bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene;scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=12 if args.quick else 28
scene.cycles.use_denoising=True;scene.cycles.max_bounces=5;scene.cycles.diffuse_bounces=3;scene.cycles.glossy_bounces=3
scene.render.resolution_x=1000 if args.quick else 1600;scene.render.resolution_y=750 if args.quick else 1200;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.film_transparent=False
scene.world=bpy.data.worlds.new('European_Daylight');scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.60,.72,.88,1);scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.45
scene.view_settings.view_transform='AgX'
sun_data=bpy.data.lights.new('Late_Morning_Sun','SUN');sun_data.energy=3.2;sun_data.angle=math.radians(8)
sun=bpy.data.objects.new('Late_Morning_Sun',sun_data);scene.collection.objects.link(sun);sun.rotation_euler=(math.radians(27),math.radians(-22),math.radians(-28))
log('Generating portable texture library');mats=material_library(ROOT/'textures')
all_objects=[];metadata={};region_objects={};region_cols={}
for module,name,offset in REGIONS:
    log('Building '+name);col=collection(name);B=Builder(col,mats,offset)
    B.box(name+'_Ground',(0,0,-.8),(140,120,1.6),'grass' if module!='italy' else 'gravel')
    meta=importlib.import_module(module).build(B)
    obs=B.finish()
    all_objects.extend(obs);region_objects[module]=obs;region_cols[module]=col
    meta.update({'collection':name,'world_offset':list(offset),'mesh_objects':len(obs),'triangles_LOD0':triangles(obs),'units':'meters','ground_extent':[140,120]})
    metadata[module]=meta;log(name+' created: '+str(len(obs))+' objects / '+str(meta['triangles_LOD0'])+' triangles')

# Export at local origins for reusable game scenes; Blender presentation keeps district offsets.
if not args.quick:
    for module,name,offset in REGIONS:
        obs=region_objects[module]
        for ob in obs:ob.location-=Vector(offset)
        log('Exporting '+name+' LOD0 GLB and FBX')
        export_glb(obs,ROOT/'exports'/(name+'.glb'));export_fbx(obs,ROOT/'exports'/(name+'.fbx'))
        # Evaluation applies simplification only to a duplicate; editable source stays detailed.
        lodcol=collection(name+'_LOD1_EXPORT');lod=[]
        for ob in obs:
            du=ob.copy();du.data=ob.data.copy();du.name=ob.name+'_LOD1';lodcol.objects.link(du)
            if len(du.data.polygons)>100:
                select([du]);mod=du.modifiers.new('Game_Simplification','DECIMATE');mod.ratio=.38
                bpy.ops.object.modifier_apply(modifier=mod.name)
            lod.append(du)
        export_glb(lod,ROOT/'exports'/(name+'_LOD1.glb'))
        metadata[module]['triangles_LOD1']=exported_triangles(ROOT/'exports'/(name+'_LOD1.glb'))
        for ob in lod:bpy.data.objects.remove(ob,do_unlink=True)
        bpy.data.collections.remove(lodcol)
        for ob in obs:ob.location+=Vector(offset)

# Independent static collision proxies: intentional structural surfaces, no visual detail clutter.
if not args.quick:
    for module,name,offset in REGIONS:
        source=region_objects[module];c=collection(name+'_Collision_Proxies');proxies=[]
        candidates={
          'france':['Ground','Footings','Esplanade','Walk','Quay','Bridge','Haussmann_Stone'],
          'italy':['Ground','Arena','Seating','Stairs','Arch','Spandrels','Piers','Pier','Cornices','Attic','Piazza','Plaza','Facade','Wall','Footing','Steps'],
          'switzerland':['Ground','Terrain','Mountain','Rock','Trail','Path','Lanes','Bridge','Foundation','Walls','Wall','Church'],
          'germany':['Ground','Terrain','Hill','Rock','Path','Road','Ramp','Courtyard','Palace','Wall','Gate','Foundation','Tower_Shaft','Tower_Masonry','Battlements']
        }[module]
        for ob in source:
            if not any(key.lower() in ob.name.lower() for key in candidates):continue
            du=ob.copy();du.data=ob.data.copy();du.name='COLLIDER_'+ob.name;c.objects.link(du);du.location-=Vector(offset)
            du.data.materials.clear();du['role']='static_triangle_collision_proxy';du['render_in_game']=False
            proxies.append(du)
        export_glb(proxies,ROOT/'exports'/(name+'_Collision.glb'))
        metadata[module]['collision_triangles']=exported_triangles(ROOT/'exports'/(name+'_Collision.glb'))
        for ob in proxies:ob.location+=Vector(offset);ob.hide_render=True;ob.hide_set(True);ob.display_type='WIRE'
        c.hide_render=True

if not args.quick:
    log('Exporting combined world GLB')
    export_glb(all_objects,ROOT/'exports'/'Europe_Travel_All.glb')

camera_offsets={'france':((133,-191,131),(0,3,37)), 'italy':((117,-164,124),(0,3,7)), 'switzerland':((139,-188,122),(0,7,29)), 'germany':((132,-180,122),(0,9,28))}
cams={}
for module,name,offset in REGIONS:
    position,target=camera_offsets[module];cams[module]=camera('Camera_'+name,Vector(position)+Vector(offset),Vector(target)+Vector(offset),lens=48)
overview=camera('Camera_Europe_Overview',(365,-487,400),(0,0,28),ortho=430)
scene.camera=cams[REGIONS[0][0]] if args.only else overview
# Set a useful opening viewport in material-preview camera view.
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_perspective='CAMERA';area.spaces.active.shading.type='MATERIAL'
            area.spaces.active.clip_end=2500
select([])
scene['project']='European Travel / realistic game exterior asset pack'
scene['readme']='See 使用说明.md. Models use compressed landmark scale; collisions and LOD require engine setup.'
for img in bpy.data.images:
    if img.source in ('FILE','GENERATED'):img.pack()
blend_path=ROOT/('Europe_Travel_Preview.blend' if args.quick else '欧洲四国旅行场景.blend')
bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
log('BLEND SAVED '+str(blend_path))
report={'blender_version':bpy.app.version_string,'regions':metadata,'total_triangles_LOD0':triangles(all_objects),'total_mesh_objects':len(all_objects),'materials':len(mats),'textures':'512 px tileable BaseColor and tangent-space Normal maps; packed in blend and GLB','generation_seconds':round(time.time()-start,2),'scope':'Exterior model pack; no complete game or guaranteed engine frame rate'}
(ROOT/('quick_report.json' if args.quick else 'asset_report.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
if not args.skip_render:
    render_list=[(REGIONS[0][0],cams[REGIONS[0][0]])] if args.only else [('overview',overview)]+list(cams.items())
    for key,cam in render_list:
        # Individual renders isolate each district so adjoining asset tiles cannot distract.
        for mod,col in region_cols.items():col.hide_render=key!='overview' and mod!=key
        scene.camera=cam;scene.render.filepath=str(ROOT/'previews'/(('draft_' if args.quick else '')+key+'.png'))
        log('RENDER '+key);bpy.ops.render.render(write_still=True)
    for col in region_cols.values():col.hide_render=False
    scene.camera=cams[REGIONS[0][0]] if args.only else overview
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
log('DONE total seconds '+str(round(time.time()-start,2)))

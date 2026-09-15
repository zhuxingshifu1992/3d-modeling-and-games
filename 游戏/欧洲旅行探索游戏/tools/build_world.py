"""Build the connected, enterable game world, source .blend and engine manifests."""
import bpy,sys,json,math,time,importlib,hashlib
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools/model'))
from geometry import Builder,material_library
from materials_v2 import upgrade
REGIONS=[('france','FR_Paris',(-90,85,0),'法国 · 巴黎'),('italy','IT_Rome',(90,85,0),'意大利 · 罗马'),('switzerland','CH_Alps',(-90,-85,0),'瑞士 · 阿尔卑斯'),('germany','DE_Bavaria',(90,-85,0),'德国 · 巴伐利亚')]
def log(s):print('WORLD | '+s,flush=True)
def select(obs):
    bpy.ops.object.select_all(action='DESELECT')
    for o in obs:o.hide_set(False);o.select_set(True)
    if obs:bpy.context.view_layer.objects.active=obs[0]
def newcol(n):
    c=bpy.data.collections.new(n);bpy.context.scene.collection.children.link(c);return c
def count(obs):return sum(len(p.vertices)-2 for o in obs for p in o.data.polygons)
def gamepoint(p,off=(0,0,0)):return [round(p[0]+off[0],5),round(p[2]+off[2],5),round(-p[1]-off[1],5)]
def glb(obs,path):
    select(obs);bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_extras=True,export_cameras=False,export_lights=False)
def merged_export(obs,building_ids,colname):
    col=newcol(colname);copies=[]
    buckets={}
    for o in obs:
        du=o.copy();du.data=o.data.copy();col.objects.link(du);du.location=(0,0,0);copies.append(du)
        key=du.name
        if o.name.startswith('IN_'):
            id=next((k for k in sorted(building_ids,key=len,reverse=True) if o.name.startswith('IN_'+k+'_')),None)
            if id:key='IN_'+id+'_Interior'
        elif o.name.startswith('EX_'):
            id=next((k for k in sorted(building_ids,key=len,reverse=True) if o.name.startswith('EX_'+k+'_')),None)
            if id:key='EX_'+id+'_Building'
        buckets.setdefault(key,[]).append(du)
    final=[]
    for key,parts in buckets.items():
        select(parts)
        if len(parts)>1:bpy.ops.object.join()
        o=bpy.context.view_layer.objects.active;o.name=key;final.append(o)
    return col,final
def dispose(col):
    for o in list(col.objects):bpy.data.objects.remove(o,do_unlink=True)
    bpy.data.collections.remove(col)

start=time.time();bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene;scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
mats=upgrade(material_library(ROOT/'assets/textures/generated'),ROOT)
manifest={'version':2,'name':'欧洲漫游','regions':[],'buildings':[],'interactions':[],'landmarks':[],'lights':[],'spawn':[-90,.26,-47]}
stats={};allvisual=[];allcollision=[]
structural={
 'france':['Ground','Footings','Esplanade','Walk','Quay','Bridge','Observation_Decks','Deck_Railing'],
 'italy':['Ground','Arena','Seating','Stairs','Arch','Spandrel','Pier','Cornices','Attic','Piazza'],
 'switzerland':['Ground','Mountain','Trail','Lanes','Bridge','Foundation','Church'],
 'germany':['Ground','Terrain','Hill','Path','Road','Ramp','Courtyard','Retaining','Gatehouse','Battlements','Palace_Walls','Tower_Masonry']}
for module,id,offset,label in REGIONS:
    log('BUILD '+id);col=newcol(id);B=Builder(col,mats,offset)
    B.box(id+'_Ground',(0,0,-.8),(140,120,1.6),'grass' if module!='italy' else 'gravel')
    meta=importlib.import_module(module).build(B);obs=B.finish()
    # Small bevels give furniture edges a physical highlight at walking distance.
    for o in obs:
        if o.name.startswith('IN_') and any(k in o.name for k in ('Furniture','Upholstery','Cabinetry','Countertops')):
            select([o]);bevel=o.modifiers.new('Furniture_Edge_Detail','BEVEL');bevel.width=.035 if 'Upholstery' in o.name else .012;bevel.segments=3 if 'Upholstery' in o.name else 2;bevel.limit_method='ANGLE'
            bpy.ops.object.modifier_apply(modifier=bevel.name)
    visual=[o for o in obs if not o.name.startswith('COL_')];collisions=[o for o in obs if o.name.startswith('COL_')]
    for o in visual:
        if any(k.lower() in o.name.lower() for k in structural[module]) and not o.name.startswith(('IN_','EX_')):
            du=o.copy();du.data=o.data.copy();col.objects.link(du);du.name='COL_'+o.name;du.data.materials.clear();collisions.append(du)
    # All collision meshes live in separate hidden source collections.
    cc=newcol(id+'_Collision')
    for o in collisions:
        for own in list(o.users_collection):own.objects.unlink(o)
        cc.objects.link(o);o['role']='collision';o.data.materials.clear()
    ids=[b['id'] for b in B.buildings]
    ec,export=merged_export(visual,ids,id+'_GAME_EXPORT')
    log('EXPORT '+id+' '+str(len(export))+' visual nodes')
    modelname=id+'.glb';glb(export,ROOT/'assets/models'/modelname)
    select(export);bpy.ops.export_scene.fbx(filepath=str(ROOT/'source'/(id+'.fbx')),use_selection=True,object_types={'MESH'},bake_anim=False,axis_forward='-Z',axis_up='Y',path_mode='COPY',embed_textures=True)
    # Distance LOD omits interior contents; facades/landmarks remain.
    for o in list(export):
        if o.name.startswith('IN_'):bpy.data.objects.remove(o,do_unlink=True);export.remove(o)
        elif len(o.data.polygons)>120:
            select([o]);mod=o.modifiers.new('Distance_LOD','DECIMATE');mod.ratio=.32;bpy.ops.object.modifier_apply(modifier=mod.name)
    lowname=id+'_low.glb';glb(export,ROOT/'assets/models'/lowname);dispose(ec)
    for o in collisions:o.location=(0,0,0)
    glb(collisions,ROOT/'assets/models'/(id+'_collision.glb'))
    for o in collisions:o.location=offset;o.hide_render=True;o.hide_set(True)
    cc.hide_render=True
    starts={'france':(0,-37,.26),'italy':(0,-49,.35),'switzerland':(0,-51,.12),'germany':(-17,-52,.15)}
    manifest['regions'].append({'id':id,'name':label,'model':'res://assets/models/'+modelname,'lod':'res://assets/models/'+lowname,'collision':'res://assets/models/'+id+'_collision.glb','position':gamepoint(offset),'bounds':[140,120],'spawn':gamepoint(starts[module],offset)})
    for b in B.buildings:
        rec=dict(b);rec['region']=id
        for key in ['entrance','inside','center']:rec[key]=gamepoint(b[key],offset)
        # Rotated house axis-aligned bounds in the game XZ plane.
        a=b.get('front_angle',0);w,d,h=b['size'];ww=abs(w*math.cos(a))+abs(d*math.sin(a));dd=abs(w*math.sin(a))+abs(d*math.cos(a))
        rec['bounds']={'center':rec['center'],'size':[ww,h,dd]};rec['stair_landings']=[gamepoint(p,offset) for p in b.get('stair_landings',[])]
        rec['floor_levels']=[round(z+offset[2],5) for z in b['floor_levels']]
        manifest['buildings'].append(rec)
    for i in B.interactions:manifest['interactions'].append({'id':i['id'],'label':i['label'],'kind':i['kind'],'region':id,'position':gamepoint(i['source'],offset),'target':gamepoint(i['target'],offset)})
    for light in B.room_lights:
        rec=dict(light);rec['position']=gamepoint(light['position'],offset);manifest['lights'].append(rec)
    stats[id]={'visual_triangles':count(visual),'collision_triangles':count(collisions),'source_objects':len(visual),'buildings':len(B.buildings),'floors':sum(b['floors'] for b in B.buildings)}
    allvisual+=visual;allcollision+=collisions

# Continuous shared terrain, civic boulevard and graded entry connections.
col=newcol('European_Connecting_Streets');B=Builder(col,mats)
B.box('World_Ground',(0,0,-.10),(365,330,.15),'grass')
road_index=0
def road(a,b,width=6,mat='paving'):
    global road_index
    road_index+=1
    x=(a[0]+b[0])/2;y=(a[1]+b[1])/2;length=math.hypot(b[0]-a[0],b[1]-a[1]);ang=math.atan2(b[1]-a[1],b[0]-a[0])
    # Millimetric height offsets prevent coplanar flicker at road crossings.
    z=.015+road_index*.002
    B.box('Connected_Walkways',(x,y,z),(length,width,.07),mat,ang)
    B.box('COL_Connected_Walkways',(x,y,z),(length,width,.07),'stone',ang)
road((0,-155),(0,155),9);road((-172,0),(172,0),9)
road((-172,-153),(172,-153),7);road((-172,150),(172,150),7)
road((-172,-153),(-172,150),7);road((172,-153),(172,150),7)
road((-132,0),(-132,25),7);road((90,0),(90,35),7)
road((-90,-153),(-90,-136),6);road((73,-153),(73,-137),6)
# Short connectors link historic street ends to the central avenue.
road((-20,124),(0,124),7);road((20,128),(0,128),7)
road((-24,-106),(0,-106),6);road((0,-137),(73,-137),5)
for x,y in [(0,y) for y in range(-140,150,24)]+[(x,0) for x in range(-150,160,26)]:
    B.cyl('Street_Lamps',(x+5.5,y,2.4),.07,4.8,'metal',10)
    B.cyl('Street_Lamps',(x+5.5,y,.18),.20,.36,'metal',12)
    B.box('Street_Lamp_Globes',(x+5.5,y,4.76),(.44,.44,.56),'emissive')
    B.cyl('Street_Lamps',(x+5.5,y,5.10),.34,.16,'metal',8,radius_top=.08)
for x,y in [(-7,-58),(7,58),(-65,7),(67,-7),(-148,-152),(148,152)]:
    B.box('Roadside_Benches',(x,y,.47),(2.2,.65,.13),'wood')
    B.box('Roadside_Benches',(x,y+.30,.86),(2.2,.10,.66),'wood')
    for dx in (-.75,.75):B.box('Roadside_Benches',(x+dx,y,.22),(.08,.65,.44),'metal')
for x,y in [(-10,-30),(10,30),(-10,92),(10,-92),(-43,10),(40,-10),(-160,65),(160,-60)]:B.tree('Connecting_Street_Trees',x,y,0,8.5)
for module,id,off,label in REGIONS:
    # Four covered travel stops, matching the region spawn neighborhood.
    p=next(r['spawn'] for r in manifest['regions'] if r['id']==id);x,y=p[0]+4,-p[2]
    B.box('Travel_Stops',(x,y,2.65),(3.8,1.75,.18),'metal')
    for dx in (-1.7,1.7):B.box('Travel_Stops',(x+dx,y+.55,1.3),(.10,.10,2.6),'metal')
    B.box('Travel_Stops',(x,y+.66,1.35),(3.5,.07,2.3),'glass')
    B.box('Travel_Stops',(x,y+.35,.5),(2.4,.4,.13),'wood')
    manifest['interactions'].append({'id':id+'_station','kind':'station','label':label+' · 旅行车站','position':[x,p[1],-y],'target':p,'region':id})
obs=B.finish();worldvisual=[o for o in obs if not o.name.startswith('COL_')];worldcollision=[o for o in obs if o.name.startswith('COL_')]
ground=next(o for o in worldvisual if o.name=='World_Ground');du=ground.copy();du.data=ground.data.copy();col.objects.link(du);du.name='COL_World_Ground';worldcollision.append(du)
glb(worldvisual,ROOT/'assets/models'/'connected_world.glb');glb(worldcollision,ROOT/'assets/models'/'connected_world_collision.glb')
for o in worldcollision:o.hide_render=True;o.hide_set(True)
manifest['world_model']='res://assets/models/connected_world.glb';manifest['world_collision']='res://assets/models/connected_world_collision.glb'
landmarks=[('FR_Paris','fr_eiffel','埃菲尔铁塔',(-90,.20,-77),'沿着铁塔桁架探索巴黎，在观景台眺望城市。'),('IT_Rome','it_colosseum','罗马斗兽场',(90,.35,-61),'穿过石拱进入竞技场，观察罗马建筑的层叠结构。'),('CH_Alps','ch_matterhorn','阿尔卑斯山村',(-90,.15,77),'走进木屋，沿山脚观景路欣赏岩壁与雪峰。'),('DE_Bavaria','de_castle','巴伐利亚城堡',(98,12.5,102),'进入庭院、宫殿和塔楼，收集德国旅行印章。')]
for region,id,label,pos,desc in landmarks:manifest['landmarks'].append({'id':id,'region':region,'label':label,'position':list(pos),'description':desc})
(ROOT/'assets/world_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
report={'regions':stats,'buildings':len(manifest['buildings']),'floors':sum(b['floors'] for b in manifest['buildings']),'interactions':len(manifest['interactions']),'visual_triangles':sum(s['visual_triangles'] for s in stats.values())+count(worldvisual),'materials':len(mats),'build_seconds':round(time.time()-start,1)}
(ROOT/'docs/world_build_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
scene.render.engine='CYCLES';scene.cycles.samples=32;scene.cycles.use_denoising=True;scene.render.resolution_x=1600;scene.render.resolution_y=1000;scene.render.resolution_percentage=100
scene.world=bpy.data.worlds.new('Daylight');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.55,.69,.85,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.5
for index,l in enumerate(manifest['lights']):
    data=bpy.data.lights.new('Room_Light_'+str(index),'POINT');data.energy=135;data.color=l['color'];data.shadow_soft_size=.25
    ob=bpy.data.objects.new(data.name,data);scene.collection.objects.link(ob);p=l['position'];ob.location=(p[0],-p[2],p[1])
sun=bpy.data.lights.new('Sun','SUN');sun.energy=3;sun.angle=math.radians(8);ob=bpy.data.objects.new('Sun',sun);scene.collection.objects.link(ob);ob.rotation_euler=(.5,-.3,-.4)
cam=bpy.data.cameras.new('Connected_World_Overview');ob=bpy.data.objects.new('Connected_World_Overview',cam);scene.collection.objects.link(ob);ob.location=(395,-480,395);ob.rotation_euler=(Vector((0,0,18))-ob.location).to_track_quat('-Z','Y').to_euler();cam.type='ORTHO';cam.ortho_scale=490;cam.clip_end=3000;scene.camera=ob
for img in bpy.data.images:
    if img.source in ('FILE','GENERATED'):img.pack()
select([])
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'source'/'欧洲漫游_可进入建筑.blend'))
log('DONE '+json.dumps(report,ensure_ascii=False))

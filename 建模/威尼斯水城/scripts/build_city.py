"""Generate and render an original, stylized Venetian lagoon city.

Usage: blender --background --factory-startup --python build_city.py -- --draft
"""
import argparse
import json
import math
import os
from pathlib import Path
import random
import sys
import time

import bpy
from mathutils import Vector

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
from scene_utils import mat,cube,cyl,mesh,curve,sphere,collection,group_objects,aim
from buildings import create_building
from landmarks import create_basilica,create_campanile,create_palazzo

OUT=HERE.parent
RNG=random.Random(2911)
M={}

def materials():
    colors={
        'Limestone':(.70,.64,.48),'Paving':(.52,.47,.36),'Paving light':(.65,.60,.46),
        'Foundation':(.27,.32,.27),'Coping':(.80,.74,.60),'Iron':(.032,.055,.053),
        'Wood':(.23,.105,.045),'Dark wood':(.055,.034,.024),'Gold':(.74,.44,.12),
        'Ivory':(.88,.80,.60),'Red':(.57,.065,.03),'Blue':(.024,.20,.25),
        'Leaf':(.115,.25,.09),'Leaf light':(.25,.39,.115),'Clay':(.48,.18,.09),
        'Petal':(.76,.08,.20),'Boat black':(.018,.031,.034),'Cushion':(.34,.025,.027),
    }
    for name,col in colors.items():M[name]=mat(name,col)
    M['Gold'].node_tree.nodes['Principled BSDF'].inputs['Metallic'].default_value=.65
    M['Iron'].node_tree.nodes['Principled BSDF'].inputs['Metallic'].default_value=.5
    for key in ['Paving','Limestone']:
        m=M[key]; n=m.node_tree.nodes; l=m.node_tree.links
        noise=n.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=5
        bump=n.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.13;bump.inputs['Distance'].default_value=.045
        l.new(noise.outputs['Fac'],bump.inputs['Height']);l.new(bump.outputs['Normal'],n['Principled BSDF'].inputs['Normal'])

def water():
    collection('01 • Lagoon & canals')
    w=mat('Lagoon • jade ripples',(.027,.28,.28),.2,.23)
    n=w.node_tree.nodes;l=w.node_tree.links;p=n['Principled BSDF']
    p.inputs['IOR'].default_value=1.333
    p.inputs['Coat Weight'].default_value=.3
    tex=n.new('ShaderNodeTexCoord')
    noise=n.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=.33;noise.inputs['Detail'].default_value=3;noise.inputs['Roughness'].default_value=.58
    l.new(tex.outputs['Object'],noise.inputs['Vector'])
    ramp=n.new('ShaderNodeValToRGB');ramp.color_ramp.elements[0].position=.16;ramp.color_ramp.elements[0].color=(.024,.205,.215,1);ramp.color_ramp.elements[1].position=.85;ramp.color_ramp.elements[1].color=(.045,.30,.28,1)
    l.new(noise.outputs['Fac'],ramp.inputs['Fac']);l.new(ramp.outputs['Color'],p.inputs['Base Color'])
    wave=n.new('ShaderNodeTexWave');wave.wave_type='BANDS';wave.bands_direction='X';wave.inputs['Scale'].default_value=.65;wave.inputs['Distortion'].default_value=3;wave.inputs['Detail Scale'].default_value=.6
    l.new(tex.outputs['Object'],wave.inputs['Vector'])
    bump=n.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.16;bump.inputs['Distance'].default_value=.07
    l.new(wave.outputs['Color'],bump.inputs['Height']);l.new(bump.outputs['Normal'],p.inputs['Normal'])
    ob=mesh('Continuous lagoon water',[(-2000,-2000,0),(2000,-2000,0),(2000,2000,0),(-2000,2000,0)],[(0,1,2,3)],w)
    ob['surface']='Procedural jade lagoon; shared surface for all connected canals'

def block(label,cx,cy,w,d):
    collection('02 • Stone islands & quays')
    cube(label+' masonry',(cx,cy,.15),(w,d,1.5),M['Foundation'],.16)
    cube(label+' promenade',(cx,cy,.87),(w,d,.24),M['Paving'],.12)
    for y in [cy-d/2+.18,cy+d/2-.18]:
        for i in range(math.ceil(w/1.5)):
            x=cx-w/2+(i+.5)*w/math.ceil(w/1.5)
            cube(label+' edge coping',(x,y,1.015),(w/math.ceil(w/1.5)-.035,.42,.18),M['Coping'],.025)
            cube(label+' waterfront course',(x,y,.42),(w/math.ceil(w/1.5)-.04,.12,.40),M['Limestone'])
    for x in [cx-w/2+.18,cx+w/2-.18]:
        for i in range(math.ceil(d/1.5)):
            y=cy-d/2+(i+.5)*d/math.ceil(d/1.5)
            cube(label+' edge coping',(x,y,1.015),(.42,d/math.ceil(d/1.5)-.035,.18),M['Coping'],.025)
            cube(label+' waterfront course',(x,y,.42),(.12,d/math.ceil(d/1.5)-.04,.4),M['Limestone'])
    # Sparse large paving slabs retain legibility at architectural scale.
    for x in range(round(cx-w/2+1),round(cx+w/2),2):
        for y in range(round(cy-d/2+1),round(cy+d/2),2):
            if RNG.random()<.58:cube('Paving slab',(x,y,1.003),(1.92,1.92,.012),M['Paving light'])

def bridge(label,loc,length=12,width=3.1,rotation=0):
    collection('05 • Arched pedestrian bridges')
    before=set(bpy.data.objects)
    count=32;xs=[-length/2+length*i/count for i in range(count+1)]
    def walking(x):return 1.15+2.10*(1-abs(2*x/length))
    def underside(x):return .20+1.85*math.sqrt(max(0,1-(2*x/length)**2))
    for y in [-width/2,width/2]:
        vs=[]
        for x in xs:
            vs.extend([(x,y-.19,underside(x)),(x,y+.19,underside(x)),(x,y-.19,walking(x)),(x,y+.19,walking(x))])
        fs=[]
        for i in range(count):
            a=4*i;b=a+4
            fs.extend([(a,b,b+2,a+2),(a+1,a+3,b+3,b+1),(a,a+1,b+1,b),(a+2,b+2,b+3,a+3)])
        fs.extend([(0,2,3,1),(4*count,4*count+1,4*count+3,4*count+2)])
        mesh(label+' arch masonry',vs,fs,M['Limestone'])
        curve(label+' arch voussoir rim',[(x,y+(-.2 if y<0 else .2),underside(x)+.06) for x in xs],.10,M['Coping'])
        for i in range(1,count,2):
            x=xs[i]
            curve('Arch radial mortar',[(x,y+(-.195 if y<0 else .195),underside(x)+.12),(x*.985,y+(-.2 if y<0 else .2),min(underside(x)+.42,walking(x)))],.016,M['Foundation'])
        for i in range(17):
            x=-length/2+length*i/16;z=walking(x)
            cube(label+' baluster',(x,y,z+.49),(.16,.22,.95),M['Coping'],.025)
        curve(label+' top rail',[(x,y,walking(x)+1.0) for x in xs],.12,M['Coping'])
        curve(label+' lower rail',[(x,y,walking(x)+.19) for x in xs],.075,M['Coping'])
    for i in range(count):
        x=(xs[i]+xs[i+1])/2;z=walking(x)
        cube(label+' stair tread',(x,0,z-.10),(length/count+.02,width,.22),M['Coping'],.015)
    return group_objects(label,before,loc,rotation)

def lamp(x,y,z=1.08):
    collection('07 • Quay life & planting')
    cyl('Lamp stone plinth',(x,y,z+.1),.22,.2,M['Limestone'])
    cyl('Cast iron lamppost',(x,y,z+1.48),.07,2.8,M['Iron'])
    cyl('Lamp base',(x,y,z+.38),.13,.65,M['Iron'])
    cube('Lantern glass',(x,y,z+2.96),(.35,.35,.48),M['Ivory'],.025)
    for dx in [-.2,.2]:
        for dy in [-.2,.2]:cyl('Lantern mullion',(x+dx,y+dy,z+2.96),.025,.53,M['Iron'],8)
    cyl('Lantern hood',(x,y,z+3.28),.34,.12,M['Iron'],4).rotation_euler[2]=math.pi/4
    sphere('Lantern finial',(x,y,z+3.43),(.07,.07,.10),M['Gold'],8,4)

def mooring(x,y):
    collection('06 • Gondolas & moorings')
    cyl('Timber mooring pole',(x,y,.69),.13,2.1,M['Wood'])
    cyl('Painted ivory cap',(x,y,1.69),.145,.22,M['Ivory'])
    for z in [1.0,1.12]:cyl('Pole rope band',(x,y,z),.15,.055,M['Gold'])

def gondola(name,loc,rotation=0,scale=1):
    collection('06 • Gondolas & moorings')
    before=set(bpy.data.objects)
    # Hollow, double-ended hull built as outside / sheer / inside rings.
    sides=32;verts=[]
    for ring in range(3):
        for i in range(sides):
            t=math.tau*i/sides;x=3.0*math.cos(t);y=.63*math.sin(t)
            if ring==0:verts.append((x*.91,y*.55,.08+.19*abs(math.cos(t))**6))
            elif ring==1:verts.append((x,y,.47+.52*abs(math.cos(t))**9))
            else:verts.append((x*.91,y*.77,.32+.43*abs(math.cos(t))**9))
    faces=[]
    for ring in range(2):
        for i in range(sides):a=ring*sides+i;b=ring*sides+(i+1)%sides;faces.append((a,b,b+sides,a+sides))
    mesh(name+' curved hull',verts,faces,M['Boat black'])
    cube('Gondola floor',(0,0,.27),(3.6,.64,.13),M['Wood'],.07)
    for i in [-1.2,-.55,.55,1.3]:cube('Carved gondola seat',(i,0,.52),(.30,.94,.14),M['Boat black'],.04)
    for i in [-.55,.55]:cube('Burgundy passenger cushion',(i,0,.63),(.46,.62,.16),M['Cushion'],.06)
    curve('Gondola gold sheer',verts[sides:2*sides],.025,M['Gold'],True)
    curve('Sweeping prow ferro',[(2.7,0,.60),(3.03,0,1.08),(3.06,0,1.46),(2.93,0,1.60)],.052,M['Coping'])
    for i in range(5):curve('Ferro teeth',[(3.03,0,1.06+i*.085),(3.22,0,1.06+i*.085)],.026,M['Coping'])
    curve('Gondolier oar',[(-1.7,.1,.9),(-2.15,1.8,.2),(-2.7,2.8,.02)],.045,M['Wood'])
    cube('Oar paddle',(-2.62,2.64,.035),(.15,.62,.065),M['Wood']).rotation_euler[2]=-.3
    # Tiny stylized boatman provides a useful scale cue.
    for x in [-1.58,-1.37]:curve('Boatman leg',[(x,0,.46),(x,0,.88)],.06,M['Iron'])
    sphere('Boatman striped jersey',(-1.48,0,1.10),(.20,.15,.29),M['Ivory'])
    sphere('Boatman head',(-1.48,0,1.49),(.13,.13,.15),M['Limestone'])
    cyl('Straw hat',(-1.48,0,1.62),.23,.07,M['Gold'])
    cyl('Hat crown',(-1.48,0,1.69),.14,.12,M['Gold'])
    curve('Boatman arm',[(-1.53,.1,1.25),(-1.72,.36,1.05),(-1.84,.70,.88)],.055,M['Ivory'])
    root=group_objects(name,before,loc,rotation);root.scale=(scale,)*3
    # Very subtle rocking; animation-ready scene without requiring a video render.
    for frame,dz,roll in [(1,0,-.012),(90,.07,.013),(180,0,-.012)]:
        root.location.z=loc[2]+dz;root.rotation_euler.x=roll
        root.keyframe_insert('location',frame=frame);root.keyframe_insert('rotation_euler',frame=frame)
    return root

def dock(x,y,rotation=0):
    collection('06 • Gondolas & moorings');before=set(bpy.data.objects)
    for i in range(12):cube('Landing dock plank',((i-5.5)*.27,0,.71),(.245,1.85,.16),M['Wood'],.02)
    for a in [-1.45,1.45]:
        for b in [-.72,.72]:cyl('Dock pile',(a,b,.38),.12,1.8,M['Wood'])
    return group_objects('Timber landing dock',before,(x,y,0),rotation)

def tree(x,y,scale=1,cypress=False):
    collection('07 • Quay life & planting')
    cyl('Terracotta planter',(x,y,1.35),.59,.66,M['Clay'])
    cyl('Planter rim',(x,y,1.68),.64,.14,M['Clay'])
    cyl('Tree trunk',(x,y,2.25),.12,1.6,M['Wood'])
    if cypress:
        for z,r in [(2.8,.7),(3.5,.63),(4.2,.45),(4.8,.22)]:sphere('Cypress foliage',(x,y,z),(r,r,.85),M['Leaf'],12,7)
    else:
        for dx,dy,dz,s in [(0,0,0,1.05),(.55,.16,-.2,.74),(-.5,-.1,-.1,.8),(.1,-.4,.48,.65)]:
            sphere('Olive crown',(x+dx*scale,y+dy*scale,3.3+dz*scale),(s*scale,s*scale,s*.78*scale),M['Leaf light' if dx>0 else 'Leaf'],12,7)

def cafe(x,y):
    collection('07 • Quay life & planting')
    for dx in [-1.5,1.5]:
        cx=x+dx
        cyl('Cafe tabletop',(cx,y,1.85),.55,.11,M['Ivory'],24)
        cyl('Cafe table leg',(cx,y,1.45),.07,.78,M['Iron'])
        for dy in [-.85,.85]:
            cube('Cafe chair seat',(cx,y+dy,1.51),(.48,.48,.08),M['Wood'],.03)
            for q in [-.2,.2]:curve('Chair frame',[(cx+q,y+dy-.20,1.03),(cx+q,y+dy-.20,1.52),(cx+q,y+dy+.2,1.52),(cx+q,y+dy+.2,2.10)],.025,M['Iron'])
            cube('Cafe chair back',(cx,y+dy+.2,1.95),(.47,.05,.3),M['Wood'],.02)
    cyl('Umbrella pole',(x,y,2.2),.045,2.5,M['Wood'])
    vs=[(x,y,3.85)]+[(x+2.4*math.cos(math.tau*i/12),y+2.4*math.sin(math.tau*i/12),3.20) for i in range(12)]
    ob=mesh('Striped cafe parasol',vs,[(0,i+1,(i+1)%12+1) for i in range(12)],M['Ivory']);ob.data.materials.append(M['Red'])
    for i,p in enumerate(ob.data.polygons):p.material_index=i%2

def street_details():
    for x in [-6.65,6.65]:
        for y in [-22,-6,6,23]:lamp(x,y)
    for x in [-28,-17,-7,7,18,29]:lamp(x,-23.0)
    for x,y in [(-30,4.8),(-15,4.8),(15,4.8),(29,4.8)]:lamp(x,y)
    for x,y in [(-30,18),(-30.15,-16.4),(-16.1,-5.1),(29.8,-11),(29,8),(29,23),(8,23),(16,23)]:tree(x,y,.82,cypress=(y>10))
    cafe(17.8,7.5);cafe(-23,-26)
    # Scattered flower pots and market crates along the quays.
    collection('07 • Quay life & planting')
    for x,y in [(-14.3,-22.7),(-26,-23.25),(13.6,-22.8),(29,-16),(-29,4.9),(7.2,9)]:
        cyl('Flower pot',(x,y,1.25),.27,.46,M['Clay'])
        sphere('Potted greenery',(x,y,1.59),(.34,.32,.26),M['Leaf'])
        for j in range(5):sphere('Geranium',(x+RNG.uniform(-.25,.25),y+RNG.uniform(-.25,.25),1.8),(.085,.085,.07),M['Petal'],8,4)

def buildings():
    palette=[(.76,.42,.21),(.74,.28,.20),(.86,.64,.32),(.73,.47,.37),(.77,.65,.48),(.47,.58,.48),(.78,.50,.41),(.70,.35,.24)]
    collection('03 • Venetian houses')
    specs=[]
    # Narrow facades follow the grand canal, leaving a walkable quay at the edge.
    for side,ys in [(-1,[-20.5,-14.2,-7.8,7.9,14.2,21.0]),(1,[-19.8,-12.8,-6.8])]:
        for i,y in enumerate(ys):specs.append((side*10.5,y,5.4,5.9,RNG.uniform(7.4,11.6),side*-math.pi/2))
    # Western neighborhood blocks: frontage, inner lanes, varied roof heights.
    for y,xs in [(-20.3,[-28.0,-21.4]),(-12.6,[-27.8,-20.4]),(-6.7,[-27.8,-21.0]),(7.6,[-27.6,-20.3]),(15.0,[-27.5,-20.1]),(22.0,[-27.7,-20.3])]:
        for x in xs:specs.append((x,y,5.8,5.0,RNG.uniform(7.2,12.4),0 if y<0 or y==7.6 else math.pi/2*(int(x)%2)))
    # South east residential waterfront in front of the palazzo.
    specs.extend([(17.5,-20.3,6.1,4.8,8.3,0),(25.1,-20.3,6.3,4.8,9.5,0)])
    for i,(x,y,w,d,h,r) in enumerate(specs):
        create_building('House %02d'%(i+1),(x,y,1.04),width=w,depth=d,height=h,color=palette[i%len(palette)],rotation=r,seed=110+i,variant=i%5)
    collection('04 • Basilica, campanile & palazzo')
    create_basilica('Basilica of the lagoon',(22,18.7,1.04))
    create_campanile('Piazza campanile',(10.0,20,1.04))
    create_palazzo('Canal-side palazzo',(23,-12.0,1.04),rotation=math.pi/2)
    # Piazza paving diamond, a central well, and two marker columns.
    collection('07 • Quay life & planting')
    cube('Piazza inlay',(18.5,8.0,1.024),(14,6.5,.025),M['Limestone'])
    for x in [13.5,18.5,23.5]:cube('Piazza diamond',(x,8,1.043),(1.45,1.45,.018),M['Paving']).rotation_euler[2]=math.pi/4
    cyl('Piazza well foot',(10,8,1.17),.92,.27,M['Coping'],12)
    cyl('Piazza well stone',(10,8,1.60),.63,.65,M['Limestone'],12)
    cyl('Well coping',(10,8,1.99),.74,.18,M['Coping'],12)
    cyl('Well opening',(10,8,2.084),.46,.015,M['Iron'],24)

def cameras_lighting():
    collection('08 • Cameras & lighting')
    world=bpy.data.worlds.new('Warm lagoon afternoon');bpy.context.scene.world=world;world.use_nodes=True
    world.node_tree.nodes['Background'].inputs[0].default_value=(.49,.64,.72,1)
    world.node_tree.nodes['Background'].inputs[1].default_value=.40
    sun_data=bpy.data.lights.new('Afternoon sun','SUN');sun_data.energy=2.2;sun_data.angle=math.radians(18);sun_data.color=(1,.81,.59)
    sun=bpy.data.objects.new('Afternoon sun',sun_data);collection('08 • Cameras & lighting').objects.link(sun);sun.rotation_euler=(math.radians(24),math.radians(-28),math.radians(-32))
    light_data=bpy.data.lights.new('Large soft sky','AREA');light_data.energy=1900;light_data.shape='DISK';light_data.size=45;light_data.color=(.63,.80,1)
    light=bpy.data.objects.new('Large soft sky',light_data);collection('08 • Cameras & lighting').objects.link(light);light.location=(10,-30,48);aim(light,(0,0,0))
    specs=[('01 • City portrait',(85,-112,88),(0,1.8,4.2),'ORTHO',89),('02 • Grand canal',(4,-70,34),(0,4,7.5),'PERSP',42),('03 • Piazza',(48,-31,36),(18,15,10),'PERSP',44)]
    cameras=[]
    for name,loc,target,typ,lens in specs:
        d=bpy.data.cameras.new(name);o=bpy.data.objects.new(name,d);collection('08 • Cameras & lighting').objects.link(o);o.location=loc;aim(o,target);d.type=typ
        if typ=='ORTHO':d.ortho_scale=lens
        else:d.lens=lens
        d.clip_end=1000;cameras.append(o)
    bpy.context.scene.camera=cameras[0]
    # A gentle 7.5-second architectural orbit is ready for later animation rendering.
    hero=cameras[0]
    for frame,loc in [(1,(85,-112,88)),(180,(66,-124,86))]:
        hero.location=loc;aim(hero,(0,1.8,4.2));hero.keyframe_insert('location',frame=frame);hero.keyframe_insert('rotation_euler',frame=frame)
    sc=bpy.context.scene;sc.frame_start=1;sc.frame_end=180;sc.render.fps=24;sc.frame_set(1)
    sc.timeline_markers.new('CITY • 7.5s orbit',frame=1)
    return cameras

def settings(draft):
    sc=bpy.context.scene
    sc.unit_settings.system='METRIC';sc.unit_settings.length_unit='METERS'
    sc.render.engine='CYCLES';sc.cycles.device='CPU';sc.cycles.samples=24 if draft else 56
    sc.cycles.use_denoising=True;sc.cycles.max_bounces=5;sc.cycles.diffuse_bounces=3;sc.cycles.glossy_bounces=3;sc.cycles.transmission_bounces=3
    sc.render.resolution_x=1100 if draft else 1800;sc.render.resolution_y=900 if draft else 1400;sc.render.resolution_percentage=100
    sc.render.image_settings.file_format='PNG';sc.render.image_settings.color_mode='RGB'
    sc.view_settings.view_transform='AgX'
    sc.view_settings.exposure=.35
    try:sc.view_settings.look='AgX - Medium High Contrast'
    except TypeError:pass
    sc.render.film_transparent=False
    sc.render.threads_mode='FIXED';sc.render.threads=12
    sc.world.color=(.3,.4,.5)
    # Open the saved file in a fast, readable material-color viewport.
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D':
                area.spaces.active.shading.type='SOLID';area.spaces.active.shading.color_type='MATERIAL';area.spaces.active.clip_end=1000
                area.spaces.active.region_3d.view_perspective='CAMERA'

def verify_and_save():
    sc=bpy.context.scene
    meshes=[o for o in sc.objects if o.type=='MESH']
    empty=[o.name for o in meshes if not o.data.vertices]
    assert not empty,empty
    assert len(meshes)>500,len(meshes)
    assert len([o for o in sc.objects if o.type=='CAMERA'])==3
    assert sc.camera is not None
    report={'blender':bpy.app.version_string,'objects':len(sc.objects),'meshes':len(meshes),'mesh_vertices':sum(len(o.data.vertices) for o in meshes),'materials':len(bpy.data.materials),'cameras':[o.name for o in sc.objects if o.type=='CAMERA'],'external_images':[i.filepath for i in bpy.data.images if i.source=='FILE' and not i.packed_file],'style':'Original stylized Venetian lagoon city','animation_frames':[1,180],'fps':24}
    assert not report['external_images'],report['external_images']
    text=bpy.data.texts.new('README • Venice lagoon city')
    text.write('Original stylized Venetian city. All geometry and procedural materials are editable.\nCollections separate houses, landmarks, bridges, boats, water and lighting.\nThree cameras are available. Frame 1–180 contains a gentle hero-camera orbit and subtle boat rocking.\nUse Numpad 0 for camera view. CPU Cycles render configured for this computer.\n')
    OUT.mkdir(exist_ok=True)
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'威尼斯水城.blend'),compress=True)
    (OUT/'scene_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print('SCENE_VALIDATION',json.dumps(report,ensure_ascii=False),flush=True)

def main():
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    parser=argparse.ArgumentParser();parser.add_argument('--draft',action='store_true');parser.add_argument('--no-render',action='store_true');parser.add_argument('--views',type=int,default=2);opts=parser.parse_args(args)
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    for c in list(bpy.data.collections):
        if c.name=='Collection':bpy.data.collections.remove(c)
    materials();water()
    for label,x,y,w,d in [('Northwest',-18.5,15,25,22),('Southwest',-18.5,-14,25,20),('Northeast',18.5,15,25,22),('Southeast',18.5,-14,25,20)]:block(label,x,y,w,d)
    block('Waterfront cafe terrace',-23,-26,8.5,4.8)
    buildings();print('ARCHITECTURE_READY',flush=True)
    bridge('Grand canal • Rialto-inspired arch',(0,-14,0))
    bridge('Grand canal • northern arch',(0,14.8,0),width=2.6)
    bridge('West neighborhood footbridge',(-22,0,0),length=8.6,width=2.5,rotation=math.pi/2)
    bridge('Piazza footbridge',(22,0,0),length=8.6,width=2.7,rotation=math.pi/2)
    for x,y in [(-4.6,-21),(-4.6,-19),(4.6,7),(4.6,9),(-15,-25.1),(-18,-25.1),(15,-25.1),(18,-25.1),(32,-15),(32,-12)]:mooring(x,y)
    dock(-16.5,-25.1);dock(16.5,-25.1);dock(32,-13.5,math.pi/2)
    for name,loc,rot in [('Gondola • foreground',(-10,-29,.04),.08),('Gondola • lagoon',(9,-29,.04),-.2),('Gondola • main canal',(1,-4,.04),math.pi/2),('Gondola • north canal',(-1.6,23,.04),math.pi/2),('Gondola • west rio',(-13,0,.04),.1),('Gondola • east quay',(34,-13,.04),math.pi/2)]:gondola(name,loc,rot)
    street_details();cameras=cameras_lighting();settings(opts.draft);verify_and_save()
    if not opts.no_render:
        for index,cam in enumerate(cameras[:opts.views]):
            bpy.context.scene.camera=cam
            bpy.context.scene.render.filepath=str(OUT/('预览_城市全景.png' if index==0 else '预览_大运河.png' if index==1 else '预览_广场.png'))
            print('RENDER_START',cam.name,flush=True);bpy.ops.render.render(write_still=True);print('RENDER_DONE',cam.name,flush=True)
    print('CITY_BUILD_COMPLETE',flush=True)

if __name__=='__main__':main()

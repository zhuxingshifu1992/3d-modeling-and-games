"""Build the licensed Rocketbox anatomical skater and authored skate poses.
Run with Blender 5.2 --background --python tools/rider_build.py.
"""
import bpy, bmesh, math, json, hashlib, struct, numpy as np
from pathlib import Path
from mathutils import Vector, Matrix, Quaternion

BASE=Path(__file__).resolve().parents[1]
SRC=BASE/'source/rider'; OUT=BASE/'assets/rider_realistic'

def load_approved_overrides(project_root):
    """Opt in with {material: project-relative PNG}; validate before building."""
    project_root=project_root.resolve()
    config=project_root/'source/image_optimization/approved_overrides.json'
    if not config.exists():return {}
    mapping=json.loads(config.read_text(encoding='utf-8-sig'))
    if not isinstance(mapping,dict):raise ValueError('Approved overrides must be a material-to-PNG object')
    overrides={}
    for material,relative in mapping.items():
        if material not in {'CottonTee','GreenDenim'}:
            raise ValueError('Unsupported approved material: '+str(material))
        if not isinstance(relative,str) or not relative.strip():
            raise ValueError('Approved override must name a project-relative PNG: '+material)
        path=Path(relative)
        if path.is_absolute() or path.drive:
            raise ValueError('Approved override must be project-relative: '+relative)
        path=(project_root/path).resolve()
        if not path.is_relative_to(project_root):
            raise ValueError('Approved override escapes the project: '+relative)
        if path.suffix.lower()!='.png' or not path.is_file():
            raise ValueError('Approved PNG is missing or has the wrong extension: '+relative)
        with path.open('rb') as stream:header=stream.read(24)
        if len(header)!=24 or header[:8]!=b'\x89PNG\r\n\x1a\n' or header[12:16]!=b'IHDR':
            raise ValueError('Approved override is not a PNG image: '+relative)
        width,height=struct.unpack('>II',header[16:24])
        if width!=height or width<1024:
            raise ValueError('Approved PNG must be square and at least 1024 pixels: '+relative)
        overrides[material]={'path':path,'source':path.relative_to(project_root).as_posix(),
            'width':width,'height':height,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    return overrides

APPROVED_OVERRIDES=load_approved_overrides(BASE)
USED_OVERRIDES={}
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)

def import_avatar(category,name):
    before=set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=str(SRC/'originals'/category/name/'Export'/f'{name}.fbx'),use_anim=False)
    obs=[o for o in bpy.data.objects if o not in before]
    arm=next(o for o in obs if o.type=='ARMATURE')
    mesh=next(o for o in obs if o.type=='MESH')
    world=mesh.matrix_world.copy(); mesh.parent=None; mesh.matrix_world=world
    bpy.ops.object.select_all(action='DESELECT');mesh.select_set(True);bpy.context.view_layer.objects.active=mesh
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    mesh.select_set(False);arm.select_set(True);bpy.context.view_layer.objects.active=arm
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    return arm,mesh

rig,body=import_avatar('Professions','Sports_Female_01')
rig.name='RiderRig';body.name='AnatomicalSkin'
tee_rig,tee=import_avatar('Adults','Female_Adult_17')
shorts_rig,shorts=import_avatar('Adults','Female_Adult_12')

def png_image(path,name,mode='copy'):
    im=bpy.data.images.load(str(path.with_suffix('.png')),check_existing=False)
    _=im.pixels[0]
    # Keep the photographic luminance folds while changing the garment dye.
    if mode!='copy':
        pix=np.empty(len(im.pixels),dtype=np.float32);im.pixels.foreach_get(pix);a=pix.reshape((-1,4))
        lum=a[:,:3]@np.array([.25,.60,.15],dtype=np.float32)
        if mode=='white':
            shade=np.clip(lum*1.15+.26,.20,.88)
            a[:,:3]=shade[:,None]*np.array([1.,.985,.96])
        elif mode=='green':
            shade=np.clip(lum*2.2+.20,.12,.88)
            a[:,:3]=shade[:,None]*np.array([.24,.57,.33])
        elif mode=='shoe':
            neutral=np.max(a[:,:3],axis=1)-np.min(a[:,:3],axis=1)<.12
            sole=neutral&(lum>.48)
            a[:,:3]=np.clip(lum*1.1+.25,.12,.88)[:,None]*np.array([.63,.065,.075])
            a[sole,:3]=np.clip(lum[sole]*.8+.22,.4,.95)[:,None]
        im.pixels.foreach_set(pix)
    im.name=name;im.filepath_raw=str(OUT/(name+'.png'));im.file_format='PNG';im.save()
    return im

def mat(name,color_path=None,normal_path=None,mode='copy',color=(.5,.5,.5,1),rough=.7):
    m=bpy.data.materials.new(name);m.use_nodes=True
    n=m.node_tree.nodes;p=n.get('Principled BSDF');p.inputs['Base Color'].default_value=color;p.inputs['Roughness'].default_value=rough
    if 'Specular IOR Level' in p.inputs:p.inputs['Specular IOR Level'].default_value=.25
    if color_path:
        override=APPROVED_OVERRIDES.get(name)
        if override:
            color_path=override['path'];mode='copy'
        t=n.new('ShaderNodeTexImage');t.image=png_image(color_path,name+'_albedo',mode);m.node_tree.links.new(t.outputs['Color'],p.inputs['Base Color'])
        if override:
            if tuple(t.image.size)!=(override['width'],override['height']):
                raise ValueError('Decoded approved image dimensions changed: '+name)
            USED_OVERRIDES[name]={key:override[key] for key in ('source','width','height','sha256')}
            USED_OVERRIDES[name]['channel']='albedo'
            USED_OVERRIDES[name]['approval_manifest']='source/image_optimization/approved_overrides.json'
    if normal_path:
        t=n.new('ShaderNodeTexImage');t.image=png_image(normal_path,name+'_normal');t.image.colorspace_settings.name='Non-Color'
        nm=n.new('ShaderNodeNormalMap');nm.inputs['Strength'].default_value=.6
        m.node_tree.links.new(t.outputs['Color'],nm.inputs['Color']);m.node_tree.links.new(nm.outputs['Normal'],p.inputs['Normal'])
    return m

def tex(category,name,tag,part,suffix):return SRC/'originals'/category/name/'Textures'/f'{tag}_{part}_{suffix}.tga'
skin=mat('Skin',tex('Professions','Sports_Female_01','f021','body','color'),tex('Professions','Sports_Female_01','f021','body','normal'),rough=.64)
head=mat('Face',tex('Professions','Sports_Female_01','f021','head','color'),tex('Professions','Sports_Female_01','f021','head','normal'),rough=.67)
shirtmat=mat('CottonTee',tex('Adults','Female_Adult_17','f006','body','color'),tex('Adults','Female_Adult_17','f006','body','normal'),mode='white',rough=.91)
shortmat=mat('GreenDenim',tex('Adults','Female_Adult_12','f012','body','color'),tex('Adults','Female_Adult_12','f012','body','normal'),mode='green',rough=.88)
shoemat=mat('CanvasSneakers',tex('Adults','Female_Adult_12','f012','body','color'),tex('Adults','Female_Adult_12','f012','body','normal'),mode='shoe',rough=.79)
red=mat('CapCotton',color=(.32,.009,.018,1),rough=.88)
thread=mat('RedStitch',color=(.16,.008,.012,1),rough=.94)
hairmat=mat('DarkChestnut',color=(.034,.019,.012,1),rough=.53)
hairlight=mat('HairFineStrands',color=(.066,.037,.02,1),rough=.55)
white=mat('SockCotton',color=(.78,.78,.74,1),rough=.92)

original_material_indices=[p.material_index for p in body.data.polygons]
body.data.materials.clear();body.data.materials.append(skin);body.data.materials.append(head)
for polygon,index in zip(body.data.polygons,original_material_indices):polygon.material_index=index
def filter_mesh(obj,predicate):
    bm=bmesh.new();bm.from_mesh(obj.data);bm.faces.ensure_lookup_table()
    kill=[f for f in bm.faces if not predicate(f)]
    bmesh.ops.delete(bm,geom=kill,context='FACES')
    loose=[v for v in bm.verts if not v.link_faces]
    if loose:bmesh.ops.delete(bm,geom=loose,context='VERTS')
    bm.to_mesh(obj.data);bm.free();obj.data.update()

# UV layout is the original authored garment layout. Retain the actual tee
# vertices, sleeve openings and collar; remove its jeans, skin and head.
color=bpy.data.images.load(str(tex('Adults','Female_Adult_17','f006','body','color')),check_existing=False)
pix=np.empty(len(color.pixels),dtype=np.float32);color.pixels.foreach_get(pix);rgb=pix.reshape((color.size[1],color.size[0],4))
def tee_keep(f):
    if f.material_index!=0:return False
    p=f.calc_center_median()
    if p.z<1.015:return False
    uv=f.loops[0][f.loops[0].id_data.loops.layers.uv.active].uv if False else None
    # Anatomical silhouette has arm skin outside x=0.27 m. Collar stays closed.
    return (abs(p.x)<.245 and p.z<1.505) or (.245<=abs(p.x)<.315 and p.z>1.265)
filter_mesh(tee,tee_keep)
tee.name='CroppedCottonTee';tee.data.materials.clear();tee.data.materials.append(shirtmat)
for f in tee.data.polygons:f.material_index=0
# Keep the source denim seat and upper trouser topology, cropped above the knee.
shoes=shorts.copy();shoes.data=shorts.data.copy();bpy.context.collection.objects.link(shoes)
filter_mesh(shoes,lambda f:f.calc_center_median().z<.135)
shoes.name='PhotographicCanvasSneakers';shoes.data.materials.clear();shoes.data.materials.append(shoemat)
for f in shoes.data.polygons:f.material_index=0
filter_mesh(shorts,lambda f:.735<f.calc_center_median().z<1.075 and abs(f.calc_center_median().x)<.23 and f.material_index==0)
shorts.name='TailoredGreenShorts';shorts.data.materials.clear();shorts.data.materials.append(shortmat)
for f in shorts.data.polygons:f.material_index=0
for v in shorts.data.vertices:
    v.co.x*=1.055;v.co.y*=1.09
for v in tee.data.vertices:
    v.co.x*=1.025;v.co.y*=1.035
def finish_garment_edges(obj):
    bm=bmesh.new();bm.from_mesh(obj.data)
    for v in bm.verts:
        if not v.is_boundary:continue
        if obj==tee:
            if v.co.z<1.15:v.co.z=1.045
            elif abs(v.co.x)>.23:
                side=1 if v.co.x>0 else -1
                axis=Vector((side*.72,0,-.69)).normalized()
                center=Vector((side*.283,.075,1.325))
                v.co-=axis*(v.co-center).dot(axis)
            elif v.co.z>1.30:
                angle=math.atan2((v.co.y-.045)/.083,v.co.x/.098)
                v.co=Vector((.055*math.cos(angle),.053+.055*math.sin(angle),1.49))
        elif obj==shorts:
            if v.co.z>1.0:v.co.z=1.073
            elif v.co.z<.8:v.co.z=.744
    bm.to_mesh(obj.data);bm.free();obj.data.update()
finish_garment_edges(tee);finish_garment_edges(shorts)
for vertex in shorts.data.vertices:
    waist=max(0,min(1,(vertex.co.z-.95)/.123))
    vertex.co.x*=1-.04*waist;vertex.co.y*=1-.10*waist
# Covered skin is removed to prevent depth conflict and swimsuit texture leaks.
filter_mesh(body,lambda f:not ((1.035<f.calc_center_median().z<1.46 and abs(f.calc_center_median().x)<.19) or (.765<f.calc_center_median().z<1.08 and abs(f.calc_center_median().x)<.23) or f.calc_center_median().z<.115 or f.calc_center_median().z>1.656 or (f.calc_center_median().y>.142 and f.calc_center_median().z>1.575)))

for obj in [body,tee,shorts,shoes]:
    for mod in list(obj.modifiers):obj.modifiers.remove(mod)
    mod=obj.modifiers.new('AnatomicalSkinning','ARMATURE');mod.object=rig;mod.use_deform_preserve_volume=True
    # Surface refinement starts from the original anatomical edge loops.
    sub=obj.modifiers.new('AnatomicalSurface','SUBSURF');sub.levels=1;sub.render_levels=1
    bpy.context.view_layer.objects.active=obj;bpy.ops.object.select_all(action='DESELECT');obj.select_set(True)
    # Export subdivision as real geometry while keeping the armature live.
    bpy.ops.object.modifier_apply(modifier=sub.name)
    if obj in [tee,shorts]:
        solid=obj.modifiers.new('StitchedFabricThickness','SOLIDIFY');solid.thickness=.002;solid.offset=0
        bpy.ops.object.modifier_apply(modifier=solid.name)
    for f in obj.data.polygons:f.use_smooth=True
    obj.parent=rig
for obsolete in [tee_rig,shorts_rig]:bpy.data.objects.remove(obsolete,do_unlink=True)

def bind(obj,bone):
    obj.parent=rig
    g=obj.vertex_groups.new(name='Bip01 '+bone);g.add(list(range(len(obj.data.vertices))),1,'REPLACE')
    mod=obj.modifiers.new('RigidBoneAttachment','ARMATURE');mod.object=rig
    for f in obj.data.polygons:f.use_smooth=True
    return obj

def mesh_obj(name,vs,fs,material):
    me=bpy.data.meshes.new(name);me.from_pydata(vs,[],fs);me.update()
    ob=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(ob);me.materials.append(material);return ob

def tube(name,points,radius,material,bone='Head',sides=8,taper=False):
    vs=[];fs=[]
    for i,p in enumerate(points):
        p=Vector(p);d=Vector(points[min(i+1,len(points)-1)])-Vector(points[max(0,i-1)])
        q=Vector((0,0,1)).rotation_difference(d.normalized())
        width=radius*(max(.04,1-(i/(len(points)-1))**1.8) if taper else 1)
        for j in range(sides):vs.append(p+q@Vector((width*math.cos(j*math.tau/sides),width*math.sin(j*math.tau/sides),0)))
    for i in range(len(points)-1):
        for j in range(sides):a=i*sides+j;b=i*sides+(j+1)%sides;fs.append((a,b,b+sides,a+sides))
    return bind(mesh_obj(name,vs,fs,material),bone)

# Baseball cap constructed against the actual skull, with shaped visor and seams.
headpos=rig.data.bones['Bip01 Head'].head_local.copy()
cx=0.;cy=headpos.y-.008;cz=1.642
vs=[];fs=[];N=64
for i in range(13):
    t=i/12*math.pi/2;r=math.cos(t)
    for j in range(N):
        a=j*math.tau/N;vs.append((cx+.093*r*math.cos(a),cy+.107*r*math.sin(a),cz+.09*math.sin(t)))
for i in range(12):
    for j in range(N):a=i*N+j;b=i*N+(j+1)%N;fs.append((a,b,b+N,a+N))
cap=bind(mesh_obj('SixPanelRedCap',vs,fs,red),'Head')
sol=cap.modifiers.new('CapFabricThickness','SOLIDIFY');sol.thickness=.0025
for j in range(6):
    a=j*math.tau/6;tube('CapPanelSeam',[(cx+.094*math.cos(t)*math.cos(a),cy+.108*math.cos(t)*math.sin(a),cz+.091*math.sin(t)) for t in np.linspace(0,math.pi/2,14)],.0008,thread)
vs=[];fs=[]
for row in range(7):
    t=row/6
    for j in range(25):
        a=-math.pi/2+j/24*math.pi
        x=math.sin(a)*(.092+.02*t);y=cy-.05-math.cos(a)*(.055+.087*t);z=cz-.003-.012*t+.015*(x/.115)**2
        vs.append((x,y,z))
for i in range(6):
    for j in range(24):a=i*25+j;fs.append((a,a+1,a+26,a+25))
visor=bind(mesh_obj('CurvedCapVisor',vs,fs,red),'Head');sol=visor.modifiers.new('VisorThickness','SOLIDIFY');sol.thickness=.004
# Individual tapered hair locks form a swept ponytail, anchored behind the cap.
for strand in range(32):
    angle=strand*2.399963;spread=(strand/32)**.5
    pts=[]
    for i in range(9):
        t=i/8;r=.017+.01*math.sin(t*math.pi)
        pts.append((r*spread*math.cos(angle)*(1-t*.7)+.027*math.sin(t*2.5),cy+.111+.11*math.sin(t*1.4)+.011*spread*math.sin(angle),1.603-.24*t+.017*spread*math.sin(angle)*t))
    tube('PonytailLock',pts,.005 if strand<22 else .0015,hairmat if strand<22 else hairlight,sides=7,taper=True)
tiepoints=[(.026*math.cos(a),cy+.112,1.584+.021*math.sin(a)) for a in np.linspace(0,math.tau,25)]
tube('RedHairTie',tiepoints,.003,red)
# Fit each sock around the actual ankle section. The hidden lower rim follows
# the shoe/Foot; exposed rings approach the skin's Calf-dominant weighting.
for side in ['L','R']:
    ankle=rig.data.bones[f'Bip01 {side} Foot'].head_local
    sign=1 if ankle.x>0 else -1
    edges=[]
    for edge in body.data.edges:
        a,b=(body.data.vertices[index].co for index in edge.vertices)
        if a.x*sign>0 and b.x*sign>0 and max(a.z,b.z)>.12 and min(a.z,b.z)<.206:
            edges.append((a.copy(),b.copy()))
    vs=[];fs=[];ring_weights=[];rings=13;sides=32
    weight_profile=[(.095,1.0),(.108,.40),(.125,.13),(.145,.065),(.165,.02),(.185,0.0),(.205,0.0)]
    for i in range(rings):
        z=.095+.110*i/(rings-1)
        sample_z=max(.125,z)
        section=[a.lerp(b,(sample_z-a.z)/(b.z-a.z)) for a,b in edges
                 if (a.z-sample_z)*(b.z-sample_z)<=0 and abs(b.z-a.z)>1e-8]
        # Circumscribe the skin with a small fabric allowance; a fixed circular
        # tube was off-center and let the ankle protrude after the calf rolled.
        lo=Vector((min(p.x for p in section),min(p.y for p in section)))
        hi=Vector((max(p.x for p in section),max(p.y for p in section)))
        center=(lo+hi)*.5;radius=(hi-lo)*.5
        fit=max(math.hypot((p.x-center.x)/radius.x,(p.y-center.y)/radius.y) for p in section)
        cuff=.0012*max(0,(z-.193)/.012)
        radius=radius*fit+Vector((.0025+cuff,.0025+cuff))
        for j in range(sides):
            angle=j*math.tau/sides
            vs.append((center.x+radius.x*math.cos(angle),center.y+radius.y*math.sin(angle),z))
        for (z0,w0),(z1,w1) in zip(weight_profile,weight_profile[1:]):
            if z<=z1+1e-8:
                t=max(0,min(1,(z-z0)/(z1-z0)));t=t*t*(3-2*t)
                ring_weights.append(w0+(w1-w0)*t);break
    for i in range(rings-1):
        for j in range(sides):
            a=i*sides+j;b=i*sides+(j+1)%sides;fs.append((a,b,b+sides,a+sides))
    sock=bind(mesh_obj('AthleticSock_'+side,vs,fs,white),side+' Calf')
    calf_group=sock.vertex_groups['Bip01 '+side+' Calf']
    foot_group=sock.vertex_groups.new(name='Bip01 '+side+' Foot')
    for i,foot_weight in enumerate(ring_weights):
        indices=list(range(i*sides,(i+1)*sides))
        if foot_weight>=1:calf_group.remove(indices)
        else:calf_group.add(indices,1-foot_weight,'REPLACE')
        if foot_weight>0:foot_group.add(indices,foot_weight,'REPLACE')

# Batch cap, locks, seams and socks into one skinned mesh with shared materials.
accessories=[o for o in bpy.context.scene.objects if o.type=='MESH' and o not in [body,tee,shorts,shoes]]
bpy.ops.object.select_all(action='DESELECT')
for o in accessories:
    bpy.context.view_layer.objects.active=o;o.select_set(True)
    for m in list(o.modifiers):
        if m.type=='SOLIDIFY':bpy.ops.object.modifier_apply(modifier=m.name)
    o.select_set(False)
for o in accessories:o.select_set(True)
bpy.context.view_layer.objects.active=accessories[0];bpy.ops.object.join();bpy.context.object.name='CapPonytailAndSocks'

rest={b.name:b.matrix_local.copy() for b in rig.data.bones}
heads={b.name:b.head_local.copy() for b in rig.data.bones}
def V(g):return Vector((g[0],-g[2],g[1]))
def G(v):return Vector((v.x,v.z,-v.y))
def posebone(name,pos,target=None,child=None,q=None,frame=None):
    name='Bip01 '+name;pb=rig.pose.bones[name]
    if q is None:
        # Carry the parent's roll into the new limb direction. Independent
        # rest-to-target swings twist the shoulder/elbow and collapse skinning.
        if frame is None:
            frame=pb.parent.matrix.to_quaternion() @ rest[pb.parent.name].to_quaternion().inverted()
        direction=frame @ (heads['Bip01 '+child]-heads[name])
        q=direction.rotation_difference(V(target)-V(pos)) @ frame
    matrix=q.to_matrix().to_4x4()@rest[name];matrix.translation=V(pos);pb.matrix=matrix;bpy.context.view_layer.update()
def joint_g(name):
    return G(rig.pose.bones['Bip01 '+name].matrix.translation)
def inherited_joint(name):
    pb=rig.pose.bones['Bip01 '+name]
    return G(pb.parent.matrix @ rest[pb.parent.name].inverted() @ heads[pb.name])
def ik(hip,ankle,l1,l2,bend):
    d=ankle-hip;dist=d.length;axis=d.normalized();a=(l1*l1-l2*l2+dist*dist)/(2*dist);h=max(0,l1*l1-a*a)**.5
    pole=Vector(bend);pole=(pole-axis*pole.dot(axis)).normalized();return hip+axis*a+pole*h

def make_pose(label,tuck=0,brake=0,push=0):
    for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
    bpy.context.view_layer.update()
    hip=Vector((.015,.82-.14*tuck-.07*push,.065+.03*tuck))
    yaw=Quaternion(Vector((0,0,1)),-1.85)
    # Rest avatar faces Blender -Y; this turns the hips into a regular skate stance.
    posebone('Pelvis',hip,q=yaw)
    # Turn toward travel progressively, keeping the source joint spacing with
    # forward kinematics instead of rotating every spine origin around the hips.
    headlook=Quaternion(Vector((0,0,1)),math.pi-.12)
    torso_yaw=yaw.slerp(headlook,.28)
    lean=Vector((-.08,.86-.22*tuck,-.43-.40*tuck)).normalized()
    chestq=Vector((0,0,1)).rotation_difference(V(lean)) @ torso_yaw
    for name,amount in [('Spine',.55),('Spine1',.80),('Spine2',1.0)]:
        posebone(name,inherited_joint(name),q=yaw.slerp(chestq,amount))
    posebone('Neck',inherited_joint('Neck'),q=chestq.slerp(headlook,.5))
    posebone('Head',inherited_joint('Head'),q=headlook)
    # Clavicles are parented to Neck in this Biped. Keep the shoulder girdle
    # with the chest while the neck turns independently toward the road.
    for side in ['L','R']:
        name=side+' Clavicle'
        offset=chestq @ (heads['Bip01 '+name]-heads['Bip01 Neck'])
        posebone(name,joint_g('Neck')+G(offset),q=chestq)
    forward=G(torso_yaw @ Vector((0,-1,0)))
    lateral=G(torso_yaw @ Vector((1,0,0)))
    for side,sgn in [('L',-1),('R',1)]:
        offset=yaw @ (heads[f'Bip01 {side} Thigh']-heads['Bip01 Pelvis'])
        thigh=hip+Vector((offset.x,offset.z,-offset.y))
        ankle=Vector((-.018 if side=='L' else .018,.265,.295 if side=='L' else -.315))
        if side=='L':ankle+=Vector((.20*push,-.165*push,.28*push))
        l1=(heads[f'Bip01 {side} Calf']-heads[f'Bip01 {side} Thigh']).length
        l2=(heads[f'Bip01 {side} Foot']-heads[f'Bip01 {side} Calf']).length
        knee=ik(thigh,ankle,l1,l2,(-1,0,-.06))
        # Biped parents thighs under Spine; their anatomical reference remains
        # the pelvis, so torso articulation must not twist the leg frames.
        posebone(side+' Thigh',thigh,knee,side+' Calf',frame=yaw)
        posebone(side+' Calf',knee,ankle,side+' Foot')
        footyaw=Quaternion(Vector((0,0,1)),-1.88 if side=='L' else -1.72)
        posebone(side+' Foot',ankle,q=footyaw)
        shoulder=joint_g(side+' UpperArm')
        outward=lateral*(-sgn)
        wrist=hip+forward*(.19+.08*tuck+.04*brake)
        wrist+=outward*(.24-.055*tuck+.06*brake)
        wrist+=Vector((0,.18-.025*tuck+.055*brake,0))
        upper_length=(heads[f'Bip01 {side} Forearm']-heads[f'Bip01 {side} UpperArm']).length
        lower_length=(heads[f'Bip01 {side} Hand']-heads[f'Bip01 {side} Forearm']).length
        reach=wrist-shoulder
        # Keep useful elbow flexion for balance rather than locking at 98% reach.
        arm_length=upper_length+lower_length
        wrist=shoulder+reach.normalized()*max(arm_length*.60,min(reach.length,arm_length*.86))
        elbow=ik(shoulder,wrist,upper_length,lower_length,outward*.45+forward*.25+Vector((0,-1,0)))
        posebone(side+' UpperArm',shoulder,elbow,side+' Forearm')
        posebone(side+' Forearm',elbow,wrist,side+' Hand')
        # The donor's finger joints flex about local Z. Small additional curls
        # keep the relaxed source hand shape while eliminating the flat mitt pose.
        hand=rig.pose.bones['Bip01 '+side+' Hand'];hand.rotation_mode='QUATERNION'
        hand.rotation_quaternion=Quaternion(Vector((0,0,1)),math.radians(6))
        for finger in range(5):
            curls=(5,8,5) if finger==0 else (10+finger*1.5,15+finger*1.5,8+finger)
            for suffix,degrees in zip(('', '1', '2'),curls):
                pb=rig.pose.bones[f'Bip01 {side} Finger{finger}{suffix}']
                pb.rotation_mode='QUATERNION'
                pb.rotation_quaternion=Quaternion(Vector((0,0,1)),math.radians(degrees))
    bpy.context.view_layer.update()
    act=bpy.data.actions.new(label);rig.animation_data_create();rig.animation_data.action=act
    for pb in rig.pose.bones:
        pb.rotation_mode='QUATERNION';pb.keyframe_insert('location',frame=1);pb.keyframe_insert('rotation_quaternion',frame=1);pb.keyframe_insert('scale',frame=1)
    return act

actions=[]
for name,t,b,p in [('Ride',0,0,0),('Tuck',1,0,0),('Brake',0,1,0),('Push',0,0,1)]:actions.append(make_pose(name,t,b,p))
rig.animation_data.action=None
for action in actions:
    track=rig.animation_data.nla_tracks.new();track.name=action.name;strip=track.strips.new(action.name,1,action);strip.action_frame_end=2
    track.mute=True
rig.animation_data.action=actions[0];bpy.context.scene.frame_set(1)

# Save reusable editable geometry, textures, skeleton and pose actions.
for material in list(bpy.data.materials):
    if material.users==0:bpy.data.materials.remove(material)
for image in list(bpy.data.images):
    if image.users==0:bpy.data.images.remove(image)
for image in bpy.data.images:
    if image.has_data:image.pack()
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'rider_realistic.blend'))
bpy.ops.object.select_all(action='DESELECT')
for obj in bpy.context.scene.objects:
    if obj.type in {'MESH','ARMATURE'}:obj.select_set(True)
bpy.context.view_layer.objects.active=rig
bpy.ops.export_scene.gltf(filepath=str(OUT/'rider.glb'),export_format='GLB',use_selection=True,export_apply=True,export_animations=True,export_animation_mode='ACTIONS',export_force_sampling=True,export_frame_range=False,export_anim_single_armature=True,export_all_influences=False,export_def_bones=True)
summary={'source':'Microsoft Rocketbox','upstream_commit':'0943055db6ec570bcef9f2c8b41c9e5467c808f9','bones':len(rig.data.bones),'meshes':[{'name':o.name,'vertices':len(o.data.vertices),'polygons':len(o.data.polygons)} for o in bpy.data.objects if o.type=='MESH'],'actions':[a.name for a in actions]}
if USED_OVERRIDES:summary['material_overrides']=USED_OVERRIDES
(OUT/'manifest.json').write_text(json.dumps(summary,indent=2))
print('RIDER_BUILD_DONE',json.dumps(summary))

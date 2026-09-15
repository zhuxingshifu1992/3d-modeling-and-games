"""Editable, articulated Blender assets for Last Current. All inputs are metres
in Godot axes (+Y up, -Z forward); export preserves that convention. No downloads.
Run: blender --background --python source/build_detailed_models.py
"""
import bpy, bmesh, math, json, random
import numpy as np
from pathlib import Path
from mathutils import Vector, Matrix, Euler
from math import sin, cos, pi

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/models/detail'
TEX=ROOT/'assets/textures/equipment'
OUT.mkdir(parents=True,exist_ok=True); TEX.mkdir(parents=True,exist_ok=True)
G=Matrix(((1,0,0),(0,0,-1),(0,1,0)))
M={}; COLL=None; JOINTS=[]; ASSETS=[]; ATLAS=None
random.seed(17)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)

def cv(v): return G@Vector(v)
def link(o):
    for c in list(o.users_collection): c.objects.unlink(o)
    COLL.objects.link(o)
    return o
def empty(name,parent=None,pos=(0,0,0)):
    o=bpy.data.objects.new(name,None); COLL.objects.link(o); o.parent=parent; o.location=cv(pos)
    o.empty_display_size=.08; JOINTS.append(o); return o
def uv_planar(o,scale=.14):
    me=o.data; me.update(); uv=me.uv_layers.active or me.uv_layers.new(name='UVMap')
    for f in me.polygons:
        axis=max(range(3),key=lambda a:abs(f.normal[a])); a,b=((1,2),(0,2),(0,1))[axis]
        for li in f.loop_indices:
            p=me.vertices[me.loops[li].vertex_index].co; uv.data[li].uv=(p[a]/scale,p[b]/scale)
def finish(o,name,parent,mat,bevel=0,smooth=False):
    o.name=name; link(o); o.parent=parent; o.data.materials.append(M[mat]); uv_planar(o)
    if bevel:
        mod=o.modifiers.new('Machined edge radius','BEVEL'); mod.width=bevel; mod.segments=3
        mod.affect='EDGES'; mod.harden_normals=True
        bpy.context.view_layer.objects.active=o; bpy.ops.object.modifier_apply(modifier=mod.name)
        mod=o.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL'); mod.keep_sharp=True; mod.weight=40
        bpy.ops.object.modifier_apply(modifier=mod.name)
    if smooth:
        for p in o.data.polygons: p.use_smooth=True
    return o
def box(p,n,loc,size,mat,bev=.003,rot=(0,0,0)):
    bpy.ops.mesh.primitive_cube_add(size=1)
    o=bpy.context.object; o.scale=(size[0],size[2],size[1]); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    o.location=cv(loc); o.rotation_euler=(G@Euler(rot,'XYZ').to_matrix()@G.transposed()).to_euler()
    return finish(o,n,p,mat,min(bev,min(size)*.44))
def ell(p,n,loc,size,mat,seg=24,rings=14):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg,ring_count=rings,radius=1)
    o=bpy.context.object; o.scale=(size[0]/2,size[2]/2,size[1]/2); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    o.location=cv(loc); return finish(o,n,p,mat,0,True)
def tube(p,n,a,b,r,mat,r2=None,seg=16):
    av,bv=cv(a),cv(b); d=bv-av
    bpy.ops.mesh.primitive_cone_add(vertices=seg,radius1=r,radius2=r if r2 is None else r2,depth=d.length)
    o=bpy.context.object; o.location=(av+bv)/2; o.rotation_mode='QUATERNION'; o.rotation_quaternion=Vector((0,0,1)).rotation_difference(d.normalized())
    return finish(o,n,p,mat,min(r*.15,.0015),True)
def path(p,n,points,r,mat):
    cu=bpy.data.curves.new(n,'CURVE'); cu.dimensions='3D'; cu.resolution_u=1; cu.bevel_depth=r; cu.bevel_resolution=2
    sp=cu.splines.new('POLY'); sp.points.add(len(points)-1)
    for q,v in zip(sp.points,points): q.co=(*cv(v),1)
    ob=bpy.data.objects.new(n,cu); COLL.objects.link(ob); ob.parent=p; cu.materials.append(M[mat])
    bpy.ops.object.select_all(action='DESELECT'); ob.select_set(True); bpy.context.view_layer.objects.active=ob; bpy.ops.object.convert(target='MESH')
    uv_planar(ob); return ob
def profile(p,n,rings,mat,sides=24,fold=0):
    # rings are (height, half-width, half-depth, x-offset, z-offset).
    verts=[]; faces=[]
    for j,(y,rx,rz,ox,oz) in enumerate(rings):
        for i in range(sides):
            a=2*pi*i/sides; wave=1+fold*(sin(a*5+j*1.8)+.4*sin(a*9-j*.7))
            verts.append(cv((ox+rx*cos(a)*wave,y,oz+rz*sin(a)*wave)))
    for j in range(len(rings)-1):
        for i in range(sides):
            k=j*sides+i; ni=j*sides+(i+1)%sides
            faces.append((k,ni,ni+sides,k+sides))
    faces+=[tuple(reversed(range(sides))),tuple((len(rings)-1)*sides+i for i in range(sides))]
    me=bpy.data.meshes.new(n); me.from_pydata(verts,[],faces); me.update()
    bm=bmesh.new(); bm.from_mesh(me); bmesh.ops.recalc_face_normals(bm,faces=bm.faces); bm.to_mesh(me); bm.free()
    o=bpy.data.objects.new(n,me); COLL.objects.link(o); o.parent=p; me.materials.append(M[mat]); uv_planar(o)
    for f in me.polygons: f.use_smooth=True
    if mat in ['cloth','flankcloth','heavycloth','webbing'] and len(rings)>3:
        bpy.context.view_layer.objects.active=o
        sub=o.modifiers.new('Soft tailored fabric surface','SUBSURF'); sub.levels=1; sub.render_levels=1
        bpy.ops.object.modifier_apply(modifier=sub.name)
    return o
def prism(p,n,poly,width,mat,bev=.003):
    verts=[cv((x,y,z)) for x in [-width/2,width/2] for y,z in poly]; L=len(poly)
    faces=[tuple(reversed(range(L))),tuple(range(L,2*L))]+[(i,(i+1)%L,(i+1)%L+L,i+L) for i in range(L)]
    me=bpy.data.meshes.new(n); me.from_pydata(verts,[],faces); me.update()
    bm=bmesh.new(); bm.from_mesh(me); bmesh.ops.recalc_face_normals(bm,faces=bm.faces); bm.to_mesh(me); bm.free()
    o=bpy.data.objects.new(n,me); COLL.objects.link(o)
    return finish(o,n,p,mat,bev)
def text_mesh(p,n,label,loc,size,mat):
    cu=bpy.data.curves.new(n,'FONT'); cu.body=label; cu.size=size; cu.extrude=.00015
    ob=bpy.data.objects.new(n,cu); COLL.objects.link(ob); ob.parent=p; ob.location=cv(loc)
    # Lie on weapon right face, horizontal text along its length.
    ob.rotation_euler=(pi/2,0,pi/2); cu.materials.append(M[mat])
    bpy.ops.object.select_all(action='DESELECT'); ob.select_set(True); bpy.context.view_layer.objects.active=ob; bpy.ops.object.convert(target='MESH'); uv_planar(ob)
    return ob

def material(name,color,metal=0,rough=.7,kind='cloth'):
    # Embedded image textures survive glTF; microgeometry is actual mesh bevels.
    N=256; rng=np.random.default_rng(sum(map(ord,name)))
    y,x=np.mgrid[0:N,0:N]; rnd=rng.random((N,N))
    coarse=np.zeros((N,N))
    for freq,amp in [(5,.028),(13,.016),(37,.008)]:
        lattice=rng.random((freq,freq))-.5
        grid=np.linspace(0,freq-1,N); first=np.array([np.interp(grid,np.arange(freq),row) for row in lattice])
        coarse+=np.array([np.interp(grid,np.arange(freq),col) for col in first.T]).T*amp
    weave=(np.sin(x*pi*.75)*np.cos(y*pi*.8)*.010) if kind=='cloth' else np.sin(x*.21+y*.003)*.006
    noise=coarse+(rnd-.5)*(.10 if kind=='cloth' else .055)+weave
    rgb=np.clip(np.array(color)[None,None,:]*(1+noise[:,:,None]*2.2),.005,.92)
    if kind=='metal':
        for k in range(90):
            a,b=rng.integers(0,N,size=2); ln=int(rng.integers(2,20)); rgb[b,min(a,N-1):min(a+ln,N),:]=np.array(color)*1.75+.04
    if kind=='leather': rgb *= (1-0.06*(np.sin(x*.36)*np.cos(y*.32)>0.82))[:,:,None]
    rgba=np.concatenate([rgb,np.ones((N,N,1))],2).astype(np.float32)
    im=bpy.data.images.new(name+'_albedo',width=N,height=N); im.pixels.foreach_set(rgba.ravel()); im.filepath_raw=str(TEX/(name+'_albedo.png')); im.file_format='PNG'; im.save(); im.pack()
    m=bpy.data.materials.new(name); m.use_nodes=True; bs=m.node_tree.nodes.get('Principled BSDF'); bs.inputs['Metallic'].default_value=metal; bs.inputs['Roughness'].default_value=rough
    tx=m.node_tree.nodes.new('ShaderNodeTexImage'); tx.image=im; m.node_tree.links.new(tx.outputs['Color'],bs.inputs['Base Color'])
    # Small surface relief, normal texture rather than unsupported procedural nodes.
    h=noise*(.20 if kind=='cloth' else .065); dy,dx=np.gradient(h)
    normal=np.stack([-dx,-dy,np.ones_like(dx)],2); normal/=np.linalg.norm(normal,axis=2)[:,:,None]; normal=normal*.5+.5
    nm=bpy.data.images.new(name+'_normal',width=N,height=N); nm.colorspace_settings.name='Non-Color'; nm.pixels.foreach_set(np.concatenate([normal,np.ones((N,N,1))],2).astype(np.float32).ravel()); nm.filepath_raw=str(TEX/(name+'_normal.png')); nm.file_format='PNG'; nm.save(); nm.pack()
    nt=m.node_tree.nodes.new('ShaderNodeTexImage'); nt.image=nm; ns=m.node_tree.nodes.new('ShaderNodeNormalMap'); ns.inputs['Strength'].default_value=.35; m.node_tree.links.new(nt.outputs['Color'],ns.inputs['Color']); m.node_tree.links.new(ns.outputs['Normal'],bs.inputs['Normal'])
    M[name]=m; return m

for args in [
 ('anodized',(.16,.18,.19),.78,.38,'metal'),('edge',(.30,.32,.30),.82,.32,'metal'),('steel',(.19,.21,.205),.80,.38,'metal'),
 ('polymer',(.10,.115,.105),.05,.78,'leather'),('rubber',(.040,.048,.044),0,.88,'leather'),('wood',(.24,.12,.052),.05,.58,'leather'),
 ('brass',(.50,.31,.085),.72,.33,'metal'),('red',(.33,.078,.035),.15,.62,'metal'),
 ('cloth',(.25,.24,.175),0,.91,'cloth'),('flankcloth',(.255,.21,.15),0,.93,'cloth'),('heavycloth',(.15,.19,.16),0,.92,'cloth'),
 ('webbing',(.19,.18,.12),0,.88,'cloth'),('leather',(.17,.13,.084),0,.82,'leather'),('plate',(.145,.18,.16),.50,.58,'metal'),
 ('stitch',(.42,.38,.265),0,.9,'cloth'),('skin',(.39,.255,.175),0,.70,'leather'),('lens',(.08,.19,.18),.65,.15,'metal')]: material(*args)

def fastener(p,loc,axis='x',radius=.0028):
    d=Vector((.002,0,0)) if axis=='x' else Vector((0,0,.002)); a=Vector(loc)
    tube(p,'Hex screw',a-d,a+d,radius,'edge',seg=6)
    if axis=='x': box(p,'Screw driver slot',a+d*1.05,(.0008,.0007,radius*1.25),'rubber',.0001)

def glove(p,n,loc=(0,0,0),size=1,gripping=True):
    hand=empty(n,p,loc)
    ell(hand,'Palm with thumb pad',(0,0,0),(.072*size,.095*size,.047*size),'leather')
    ell(hand,'Back of glove',(0,.004,.012*size),(.074*size,.073*size,.028*size),'cloth')
    for i in range(4):
        x=(-.028+i*.019)*size; length=(.060 if i in [1,2] else .052)*size
        a=(x,-.028*size,0); b=(x,-.05*size,-.022*size if gripping else 0); c=(x,-.033*size,-.048*size) if gripping else (x,-.028*size-length,0)
        tube(hand,'Finger proximal',a,b,.009*size,'leather',r2=.008*size,seg=12)
        tube(hand,'Finger distal',b,c,.008*size,'leather',r2=.0065*size,seg=12)
        ell(hand,'Knuckle padding',(x,-.018*size,.023*size),(.015*size,.020*size,.011*size),'polymer',16,8)
    tube(hand,'Thumb base',(.032*size,.017*size,0),(.045*size,-.010*size,-.014*size),.012*size,'leather',r2=.009*size)
    tube(hand,'Thumb curled tip',(.045*size,-.010*size,-.014*size),(.028*size,-.025*size,-.039*size),.009*size,'leather',r2=.007*size)
    box(hand,'Cuff closure',(0,.047*size,0),(.071*size,.023*size,.047*size),'rubber',.006)
    path(hand,'Glove stitched panel',[(-.025*size,.025*size,.028*size),(-.028*size,-.008*size,.028*size),(.028*size,-.008*size,.028*size),(.025*size,.025*size,.028*size)],.0009*size,'stitch')
    return hand

def sleeve_between(p,n,a,b,r,mat):
    pivot=empty(n,p,a); d=Vector(b)-Vector(a); L=d.length
    pivot.rotation_mode='QUATERNION'; pivot.rotation_quaternion=cv((0,-1,0)).rotation_difference(cv(d).normalized())
    rings=[]
    for i in range(13):
        f=i/12; bulge=(1-f)*r+f*r*.66; bulge*=1+.055*sin(i*2.3)
        rings.append((-f*L,bulge,bulge*.86,0,0))
    profile(pivot,'Sleeve tailored volume',rings,mat,20,.025)
    for i in [3,5,8]:
        yy=-L*i/12; path(pivot,'Fabric crease',[(r*cos(t),yy+.008*sin(t*2),r*.85*sin(t)) for t in np.linspace(.6,2.7,13)],.0014,'webbing')
    return pivot

def weapon(parent,kind='rifle',hands=False):
    gun=empty('R7_Carbine' if kind=='rifle' else 'Breacher_Shotgun',parent)
    rifle=kind=='rifle'
    prism(gun,'Chamfered upper receiver',[(.035,.065),(.061,.030),(.061,-.28),(.034,-.325),(-.012,-.305),(-.016,.05)],.064,'anodized',.005)
    prism(gun,'Lower receiver and magazine well',[(-.01,.045),(-.048,.035),(-.050,-.045),(-.036,-.12),(-.065,-.145),(-.062,-.245),(-.012,-.265)],.060,'steel',.004)
    box(gun,'Ejection port shadow',(.034,.018,-.162),(.003,.026,.094),'rubber',.002)
    box(gun,'Bolt visible in ejection port',(.036,.021,-.17),(.003,.016,.048),'edge',.002)
    path(gun,'Port beveled lip',[(.037,.033,-.216),(.037,.034,-.107),(.037,.004,-.107)],.0016,'edge')
    tube(gun,'Charging handle',(.030,.036,-.08),(.060,.036,-.08),.0045,'steel',seg=16)
    ell(gun,'Charging handle knob',(.061,.036,-.08),(.015,.013,.023),'polymer',16,8)
    for z in [-.235,-.105,.030]: fastener(gun,(.034,-.007,z))
    tube(gun,'Selector lever',(.035,-.024,-.006),(.045,-.040,.006),.0028,'edge')
    # Open trigger guard and visible curved trigger.
    path(gun,'Open trigger guard',[(.0,-.046,-.055),(.0,-.093,-.066),(.0,-.101,-.022),(.0,-.061,.011)],.004,'anodized')
    path(gun,'Curved trigger',[(0,-.044,-.047),(0,-.065,-.040),(0,-.075,-.028)],.0025,'edge')
    grip=prism(gun,'Contoured pistol grip',[(-.045,.005),(-.071,.045),(-.19,.085),(-.205,.032),(-.112,-.002)],.042,'polymer',.009)
    for i in range(6): box(gun,'Grip textured rib',(.023,-.102-i*.012,.032+i*.003),(.002,.003,.037),'rubber',.001)
    tube(gun,'Stock extension',(0,.022,.06),(0,.022,.255),.019,'steel')
    prism(gun,'Skeleton stock cheek rest',[(.052,.095),(.055,.277),(.012,.326),(-.072,.306),(-.068,.281),(.001,.247),(-.002,.109)],.058,'polymer',.007)
    box(gun,'Rubber shoulder pad',(0,-.011,.308),(.070,.137,.021),'rubber',.009)
    for yy in [-.055,-.035,-.015,.005,.025]: box(gun,'Buttpad grooves',(0,yy,.321),(.056,.005,.003),'leather',.001)
    if rifle:
        magazine=empty('Magazine',gun,(0,-.059,-.191))
        profile(magazine,'Curved stamped magazine',[(0,.029,.047,0,0),(-.045,.029,.047,0,.004),(-.105,.029,.047,0,.011),(-.17,.028,.046,0,.027),(-.205,.028,.045,0,.043)],'steel',8,0)
        for x in [-.0298,.0298]:
            for z in [-.026,0,.026]: path(magazine,'Magazine stiffening flute',[(x,-.035,z),(x,-.10,z+.010),(x,-.181,z+.035)],.002,'anodized')
        box(magazine,'Magazine baseplate',(0,-.205,.043),(.064,.014,.097),'polymer',.003)
        tube(gun,'Free floating barrel',(0,.024,-.28),(0,.024,-.94),.012,'steel',seg=24)
        # Side slots are real gaps assembled from an octagonal frame, not black stickers.
        for x in [-.039,.039]:
            for yy in [-.009,.050]: box(gun,'Handguard side rail',(x,yy,-.491),(.010,.018,.333),'anodized',.003)
            for z in [-.336,-.404,-.472,-.540,-.607,-.654]: box(gun,'Handguard slot divider',(x,.020,z),(.010,.049,.012),'anodized',.003)
            for z in [-.360,-.428,-.496,-.564,-.632]: fastener(gun,(x*1.15,-.010,z),radius=.0023)
        box(gun,'Handguard underside',(0,-.017,-.493),(.065,.016,.34),'polymer',.003)
        for z in np.arange(-.64,-.29,.021): box(gun,'Picatinny rail tooth',(0,.072,float(z)),(.038,.010,.010),'edge',.001)
        tube(gun,'Gas block',(0,.025,-.705),(0,.025,-.738),.021,'anodized',seg=20)
        tube(gun,'Muzzle brake',(0,.024,-.934),(0,.024,-.984),.018,'anodized',seg=24)
        tube(gun,'Dark bore opening',(0,.024,-.985),(0,.024,-.987),.010,'rubber',seg=24)
        for zz in [-.944,-.958,-.972]:
            for xx in [-.0185,.0185]: box(gun,'Brake port',(xx,.024,zz),(.002,.010,.006),'rubber',.001)
        # Clear optic window aligns with the gameplay reticle at ADS.
        for x in [-.025,.025]: box(gun,'Reflex optic sidewall',(x,.126,-.16),(.007,.043,.028),'polymer',.003)
        for yy in [.105,.147]: box(gun,'Reflex optic crossbar',(0,yy,-.16),(.054,.007,.030),'polymer',.002)
        box(gun,'Optic mount',(0,.077,-.16),(.056,.021,.070),'anodized',.003)
        tube(gun,'Optic adjuster',(.028,.125,-.16),(.038,.125,-.16),.009,'edge',seg=16)
        box(gun,'Front sight foot',(0,.058,-.731),(.025,.028,.025),'anodized',.002)
        tube(gun,'Front sight pin',(0,.068,-.731),(0,.091,-.731),.002,'edge',seg=12)
        text_mesh(gun,'R7 laser marking','R7  /  7-19',(.037,.043,-.265),.010,'stitch')
        text_mesh(gun,'Serial stamping','LC  0417',(.037,-.018,-.25),.006,'edge')
    else:
        tube(gun,'Shotgun barrel',(0,.027,-.27),(0,.027,-.94),.019,'steel',seg=24)
        tube(gun,'Magazine tube',(0,-.020,-.28),(0,-.020,-.795),.017,'anodized',seg=24)
        tube(gun,'Tube cap',(0,-.020,-.792),(0,-.020,-.812),.022,'edge',seg=20)
        pump=ell(gun,'Rounded walnut pump',(0,-.010,-.540),(.085,.098,.258),'wood',32,16)
        for z in np.linspace(-.64,-.45,10):
            # Follow the elliptical fore-end surface so end grooves do not float.
            section=math.sqrt(1-((float(z)+.540)/.129)**2)
            path(gun,'Pump grip flute',[(.0425*section*cos(t),-.01+.049*section*sin(t),float(z)) for t in np.linspace(0,2*pi,48)],.0009,'leather')
        for x in [-.025,.025]: tube(gun,'Action slide bar',(x,-.025,-.310),(x,-.025,-.510),.0035,'steel')
        for z in [-.15,-.103,-.056,.0]:
            tube(gun,'Side saddle cartridge',(-.048,-.025,z),(-.048,.040,z),.0105,'red',seg=16)
            tube(gun,'Cartridge brass rim',(-.048,.04,z),(-.048,.052,z),.011,'brass',seg=16)
        tube(gun,'Shotgun muzzle ring',(0,.027,-.933),(0,.027,-.951),.022,'anodized',seg=24)
        tube(gun,'Shotgun bore',(0,.027,-.952),(0,.027,-.953),.015,'rubber',seg=24)
        ell(gun,'Bead sight',(0,.052,-.887),(.007,.007,.007),'brass',12,8)
        text_mesh(gun,'Shotgun model marking','BREACHER',(.036,.041,-.26),.009,'edge')
    if hands:
        # A complete two-handed first-person grip, including curved fingers and cuffs.
        sleeve_between(gun,'RightSleeve',(.23,-.24,.37),(.065,-.142,.09),.055,'cloth')
        rh=glove(gun,'RightHand',(.037,-.103,.043),1.0); rh.rotation_euler=(G@Euler((-.16,0,-.13),'XYZ').to_matrix()@G.transposed()).to_euler()
        sleeve_between(gun,'LeftSleeve',(-.23,-.25,.24),(-.058,-.081,-.44),.051,'cloth')
        lh=glove(gun,'LeftHand',(-.032,-.053,-.477),1.0); lh.rotation_euler=(G@Euler((-.20,0,-pi/2),'XYZ').to_matrix()@G.transposed()).to_euler()
    return gun

def pouch(p,n,loc,size=(.10,.14,.067)):
    box(p,n,loc,size,'webbing',.012)
    box(p,n+' flap',(loc[0],loc[1]+size[1]*.27,loc[2]-size[2]*.51),(size[0]*.93,size[1]*.35,.010),'cloth',.006)
    box(p,n+' fastener',(loc[0],loc[1]+size[1]*.10,loc[2]-size[2]*.60),(.013,.035,.007),'rubber',.002)
    path(p,n+' seam',[(loc[0]-size[0]*.39,loc[1]-size[1]*.36,loc[2]-size[2]*.52),(loc[0]+size[0]*.39,loc[1]-size[1]*.36,loc[2]-size[2]*.52)],.0009,'stitch')

def humanoid(role):
    root=empty('Raider_'+role); cloth={'rifle':'cloth','flanker':'flankcloth','heavy':'heavycloth'}[role]; bulk=1.08 if role=='heavy' else .96 if role=='flanker' else 1
    hips=empty('Hips',root,(0,.9,0))
    profile(hips,'Jacket hem and pelvis',[(-.095,.175*bulk,.110,0,0),(-.055,.195*bulk,.127,0,0),(.04,.185*bulk,.124,0,0),(.10,.169*bulk,.113,0,0)],cloth,28,.025)
    profile(hips,'Woven utility belt',[(.025,.189*bulk,.130,0,0),(.068,.180*bulk,.126,0,0)],'webbing',32,0)
    box(hips,'Belt buckle',(0,.047,-.130),(.045,.037,.011),'edge',.004)
    for s in [-1,1]: pouch(hips,'Utility hip pouch',(s*.191*bulk,-.005,-.025),(.074,.133,.097))
    torso=empty('Torso',hips,(0,.10,0))
    rings=[(-.02,.175,.115),(0.04,.174,.117),(.12,.190,.128),(.20,.214,.140),(.29,.223,.143),(.37,.233,.132),(.42,.213,.110),(.455,.118,.085)]
    profile(torso,'Tailored combat jacket',[(y,x*bulk,z,0,.010) for y,x,z in rings],cloth,32,.025)
    profile(torso,'Raised fabric collar',[(.425,.096,.074,0,.005),(.470,.086,.067,0,.005),(.503,.070,.061,0,.005)],'webbing',28,.018)
    path(torso,'Jacket centre zip',[(0,y,-z-.002) for y,x,z in rings[:-1]],.0016,'rubber')
    for s in [-1,1]:
        path(torso,'Shoulder stitched yoke',[(s*.10,.43,-.065),(s*.20,.40,-.095),(s*.228,.36,-.115)],.0015,'stitch')
        box(torso,'Shoulder harness',(s*.14,.335,-.145),(.045,.26,.017),'webbing',.005,rot=(0,0,s*-.13))
        box(torso,'Harness ladderlock',(s*.14,.28,-.16),(.037,.042,.007),'polymer',.004)
    # Shaped plate carrier silhouette, with rounded chamfered corners and cloth edge binding.
    profile(torso,'Plate carrier soft shell',[(.06,.171*bulk,.055,0,-.145),(.13,.186*bulk,.053,0,-.152),(.30,.183*bulk,.048,0,-.151),(.365,.133*bulk,.042,0,-.134)],'webbing',16,.01)
    plate=box(torso,'Curved chest armour',(0,.252,-.184),(.295*bulk,.238,.036),'plate',.022)
    for yy in [.105,.140,.175,.21]:
        for xx in [-.12,-.06,0,.06,.12]: box(torso,'MOLLE webbing loop',(xx,yy,-.207),(.047,.014,.008),'webbing',.002)
    for x in [-.106,0,.106]: pouch(torso,'Ammunition pouch',(x,.065,-.225),(.091,.153,.063))
    box(torso,'Chest identification patch',(-.04,.322,-.205),(.094,.035,.003),'rubber',.001)
    for i in range(4): box(torso,'Patch worn lettering',(-.072+i*.018,.323,-.208),(.009,.014,.001),'stitch',.0002)
    # Small radio and flexible aerial add recognizable purpose to the silhouette.
    box(torso,'Radio housing',(.17,.225,-.201),(.051,.106,.030),'polymer',.006)
    tube(torso,'Radio antenna',(.185,.28,-.20),(.193,.47,-.19),.003,'rubber')
    path(torso,'Radio wire',[(.16,.277,-.202),(.19,.36,-.17),(.13,.41,-.13)],.002,'rubber')
    box(torso,'Canvas backpack',(0,.23,.178),(.28,.36,.146),cloth,.038)
    for yy in [.09,.26]: box(torso,'Backpack compression strap',(0,yy,.254),(.29,.025,.010),'webbing',.003)
    ell(torso,'Rolled field blanket',(0,.424,.192),(.30,.09,.10),'leather',24,12)
    for xx in [-.10,.10]: path(torso,'Blanket strap',[(xx,.405,.14),(xx,.47,.19),(xx,.416,.242)],.005,'webbing')
    head=empty('Head',torso,(0,.585,0))
    tube(head,'Neck',(0,-.15,0),(0,-.07,0),.054,'skin',r2=.05,seg=24)
    profile(head,'Jaw cranium anatomy',[(-.106,.046,.052,0,-.013),(-.072,.071,.078,0,-.01),(-.02,.084,.087,0,0),(.046,.085,.091,0,.005),(.099,.072,.079,0,.01),(.126,.03,.037,0,.006)],'skin',32,.002)
    for s in [-1,1]:
        ell(head,'Ear',(s*.083,-.012,.009),(.028,.057,.037),'skin',20,12)
        ell(head,'Eye brow',(s*.040,.031,-.083),(.054,.014,.017),'leather',20,10)
        ell(head,'Eye socket',(s*.038,.012,-.084),(.047,.020,.018),'rubber',20,10)
    prism(head,'Anatomical nose bridge',[(.025,-.077),(-.025,-.113),(-.039,-.102),(-.030,-.077)],.026,'skin',.004)
    # Balaclava / scarf protects the lower face, leaving the cheek and eye anatomy readable.
    profile(head,'Fabric face wrap',[(-.113,.050,.065,0,-.014),(-.086,.072,.076,0,-.026),(-.058,.080,.087,0,-.017),(-.025,.077,.084,0,-.015)],'leather',28,.04)
    for yy in [-.047,-.066,-.088]: path(head,'Mask cloth fold',[(-.068,yy+.004,-.073),(-.033,yy,-.107),(0,yy-.003,-.113),(.036,yy+.003,-.10),(.068,yy,-.073)],.0015,'webbing')
    # Two contoured goggle lenses in individual frames; no square head block.
    for s in [-1,1]:
        ell(head,'Goggle rubber gasket',(s*.042,.022,-.091),(.089,.057,.028),'rubber',24,14)
        ell(head,'Convex smoke goggle lens',(s*.042,.024,-.107),(.072,.043,.013),'lens',24,14)
        fastener(head,(s*.078,.023,-.112),'z',.002)
    tube(head,'Goggle bridge',(-.01,.026,-.108),(.01,.026,-.108),.006,'polymer')
    for s in [-1,1]: path(head,'Goggle strap',[(s*.077,.028,-.066),(s*.095,.024,.0),(s*.077,.027,.075)],.008,'rubber')
    if role=='flanker':
        profile(head,'Knitted watch cap',[(.040,.089,.094,0,.003),(.088,.091,.096,0,.009),(.142,.060,.065,0,.01),(.16,.01,.013,0,.01)],cloth,32,.015)
        profile(head,'Cap folded edge',[(.032,.094,.096,0,.004),(.065,.096,.098,0,.004)],'webbing',32,.01)
        path(head,'Trailing scarf',[(-.059,-.083,.064),(-.075,-.16,.10),(-.085,-.27,.115)],.020,cloth)
    else:
        profile(head,'Ballistic helmet shell',[(.025,.103,.107,0,.014),(.072,.109,.112,0,.014),(.119,.096,.102,0,.014),(.162,.066,.072,0,.014),(.184,.008,.012,0,.014)],'plate',40,.001)
        profile(head,'Helmet edge rubber seal',[(.020,.105,.109,0,.014),(.030,.105,.109,0,.014)],'rubber',40,0)
        box(head,'Helmet front mount',(0,.078,-.098),(.034,.045,.014),'anodized',.004)
        for s in [-1,1]:
            box(head,'Helmet accessory rail',(s*.106,.058,.01),(.009,.021,.100),'polymer',.003)
            for zz in [-.027,.042]: fastener(head,(s*.112,.056,zz),radius=.0028)
            path(head,'Chin strap',[(s*.089,.009,.02),(s*.074,-.080,-.014),(s*.025,-.119,-.051)],.004,'webbing')
        if role=='heavy':
            box(head,'Helmet top reinforcement',(0,.167,.013),(.066,.014,.130),'edge',.008)
            for s in [-1,1]: ell(head,'Armoured cheek guard',(s*.079,-.049,.016),(.046,.100,.093),'plate',24,12)
    for i,s in enumerate([-1,1]):
        side='Left' if i==0 else 'Right'
        thigh=empty(side+'Thigh',hips,(s*.105,-.025,0))
        profile(thigh,'Trouser thigh volume',[(.015,.101*bulk,.111,0,0),(-.060,.107*bulk,.107,0,0),(-.145,.098*bulk,.094,0,0),(-.225,.088*bulk,.087,0,.007),(-.310,.075*bulk,.078,0,.004),(-.395,.070*bulk,.074,0,0)],cloth,24,.042)
        pouch(thigh,'Cargo thigh pocket',(s*.091,-.181,.012),(.033,.147,.130))
        path(thigh,'Trousers outside seam',[(s*.101,-.05,.015),(s*.099,-.16,.019),(s*.088,-.28,.008),(s*.071,-.385,.005)],.0015,'stitch')
        shin=empty(side+'Shin',thigh,(0,-.40,0))
        profile(shin,'Trouser shin and boot cuff',[(.018,.071,.077,0,0),(-.067,.077,.078,0,.020),(-.145,.069,.071,0,.019),(-.232,.060,.066,0,.014),(-.315,.057,.063,0,.008)],cloth,24,.052)
        ell(shin,'Kneepad moulded shell',(0,.010,-.067),(.138,.128,.052),'polymer',24,14)
        box(shin,'Kneepad wear cap',(0,.012,-.093),(.084,.082,.018),'plate',.020)
        for yy in [-.040,.057]: path(shin,'Knee elastic strap',[(-.066,yy,-.04),(-.075,yy,.035),(0,yy,.078),(.075,yy,.035),(.066,yy,-.04)],.010,'webbing')
        ell(shin,'Rounded leather boot upper',(0,-.340,-.028),(.147,.197,.255),'leather',28,16)
        box(shin,'Rounded boot sole',(0,-.428,-.047),(.157,.036,.282),'rubber',.015)
        ell(shin,'Toe cap',(0,-.369,-.128),(.149,.091,.125),'polymer',28,12)
        for zz in np.linspace(-.14,.065,7): box(shin,'Sole tread lug',(0,-.449,float(zz)),(.149,.013,.012),'rubber',.003)
        for k in range(5):
            yy=-.266-k*.020; zz=-.118-k*.009
            path(shin,'Crossed boot lace',[(-.036,yy,zz),(0,yy-.010,zz-.008),(.036,yy,zz)],.0018,'stitch')
        upper=empty(side+'Arm',torso,(s*.232*bulk,.405,0))
        profile(upper,'Upper sleeve deltoid bicep',[(.04,.075*bulk,.081,0,0),(-.016,.087*bulk,.091,0,0),(-.09,.080*bulk,.085,0,0),(-.18,.067*bulk,.074,0,0),(-.265,.059,.065,0,0)],cloth,24,.04)
        box(upper,'Unit shoulder patch',(s*.079,-.065,-.006),(.008,.066,.071),'red',.009)
        lower=empty(side+'Forearm',upper,(0,-.275,0))
        profile(lower,'Forearm sleeve folds',[(.015,.059,.064,0,0),(-.045,.066,.069,0,.004),(-.12,.058,.061,0,0),(-.19,.046,.047,0,0),(-.233,.042,.043,0,0)],cloth,24,.055)
        box(lower,'Wrist strap',(0,-.224,0),(.089,.025,.084),'webbing',.008)
        hand=glove(lower,side+'Glove',(0,-.276,0),.91,True)
        if role=='heavy':
            ell(upper,'Shoulder armour',(s*.018,-.022,-.008),(.174,.150,.185),'plate',24,12)
            box(lower,'Forearm armour',(0,-.098,-.063),(.092,.15,.027),'plate',.016)
    gunpivot=empty('WeaponPivot',torso,(.075,.285,-.095)); gun=weapon(gunpivot,'rifle',False); gun.scale=(.80,.80,.80)
    return root

def atlas_material():
    global ATLAS
    if ATLAS:return ATLAS
    N=256; cols=4; rows=5; names=list(M); albedo=np.ones((N*rows,N*cols,4),np.float32); normal=albedo.copy(); orm=albedo.copy()
    normal[:,:,:3]=(.5,.5,1)
    for i,name in enumerate(names):
        yy,xx=(i//cols)*N,(i%cols)*N; sl=(slice(yy,yy+N),slice(xx,xx+N))
        for suffix,array in [('albedo',albedo),('normal',normal)]:
            data=np.empty(N*N*4,np.float32); bpy.data.images[name+'_'+suffix].pixels.foreach_get(data); array[sl]=data.reshape(N,N,4)
        bs=M[name].node_tree.nodes.get('Principled BSDF'); orm[sl+(1,)]=bs.inputs['Roughness'].default_value; orm[sl+(2,)]=bs.inputs['Metallic'].default_value
    material=bpy.data.materials.new('Equipment_PBR_Atlas'); material.use_nodes=True; nodes=material.node_tree.nodes; links=material.node_tree.links; bs=nodes.get('Principled BSDF')
    for name,array in [('albedo',albedo),('normal',normal),('orm',orm)]:
        im=bpy.data.images.new('EquipmentAtlas_'+name,width=N*cols,height=N*rows)
        if name!='albedo':im.colorspace_settings.name='Non-Color'
        im.pixels.foreach_set(array.ravel()); im.filepath_raw=str(TEX/('EquipmentAtlas_'+name+'.png')); im.file_format='PNG'; im.save(); im.pack()
        tx=nodes.new('ShaderNodeTexImage'); tx.image=im
        if name=='albedo':links.new(tx.outputs['Color'],bs.inputs['Base Color'])
        elif name=='normal':
            nm=nodes.new('ShaderNodeNormalMap'); nm.inputs['Strength'].default_value=.35; links.new(tx.outputs['Color'],nm.inputs['Color']); links.new(nm.outputs['Normal'],bs.inputs['Normal'])
        else:
            sep=nodes.new('ShaderNodeSeparateColor'); links.new(tx.outputs['Color'],sep.inputs['Color']); links.new(sep.outputs['Green'],bs.inputs['Roughness']); links.new(sep.outputs['Blue'],bs.inputs['Metallic'])
    ATLAS=material; return material

def consolidate(collection):
    # Join visible meshes by articulated parent; glTF keeps material surfaces.
    parents={o.parent for o in list(collection.objects) if o.type=='MESH'}
    for parent in parents:
        objs=[o for o in list(collection.objects) if o.type=='MESH' and o.parent==parent]
        if not objs: continue
        bpy.ops.object.select_all(action='DESELECT')
        for o in objs:o.select_set(True)
        bpy.context.view_layer.objects.active=objs[0]; bpy.ops.object.join()
        ob=objs[0]; ob.name=(parent.name if parent else 'Asset')+'_mesh'
        # Atlas all material classes into one draw surface per animated part.
        names=list(M); me=ob.data; uv=me.uv_layers.active
        for face in me.polygons:
            name=me.materials[face.material_index].name; idx=names.index(name)
            for li in face.loop_indices:
                u,v=uv.data[li].uv; u=(u%1)*.94+.03; v=(v%1)*.94+.03
                uv.data[li].uv=((idx%4+u)/4,(idx//4+v)/5)
            face.material_index=0
        me.materials.clear(); me.materials.append(atlas_material())

def new_asset(name,fn):
    global COLL
    COLL=bpy.data.collections.new(name); bpy.context.scene.collection.children.link(COLL)
    root=fn(); bpy.context.view_layer.update(); consolidate(COLL)
    bpy.ops.object.select_all(action='DESELECT')
    for o in COLL.objects:o.select_set(True)
    target=OUT/(name+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',use_selection=True,export_yup=True,export_apply=True,export_animations=False,export_materials='EXPORT',export_cameras=False,export_lights=False)
    tris=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in COLL.objects if o.type=='MESH')
    ASSETS.append({'asset':name,'triangles':tris,'bytes':target.stat().st_size,'root':root.name})
    return root

roots=[]
roots.append(new_asset('r7_view',lambda:weapon(None,'rifle',True)))
roots.append(new_asset('shotgun_view',lambda:weapon(None,'shotgun',True)))
for role in ['rifle','flanker','heavy']: roots.append(new_asset('raider_'+role,lambda r=role:humanoid(r)))
# Keep a composed, editable Blender file with all five assets arranged for inspection.
for i,o in enumerate(roots):
    o.location=cv(((-1.25+i*.75) if i<2 else (i-3)*1.0, .65 if i<2 else 0, -1.1 if i<2 else 0))
bpy.ops.object.select_all(action='DESELECT')
bpy.context.scene.world.color=(.16,.16,.16)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'source/人物与枪械_精修.blend'))
(OUT/'asset_manifest.json').write_text(json.dumps({'assets':ASSETS,'authoring':'Blender generated editable geometry, local procedural PBR images','units':'metres','axis':'Godot Y up / -Z forward'},ensure_ascii=False,indent=2),encoding='utf-8')
print('DETAIL_MODELS_READY',json.dumps(ASSETS),flush=True)

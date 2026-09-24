"""Six original procedural mechanical sculptures, Blender 5.2. Run with --background --python.
Editable component meshes remain in the .blend; GLBs merge by material. +Y is front.
"""
import bpy, math, json, os
from mathutils import Vector
from collections import defaultdict

ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT=os.path.join(ROOT,'assets','models')
PREVIEW=os.path.join(ROOT,'previews','models')
os.makedirs(OUT,exist_ok=True); os.makedirs(PREVIEW,exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
M={}
def mat(key,color,metal=.4,rough=.3,emission=0):
    m=bpy.data.materials.new(key); m.diffuse_color=(*color,1); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Metallic'].default_value=metal; p.inputs['Roughness'].default_value=rough
    if emission: p.inputs['Emission Color'].default_value=(*color,1); p.inputs['Emission Strength'].default_value=emission
    M[key]=m
mat('porcelain',(0.77,.84,.89),.45,.26)
mat('white',(0.93,.96,1),.32,.25)
mat('silver',(.35,.44,.50),.85,.22)
mat('gunmetal',(.055,.08,.105),.8,.29)
mat('navy',(.014,.037,.095),.65,.26)
mat('blue',(.025,.15,.43),.5,.26)
mat('red',(.57,.025,.042),.48,.27)
mat('gold',(.86,.54,.075),.7,.25)
mat('black',(.015,.021,.032),.4,.34)
mat('eye',(.16,1,.57),.4,.2,2.8)
mat('psycho',(1,.025,.13),.45,.22,2)
mat('cyan',(.05,.62,1),.3,.2,1.6)
mat('warning',(.95,.56,.09),.25,.4)
COL=None; PARTS=[]
def finish(o,name,material,bevel=0):
    o.name=name; o.data.materials.append(M[material])
    for c in list(o.users_collection): c.objects.unlink(o)
    COL.objects.link(o); PARTS.append(o)
    if bevel:
        mod=o.modifiers.new('Machined chamfer','BEVEL'); mod.width=bevel; mod.segments=3
        mod.affect='EDGES'
        norm=o.modifiers.new('Face weighted normals','WEIGHTED_NORMAL'); norm.keep_sharp=True; norm.weight=50
    return o
def cube(n,loc,dim,m='white',b=.06,rot=None):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc); o=bpy.context.object; o.dimensions=dim
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if rot: o.rotation_euler=rot
    return finish(o,n,m,b)
def ellipsoid(n,loc,scale,m='gunmetal',segments=24):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments,ring_count=12,location=loc)
    o=bpy.context.object; o.scale=scale; bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    for p in o.data.polygons:p.use_smooth=True
    return finish(o,n,m)
def rod(n,a,b,r,m='gunmetal',vertices=20,r2=None):
    a,b=Vector(a),Vector(b); v=b-a
    bpy.ops.mesh.primitive_cone_add(vertices=vertices,radius1=r,radius2=r if r2 is None else r2,depth=v.length,location=(a+b)/2)
    o=bpy.context.object; o.rotation_euler=v.to_track_quat('Z','Y').to_euler()
    for p in o.data.polygons:p.use_smooth=len(p.vertices)==4
    return finish(o,n,m,.025 if r>.1 else .008)
def plate(n,points,y,depth,m='white',bevel=.05):
    # x,z outline in front elevation; depth extends behind front face y.
    vs=[(x,y,z) for x,z in points]+[(x,y-depth,z) for x,z in points]; k=len(points)
    fs=[tuple(range(k-1,-1,-1)),tuple(range(k,2*k))]+[(i,(i+1)%k,(i+1)%k+k,i+k) for i in range(k)]
    mesh=bpy.data.meshes.new(n); mesh.from_pydata(vs,[],fs); mesh.update(); o=bpy.data.objects.new(n,mesh); COL.objects.link(o)
    return finish(o,n,m,bevel)
def mirrored(n,points,y,depth,m='white',bevel=.05):
    for s in [-1,1]:plate(n+str(s),[(s*x,z) for x,z in points],y,depth,m,bevel)
def armor(n,x,y,z,w,d,h,m='white',taper=.8):
    # Convex shaped sleeve, asymmetrical front bevel silhouette, not a cuboid.
    points=[(-w*.5,-h*.36),(-w*.36,-h*.5),(w*.36,-h*.5),(w*.5,-h*.30),(w*.5*taper,h*.34),(w*.3*taper,h*.5),(-w*.3*taper,h*.5),(-w*.5*taper,h*.34)]
    return plate(n,[(x+a,z+b) for a,b in points],y+d*.5,d,m,.075)
def seam(n,a,b,r=.022,m='gunmetal'):return rod(n,a,b,r,m,8)
def bolt(n,x,y,z,r=.065):rod(n,(x,y-.045,z),(x,y+.045,z),r,'silver',12)
def vent(n,x,y,z,w,h,rows=4):
    cube(n+' recess',(x,y,z),(w,.12,h),'black',.04)
    for j in range(rows):cube(n+' grille'+str(j),(x,y+.09,z-h*.37+j*h*.74/(rows-1)),(w*.88,.16,h*.075),'gold',.02)
def ring(n,loc,major,minor,m='gold',rotation=(math.pi/2,0,0)):
    bpy.ops.mesh.primitive_torus_add(major_segments=32,minor_segments=10,location=loc,major_radius=major,minor_radius=minor,rotation=rotation)
    o=bpy.context.object
    for p in o.data.polygons:p.use_smooth=True
    return finish(o,n,m)

SPECS=[('rx78','RX-78-2',18),('unicorn','RX-0 Unicorn · Destroy',21.7),('nu','RX-93 ν Gundam',22),('freedom','ZGMF-X20A Strike Freedom',18.88),('wing','XXXG-00W0 Wing Zero EW',16.7),('exia','GN-001 Exia',18.3)]

def build(key,H):
    global COL,PARTS
    COL=bpy.data.collections.new(key+' · editable components'); bpy.context.scene.collection.children.link(COL); PARTS=[]
    white='white' if key in ['unicorn','wing'] else 'porcelain'
    body='white' if key=='unicorn' else 'navy' if key=='nu' else 'blue'
    joint='gold' if key=='freedom' else 'gunmetal'
    slim=.87 if key=='exia' else .94 if key=='wing' else 1
    legx=1.32*slim
    for s in [-1,1]:
        x=s*legx
        # Feet: broad geometric toe, separate ankle cuff, heel and sole tread.
        plate('Foot / red wedge',[(x-.77,.2),(x+.77,.2),(x+.81,.69),(x+.55,1.13),(x-.5,1.13),(x-.79,.65)],2.0,3.05,'white' if key=='unicorn' else 'red',.095)
        cube('Rubber sole',(x,.45,.13),(1.65,3.22,.26),'gunmetal',.065)
        for k in range(4): cube('Toe rib',(x,1.45+k*.15,.85),(1.2,.06,.055),'gunmetal',.015)
        armor('Toe armored cap',x,1.15,.9,1.28,1.0,.5,white)
        rod('Ankle bearing',(x-.65,-.08,1.55),(x+.65,-.08,1.55),.40,joint)
        armor('Ankle guard',x,.13,1.81,1.54,1.48,1.2,white)
        armor('Calf shell',x,-.17,3.5,1.73,1.65,3.6,white,.82)
        armor('Shin raised central blade',x,.91,3.74,1.15,.44,3.22,white,.66)
        plate('Shin inset stripe',[(x-.12,2.53),(x+.12,2.53),(x+.19,4.90),(x-.19,4.90)],1.17,.07,'psycho' if key=='unicorn' else 'silver',.015)
        for z in [2.34,4.55]:
            seam('Shin armor seam',(x-.52,1.205,z),(x+.52,1.205,z+.08))
            for a in [-.55,.55]: bolt('Shin fastener',x+a,1.20,z+.2)
        rod('Knee transverse axle',(x-.87,0,5.64),(x+.87,0,5.64),.48,joint)
        armor('Knee diamond',x,.91,5.8,1.5,.77,1.35,white,.6)
        armor('Knee lower inset',x,1.32,5.6,.81,.12,.46,'blue' if key=='exia' else 'psycho' if key=='unicorn' else 'gunmetal')
        armor('Thigh upper shell',x,-.08,7.33,1.67*slim,1.65,2.67,white,.8)
        armor('Thigh face floating plate',x,.88,7.46,1.27*slim,.25,2.21,white,.74)
        for z in [6.72,7.76]:seam('Thigh engraved separation',(x-.52,.995,z),(x+.52,.995,z))
        if key=='unicorn':
            for a in [-.57,.57]:cube('Psycho thigh split',(x+a,.91,7.41),(.075,.12,1.73),'psycho',.018)
            for a in [-.70,.70]:cube('Psycho shin split',(x+a,.75,3.6),(.065,.18,2.55),'psycho',.018)
        rod('Hip piston',(x,-.45,8.1),(x,-.45,9.4),.32,joint)
    armor('Pelvis core',0,-.1,9.1,3.25,2.0,1.55,'gunmetal')
    armor('Pelvis belt',0,.08,9.87,3.73,2.15,.63,white)
    armor('Waist red center',0,1.2,9.59,.81,.40,1.03,'red' if key!='unicorn' else 'white')
    cube('Waist buckle',(0,1.46,9.94),(.53,.12,.38),'gold',.045)
    for s in [-1,1]:
        plate('Front skirt segmented',[(s*.51,9.58),(s*1.84,9.52),(s*2.07,7.99),(s*.66,8.2)],1.43,.55,white,.075)
        plate('Front skirt relief',[(s*.72,9.37),(s*1.57,9.32),(s*1.74,8.32),(s*.81,8.46)],1.76,.12,white,.035)
        cube('Skirt vent',(s*1.2,1.86,8.75),(.62,.065,.13),'psycho' if key=='unicorn' else 'gunmetal',.012)
        armor('Side skirt',s*2.07,-.14,8.83,.86,1.84,1.77,white)
        armor('Rear skirt',s*1.01,-1.1,8.83,1.65,.55,1.81,white)
    # Cockpit passage: x +/-1.2m and z H*.6 to H*.6+2.4m stays free; 18m baseline gap slightly generous.
    # Keep rear shell behind y=-1.10 (Godot z=+1.10), all chest parts outside width.
    cube('Thorax rear structural bulkhead',(0,-1.34,12.36),(4.35,.40,4.40),'gunmetal',.08)
    cube('Abdominal lower structural shelf',(0,-.16,10.41),(3.73,2.05,.65),body,.08)
    cube('Torso upper arch',(0,-.05,14.15),(4.54,2.61,1.17),body,.12)
    for s in [-1,1]:
        armor('Chest side buttress',s*(1.98 if key=='wing' else 1.94),.23,12.53,1.32,2.37,3.0,body,.90)
        plate('Breastplate swept clavicle',[(s*1.23,13.55),(s*2.86,14.02),(s*2.42,14.84),(s*.31,14.52)],1.55,.50,body,.09)
        armor('Chest outer white trim',s*2.52,.2,13.18,.58,1.80,2.0,white)
        vent('Thoracic heat exchanger',s*1.97,1.68,13.15,.83,1.05)
        bolt('Chest bolt',s*2.33,1.96,14.2,.09)
        cube('Chest warning bar',(s*1.87,1.64,14.4),(.55,.08,.09),'warning',.01)
        if key=='unicorn':
            cube('Psycho clavicle',(s*1.70,1.85,14.13),(1.23,.10,.12),'psycho',.02)
            cube('Psycho chest rail',(s*1.31,1.43,12.08),(.11,.10,1.67),'psycho',.02)
    for z in [10.05,10.45]:cube('Abdominal belt rib',(0,1.13,z),(2.90,.17,.10),'silver',.02)
    # Head crown = exactly 18 baseline. Helmet has angular temples and layered mask.
    rod('Neck collar',(0,0,14.62),(0,0,15.98),.64,joint,24)
    ring('Neck seal',(0,0,15.27),.65,.10,'silver',(0,0,0))
    armor('Helmet main crown',0,-.04,16.99,2.21,1.84,2.02,white,.73)
    armor('Helmet rear cap',0,-.80,16.87,1.94,.60,1.85,white)
    plate('Face shadow pentagon',[(-.8,17.22),(.8,17.22),(.68,16.20),(0,15.99),(-.68,16.20)],1.025,.30,'black',.035)
    for s in [-1,1]:
        plate('Temple cheek armor',[(s*.69,17.56),(s*1.12,17.37),(s*1.06,16.04),(s*.59,16.09),(s*.47,16.51)],1.17,.54,white,.045)
        plate('Angular luminous eye',[(s*.11,16.94),(s*.69,17.08),(s*.61,16.88),(s*.18,16.79)],1.255,.055,'eye',.01)
        plate('Mask cheek',[ (s*.10,16.71),(s*.54,16.74),(s*.62,16.2),(s*.15,16.07)],1.30,.18,white,.025)
        rod('Ear bearing',(s*1.04,-.1,16.75),(s*1.21,-.1,16.75),.31,'silver')
        for j in range(3):cube('Cheek exhaust',(s*.89,1.225,16.22+j*.18),(.23,.03,.055),'gunmetal',.006)
    plate('Face bridge',[(-.1,16.88),(.1,16.88),(.23,16.40),(0,16.24),(-.23,16.4)],1.49,.2,white,.025)
    armor('Red chin',0,1.3,16.01,.46,.39,.39,'red')
    for j in [-1,1]:seam('Mask mouth vent',(j*.07,1.532,16.34),(j*.24,1.532,16.49),.026)
    armor('Forehead crest',0,1.02,17.57,.50,.49,.66,'red' if key!='unicorn' else 'white')
    cube('Forehead sensor',(0,1.30,17.68),(.21,.08,.22),'eye',.015)
    # Gold V-fin, separate above-crown dimension.
    for s in [-1,1]:
        plate('V fin',[(s*.11,17.39),(s*.29,17.73),(s*1.92,18.66),(s*1.48,17.76),(s*.35,17.43)],1.28,.11,'white' if key=='rx78' else 'gold',.022)
        if key in ['freedom','nu','wing']:
            plate('Secondary V fin',[(s*.19,17.47),(s*.45,17.84),(s*1.63,18.12),(s*.91,17.56)],1.23,.09,'gold',.015)
    # Segmented shoulder-arm chain, separate wrist digits.
    shoulderx=3.40*slim
    for s in [-1,1]:
        x=s*shoulderx
        rod('Shoulder axle',(s*2.25,0,14.32),(s*3.75*slim,0,14.32),.51,joint)
        ellipsoid('Shoulder ball',(x,0,14.18),(.72,.73,.73),joint)
        if key=='exia':
            plate('Exia pointed shoulder',[(s*2.55,14.55),(s*3.17,15.72),(s*4.43,14.58),(s*3.62,13.95)],.90,1.64,white)
            plate('Exia blue shoulder vane',[(s*3.15,15.16),(s*4.37,14.65),(s*3.81,14.20)],1.02,.20,'blue')
        else:
            plate('Shoulder armored pauldron',[(s*2.54*slim,14.40),(s*2.79*slim,15.32),(s*4.33*slim,15.10),(s*4.69*slim,13.70),(s*3.22*slim,13.67)],.97,1.99,white if key!='nu' else 'navy',.09)
            plate('Shoulder upper armor layer',[(s*2.73*slim,15.12),(s*3.02*slim,15.55),(s*4.45*slim,15.20),(s*4.65*slim,14.58)],1.1,1.75,white,.06)
            for j in range(3):cube('Shoulder face heat slit',(s*(3.5+j*.23)*slim,1.13,14.53),(.085,.075,.39),'psycho' if key=='unicorn' else 'gunmetal',.01)
        armor('Upper arm',x,-.04,12.84,1.14*slim,1.31,1.70,white)
        rod('Elbow axle',(x-.70,0,11.86),(x+.70,0,11.86),.39,joint)
        armor('Elbow cap',x,.76,11.85,.83,.36,.85,white)
        armor('Forearm gauntlet',x,.01,10.74,1.40*slim,1.57,1.97,white,.72)
        armor('Forearm face inset',x,.90,10.87,.91*slim,.20,1.39,'blue' if key=='exia' else white)
        for zz in [10.35,10.75]:seam('Forearm panel engraving',(x-.41,1.03,zz),(x+.41,1.03,zz))
        if key=='unicorn':cube('Forearm psycho slit',(x,1.03,11.07),(.10,.08,1.34),'psycho',.01)
        rod('Wrist swivel',(x,0,9.70),(x,0,9.34),.34,joint)
        armor('Hand dorsal armor',x,.13,9.12,1.1,.92,.77,'gunmetal')
        for j in range(4):
            fx=x+(j-1.5)*.22
            for k in range(2):
                cube('Finger articulated phalange',(fx,.37+k*.12,8.76-k*.20),(.185,.48,.23),'gunmetal',.055)
            ellipsoid('Knuckle',(fx,.65,9.0),(.115,.105,.12),'silver',12)
        rod('Thumb knuckle',(x-s*.51,.15,9.16),(x-s*.59,.62,8.94),.17,'gunmetal',12)
        # Rear vent backpack and thruster bells.
        armor('Backpack side module',s*1.16,-1.74,13.10,1.30,1.08,2.86,body)
        rod('Thruster engine',(s*1.13,-1.82,12.46),(s*1.13,-1.82,11.32),.40,'gunmetal',24,r2=.61)
        rod('Thruster throat',(s*1.13,-1.82,11.28),(s*1.13,-1.82,11.35),.36,'cyan',24)
        for z in [12.6,12.85,13.10]:cube('Backpack grille',(s*1.16,-2.32,z),(.89,.075,.095),'silver',.015)
    if key=='rx78':
        # Long red kite shield left, white rim and iconic gold cross.
        plate('RX shield white rim',[(-4.24,13.73),(-6.20,13.28),(-6.39,9.03),(-5.27,7.79),(-4.17,8.68)],.71,.49,'white',.08)
        plate('RX shield red field',[(-4.45,13.38),(-5.97,13.04),(-6.15,9.20),(-5.26,8.17),(-4.41,8.85)],.99,.25,'red',.07)
        cube('RX shield cross vertical',(-5.26,1.18,10.26),(.19,.10,2.24),'gold',.02)
        cube('RX shield cross horizontal',(-5.26,1.18,10.34),(1.32,.10,.18),'gold',.02)
        cube('RX shield sight',(-5.21,1.15,12.58),(.80,.1,.40),'black',.04)
        for x in [-.92,.92]: rod('Beam saber grip',(x,-1.51,14.25),(x,-1.51,16.50),.17,'white',16)
    if key=='unicorn':
        # Opened armor petals / luminous inner frame, clear shield silhouette.
        for s in [-1,1]:
            plate('Unicorn expanded calf petal',[(s*1.87,4.94),(s*2.72,4.31),(s*2.26,2.21),(s*1.92,2.79)],.34,.53,'white')
            rod('Psycho calf underframe',(s*2.02,.19,2.59),(s*2.35,.19,4.13),.11,'psycho',8)
            cube('Psycho shoulder trace',(s*3.44,1.17,15.24),(1.09,.09,.10),'psycho',.01)
            cube('Psycho biceps seam',(s*3.40,.65,12.85),(.12,.10,1.39),'psycho',.01)
            plate('Unicorn chest flare',[(s*1.34,14.52),(s*1.67,15.32),(s*2.13,15.55),(s*2.44,14.54)],.68,.44,'white')
        plate('Unicorn shield spine',[(-4.43,14.07),(-5.27,14.52),(-6.1,13.79),(-6.22,9.41),(-5.14,7.48),(-4.34,9.19)],.55,.48,'white')
        plate('Unicorn shield psycho center',[(-4.83,13.44),(-5.45,13.65),(-5.73,9.65),(-5.13,8.47),(-4.76,9.46)],.83,.13,'psycho')
        for z in [10.1,11.3,12.5]:cube('Unicorn shield split crossbar',(-5.24,1.01,z),(1.47,.18,.46),'white',.06)
    if key=='nu':
        # Asymmetric six full-length detachable fin funnels, staggered sawtooth silhouette.
        for j in range(6):
            x=2.0+j*.72; zz=14.1+j*.40
            plate('Nu fin funnel white shell '+str(j),[(x-.29,zz-3.25),(x+.29,zz-2.93),(x+.29,zz+3.48),(x-.29,zz+3.79)],-2.17,.53,'porcelain')
            cube('Nu fin funnel dark midsection '+str(j),(x,-2.05,zz),(.54,.58,2.2),'navy',.04)
            cube('Nu funnel golden capacitor',(x,-1.75,zz-.44),(.42,.1,.27),'gold',.018)
            seam('Nu funnel length seam',(x,-1.85,zz+1.2),(x,-1.85,zz+3.19))
        plate('Nu shield',[(-4.32,13.29),(-5.55,13.4),(-5.91,9.5),(-5.20,7.61),(-4.28,9.04)],.68,.50,'porcelain')
        plate('Nu shield navy split',[(-4.96,13.10),(-5.41,13.11),(-5.68,9.60),(-5.18,8.11),(-4.90,9.51)],.98,.20,'navy')
        cube('Nu shield red insignia',(-4.66,1.04,11.30),(.20,.06,.66),'red',.02)
    if key=='freedom':
        # Ten long blue/black wing panels radiate from the backpack.
        for s in [-1,1]:
            rod('Freedom wing hinge',(s*1.2,-2.08,13.8),(s*3.05,-2.08,14.7),.35,'gunmetal')
            for j in range(5):
                start=(s*(1.8+j*.30),13.9-j*.26)
                tip=(s*(5.95+j*.49),19.8-j*1.52)
                plate('Freedom wing black blade',[(start[0],start[1]),(tip[0]-s*.12,tip[1]),(tip[0]+s*.40,tip[1]-.48),(start[0]+s*.97,start[1]-2.3)],-2.20-j*.14,.34,'navy')
                plate('Freedom cobalt wing edge',[(start[0]+s*.19,start[1]),(tip[0],tip[1]-.08),(tip[0]+s*.19,tip[1]-.56),(start[0]+s*.51,start[1]-1.54)],-1.99-j*.14,.10,'blue',.027)
            armor('Freedom hip railgun',s*2.80,-.1,8.88,.70,1.09,3.12,'navy')
            cube('Freedom railgun edge',(s*2.80,.49,8.68),(.24,.20,2.14),'silver',.04)
    if key=='wing':
        # Articulated wings with 32 separate long curved feather contours, not rectangles.
        for s in [-1,1]:
            rod('Wing shoulder spar',(s*1.05,-2.09,14.24),(s*5.31,-2.23,16.10),.34,'silver')
            plate('Wing inner mantle',[(s*1.37,14.24),(s*2.68,17.62),(s*4.43,18.87),(s*5.72,18.32),(s*6.88,16.23),(s*5.12,13.68),(s*2.89,12.73)],-2.29,.59,'white',.12)
            for j in range(10):
                x=2.43+j*.46; top=17.92-math.pow(j*.23,1.35); length=5.2+j*.16
                pts=[(s*(x-.14),top),(s*(x+.39),top-.06),(s*(x+1.54),top-length*.67),(s*(x+1.29),top-length),(s*(x+.47),top-length+.63),(s*(x-.11),top-1.57)]
                plate('Wing primary feather '+str(j),pts,-1.93+j*.031,.20,'white' if j%3 else 'porcelain',.075)
                seam('Wing feather midrib',(s*(x+.2),-1.68+j*.031,top-.5),(s*(x+1.15),-1.68+j*.031,top-length+.7),.026,'silver')
            for j in range(6):
                x=2.01+j*.55; top=17.43-j*.29
                plate('Wing layered cover feather',[(s*x,top),(s*(x+.47),top+.18),(s*(x+1.01),top-2.2),(s*(x+.62),top-2.72),(s*(x+.17),top-1.62)],-1.57,.23,'white',.08)
        ring('Wing chest jewel setting',(0,1.48,14.10),.52,.14,'gold')
        ellipsoid('Wing chest green orb',(0,1.53,14.10),(.43,.23,.43),'eye')
    if key=='exia':
        ring('GN Drive chest collar',(0,1.46,14.08),.65,.15,'silver')
        ellipsoid('GN Drive green core',(0,1.54,14.08),(.52,.26,.52),'eye')
        for s in [-1,1]:
            ring('GN condenser elbow',(s*3.14,.81,11.82),.36,.1,'white')
            ellipsoid('Elbow GN lens',(s*3.14,.85,11.82),(.28,.16,.28),'eye')
            # Broad translucent-looking flat shoulder cables using blue strips.
            plate('Exia flexible shoulder ribbon',[(s*2.08,14.89),(s*2.45,15.05),(s*3.07,12.98),(s*3.11,11.08),(s*2.86,11.03),(s*2.76,12.86)],-.53,.12,'cyan',.025)
            plate('Exia rear blue waist fin',[(s*1.52,9.65),(s*2.82,10.05),(s*2.32,7.33),(s*1.76,8.07)],-.51,.60,'blue')
        # GN Sword right forearm, silver single-edge blade tapering well below fist.
        armor('GN sword shield mount',3.63,.55,10.77,1.02,.61,2.08,'blue')
        plate('GN sword dark spine',[(3.87,11.39),(4.29,11.32),(4.71,5.45),(3.69,6.51)],1.10,.28,'gunmetal')
        plate('GN sword polished broad blade',[(4.16,10.80),(4.71,10.39),(5.30,4.22),(4.01,5.67)],1.19,.16,'silver')
        plate('GN sword brilliant cutting edge',[(4.64,10.37),(4.82,10.15),(5.30,4.22),(4.96,5.16)],1.31,.065,'white',.022)
    # Initial uniform scale; total-height references are calibrated above the cockpit below.
    factor=H/18
    for o in PARTS:
        o.location*=factor; o.scale*=factor
    return COL,list(PARTS)

def evaluated_bounds(objects):
    deps=bpy.context.evaluated_depsgraph_get(); coords=[]
    for o in objects:
        e=o.evaluated_get(deps); coords.extend([e.matrix_world@Vector(v) for v in e.bound_box])
    return [[min(v[k] for v in coords),max(v[k] for v in coords)] for k in range(3)]

def is_wing_equipment(key,o):
    return key=='freedom' and o.name.startswith(('Freedom wing hinge','Freedom wing black blade','Freedom cobalt wing edge'))

def calibrate_height(key,H,parts):
    """Preserve the portal and feet; compress only upper body above its clear opening."""
    if key not in ('unicorn','freedom'):return
    body=[o for o in parts if not is_wing_equipment(key,o)]
    top=evaluated_bounds(body)[2][1]; pivot=H*.6+2.4
    ratio=(H-pivot)/(top-pivot)
    if abs(top-H)<.00001:return
    bpy.ops.object.select_all(action='DESELECT')
    for o in body:
        bpy.context.view_layer.objects.active=o;o.select_set(True)
        for mod in list(o.modifiers):bpy.ops.object.modifier_apply(modifier=mod.name)
        matrix=o.matrix_world.copy();inverse=matrix.inverted()
        for v in o.data.vertices:
            p=matrix@v.co
            if p.z>pivot:p.z=pivot+(p.z-pivot)*ratio
            v.co=inverse@p
        o.data.update();o.select_set(False)
    bpy.context.view_layer.update()

def height_metadata(key,H,parts):
    crown=evaluated_bounds([o for o in parts if o.name.startswith('Helmet main crown')])[2][1]
    body_top=evaluated_bounds([o for o in parts if not is_wing_equipment(key,o)])[2][1]
    # Nu funnels and Wing feathers are equipment, so report body separately for all variants.
    body=[o for o in parts if not is_wing_equipment(key,o) and not o.name.startswith(('Nu fin funnel','Nu funnel','Wing inner mantle','Wing primary feather','Wing layered cover feather','Wing feather midrib','Wing shoulder spar'))]
    body_top=evaluated_bounds(body)[2][1]
    basis='body_total_including_antenna' if key in ('unicorn','freedom') else 'head_crown_reference'
    return {'reference_height_m':H,'head_crown_height_m':round(crown,6),'measured_crown_m':round(crown,6),'body_height_including_antenna_m':round(body_top,6),'equipment_inclusive_height_m':round(evaluated_bounds(parts)[2][1],6),'height_basis':basis,'height_status':'official reference; Wing/Exia modeled using head-crown interpretation' if key in ('wing','exia') else 'specified official reference','reference_url':{'freedom':'https://manual.bandai-hobby.net/pdf/646.pdf','wing':'https://manual.bandai-hobby.net/pdf/642.pdf'}.get(key),'calibration_preserves':'feet and cockpit portal; only body vertices above H*0.6+2.4m adjusted'}

manifest={'format_version':1,'source':'source/机体模型.blend','generator':'source/build_models.py','coordinate_system':{'source_front':'+Y','godot_front':'-Z','up':'Y in GLB / Z in Blender','units':'meters','feet_bottom':0},'models':{}}
originals=[]
for index,(key,label,H) in enumerate(SPECS):
    col,parts=build(key,H); calibrate_height(key,H,parts); bounds=evaluated_bounds(parts)
    helmet=[o for o in parts if o.name.startswith('Helmet main crown')][0]
    crown=evaluated_bounds([helmet])[2][1]
    # Exports get temporary evaluated copies. Original semantic components stay editable.
    bpy.ops.object.select_all(action='DESELECT'); copies=[]; groups=defaultdict(list)
    for o in parts:
        dup=o.copy(); dup.data=o.data.copy(); bpy.context.scene.collection.objects.link(dup)
        bpy.context.view_layer.objects.active=dup; dup.select_set(True)
        for mod in list(dup.modifiers):bpy.ops.object.modifier_apply(modifier=mod.name)
        bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
        dup.select_set(False); copies.append(dup); groups[dup.data.materials[0].name].append(dup)
    merged=[]
    for mn,obs in groups.items():
        bpy.ops.object.select_all(action='DESELECT')
        for o in obs:o.select_set(True)
        bpy.context.view_layer.objects.active=obs[0]; bpy.ops.object.join(); o=bpy.context.object; o.name=key+'__'+mn
        # Join uses active origin; set every export mesh origin to world for clean model root.
        bpy.context.scene.cursor.location=(0,0,0); bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
        bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
        merged.append(o)
    tris=0
    for o in merged:o.data.calc_loop_triangles(); tris+=len(o.data.loop_triangles)
    bpy.ops.object.select_all(action='DESELECT')
    for o in merged:o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,key+'.glb'),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_materials='EXPORT',export_cameras=False,export_lights=False)
    manifest['models'][key]={'name':label,'file':key+'.glb','head_crown_height_m':H,'measured_crown_m':round(crown,4),'height_status':'specified reference; see height_basis','overall_height_m':round(bounds[2][1],4),'width_m':round(bounds[0][1]-bounds[0][0],4),'depth_m':round(bounds[1][1]-bounds[1][0],4),'bounds_blender_xyz_m':bounds,'bounds_godot_xyz_m':[bounds[0],bounds[2],[-bounds[1][1],-bounds[1][0]]],'triangles':tris,'draw_surfaces':len(merged),'editable_components':len(parts),'cockpit_floor':H*.6,'portal_z':-H*.11,'portal_clear_width':2.4,'portal_clear_height':2.4,'crown_excludes':'V-fin, antennas, wing tips, funnel backpack','collisions':'none; gameplay proxies are separate'}
    manifest['models'][key].update(height_metadata(key,H,parts))
    for o in merged:bpy.data.objects.remove(o,do_unlink=True)
    # In editable source each robot is spread on X; export geometry above was at origin.
    for o in parts:o.location.x+=index*24
    originals.append((key,parts))
    print('MODEL_DONE',key,tris,len(groups),flush=True)

with open(os.path.join(OUT,'model_manifest.json'),'w',encoding='utf8') as f:json.dump(manifest,f,ensure_ascii=False,indent=2)

# Studio camera and soft light for inspectable visual proof. Ground is preview-only.
scene=bpy.context.scene
scene.render.engine='CYCLES'; scene.cycles.samples=24
scene.cycles.use_denoising=True
scene.world.color=(.16,.16,.16)
scene.render.resolution_x=1200; scene.render.resolution_y=1500; scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'
def track(o,p):o.rotation_euler=(Vector(p)-o.location).to_track_quat('-Z','Y').to_euler()
stage=bpy.data.collections.new('Preview studio · excluded from GLB');scene.collection.children.link(stage)
def light(name,loc,power,size):
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size
    o=bpy.data.objects.new(name,data);stage.objects.link(o);o.location=loc;return o
keylight=light('Large warm key',(12,16,27),6200,12)
fill=light('Soft blue fill',(-11,7,17),4100,10)
rim=light('Back rim',(0,-10,23),7500,9)
camdata=bpy.data.cameras.new('Inspection camera');cam=bpy.data.objects.new('Inspection camera',camdata);stage.objects.link(cam);scene.camera=cam;camdata.type='ORTHO';camdata.ortho_scale=27
for o in [keylight,fill,rim]:track(o,(0,0,10))
cam.location=(26,47,24);track(cam,(0,0,10.7))
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT,'source','机体模型.blend'))
# Render all six individually, using collection visibility and repositioning only camera/lights.
for idx,(key,parts) in enumerate(originals):
    for j,(_,allparts) in enumerate(originals):
        for o in allparts:o.hide_render=j!=idx
    offset=idx*24
    cam.location=(offset+26,47,24);track(cam,(offset,0,10.7))
    camdata.ortho_scale=29 if key in ['wing','freedom','nu','unicorn'] else 25
    for o,pos in [(keylight,(12,16,27)),(fill,(-11,7,17)),(rim,(0,-10,23))]:o.location=(pos[0]+offset,pos[1],pos[2]);track(o,(offset,0,10))
    scene.render.filepath=os.path.join(PREVIEW,key+'.png');bpy.ops.render.render(write_still=True)
for _,parts in originals:
    for o in parts:o.hide_render=False
print('ALL_MODELS_COMPLETE',flush=True)

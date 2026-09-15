"""Ground wear, scrub vegetation and industrial site dressing."""
from common import *

R=random.Random(927)

def _ribbon(name,points,width,mat,z=.012):
    vs=[]
    for i,p in enumerate(points):
        prev=Vector(points[max(0,i-1)]);nxt=Vector(points[min(len(points)-1,i+1)])
        d=nxt-prev;norm=Vector((-d.y,d.x));norm.normalize()
        w=width*R.uniform(.5,1.6)
        vs.extend([(p[0]+norm.x*w,p[1]+norm.y*w,z),(p[0]-norm.x*w,p[1]-norm.y*w,z)])
    return mesh(name,vs,[(2*i,2*i+1,2*i+3,2*i+2) for i in range(len(points)-1)],mat)

def crack(x,y,length,angle):
    ps=[(x,y)];a=angle
    for i in range(int(length/.35)):
        a+=R.uniform(-.55,.55);x+=cos(a)*.35;y+=sin(a)*.35;ps.append((x,y))
    if len(ps)<2:return
    _ribbon('Asphalt fractured seam',ps,R.uniform(.008,.027),'concrete_dark')
    for i in range(3,len(ps)-1,7):
        xx,yy=ps[i];aa=a+R.choice([-1,1])*R.uniform(.7,1.4)
        branch=[(xx,yy)]
        for j in range(R.randint(3,7)):
            xx+=cos(aa)*.26;yy+=sin(aa)*.26;aa+=R.uniform(-.7,.7);branch.append((xx,yy))
        _ribbon('Hairline fracture',branch,.006,'concrete_dark',.013)

def bush(x,y,z=0,size=1,dry=False):
    verts=[];faces=[]
    for stem in range(7):
        ang=stem*2.4;end=(x+cos(ang)*size*.36,y+sin(ang)*size*.36,z+size*R.uniform(.5,1.0))
        beam('Wild shrub woody stem',(x,y,z),end,.012*size,'wood',5)
    for k in range(int(125*max(.45,size))):
        angle=R.random()*2*pi;rad=size*R.random()**.5*.62
        px=x+cos(angle)*rad;py=y+sin(angle)*rad;pz=z+size*(.17+.85*(1-rad/size))+R.uniform(-.18,.18)*size
        a=R.random()*2*pi;ll=R.uniform(.07,.19)*size;ww=ll*.4;lift=R.uniform(-.45,.55)*ll
        u=Vector((cos(a)*ll,sin(a)*ll,lift));v=Vector((-sin(a)*ww,cos(a)*ww,ww*.25));p=Vector((px,py,pz));mid=p+Vector((0,0,ww*.5));off=len(verts)
        verts.extend([tuple(p-u),tuple(p-v),tuple(p+u),tuple(p+v),tuple(mid)])
        faces.extend([(off,off+1,off+4),(off+1,off+2,off+4),(off+2,off+3,off+4),(off+3,off,off+4)])
    return mesh('Scrub | individual curled leaves',verts,faces,'foliage_dry' if dry else 'foliage')

def grasses(centers):
    vs=[];fs=[]
    for x,y,size in centers:
        for blade in range(34):
            ang=R.random()*2*pi;r=R.random()*.25*size;h=R.uniform(.22,.7)*size
            p=Vector((x+cos(ang)*r,y+sin(ang)*r,.016));w=Vector((cos(ang+.8),sin(ang+.8),0))*.014*size
            bend=Vector((cos(ang)*h*.4,sin(ang)*h*.4,h));off=len(vs)
            vs.extend([tuple(p-w),tuple(p+w),tuple(p+w*.5+bend*.55),tuple(p-w*.5+bend*.55),tuple(p+bend)])
            fs.extend([(off,off+1,off+2,off+3),(off+3,off+2,off+4)])
    mesh('Dry grass in paving cracks',vs,fs,'foliage_dry')

def rock(x,y,z,scale):
    ob=ico('Weathered ornamental boulder',(x,y,z),scale,'concrete_dark',3)
    rr=random.Random(round(x*167+y*331))
    for v in ob.data.vertices:
        v.co*=rr.uniform(.85,1.14)
    _uv_local=ob.data.uv_layers.active
    return ob

def tree(x,y,height):
    beam('Dead tree trunk',(x,y,0),(x+.12,y+.1,height*.66),height*.032,'wood',9)
    for k in range(8):
        ang=k*2.4;rr=height*R.uniform(.12,.28);zz=height*R.uniform(.62,.92)
        beam('Angular branches',(x+.08,y,height*.44),(x+cos(ang)*rr,y+sin(ang)*rr,zz),height*.012,'wood',6)
        bush(x+cos(ang)*rr,y+sin(ang)*rr,zz-height*.11,height*.24,k%4==0)

def build():
    collection('01_Ground | cracked concrete and road paint')
    box('Site concrete foundation',(0,3,-.18),(50,56,.35),'concrete',.04)
    box('Horizon ground',(0,0,-.42),(2000,2000,.12),'soil',0)
    # Separate large repair patches, not a uniform checkerboard.
    for x,y,sx,sy in [(-17,7,7,28),(19,1,6,36),(-5,-12,8,5),(3,17,5,3),(-1,-22,14,2)]:
        box('Old road resurfacing',(x,y,-.006),(sx,sy,.009),'asphalt',0)
    for k in range(105):
        crack(R.uniform(-21,22),R.uniform(-22,24),R.uniform(1.5,8),R.random()*2*pi)
    for x in [-20,-14,-8,-2,4,10,16,22]:
        _ribbon('Concrete expansion gap',[(x+R.uniform(-.04,.04),y) for y in range(-23,30,2)],.006,'concrete_dark',.014)
    for y in [-19,-13,-7,-1,5,11,17,23]:
        _ribbon('Transverse concrete gap',[(x,y+R.uniform(-.06,.06)) for x in range(-24,25,2)],.006,'concrete_dark',.014)
    paint=[]
    for y in [1,5.3,9.6,13.9]:
        for k in range(24):
            if R.random()<.19:continue
            paint.append(((-6.1+k*.19,y,.024),(.16,R.uniform(.08,.115),.008),0))
    for y in [8.3,17.2]:
        for k in range(70):
            if R.random()<.15:continue
            paint.append(((4.4+k*.21,y,.024),(.17,.095,.008),0))
    for x in [4.6,8.4,12.3,16.3,20.3]:
        for k in range(26):
            if R.random()<.2:paint.append(((x,8.5+k*.32,.024),(.1,.25,.008),0))
    batched_boxes('Abraded parking-bay paint',paint,'cream')
    for y,n in [(3.2,'01'),(7.5,'02'),(11.8,'03')]:text_obj('Charging bay number '+n,n,(-2.4,y,.028),.63,'cream',rot=(0,0,pi/2))
    # Central worn directional arrow and broken lane stripe.
    mesh('Ground directional arrow',[(-.16,-8,.028),(.16,-8,.028),(.16,-5.8,.028),(.72,-5.8,.028),(0,-4.9,.028),(-.72,-5.8,.028),(-.16,-5.8,.028)],[(0,1,2,3,4,5,6)],'cream')
    for y in range(-21,19,5):box('Faded center marker',(.4,y,.02),(.11,1.9,.008),'cream',0)
    for x in [-9.5,10.5]:
        for j in range(4):
            box('Storm drain surround',(x,-11+j*9,.008),(1.05,.6,.012),'rust',0)
            for i in range(9):box('Drainage slots',(x-.43+i*.11,-11+j*9,.02),(.065,.49,.014),'black',.002)
    for i in range(30):
        x=-7.5+i*.54
        ob=box('Entrance speed bump',(x,-19,.075),(.51,.36,.13),'yellow' if i%4<2 else 'rubber',.055)
        for j in [-.15,0,.15]:box('Bump grip ridge',(x+j,-19,.139),(.02,.24,.012),'rubber',0)
    # Low garden retaining walls, weeds fill the disused service strip.
    for x in [-12.2,21.1]:
        box('Retaining curb',(x,8,.34),(.25,31,.68),'concrete',.025)
        box('Long neglected planter',(x+(-1 if x<0 else 1),8,.045),(1.8,31,.09),'soil',.015)
    for k in range(65):
        x=R.choice([-1,1])*R.uniform(12.5,21);y=R.uniform(-9,23)
        if x>0 and -7<y<6:continue
        ico('Broken concrete aggregate',(x,y,.10),(R.uniform(.07,.3),R.uniform(.05,.22),R.uniform(.05,.18)),R.choice(['concrete','concrete_dark','rust']),1)
    # Slick patches have irregular real outlines; no opaque picture planes.
    wet=bpy.data.materials.new('Thin oil and rain stains');wet.use_nodes=True;wet.diffuse_color=(.075,.083,.073,1)
    bs=wet.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(.075,.083,.073,1);bs.inputs['Metallic'].default_value=.5;bs.inputs['Roughness'].default_value=.24
    for x,y,r in [(-1.8,-15,.8),(3.2,8,1.15),(11,6,.7),(-7,-7,.55)]:
        vs=[(x,y,.023)]
        for j in range(25):
            a=j*2*pi/25;rr=r*R.uniform(.6,1.15);vs.append((x+cos(a)*rr,y+sin(a)*rr*.53,.023))
        mesh('Oil-stained shallow puddle',vs,[(0,j+1,(j+1)%25+1) for j in range(25)],wet)

    collection('05_Overgrowth | individual leaves and weeds')
    for y in [-4,0,4,8,12,16,20]:
        bush(-13,y,0,R.uniform(1.2,2.2));bush(-14.7,y+.4,0,R.uniform(1,1.9),y%3==0)
    for x,y in [(17,-5),(20,2),(22,5),(21,18),(20,22),(-18,-14),(-19,18),(-16,20)]:bush(x,y,0,R.uniform(1.1,2))
    grasses([(R.choice([-12,-10.8,20.8])+R.uniform(-.4,.4),R.uniform(-12,24),R.uniform(.7,1.6)) for _ in range(110)]+[(R.uniform(-14,18),R.uniform(-19,20),R.uniform(.28,.7)) for _ in range(34)])
    rock(15.8,-4.1,1.05,(1.35,1.2,1.6));rock(-12.9,7,.95,(1.3,.85,1.4));rock(-13.4,11,.7,(1.6,.8,.8))
    for x,y,h in [(-23,18,8),(-20,28,9),(-13,32,10),(2,34,8),(19,32,9),(26,24,11),(27,8,9),(24,-4,8)]:tree(x,y,h)
    # Terrace pots: architecture supplies exact pots; this sparse palm is a photo cue.
    beam('Terrace palm trunk',(8.5,-3.35,3.5),(8.53,-3.35,5.48),.11,'wood',12)
    pv=[];pf=[]
    for j in range(11):
        a=j*2*pi/11
        for k in range(9):
            t=k/9;r=t*1.5;z=5.57+.55*sin(t*pi)-.36*t
            p=Vector((8.53+cos(a)*r,-3.35+sin(a)*r,z));w=.22*sin(t*pi)+.03;side=Vector((-sin(a)*w,cos(a)*w,-.13))
            off=len(pv);pv.extend([tuple(p),tuple(p+side),tuple(p+Vector((cos(a)*.22,sin(a)*.22,.03))),tuple(p-side)])
            pf.extend([(off,off+1,off+2),(off,off+2,off+3)])
    mesh('Terrace palm ragged fronds',pv,pf,'foliage_dry')
    bush(7.2,-3.28,3.39,.55);bush(10.3,-3.32,3.41,.42)

    collection('06_Debris | salvage and forgotten objects')
    for x,y in [(18.5,-1),(20.5,5),(-16,-6),(-15,17)]:
        for k in range(3):
            cyl('Rusted steel drum',(x+k*.55,y+R.uniform(-.3,.3),.46),.28,.9,'rust',24)
            for z in [.13,.77]:torus('Drum stiffening ring',(x+k*.55,y,z),.281,.014,'iron')
    for x,y in [(-14,-7),(19,4),(19.5,5),(18,-1)]:
        for row in range(2):
            for j in range(5):box('Splintered pallet planks',(x+j*.16,y,.12+row*.14),(.12,1.05,.07),'wood',.006)
        for yy in [-.38,.38]:box('Pallet support',(x+.3,y+yy,.12),(.9,.08,.14),'wood',.005)
    for j in range(6):
        torus('Discarded truck tire',(19+R.uniform(-.5,.5),-2+R.uniform(-.5,.5),.18+j*.13),.34,.10,'rubber',rot=(R.uniform(-.2,.2),0,0))
    for k in range(35):
        x=R.choice([-1,1])*R.uniform(11.5,20);y=R.uniform(-9,21)
        if x>0 and -7<y<5:continue
        if k%3==0:
            cyl('Empty discarded bottle',(x,y,.085),.045,.22,'glass',10,rot=(0,pi/2,R.random()*pi))
        else:
            ob=box('Windblown packaging',(x,y,.034),(.19,.13,.009),'cream' if k%2 else 'blue',.005,rot=(0,0,R.random()*6))
    for x,y in [(-15,-5),(19,1)]:
        for j in range(7):
            ob=box('Scrapped corrugated sheet',(x,y+j*.09,.22+j*.03),(1.3,.45,.023),'rust',0,rot=(0,.18,j*.18))
    # Tumbled concrete rings match the utility yard behind the reference charger.
    for x,y in [(-14,2),(-15,14)]:
        torus('Abandoned concrete service ring',(x,y,.4),.72,.17,'concrete')

    collection('07_Utilities | overhead lines and fence')
    for x,y in [(-19,3),(-19,23),(22,19)]:
        cyl('Concrete utility pole',(x,y,5),.13,10,'concrete',12,radius_top=.08)
        beam('Utility crossarm',(x-1,y,8.9),(x+1,y,8.9),.06,'iron',4)
        for dx in [-.7,0,.7]:
            cyl('Ceramic insulator',(x+dx,y,9.08),.075,.22,'cream',12)
    for dx in [-.7,0,.7]:
        curve('Low service wire',[(-19+dx,3,9.2),(-19+dx,13,8.1),(-19+dx,23,9.2)],.014,'black')
        curve('Cross-yard service wire',[(-19+dx,23,9.2),(1,21,7.8),(22+dx,19,9.2)],.015,'black')
    # Distant lattice pylon and six sagging power lines.
    cx,cy=26,43
    levels=[(0,2.4),(5,1.8),(11,1.2),(17,.7),(23,.25)]
    for (za,wa),(zb,wb) in zip(levels,levels[1:]):
        for sx in [-1,1]:
            for sy in [-1,1]:
                beam('Pylon main angle',(cx+sx*wa,cy+sy*wa,za),(cx+sx*wb,cy+sy*wb,zb),.06,'steel',4)
        for side in [-1,1]:
            beam('Pylon diagonal bracing',(cx-wa,cy+side*wa,za),(cx+wb,cy+side*wb,zb),.035,'steel',4)
            beam('Pylon diagonal bracing',(cx+wa,cy+side*wa,za),(cx-wb,cy+side*wb,zb),.035,'steel',4)
            beam('Pylon cross brace',(cx+side*wa,cy-wa,za),(cx+side*wb,cy+wb,zb),.035,'steel',4)
    for z,w in [(14,5),(19,4),(23,3)]:
        beam('Transmission tower cross-arm',(cx-w,cy,z),(cx+w,cy,z),.05,'steel',4)
        for s in [-1,1]:
            beam('Tower truss strut',(cx,cy,z+1.4),(cx+s*w,cy,z),.035,'steel',4)
            beam('Suspended insulator',(cx+s*w,cy,z),(cx+s*w,cy,z-.7),.07,'cream',10)
            curve('High voltage catenary',[(cx+s*w-75,cy-14,z+2),(cx+s*w-36,cy-7,z-4),(cx+s*w,cy,z-.7),(cx+s*w+50,cy+10,z-3)],.023,'iron')
    for y in range(-9,25,3):beam('Chain-link fence post',(-16.5,y,0),(-16.5,y,2.1),.037,'rust',8)
    # One mesh of thin wire diamonds reduces overhead for fine detail.
    for j in range(2):
        beam('Fence horizontal rail',(-16.5,-9,.15+j*1.8),(-16.5,24,.15+j*1.8),.023,'iron',8)
    vv=[];ff=[]
    for yi in range(165):
        for zi in range(9):
            yy=-9+yi*.2;zz=.2+zi*.2
            for dy in [-.2,.2]:
                a=Vector((-16.5,yy,zz));b=Vector((-16.5,yy+dy,zz+.2));side=Vector((0,.004,-.004 if dy>0 else .004));o=len(vv)
                vv.extend([tuple(a-side),tuple(a+side),tuple(b+side),tuple(b-side)]);ff.append((o,o+1,o+2,o+3))
    mesh('Fine diagonal chain-link weave',vv,ff,'rust')
    # One leaning, empty handcart near the service corner.
    for x in [-9.3,-8.8]:
        beam('Salvage handcart rails',(x,-5.8,.1),(x,-5.3,1.05),.022,'rust')
        torus('Handcart wheel',(x,-5.77,.16),.12,.035,'rubber',rot=(pi/2,0,0))
    beam('Handcart grip',(-9.3,-5.3,1.05),(-8.8,-5.3,1.05),.025,'iron')

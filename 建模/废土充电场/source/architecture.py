"""Reference-based, fully editable industrial architecture for the charging yard.
All dimensions are in meters.  Front elevation faces negative Y.
"""
from common import *
import math
import random


def _boxes(name, entries, mat):
    """One editable mesh for regularly repeated fabricated parts."""
    verts, faces = [], []
    for item in entries:
        loc, size = item[:2]
        angle = item[2] if len(item) > 2 else 0.0
        x,y,z = loc; sx,sy,sz = [v*.5 for v in size]
        c,s = math.cos(angle), math.sin(angle); off=len(verts)
        for a,b,d in [(-sx,-sy,-sz),(sx,-sy,-sz),(sx,sy,-sz),(-sx,sy,-sz),(-sx,-sy,sz),(sx,-sy,sz),(sx,sy,sz),(-sx,sy,sz)]:
            verts.append((x+a*c-b*s,y+a*s+b*c,z+d))
        faces.extend(tuple(off+j for j in face) for face in [(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)])
    return mesh(name, verts, faces, mat)


def _rods(name, lines, mat, sides=8):
    verts, faces = [], []
    for a,b,r in lines:
        a,b=Vector(a),Vector(b); direction=(b-a).normalized()
        axis=Vector((0,0,1)) if abs(direction.z)<.9 else Vector((1,0,0))
        u=direction.cross(axis).normalized(); v=direction.cross(u).normalized()
        off=len(verts)
        for p in (a,b):
            for i in range(sides):
                point=p+r*(u*math.cos(i*2*pi/sides)+v*math.sin(i*2*pi/sides))
                verts.append(tuple(point))
        faces.append(tuple(off+i for i in reversed(range(sides))))
        faces.append(tuple(off+sides+i for i in range(sides)))
        for i in range(sides):
            j=(i+1)%sides; faces.append((off+i,off+j,off+sides+j,off+sides+i))
    return mesh(name,verts,faces,mat)


def _corr_wall(name, axis, plane, lo, hi, bottom, top, mat, pitch=.19, relief=.027):
    """Folded steel sheet; actual ridges, not a normal-map approximation."""
    count=max(1,int((hi-lo)/pitch)); pitch=(hi-lo)/count
    profile=[(0,0),(.20,0),(.32,relief),(.70,relief),(.82,0),(1,0)]
    verts,faces=[],[]
    for k in range(count):
        for i in range(len(profile)-1):
            q0,d0=profile[i];q1,d1=profile[i+1]
            a=lo+(k+q0)*pitch;b=lo+(k+q1)*pitch;off=len(verts)
            if axis=='X': verts.extend([(a,plane-d0,bottom),(b,plane-d1,bottom),(b,plane-d1,top),(a,plane-d0,top)])
            else: verts.extend([(plane+d0,a,bottom),(plane+d1,b,bottom),(plane+d1,b,top),(plane+d0,a,top)])
            faces.append((off,off+1,off+2,off+3))
    return mesh(name,verts,faces,mat)


def _corr_roof(name,x0,x1,y0,y1,z0,z1,mat,pitch=.22,warp=0):
    count=max(1,int((x1-x0)/pitch));pitch=(x1-x0)/count
    verts,faces=[],[]
    for k in range(count):
        for u in range(4):
            a=x0+(k+u/4)*pitch;b=x0+(k+(u+1)/4)*pitch
            da=[0,.035,.035,0,0][u];db=[0,.035,.035,0,0][u+1]
            off=len(verts)
            bend=warp*((k/count)**2)
            verts.extend([(a,y0,z0+da),(b,y0,z0+db),(b,y1,z1+db+bend),(a,y1,z1+da+bend)])
            faces.append((off,off+1,off+2,off+3))
    ob=mesh(name,verts,faces,mat)
    sol=ob.modifiers.new('Thin folded steel sheet','SOLIDIFY');sol.thickness=.014
    return ob


def _frame(name,xc,y,z,w,h,mat='white',thickness=.065):
    return _boxes(name,[((xc-w/2,y,z),(thickness,.11,h+thickness)),((xc+w/2,y,z),(thickness,.11,h+thickness)),((xc,y,z-h/2),(w,.11,thickness)),((xc,y,z+h/2),(w,.11,thickness))],mat)


def _window(name,xc,y,zc,w,h,bars=False):
    box(name+' deep recess',(xc,y+.06,zc),(w+.13,.10,h+.13),'black',.005)
    box(name+' dusty glazing',(xc,y,zc),(w,.025,h),'glass',.004)
    _frame(name+' steel frame',xc,y-.04,zc,w,h,'cream')
    box(name+' center mullion',(xc,y-.07,zc),(.043,.07,h),'silver',.004)
    box(name+' sill',(xc,y-.12,zc-h/2-.055),(w+.21,.26,.075),'steel',.008)
    if bars:
        rods=[]
        for i in range(int(w/.20)+1):
            x=xc-w/2+i*w/int(w/.20)
            rods.append(((x,y-.20,zc-h/2),(x,y-.20,zc+h/2),.018))
        for z in [zc-h/2,zc,zc+h/2]: rods.append(((xc-w/2,y-.20,z),(xc+w/2,y-.20,z),.018))
        _rods(name+' security bars',rods,'iron')


def _door(name,xc,y,base,w=1.0,h=2.16,mat='steel'):
    box(name+' threshold',(xc,y-.07,base+.035),(w+.22,.32,.07),'concrete_dark',.008)
    box(name+' inset door leaf',(xc,y,base+h*.5),(w,.065,h),mat,.012)
    _frame(name+' jamb',xc,y-.04,base+h*.5,w+.10,h+.07,'iron',.055)
    for z in [base+.27,base+h-.30]:box(name+' welded panel',(xc,y-.045,z),(w-.17,.027,.33),mat,.006)
    beam(name+' handle',(xc+w*.31,y-.10,base+1.00),(xc+w*.31,y-.10,base+1.22),.023,'silver')
    for z in [base+.28,base+1.0,base+h-.24]:box(name+' hinge',(xc-w/2-.015,y-.065,z),(.055,.055,.15),'rust',.004)


def _weather_strips(name,axis,plane,lo,hi,bottom,top,seed,count=18):
    rng=random.Random(seed);verts=[];faces=[]
    for i in range(count):
        x=rng.uniform(lo,hi);width=rng.uniform(.012,.062);zt=rng.uniform(bottom+.20,top);zb=max(bottom,zt-rng.uniform(.25,1.35))
        pts=[(x-width,zt),(x+width*.6,zt-.025),(x+width*.13,zb),(x-width*.2,zb+.10)]
        off=len(verts)
        if axis=='X':verts.extend((a,plane,z) for a,z in pts)
        else:verts.extend((plane,a,z) for a,z in pts)
        faces.append((off,off+1,off+2,off+3))
    return mesh(name,verts,faces,'rust')


def _container_structure(name,x,y,w,d,z,h,mat='white',front=True):
    # Shell is assembled out of independent sheet walls and structural rails.
    _corr_wall(name+' rear folded wall','X',y+d/2,x-w/2,x+w/2,z+.13,z+h-.13,mat)
    _corr_wall(name+' west folded wall','Y',x-w/2,y-d/2,y+d/2,z+.13,z+h-.13,mat)
    _corr_wall(name+' east folded wall','Y',x+w/2,y-d/2,y+d/2,z+.13,z+h-.13,mat)
    if front:_corr_wall(name+' front folded wall','X',y-d/2,x-w/2,x+w/2,z+.13,z+h-.13,mat)
    rails=[]
    for zz in [z+.09,z+h-.08]:
        for yy in [y-d/2,y+d/2]:rails.append(((x,yy,zz),(w,.14,.16)))
        for xx in [x-w/2,x+w/2]:rails.append(((xx,y,zz),(.14,d,.16)))
    for xx in [x-w/2,x+w/2]:
        for yy in [y-d/2,y+d/2]:rails.append(((xx,yy,z+h/2),(.16,.16,h)))
    _boxes(name+' ISO perimeter structure',rails,'steel')
    corners=[];holes=[]
    for xx in [x-w/2,x+w/2]:
        for yy in [y-d/2,y+d/2]:
            for zz in [z+.10,z+h-.10]:
                corners.append(((xx,yy,zz),(.22,.19,.19)))
                holes.append(((xx,yy-.101,zz),(.092,.012,.06)))
    _boxes(name+' corner castings',corners,'rust');_boxes(name+' corner lock apertures',holes,'black')
    box(name+' floor',(x,y,z+.08),(w,d,.15),'wood',.005)
    _corr_roof(name+' corrugated roof',x-w/2,x+w/2,y-d/2,y+d/2,z+h+.01,z+h+.02,mat)


def _orange_material():
    mat=material('yellow').copy();mat.name='Office burnt orange paint'
    mat.diffuse_color=(.52,.22,.064,1)
    for node in mat.node_tree.nodes:
        if node.type=='TEX_IMAGE' and node.image and node.image.name=='yellow_color':
            src=node.image;arr=np.array(src.pixels[:],dtype=np.float32).reshape(-1,4)
            arr[:,:3]*=np.array([1.05,.64,.40]);arr[:,:3]=np.clip(arr[:,:3],0,1)
            im=bpy.data.images.new('Office_orange_color',width=src.size[0],height=src.size[1],alpha=False)
            im.pixels.foreach_set(arr.ravel());im.pack();node.image=im
    return mat


def _office():
    collection('ARCH • Two storey container office')
    orange=_orange_material()
    _container_structure('Office lower',10,0,6,5,.20,2.80,'steel',False)
    # True apertures around the front security window and the entrance door.
    y=-2.515
    for xa,xb,za,zb in [(7,7.55,.34,2.88),(10.35,10.95,.34,2.88),(12.10,13,.34,2.88),(7.55,10.35,.34,.97),(7.55,10.35,2.31,2.88),(10.95,12.10,2.45,2.88)]:
        _corr_wall('Office lower front sheet','X',y,xa,xb,za,zb,'steel')
    _window('Office barred front window',8.95,y-.018,1.64,2.66,1.20,True)
    _door('Office lower door',11.525,y-.013,.24,1.01,2.15,'cream')
    _window('Small office service window',12.58,-2.57,1.77,.46,.71,False)
    _weather_strips('Office rusty lower seams','X',-2.548,7,10.4,.34,2.86,94,25)
    _container_structure('Office upper',10,0,6,5,3.01,2.80,orange,False)
    for xa,xb,za,zb in [(7,7.31,3.15,5.69),(10.50,10.94,3.15,5.69),(12.05,13,3.15,5.69),(7.31,10.50,3.15,3.60),(7.31,10.50,5.22,5.69),(10.94,12.05,5.27,5.69)]:
        _corr_wall('Office upper orange sheet','X',-2.515,xa,xb,za,zb,orange)
    _window('Upper broad dark glass strip',8.90,-2.56,4.42,3.11,1.54)
    # Additional mullions create the reference's three-pane window strip.
    for x in [7.89,9.92]:box('Upper narrow window mullion',(x,-2.64,4.42),(.043,.08,1.54),'iron',.004)
    _door('Office upper terrace door',11.50,-2.55,3.06,.99,2.15,orange)
    box('Office upper door glass',(11.50,-2.604,4.55),(.77,.025,.74),'glass',.004)
    _weather_strips('Orange cabin seam rust','X',-2.553,12.11,12.95,3.15,5.70,104,14)
    # Front terrace and east passage connect the landing to the front door.
    box('Terrace black steel plate',(10,-3.27,2.97),(6.6,1.49,.14),'iron',.012)
    box('East elevated access passage',(13.56,-1.04,2.97),(1.13,3.00,.14),'iron',.012)
    beams=[]
    for x in [6.8,9.3,11.7,13.24]:
        beams.append(((x,-3.91,.18),(x,-3.91,2.97),.065))
        beams.append(((x,-3.87,1.9),(x,-2.66,2.89),.037))
        box('Terrace support footing',(x,-3.91,.14),(.37,.34,.23),'concrete',.024)
    _rods('Terrace columns and diagonal brackets',beams,'rust')
    rails=[]
    for x in [6.72,7.72,8.72,9.72,10.72,11.72,12.72,13.28]:
        rails.append(((x,-3.97,3.03),(x,-3.97,4.13),.027))
    for z in [3.13,3.56,4.12]:rails.append(((6.70,-3.97,z),(13.28,-3.97,z),.027))
    for yy in [-3.95,-3.20,-2.5]: rails.append(((6.70,yy,3.03),(6.70,yy,4.13),.026))
    for z in [3.56,4.12]:rails.append(((6.70,-3.97,z),(6.70,-2.50,z),.026))
    # East rail follows the side passage, with landing entry left open.
    for yy in [-2.45,-1.5,-.6]:rails.append(((14.13,yy,3.03),(14.13,yy,4.13),.025))
    for z in [3.56,4.12]:rails.append(((14.13,-2.47,z),(14.13,-.43,z),.025))
    _rods('Terrace full tubular balustrade',rails,'silver')
    # Thin overhead trellis frame, open to the sky as in reference 01.
    lines=[]
    for x in [6.70,9.90,13.27]:
        for yy in [-3.98,-2.55]:lines.append(((x,yy,3.07),(x,yy,6.18),.022))
        lines.append(((x,-3.98,6.18),(x,-2.55,6.18),.022))
    for yy in [-3.98,-2.55]:
        for z in [5.38,6.18]:lines.append(((6.70,yy,z),(13.27,yy,z),.024))
    for x in [7.5,8.3,9.1,10.7,11.5,12.3]:lines.append(((x,-3.98,6.18),(x,-2.55,6.18),.012))
    _rods('Office open overhead plant trellis',lines,'iron')
    curve('Terrace loose rope',[(6.72,-3.98,5.37),(8.2,-3.98,4.94),(9.9,-3.98,5.37)],.009,'wood')
    # Glazed IBC tank, enclosed by an actual square-tube welded cage.
    tankx,tanky,tankz=12.40,-3.20,3.64
    box('IBC weathered pallet',(tankx,tanky,3.14),(1.10,.93,.20),'black',.025)
    box('IBC translucent white polymer tank',(tankx,tanky,tankz),(1.02,.83,.97),'white',.12)
    cage=[]
    for dx in [-.55,-.28,0,.28,.55]:
        for yy in [tanky-.46,tanky+.46]:cage.append(((tankx+dx,yy,3.22),(tankx+dx,yy,4.19),.011))
    for dy in [-.46,-.16,.16,.46]:
        for xx in [tankx-.55,tankx+.55]:cage.append(((xx,tanky+dy,3.22),(xx,tanky+dy,4.19),.011))
    for z in [3.24,3.50,3.78,4.05,4.19]:
        cage.extend([((tankx-.55,tanky-.46,z),(tankx+.55,tanky-.46,z),.013),((tankx-.55,tanky+.46,z),(tankx+.55,tanky+.46,z),.013),((tankx-.55,tanky-.46,z),(tankx-.55,tanky+.46,z),.013),((tankx+.55,tanky-.46,z),(tankx+.55,tanky+.46,z),.013)])
    _rods('IBC galvanized cage',cage,'silver')
    cyl('IBC fill cap',(tankx,tanky,4.19),.12,.05,'black',16)
    beam('IBC low outlet',(tankx,tanky-.44,3.25),(tankx,tanky-.63,3.25),.042,'cream',12)
    box('IBC valve red lever',(tankx,tanky-.62,3.32),(.17,.035,.035),'red',.005)
    # Empty/dead pots with soil; plant foliage can be added by ground module.
    for index,(x,y,r,h) in enumerate([(7.2,-3.28,.27,.34),(8.5,-3.35,.32,.45),(10.3,-3.32,.28,.36)]):
        cyl('Terrace planter %d'%index,(x,y,3.05+h/2),r*.75,h,'red',16,radius_top=r)
        cyl('Terrace planter soil %d'%index,(x,y,3.05+h-.014),r*.90,.02,'soil',16)
        torus('Terrace pot rim',(x,y,3.05+h),r*.94,.027,'cream')
    # Air conditioner beside the building with condenser fan, wiring, and drain.
    box('Office condenser brackets',(13.09,.84,1.32),(.31,1.01,.08),'rust',.005)
    box('Office AC condenser case',(13.25,.84,1.73),(.52,.93,.68),'cream',.045)
    cyl('Condenser fan recess',(13.524,.85,1.73),.25,.025,'black',24,rot=(0,pi/2,0))
    rings=[]
    for z in range(8):rings.append(((13.549,.57,1.45+z*.075),(13.549,1.13,1.45+z*.075),.007))
    _rods('AC condenser face grille',rings,'silver',6)
    for a in [0,pi*.5,pi,pi*1.5]:
        beam('Condenser fan blade',(13.553,.85,1.73),(13.553,.85+.2*cos(a),1.73+.2*sin(a)),.039,'steel')
    curve('AC insulated pipe',[(13.13,1.2,1.7),(13.03,1.5,1.65),(13.03,1.5,.5)],.027,'white')
    curve('Office electric cable',[(12.85,-2.6,2.85),(12.82,-2.7,2.45),(12.83,-2.69,.65)],.012,'black')
    box('Office weathered yellow number board',(12.58,-2.60,4.68),(.60,.034,.61),'yellow',.008)
    text_obj('Office hand painted 07','07',(12.58,-2.626,4.72),.31,'black')
    box('Office entrance light fixture',(11.5,-2.71,2.69),(.49,.25,.08),'black',.02)
    box('Office entrance light lens',(11.5,-2.74,2.65),(.34,.15,.025),'light_warm',.009)


def _stair():
    collection('ARCH • Open metal office staircase')
    left,right=13.42,14.72
    y0,y1,z0,z1=-6.30,-.24,.19,2.98
    for x in [left,right]:
        # Channel stringers have a web and upper/lower edge flanges.
        direction=Vector((0,y1-y0,z1-z0));length=direction.length;angle=math.atan2(z1-z0,y1-y0)
        ob=box('Stair rusted channel stringer',(x,(y0+y1)/2,(z0+z1)/2),(.095,length,.20),'rust',.008,rot=(angle,0,0))
    steps=[];nosings=[]
    for i in range(17):
        y=y0+(i+.5)*(y1-y0)/17;z=z0+(i+1)*(z1-z0)/17
        for k in range(5):steps.append((((left+right)/2,y-.135+k*.064,z),((right-left)+.05,.045,.036)))
        nosings.append((((left+right)/2,y-.166,z+.009),((right-left)+.075,.027,.055)))
    _boxes('Stair open tread steel grating',steps,'steel')
    _boxes('Stair worn pale tread nosings',nosings,'silver')
    rails=[]
    for x in [left-.055,right+.055]:
        for i in [0,3,6,9,12,16,17]:
            y=y0+i*(y1-y0)/17;z=z0+i*(z1-z0)/17
            rails.append(((x,y,z),(x,y,z+1.03),.025))
        for dz in [.52,1.03]:rails.append(((x,y0,z0+dz),(x,y1,z1+dz),.027))
    _rods('Stair twin continuous handrails',rails,'silver')
    box('Stair top landing',(14.05,.20,2.98),(1.65,.94,.12),'steel',.012)
    for x in [13.4,14.73]:
        box('Stair landing column',(x,.56,1.52),(.12,.12,2.92),'rust',.012)
        box('Stair concrete anchor',(x,.56,.14),(.45,.45,.24),'concrete',.012)
        for dx in [-.12,.12]:cyl('Stair footing bolt',(x+dx,.56,.276),.022,.035,'silver',6)
    _rods('Landing end balustrade',[((13.25,.67,3.03),(13.25,.67,4.09),.026),((14.86,.67,3.03),(14.86,.67,4.09),.026),((13.25,.67,4.09),(14.86,.67,4.09),.028),((13.25,.67,3.56),(14.86,.67,3.56),.027)],'silver')


def _canopy():
    collection('ARCH • Weathered charging canopy')
    posts=[];bolts=[];purlins=[]
    for x in [-11.05,-3.03]:
        for y in [-5.10,.20,5.50,10.80,16.10]:
            top=3.80+(x+11.05)*.037
            box('Canopy concrete pad',(x,y,.13),(.61,.58,.25),'concrete',.02)
            box('Canopy column base plate',(x,y,.27),(.36,.33,.035),'rust',.005)
            # I-section profile: two flanges and a thin web.
            posts.extend([((x-.07,y,(top+.28)/2),(.036,.17,top-.28)),((x+.07,y,(top+.28)/2),(.036,.17,top-.28)),((x,y,(top+.28)/2),(.14,.028,top-.28))])
            for dx in [-.115,.115]:
                for dy in [-.102,.102]:bolts.append(((x+dx,y+dy,.28),(x+dx,y+dy,.33),.023))
            beam('Canopy short knee brace',(x,y,top-.69),(x+( .63 if x<-5 else -.63),y,top-.05),.036,'rust',6)
    _boxes('Canopy exposed I-section columns',posts,'cream');_rods('Canopy anchored hex bolts',bolts,'iron',6)
    for y in [-5.10,.20,5.50,10.80,16.10]:
        beam('Canopy main transverse beam',(-11.20,y,3.78),(-2.90,y,4.09),.065,'iron',4)
        # Light triangular underside truss, making roof appear engineered.
        beam('Canopy truss bottom chord',(-11.03,y,3.57),(-3.02,y,3.88),.034,'rust',6)
        for i in range(8):
            x=-11.03+i; z=3.58+(x+11.03)*.037
            beam('Canopy triangulated web',(x,y,z),(x+.50,y,z+.25),.017,'rust',6)
            beam('Canopy triangulated web',(x+.50,y,z+.25),(x+1,y,z+.037),.017,'rust',6)
    for x in [-11.10,-9.06,-7.02,-4.98,-2.94]:
        purlins.append(((x,5.50,3.85+(x+11.1)*.037),(.055,21.42,.065)))
    _boxes('Canopy longitudinal purlins',purlins,'iron')
    # Panels omitted near foreground and in two storm-damaged bays.
    for j in range(10):
        ya=-5.35+j*2.18;yb=ya+2.13
        for i in range(4):
            if (j,i) in {(0,2),(0,3),(1,3),(4,1),(7,2)}:continue
            xa=-11.27+i*2.11;xb=xa+2.07
            z=3.91+(xa+11.27)*.037
            mat='cream' if (i+j)%5 else 'steel'
            ob=_corr_roof('Canopy separate roof sheet %02d_%02d'%(j,i),xa,xb,ya,yb,z,z,mat)
            # Applied transverse slope; sheets remain editable individual pieces.
            for v in ob.data.vertices:v.co.z+=(v.co.x-xa)*.037
            if (j,i)==(4,2):
                for v in ob.data.vertices:
                    if v.co.y>yb-.8:v.co.z+=.36*(v.co.y-(yb-.8))/.8
            if (j,i)==(7,1):
                for v in ob.data.vertices:
                    if v.co.x<xa+.5:v.co.z-=.35*(1-(v.co.x-xa)/.5)
    box('Canopy east rain gutter',(-2.85,5.48,4.025),(.15,21.80,.15),'rust',.018)
    curve('Canopy broken drainpipe',[(-2.82,15.87,4.08),(-2.71,16.02,3.84),(-2.71,16.02,1.26),(-2.47,16.02,1.08)],.044,'steel')
    for y in [-2.1,3.5,9.0,14.0]:
        box('Canopy old fluorescent fitting',(-7,y,3.53),(1.45,.19,.10),'iron',.018)
        box('Canopy stained strip lamp',(-7,y,3.472),(1.27,.095,.025),'cream',.012)
    curve('Canopy sagging service cable',[(-11.12,-5.08,3.45),(-11.16,1.0,3.05),(-11.10,7.0,3.41),(-11.14,13.0,3.11),(-11.12,16.10,3.46)],.016,'black')


def _warehouse():
    collection('ARCH • Rear industrial warehouse')
    x0,x1,y0,y1=-14,20,22,29
    box('Warehouse concrete stem wall',((x0+x1)/2,25.5,.42),(34,7,.72),'concrete_dark',.015)
    _corr_wall('Warehouse rear elevation','X',29,x0,x1,.68,4.86,'cream',.24,.033)
    for x in [x0,x1]:
        _corr_wall('Warehouse side gable wall','Y',x,22,29,.68,4.84,'cream',.24,.035)
        mesh('Warehouse upper gable',[(x,22,4.84),(x,29,4.84),(x,25.5,6.16)],[(0,1,2)],'cream')
    # Structural piers interleave four rolling doors.
    doors=[(-9.65,5.1),(-1.05,5.50),(7.65,5.20),(16.40,4.55)]
    cursor=x0
    for index,(cx,width) in enumerate(doors):
        left,right=cx-width/2,cx+width/2
        _corr_wall('Warehouse front wall pier','X',21.985,cursor,left,.70,4.84,'cream',.24,.035)
        _corr_wall('Warehouse overhead cladding','X',21.985,left,right,3.42,4.84,'cream',.24,.035)
        box('Warehouse roller opening',(cx,21.955,1.92),(width,.08,3.16),'black',.005)
        # The first shutter stops part way up, leaving a dark loading aperture.
        bottom=.94 if index==0 else .56
        _boxes('Warehouse shutter rolled slats %d'%index,[((cx,21.895,bottom+.064+i*.129),(width-.09,.068,.119)) for i in range(int((3.39-bottom)/.129))],'steel' if index%2 else 'cream')
        _frame('Warehouse rollup door track',cx,21.84,1.96,width+.15,3.30,'iron',.085)
        box('Warehouse roller drum cover',(cx,21.87,3.61),(width+.29,.38,.38),'rust',.032)
        box('Warehouse door pull bar',(cx,21.827,bottom+.25),(.67,.07,.06),'iron',.006)
        text_obj('Warehouse bay number','0%d'%(index+1),(left+.3,21.831,3.95),.34,'white')
        cursor=right
    _corr_wall('Warehouse end pier','X',21.985,cursor,x1,.70,4.84,'cream',.24,.035)
    # Long clerestory strip under the front eaves.
    for i in range(17):
        cx=-13.0+i*1.97
        _window('Warehouse dusty clerestory',cx,21.91,4.43,1.56,.46)
    columns=[]
    for x in [-14,-5.5,3,11.5,20]:
        columns.append(((x,21.86,2.53),(.16,.19,4.63)))
        columns.append(((x,29.04,2.53),(.16,.19,4.63)))
    _boxes('Warehouse steel bay columns',columns,'rust')
    # Gable roof panels slope from a center ridge; ribs run downslope.
    for i in range(17):
        xa=-14.42+i*2.04;xb=xa+2.00
        for side in [0,1]:
            ya,yb,za,zb=(21.64,25.50,4.93,6.19) if side==0 else (25.50,29.35,6.19,4.93)
            _corr_roof('Warehouse roof folded sheet %02d_%d'%(i,side),xa,xb,ya,yb,za,zb,'cream' if i%6 else 'steel',.21)
    _boxes('Warehouse metal fascia',[(((x0+x1)/2,21.60,4.86),(34.9,.15,.19)),(((x0+x1)/2,29.40,4.86),(34.9,.15,.19))],'rust')
    # Ridge cap is a folded inverted V, with physical thickness.
    roof=mesh('Warehouse continuous ridge flashing',[(x0-.5,25.20,6.13),(x1+.5,25.20,6.13),(x1+.5,25.50,6.25),(x0-.5,25.50,6.25),(x0-.5,25.80,6.13),(x1+.5,25.80,6.13)],[(0,1,2,3),(3,2,5,4)],'rust')
    roof.modifiers.new('Ridge thin sheet','SOLIDIFY').thickness=.015
    for x in [-13.6,3.0,19.6]:
        curve('Warehouse rain downpipe',[(x,21.57,4.89),(x,21.48,4.4),(x,21.48,.47),(x,21.11,.25)],.063,'steel')
    box('Warehouse weathered service sign',(7.64,21.57,3.77),(4.06,.07,.43),'blue',.004)
    text_obj('Warehouse service sign lettering','机 械 维 修',(7.64,21.523,3.79),.28,'white')
    for x in [-12.8,-4.6,4.1,12.9,19.5]:
        beam('Warehouse floodlight arm',(x,21.74,4.12),(x,21.29,4.25),.026,'iron')
        box('Warehouse floodlight',(x,21.26,4.20),(.32,.18,.21),'iron',.025,rot=(.2,0,0))
        box('Warehouse floodlight lens',(x,21.16,4.18),(.25,.017,.14),'cream',.008,rot=(.2,0,0))


def _industrial_containers():
    collection('ARCH • Stacked utility containers and water tanks')
    # The left-side double white cabin sits behind the charging machines.
    for level in range(2):
        z=.19+level*2.72
        _container_structure('White utility container level %d'%level,-16.40,13.80,6.0,4.20,z,2.70,'white')
    for xc in [-18.1,-16.4,-14.7]:
        box('Utility upper ventilation inset',(xc,11.647,4.94),(1.37,.06,.94),'black',.004)
        _frame('Utility vent perimeter',xc,11.61,4.94,1.43,1.0,'white')
        _boxes('Utility horizontal ventilation louvres',[((xc,11.57,4.53+j*.12),(1.36,.095,.074)) for j in range(8)],'cream')
    box('Utility container old maker plaque',(-16.42,11.568,2.17),(3.61,.045,.57),'white',.004)
    text_obj('Utility UTILITY industrial letters','UTILITY  POWER',(-16.42,11.536,2.2),.34,'blue')
    # Rear blue cargo cabin beside the segmented water reservoir.
    _container_structure('Blue industrial tank cabin',-16.47,19.34,6.05,4.40,.19,2.70,'blue')
    _door('Blue cabin double left door',-17.30,17.101,.27,1.17,2.27,'blue')
    _door('Blue cabin double right door',-16.04,17.101,.27,1.17,2.27,'blue')
    locks=[]
    for x in [-17.69,-16.89,-16.43,-15.63]:
        locks.append(((x,16.98,.5),(x,16.98,2.34),.018))
        for z in [.6,1.43,2.2]:box('Cargo locking rod keeper',(x,16.97,z),(.095,.058,.066),'steel',.008)
        beam('Cargo twist-lock handle',(x,16.94,1.3),(x+.19,16.94,1.3),.022,'silver')
    _rods('Cargo twin locking bars',locks,'silver')
    _weather_strips('Blue cabin seam corrosion','X',17.064,-19.4,-13.48,.33,2.78,240,48)
    # Panelized stainless steel reservoir, with domed panels seen in ref04.
    tx,ty,tz=-16.50,19.30,4.14
    box('Segmented reservoir supporting raft',(tx,ty,2.97),(5.54,3.58,.20),'iron',.016)
    box('Panel water reservoir inner shell',(tx,ty,tz),(5.24,3.24,2.20),'silver',.022)
    seams=[]
    for face in ['front','back']:
        yy=ty+(-1 if face=='front' else 1)*1.657
        for ix in range(5):
            for iz in range(2):
                x=tx-2.08+ix*1.04;z=3.59+iz*1.10
                # Convex stamped panel: faceted dome and metal square rim.
                box('Reservoir %s panel flange'%face,(x,yy,z),(1.016,.035,1.07),'silver',.032)
                ico('Reservoir %s pressed dome'%face,(x,yy+(-.075 if face=='front' else .075),z),(.45,.12,.45),'silver',3)
        for ix in range(6):
            x=tx-2.60+ix*1.04;seams.append(((x,yy-.023,3.05),(.024,.023,2.19)))
        for z in [3.045,4.14,5.235]:seams.append(((tx,yy-.023,z),(5.23,.023,.024)))
    for side in [-1,1]:
        xx=tx+side*2.667
        for iy in range(3):
            for iz in range(2):
                y=ty-1.06+iy*1.06;z=3.59+iz*1.10
                box('Reservoir side panel flange',(xx,y,z),(.033,1.04,1.07),'silver',.024)
                ico('Reservoir side pressed dome',(xx+side*.064,y,z),(.12,.45,.45),'silver',3)
    _boxes('Water tank bolted panel seams',seams,'steel')
    rivets=[]
    for ix in range(6):
        x=tx-2.60+ix*1.04
        for iz in range(9):
            z=3.13+iz*.25;rivets.append(((x,ty-1.683,z),(x,ty-1.712,z),.017))
    _rods('Water reservoir flange bolt heads',rivets,'iron',6)
    cyl('Water tank inspection hatch',(tx-.6,ty,5.29),.44,.085,'steel',32)
    torus('Reservoir hatch seal',(tx-.6,ty,5.341),.35,.018,'black')
    beam('Water tank vent riser',(tx+1.4,ty,5.23),(tx+1.4,ty,5.82),.052,'silver',12)
    cyl('Water tank mushroom vent',(tx+1.4,ty,5.82),.14,.08,'steel',16)
    curve('Reservoir descending service pipe',[(tx+2.7,ty+.5,4.8),(tx+2.97,ty+.5,4.6),(tx+2.97,ty+.5,.35),(tx+3.4,ty+.5,.24)],.061,'silver')
    ladder=[]
    for x in [tx-1.12,tx-.58]:ladder.append(((x,ty-1.94,2.86),(x,ty-1.94,5.65),.022))
    for z in [2.96+i*.28 for i in range(10)]:ladder.append(((tx-1.12,ty-1.94,z),(tx-.58,ty-1.94,z),.019))
    _rods('Water reservoir inspection ladder',ladder,'silver')


def _entry():
    collection('ARCH • Entrance booth and raised barrier')
    _container_structure('Entry booth',-17,-14,3.6,3.6,.14,2.70,'white',False)
    for xa,xb,za,zb in [(-18.8,-18.4,.28,2.70),(-15.7,-15.2,.28,2.70),(-18.4,-15.7,.28,1.05),(-18.4,-15.7,2.32,2.70)]:
        _corr_wall('Entry booth front sheet','X',-15.805,xa,xb,za,zb,'white')
    _window('Booth sliding front window',-17.05,-15.84,1.70,2.58,1.18)
    box('Booth front projecting counter',(-17.03,-16.13,1.11),(2.88,.65,.085),'wood',.016)
    _window('Entry booth adjacent notice window',-17.0,-15.84,.65,1.00,.43,False)
    box('Booth rain hood',(-17,-16.04,2.74),(4.03,1.1,.12),'iron',.012,rot=(.06,0,0))
    # Slightly peeled industrial blue enamel sign over the booth.
    box('Entry booth blue header',(-17,-15.906,2.50),(2.30,.054,.35),'blue',.008)
    text_obj('Entry booth duty room letters','值 班 室',(-17,-15.949,2.515),.26,'white')
    box('Entry notice plate',(-15.71,-15.89,.65),(.64,.033,.79),'yellow',.009)
    text_obj('Entry small warning digits','24 H',(-15.71,-15.918,.83),.17,'black')
    # Barrier mechanism sits left of center, raised enough to keep the aisle open.
    box('Entrance barrier concrete plinth',(-7.0,-17.15,.18),(.99,.88,.32),'concrete',.025)
    box('Barrier motor pedestal',(-7.0,-17.15,.96),(.49,.53,1.31),'iron',.045)
    box('Barrier motor painted cover',(-7.0,-17.15,1.45),(.61,.61,.39),'yellow',.04)
    cyl('Barrier pivot',(-6.98,-17.48,1.56),.16,.11,'silver',20,rot=(pi/2,0,0))
    # A 40 degree raised, alternating red-white boom; individually editable sections.
    pivot=Vector((-6.98,-17.43,1.57));angle=math.radians(39);length=6.0
    for i in range(12):
        x=pivot.x+(i+.5)*(length/12)*cos(angle);z=pivot.z+(i+.5)*(length/12)*sin(angle)
        box('Barrier %s section %02d'%('red' if i%2 else 'white',i),(x,pivot.y,z),(length/12+.006,.095,.135),'red' if i%2 else 'white',.008,rot=(0,-angle,0))
    box('Barrier unused receiving post',(-.97,-17.40,.60),(.10,.14,1.14),'rust',.014)
    torus('Barrier boom counterweight spring',(-7.01,-17.51,1.57),.135,.023,'iron',rot=(pi/2,0,0))
    for x in [-8.0,2.8]:
        box('Entrance parking reader pedestal',(x,-17.6,.78),(.13,.13,1.47),'iron',.014)
        box('Entrance parking reader head',(x,-17.63,1.62),(.52,.26,.75),'black',.033)
        box('Entrance reader dark display',(x,-17.774,1.62),(.40,.015,.40),'screen',.012)
        text_obj('Entrance parking P','P',(x,-17.794,1.87),.21,'white')
        if x<0:
            text_obj('Entrance active digits','07:21',(x,-17.794,1.65),.10,'light_cyan')
            box('Entrance reader status line',(x,-17.795,1.48),(.30,.008,.027),'light_cyan',.004)
        box('Entrance bollard foot',(x,-17.60,.085),(.37,.37,.15),'concrete_dark',.018)


def build():
    _office()
    _stair()
    _canopy()
    _warehouse()
    _industrial_containers()
    _entry()

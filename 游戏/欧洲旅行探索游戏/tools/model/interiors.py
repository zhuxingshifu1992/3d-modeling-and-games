"""Enterable multi-floor building shells, safe stair ramps and detailed room furniture."""
import math,random

class _Local:
    def __init__(self,B,x,y,angle=0):self.B=B;self.x=x;self.y=y;self.a=angle;self.c=math.cos(angle);self.s=math.sin(angle)
    def point(self,p):return (self.x+p[0]*self.c-p[1]*self.s,self.y+p[0]*self.s+p[1]*self.c,p[2])
    def box(self,n,p,size,m,rot=0):self.B.box(n,self.point(p),size,m,rot+self.a)
    def cyl(self,n,p,r,d,m,vertices=16,radius_top=None):self.B.cyl(n,self.point(p),r,d,m,vertices,radius_top)
    def beam(self,n,a,b,r,m,sides=4):self.B.beam(n,self.point(a),self.point(b),r,m,sides)
    def poly(self,n,vs,fs,m):self.B.poly(n,[self.point(v) for v in vs],fs,m)

def furnish_space(B,id,cx,cy,w,d,z,style):
    """Furnish around an unobstructed center aisle and a reserved rear-right stairwell."""
    T=_Local(B,cx,cy);p='IN_'+id;scale=min(1,w/7,d/8)
    if w<4.5 or d<4.5:
        T.box(p+'_Furniture',(0,d/2-.08,z+1.3),(w*.55,.055,.78),'gold')
        T.box(p+'_Furniture',(0,d/2-.115,z+1.3),(w*.49,.015,.68),'fabric')
        return
    rng=random.Random(sum(ord(c) for c in id));floor_mat='marble' if style in ('castle','church') else 'parquet'
    T.box(p+'_Rug',(-w*.23,-d*.19,z+.015),(w*.35,d*.32,.018),'fabric')
    def box(name,pos,size,mat,rot=0):
        T.box(p+'_'+name,(pos[0],pos[1],z+pos[2]),size,mat,rot)
        if name in ('Furniture','Cabinetry','Bookcase'):
            T.box('COL_'+id+'_Furniture',(pos[0],pos[1],z+pos[2]),size,'stone',rot)
    def table(x,y,width=1.65,depth=.85,height=.77):
        box('Furniture',(x,y,height),(width,depth,.09),'wood')
        for xx in (-width*.4,width*.4):
            for yy in (-depth*.35,depth*.35):box('Furniture',(x+xx,y+yy,height/2),(.075,.075,height),'dark_wood')
        box('Table_Details',(x+.25,y,height+.065),(.42,.28,.035),'leather')
        box('Table_Details',(x+.25,y,height+.09),(.39,.25,.012),'ceiling')
        T.cyl(p+'_Table_Details',(x-.35,y,z+height+.15),.095,.2,'marble',16)
        T.cyl(p+'_Table_Details',(x-.35,y,z+height+.25),.103,.015,'gold',16)
    def chair(x,y,rot=0):
        Q=_Local(T,x,y,rot)
        Q.box(p+'_Furniture',(0,0,z+.45),(.48,.5,.10),'wood')
        Q.box(p+'_Furniture',(0,.21,z+.77),(.47,.07,.61),'wood')
        Q.box(p+'_Upholstery',(0,0,z+.51),(.41,.4,.08),'fabric')
        for xx in (-.18,.18):
            for yy in (-.18,.18):Q.box(p+'_Furniture',(xx,yy,z+.23),(.06,.06,.46),'dark_wood')
    if style=='church':
        for yy in (-d*.24,-d*.05,d*.14):
            for sx in (-1,1):
                box('Furniture',(sx*w*.26,yy,.5),(w*.30,.5,.15),'wood')
                box('Furniture',(sx*w*.26,yy+.23,.85),(w*.30,.08,.62),'dark_wood')
                for dx in (-w*.12,w*.12):box('Furniture',(sx*w*.26+dx,yy,.23),(.09,.4,.46),'dark_wood')
        table(0,d*.33,w*.45,1,1)
        box('Sacred_Details',(0,d*.40,2.0),(.10,.10,1.5),'gold')
        box('Sacred_Details',(0,d*.40,2.3),(.75,.10,.1),'gold')
    else:
        table(-w*.23,-d*.16,1.7*scale,.88*scale)
        chair(-w*.23-.98*scale,-d*.16,math.pi/2);chair(-w*.23+.98*scale,-d*.16,-math.pi/2)
        # Upholstered sofa remains against the left wall, outside entry circulation.
        x=-w/2+.72;y=-d*.33
        box('Furniture',(x,y,.31),(.82,1.75,.35),'dark_wood')
        box('Upholstery',(x+.05,y,.58),(.72,1.62,.22),'leather' if style=='castle' else 'fabric')
        box('Upholstery',(x-.34,y,.9),(.18,1.75,.90),'fabric')
        for yy in (-.79,.79):box('Upholstery',(x,y+yy,.75),(.86,.16,.56),'fabric')
        for yy in (-.40,.40):box('Upholstery',(x+.12,y+yy,.77),(.32,.38,.15),'ceiling',.15)
        # Paneled kitchen / sideboard at the rear left; cookware, countertop and basin.
        for k in range(3):
            xx=-w*.34+k*.75;yy=d/2-.72
            box('Cabinetry',(xx,yy,.46),(.72,.62,.86),'wood')
            box('Cabinetry',(xx,yy-.33,.5),(.64,.04,.72),'dark_wood')
            box('Cabinetry',(xx,yy-.37,.53),(.54,.035,.59),'wood')
            box('Hardware',(xx+.18,yy-.40,.7),(.13,.04,.035),'bronze')
            box('Countertops',(xx,yy,.93),(.78,.73,.09),'marble')
            box('Cabinetry',(xx,yy,1.98),(.72,.4,.75),'wood')
            box('Cabinetry',(xx,yy-.23,1.98),(.65,.03,.64),'wood')
        T.cyl(p+'_Cookware',(-w*.34,d/2-.72,z+1.14),.22,.32,'metal',18)
        T.cyl(p+'_Cookware',(-w*.34,d/2-.72,z+1.31),.24,.03,'bronze',18)
        T.beam(p+'_Hardware',(-w*.34+.75,d/2-.59,z+.98),(-w*.34+.75,d/2-.59,z+1.24),.023,'metal',8)
        box('Countertops',(-w*.34+.75,d/2-.72,.995),(.5,.4,.025),'metal')
        # A bed and work desk occupy the left central zone on upper floors.
        if '_L0' not in id and d>9:
            bx=-w*.24;by=d*.16
            box('Furniture',(bx,by,.26),(1.55,2.1,.4),'dark_wood')
            box('Upholstery',(bx,by,.55),(1.48,2,.28),'ceiling')
            box('Upholstery',(bx,by-.2,.73),(1.52,1.5,.09),'fabric')
            for dx in (-.37,.37):box('Upholstery',(bx+dx,by+.68,.77),(.57,.43,.16),'ceiling')
            box('Furniture',(bx,by+.99,.89),(1.65,.13,1.1),'wood')
        # Full bookcase with shelves and individual book spines.
        bx=w/2-.6;by=-d*.29
        box('Bookcase',(bx,by,1.18),(.43,1.50,2.35),'dark_wood')
        for lev in range(5):
            zz=.18+lev*.45;box('Bookcase',(bx-.09,by,zz),(.53,1.56,.07),'wood')
            for k in range(10):
                hh=rng.uniform(.24,.36)
                box('Books',(bx-.17,by-.63+k*.137,zz+hh/2+.06),(.34,.09,hh),rng.choice(['red','leather','fabric','gold','dark_wood']))
        # Framed oil-painting-like layered landscape relief and panel moldings.
        xx=-w/2+.08;yy=.25
        box('Wall_Decoration',(xx,yy,1.9),(.08,1.55,1.08),'gold')
        box('Wall_Decoration',(xx+.05,yy,1.9),(.022,1.39,.92),'fabric')
        for j in range(5):box('Wall_Decoration',(xx+.07,yy-.5+j*.23,1.72+rng.random()*.20),(.015,.27,.28),'foliage_dark')
    # Curtains are multiple folded strips, not a flat billboard.
    for sx in (-1,1):
        for j in range(7):box('Curtains',(sx*(w*.30)+j*.052,-d/2+.20,1.62),(.095,.12+(j%2)*.06,1.95),'fabric')
    # Interior trim and warm hanging pendant. Light data is separately registered.
    for sx in (-1,1):box('Trim',(sx*(w/2-.04),0,.14),(.07,d,.21),'wood')
    T.beam(p+'_Lighting',(0,0,z+2.72),(0,0,z+2.43),.023,'bronze',8)
    T.cyl(p+'_Lighting',(0,0,z+2.35),.29,.20,'gold',20,.18)
    T.cyl(p+'_Lighting',(0,0,z+2.245),.25,.018,'emissive',20)

def make_building(B,id,label,cx,cy,w,d,base,height,style,floors=2,front_angle=0,shell=True):
    if not hasattr(B,'buildings'):B.buildings=[]
    if not hasattr(B,'room_lights'):B.room_lights=[]
    floors=max(1,int(floors));fh=height/floors;T=_Local(B,cx,cy,front_angle);wall=.3
    def solid(name,loc,size,mat,collision=True):
        T.box(name,loc,size,mat)
        if name.endswith('_Floors'):
            B.groups[name]['m'][-6]='ceiling'
        if collision:T.box('COL_'+id+'_'+('Stairs' if 'Stair' in name else 'Structure'),loc,size,'stone')
    floor0=base+.08
    if shell:
        wallmat={'french':'limestone','italian':'warm_plaster','swiss':'wood','castle':'white','church':'plaster'}[style]
        solid('EX_'+id+'_Shell',(-w/2+wall/2,0,base+height/2),(wall,d,height),wallmat)
        solid('EX_'+id+'_Shell',(w/2-wall/2,0,base+height/2),(wall,d,height),wallmat)
        solid('EX_'+id+'_Shell',(0,d/2-wall/2,base+height/2),(w,wall,height),wallmat)
        opening=min(2.0,w*.4);side=(w-opening)/2;doorh=min(2.8,height-.2)
        for sg in (-1,1):solid('EX_'+id+'_Shell',(sg*(opening/2+side/2),-d/2+wall/2,base+height/2),(side,wall,height),wallmat)
        solid('EX_'+id+'_Shell',(0,-d/2+wall/2,base+doorh+(height-doorh)/2),(opening,wall,height-doorh),wallmat)
        # Door casing and two open leaves remain outside the clear aperture.
        for sg in (-1,1):
            T.box('EX_'+id+'_Doorframe',(sg*(opening/2+.10),-d/2-.06,base+1.4),(.13,.42,2.8),'wood')
            T.box('EX_'+id+'_OpenDoor',(sg*(opening/2+.015),-d/2-.52,base+1.37),(.075,.88,2.68),'dark_wood')
            T.box('EX_'+id+'_DoorPanels',(sg*(opening/2+.055),-d/2-.52,base+1.37),(.03,.65,2.35),'wood')
        T.box('EX_'+id+'_Doorframe',(0,-d/2-.06,base+2.82),(opening+.34,.4,.14),'wood')
        # Separate interior plaster/wood linings keep masonry on the exterior.
        finish='wood' if style=='swiss' else 'wallpaper' if style=='castle' else 'plaster'
        lining='IN_'+id+'_Wall_Finish'
        for sg in (-1,1):
            T.box(lining,(sg*(w/2-wall-.014),0,base+height/2),(.03,d-.60,height-.06),finish)
        T.box(lining,(0,d/2-wall-.014,base+height/2),(w-.60,.03,height-.06),finish)
        for sg in (-1,1):
            T.box(lining,(sg*(opening/2+side/2),-d/2+wall+.014,base+height/2),(side,.03,height-.06),finish)
        T.box(lining,(0,-d/2+wall+.014,base+doorh+(height-doorh)/2),(opening,.03,height-doorh),finish)
    stair_w=min(2.65,w*.30);stair_run=min(5.35,d*.48);right=w/2-.35;rear=d/2-.35;bottom_y=rear-stair_run
    levels=[];stair_landings=[];use_stairs=w>5 and d>6
    for lev in range(floors):
        floor=base+lev*fh+.08;levels.append(floor)
        mat='marble' if style in ('castle','church') else 'parquet'
        if lev==0 or floors==1 or not use_stairs:
            solid('IN_'+id+'_Floors',(0,0,floor-.08),(w-.25,d-.25,.16),mat)
        else:
            # L-shaped floor keeps the entire stair aperture empty.
            split=right-stair_w
            left_width=split+w/2-.05
            solid('IN_'+id+'_Floors',(-w/2+.05+left_width/2,0,floor-.08),(left_width,d-.25,.16),mat)
            front_depth=bottom_y+d/2-.12
            solid('IN_'+id+'_Floors',((split+right)/2,-d/2+.12+front_depth/2,floor-.08),(stair_w,front_depth,.16),mat)
        # Ceiling only closes the roof; intermediate floors remain accessible.
        if lev==floors-1:solid('IN_'+id+'_Ceiling',(0,0,base+height-.12),(w-.22,d-.22,.16),'ceiling')
        if lev<floors-1 and use_stairs:
            lane=(stair_w-.15)/2;run=stair_run-.9;start=bottom_y;end=start+run
            xa=right-stair_w+lane/2;xb=right-lane/2;half=fh/2
            for x,y0,y1,z0,z1 in [(xa,start,end,floor,floor+half),(xb,end,start,floor+half,floor+fh)]:
                # Display treads; collision uses a smooth inclined quad.
                count=max(7,int(half/.16))
                for k in range(count):
                    t=(k+.5)/count;y=y0+(y1-y0)*t;top=z0+(z1-z0)*(k+1)/count
                    T.box('IN_'+id+'_StairTreads',(x,y,top-.055),(lane,abs(y1-y0)/count+.015,.11),'wood')
                verts=[(x-lane/2,y0,z0),(x+lane/2,y0,z0),(x+lane/2,y1,z1),(x-lane/2,y1,z1)]
                face=(0,1,2,3) if y1>y0 else (3,2,1,0)
                T.poly('COL_'+id+'_Stairs',verts,[face],'stone')
                T.poly('IN_'+id+'_StairStringer',verts,[face],'dark_wood')
                for side in (-1,1):
                    xx=x+side*(lane/2-.055)
                    T.beam('IN_'+id+'_StairRails',(xx,y0,z0+.93),(xx,y1,z1+.93),.032,'wood',6)
                    for k in range(9):
                        t=k/8;yy=y0+(y1-y0)*t;zz=z0+(z1-z0)*t
                        T.beam('IN_'+id+'_StairRails',(xx,yy,zz),(xx,yy,zz+.93),.023,'metal',4)
            solid('IN_'+id+'_StairLanding',((xa+xb)/2,end+.38,floor+half-.065),(stair_w,.8,.13),'wood')
            stair_landings.append(T.point((xb,start-.25,floor+fh)))
        if w>=5:
            furnish_space(T,id+'_L'+str(lev),0,0,w-.7,d-.7,floor,style)
        else:furnish_space(T,id+'_L'+str(lev),0,0,w-.4,d-.4,floor,style)
        positions=[(0,0)] if w*d<110 else [(0,0),(-w*.29,0),(w*.29,0)]
        for lx,ly in positions:
            B.room_lights.append({'building':id,'position':T.point((lx,ly,floor+min(2.18,fh-.25))),'color':[1,.89,.76],'energy':1.7,'range':max(5,min(10,w*.65))})
            if lx or ly:
                T.beam('IN_'+id+'_Lighting',(lx,ly,floor+2.72),(lx,ly,floor+2.43),.023,'bronze',8)
                T.cyl('IN_'+id+'_Lighting',(lx,ly,floor+2.35),.29,.20,'gold',20,.18)
                T.cyl('IN_'+id+'_Lighting',(lx,ly,floor+2.245),.25,.018,'emissive',20)
        # Wall panel molding and a cornice add close-range construction detail.
        if shell and w>6:
            for sg in (-1,1):
                for zz in (.12,1.04,fh-.19):
                    T.box('IN_'+id+'_Moldings',(sg*(w/2-.335),0,floor+zz),(.075,d-.7,.06),'ceiling' if style!='swiss' else 'dark_wood')
                for yy in range(-int(d/2)+1,int(d/2),2):
                    T.box('IN_'+id+'_Moldings',(sg*(w/2-.333),yy,floor+.58),(.07,.045,.85),'ceiling' if style!='swiss' else 'dark_wood')
    # Small smooth threshold ramp rather than a tall step at the doorway.
    if shell and base<2:
        y=-d/2;run=max(.7,(base+.08)*3)
        vs=[(-1.05,y-run,.045),(1.05,y-run,.045),(1.05,y,floor0),(-1.05,y,floor0)]
        T.poly('EX_'+id+'_Threshold',vs,[(0,1,2,3)],'stone');T.poly('COL_'+id+'_Threshold',vs,[(0,1,2,3)],'stone')
    record={'id':id,'label':label,'center':(cx,cy,base+height/2),'size':(w,d,height),'front_angle':front_angle,'entrance':T.point((0,-d/2-1.5,max(.08,base+.08))),'inside':T.point((0,-d/2+1.5,floor0+.05)),'floor_levels':levels,'floors':floors,'style':style,'height':height,'base':base,'stair_landings':stair_landings,'access':'walk'}
    if floors>1 and not use_stairs:
        for lev in range(floors-1):
            low=T.point((-.25,-d/2+1.1,levels[lev]+.05));high=T.point((-.25,-d/2+1.1,levels[lev+1]+.05))
            add_landmark_access(B,id+'_up_'+str(lev),label+' · 上一层',low,high)
            add_landmark_access(B,id+'_down_'+str(lev),label+' · 下一层',T.point((.65,-d/2+1.8,levels[lev+1]+.05)),T.point((.65,-d/2+1.8,levels[lev]+.05)))
    B.buildings.append(record);return record

def add_landmark_access(B,id,label,source,target,kind='lift'):
    if not hasattr(B,'interactions'):B.interactions=[]
    rec={'id':id,'label':label,'source':tuple(source),'target':tuple(target),'kind':kind}
    B.interactions.append(rec);return rec

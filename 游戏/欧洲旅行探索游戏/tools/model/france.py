"""Paris: a detailed lattice tower, formal gardens and Haussmann facades."""
import math, random
from interiors import make_building, add_landmark_access

def build(B):
    cy=8
    profile=[(0,19.4,3.7),(4,16.8,3.35),(9,13.6,2.9),(14,11.1,2.5),(18,9.25,2.15),(25,7.05,1.65),(35,5.25,1.25),(48,3.5,.88),(64,2.25,.62),(79,1.42,.43),(88,1.14,.35)]
    def section(z):
        for j in range(len(profile)-1):
            a,b=profile[j],profile[j+1]
            if a[0]<=z<=b[0]:
                t=(z-a[0])/(b[0]-a[0]);return (a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t)
        return profile[-1][1:]
    # Four tapered lattice legs. Cross-members are mesh beams, never alpha cards.
    for sx in (-1,1):
        for sy in (-1,1):
            B.box('FR_Tower_Footings',(sx*19.4,cy+sy*19.4,.7),(6.6,6.6,1.4),'limestone')
            B.box('FR_Tower_Footings',(sx*19.4,cy+sy*19.4,1.5),(5.3,5.3,.4),'stone')
            levels=[1.5]+[3*i for i in range(1,30)]+[88]
            for j in range(len(levels)-1):
                za,zb=levels[j:j+2];ha,da=section(za);hb,db=section(zb)
                qa=[(sx*ha+ux*da/2,cy+sy*ha+uy*da/2,za) for ux,uy in ((-1,-1),(1,-1),(1,1),(-1,1))]
                qb=[(sx*hb+ux*db/2,cy+sy*hb+uy*db/2,zb) for ux,uy in ((-1,-1),(1,-1),(1,1),(-1,1))]
                r=.16 if za<35 else .085
                for k in range(4):
                    B.beam('FR_Tower_Primary',qa[k],qb[k],r,'bronze',6)
                    B.beam('FR_Tower_Lattice',qa[k],qb[(k+1)%4],r*.47,'bronze',4)
                    B.beam('FR_Tower_Lattice',qb[k],qa[(k+1)%4],r*.47,'bronze',4)
                    B.beam('FR_Tower_Rings',qa[k],qa[(k+1)%4],r*.65,'bronze',4)
            # Base lift guide and capsule.
            ha,_=section(2);hb,_=section(18)
            B.beam('FR_Lift_Tracks',(sx*ha,cy+sy*ha,2),(sx*hb,cy+sy*hb,18),.17,'metal')
            hz,_=section(9)
            B.box('FR_Lift_Cabins',(sx*hz,cy+sy*hz,9),(1.6,1.6,2.7),'bronze')
            B.box('FR_Lift_Cabins',(sx*hz,cy+sy*hz-1,9.5),(1.15,.12,1.4),'glass')
    # Four monumental curved arches under first deck, made of open steel ribs.
    for side in range(4):
        ang=side*math.pi/2
        def tr(x,y,z): return (x*math.cos(ang)-y*math.sin(ang),cy+x*math.sin(ang)+y*math.cos(ang),z)
        pts=[]
        for i in range(33):
            x=-17+34*i/32;z=3+13*math.sqrt(max(0,1-(x/17)**2));pts.append((x,16.4,z))
        for i in range(32):
            for dz in (0,.7):B.beam('FR_Tower_Arches',tr(pts[i][0],pts[i][1],pts[i][2]+dz),tr(pts[i+1][0],pts[i+1][1],pts[i+1][2]+dz),.13,'bronze',5)
            B.beam('FR_Tower_Arches',tr(*pts[i]),tr(pts[i+1][0],pts[i+1][1],pts[i+1][2]+.7),.045,'bronze')
    # Upper tower complete face bracing across the four converging legs.
    levels=list(range(36,88,3))+[88]
    for j in range(len(levels)-1):
        za,zb=levels[j:j+2];ha,_=section(za);hb,_=section(zb)
        pa=[(-ha,cy-ha,za),(ha,cy-ha,za),(ha,cy+ha,za),(-ha,cy+ha,za)]
        pb=[(-hb,cy-hb,zb),(hb,cy-hb,zb),(hb,cy+hb,zb),(-hb,cy+hb,zb)]
        for k in range(4):
            B.beam('FR_Tower_Upper_Bracing',pa[k],pa[(k+1)%4],.09,'bronze')
            B.beam('FR_Tower_Upper_Bracing',pa[k],pb[(k+1)%4],.075,'bronze')
            B.beam('FR_Tower_Upper_Bracing',pb[k],pa[(k+1)%4],.075,'bronze')
    for z,half,band in [(18.1,11.2,1.8),(35.2,6.6,1.35),(88.7,2.9,.7)]:
        for rot in (0,math.pi/2):
            for s in (-1,1):
                if rot==0: loc=(0,cy+s*(half-band/2),z);size=(half*2,band,.65)
                else:loc=(s*(half-band/2),cy,z);size=(band,half*2-band*2,.65)
                B.box('FR_Observation_Decks',loc,size,'bronze')
        # railings around each terrace edge
        corners=[(-half,cy-half),(half,cy-half),(half,cy+half),(-half,cy+half)]
        for k in range(4):
            a,c=corners[k],corners[(k+1)%4]
            for h in (.35,1.35): B.beam('FR_Deck_Railings',(*a,z+h),(*c,z+h),.05,'metal')
            count=max(4,int(half*2/.65))
            for i in range(count+1):
                t=i/count;x=a[0]*(1-t)+c[0]*t;y=a[1]*(1-t)+c[1]*t
                B.beam('FR_Deck_Railings',(x,y,z+.35),(x,y,z+1.35),.035,'metal')
        # The observation floor is a ring. Its inner rail keeps visitors on it.
        inner=half-band
        inner_corners=[(-inner,cy-inner),(inner,cy-inner),(inner,cy+inner),(-inner,cy+inner)]
        for k in range(4):
            a,c=inner_corners[k],inner_corners[(k+1)%4]
            B.beam('FR_Inner_Deck_Railings',(*a,z+1.35),(*c,z+1.35),.045,'metal',6)
            count=max(4,int(inner*2/.7))
            for j in range(count+1):
                t=j/count;x=a[0]*(1-t)+c[0]*t;y=a[1]*(1-t)+c[1]*t
                B.beam('FR_Inner_Deck_Railings',(x,y,z+.34),(x,y,z+1.35),.03,'metal')
        if z<40:
            for sx in (-1,1):
                B.box('FR_Deck_Pavilions',(sx*(half-1.4),cy,z+1.6),(1.25,half*1.15,1.8),'glass')
                for y in range(-int(half*.57),int(half*.57)+1):
                    B.box('FR_Deck_Pavilions',(sx*(half-2.07),cy+y,z+1.6),(.08,.08,1.85),'bronze')
    B.cyl('FR_Summit',(0,cy,90.8),1.75,3,'bronze',16,radius_top=1.2)
    B.cyl('FR_Summit',(0,cy,93.2),1.55,1.8,'metal',16,radius_top=.25)
    B.cyl('FR_Antenna',(0,cy,98),.12,9,'metal',10,radius_top=.04)
    for z in (95,98,100):B.cyl('FR_Antenna',(0,cy,z),.32,.12,'metal',10)
    # Both destinations lie over real surfaces: esplanade and first-deck ring.
    lift_source=(3.0,-12.0,.18)
    lift_landing=(0.0,-2.3,18.55)
    add_landmark_access(B,'fr_tower_lift','埃菲尔铁塔一层观景台',
                        source=lift_source,target=lift_landing,kind='lift')
    add_landmark_access(B,'fr_tower_lift_return','乘升降机返回铁塔广场',
                        source=lift_landing,target=lift_source,kind='lift')
    for x,y,z in ((4.4,-12.0,.12),(1.5,-2.3,18.425)):
        B.box('FR_Lift_Information',(x,y,z+.55),(.38,.30,1.10),'bronze')
        B.box('FR_Lift_Information',(x,y-.17,z+.92),(.29,.035,.32),'emissive')
    # Stone esplanade and formal garden, maintained clear walking axes.
    B.box('FR_Esplanade',(0,8,.06),(53,49,.12),'paving')
    B.box('FR_Main_Walk',(0,-28,.09),(9,30,.18),'gravel')
    for sx in (-1,1):
        B.box('FR_Garden_Paths',(sx*34,-19,.05),(4,55,.1),'gravel')
        for y in (-25,-9):
            B.box('FR_Parterres',(sx*19,y,.22),(19,10,.4),'limestone')
            B.box('FR_Parterres',(sx*19,y,.43),(18.2,9.2,.12),'grass')
            for dx in (-8.2,8.2):B.box('FR_Hedges',(sx*19+dx,y,.9),(1,8.2,1.1),'foliage_dark')
            for dy in (-3.7,3.7):B.box('FR_Hedges',(sx*19,y+dy,.9),(17.1,1,1.1),'foliage_dark')
    B.cyl('FR_Fountain',(0,-29,.45),5,.9,'limestone',48)
    B.cyl('FR_Fountain',(0,-29,.94),4.5,.1,'water',48)
    B.cyl('FR_Fountain',(0,-29,1.3),.7,1,'limestone',16)
    B.cyl('FR_Fountain',(0,-29,1.85),1.8,.24,'limestone',32,radius_top=2.1)
    B.cyl('FR_Fountain',(0,-29,2.35),.28,.8,'bronze',12)
    # Seine and embankments in the front of the district.
    B.box('FR_Seine',(0,-52,-.03),(139,13,.14),'water')
    for y in (-44.5,-59):
        for left,right in ((-70,-46.2),(-37.8,70)):
            B.box('FR_Quay',((left+right)/2,y,.45),(right-left,1.5,1.3),'stone')
    B.box('FR_Riverside_Walk',(0,-41.5,.13),(140,4,.26),'paving')
    for x in range(-67,68,3):
        if abs(x+42)<4.4:continue
        B.box('FR_Quay_Railing',(x,-44.1,1.32),(.13,.13,1.25),'metal')
    for left,right in ((-69,-46.2),(-37.8,69)):
        B.beam('FR_Quay_Railing',(left,-44.1,1.9),(right,-44.1,1.9),.07,'metal')
    # Bridge across the river, shallow usable ramp and balustrade.
    B.box('FR_Seine_Bridge',(-42,-51.3,1.1),(8,13.4,.65),'limestone')
    for x in (-45.8,-38.2):
        B.box('FR_Bridge_Parapet',(x,-51.3,2.38),(.4,13.4,.30),'limestone')
        for k in range(14):
            y=-57.8+k
            B.box('FR_Bridge_Parapet',(x,y,1.98),(.25,.25,1.10),'limestone')
    for ya,yb,za,zb in ((-60,-58,.12,1.425),(-44.6,-40.8,1.425,.26)):
        B.poly('FR_Seine_Bridge',[(-46,ya,za),(-38,ya,za),(-38,yb,zb),(-46,yb,zb)],[(0,1,2,3)],'paving')
        for x in (-45.8,-38.2):
            margin=.10/(yb-ya)
            B.beam('FR_Bridge_Parapet',(x,ya+.10,za+(zb-za)*margin+1.10),
                   (x,yb-.10,zb-(zb-za)*margin+1.10),.07,'metal',6)
            for k in range(5):
                t=margin+(1-2*margin)*k/4;y=ya+(yb-ya)*t;z=za+(zb-za)*t
                B.beam('FR_Bridge_Parapet',(x,y,z+.03),(x,y,z+1.10),.045,'metal',6)
    # Paris limestone facades, mansards, dormers, balconies and chimneys.
    street_labels=('巴黎旅行书店','塞纳河咖啡馆','巴黎艺术画廊','法式精品旅馆','巴黎花艺工坊','巴黎建筑展馆')
    street_buildings=[]
    def block(cx,by,w,d,h,index):
        base=.18
        h=max(h,base+13.6)
        record=make_building(B,f'fr_haussmann_{index+1:02d}',street_labels[index],
                             cx,by,w,d,base,13.6,'french',floors=4,front_angle=0,shell=True)
        street_buildings.append(record)
        front=by-d/2
        # Perimeter strips keep the interior and stairwell free of old solid bands.
        def perimeter(name,z,thickness,overhang,mat,door_gap=False):
            depth=.22
            B.box(name,(cx,by+d/2+overhang/2,z),(w+overhang*2,depth+overhang,thickness),mat)
            for side in (-1,1):
                B.box(name,(cx+side*(w/2+overhang/2),by,z),(depth+overhang,d,thickness),mat)
            if door_gap:
                wing=(w+overhang*2-2.2)/2
                for side in (-1,1):
                    B.box(name,(cx+side*(1.1+wing/2),front-overhang/2,z),
                          (wing,depth+overhang,thickness),mat)
            else:
                B.box(name,(cx,front-overhang/2,z),(w+overhang*2,depth+overhang,thickness),mat)
        perimeter('FR_Haussmann_Plinth',.40,.8,.15,'stone',True)
        for z in (3.4,6.9,10.4,h):
            perimeter('FR_Haussmann_Cornice',z,.24,.25,'limestone')
        if h>base+13.6+.01:
            perimeter('FR_Haussmann_Stone',(base+13.6+h)/2,h-base-13.6,0,'limestone')
        # Open stone portal: clear width 2.0 m, clear height at least 2.8 m.
        for side in (-1,1):
            B.box('FR_Entrance_Portals',(cx+side*1.15,front-.15,1.67),(.26,.38,2.98),'limestone')
            B.box('FR_Entrance_Portals',(cx+side*1.15,front-.20,3.08),(.39,.46,.18),'limestone')
        B.box('FR_Entrance_Portals',(cx,front-.18,3.23),(2.68,.45,.28),'limestone')
        B.box('FR_Entrance_Plaques',(cx+1.70,front-.25,1.75),(.43,.06,.55),'bronze')
        x1,x2=cx-w/2-.4,cx+w/2+.4;y1,y2=by-d/2-.4,by+d/2+.4
        vs=[(x1,y1,h),(x2,y1,h),(x2,y2,h),(x1,y2,h),(x1+1.8,y1+1.7,h+3.3),(x2-1.8,y1+1.7,h+3.3),(x2-1.8,y2-1.7,h+3.3),(x1+1.8,y2-1.7,h+3.3)]
        B.poly('FR_Mansard_Roofs',vs,[(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)],'slate')
        n=max(3,int(w/2.7))
        for k in range(n):
            x=cx-w/2+(k+.5)*w/n
            for level in range(4):
                z=1.8+3.4*level;front=by-d/2-.08
                if level==0 and abs(x-cx)<1.80:
                    continue
                B.box('FR_Window_Stone_Frames',(x,front,z),(1.35,.22,2.28),'plaster')
                B.box('FR_Window_Glazing',(x,front-.14,z),(1.07,.08,1.98),'glass')
                B.box('FR_Window_Mullions',(x,front-.21,z),(.075,.06,1.98),'white')
                B.box('FR_Window_Mullions',(x,front-.21,z+.22),(1.1,.06,.075),'white')
                B.box('FR_Window_Sills',(x,front-.15,z-1.15),(1.6,.5,.16),'limestone')
                if level in (1,3):
                    B.box('FR_Balconies',(x,front-.42,z-.93),(1.65,.83,.18),'limestone')
                    for dx in (-.7,-.35,0,.35,.7):B.beam('FR_Balcony_Ironwork',(x+dx,front-.8,z-.87),(x+dx,front-.8,z-.13),.025,'metal')
                    B.beam('FR_Balcony_Ironwork',(x-.8,front-.8,z-.1),(x+.8,front-.8,z-.1),.035,'metal')
            # dormers
            B.box('FR_Dormers',(x,by-d/2+.55,h+1.2),(1.7,1.6,1.75),'limestone')
            B.box('FR_Dormer_Windows',(x,by-d/2-.29,h+1.3),(1.1,.06,1.35),'glass')
            B.roof('FR_Dormer_Roofs',(x,by-d/2+.5,h+2.1),2,1.9,.65,'slate')
        for dx in (-w*.3,w*.3):
            B.box('FR_Chimneys',(cx+dx,by,h+3.5),(1.5,.9,2),'brick')
            for xoff in (-.4,0,.4):B.cyl('FR_Chimney_Pots',(cx+dx+xoff,by,h+4.65),.13,.4,'terracotta',8)
        B.box('FR_Shop_Awnings',(cx,by-d/2-.8,3.38),(w*.82,1.4,.15),'dark_wood')
    for index,(x,w,h) in enumerate([(-55,20,13.7),(-32,20,14.6),(-9,20,13.8),(15,22,15),(41,21,13.9),(61,15,14.5)]):
        block(x,51,w,13,h,index)
    B.box('FR_Boulevard',(0,39,.02),(140,8,.05),'asphalt')
    for x in range(-66,67,7):B.box('FR_Road_Markings',(x,39,.055),(3.3,.13,.02),'white')
    for sx in (-1,1):
        for y in (-30,-18,-5,9,24):B.tree('FR_Plane_Trees',sx*45,y,0,10+(y%3))
    for x in range(-59,65,17):B.tree('FR_Boulevard_Trees',x,33,0,8)
    # Street lamps and benches, consistent meter-scale street furniture.
    for x,y in [(s*31,y) for s in (-1,1) for y in (-33,-18,0,22)]+[(x,-40) for x in (-58,-20,15,48)]:
        B.cyl('FR_Lamp_Posts',(x,y,2.4),.08,4.8,'metal',10)
        B.cyl('FR_Lamp_Posts',(x,y,.2),.22,.4,'metal',10)
        B.box('FR_Lamp_Lanterns',(x,y,4.8),(.5,.5,.7),'gold')
        B.roof('FR_Lamp_Caps',(x,y,5.18),.75,.75,.3,'metal')
        for i in (-1,0,1): B.box('FR_Bench_Wood',(x+2,y+i*.2,.48),(2,.15,.12),'wood')
        B.box('FR_Bench_Wood',(x+2,y+.3,.85),(2,.12,.55),'wood')
        for dx in (-.7,.7):B.box('FR_Bench_Feet',(x+2+dx,y,.23),(.08,.7,.46),'metal')
    return {'landmark':'Eiffel Tower / Paris','approximate_scale':'Tower approx. 0.31 of full-size height; adjacent streets composed for gameplay','spawn':[0,-37,1.7],
            'description':'细密钢桁架铁塔、可乘升降机到达的一层观景环廊、六栋拥有真实门洞和四层室内的奥斯曼式街屋、法式花园与塞纳河畔。',
            'street_building_count':len(street_buildings),'street_building_ids':[f'fr_haussmann_{i+1:02d}' for i in range(6)],
            'street_building_labels':list(street_labels),'interior_style':'french',
            'observation_access':['fr_tower_lift','fr_tower_lift_return']}

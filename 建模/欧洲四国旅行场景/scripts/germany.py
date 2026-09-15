"""Neuschwanstein-inspired limestone castle and a continuous forest approach.

Architectural interpretation, not a measured reconstruction.  The official
palace photographs informed the long Palas, pale cylindrical towers, steep
slate roofs and the contrasting red gatehouse.
Reference: https://www.neuschwanstein.de/englisch/palace/
All dimensions are metres in the Germany region's local coordinate system.
"""
import math
import random


def build(B):
    rng = random.Random(1876)
    tau = math.tau
    # A graded approach deliberately curls around the front/east of the hill.
    route = [(-17, -55, .08), (7, -49, .7), (30, -44, 2.5),
             (43, -34, 5), (45, -20, 7.5), (37, -16, 9.2),
             (31, -24, 10.4), (23, -31, 11.2), (12, -31, 11.8),
             (8, -27, 12), (8, -19, 12)]
    # Catmull-Rom centerline, also used to grade the underlying terrain.
    path = []
    for i in range(len(route)-1):
        a, b = route[max(0, i-1)], route[i]
        c, d = route[i+1], route[min(len(route)-1, i+2)]
        for j in range(12):
            t = j / 12
            p = tuple(.5*((2*b[k])+(-a[k]+c[k])*t +
                         (2*a[k]-5*b[k]+4*c[k]-d[k])*t*t +
                         (-a[k]+3*b[k]-3*c[k]+d[k])*t*t*t)
                      for k in range(3))
            path.append(p)
    path.append(route[-1])

    def nearest_path(x, y):
        best = (1e20, 0.0)
        for a, b in zip(path, path[1:]):
            vx, vy = b[0]-a[0], b[1]-a[1]
            t = max(0., min(1., ((x-a[0])*vx+(y-a[1])*vy)/(vx*vx+vy*vy)))
            px, py = a[0]+vx*t, a[1]+vy*t
            dd = (x-px)**2+(y-py)**2
            if dd < best[0]:
                best = (dd, a[2]+(b[2]-a[2])*t)
        return math.sqrt(best[0]), best[1]

    def terrain(x, y):
        # Rounded rectangular crown gives every castle foundation solid support.
        r = ((abs(x)/34.)**4 + (abs(y-6)/34.)**4)**.25
        if r <= 1:
            z = 12.
        elif r < 1.72:
            t = (r-1)/.72
            z = 12*(1-t)**1.18
            z += math.sin(t*math.pi)**2*(.7*math.sin(x*.37+y*.23)+.3*math.cos(y*.71))
        else:
            z = .03
        z = max(.03, z)
        distance, pz = nearest_path(x, y)
        if distance < 6.4:
            weight = 1.0 if distance < 3.7 else (6.4-distance)/2.7
            weight = weight*weight*(3-2*weight)
            z = z*(1-weight)+max(.04, pz-.06)*weight
        return max(.03, z)

    # Dense enough to retain coherent slopes and cliff strata in close views.
    step = 1.8
    xs = [-66+i*step for i in range(74)]
    ys = [-58+i*step for i in range(65)]
    terrain_verts = [(x,y,terrain(x,y)) for y in ys for x in xs]
    terrain_faces = {'grass': [], 'rock': [], 'rock_dark': []}
    nx = len(xs)
    for j in range(len(ys)-1):
        for i in range(nx-1):
            a=j*nx+i; b=a+1; c=a+nx; d=c+1
            for f in ((a,b,d),(a,d,c)):
                vv=[terrain_verts[k] for k in f]
                dz=max(v[2] for v in vv)-min(v[2] for v in vv)
                mat='rock' if dz>1.05 and min(v[2] for v in vv)>1.4 else 'grass'
                if mat=='rock' and (i+3*j)%7==0: mat='rock_dark'
                terrain_faces[mat].append(f)
    for mat, faces in terrain_faces.items():
        B.poly('DE_Hill_Terrain',terrain_verts,faces,mat)

    def actual_height(x, y):
        """Interpolate the exact terrain triangle, including its diagonal."""
        i=max(0,min(nx-2,int((x-xs[0])/step)))
        j=max(0,min(len(ys)-2,int((y-ys[0])/step)))
        u=(x-xs[i])/step; v=(y-ys[j])/step; a=j*nx+i
        za=terrain_verts[a][2]; zb=terrain_verts[a+1][2]
        zc=terrain_verts[a+nx][2]; zd=terrain_verts[a+nx+1][2]
        return za+(zb-za)*u+(zd-zb)*v if u>=v else za+(zd-zc)*u+(zc-za)*v

    road=[]; road_width=4.8; cross_sections=8
    for i,p in enumerate(path):
        a=path[max(0,i-1)]; c=path[min(len(path)-1,i+1)]
        dx=c[0]-a[0];dy=c[1]-a[1]; length=math.hypot(dx,dy)
        normal=(-dy/length,dx/length)
        for j in range(cross_sections+1):
            side=(j/cross_sections-.5)*road_width
            x=p[0]+normal[0]*side; y=p[1]+normal[1]*side
            road.append((x,y,actual_height(x,y)+.16))
    road_faces=[]
    for i in range(len(path)-1):
        for j in range(cross_sections):
            a=i*(cross_sections+1)+j;b=a+cross_sections+1
            road_faces.extend([(a,a+1,b+1),(a,b+1,b)])
    B.poly('DE_Arrival_Path',road,road_faces,'gravel')
    # Small edge stones and intermittent timber safety rails on the steep bend.
    for i in range(8,len(path)-12,3):
        p=path[i]; a=path[i-1];c=path[i+1]
        dx=c[0]-a[0];dy=c[1]-a[1]; length=math.hypot(dx,dy)
        nxp,nyp=-dy/length,dx/length
        for side in (-1,1):
            x=p[0]+side*nxp*2.6;y=p[1]+side*nyp*2.6
            B.box('DE_Path_Edges',(x,y,actual_height(x,y)+.16),(.48,.24,.25),'stone',math.atan2(dy,dx))
        if 31<i<91:
            x=p[0]-nxp*3.0;y=p[1]-nyp*3.0;z=actual_height(x,y)
            B.cyl('DE_Path_Railing',(x,y,z+.64),.095,1.28,'dark_wood',8)
            q=path[i+3]; q0=path[i+2];q1=path[i+4]
            qdx=q1[0]-q0[0];qdy=q1[1]-q0[1];ql=math.hypot(qdx,qdy)
            xx=q[0]+qdy/ql*3;yy=q[1]-qdx/ql*3;zz=actual_height(xx,yy)
            for h in (.55,1.06): B.beam('DE_Path_Railing',(x,y,z+h),(xx,yy,zz+h),.06,'wood',6)

    # Paved, open-air courtyard with a solid terrace below the architecture.
    B.box('DE_Foundations',(0,6,11.8),(56,58,.7),'stone')
    B.box('DE_Courtyard',(0,6,12.17),(55.5,57.5,.10),'paving')
    for x in (-28.15,28.15):
        B.box('DE_Retaining_Walls',(x,6,10.8),(.8,59,3),'stone')
        B.box('DE_Retaining_Walls',(x,6,12.42),(1.0,59,.24),'limestone')
    B.box('DE_Retaining_Walls',(0,35.2,10.8),(56,1,3),'stone')
    for cx,w in ((-12.5,31),(20.25,15.5)):
        B.box('DE_Retaining_Walls',(cx,-23.2,10.75),(w,.8,3),'stone')

    def point(origin,u,d,z,rot=0):
        c,s=math.cos(rot),math.sin(rot)
        return (origin[0]+u*c-d*s,origin[1]+u*s+d*c,z)

    def local_box(name,origin,u,d,z,w,dep,h,mat,rot):
        B.box(name,point(origin,u,d,z,rot),(w,dep,h),mat,rot)

    def extrude(name,origin,profile,front,back,mat,rot):
        n=len(profile)
        vs=[point(origin,u,d,z,rot) for d in (front,back) for u,z in profile]
        fs=[tuple(reversed(range(n))),tuple(range(n,2*n))]
        fs += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
        B.poly(name,vs,fs,mat)

    def aperture(origin,u,base,width,height,rot=0,glazed=True,trim='limestone',segments=8,glazing_depth=.27):
        """Arched glass sits behind a real opening, with visible deep reveals."""
        r=width/2; spring=base+height-r
        # One continuous archivolt avoids internal faces between voussoirs.
        vs=[]; fs=[]; thickness=.13
        for i in range(segments+1):
            a=i*math.pi/segments
            for dep in (-.21,.03):
                for rad in (r,r+thickness):
                    vs.append(point(origin,u+rad*math.cos(a),dep,spring+rad*math.sin(a),rot))
        for i in range(segments):
            a=i*4; b=a+4
            fs.extend([(a,b,b+1,a+1),(a+2,a+3,b+3,b+2),
                       (a,a+2,b+2,b),(a+1,b+1,b+3,a+3)])
        fs.extend([(0,1,3,2),(segments*4,segments*4+2,segments*4+3,segments*4+1)])
        B.poly('DE_Window_Stonework',vs,fs,trim)
        for side in (-1,1):
            local_box('DE_Window_Stonework',origin,u+side*(r+thickness/2),-.09,(base+spring)/2,thickness,.24,spring-base,trim,rot)
        if glazed:
            profile=[(u-r,base),(u+r,base),(u+r,spring)]
            profile += [(u+r*math.cos(i*math.pi/segments),spring+r*math.sin(i*math.pi/segments)) for i in range(1,segments+1)]
            # Exterior glass needs a single front surface; an opaque backface
            # and the four hidden perimeter sides add no visible information.
            B.poly('DE_Window_Glass',[point(origin,px,glazing_depth,pz,rot) for px,pz in profile],[tuple(range(len(profile)))],'glass')
            # Dark reveals and lead dividers give depth in oblique views.
            for side in (-1,1):
                x=u+side*(r-.025)
                B.poly('DE_Window_Details',[point(origin,x,-.10,base,rot),point(origin,x,.27,base,rot),point(origin,x,.27,spring,rot),point(origin,x,-.10,spring,rot)],[(0,1,2,3)],'dark_wood')
            local_box('DE_Window_Details',origin,u,.035,base+height*.44,.075,.08,height*.88,'metal',rot)
            for h in (.55,):
                local_box('DE_Window_Details',origin,u,.035,base+height*h,width,.08,.06,'metal',rot)
            local_box('DE_Window_Stonework',origin,u,-.14,base-.10,width+.40,.49,.20,trim,rot)

    def wall_cell(origin,u,bottom,top,cell_width,opening_width,window_bottom,window_height,rot,mat='white',depth=.55,glazed=True):
        """Build a masonry cell around an empty round-headed aperture."""
        r=opening_width/2; spring=window_bottom+window_height-r
        pier=(cell_width-opening_width)/2
        for side in (-1,1):
            local_box('DE_Palace_Walls',origin,u+side*(r+pier/2),depth/2,(bottom+top)/2,pier,depth,top-bottom,mat,rot)
        if window_bottom>bottom:
            local_box('DE_Palace_Walls',origin,u,depth/2,(bottom+window_bottom)/2,opening_width,depth,window_bottom-bottom,mat,rot)
        for i in range(8):
            a=i*math.pi/8;b=(i+1)*math.pi/8
            x1=u+r*math.cos(a);x2=u+r*math.cos(b)
            z1=spring+r*math.sin(a);z2=spring+r*math.sin(b)
            extrude('DE_Palace_Walls',origin,[(x2,z2),(x1,z1),(x1,top),(x2,top)],0,depth,mat,rot)
        aperture(origin,u,window_bottom,opening_width,window_height,rot,glazed)

    def facade(origin,width,base,storeys,bays,floor_height,rot):
        bay=width/bays
        for row in range(storeys):
            bottom=base+row*floor_height; top=bottom+floor_height
            for col in range(bays):
                u=-width/2+(col+.5)*bay
                wh=3.1 if floor_height<6 else 3.45
                wall_cell(origin,u,bottom,top,bay,1.33 if bay<3.4 else 1.55,bottom+1.05,wh,rot)
            local_box('DE_Palace_Cornices',origin,0,-.12,top-.18,width+.18,.38,.22,'limestone',rot)
        # Corner rustication is shallow and alternating, like dressed quoins.
        top=base+storeys*floor_height
        for side in (-1,1):
            for j in range(int((top-base)/.82)):
                local_box('DE_Palace_Quoins',origin,side*(width/2-.26),-.09,base+.42+j*.82,.72 if j%2 else .98,.17,.38,'limestone',rot)

    def palace(cx,cy,w,d,base,storeys,bays_w,bays_d,fh,roof_h):
        eave=base+storeys*fh
        facade((cx,cy-d/2),w,base,storeys,bays_w,fh,0)
        facade((cx,cy+d/2),w,base,storeys,bays_w,fh,math.pi)
        facade((cx+w/2,cy),d,base,storeys,bays_d,fh,math.pi/2)
        facade((cx-w/2,cy),d,base,storeys,bays_d,fh,-math.pi/2)
        B.box('DE_Foundations',(cx,cy,base+.35),(w+.6,d+.6,.7),'stone')
        B.box('DE_Palace_Cornices',(cx,cy,eave+.07),(w+.8,d+.8,.44),'limestone')
        B.roof('DE_Slate_Roofs',(cx,cy,eave+.28),w+1.1,d+1.1,roof_h,'slate')
        B.beam('DE_Roof_Metalwork',(cx,cy-d/2-.6,eave+roof_h+.32),(cx,cy+d/2+.6,eave+roof_h+.32),.10,'metal',8)
        # Ridge fencing and dormers are deliberately thin in silhouette.
        for yy in range(int(cy-d/2)+2,int(cy+d/2),2):
            B.beam('DE_Roof_Metalwork',(cx,yy,eave+roof_h+.32),(cx,yy,eave+roof_h+.95),.045,'metal',5)
        for side in (-1,1):
            for k in range(max(2,int(d/6))):
                yy=cy-d/2+3+k*(d-6)/max(1,int(d/6)-1)
                xx=cx+side*w*.31; zz=eave+roof_h*(1-(w*.62)/(w+1.1))+.3
                B.box('DE_Roof_Dormers',(xx,yy,zz+.72),(1.6,1.9,1.7),'white')
                B.roof('DE_Slate_Roofs',(xx,yy,zz+1.56),1.95,2.2,1.55,'slate')
                # Dormers on this roof face sideways, parallel to its slope.
                ori=(xx+side*.82,yy)
                aperture(ori,0,zz+.24,.78,1.13,math.pi/2 if side>0 else -math.pi/2,glazing_depth=-.015)
        # Stepped, limestone-edged gables interrupt the long slate silhouette.
        for side in (-1,1):
            yy=cy+side*(d/2+.17)
            extrude('DE_Palace_Gables',(cx,yy),[(-w/2,eave),(w/2,eave),(0,eave+roof_h+.35)],-.15,.15,'white',0)
            for sg in (-1,1):
                for k in range(6):
                    xx=cx+sg*(w/2)*(1-(k+.5)/6)
                    zz=eave+roof_h*(k+1)/6
                    B.box('DE_Palace_Gables',(xx,yy,zz+.10),(w/12+.15,.60,.35),'limestone')
            aperture((cx,yy+side*.19),0,eave+1.0,1.32,2.6,0 if side<0 else math.pi,glazing_depth=-.015)
            aperture((cx,yy+side*.19),0,eave+5.1,.78,1.7,0 if side<0 else math.pi,glazing_depth=-.015)
        for side in (-1,1):
            x=cx+side*(w/2+.56)
            B.beam('DE_Roof_Metalwork',(x,cy-d/2-.5,eave+.33),(x,cy+d/2+.5,eave+.33),.105,'metal',8)
            B.beam('DE_Roof_Metalwork',(x,cy-d/2+.22,base+.55),(x,cy-d/2+.22,eave+.30),.083,'metal',8)

    palace(-15,14,19,35,12.23,5,5,9,5.6,10.1)
    palace(19.7,7.0,9.5,29,12.23,3,3,7,6.5,7.2)

    def tower(cx,cy,r,base,top,spire,slender=False):
        n=24
        B.cyl('DE_Tower_Masonry',(cx,cy,(base+top)/2),r,top-base,'white',n)
        B.cyl('DE_Tower_Masonry',(cx,cy,base+.5),r+.38,1,'limestone',n)
        for z in (base+3.6,base+9.2,base+14.8,base+20.4,top-1.1,top-.25):
            if z<top:
                B.cyl('DE_Tower_Cornices',(cx,cy,z),r+.13,.18,'limestone',n)
        for row in range(max(1,int((top-base-3)/5.6))):
            z=base+3.0+row*5.6
            if z+3>top-.8: continue
            for j in range(6 if r>2.6 else 4):
                a=j*tau/(6 if r>2.6 else 4)+math.pi/8
                rot=a+math.pi/2
                # Mounted glass is just forward of the tower skin; its stone
                # archivolts and projecting sill create the recessed reading.
                ori=(cx+math.cos(a)*(r+.34),cy+math.sin(a)*(r+.34))
                aperture(ori,0,z,.78 if slender else 1.06,2.45,rot)
        # Corbel-supported roof gallery and polygonal steep pointed cap.
        for j in range(n):
            a=j*tau/n
            B.box('DE_Tower_Cornices',(cx+math.cos(a)*(r+.12),cy+math.sin(a)*(r+.12),top-.58),(.22,.48,.60),'limestone',a)
        B.cyl('DE_Slate_Roofs',(cx,cy,top+spire/2),r+.55,spire,'slate',n,.025)
        B.cyl('DE_Tower_Cornices',(cx,cy,top+.04),r+.60,.20,'metal',n)
        # Seam ribs describe sheet-slate segments without a dense roof mesh.
        for j in range(12):
            a=j*tau/12
            B.beam('DE_Roof_Metalwork',(cx+math.cos(a)*(r+.56),cy+math.sin(a)*(r+.56),top+.13),(cx,cy,top+spire),.025,'metal',5)
        B.beam('DE_Roof_Metalwork',(cx,cy,top+spire-.05),(cx,cy,top+spire+1.65),.055,'metal',7)
        B.cyl('DE_Roof_Metalwork',(cx,cy,top+spire+.72),.16,.31,'gold',10,.03)

    tower(-23.3,29,4.1,12.23,49.4,12.5)
    tower(-24.2,-2.9,3.3,12.23,42.8,10.2)
    tower(-6.0,29.0,3.1,12.23,45.7,10.4)
    tower(23.6,21.5,3.35,12.23,46.0,11.7)
    tower(15.1,-6.8,2.0,12.23,35.5,8.3,True)

    # Squared keep beside the Palas with smaller corner turrets.
    kx,ky=-14.4,-7.8
    B.box('DE_Tower_Masonry',(kx,ky,29.8),(9.4,8.4,35.15),'white')
    for z in (17,22.6,28.2,33.8,39.4,46.7):
        B.box('DE_Tower_Cornices',(kx,ky,z),(9.7,8.7,.23),'limestone')
    for side in (-1,1):
        ori=(kx,ky+side*4.29); rot=0 if side<0 else math.pi
        for z in (16.1,21.7,27.3,32.9,38.5,43.2):
            for u in (-2.6,0,2.6): aperture(ori,u,z,1.12,2.8,rot,glazing_depth=-.015)
    # A hipped pyramidal cap is distinct from the long palace roof.
    zz=47.6
    B.poly('DE_Slate_Roofs',[(kx-5.1,ky-4.6,zz),(kx+5.1,ky-4.6,zz),(kx+5.1,ky+4.6,zz),(kx-5.1,ky+4.6,zz),(kx,ky,55.0)],[(0,1,4),(1,2,4),(2,3,4),(3,0,4),(3,2,1,0)],'slate')
    for dx in (-4.55,4.55):
        for dy in (-4.1,4.1): tower(kx+dx,ky+dy,.73,43.5,49.1,3.4,True)

    # East-facing oriel on the Palas, supported by tapered stone corbels.
    B.box('DE_Balconies',(-4.55,9.5,29.4),(2.8,5.6,10.8),'white')
    for z in (24,29,34.7):
        B.box('DE_Balconies',(-4.4,9.5,z),(3.1,6,.27),'limestone')
    for yy in (7.65,9.5,11.35):
        for z in (25.0,30.1): aperture((-3.06,yy),0,z,1.07,3.0,math.pi/2,glazing_depth=-.015)
        B.beam('DE_Balconies',(-5.5,yy,21.7),(-3.2,yy,24.0),.28,'limestone',4)
    B.roof('DE_Slate_Roofs',(-4.4,9.5,34.95),3.25,6.1,3.4,'slate')

    # Open arcaded gallery at the north end of the courtyard.
    for i in range(6):
        xx=-1.8+i*3.1
        B.arch('DE_Courtyard_Gallery',(xx,27.7,12.27),2.36,4.2,2.4,'limestone',0,10,.37)
    B.box('DE_Courtyard_Gallery',(5.9,27.7,17.05),(20.2,2.6,1.10),'white')
    B.box('DE_Courtyard_Gallery',(5.9,27.7,17.74),(20.6,3,.28),'limestone')
    B.roof('DE_Slate_Roofs',(5.9,27.7,17.89),21.1,3.1,1.4,'slate')
    for xx in (-4.4,16.1):
        B.box('DE_Courtyard_Gallery',(xx,27.7,14.9),(.8,2.6,5.2),'stone')

    # The red gatehouse has an uninterrupted 4.8 m arch tunnel at grade.
    # Side piers and curved spandrels replace any solid wall behind the gate.
    gate_origin=(8,-24.2)
    wall_cell(gate_origin,0,12.22,24.5,8.6,4.8,12.22,6.3,0,'brick',5.7,False)
    B.arch('DE_Gatehouse',(8,-18.47,12.22),4.8,6.3,.30,'limestone',0,12,.45)
    for cx,w in ((-.75,8.9),(17.25,9.9)):
        B.box('DE_Gatehouse',(cx,-21.35,18.36),(w,5.7,12.28),'brick')
        for z in (15.6,20.6,24.55):
            B.box('DE_Gatehouse',(cx,-21.35,z),(w+.18,5.9,.24),'limestone')
        for xx in (cx-w*.26,cx+w*.26):
            for z in (16.2,21.0): aperture((xx,-24.52),0,z,1.10,2.55)
        B.roof('DE_Slate_Roofs',(cx,-21.35,24.73),w+.7,6.3,4.0,'slate')
    B.box('DE_Gatehouse',(8,-21.35,24.62),(8.9,6.1,.38),'limestone')
    B.roof('DE_Slate_Roofs',(8,-21.35,24.85),9.1,6.4,4.2,'slate')
    for xx in (5.9,8,10.1): aperture((xx,-24.51),0,20.4,1.12,2.4)
    # Recessed panels, pilaster caps, open door leaves, crest and ironwork.
    for xx in (-5.18,3.67,12.45,22.18):
        for z in (13.2,15.2,17.2,19.2,21.2,23.2):
            B.box('DE_Gatehouse',(xx,-24.39,z),(.64,.22,1.45),'limestone')
    for side in (-1,1):
        B.box('DE_Gate_Ironwork',(8+side*2.48,-21.35,14.53),(.16,4.0,4.45),'dark_wood')
        for yy in (-22.9,-22.2,-21.5,-20.8,-20.1):
            B.box('DE_Gate_Ironwork',(8+side*2.58,yy,14.53),(.045,.06,4.18),'metal')
    B.box('DE_Gatehouse',(8,-24.65,19.36),(1.4,.30,1.05),'limestone')
    B.cyl('DE_Gate_Ironwork',(8,-24.86,19.4),.27,.06,'gold',8)
    B.box('DE_Arrival_Path',(8,-21.35,12.30),(4.7,7,.08),'paving')

    # Low courtyard boundary has crenellations and a real gap at the entrance.
    for x1,x2,y in ((-28,-5.2,-22.5),(-28,28,34.6)):
        width=x2-x1
        B.box('DE_Battlements',((x1+x2)/2,y,13.2),(width,.86,2.0),'white')
        B.box('DE_Battlements',((x1+x2)/2,y,14.27),(width+.1,1.02,.20),'limestone')
        for j in range(int(width/1.6)):
            xx=x1+.7+j*1.6
            B.box('DE_Battlements',(xx,y,14.75),(.78,.92,.78),'white')
            B.box('DE_Battlements',(xx,y,15.16),(.90,1.04,.14),'limestone')
    for side in (-1,1):
        xx=side*27.8
        B.box('DE_Battlements',(xx,6,13.05),(.85,56.5,1.7),'white')
        B.box('DE_Battlements',(xx,6,13.97),(1.04,56.7,.18),'limestone')
        for yy in range(-20,34,2):
            B.box('DE_Battlements',(xx,yy,14.4),(.9,.88,.75),'white')

    # Fountain and courtyard fittings, leaving the center and gateway walkable.
    B.cyl('DE_Courtyard_Fittings',(7.1,16.0,12.40),2.10,.30,'limestone',24)
    B.cyl('DE_Courtyard_Fittings',(7.1,16.0,12.61),1.74,.25,'water',24)
    for j in range(24):
        a=tau*j/24
        B.box('DE_Courtyard_Fittings',(7.1+1.95*math.cos(a),16+1.95*math.sin(a),12.65),(.32,.48,.40),'limestone',a)
    B.cyl('DE_Courtyard_Fittings',(7.1,16.0,13.49),.23,1.90,'stone',16,.16)
    B.cyl('DE_Courtyard_Fittings',(7.1,16.0,14.35),.82,.20,'limestone',24,.60)
    for xx,yy in ((2,-11),(11,-10),(4,23)):
        for dx in (-.82,.82): B.box('DE_Courtyard_Fittings',(xx+dx,yy,12.59),(.18,.56,.72),'stone')
        B.box('DE_Courtyard_Fittings',(xx,yy,13.02),(2.1,.67,.18),'wood')
    # Grounded, varied fir trees frame the architecture without hiding it.
    planted=[]
    for _ in range(450):
        x=rng.uniform(-62,61);y=rng.uniform(-49,54)
        if abs(x)<33 and -29<y<40: continue
        dist,_=nearest_path(x,y)
        if dist<5.8: continue
        if any((x-a)**2+(y-b)**2<19 for a,b in planted): continue
        planted.append((x,y))
        h=rng.uniform(7.5,15.0)
        if y<-35:h*=.75
        B.pine('DE_Forest',x,y,actual_height(x,y)-.06,h)
        if len(planted)>=84: break
    # Angular outcrops tie the flat terrain texture into the cliff silhouette.
    for _ in range(43):
        x=rng.uniform(-48,48);y=rng.uniform(-39,46)
        z=actual_height(x,y);dist,_=nearest_path(x,y)
        if not 1.5<z<10.8 or dist<4.7:continue
        r=rng.uniform(.8,2.4)
        B.cyl('DE_Hill_Outcrops',(x,y,z+.15),r,rng.uniform(1.1,3.0),'rock',7,r*.53)

    return {'landmark':'新天鹅堡风格山顶城堡',
            'approximate_scale':'约 1:2 建筑体量重组；140 × 120 m 外景区域，城堡最高约 63.6 m',
            'spawn':[-17,-55,.30],
            'description':'白色石灰岩宫殿、带拱券的深窗洞、板岩陡屋顶、圆塔、红砖门楼、开放庭院和连续山林到达道路；依据官方外观照片作游戏化建筑重组。',
            'reference':'https://www.neuschwanstein.de/englisch/palace/',
            'approach_width_m':4.8,
            'gate_clearance_m':[4.8,6.3],
            'courtyard_elevation_m':12.22}

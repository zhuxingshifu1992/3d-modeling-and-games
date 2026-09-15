"""Editable, meter-scale abandoned vehicles reconstructed from references 01/05.

Front is -Y. Each vehicle is a named hierarchy; tires and fittings use batched
meshes to keep the complete fleet below 1,500 objects. No scene-level changes.
"""
from common import *
from mathutils import Matrix, Euler


def _paint(name, base, tint):
    """Retain shared baked wear maps, changing only the faded paint tint."""
    old = bpy.data.materials.get(name)
    if old:
        return old
    mat = material(base).copy()
    mat.name = name
    nt = mat.node_tree
    bs = nt.nodes.get('Principled BSDF')
    if bs and bs.inputs['Base Color'].links:
        source = bs.inputs['Base Color'].links[0].from_socket
        mix = nt.nodes.new('ShaderNodeMixRGB')
        mix.blend_type = 'MULTIPLY'
        mix.inputs[0].default_value = 1.0
        mix.inputs[2].default_value = (*tint, 1)
        nt.links.new(source, mix.inputs[1])
        nt.links.new(mix.outputs[0], bs.inputs['Base Color'])
    return mat


def _batch_boxes(name, items, mat):
    verts, faces = [], []
    face_template = [(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
    for loc, size, rot in items:
        matrix = Euler(rot).to_matrix()
        off = len(verts)
        for xx, yy, zz in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]:
            p = matrix @ Vector((xx*size[0]/2, yy*size[1]/2, zz*size[2]/2)) + Vector(loc)
            verts.append(tuple(p))
        faces.extend(tuple(off+i for i in f) for f in face_template)
    return mesh(name, verts, faces, mat)


def _cylinders_x(name, cylinders, mat, count=8):
    verts, faces = [], []
    for (x,y,z), radius, depth in cylinders:
        off = len(verts)
        for side in (-1, 1):
            for i in range(count):
                a = 2*pi*i/count
                verts.append((x+side*depth/2, y+radius*sin(a), z+radius*cos(a)))
        faces.append(tuple(off+i for i in range(count)))
        faces.append(tuple(off+count+i for i in range(count-1,-1,-1)))
        faces.extend((off+i, off+count+i, off+count+(i+1)%count, off+(i+1)%count) for i in range(count))
    return mesh(name, verts, faces, mat)


def _extrude_side(name, profile, half_width, mat, bevel=.035):
    """A real shaped shell with a concave sill profile / wheel opening."""
    n = len(profile)
    verts = [(x,y,z) for x in (-half_width,half_width) for y,z in profile]
    faces = [tuple(range(n)), tuple(range(2*n-1,n-1,-1))]
    faces += [(i,i+n,(i+1)%n+n,(i+1)%n) for i in range(n)]
    ob = mesh(name,verts,faces,mat)
    if bevel:
        mod=ob.modifiers.new('Rolled body panel edges','BEVEL');mod.width=bevel;mod.segments=3
    return ob


def _rect_beam(name, a, b, width, thick, mat, bevel=.025):
    d = Vector(b)-Vector(a)
    ob = box(name,(Vector(a)+Vector(b))/2,(width,thick,d.length),mat,bevel)
    ob.rotation_euler=d.to_track_quat('Z','Y').to_euler()
    return ob


def _polygon(name, points, mat):
    return mesh(name, points, [tuple(range(len(points)))], mat)


def _inset_side(name, side, yz, mat='glass', x=1.092, inset=.045):
    seal=[(side*x,y,z) for y,z in yz]
    _polygon(name+' rubber seal',seal[::-1] if side>0 else seal,'black')
    cy=sum(v[0] for v in yz)/len(yz);cz=sum(v[1] for v in yz)/len(yz)
    glass=[(side*(x+.006),y+(cy-y)*inset*3,z+(cz-z)*inset*3) for y,z in yz]
    return _polygon(name+' recessed glass',glass[::-1] if side>0 else glass,mat)


def _wheel(name, x, y, r=.54, width=.29, flatten=.0):
    """Six-ring tire cross section, 48 angular slices, individual tread blocks."""
    z=r+.025-flatten
    profile=[(-width*.5,r*.67),(-width*.51,r*.85),(-width*.39,r*.98),
             (width*.39,r*.98),(width*.51,r*.85),(width*.5,r*.67)]
    verts=[];faces=[];n=48
    for xx,rr in profile:
        for i in range(n):
            a=2*pi*i/n
            verts.append((x+xx,y+sin(a)*rr,max(.025,z+cos(a)*rr)))
    for j in range(len(profile)-1):
        for i in range(n):
            faces.append((j*n+i,(j+1)*n+i,(j+1)*n+(i+1)%n,j*n+(i+1)%n))
    tire=mesh(name+' aged sidewall',verts,faces,'rubber')
    for p in tire.data.polygons:p.use_smooth=True
    items=[]
    for i in range(40):
        a=2*pi*i/40
        for stagger in (-1,1):
            aa=a+stagger*.027
            items.append(((x+stagger*width*.215,y+sin(aa)*r*.989,max(.029,z+cos(aa)*r*.989)),
                          (width*.39,r*.128,.030),(-aa,0,0)))
    _batch_boxes(name+' 80 tread blocks',items,'rubber')
    sign=1 if x>0 else -1
    rimx=x+sign*(width*.50+.003)
    cyl(name+' dished wheel rim',(rimx,y,z),r*.64,.052,'steel',32,rot=(0,pi/2,0))
    cyl(name+' hub recess',(rimx+sign*.031,y,z),r*.44,.055,'iron',24,rot=(0,pi/2,0))
    cyl(name+' axle dust cap',(rimx+sign*.073,y,z),r*.19,.13,'steel',16,rot=(0,pi/2,0))
    nuts=[];holes=[]
    for i in range(8):
        a=i*2*pi/8
        nuts.append(((rimx+sign*.078,y+sin(a)*r*.29,z+cos(a)*r*.29),r*.036,.04))
        aa=a+pi/8
        holes.append(((rimx+sign*.035,y+sin(aa)*r*.51,z+cos(aa)*r*.51),r*.069,.009))
    _cylinders_x(name+' eight hex lug nuts',nuts,'silver',6)
    _cylinders_x(name+' rim ventilation holes',holes,'black',10)


def _vehicle_root(name, before, loc, angle=0):
    objects=[ob for ob in bpy.data.objects if ob not in before]
    root=bpy.data.objects.new(name,None)
    root.empty_display_type='PLAIN_AXES';root.empty_display_size=.6
    bpy.context.scene.collection.objects.link(root)
    for ob in objects:
        ob.name=name+' / '+ob.name
        ob.parent=root
    root.location=loc;root.rotation_euler.z=angle
    root['units']='meters';root['front']='local -Y';root['reference']='ref_01.jpg / ref_05.jpg'
    return root


def _rust_patches(name, seed, severity, side_x, zones):
    rng=random.Random(seed);verts=[];faces=[]
    for side in (-1,1):
        for ymin,ymax,zmin,zmax,amount in zones:
            for _ in range(int(amount*severity)):
                cy=rng.uniform(ymin,ymax);cz=rng.uniform(zmin,zmax)
                ry=rng.uniform(.016,.085)*severity;rz=rng.uniform(.007,.045)
                off=len(verts)
                for j in range(7):
                    a=j*2*pi/7;v=rng.uniform(.55,1.15)
                    verts.append((side*side_x,cy+sin(a)*ry*v,cz+cos(a)*rz*v))
                faces.append(tuple(off+j for j in (range(6,-1,-1) if side>0 else range(7))))
    return mesh(name,verts,faces,'rust')


def _hydraulic(name, a, b, casing=.082):
    a=Vector(a);b=Vector(b);d=b-a
    beam(name+' oil cylinder',a,a+d*.67,casing,'iron',16)
    beam(name+' polished piston rod',a+d*.59,b,casing*.49,'silver',12)
    for point in (a,b):
        cyl(name+' pin eye',point,casing*1.33,.16,'steel',12,rot=(0,pi/2,0))


def _truck(index, center, paint, severity, raise_tip=0):
    collection('04 VEHICLES / boom truck %02d'%index)
    before=set(bpy.data.objects)
    profile=[(-2.89,.78),(-2.92,1.68),(-2.76,2.04),(-2.45,2.83),
             (-1.03,2.83),(-.86,2.64),(-.86,.80),(-1.18,.80),
             (-1.26,1.01),(-1.48,1.25),(-1.80,1.36),(-2.12,1.27),(-2.35,1.03),(-2.43,.78)]
    _extrude_side('Cab shell with formed front wheel arches',profile,1.078,paint)
    # Windshield is seated on the inclined front plane, with exposed perimeter seal.
    _polygon('Windshield rubber surround',[(-1.004,-2.774,2.037),(1.004,-2.774,2.037),(1.00,-2.490,2.752),(-1.00,-2.490,2.752)],'black')
    _polygon('Wide dusty angled windshield',[(-.939,-2.758,2.090),(.939,-2.758,2.090),(.946,-2.515,2.710),(-.946,-2.515,2.710)],'glass')
    beam('Windscreen center fine mullion',(0,-2.760,2.070),(0,-2.493,2.727),.011,'black',6)
    for sign in (-1,1):
        yz=[(-2.692,2.046),(-2.419,2.744),(-1.125,2.744),(-.953,2.595),(-.953,2.048)]
        _inset_side('Driver window' if sign<0 else 'Passenger window',sign,yz)
        beam('Sliding pane divider',(sign*1.105,-1.462,2.070),(sign*1.105,-1.462,2.727),.019,'black',6)
        curve('Stamped door seam',[(sign*1.104,-2.665,1.984),(sign*1.104,-2.495,1.475),(sign*1.104,-2.268,1.417),(sign*1.104,-1.124,1.412),(sign*1.104,-.981,1.57),(sign*1.104,-.981,2.01)],.009,'rust')
        box('Inset black door handle',(sign*1.105,-1.185,1.841),(.035,.225,.055),'black',.018)
        cyl('Door handle keyhole',(sign*1.13,-1.185,1.787),.022,.012,'silver',12,rot=(0,pi/2,0))
        box('Lower cab step',(sign*1.04,-1.10,.742),(.33,.55,.08),'steel',.012)
        _batch_boxes('Perforated anti-slip step', [((sign*1.054,-1.31+j*.09,.789),(.29,.03,.012),(0,0,0)) for j in range(5)],'black')
        curve('Mirror support arm',[(sign*1.04,-2.38,2.65),(sign*1.30,-2.47,2.69),(sign*1.365,-2.44,2.33)],.023,'iron')
        mirror=box('Side mirror housing',(sign*1.38,-2.424,2.272),(.15,.14,.40),'black',.055)
        box('Mirror reflective face',(sign*1.38,-2.347,2.277),(.115,.012,.339),'silver',.033)
        box('Cab orange turn signal',(sign*1.09,-2.556,1.872),(.023,.17,.08),paint,.01)
        # Wheel-arch edging is actual tubing following the stamped cutout.
        points=[]
        for k in range(15):
            a=pi*k/14
            points.append((sign*1.096,-1.82+.64*cos(a),.728+.628*sin(a)))
        curve('Rubber wheel arch trim',points,.028,'rubber')
        text_obj('Fleet identification','高空作业',(sign*1.116,-1.69,1.677),.139,'cream',rot=(pi/2,0,sign*pi/2))
    for x in (-.47,.47):
        curve('Wiper arm',[(x*.80,-2.797,2.072),(x+.18,-2.669,2.372)],.012,'iron')
        beam('Wiper rubber blade',(x-.10,-2.699,2.315),(x+.39,-2.632,2.471),.015,'black',6)
    box('Cab bumper',(0,-2.987,.812),(2.24,.18,.245),'steel',.065)
    box('Front grille recess',(0,-2.936,1.383),(.86,.035,.37),'black',.025)
    _batch_boxes('Front grille seven horizontal bars',[((0,-2.960,1.233+j*.047),(.81,.021,.019),(0,0,0)) for j in range(7)],'steel')
    for x in (-.80,.80):
        box('Headlight rubber gasket',(x,-2.954,1.274),(.48,.036,.275),'black',.045)
        box('Unlit oxidised headlight',(x,-2.980,1.290),(.386,.023,.183),'cream',.029)
        box('Indicator lens',(x,-2.982,1.14),(.37,.024,.060),paint,.01)
        beam('Headlight glass flute',(x-.09,-2.997,1.220),(x-.09,-2.997,1.360),.003,'silver',4)
        box('Bumper reflector',(x,-3.09,.834),(.24,.012,.06),'red',.005)
    box('Front plate backing',(0,-3.087,.904),(.46,.022,.145),'blue',.009)
    text_obj('Plate number','DEMO',(0,-3.104,.902),.085,'cream')
    box('Roof visor',(0,-2.436,2.858),(2.06,.32,.049),paint,.025)
    for x in (-.65,.65):
        cyl('Beacon black mount',(x,-1.72,2.858),.092,.043,'black',16)
        cyl('Faded amber beacon',(x,-1.72,2.933),.077,.12,paint,16)
    # Ladder-frame chassis and six tires (single steering wheels / rear duals).
    for x in (-.57,.57):box('Long chassis rail',(x,.10,.742),(.15,5.11,.22),'iron',.018)
    for yy in (-1.82,1.78):beam('Heavy live axle',(-1.1,yy,.55),(1.1,yy,.55),.10,'iron',12)
    for xx in (-1.018,1.018):_wheel('Steering wheel',xx,-1.82,.555,.29,.018 if index==4 else 0)
    for xx in (-1.049,-.789,.789,1.049):_wheel('Rear dual tire',xx,1.78,.548,.235,.057 if index==3 else 0)
    box('Steel flatbed deck',(0,1.05,1.212),(2.29,3.69,.145),'steel',.025)
    box('Boom subframe',(0,.95,1.349),(1.32,2.45,.16),'iron',.015)
    for sign in (-1,1):
        box('Bed side rail',(sign*1.13,1.13,1.365),(.055,3.50,.25),paint,.012)
        box('Side underrun bar',(sign*1.12,.12,.717),(.095,1.39,.09),'steel',.014)
        box('Lockable service locker',(sign*.84,.14,1.02),(.47,1.19,.39),paint,.032)
        box('Service locker latch',(sign*1.09,.14,1.059),(.032,.12,.067),'iron',.009)
        box('Rear mudflap',(sign*1.014,2.448,.538),(.41,.075,.465),'rubber',.011)
        box('Rear dual fender',(sign*1.002,1.775,1.146),(.54,1.61,.07),'steel',.04)
        stripe=[];white=[]
        for j in range(9):
            row=((sign*1.163,-.435+j*.361,1.376),(.013,.18,.068),(0,0,0))
            (stripe if j%2 else white).append(row)
        _batch_boxes('Red bed reflective rectangles',stripe,'red')
        _batch_boxes('White bed reflective rectangles',white,'white')
        for y in (-.39,2.21):
            box('Retracted outrigger channel',(sign*.79,y,.937),(.61,.24,.18),'iron',.015)
            cyl('Outrigger ram',(sign*1.01,y,.818),.064,.42,'steel',12)
            box('Stabilizer ground plate',(sign*1.01,y,.60),(.25,.29,.04),'steel',.012)
    box('Rear bumper',(0,2.966,.827),(2.22,.17,.13),'steel',.018)
    for x in (-.90,.90):
        box('Rear lamp cluster',(x,3.025,1.091),(.35,.025,.13),'black',.012)
        box('Rear red tail lens',(x-.075,3.046,1.091),(.16,.024,.097),'red',.008)
        box('Rear pale lens',(x+.09,3.046,1.091),(.095,.024,.097),'cream',.007)
    # Folded articulated assembly: triangular elevation, telescoping return boom.
    cyl('Slew-ring bearing',(0,.48,1.485),.53,.19,'iron',32)
    cyl('Slew gear crown',(0,.48,1.602),.45,.10,'steel',32)
    box('Turret pedestal',(0,.48,1.801),(.70,.63,.41),paint,.05)
    a=(0,.48,1.946);b=(0,-2.215,3.163+raise_tip);c=(0,2.22,3.34+raise_tip)
    _rect_beam('Lower folded lifting boom',a,b,.49,.52,paint)
    _rect_beam('Main telescopic boom casing',b,(0,.70,3.279+raise_tip),.63,.44,paint)
    _rect_beam('Telescopic second section',(0,.55,3.273+raise_tip),c,.43,.34,paint)
    _rect_beam('Black telescopic seal',(0,.61,3.275+raise_tip),(0,.78,3.282+raise_tip),.664,.47,'black',.008)
    _rect_beam('Exposed inner section',(0,1.52,3.312+raise_tip),(0,2.42,3.348+raise_tip),.295,.26,'yellow',.015)
    for point,rad in ((a,.185),(b,.215),(c,.145)):
        cyl('Articulation pivot pin',point,rad,.79,'iron',16,rot=(0,pi/2,0))
        for sign in (-1,1):
            cyl('Pivot end washer',(sign*.415,point[1],point[2]),rad*.68,.065,'steel',16,rot=(0,pi/2,0))
            cyl('Pivot retaining nut',(sign*.455,point[1],point[2]),rad*.37,.035,'rust',6,rot=(0,pi/2,0))
    for side in (-1,1):
        _hydraulic('Luffing cylinder',(side*.341,.48,1.741),(side*.341,-1.58,2.84+raise_tip*.77),.085)
        _hydraulic('Folding cylinder',(side*.373,-1.916,2.847+raise_tip),(side*.373,.32,3.124+raise_tip),.065)
    _rect_beam('Rear basket levelling jib',(0,2.23,3.33+raise_tip),(0,2.73,2.658),.23,.22,paint,.015)
    _hydraulic('Basket self-levelling ram',(.23,2.17,3.175+raise_tip),(.23,2.64,2.708),.049)
    # Flexible lines are individually editable curves, with a recognisable hose loop.
    for j in range(5):
        xx=-.27+j*.093
        curve('Hydraulic hose bundle %d'%j,[(xx,.47,1.64),(xx,.16,1.97),(xx,-1.62,2.74+raise_tip),
              (xx,-2.40,3.05+raise_tip),(xx,-2.41,3.42+raise_tip),(xx,-1.98,3.48+raise_tip),
              (xx,1.56,3.53+raise_tip),(xx,2.32,3.48+raise_tip),(xx,2.48,2.76)],.019,'rubber')
    clips=[]
    for j in range(11):clips.append(((0,-1.82+j*.302,3.548+raise_tip),(.64,.045,.035),(0,0,0)))
    _batch_boxes('Hose clamps across main boom',clips,'iron')
    # Rear work basket: open cage with small kick-plates and control console.
    box('Basket anti-slip floor',(0,2.666,2.218),(1.43,.83,.084),'steel',.015)
    for xx in (-.692,.692):
        box('Basket toe board',(xx,2.666,2.355),(.038,.83,.20),'steel',.008)
    for yy in (2.27,3.064):
        box('Basket toe board',(0,yy,2.355),(1.41,.036,.20),'steel',.008)
    for z in (2.79,3.259):
        rail=curve('Basket continuous guard rail',[(-.695,2.266,z),(.695,2.266,z),(.695,3.066,z),(-.695,3.066,z)],.026,'silver',cyclic=True)
        for point in rail.data.splines[0].bezier_points:
            point.handle_left_type='VECTOR';point.handle_right_type='VECTOR'
    for xx in (-.695,0,.695):
        for yy in (2.266,3.066):beam('Basket railing vertical',(xx,yy,2.33),(xx,yy,3.265),.025,'silver')
    for xx in (-.695,.695):beam('Basket side vertical',(xx,2.67,2.33),(xx,2.67,3.265),.022,'steel')
    box('Basket control console',(.47,2.49,2.995),(.33,.21,.19),'iron',.022)
    for j in range(3):beam('Control lever',(.39+j*.063,2.466,3.069),(.39+j*.063,2.435,3.175),.009,'steel',6)
    # On-body rust flakes add non-repeating local deterioration over baked paint.
    _rust_patches('Chipped cab door paint',100+index,severity,1.114,[(-2.30,-1.02,1.45,1.96,19)])
    _rust_patches('Bed rail rust flakes',800+index,severity,1.164,[(-.42,2.65,1.265,1.474,27)])
    if index in (3,4):
        curve('Cracked windshield',[(.22,-2.682,2.304),(.30,-2.638,2.415),(.18,-2.594,2.528),(.27,-2.556,2.625)],.003,'cream')
        curve('Windshield crack branch',[(.30,-2.638,2.415),(.53,-2.625,2.449),(.70,-2.647,2.392)],.0025,'cream')
    root=_vehicle_root('TRUCK %02d / rusted aerial work truck'%index,before,(*center,0))
    root['approx_dimensions_m']='2.91 incl mirrors × 6.21 × %.2f'%(3.60+raise_tip)
    root['six_tires']='2 steering plus 4 rear duals'
    return root


def _car_body(name, sections, mat):
    verts=[];faces=[]
    # Eight-point section produces real shoulder, sill and hood curvature.
    for y,w,zb,zt in sections:
        verts.extend([(-w*.83,y,zb),(-w,y,zb+.11),(-w,y,zt-.12),(-w*.79,y,zt),
                      (w*.79,y,zt),(w,y,zt-.12),(w,y,zb+.11),(w*.83,y,zb)])
    for j in range(len(sections)-1):
        for k in range(8):faces.append((j*8+k,j*8+(k+1)%8,(j+1)*8+(k+1)%8,(j+1)*8+k))
    faces += [tuple(range(7,-1,-1)),tuple((len(sections)-1)*8+k for k in range(8))]
    ob=mesh(name,verts,faces,mat)
    mod=ob.modifiers.new('Soft formed sheetmetal','BEVEL');mod.width=.047;mod.segments=3
    return ob


def _car(name, center, paint='white', abandoned=False):
    collection('04 VEHICLES / '+name);before=set(bpy.data.objects)
    _car_body('Stamped unibody',[(-2.11,.73,.38,.76),(-1.70,.877,.38,.94),(-.84,.895,.40,1.005),
              (.73,.884,.40,1.036),(1.48,.846,.41,.975),(2.03,.70,.40,.82)],paint)
    # Separate greenhouse makes the roof height and raked screens legible.
    _extrude_side('Passenger cabin shell',[(-.98,.90),(-.405,1.566),(-.21,1.628),(.83,1.611),(1.56,.98)],.694,paint,.055)
    _polygon('Front windscreen seal',[(-.683,-.882,1.025),(.683,-.882,1.025),(.669,-.415,1.566),(-.669,-.415,1.566)],'black')
    _polygon('Front dusty windscreen',[(-.633,-.856,1.058),(.633,-.856,1.058),(.624,-.438,1.542),(-.624,-.438,1.542)],'glass')
    _polygon('Rear windscreen seal',[(-.669,.835,1.615),(.669,.835,1.615),(.68,1.494,1.038),(-.68,1.494,1.038)],'black')
    _polygon('Rear dusty windscreen',[(-.623,.880,1.580),(.623,.880,1.580),(.625,1.433,1.095),(-.625,1.433,1.095)],'glass')
    for sign in (-1,1):
        _inset_side('Front side window',sign,[(-.855,1.026),(-.369,1.529),(.144,1.550),(.144,1.031)],x=.700,inset=.033)
        _inset_side('Rear side window',sign,[(.225,1.031),(.225,1.550),(.800,1.534),(1.375,1.031)],x=.700,inset=.033)
        curve('Window belt chrome',[(sign*.735,-.901,1.013),(sign*.735,.13,1.013),(sign*.735,1.435,1.013)],.009,'steel')
        for yy in (-.22,.89):
            box('Recessed door pull',(sign*.898,yy,.965),(.021,.145,.028),'steel',.012)
        curve('Front door shutline',[(sign*.902,-.77,.991),(sign*.902,-.64,.53),(sign*.902,.20,.53),(sign*.902,.20,.982)],.006,'iron')
        curve('Rear door shutline',[(sign*.891,.26,.983),(sign*.891,.26,.539),(sign*.868,1.094,.550),(sign*.868,1.29,.938)],.005,'iron')
        box('Side mirror stalk',(sign*.799,-.671,1.095),(.20,.075,.063),'black',.016)
        ico('Aerodynamic side mirror',(sign*.941,-.667,1.119),(.127,.167,.078),paint,2)
        box('Black side sill strip',(sign*.891,.0,.498),(.035,2.85,.069),'black',.012)
        for yy in (-1.318,1.290):
            _wheel('Road wheel',sign*.877,yy,.352,.206,.033 if abandoned else .012)
            curve('Fender arch edging',[(sign*.903,yy+.391*cos(k*pi/16),.43+.35*sin(k*pi/16)) for k in range(17)],.012,'black')
    box('Front bumper rub strip',(0,-2.130,.561),(1.50,.045,.11),'black',.026)
    box('Radiator opening',(0,-2.115,.731),(.54,.054,.112),'iron',.021)
    for sign in (-1,1):
        lamp=[(sign*.397,-2.133,.717),(sign*.678,-2.124,.725),(sign*.725,-2.001,.801),(sign*.467,-2.030,.813)]
        _polygon('Shaped front lamp',lamp if sign>0 else lamp[::-1],'cream')
        box('Rear taillamp',(sign*.57,2.037,.763),(.26,.036,.12),'red',.023)
    box('Front blue number plate',(0,-2.155,.53),(.36,.012,.115),'blue',.004)
    text_obj('Small car registration','DEMO',(0,-2.165,.53),.063,'cream')
    box('Rear bumper strip',(0,2.055,.545),(1.42,.044,.10),'black',.023)
    curve('Left windshield wiper',[(-.51,-.897,1.014),(-.26,-.721,1.217)],.007,'black')
    curve('Right windshield wiper',[(.08,-.897,1.014),(.35,-.721,1.217)],.007,'black')
    cyl('Short roof antenna',(.25,.81,1.773),.008,.31,'black',8,rot=(.2,0,0))
    _rust_patches('Rocker panel corrosion',112 if abandoned else 411,.85 if abandoned else .35,.902,[(-.78,1.0,.49,.63,15)])
    root=_vehicle_root(name,before,(*center,0),-pi/2)
    root['approx_dimensions_m']='4.25 × 2.14 incl mirrors × 1.93'
    return root


def _van(center):
    collection('04 VEHICLES / abandoned cargo van');before=set(bpy.data.objects)
    paint=_paint('Fleet van chalky white','white',(.97,.96,.91))
    profile=[(-2.22,.62),(-2.26,1.22),(-2.11,1.54),(-1.59,2.24),(-1.38,2.33),
             (1.98,2.33),(2.20,2.20),(2.24,.61),(1.71,.61),(1.66,.85),(1.47,1.00),
             (1.22,1.075),(.97,1.00),(.79,.81),(.73,.60),(-.91,.60),(-.97,.85),
             (-1.16,1.019),(-1.42,1.081),(-1.66,1.01),(-1.88,.80),(-1.94,.61)]
    _extrude_side('Rounded cargo van shell and wheel arches',profile,.973,paint,.078)
    _polygon('Van windshield wide seal',[(-.889,-2.115,1.559),(.889,-2.115,1.559),(.858,-1.628,2.217),(-.858,-1.628,2.217)],'black')
    _polygon('Van windshield accumulated dust',[(-.829,-2.091,1.607),(.829,-2.091,1.607),(.811,-1.666,2.187),(-.811,-1.666,2.187)],'glass')
    for sign in (-1,1):
        _inset_side('Van cab window',sign,[(-2.015,1.56),(-1.55,2.223),(-.57,2.223),(-.57,1.56)],x=.980,inset=.025)
        _inset_side('Cargo side dark tinted window',sign,[(-.39,1.64),(-.39,2.224),(1.87,2.224),(2.013,2.06),(2.013,1.64)],x=.980,inset=.037)
        beam('Cargo window divider',(sign*.994,.68,1.688),(sign*.994,.68,2.18),.015,'black')
        curve('Cab door perimeter',[(sign*.992,-2.017,1.46),(sign*.992,-1.82,1.12),(sign*.992,-.49,1.13),(sign*.992,-.49,2.226)],.008,'iron')
        curve('Sliding cargo door shut line',[(sign*.994,-.402,2.224),(sign*.994,-.402,.71),(sign*.994,1.66,.71),(sign*.994,1.66,1.57)],.008,'iron')
        box('Sliding door track',(sign*.992,.76,1.452),(.035,2.36,.05),'steel',.009)
        for yy in (-.72,.29):box('Van door pull',(sign*1.001,yy,1.474),(.038,.19,.045),'black',.017)
        box('Van mirror arm',(sign*1.073,-1.86,1.66),(.27,.06,.055),'iron',.011)
        box('Van side mirror',(sign*1.171,-1.86,1.763),(.16,.22,.26),'black',.047)
        box('Van black sill',(sign*.970,.23,.663),(.085,4.08,.094),'black',.018)
        for yy in (-1.42,1.22):
            _wheel('Van tire',sign*.943,yy,.425,.215,.066)
            curve('Wheelarch rubbed trim',[(sign*.997,yy+.501*cos(k*pi/16),.611+.483*sin(k*pi/16)) for k in range(17)],.021,'rubber')
        # Rust runs down a weathered roof joint, distinct from the base wear map.
        for j in range(6):
            yy=-.28+j*.39
            curve('Thin rust drip',[(sign*.982,yy,2.31),(sign*.985,yy+.02,2.255),(sign*.988,yy+.055,2.209)],.005,'rust')
    box('Van front bumper',(0,-2.303,.678),(1.90,.128,.19),'black',.056)
    box('Van front radiator',(0,-2.289,1.042),(.67,.056,.26),'black',.025)
    _batch_boxes('Van grille ribs',[((0,-2.325,.957+j*.057),(.62,.016,.025),(0,0,0)) for j in range(4)],'steel')
    for x in (-.710,.710):
        box('Van headlight surround',(x,-2.292,1.145),(.39,.041,.25),'black',.033)
        box('Van aged headlight',(x,-2.321,1.146),(.32,.021,.182),'cream',.025)
        box('Vertical rear taillamp',(x,2.265,1.438),(.11,.035,.49),'red',.024)
    box('Van rear black bumper',(0,2.272,.683),(1.90,.11,.16),'black',.035)
    for x in (-.479,.479):
        box('Rear door dark window seal',(x,2.264,1.930),(.813,.033,.595),'black',.045)
        box('Rear door tinted window',(x,2.286,1.933),(.743,.017,.512),'glass',.035)
        curve('Rear cargo door lower seam',[(x-.428,2.273,1.615),(x-.428,2.273,.89),(x+.428,2.273,.89),(x+.428,2.273,1.615)],.007,'iron')
    beam('Rear doors center join',(0,2.287,.84),(0,2.287,2.27),.007,'iron')
    box('Rear cargo door handle',(.16,2.30,1.387),(.21,.041,.049),'black',.013)
    box('Van rear plate backing',(-.42,2.301,1.269),(.43,.022,.137),'teal',.007)
    text_obj('Van abandoned plate','DEMO',(-.42,2.319,1.269),.075,'cream',rot=(pi/2,0,pi))
    for x in (-.47,.47):curve('Van wiper',[(x,-2.156,1.555),(x+.2,-1.950,1.824)],.010,'black')
    _rust_patches('Cargo sill flaking and mud',713,1.6,1.001,[(-.80,.68,.69,1.10,16),(-.30,1.66,1.23,1.45,12)])
    root=_vehicle_root('VAN / abandoned white cargo van',before,(*center,0))
    root['approx_dimensions_m']='2.51 incl mirrors × 4.63 × 2.41'
    return root


def build():
    """Create four utility trucks, a parked cargo van and two charge-bay cars."""
    paints=[_paint('Truck 01 ochre yellow','yellow',(1.08,1.00,.78)),
            _paint('Truck 02 sun-faded gold','yellow',(1.12,1.05,.86)),
            _paint('Truck 03 oxidised orange','yellow',(1.12,.73,.53)),
            _paint('Truck 04 ash yellow','yellow',(.86,.84,.72))]
    roots=[]
    for i,x in enumerate((6,10,14,18)):
        roots.append(_truck(i+1,(x,12.5),paints[i],(.72,.90,1.22,1.52)[i],(0,.09,.19,.035)[i]))
    roots.append(_van((-5,17)))
    roots.append(_car('CAR / dusty white EV in charging bay',(-5.3,7.5),'white'))
    roots.append(_car('CAR / abandoned dark hatchback',(-5.3,12),'iron',True))
    return roots

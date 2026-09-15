"""Editable charging pods and everyday yard equipment, based on refs 02/03/04/06.

All shapes are in metres; appliance assemblies are parented to named empties.
Only build() is public. No scene, camera, render or save changes are made here.
"""
from common import *
import random


def _round(name, loc, size, mat, radius=.06, rot=(0, 0, 0)):
    # Bevel width on a thin flat pane would be clamped by its thickness.
    # Instead extrude a genuinely rounded 2D outline for such panels.
    thin = min(range(3), key=lambda i:size[i])
    if radius > size[thin]*.48:
        a,b=[i for i in range(3) if i!=thin]
        w,h=size[a],size[b]
        r=min(radius,w*.48,h*.48)
        outline=[]
        corners=[(w/2-r,h/2-r,0),(-w/2+r,h/2-r,90),
                 (-w/2+r,-h/2+r,180),(w/2-r,-h/2+r,270)]
        for x,z,start in corners:
            for k in range(7):
                ang=(start+k*15)*pi/180
                outline.append((x+r*cos(ang),z+r*sin(ang)))
        verts=[]
        for side in [-1,1]:
            for x,z in outline:
                co=[0,0,0];co[a]=x;co[b]=z;co[thin]=side*size[thin]/2
                verts.append(tuple(co))
        n=len(outline)
        faces=[tuple(reversed(range(n))),tuple(range(n,n*2))]
        faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
        if thin==1:faces=[tuple(reversed(face)) for face in faces]
        ob=mesh(name,verts,faces,mat);ob.location=loc;ob.rotation_euler=rot
        return ob
    ob = box(name, loc, size, mat, radius, rot)
    if ob.modifiers:
        ob.modifiers[-1].segments = 6
    return ob


def _assembly(name, loc, angle, fn):
    """Build in local coordinates, preserving every part as an editable object."""
    col = collection(name)
    before = set(bpy.data.objects)
    fn()
    pieces = set(bpy.data.objects) - before
    root = bpy.data.objects.new(name + ' / Assembly', None)
    col.objects.link(root)
    for ob in pieces:
        if ob.parent is None:
            ob.parent = root
    root.location = loc
    root.rotation_euler.z = angle
    root.empty_display_size = .3
    root['reference'] = 'User supplied yard photographs; proportionally reconstructed'
    return root


def _front_label(name, x, y, z, w, h, uv, ref):
    # UV is given as top-left, top-right, bottom-right, bottom-left in photo space.
    verts = [(x-w/2,y,z+h/2),(x+w/2,y,z+h/2),
             (x+w/2,y,z-h/2),(x-w/2,y,z-h/2)]
    return photo_plane(name, list(reversed(verts)), [(u,1-v) for u,v in reversed(uv)], ref)


def _wear(name, xmin, xmax, y, zmin, zmax, count=15, seed=0, mat='rust'):
    rng = random.Random(seed)
    verts, faces = [], []
    for i in range(count):
        x,z = rng.uniform(xmin,xmax),rng.uniform(zmin,zmax)
        w,h = rng.uniform(.007,.045),rng.uniform(.004,.020)
        n = len(verts)
        verts += [(x-w,y,z),(x-w*.2,y,z+h),(x+w,y,z+h*.25),
                  (x+w*.4,y,z-h*.6),(x-w*.5,y,z-h)]
        faces.append(tuple(reversed(range(n,n+5))))
    return mesh(name,verts,faces,mat)


def _bolts(name, positions, axis='Y', radius=.018):
    rot=(pi/2,0,0) if axis=='Y' else (0,0,0)
    for i,p in enumerate(positions):
        cyl(name+' bolt %02d'%i,p,radius,.012,'silver',vertices=6,rot=rot)


def _clear_glass():
    key='Appliance_Dusty_Clear_Glass'
    mat=bpy.data.materials.get(key)
    if mat:return mat
    mat=bpy.data.materials.new(key);mat.use_nodes=True
    mat.diffuse_color=(.30,.43,.40,.16)
    bs=mat.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value=(.30,.43,.40,1)
    bs.inputs['Roughness'].default_value=.23
    bs.inputs['Metallic'].default_value=.05
    bs.inputs['Alpha'].default_value=.16
    bs.inputs['Transmission Weight'].default_value=.48
    if hasattr(mat,'surface_render_method'):mat.surface_render_method='DITHERED'
    return mat


def _pod(index):
    prefix='Rest charge pod %02d'%index
    _round(prefix+' molded white shell',(0,0,.91),(2.1,.95,1.35),'white',.18)
    _round(prefix+' broad inset face',(.025,-.477,.94),(1.89,.025,1.08),'white',.115)
    _round(prefix+' black recessed rounded end',(-1.047,0,.92),(.022,.68,1.04),'black',.15)
    _round(prefix+' end glass',(-1.061,-.01,.97),(.025,.50,.78),'screen',.105)
    _round(prefix+' end rubber surround',(-1.056,0,.44),(.035,.56,.055),'rubber',.02)
    box(prefix+' chassis',(0,0,.216),(1.85,.72,.15),'iron',.035)
    # A raised top lip and bottom service door make the rounded shell read as manufactured.
    curve(prefix+' lid seam',[(-.91,-.435,1.44),(-.6,-.479,1.515),(.5,-.479,1.515),(.96,-.421,1.44)],.007,'cream')
    box(prefix+' lower service seam',(.07,-.493,.455),(1.72,.008,.009),'cream',0)
    for x in [-.78,.78]:
        for y in [-.31,.31]:
            box(prefix+' caster fork',(x,y,.165),(.095,.075,.14),'silver',.008)
            cyl(prefix+' caster wheel',(x,y-.014,.102),.10,.056,'rubber',20,(pi/2,0,0))
            cyl(prefix+' wheel hub',(x,y-.045,.102),.037,.012,'rust',12,(pi/2,0,0))
    # Teal gradient diamonds from reference 04, intentionally geometry rather than decals.
    verts,faces=[],[]
    for col in range(5):
        for row in range(11):
            x=.60+col*.075; z=.49+row*.081+(col%2)*.038
            r=.008+col*.008
            n=len(verts);verts += [(x-r,-.495,z),(x,-.495,z+r),
                                  (x+r,-.495,z),(x,-.495,z-r)]
            faces.append((n+3,n+2,n+1,n))
    mesh(prefix+' teal diamond pattern',verts,faces,'teal')
    text_obj(prefix+' wordmark','充电站',(-.12,-.502,.96),.135,'iron')
    text_obj(prefix+' power icon','↯',(-.44,-.502,.96),.18,'teal')
    text_obj(prefix+' serial','E-0%d'%index,(.38,-.504,.38),.048,'iron')
    _front_label(prefix+' original safety sticker',.73,-.502,1.415,.24,.095,
                 [(.264,.467),(.305,.470),(.303,.493),(.264,.490)],4)
    _wear(prefix+' chipped lower enamel',-.9,.9,-.505,.30,.38,26,44+index,'cream')
    _wear(prefix+' dark lower dirt',-.95,.90,-.506,.275,.315,18,71+index,'soil')
    # Narrow louvers on the back and stainless push handle on the end.
    for z in [.59,.66,.73,.80,.87]:
        box(prefix+' rear ventilation',(0,.479,z),(.70,.012,.018),'iron',0)
    curve(prefix+' end push handle',[(1.046,-.16,.77),(1.095,-.16,.80),
          (1.095,.16,.80),(1.046,.16,.77)],.025,'silver')


def _gun(name, p, tilted=False):
    x,y,z=p
    _round(name+' ivory connector',(x,y,z),(.13,.095,.18),'white',.032,
           (0,.18 if tilted else -.18,0))
    beam(name+' black handle',(x,y,z-.065),(x+.055,y-.015,z-.25),.043,'rubber',10)
    beam(name+' trigger',(x+.02,y-.05,z-.07),(x+.065,y-.05,z-.15),.013,'silver',8)
    cyl(name+' socket collar',(x,y+.06,z+.015),.054,.062,'iron',16,(pi/2,0,0))


def _charger(index):
    p='Fast charger %02d'%index
    _round(p+' plinth',(0,0,.08),(.48,.43,.16),'concrete_dark',.045)
    _round(p+' silver pillar',(0,0,1.00),(.25,.23,1.83),'silver',.055)
    _round(p+' black front console',(0,-.126,1.46),(.197,.026,.64),'black',.033)
    box(p+' display',(0,-.144,1.49),(.132,.014,.15),'screen',.012)
    text_obj(p+' display digits','%02d : 00'%(14+index),(0,-.156,1.505),.034,'light_cyan')
    box(p+' cyan status bar',(0,-.146,1.257),(.116,.015,.026),'light_cyan' if index!=2 else 'screen',.008)
    text_obj(p+' identification','CHARGE', (0,-.149,1.705),.030,'white')
    text_obj(p+' station number','0%d'%index,(0,-.14,1.185),.047,'iron')
    _round(p+' cable holster',(0,-.148,1.045),(.17,.065,.13),'iron',.025)
    _gun(p+' parked charging gun',(0,-.23,1.02))
    # Thick cable has a genuine low sag and a broad loop lying across the concrete.
    curve(p+' heavy hanging cable',[(.06,-.06,.48),(.17,-.30,.14),
          (.55,-.68,.062),(.44,-1.11,.061),(-.28,-1.19,.058),
          (-.49,-.88,.06),(-.20,-.42,.32),(.055,-.23,.78)],.026,'rubber')
    curve(p+' supply conduit',[(0,.12,.24),(0,.25,.13),(.32,.31,.085),(.65,.31,.085)],.021,'iron')
    _bolts(p,[(x,-.224,.103) for x in [-.18,.18]])
    _wear(p+' worn lower face',-.09,.09,-.121,.23,.45,9,index+90)


def _wheel_stop(index):
    p='Lane %02d wheel stop'%index
    # Long, low rubber barrier with tapered ends and applied yellow sections.
    verts=[(-.96,-.10,.04),(.96,-.10,.04),(.96,.10,.04),(-.96,.10,.04),
           (-.82,-.085,.16),(.82,-.085,.16),(.82,.085,.16),(-.82,.085,.16)]
    mesh(p+' solid stop',verts,[(0,3,2,1),(4,5,6,7),(0,1,5,4),
          (1,2,6,5),(2,3,7,6),(3,0,4,7)],'rubber')
    for x in [-.67,0,.67]:
        box(p+' yellow reflector',(x,0,.163),(.38,.172,.014),'yellow',.006)
        box(p+' yellow front marking',(x,-.097,.105),(.37,.012,.077),'yellow',.005)
    for x in [-.80,.80]:
        cyl(p+' floor anchor',(x,0,.174),.024,.013,'rust',8)


def _vending():
    p='Green vending machine'
    glass=_clear_glass()
    _round(p+' main steel body',(0,0,1.02),(1.20,.77,1.99),'teal',.052)
    for x in [-.565,.565]:
        box(p+' forward cabinet side',(x,-.503,1.02),(.07,.258,1.96),'teal',.016)
    box(p+' forward cabinet roof',(0,-.503,1.985),(1.16,.258,.065),'teal',.014)
    box(p+' interior dark back',(-.115,-.397,1.17),(.89,.015,1.43),'black',.004)
    # Side and front door frames surround an open shelf volume with explicit products.
    for x in [-.565,.376]:
        box(p+' white door stile',(x,-.647,1.16),(.07,.10,1.64),'white',.02)
    for z in [.36,1.96]:
        box(p+' door crossbar',(-.09,-.651,z),(.99,.1,.073),'white',.018)
    _round(p+' payment fascia',(.476,-.63,1.18),(.19,.11,1.63),'white',.025)
    box(p+' payment screen',(.48,-.694,1.55),(.145,.019,.24),'screen',.006)
    text_obj(p+' screen copy','扫码',(.48,-.708,1.57),.055,'light_cyan')
    box(p+' coin slot',(.478,-.704,1.31),(.10,.018,.016),'black',.003)
    box(p+' card reader',(.478,-.702,1.20),(.117,.020,.088),'iron',.006)
    cyl(p+' payment button',(.48,-.72,1.035),.03,.01,'light_cyan',12,(pi/2,0,0))
    # Small original QR instruction region; no screenshot is used for the whole appliance.
    _front_label(p+' QR paper',.48,-.714,1.80,.132,.165,
                 [(.789,.091),(.840,.112),(.828,.179),(.785,.162)],2)
    rng=random.Random(234)
    shelf_heights=[.53,.77,1.02,1.27,1.53,1.78]
    for row,z in enumerate(shelf_heights):
        box(p+' shelf %d'%row,(-.10,-.45,z),(.86,.36,.025),'silver',.007)
        box(p+' shelf price rail %d'%row,(-.10,-.635,z+.013),(.86,.02,.035),'white',.003)
        for c in range(5):
            x=-.46+c*.174
            # Several stalls are empty; coils remain visible to show abandonment.
            points=[]
            for k in range(35):
                a=k/34*pi*5
                points.append((x+.053*cos(a),-.47-k/34*.13,z+.075+.053*sin(a)))
            curve(p+' dispensing coil %d %d'%(row,c),points,.0043,'iron')
            if (row,c) in {(0,1),(1,4),(2,0),(2,3),(3,2),(4,3),(5,1),(5,4)}:
                continue
            col=['teal','yellow','red','blue','white'][(row+c)%5]
            if row<2:
                cyl(p+' drink can %d %d'%(row,c),(x,-.507,z+.10),.052,.175,col,16)
                cyl(p+' can lid %d %d'%(row,c),(x,-.507,z+.19),.051,.009,'silver',16)
                box(p+' can label %d %d'%(row,c),(x,-.563,z+.105),(.055,.008,.062),'cream',.002)
            elif row<4:
                _round(p+' snack package %d %d'%(row,c),(x,-.51,z+.115),(.13,.07,.19),col,.018,
                       (0,rng.uniform(-.12,.12),rng.uniform(-.10,.10)))
                box(p+' snack label %d %d'%(row,c),(x,-.552,z+.13),(.088,.008,.065),'cream',.002)
            else:
                cyl(p+' noodle cup %d %d'%(row,c),(x,-.51,z+.102),.058,.16,col,16,radius_top=.073)
                cyl(p+' noodle lid %d %d'%(row,c),(x,-.51,z+.187),.077,.011,'red',16)
                text_obj(p+' noodle text %d %d'%(row,c),'面',(x,-.575,z+.115),.072,'white')
            text_obj(p+' stock code %d %d'%(row,c),'%d%d'%(row,c),(x,-.649,z+.015),.022,'iron')
    # One damaged light, one working light; glass sits ahead of true shelf geometry.
    box(p+' working shelf light',(.324,-.63,1.16),(.020,.021,1.39),'light_cyan',.008)
    box(p+' failed shelf light',(-.525,-.63,1.31),(.016,.018,1.08),'white',.003)
    box(p+' front glass',(-.10,-.664,1.18),(.86,.008,1.49),glass,0)
    curve(p+' glass crack',[(-.35,-.672,1.77),(-.29,-.672,1.62),(-.33,-.672,1.51),(-.23,-.672,1.42)],.0018,'white')
    curve(p+' glass crack fork',[(-.29,-.672,1.62),(-.18,-.672,1.60),(-.14,-.672,1.56)],.0013,'white')
    box(p+' green lower fascia',(0,-.634,.205),(1.12,.07,.285),'teal',.015)
    _round(p+' collection door',(-.09,-.679,.21),(.89,.028,.225),'cream',.012)
    box(p+' dark pickup flap',(-.09,-.70,.215),(.78,.018,.15),'black',.015)
    text_obj(p+' pickup text','取 货 口',(-.09,-.719,.215),.068,'cream')
    text_obj(p+' header','自助补给',(-.09,-.654,2.005),.085,'cream')
    for x in [-.46,.46]:
        for y in [-.24,.24]:cyl(p+' adjustable feet',(x,y,.04),.05,.07,'rubber',12)
    for z in [.18,.23,.28]:box(p+' right side ventilation',(.604,.05,z),(.01,.38,.012),'black',0)
    _wear(p+' lower white paint chips',-.55,.55,-.676,.053,.13,33,19,'cream')
    _wear(p+' door edge rust',-.565,-.54,-.700,.42,1.91,18,47)
    curve(p+' trailing plug cord',[(.4,.31,.15),(.52,.57,.055),(.2,.84,.048),(-.04,.82,.049)],.01,'rubber')


def _freezer():
    p='Red ice cream freezer'
    glass=_clear_glass()
    _round(p+' red outer shell',(0,0,.49),(1.20,.79,.92),'red',.09)
    box(p+' cream interior',(0,0,.76),(1.05,.64,.31),'cream',.03)
    box(p+' dark inner well',(0,-.01,.87),(.97,.55,.04),'glass',.015)
    for x in [-.285,.285]:
        _round(p+' lid surround',(x,-.015,.958),(.57,.71,.055),'silver',.023)
        box(p+' sliding glass lid',(x,-.02,.992),(.49,.62,.012),glass,.01)
        box(p+' glass rim front',(x,-.358,1.0),(.565,.025,.035),'red',.007)
        box(p+' lid handle',(x,-.256,1.028),(.13,.027,.034),'white',.008)
    box(p+' center slide track',(0,-.015,1.005),(.024,.70,.026),'red',.005)
    # Visible sparse frozen packages below transparent lids.
    for i,(x,y) in enumerate([(-.33,-.13),(-.20,.13),(.25,.15),(.37,-.12)]):
        box(p+' forgotten ice lolly wrapper',(x,y,.91),(.15,.25,.025),['yellow','red','cream','blue'][i],.01,rot=(0,0,i*.3))
    _round(p+' illuminated advert backboard',(0,.335,1.27),(1.18,.11,.66),'red',.035)
    _front_label(p+' original menu advertising',0,.270,1.295,1.02,.49,
                 [(.236,.296),(.480,.300),(.517,.430),(.282,.454)],3)
    # Advertising copied by UV directly from the reference photo, including weathering.
    _front_label(p+' original front illustration',0,-.404,.51,1.035,.71,
                 [(.268,.521),(.625,.660),(.508,.854),(.300,.737)],3)
    text_obj(p+' menu header','冰 淇 淋',(0,.259,1.595),.078,'cream')
    for x in [-.47,.47]:
        for y in [-.26,.26]:
            cyl(p+' castor',(x,y,.063),.060,.038,'rubber',12,(pi/2,0,0))
    for z in [.18,.22,.26,.30]:box(p+' compressor grille',(-.605,.10,z),(.012,.32,.012),'black',0)
    _wear(p+' chipped red bottom',-.48,.46,-.413,.085,.16,21,96,'cream')
    curve(p+' unplugged lead',[(.42,.34,.23),(.64,.48,.065),(.78,.27,.045),(.72,.02,.045)],.009,'rubber')
    box(p+' plug',(.72,.01,.047),(.06,.045,.025),'black',.005)


def _ac_charger():
    p='White AC charger'
    box(p+' base',(0,0,.065),(.44,.37,.13),'concrete_dark',.02)
    box(p+' narrow silver upright',(0,0,.76),(.18,.13,1.4),'silver',.018)
    _round(p+' rounded white head',(0,-.025,1.49),(.43,.25,.59),'white',.115)
    _round(p+' black face',(0,-.155,1.56),(.265,.026,.34),'black',.075)
    box(p+' screen',(0,-.176,1.59),(.18,.014,.10),'screen',.007)
    text_obj(p+' charge screen','7.0 kW',(0,-.185,1.59),.039,'light_cyan')
    for i in range(3):
        cyl(p+' indicator',(-.055+i*.055,-.181,1.69),.008,.01,'light_cyan' if i==0 else 'red',10,(pi/2,0,0))
    for x in [-.135,.135]:cyl(p+' case screw',(x,-.155,1.28),.01,.01,'iron',8,(pi/2,0,0))
    _gun(p+' holstered plug',(.17,-.12,.69),True)
    curve(p+' draped cable',[(0,-.11,1.21),(.025,-.18,.87),(-.14,-.27,.35),
          (-.31,-.42,.07),(.22,-.67,.055),(.37,-.39,.08),(.225,-.12,.49)],.017,'rubber')
    text_obj(p+' post marking','交流充电',(0,-.077,.43),.057,'teal')


def _electrical_cabinet():
    p='Stainless electrical cabinet'
    box(p+' concrete foot',(0,0,.045),(.73,.35,.09),'concrete',.012)
    _round(p+' steel housing',(0,0,.52),(.76,.34,.98),'silver',.025)
    # A slightly skewed outer door, with hinge cylinders and latch, communicates wear.
    _round(p+' misaligned door',(0,-.191,.51),(.698,.035,.90),'silver',.012,rot=(0,-.018,-.026))
    box(p+' overhanging rain cap',(0,0,1.032),(.83,.40,.045),'silver',.017)
    for z in [.23,.79]:cyl(p+' left hinge',(-.347,-.22,z),.023,.10,'iron',10)
    box(p+' latch',(.278,-.228,.47),(.095,.018,.028),'cream',.003)
    # Explicit hazard symbol remains readable independently of any texture.
    tri=[(-.126,-.237,.46),(.126,-.237,.46),(0,-.237,.69)]
    mesh(p+' warning triangle',tri,[(0,1,2)],'red')
    mesh(p+' warning triangle interior',[(-.092,-.241,.478),(.092,-.241,.478),(0,-.241,.655)],[(0,1,2)],'silver')
    mesh(p+' lightning hazard',[(.020,-.245,.626),(-.044,-.245,.545),(.001,-.245,.553),
          (-.019,-.245,.496),(.048,-.245,.581),(.006,-.245,.575)],[(0,1,2,3,4,5)],'red')
    text_obj(p+' warning copy','有电危险',(0,-.249,.415),.075,'red')
    _wear(p+' door oxidation',-.3,.3,-.247,.080,.16,12,777)
    for x in [-.18,.05,.22]:
        curve(p+' outgoing conduit',[(x,.1,.13),(x,.2,.055),(x,.5,.049)],.018,'iron')


def _exercise_bike():
    p='Abandoned exercise bicycle'
    # Bike's longitudinal axis is local X; wheels spin in XZ plane, axle along Y.
    for x in [-.55,.55]:
        beam(p+' transverse floor stabilizer',(x,-.32,.10),(x,.32,.10),.044,'iron',12)
        for y in [-.33,.33]:cyl(p+' stabilizer rubber cap',(x,y,.10),.052,.065,'rubber',12,(pi/2,0,0))
    beam(p+' lower spine',(-.52,0,.13),(.53,0,.13),.047,'iron',10)
    beam(p+' saddle upright',(-.45,0,.13),(-.39,0,.79),.056,'iron',10)
    beam(p+' handle upright',(.47,0,.15),(.50,0,1.10),.055,'iron',10)
    beam(p+' rear diagonal',(-.45,0,.68),(.10,0,.27),.043,'iron',10)
    beam(p+' main diagonal',(-.39,0,.21),(.47,0,.85),.045,'iron',10)
    _round(p+' chain case',(-.05,0,.36),(.69,.19,.30),'black',.115)
    cyl(p+' flywheel',(.38,0,.42),.28,.19,'iron',32,(pi/2,0,0))
    torus(p+' flywheel rim',(.38,-.104,.42),.24,.009,'silver',(pi/2,0,0))
    cyl(p+' crank boss',(-.29,-.12,.35),.087,.06,'silver',20,(pi/2,0,0))
    for y,sgn in [(-.17,1),(.17,-1)]:
        beam(p+' crank arm',(-.29,y,.35),(-.29+.08*sgn,y,.35-.18*sgn),.019,'silver',8)
        box(p+' pedal',(-.29+.08*sgn,y+(.07 if y>0 else -.07),.35-.18*sgn),(.12,.16,.045),'rubber',.013)
    beam(p+' saddle chrome post',(-.40,0,.73),(-.40,0,.94),.030,'silver',12)
    _round(p+' damaged saddle',(-.44,0,.94),(.32,.24,.095),'rubber',.05)
    _wear(p+' saddle fabric tear',-.50,-.37,-.125,.916,.952,6,3,'cream')
    curve(p+' handlebar',[ (.49,-.24,1.18),(.51,-.31,1.09),(.48,-.23,.99),
          (.48,.23,.99),(.51,.31,1.09),(.49,.24,1.18)],.027,'rubber')
    _round(p+' dead digital console',(.43,0,1.105),(.19,.20,.055),'black',.018,rot=(0,-.30,0))
    box(p+' console LCD',(.415,-.006,1.137),(.115,.123,.008),'screen',.004,rot=(0,-.30,0))
    cyl(p+' resistance knob',(.10,0,.71),.037,.065,'red',16)
    curve(p+' loose sensor wire',[(-.28,-.13,.35),(-.14,-.15,.55),(.36,-.10,.98),(.43,0,1.10)],.004,'black')
    text_obj(p+' flywheel logo','FITNESS',(.31,-.105,.41),.064,'cream')


def _scooter(index):
    p='Parked electric scooter %02d'%index
    col='teal' if index==1 else 'cream'
    for x in [-.52,.52]:
        torus(p+' tyre',(x,0,.25),.19,.053,'rubber',(pi/2,0,0))
        cyl(p+' wheel disc',(x,0,.25),.147,.09,'iron',20,(pi/2,0,0))
        cyl(p+' wheel hub',(x,-.060,.25),.055,.020,'silver',12,(pi/2,0,0))
        for a in range(0,360,60):
            ang=a*pi/180
            beam(p+' spoke',(x,-.055,.25),(x+.135*cos(ang),-.055,.25+.135*sin(ang)),.010,'silver',6)
    _round(p+' deck',(-.10,0,.29),(.78,.31,.105),'iron',.03)
    _round(p+' body panel',(-.38,0,.48),(.48,.35,.27),col,.09)
    beam(p+' saddle post',(-.37,0,.50),(-.37,0,.79),.034,'silver',10)
    _round(p+' saddle',(-.36,0,.80),(.47,.34,.115),'black',.055)
    beam(p+' front fork',(.52,0,.25),(.41,0,.69),.03,'silver',10)
    _round(p+' steering shield',(.40,0,.68),(.12,.37,.55),col,.053,rot=(0,-.11,0))
    beam(p+' steering tube',(.4,0,.63),(.35,0,1.03),.023,'iron',10)
    beam(p+' handlebar',(.35,-.30,1.03),(.35,.30,1.03),.021,'iron',10)
    for y in [-.26,.26]:beam(p+' hand grip',(.35,y-.055,1.03),(.35,y+.055,1.03),.029,'rubber',10)
    _round(p+' headlamp',(.477,0,.88),(.065,.19,.11),'cream',.03)
    for y in [-.18,.18]:
        beam(p+' mirror stalk',(.35,y,1.04),(.30,y*1.48,1.22),.010,'iron',8)
        ico(p+' mirror',(.30,y*1.48,1.24),(.07,.035,.045),'silver',2)
    curve(p+' kickstand',[(-.13,0,.28),(-.13,-.23,.075),(-.02,-.27,.058)],.016,'iron')
    box(p+' rear cargo basket',(-.66,0,.75),(.29,.34,.24),'iron',.014)
    box(p+' basket dark opening',(-.66,0,.876),(.245,.292,.015),'black',.002)


def _service_bits():
    p='Service cluster clutter'
    # Concrete paver and empty foam tray from ref06; a few bottles are retained geometry.
    box(p+' broken foam tray',(-.4,0,.19),(.45,.34,.13),'white',.015)
    box(p+' tray recess',(-.4,0,.258),(.36,.26,.006),'cream',.008)
    box(p+' cardboard carton',(.28,.04,.17),(.36,.3,.31),'wood',.01,rot=(0,0,.16))
    for i in range(5):
        x=.11+i*.045;y=-.22-(i%2)*.09
        cyl(p+' discarded bottle',(x,y,.095),.024,.15,'glass',10,rot=(0,.75+i*.12,0))
        cyl(p+' bottle cap',(x+.054,y,.15),.015,.021,'blue',8,rot=(0,.75+i*.12,0))
    curve(p+' loose extension cord',[(-.64,-.18,.048),(-.79,-.63,.045),
          (-.42,-.82,.045),(.08,-.71,.045),(.42,-.47,.045)],.008,'rubber')


def build():
    """Populate left charging canopy and the front service area."""
    for i,y in enumerate([3.0,7.5,12.0],1):
        _assembly('充电区 / White pod %02d'%i,(-10,y,0),pi/2,lambda i=i:_pod(i))
        pedestal=_assembly('充电区 / Fast pedestal %02d'%i,(-10,y+1.58,0),pi/2,lambda i=i:_charger(i))
        pedestal.scale.z=1.13
        _assembly('充电区 / Wheel stop %02d'%i,(-7.10,y,0),pi/2,lambda i=i:_wheel_stop(i))
    _assembly('生活区 / Green vending',(-9.8,-3.5,0),pi/2,_vending)
    _assembly('生活区 / Red freezer',(-9.75,-1.8,0),pi/2,_freezer)
    _assembly('生活区 / AC charger',(-9.7,.2,0),pi/2,_ac_charger)
    _assembly('生活区 / Electrical cabinet',(-9.90,-.65,0),pi/2,_electrical_cabinet)
    _assembly('生活区 / Exercise bike',(-8.10,-.85,0),.32,_exercise_bike)
    _assembly('生活区 / Small clutter',(-9.3,-.20,0),pi/2,_service_bits)
    _assembly('办公室 / Scooter 01',(7.55,-4.9,0),-.31,lambda:_scooter(1))
    _assembly('办公室 / Scooter 02',(9.55,-4.65,0),-.12,lambda:_scooter(2))

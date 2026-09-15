"""Editable, hand-shaped Venetian landmarks for a polished miniature city.

The public constructors build around a local XY origin, with ground at Z=0
and the principal facade facing -Y.  The caller selects the collection.
"""
import math
import bpy
from scene_utils import mat, cube, cyl, mesh, curve, sphere, group_objects


def _materials():
    return {
        'ivory': mat('Landmarks | warm Istrian limestone', (0.91, 0.79, 0.58)),
        'white': mat('Landmarks | pale carved stone', (0.98, 0.90, 0.72)),
        'rose': mat('Landmarks | dusty pink marble', (0.66, 0.33, 0.28)),
        'pink': mat('Landmarks | palace rose plaster', (0.87, 0.54, 0.44)),
        'lightpink': mat('Landmarks | diamond blush marble', (0.99, 0.75, 0.62)),
        'brick': mat('Landmarks | campanile burnt brick', (0.55, 0.20, 0.11)),
        'bricklight': mat('Landmarks | terracotta pilasters', (0.68, 0.29, 0.15)),
        'brickdark': mat('Landmarks | brick inset', (0.39, 0.13, 0.085)),
        'roof': mat('Landmarks | old terracotta roof', (0.48, 0.17, 0.09)),
        'rooflight': mat('Landmarks | tile ridge highlight', (0.67, 0.27, 0.13)),
        'copper': mat('Landmarks | patinated copper domes', (0.18, 0.40, 0.39), 0.48, 0.25),
        'copperlight': mat('Landmarks | copper raised ribs', (0.30, 0.53, 0.49), 0.45, 0.30),
        'gold': mat('Landmarks | aged gilded details', (0.92, 0.61, 0.19), 0.32, 0.65),
        'dark': mat('Landmarks | deep arcade shadow', (0.075, 0.105, 0.105)),
        'glass': mat('Landmarks | blue black leaded glass', (0.09, 0.21, 0.23), 0.30, 0.18),
        'bronze': mat('Landmarks | bronze bells', (0.23, 0.16, 0.075), 0.34, 0.60),
        'wood': mat('Landmarks | carved walnut doors', (0.22, 0.10, 0.055)),
    }


def _profile(name, points, y, depth, material):
    """Extrude an XZ outline along Y; no boolean modifiers required."""
    n = len(points)
    verts = [(x, y-depth/2, z) for x, z in points]
    verts += [(x, y+depth/2, z) for x, z in points]
    faces = [tuple(range(n)), tuple(reversed(range(n, n*2)))]
    faces += [(i, (i+1) % n, (i+1) % n+n, i+n) for i in range(n)]
    return mesh(name, verts, faces, material)


def _arch(name, x, y, spring, radius, width, depth, material, segments=20):
    """A real open arch, as a single editable annular mesh."""
    verts = []
    for yy in (y-depth/2, y+depth/2):
        for r in (radius, radius+width):
            verts += [(x+r*math.cos(i*math.pi/segments), yy,
                       spring+r*math.sin(i*math.pi/segments))
                      for i in range(segments+1)]
    k = segments+1
    faces = []
    for i in range(segments):
        faces.extend([(i, i+1, k+i+1, k+i),
                      (2*k+i, 3*k+i, 3*k+i+1, 2*k+i+1),
                      (i, 2*k+i, 2*k+i+1, i+1),
                      (k+i, k+i+1, 3*k+i+1, 3*k+i)])
    faces += [(0, k, 3*k, 2*k), (k-1, 3*k-1, 4*k-1, 2*k-1)]
    return mesh(name, verts, faces, material)


def _arched_panel(name, x, y, bottom, spring, radius, depth, material):
    points = [(x-radius, bottom), (x+radius, bottom)]
    points += [(x+radius*math.cos(i*math.pi/18), spring+radius*math.sin(i*math.pi/18))
               for i in range(19)]
    return _profile(name, points, y, depth, material)


def _spandrel(name, x, y, spring, radius, top, depth, material):
    """Wall above an open arch, bounded by a horizontal cornice."""
    points = [(x-radius, top), (x+radius, top), (x+radius, spring)]
    points += [(x+radius*math.cos(i*math.pi/18), spring+radius*math.sin(i*math.pi/18))
               for i in range(1, 19)]
    return _profile(name, points, y, depth, material)


def _column(name, x, y, bottom, top, radius, m):
    cyl(name+' shaft', (x, y, (bottom+top)/2), radius, top-bottom, m['white'], 12)
    cube(name+' square base', (x, y, bottom+0.08), (radius*2.7, radius*2.7, 0.16), m['ivory'], 0.018)
    cyl(name+' capital neck', (x, y, top-0.045), radius*1.28, 0.16, m['ivory'], 12)
    cube(name+' capital', (x, y, top+0.065), (radius*3.0, radius*3.0, 0.15), m['white'], 0.018)


def _spin_since(before, angle):
    if not angle:
        return
    c, s = math.cos(angle), math.sin(angle)
    for ob in bpy.data.objects:
        if ob not in before:
            x, y = ob.location.x, ob.location.y
            ob.location.x, ob.location.y = c*x-s*y, s*x+c*y
            ob.rotation_euler[2] += angle


def _lathe(name, x, y, profile, material, segments=32):
    verts = [(x+r*math.cos(i*math.tau/segments), y+r*math.sin(i*math.tau/segments), z)
             for r, z in profile for i in range(segments)]
    faces = [tuple(reversed(range(segments)))]
    for j in range(len(profile)-1):
        for i in range(segments):
            a = j*segments+i
            b = j*segments+(i+1) % segments
            faces.append((a, b, b+segments, a+segments))
    faces.append(tuple(range((len(profile)-1)*segments, len(profile)*segments)))
    ob = mesh(name, verts, faces, material)
    for p in ob.data.polygons:
        p.use_smooth = len(p.vertices) == 4
    return ob


def _disc(name, x, y, z, radius, thickness, material, vertices=32):
    ob = cyl(name, (x, y, z), radius, thickness, material, vertices)
    ob.rotation_euler[0] = math.pi/2
    return ob


def _finial(name, x, y, bottom, size, m, cross=True):
    cyl(name+' gilded pin', (x, y, bottom+size*0.46), size*0.055, size*0.92, m['gold'], 10)
    sphere(name+' gold orb', (x, y, bottom+size*0.20), (size*0.16,)*3, m['gold'], 12, 6)
    if cross:
        cube(name+' crossbar', (x, y, bottom+size*0.74), (size*0.44, size*0.07, size*0.065), m['gold'], 0.005)


def _dome(name, x, y, bottom, radius, height, m):
    cyl(name+' octagonal drum', (x, y, bottom+0.55), radius*0.87, 1.1, m['ivory'], 16)
    cyl(name+' drum cornice', (x, y, bottom+1.10), radius*1.03, 0.22, m['white'], 32)
    profile = [(radius*f, bottom+1.10+height*h) for f, h in
               [(1.02, 0.0), (1.04, .09), (1.0, .28), (.87, .53), (.67, .75), (.36, .93), (.07, 1.02)]]
    _lathe(name+' copper shell', x, y, profile, m['copper'])
    for i in range(12):
        a = i*math.tau/12
        curve(name+' standing seam', [(x+(r+0.015)*math.cos(a), y+(r+0.015)*math.sin(a), z+0.015)
                                     for r, z in profile], 0.022, m['copperlight'])
    for i in range(8):
        a = i*math.tau/8
        ob = cube(name+' drum dark window', (x+radius*.875*math.cos(a), y+radius*.875*math.sin(a), bottom+.53),
                  (.30, .065, .57), m['glass'], .04)
        ob.rotation_euler[2] = a-math.pi/2
    _finial(name, x, y, profile[-1][1], .72 if radius>2 else .60, m)


def create_campanile(name, loc, rotation=0):
    """Tall warm-brick campanile, open cream belfry, verdigris spire."""
    before = set(bpy.data.objects)
    m = _materials()
    cube('Campanile lower step', (0, 0, .14), (3.80, 3.80, .28), m['ivory'], .035)
    cube('Campanile upper step', (0, 0, .36), (3.52, 3.52, .20), m['white'], .025)
    cube('Campanile brick shaft', (0, 0, 8.77), (3.02, 3.02, 16.62), m['brick'], .025)
    for angle in (0, math.pi/2, math.pi, math.pi*1.5):
        face_before = set(bpy.data.objects)
        for x in (-1.37, 1.37):
            cube('Campanile raised corner pilaster', (x, -1.54, 8.85), (.21, .13, 16.78), m['bricklight'], .012)
        for x in (-.91, 0, .91):
            cube('Campanile long recessed panel', (x, -1.520, 7.87), (.58, .045, 13.54), m['brickdark'])
            cube('Campanile sunlit panel edge', (x-.28, -1.555, 7.87), (.055, .055, 13.60), m['bricklight'])
            _arch('Campanile panel crown', x, -1.553, 14.66, .29, .06, .065, m['bricklight'], 12)
        cube('Campanile lion tablet surround', (0, -1.59, 15.96), (1.38, .16, 1.05), m['ivory'], .035)
        _disc('Campanile gold civic medallion', 0, -1.695, 15.96, .37, .045, m['gold'])
        # A small winged-lion-like sculptural relief, deliberately simplified.
        sphere('Campanile carved lion body', (0, -1.744, 15.93), (.23, .065, .105), m['white'], 12, 6)
        _profile('Campanile carved relief wing', [(-.17, 15.95), (-.36, 16.16), (.05, 16.10), (.13, 15.94)], -1.75, .06, m['white'])
        _spin_since(face_before, angle)
    for z, side, h in ((16.98, 3.29, .18), (17.17, 3.63, .22), (17.36, 3.78, .16)):
        cube('Campanile belfry sill cornice', (0, 0, z), (side, side, h), m['white'], .025)
    # Nothing fills this storey: all four sides are genuinely open.
    for x, y in ((-1.43,-1.43), (0,-1.43), (1.43,-1.43),
                 (-1.43,0), (1.43,0), (-1.43,1.43), (0,1.43), (1.43,1.43)):
        _column('Campanile belfry pier', x, y, 17.45, 19.38, .155, m)
    for angle in (0, math.pi/2, math.pi, math.pi*1.5):
        face_before = set(bpy.data.objects)
        for x in (-.715, .715):
            _arch('Campanile open belfry arch', x, -1.43, 19.36, .56, .20, .32, m['white'])
            _spandrel('Campanile arch spandrel', x, -1.43, 19.36, .76, 20.18, .32, m['ivory'])
        _spin_since(face_before, angle)
    cube('Campanile bell support beam', (0, 0, 19.78), (2.55, .28, .26), m['wood'], .025)
    _lathe('Campanile hanging bronze bell', 0, 0, [(.67,18.17), (.72,18.27), (.54,18.46), (.39,19.00), (.25,19.25), (.07,19.30)], m['bronze'], 24)
    cyl('Campanile bell hanging rod', (0,0,19.48), .065, .50, m['bronze'], 10)
    sphere('Campanile bell clapper', (0,0,18.13), (.11,.11,.18), m['bronze'], 12, 6)
    cube('Campanile upper belfry fascia', (0,0,20.25), (3.46,3.46,.20), m['ivory'], .025)
    cube('Campanile roof projecting cornice', (0,0,20.45), (3.80,3.80,.20), m['white'], .025)
    cube('Campanile copper roof skirt', (0,0,20.59), (3.55,3.55,.11), m['copper'])
    mesh('Campanile four sided copper spire', [(-1.77,-1.77,20.64),(1.77,-1.77,20.64),(1.77,1.77,20.64),(-1.77,1.77,20.64),(0,0,23.48)],
         [(0,3,2,1),(0,1,4),(1,2,4),(2,3,4),(3,0,4)], m['copper'])
    for x,y in ((-1.77,-1.77),(1.77,-1.77),(1.77,1.77),(-1.77,1.77)):
        curve('Campanile roof copper hip', [(x,y,20.67),(0,0,23.49)], .025, m['copperlight'])
    _finial('Campanile gold weather finial', 0, 0, 23.48, .72, m, cross=False)
    return group_objects(name, before, loc, rotation)


def create_basilica(name, loc, rotation=0):
    """Five-domed Venetian Byzantine basilica with a richly layered west front."""
    before = set(bpy.data.objects)
    m = _materials()
    cube('Basilica broad lowest step', (0,-.05,.15), (12.3,12.1,.30), m['ivory'], .055)
    cube('Basilica second step', (0,-.05,.39), (11.94,11.8,.18), m['white'], .035)
    cube('Basilica main nave stone volume', (0,.50,3.76), (10.50,10.05,6.55), m['ivory'], .06)
    cube('Basilica rear apse', (0,5.0,3.51), (6.10,1.70,6.05), m['ivory'], .12)
    cube('Basilica low rose plinth', (0,.50,.72), (10.65,10.17,.42), m['rose'], .02)
    cube('Basilica roof terrace', (0,.50,7.08), (11.08,10.56,.32), m['white'], .035)
    cube('Basilica central crossing', (0,.75,8.11), (5.12,5.4,1.82), m['ivory'], .045)
    cube('Basilica crossing cornice', (0,.75,9.04), (5.35,5.64,.22), m['white'], .025)
    # The five deep portals stand in front of the main mass.
    portal_x = (-4.48,-2.26,0,2.26,4.48)
    for i, x in enumerate(portal_x):
        radius = 1.03 if i == 2 else .86
        spring = 3.50 if i == 2 else 3.22
        _arched_panel('Basilica shadowed portal recess', x,-4.62,.53,spring,radius,.10,m['dark'])
        _arched_panel('Basilica walnut arched doors', x,-4.69,.53,spring-.20,radius*.73,.08,m['wood'])
        cube('Basilica door center seam', (x,-4.74,1.86), (.04,.035,2.5), m['gold'])
        for dx in (-radius*.39,radius*.39):
            _disc('Basilica bronze door boss', x+dx,-4.762,1.85,.055,.04,m['gold'],12)
        for j, (offset, width, material) in enumerate(((0,.15,m['rose']),(.17,.12,m['white']),(.31,.11,m['ivory']))):
            _arch('Basilica portal layered archivolt', x,-5.09-j*.12,spring,radius+offset,width,.22,material,24)
        for side in (-1,1):
            for j in range(2):
                _column('Basilica portal marble column', x+side*(radius+.13+j*.22), -5.07-j*.16,.60,spring,.102,m)
        _spandrel('Basilica lower arcade spandrel', x,-5.07,spring,radius+.41,5.02,.37,m['ivory'])
        _finial('Basilica small portal crown',x,-5.30,spring+radius+.43,.38,m)
    cube('Basilica facade frieze rose band', (0,-5.16,5.17), (11.6,.60,.25), m['rose'], .02)
    cube('Basilica facade first cornice', (0,-5.25,5.37), (11.83,.79,.16), m['white'], .03)
    # Upper arches and marble roundels create the scalloped basilica silhouette.
    for i,x in enumerate(portal_x):
        r = 1.18 if i==2 else .96
        spring = 6.56 if i==2 else 6.09
        _arched_panel('Basilica upper arch gold mosaic field',x,-5.035,5.46,spring,r,.08,m['rose'])
        _arch('Basilica upper scalloped stone arch',x,-5.22,spring,r,.19,.26,m['white'],24)
        _arch('Basilica upper gold mosaic edging',x,-5.365,spring,r-.10,.035,.035,m['gold'],24)
        if i==2:
            _disc('Basilica central rose window stone rim',x,-5.115,6.38,.65,.09,m['white'])
            _disc('Basilica central rose window blue glass',x,-5.18,6.38,.53,.08,m['glass'])
            for j in range(12):
                a=j*math.tau/12
                curve('Basilica rose window tracery',[(x,-5.235,6.38),(x+.52*math.cos(a),-5.235,6.38+.52*math.sin(a))],.022,m['ivory'])
            _disc('Basilica rose window center',x,-5.25,6.38,.12,.04,m['gold'],16)
        else:
            _disc('Basilica upper mosaic gold medallion',x,-5.115,6.17,.39,.065,m['gold'])
            _disc('Basilica upper mosaic central stone',x,-5.155,6.17,.23,.05,m['ivory'],16)
        for sx in (-1,1):
            _column('Basilica upper facade slender column',x+sx*(r+.06),-5.23,5.47,spring,.072,m)
        # Crown carvings are small meshes rather than a texture.
        for j in range(7):
            a=(j+.5)*math.pi/7
            sphere('Basilica arch ornamental stone knop',(x+(r+.22)*math.cos(a),-5.22,spring+(r+.22)*math.sin(a)),(.075,.08,.11),m['white'],8,4)
        _finial('Basilica facade gilded cross',x,-5.22,spring+r+.25,.64 if i==2 else .48,m)
    # Side elevations: rose bands, buttresses and arched blue windows.
    for side in (-1,1):
        for yy in (-3.75,-1.4,1.0,3.4,5.20):
            cube('Basilica side carved buttress',(side*5.35,yy,3.70),(.37,.45,6.4),m['white'],.028)
            cube('Basilica buttress rose capital',(side*5.36,yy,6.4),(.50,.57,.22),m['rose'],.025)
        for yy in (-2.58,-.2,2.20,4.38):
            side_before=set(bpy.data.objects)
            _arched_panel('Basilica side arched blue glass',yy,-5.286,3.17,4.90,.46,.04,m['glass'])
            _arch('Basilica side window arch',yy,-5.32,4.90,.46,.12,.12,m['white'],16)
            for dx in (-.51,.51):
                cube('Basilica side window jamb',(yy+dx,-5.32,4.02),(.13,.12,1.75),m['white'])
            cube('Basilica side window central mullion',(yy,-5.36,4.25),(.065,.07,2.10),m['ivory'])
            _spin_since(side_before, math.pi/2 if side==1 else -math.pi/2)
        cube('Basilica side continuous rose frieze',(side*5.275,.55,2.46),(.075,9.90,.22),m['rose'])
    _dome('Basilica central great dome',0,.75,9.15,2.30,3.55,m)
    _dome('Basilica north dome',0,4.03,7.25,1.57,2.35,m)
    _dome('Basilica west dome',0,-2.92,7.26,1.70,2.57,m)
    _dome('Basilica left dome',-3.68,.76,7.26,1.73,2.63,m)
    _dome('Basilica right dome',3.68,.76,7.26,1.73,2.63,m)
    # Four modest pinnacles distinguish the corners from the larger domes.
    for x,y in ((-5.20,-4.6),(5.20,-4.6),(-5.20,5.0),(5.20,5.0)):
        cyl('Basilica corner pinnacle plinth',(x,y,7.29),.27,.55,m['white'],8)
        _lathe('Basilica corner copper pinnacle',x,y,[(.36,7.57),(.28,7.82),(.04,8.38)],m['copper'],12)
        _finial('Basilica corner pinnacle',x,y,8.38,.41,m)
    return group_objects(name,before,loc,rotation)


def _palace_diamonds(m):
    """One mesh for the inlaid facade diamonds, keeping the object count low."""
    verts, faces = [], []
    for row in range(6):
        z = 5.77+row*.48
        for col in range(20):
            x = -4.70+col*.49+(row%2)*.245
            if x>4.92:
                continue
            n=len(verts)
            verts.extend([(x-.20,-3.522,z),(x,-3.522,z+.205),(x+.20,-3.522,z),(x,-3.522,z-.205)])
            faces.append((n,n+1,n+2,n+3))
    return mesh('Palazzo individually modeled marble diamond inlay',verts,faces,m['lightpink'])


def create_palazzo(name, loc, rotation=0):
    """Rose palace with two open arcades and an ornate patterned upper facade."""
    before=set(bpy.data.objects)
    m=_materials()
    cube('Palazzo waterfront stone foundation',(0,0,.17),(10.40,7.35,.34),m['ivory'],.05)
    cube('Palazzo raised arcade floor',(0,0,.40),(10.18,7.14,.14),m['white'],.025)
    # The front 1.3 m of both storeys remains an open, accessible loggia.
    cube('Palazzo shaded arcade back wall',(0,.53,2.75),(9.8,5.75,4.6),m['rose'],.035)
    cube('Palazzo ground loggia ceiling',(0,0,3.38),(10.20,7.12,.24),m['white'],.025)
    cube('Palazzo upper loggia ceiling',(0,0,5.40),(10.20,7.12,.25),m['white'],.025)
    for floor, bottom, spring, top, bays, radius, colrad in ((0,.48,2.32,3.30,7,.585,.115),(1,3.53,4.58,5.33,14,.272,.065)):
        y=-3.25
        spacing=9.56/bays
        for i in range(bays+1):
            x=-4.78+i*spacing
            _column('Palazzo ground arcade pier' if floor==0 else 'Palazzo upper loggia column',x,y,bottom,spring,colrad,m)
        for i in range(bays):
            x=-4.78+(i+.5)*spacing
            _arch('Palazzo open arcade arch',x,y,spring,radius,.14 if floor==0 else .10,.32,m['white'],16)
            _spandrel('Palazzo arcade spandrel',x,y,spring,radius+.12,top,.34,m['ivory'])
            if floor==1:
                # A small four-lobed carved medallion above each slim arch.
                for a in (0,math.pi/2,math.pi,math.pi*1.5):
                    _disc('Palazzo quatrefoil dark inset',x+.055*math.cos(a),-3.433,5.11+.055*math.sin(a),.052,.02,m['dark'],10)
        if floor==0:
            for x in (-3.90,-1.30,1.30,3.90):
                _arched_panel('Palazzo shaded arcade doorway',x,-2.38,.48,1.82,.47,.035,m['dark'])
        else:
            cube('Palazzo upper loggia balustrade foot',(0,-3.35,3.64),(9.8,.30,.16),m['ivory'],.02)
            cube('Palazzo upper loggia balustrade rail',(0,-3.35,3.98),(9.8,.24,.10),m['white'],.02)
            for i in range(30):
                x=-4.67+i*9.34/29
                cyl('Palazzo balustrade spindle',(x,-3.35,3.82),.029,.27,m['white'],8)
    # An upper pink box with patterned marble and tall dark Gothic windows.
    cube('Palazzo pink upper walls',(0,0,7.07),(10.0,7.0,3.12),m['pink'],.035)
    _palace_diamonds(m)
    for x in (-3.75,-1.90,0,1.90,3.75):
        bottom=6.04 if x else 5.98
        _arched_panel('Palazzo upper arched window glass',x,-3.565,bottom,7.62,.45,.055,m['glass'])
        _arch('Palazzo upper window white archivolt',x,-3.63,7.62,.45,.13,.13,m['white'],20)
        for dx in (-.515,.515):
            cube('Palazzo upper window carved jamb',(x+dx,-3.63,6.83),(.13,.13,1.63),m['white'],.015)
        cube('Palazzo upper window slender mullion',(x,-3.65,6.87),(.065,.12,1.84),m['ivory'],.012)
        cube('Palazzo upper window sill',(x,-3.68,6.02),(1.19,.38,.14),m['white'],.02)
    # Center balcony with three little lobes and gilded ironwork.
    cube('Palazzo ceremonial balcony slab',(0,-3.88,5.98),(2.11,.90,.20),m['white'],.035)
    cube('Palazzo ceremonial balcony top rail',(0,-4.20,6.57),(2.12,.12,.10),m['white'],.025)
    for x in (-.91,-.60,-.30,0,.30,.60,.91):
        cyl('Palazzo ceremonial balcony baluster',(x,-4.20,6.28),.047,.51,m['ivory'],10)
    for x in (-.99,.99):
        cube('Palazzo balcony side rail',(x,-3.88,6.57),(.12,.73,.10),m['white'],.025)
    for x in (-4.95,4.95):
        cube('Palazzo carved facade corner strip',(x,-3.55,7.04),(.17,.16,3.2),m['white'],.015)
        for z in (5.72,6.35,6.98,7.61,8.24):
            cube('Palazzo corner marble block',(x,-3.58,z),(.28,.21,.18),m['ivory'],.018)
    # Side windows retain detail when the building is viewed from the canal.
    for angle in (math.pi/2,-math.pi/2):
        side_before=set(bpy.data.objects)
        for x in (-2.2,0,2.2):
            _arched_panel('Palazzo side upper window',x,-5.035,6.1,7.50,.39,.035,m['glass'])
            _arch('Palazzo side window carved arch',x,-5.08,7.5,.39,.11,.10,m['white'],16)
            for dx in (-.435,.435):
                cube('Palazzo side window jamb',(x+dx,-5.08,6.80),(.11,.10,1.43),m['white'])
        _spin_since(side_before,angle)
    cube('Palazzo facade top frieze',(0,0,8.66),(10.19,7.18,.20),m['ivory'],.025)
    cube('Palazzo deep carved eaves',(0,0,8.86),(10.42,7.42,.20),m['white'],.03)
    for i in range(27):
        cube('Palazzo eaves stone dentil',(-4.94+i*.38,-3.66,8.70),(.14,.21,.19),m['white'],.015)
    mesh('Palazzo hipped terracotta roof',[(-5.13,-3.64,8.98),(5.13,-3.64,8.98),(5.13,3.64,8.98),(-5.13,3.64,8.98),(-3.3,0,9.92),(3.3,0,9.92)],
         [(0,1,5,4),(1,2,5),(2,3,4,5),(3,0,4),(0,3,2,1)],m['roof'])
    curve('Palazzo terracotta ridge cap',[(-3.36,0,9.94),(3.36,0,9.94)],.085,m['rooflight'])
    for a,b in (((-5.13,-3.64,8.99),(-3.3,0,9.94)),((5.13,-3.64,8.99),(3.3,0,9.94)),
                ((5.13,3.64,8.99),(3.3,0,9.94)),((-5.13,3.64,8.99),(-3.3,0,9.94))):
        curve('Palazzo roof hip tiles',[a,b],.058,m['rooflight'])
    for i in range(23):
        x=-4.70+i*.427
        ex=max(-3.3,min(3.3,x))
        curve('Palazzo roof front tile channel',[(x,-3.65,9.015),(ex,0,9.955)],.018,m['rooflight'])
        curve('Palazzo roof rear tile channel',[(x,3.65,9.015),(ex,0,9.955)],.018,m['rooflight'])
    return group_objects(name,before,loc,rotation)

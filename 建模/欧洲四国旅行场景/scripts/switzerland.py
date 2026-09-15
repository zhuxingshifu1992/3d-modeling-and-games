"""A detailed, metrically compressed Alpine village beneath a rugged peak.

Pure geometry generator: no bpy dependency; the supplied Builder owns batching.
The Matterhorn is an artistic interpretation rather than surveyed topography.
"""
import math
import random


def build(B):
    rng = random.Random(417021)
    tau = math.tau

    # Four broad rock faces meet at asymmetric sharp ridges. Their lower
    # shoulders merge into a wide talus apron; the perimeter still meets z=0.
    sectors, rings = 224, 104

    def rock_noise(x, y, z):
        """Deterministic spatial value noise, independent of angular sectors."""
        ix, iy, iz = math.floor(x), math.floor(y), math.floor(z)
        fx, fy, fz = x-ix, y-iy, z-iz
        fx=fx*fx*(3-2*fx); fy=fy*fy*(3-2*fy); fz=fz*fz*(3-2*fz)
        value=0.0
        for dx in (0,1):
            for dy in (0,1):
                for dz in (0,1):
                    h=math.sin((ix+dx)*127.1+(iy+dy)*311.7+(iz+dz)*74.7)*43758.5453
                    h=2*(h-math.floor(h))-1
                    value += h*(fx if dx else 1-fx)*(fy if dy else 1-fy)*(fz if dz else 1-fz)
        return value

    def mountain_point(t, a):
        if t == 0:
            return (-13.0, 42.5, 78.0)
        # A diamond is an actual four-face cross-section, unlike an ellipse
        # decorated with radial grooves. Rotate its ridges slightly for a
        # front-facing wall and make the eastern shoulder wider and lower.
        ca, sa = math.cos(a-.11), math.sin(a-.11)
        diamond = 1.0 / (abs(ca)+abs(sa))
        apron=max(0.,min(1.,(t-.66)/.34))
        apron=apron*apron*(3-2*apron)
        outline=diamond*(1-apron)+apron
        radial=t*outline
        x=-13*(1-t)+65*radial*math.cos(a)
        y=42.5*(1-t)+34*t+23.2*radial*math.sin(a)
        # Piecewise profile: a steep horn above a defined shoulder, then a
        # gently flattening scree foot. All four major facets remain legible.
        if t<.54:
            z=78-67.8*t
        else:
            z=41.388*((1-t)/.46)**1.52
        east_distance=math.atan2(math.sin(a-.12),math.cos(a-.12))
        shoulder=8.4*math.exp(-(east_distance/.48)**2)*math.exp(-((t-.57)/.22)**2)
        # The prominent left face loses height to an oblique subsidiary ridge.
        west_distance=math.atan2(math.sin(a-2.95),math.cos(a-2.95))
        shoulder-=3.1*math.exp(-(west_distance/.48)**2)*math.sin(math.pi*t)
        z += shoulder*math.sin(math.pi*t)
        envelope=math.sin(math.pi*t)**.85*min(1.,max(0.,(1-t)/.09))
        coarse=rock_noise(x*.095,y*.12,z*.11)
        fine=rock_noise(x*.24+9,y*.29,z*.25+3)
        detail=rock_noise(x*.63+4,y*.67+13,z*.56)
        erosion=(7.2*coarse+2.8*fine+.85*detail)*envelope
        # Narrow broken bedding ledges run across faces, never as uniform
        # stripes converging on the summit.
        bedding=.65*math.sin(z*.62+x*.11+y*.08+coarse*2.4)*envelope
        x += .72*erosion*math.cos(a)
        y += .49*erosion*math.sin(a)
        z += .75*erosion+bedding
        return (x,y,min(78.,max(.045 if t<.9999 else 0.,z)))

    mountain_rows = [[mountain_point(i / rings, j * tau / sectors)
                      for j in range(sectors)] for i in range(1, rings + 1)]
    for j in range(sectors):
        B.poly('SW_Mountain', [mountain_point(0, 0), mountain_rows[0][j],
                              mountain_rows[0][(j + 1) % sectors]], [(0, 1, 2)], 'snow')
    for i in range(rings - 1):
        t = (i + 1.5) / rings
        for j in range(sectors):
            a = (j + .5) * tau / sectors
            q = (j + 1) % sectors
            v = [mountain_rows[i][j], mountain_rows[i + 1][j],
                 mountain_rows[i + 1][q], mountain_rows[i][q]]
            # Wind-scoured rock faces carry broken snow pockets on ledges.
            # Both color and snow are sampled in world space, so no bands are
            # locked to the angular tessellation of the mountain.
            altitude = sum(p[2] for p in v) / 4
            xx=sum(p[0] for p in v)/4; yy=sum(p[1] for p in v)/4
            e1=[v[1][k]-v[0][k] for k in range(3)]
            e2=[v[3][k]-v[0][k] for k in range(3)]
            normal=(e1[1]*e2[2]-e1[2]*e2[1],e1[2]*e2[0]-e1[0]*e2[2],e1[0]*e2[1]-e1[1]*e2[0])
            nz=abs(normal[2])/max(.00001,math.sqrt(sum(n*n for n in normal)))
            broad=rock_noise(xx*.078+8,yy*.10+2,altitude*.08)
            pocket=rock_noise(xx*.19,yy*.23+4,altitude*.21+8)
            snowline=31+8*rock_noise(xx*.035,yy*.061,2.3)
            drift=.82*broad+.32*pocket+.8*(nz-.48)+max(0,altitude-61)*.022
            if altitude>74.5 or (altitude>snowline and drift>.12):
                mat = 'snow'
            elif altitude<5.3 and broad>-.27:
                mat = 'grass'
            else:
                mat='rock_dark' if .45*broad+.28*pocket<-.23 else 'rock'
            # Alternating diagonals suppress a regular radial-grid appearance.
            fs = [(0, 1, 3), (1, 2, 3)] if (i + j) % 2 else [(0, 1, 2), (0, 2, 3)]
            B.poly('SW_Mountain', v, fs, mat)

    def ribbon(name, points, width, mat, zoff=0):
        verts = []
        for i, p in enumerate(points):
            prev, nex = points[max(0, i - 1)], points[min(len(points) - 1, i + 1)]
            dx, dy = nex[0] - prev[0], nex[1] - prev[1]
            length = max(.0001, math.hypot(dx, dy))
            nx, ny = -dy / length * width / 2, dx / length * width / 2
            verts.extend([(p[0] + nx, p[1] + ny, p[2] + zoff),
                          (p[0] - nx, p[1] - ny, p[2] + zoff)])
        B.poly(name, verts, [(2 * i, 2 * i + 1, 2 * i + 3, 2 * i + 2)
                            for i in range(len(points) - 1)], mat)

    # Unobstructed village lanes and a small piazza at the road intersection.
    ribbon('SW_Lanes', [(0, -60, .055), (0, -38, .055), (1, -20, .055),
                       (0, 1, .055), (0, 8.5, .055)], 5.2, 'gravel')
    ribbon('SW_Lanes', [(-60, -21, .06), (-25, -21, .06), (0, -21, .06),
                       (26, -21, .06), (47, -20, .06), (66, -20, .06)], 4.6, 'gravel')
    B.cyl('SW_Lanes', (0, -21, .055), 6, .08, 'paving', 32)
    # Accessible viewing path skirts the rock apron on flat ground. Steep
    # mountain faces are scenic terrain, not a route for a walking controller.
    trail = [(0, 3.5, .075), (0, 7.5, .075)]
    for k in range(45):
        x=k*.96
        y=34-23.2*math.sqrt(1-(x/65)**2)-1.8
        trail.append((x,y,.075))
    ribbon('SW_Trail', trail, 1.4, 'gravel')

    river = [(58, 19, .09), (54, 10, .09), (57, 2, .09), (52, -11, .09),
             (55, -20, .09), (59, -31, .09), (54, -43, .09), (60, -58.2, .09)]
    ribbon('SW_RiverBanks', river, 8.4, 'gravel', -.015)
    ribbon('SW_Water', river, 5.4, 'water', .025)
    for i in range(52):
        segment = rng.randrange(len(river) - 1)
        f = rng.random()
        a, b = river[segment:segment + 2]
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy)
        side = rng.choice([-1, 1])
        x = a[0] + f * dx + side * -dy / length * rng.uniform(3.0, 4.4)
        y = a[1] + f * dy + side * dx / length * rng.uniform(3.0, 4.4)
        r = rng.uniform(.25, .9)
        B.cyl('SW_Boulders', (x, y, r * .22), r, r * .72,
              'stone' if i % 3 else 'rock_dark', 7, radius_top=r * .52)

    # Gently ramped pedestrian bridge, with true space beneath the deck.
    B.box('SW_Bridge', (55, -20, .88), (11, 4, .4), 'wood')
    for x in (50.8, 59.2):
        B.box('SW_Bridge', (x, -20, .46), (1.2, 4.4, .92), 'stone')
    for xa, xb, za, zb in [(46, 49.5, .08, 1.08), (60.5, 64, 1.08, .08)]:
        B.poly('SW_Bridge', [(xa, -22, za), (xb, -22, zb),
                             (xb, -18, zb), (xa, -18, za)], [(0, 1, 2, 3)], 'wood')
    for x in [49.6 + i * .42 for i in range(27)]:
        B.box('SW_Bridge', (x, -20, 1.105), (.34, 4, .07), 'wood')
    for y in (-21.9, -18.1):
        for x in [49.7 + i * 1.35 for i in range(9)]:
            B.box('SW_Bridge', (x, y, 1.64), (.14, .14, 1.2), 'dark_wood')
        B.beam('SW_Bridge', (49.5, y, 2.21), (60.5, y, 2.21), .10, 'wood')
        B.beam('SW_Bridge', (49.5, y, 1.58), (60.5, y, 1.58), .06, 'wood')

    def window(x, y, z, w=1.25, h=1.45, side=False, shutters=True):
        # Local window faces south. Side windows face east.
        angle = math.pi / 2 if side else 0
        ca, sa = math.cos(angle), math.sin(angle)

        def local(dx, dy, dz):
            return (x + dx * ca - dy * sa, y + dx * sa + dy * ca, z + dz)

        B.box('SW_WindowFrames', local(0, .035, 0), (w + .23, .16, h + .22), 'dark_wood', angle)
        B.box('SW_Glazing', local(0, -.065, 0), (w, .055, h), 'glass', angle)
        for dx in (-w / 2, 0, w / 2):
            B.box('SW_WindowFrames', local(dx, -.115, 0), (.07, .085, h + .12), 'wood', angle)
        for dz in (-h / 2, 0, h / 2):
            B.box('SW_WindowFrames', local(0, -.115, dz), (w + .12, .085, .075), 'wood', angle)
        B.box('SW_WindowFrames', local(0, -.14, -h / 2 - .12), (w + .34, .34, .14), 'stone', angle)
        if shutters:
            for sign in (-1, 1):
                sx = sign * (w * .73 + .18)
                B.box('SW_Shutters', local(sx, -.045, 0), (w * .43, .11, h + .12), 'dark_wood', angle)
                for k in range(8):
                    B.box('SW_Shutters', local(sx, -.11, -h * .42 + k * h * .12),
                          (w * .37, .08, .07), 'wood', angle)

    def chalet(x, y, w, d, h, variant):
        front, rear = y - d / 2, y + d / 2
        B.box('SW_Foundations', (x, y, .46), (w + .18, d + .18, .92), 'stone')
        B.box('SW_ChaletWalls', (x, y, 1.94), (w, d, 2.05),
              'plaster' if variant % 3 else 'warm_plaster')
        B.box('SW_ChaletWalls', (x, y, (h + 2.97) / 2), (w, d, h - 2.97), 'dark_wood')
        # Real horizontal log boards, projecting alternating corner ends.
        count = int((h - 2.93) / .29)
        for k in range(count):
            zz = 3.09 + k * .29
            B.box('SW_LogBoards', (x, front - .035, zz), (w + .3 + (k % 2) * .15, .15, .25), 'wood')
            B.box('SW_LogBoards', (x, rear + .035, zz), (w + .3, .15, .25), 'wood')
            for side in (-1, 1):
                B.box('SW_LogBoards', (x + side * (w / 2 + .025), y, zz),
                      (.15, d + .28 + ((k + 1) % 2) * .14, .25), 'wood')
        for side in (-1, 1):
            for yy in (front - .14, rear + .14):
                B.box('SW_TimberStructure', (x + side * (w / 2 - .17), yy, h / 2),
                      (.2, .21, h), 'dark_wood')
        for zz in (.98, 2.92, h - .13):
            B.box('SW_TimberStructure', (x, front - .16, zz), (w + .32, .23, .21), 'dark_wood')
        # Deep gabled slate roof with overhanging rafters and faceted slate tiles.
        rw, rd, rise = w + 2.1, d + 2.0, 2.45 + .045 * w
        B.roof('SW_Roofs', (x, y, h), rw, rd, rise, 'slate')
        for yy in (front - 1.0, rear + 1.0):
            B.beam('SW_RoofEdges', (x - rw / 2, yy, h), (x, yy, h + rise), .14, 'wood')
            B.beam('SW_RoofEdges', (x, yy, h + rise), (x + rw / 2, yy, h), .14, 'wood')
            B.beam('SW_TimberStructure', (x - w / 2, yy + (.95 if yy < y else -.95), h - .05),
                   (x + w / 2, yy + (.95 if yy < y else -.95), h - .05), .12, 'dark_wood')
        for sx in (-1, 1):
            B.box('SW_RoofEdges', (x + sx * rw / 2, y, h - .02), (.18, rd + .15, .2), 'wood')
            for k in range(10):
                u0, u1 = k / 10, (k + 1.07) / 10
                u1 = min(1.015, u1)
                for j in range(17):
                    yy0 = y - rd / 2 + j * rd / 17 + .02
                    yy1 = y - rd / 2 + (j + 1) * rd / 17 - .02
                    z0, z1 = h + rise * (1 - u0) + .035, h + rise * (1 - u1) + .075
                    xx0, xx1 = x + sx * rw / 2 * u0, x + sx * rw / 2 * u1
                    mat = 'rock_dark' if (j * 7 + k * 3 + variant) % 17 == 0 else 'slate'
                    B.poly('SW_RoofSlates', [(xx0, yy0, z0), (xx1, yy0, z1),
                                           (xx1, yy1, z1), (xx0, yy1, z0)], [(0, 1, 2, 3)], mat)
            for j in range(8):
                yy = y - rd / 2 + .5 + j * (rd - 1) / 7
                B.beam('SW_TimberStructure', (x + sx * (w / 2 - .6), yy, h + .24),
                       (x + sx * (rw / 2 - .08), yy, h - .15), .09, 'dark_wood')
        B.beam('SW_RoofEdges', (x, y - rd / 2 - .06, h + rise + .10),
               (x, y + rd / 2 + .06, h + rise + .10), .105, 'slate', 6)
        # Timber gable surface and king-post structure remain visible below roof.
        for yy in (front - .10, rear + .10):
            B.poly('SW_ChaletWalls', [(x - w / 2, yy, h), (x + w / 2, yy, h),
                                     (x, yy, h + rise * w / rw)], [(0, 1, 2)], 'wood')
            B.beam('SW_TimberStructure', (x, yy - .08, h),
                   (x, yy - .08, h + rise * w / rw - .15), .10, 'dark_wood')
        # Ground-floor entrance, glazed panes, shutters and stone lintels.
        B.box('SW_Doors', (x, front - .12, 1.35), (1.38, .2, 2.5), 'dark_wood')
        for xx in (-.45, 0, .45):
            B.box('SW_Doors', (x + xx, front - .24, 1.24), (.06, .05, 2.12), 'wood')
        B.cyl('SW_VillageProps', (x + .47, front - .28, 1.45), .045, .1, 'bronze', 8)
        B.box('SW_Foundations', (x, front - .14, 2.68), (1.74, .38, .24), 'stone')
        for k in range(3):
            B.box('SW_Foundations', (x, front - .4 - .33 * k, .13 - .035 * k),
                  (1.9, .5, .2 - .055 * k), 'stone')
        for sx in (-1, 1):
            window(x + sx * w * .285, front - .14, 1.92, 1.18, 1.33)
            window(x + sx * w * .28, front - .16, 4.83, 1.22, 1.4)
        for yy in (y - d * .25, y + d * .25):
            window(x + w / 2 + .10, yy, 1.96, 1.13, 1.35, True)
            window(x + w / 2 + .10, yy, 4.83, 1.13, 1.40, True)
        # Upper balcony spans the facade, with individually modeled balusters.
        balcony_z, balcony_y, balcony_w = 3.83, front - .94, w * .9
        B.box('SW_Balconies', (x, balcony_y, balcony_z), (balcony_w, 1.85, .23), 'wood')
        B.box('SW_Doors', (x, front - .16, 4.96), (1.2, .16, 2.1), 'dark_wood')
        B.box('SW_Glazing', (x, front - .255, 5.21), (.86, .04, 1.3), 'glass')
        for xx in (x - balcony_w / 2, x + balcony_w / 2):
            B.box('SW_TimberStructure', (xx, balcony_y - .7, 2.02), (.21, .21, 3.82), 'dark_wood')
            B.beam('SW_TimberStructure', (xx, front - .25, 2.6), (xx, balcony_y - .7, 3.72), .10, 'wood')
            B.box('SW_BalconyRails', (xx, balcony_y, 4.85), (.12, 1.85, .13), 'wood')
            for j in range(5):
                B.box('SW_BalconyRails', (xx, front - .3 - j * .35, 4.4), (.09, .09, .83), 'wood')
        nbal = int(balcony_w / .24)
        for j in range(nbal + 1):
            xx = x - balcony_w / 2 + j * balcony_w / nbal
            B.box('SW_BalconyRails', (xx, front - 1.82, 4.39), (.115, .105, .86),
                  'dark_wood' if j % 5 == 0 else 'wood')
        for zz in (4.01, 4.86):
            B.box('SW_BalconyRails', (x, front - 1.82, zz), (balcony_w + .12, .16, .15), 'wood')
        for sx in (-1, 1):
            bx = x + sx * balcony_w * .27
            B.box('SW_Balconies', (bx, front - 1.98, 4.35), (1.9, .4, .34), 'dark_wood')
            for j in range(8):
                B.cyl('SW_FlowerBoxes', (bx - .82 + j * .235, front - 1.99, 4.6), .18, .23,
                      'foliage', 7, radius_top=.23)
                if j % 2 == 0:
                    B.cyl('SW_FlowerBoxes', (bx - .82 + j * .235, front - 2.02, 4.77), .085, .08,
                          'red' if variant % 2 else 'white', 6)
        cx, cy = x + w * .23, y + d * .16
        cz = h + rise * (1 - abs(cx - x) / (rw / 2))
        B.box('SW_Chimneys', (cx, cy, cz + .65), (.73, .9, 1.7), 'stone')
        B.box('SW_Chimneys', (cx, cy, cz + 1.56), (.98, 1.12, .16), 'slate')
        B.cyl('SW_Chimneys', (cx, cy, cz + 1.82), .18, .43, 'metal', 10)
        # Short entrance path joins the nearest transverse or main village lane.
        # Every chalet entrance faces south, including the northeast chalet.
        # Connect southward to the transverse lane rather than through its wall.
        endy = -21
        if y < -21:
            ribbon('SW_Lanes', [(x, front - 1.3, .07), (x - w * .7, front - 1.3, .07),
                               (x - w * .7, endy, .07)], 1.3, 'gravel')
        else:
            ribbon('SW_Lanes', [(x, front - 1.3, .07), (x, endy, .07)], 1.5, 'gravel')

    houses = [(-39, -36, 10.6, 10.4, 6.55), (-19, -38, 11.8, 10.0, 6.75),
              (18, -37, 12.0, 10.8, 6.65), (39, -35, 10.0, 10.6, 6.45),
              (-33, -7, 10.8, 10.6, 6.6), (-16, -5, 10.2, 9.3, 6.35),
              (17, -5, 11.6, 10.2, 6.75), (37, 3, 9.6, 10.0, 6.45)]
    for index, house in enumerate(houses):
        chalet(*house, index)

    # Village church: limewashed nave, real arched surrounds, clock and steeple.
    x, y = -51, 1
    B.box('SW_Church', (x, y, 3.72), (7.8, 13, 7.44), 'plaster')
    B.box('SW_Foundations', (x, y, .35), (8.1, 13.3, .7), 'stone')
    B.roof('SW_Roofs', (x, y, 7.44), 8.8, 14, 4.2, 'slate')
    tx, ty = x, y - 7.2
    B.box('SW_Church', (tx, ty, 7.35), (4.6, 4.6, 14.7), 'plaster')
    for zz in (.4, 4.9, 9.9, 14.4):
        B.box('SW_ChurchDetails', (tx, ty, zz), (4.9, 4.9, .26), 'stone')
    B.poly('SW_ChurchSpire', [(tx - 2.7, ty - 2.7, 14.7), (tx + 2.7, ty - 2.7, 14.7),
                             (tx + 2.7, ty + 2.7, 14.7), (tx - 2.7, ty + 2.7, 14.7),
                             (tx, ty, 24.3)],
           [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4), (0, 3, 2, 1)], 'slate')
    B.beam('SW_ChurchDetails', (tx, ty, 24.3), (tx, ty, 26.0), .065, 'metal', 6)
    B.beam('SW_ChurchDetails', (tx - .45, ty, 25.35), (tx + .45, ty, 25.35), .06, 'metal', 6)
    B.box('SW_Doors', (tx, ty - 2.34, 1.5), (1.5, .12, 3.0), 'dark_wood')
    B.arch('SW_ChurchDetails', (tx, ty - 2.37, .05), 1.65, 3.25, .27, 'stone', thickness=.25)
    for yy in (-2.0, 2.5, 6.2):
        window(x + 3.95, yy, 4.2, .92, 2.4, True, False)
    for side in (-1, 1):
        for dx in (-.67, .67):
            B.box('SW_Doors', (tx + dx, ty + side * 2.33, 12.78), (.67, .09, 1.6), 'dark_wood')
            B.arch('SW_ChurchDetails', (tx + dx, ty + side * 2.4, 12), .63, 1.65,
                   .15, 'stone', thickness=.13, segments=10)
            for k in range(7):
                B.box('SW_ChurchDetails', (tx + dx, ty + side * 2.42, 12.1 + k * .18),
                      (.58, .08, .075), 'wood')
    # Front clock is an actual circular face in the XZ plane.
    clock_y, clock_z, r = ty - 2.46, 10.85, .83
    circle = [(tx, clock_y, clock_z)]
    circle += [(tx + r * math.cos(k * tau / 40), clock_y, clock_z + r * math.sin(k * tau / 40))
               for k in range(40)]
    B.poly('SW_ChurchDetails', circle, [(0, k + 1, (k + 1) % 40 + 1) for k in range(40)], 'white')
    for k in range(12):
        a = k * tau / 12
        B.beam('SW_ChurchDetails', (tx + .66 * math.sin(a), clock_y - .025, clock_z + .66 * math.cos(a)),
               (tx + .76 * math.sin(a), clock_y - .025, clock_z + .76 * math.cos(a)), .025, 'metal')
    B.beam('SW_ChurchDetails', (tx, clock_y - .045, clock_z), (tx + .48, clock_y - .045, clock_z + .30), .03, 'metal')
    B.beam('SW_ChurchDetails', (tx, clock_y - .045, clock_z), (tx - .21, clock_y - .045, clock_z + .35), .038, 'metal')
    ribbon('SW_Lanes', [(tx, ty - 2.8, .07), (tx, -21, .07)], 2.5, 'paving')

    # Wayside details: water trough, firewood, benches, fences and Swiss flags.
    B.box('SW_VillageProps', (7, -19, .35), (2.5, .95, .7), 'stone')
    B.box('SW_Water', (7, -19, .71), (2.08, .58, .02), 'water')
    B.box('SW_VillageProps', (8.13, -19, 1.1), (.3, .3, 1.75), 'wood')
    B.beam('SW_VillageProps', (8.13, -19, 1.67), (7.70, -19, 1.67), .05, 'metal', 8)
    for bx, by in [(-8, -20), (9, -27), (-46, -17), (29, -20)]:
        B.box('SW_VillageProps', (bx, by, .52), (2.5, .64, .16), 'wood')
        for sx in (-1, 1):
            B.box('SW_VillageProps', (bx + sx * .9, by, .27), (.13, .48, .54), 'metal')
        B.box('SW_VillageProps', (bx, by + .29, 1.0), (2.5, .13, .5), 'wood')
    for bx, by in [(-27, -40), (27, -36), (-42, -7)]:
        for row in range(4):
            for col in range(6 - row):
                xx = bx + col * .24 + row * .12
                B.beam('SW_VillageProps', (xx, by, .18 + row * .22),
                       (xx, by + .8, .18 + row * .22), .13, 'wood', 8)
    for xa, xb, yy in [(-47, -31, -47), (-25, -12, -48), (10, 24, -48),
                       (31, 46, -46), (-42, -27, 1), (29, 43, 10)]:
        for k in range(int((xb - xa) / 1.6) + 1):
            B.box('SW_Fences', (xa + k * 1.6, yy, .66), (.14, .14, 1.3), 'wood')
        for zz in (.42, .96):
            B.beam('SW_Fences', (xa, yy, zz), (xb, yy, zz), .065, 'dark_wood')
    for fx, fy in [(-7, -16), (28, -13)]:
        B.cyl('SW_VillageProps', (fx, fy, 3.1), .048, 6.2, 'metal', 10)
        B.poly('SW_Flags', [(fx, fy, 5.8), (fx + 1.4, fy + .1, 5.75),
                             (fx + 1.4, fy + .12, 4.35), (fx, fy, 4.4)], [(0, 1, 2, 3)], 'red')
        B.box('SW_Flags', (fx + .7, fy - .022, 5.08), (.28, .025, .88), 'white')
        B.box('SW_Flags', (fx + .7, fy - .031, 5.08), (.88, .025, .28), 'white')
    # One legible trail sign silhouette; metadata carries the landmark name.
    B.box('SW_VillageProps', (3.8, 9, 1.2), (.14, .14, 2.4), 'wood')
    B.poly('SW_VillageProps', [(3.0, 8.92, 2.1), (4.55, 8.92, 2.1),
                              (4.85, 8.92, 2.32), (4.55, 8.92, 2.54), (3.0, 8.92, 2.54)],
           [(0, 1, 2, 3, 4)], 'gold')

    # Fir belts frame the clear village routes and retain an open central view.
    tree_positions = [(-62, -46), (-57, -38), (-61, -27), (-62, -14),
                      (-61, -3), (-61, 8), (-58, 13), (-45, 12),
                      (-38, 13), (-31, 14), (-24, 12), (-12, 12),
                      (10, 12), (20, 13), (28, 15), (43, 13), (48, 8),
                      (47, -5), (48, -29), (47, -43), (43, -52),
                      (29, -52), (9, -51), (-8, -50), (-30, -53),
                      (-50, -52), (64, -6), (64, -32), (64, -48),
                      (-52, -28), (-8, -7), (27, -4)]
    for i, (px, py) in enumerate(tree_positions):
        B.pine('SW_Firs', px, py, 0, rng.uniform(6.4, 11.3))
        if i < 8 or i in (15, 16, 20, 27):
            B.pine('SW_Firs', px + rng.uniform(-2.2, 2.2), py + rng.uniform(2, 3.5),
                   0, rng.uniform(4.1, 6.5))

    return {
        'landmark': '瑞士阿尔卑斯山村与马特洪峰风格山体',
        'approximate_scale': '140 × 120 m；峰高 78 m，为游览压缩的艺术重建',
        'spawn': [0, -54, 1.8],
        'description': '不对称岩雪山峰、八栋木板及石基阿尔卑斯木屋、阳台百叶窗、教堂钟塔、溪流木桥、村道与山脚步道。建筑为外景；雪线和地形非测绘数据。',
        'navigable_area': '前景村庄主路及横向村道；桥面高度约 1.1 m，山体后半部为景观。',
    }

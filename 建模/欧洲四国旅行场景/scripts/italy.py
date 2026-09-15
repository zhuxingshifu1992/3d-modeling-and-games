"""Rome: a compressed, open-arcade Colosseum and a surrounding Italian piazza.

The monument is an architectural game adaptation, not a surveyed reconstruction.
All geometry is local to a 140 x 120 m tile and is emitted in reusable batches.
"""
import math
import random


TAU = math.tau


def build(B):
    rng = random.Random(2077)
    cy = 8.0
    rx, ry = 37.0, 30.0
    bays = 56
    step = TAU / bays

    def ellipse(a, b, t, z=0.0):
        return (a * math.cos(t), cy + b * math.sin(t), z)

    def slab_ring(name, a0, b0, a1, b1, t0, t1, bottom, top, mat):
        """Closed annular-sector prism, leaving its center genuinely empty."""
        vs = [ellipse(a, b, t, z) for z in (bottom, top)
              for a, b, t in ((a0, b0, t0), (a1, b1, t0),
                              (a1, b1, t1), (a0, b0, t1))]
        B.poly(name, vs, [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
                         (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)], mat)

    def local_poly(name, center, angle, profile, depth, mat):
        c, s = math.cos(angle), math.sin(angle)
        x, y, z = center
        n = len(profile)
        verts = [(x + px * c - dy * s, y + px * s + dy * c, z + pz)
                 for dy in (-depth / 2, depth / 2) for px, pz in profile]
        faces = [tuple(reversed(range(n))), tuple(range(n, 2 * n))]
        faces += [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
        B.poly(name, verts, faces, mat)

    def arc_frame(a, b, i):
        t = i * step
        p, q = ellipse(a, b, t - step / 2), ellipse(a, b, t + step / 2)
        center = ((p[0] + q[0]) / 2, (p[1] + q[1]) / 2)
        angle = math.atan2(q[1] - p[1], q[0] - p[0])
        width = math.hypot(q[0] - p[0], q[1] - p[1])
        return t, center, angle, width

    def access(t):
        # Three unblocked radial routes: east, west and the south arrival axis.
        return min(abs(math.atan2(math.sin(t - a), math.cos(t - a)))
                   for a in (0, math.pi, math.pi * 1.5)) < .13

    def ellipsoid(name, center, radii, mat, seed):
        rr = random.Random(seed)
        x, y, z = center
        a, b, c = radii
        verts = [(x, y, z + c), (x, y, z - c)]
        sides, rings = 11, 6
        for j in range(1, rings):
            v = math.pi * j / rings
            for k in range(sides):
                u = TAU * k / sides
                jitter = rr.uniform(.9, 1.08)
                verts.append((x + a * math.sin(v) * math.cos(u) * jitter,
                              y + b * math.sin(v) * math.sin(u) * jitter,
                              z + c * math.cos(v)))
        faces = [(2 + j * sides + k, 2 + j * sides + (k + 1) % sides,
                  2 + (j + 1) * sides + (k + 1) % sides, 2 + (j + 1) * sides + k)
                 for j in range(rings - 2) for k in range(sides)]
        for k in range(sides):
            faces.append((0, 2 + k, 2 + (k + 1) % sides))
            offset = 2 + (rings - 2) * sides
            faces.append((1, offset + (k + 1) % sides, offset + k))
        B.poly(name, verts, faces, mat)

    # Low stone podium and the pedestrian paving surrounding the archaeological site.
    for i in range(112):
        t0, t1 = i * TAU / 112, (i + 1) * TAU / 112
        slab_ring('Piazza_Paving', .02, .02, 43.5, 36.5, t0, t1, .015, .15, 'paving')
        slab_ring('Piazza_Kerbs', 42.9, 35.9, 43.5, 36.5, t0, t1, .15, .24, 'stone')
        slab_ring('Colosseum_Cornices', 35.8, 28.8, 38.0, 31.0,
                  t0, t1, .15, .33, 'limestone')
    B.box('Piazza_Paving', (0, -41.7, .1), (7.0, 29.2, .2), 'paving')
    B.box('Piazza_Paving', (0, 42.5, .08), (111, 4.8, .16), 'paving')
    for x in (-45.5, 45.5):
        B.box('Piazza_Paving', (x, 5, .08), (5.2, 69, .16), 'paving')
    for j in range(14):
        B.box('Piazza_Kerbs', (0, -54.8 + j * 1.95, .207), (6.92, .028, .015), 'stone')
    for x in (-3.7, 3.7):
        B.box('Piazza_Kerbs', (x, -41.7, .19), (.35, 28.8, .25), 'limestone')

    # Lower, Ionic and Corinthian arcades: arch rings and shaped spandrels only.
    tiers = ((.33, 4.65, 5.95, -1.1), (6.18, 4.35, 11.55, -.77),
             (11.80, 3.95, 16.85, -.44))
    for tier, (base, clear_height, deck, survival) in enumerate(tiers):
        for i in range(bays):
            t, (x, y), rot, chord = arc_frame(rx, ry, i)
            if math.sin(t) < survival:
                continue
            width, thickness = chord - .93, .43
            B.arch('Colosseum_Arches', (x, y, base), width, clear_height,
                   1.5, 'limestone', rotation=rot, segments=12, thickness=thickness)
            # Fill only the spandrel outside the arched hole, never its opening.
            r = width / 2 + thickness
            spring = clear_height - width / 2
            profile = [(r * math.cos(math.pi - k * math.pi / 12),
                        spring + r * math.sin(math.pi - k * math.pi / 12))
                       for k in range(13)]
            profile += [(r, deck - base - .15), (-r, deck - base - .15)]
            local_poly('Colosseum_Spandrels', (x, y, base), rot, profile, 1.5, 'limestone')
            # Cut travertine voussoirs: slightly inset individual joints on outer face.
            c, s = math.cos(rot), math.sin(rot)
            for k in range(13):
                ang = k * math.pi / 12
                if k in (0, 12):
                    continue
                a = width / 2 + .045
                b = width / 2 + thickness - .04
                p = (x + a * math.cos(ang) * c + .758 * s,
                     y + a * math.cos(ang) * s - .758 * c,
                     base + spring + a * math.sin(ang))
                q = (x + b * math.cos(ang) * c + .758 * s,
                     y + b * math.cos(ang) * s - .758 * c,
                     base + spring + b * math.sin(ang))
                # A fine joint on the stone face needs no hidden prism back faces.
                d = (-c * math.sin(ang) * .016, -s * math.sin(ang) * .016,
                     math.cos(ang) * .016)
                joint = [tuple(point[j] + sign * d[j] for j in range(3))
                         for point, sign in ((p, -1), (q, -1), (q, 1), (p, 1))]
                B.poly('Colosseum_Piers', joint, [(0, 1, 2, 3)], 'stone')
            # Engaged order, with an outward face following the ellipse normal.
            pt = t + step / 2
            px, py, _ = ellipse(rx, ry, pt)
            nx, ny = math.cos(pt) / rx, math.sin(pt) / ry
            length = math.hypot(nx, ny)
            nx, ny = nx / length, ny / length
            angle = math.atan2(ny, nx) + math.pi / 2
            B.box('Colosseum_Piers', (px, py, (base + deck) / 2),
                  (.61, 1.55, deck - base), 'limestone', angle)
            shaft_x, shaft_y = px + nx * .84, py + ny * .84
            shaft_h = deck - base - .9
            B.cyl('Colosseum_Piers', (shaft_x, shaft_y, base + .43 + shaft_h / 2),
                  .225 if tier == 0 else .20, shaft_h, 'limestone', 10,
                  radius_top=.205 if tier == 0 else .175)
            for z, w, h in ((base + .13, .72, .26), (base + .34, .52, .16),
                            (deck - .42, .53, .16), (deck - .24, .73, .2)):
                B.box('Colosseum_Piers', (shaft_x, shaft_y, z),
                      (w, .46, h), 'limestone', angle)
            if tier > 0:
                for sign in (-1, 1):
                    B.cyl('Colosseum_Piers', (shaft_x + math.cos(angle) * sign * .21,
                                            shaft_y + math.sin(angle) * sign * .21,
                                            deck - .45), .1, .15, 'limestone', 7)
            for band_a, band_b, z, h in ((35.75, 28.75, deck, .24),
                                         (36.1, 29.1, deck + .22, .16)):
                slab_ring('Colosseum_Cornices', band_a, band_b, 38.08, 31.08,
                          t - step / 2, t + step / 2, z - h / 2, z + h / 2, 'limestone')
            if tier < 2:
                slab_ring('Colosseum_Cornices', 33.7, 26.7, 36.35, 29.35,
                          t - step / 2, t + step / 2, deck - .14, deck + .12, 'stone')

    # Attic with actual rectangular apertures. Its broken ends retain masonry teeth.
    for i in range(bays):
        t, (x, y), rot, chord = arc_frame(rx, ry, i)
        if math.sin(t) < -.07:
            continue
        base = 17.11
        top = 20.20 - (.4 if i in (0, 28) else 0)
        def bx(u, z, width, height, depth=1.4):
            B.box('Colosseum_Attic', (x + u * math.cos(rot), y + u * math.sin(rot), z),
                  (width, depth, height), 'limestone', rot)
        opening = .90
        side = (chord - opening) / 2
        bx(-(opening + side) / 2, (base + top) / 2, side - .015, top - base)
        bx((opening + side) / 2, (base + top) / 2, side - .015, top - base)
        bx(0, base + .36, opening, .72)
        bx(0, top - .35, opening, .70)
        slab_ring('Colosseum_Cornices', 35.9, 28.9, 38.15, 31.15,
                  t - step / 2, t + step / 2, top, top + .27, 'limestone')
        # Velarium mast corbels are a distinctive remnant of the original roof system.
        px, py, _ = ellipse(38, 31, t)
        B.box('Colosseum_Attic', (px, py, top - .52), (.39, .75, .40), 'limestone', rot)
        B.box('Colosseum_Attic', (px, py, top - 1.18), (.32, .68, .31), 'limestone', rot)

    # Irregular broken masonry along the staggered front silhouette.
    for tier, (base, clear_height, deck, survival) in enumerate(tiers[1:], 1):
        for i in range(bays):
            t, (x, y), rot, chord = arc_frame(rx, ry, i)
            if abs(math.sin(t) - survival) < .145:
                for k in range(3):
                    u = (k - 1) * chord * .26
                    height = rng.uniform(.25, .85)
                    B.box('Colosseum_Ruins', (x + u * math.cos(rot), y + u * math.sin(rot),
                                              base + height / 2),
                          (chord * .23, 1.32, height), 'brick' if k == 1 else 'limestone', rot)

    # Secondary lower arcade encloses the ambulatory, with matching open access bays.
    for i in range(bays):
        t, (x, y), rot, chord = arc_frame(34.0, 27.0, i)
        B.arch('Colosseum_InnerArcades', (x, y, .33), chord - .74, 4.1, .62,
               'brick', rotation=rot, segments=10, thickness=.34)

    # A hollow elliptical arena. Sand and lower hypogeum remnants preserve broad routes.
    n = 112
    floor = [ellipse(20.2, 13.2, i * TAU / n, .27) for i in range(n)]
    B.poly('Colosseum_Arena', floor, [tuple(range(n))], 'gravel')
    for i in range(n):
        t0, t1 = (i - .5) * TAU / n, (i + .5) * TAU / n
        if not access((t0 + t1) / 2):
            slab_ring('Colosseum_Arena', 20.1, 13.1, 20.7, 13.7,
                      t0, t1, .20, 1.20, 'brick')
            slab_ring('Colosseum_Arena', 20.0, 13.0, 20.85, 13.85,
                      t0, t1, 1.20, 1.36, 'limestone')
    for y in (cy - 6.2, cy - 3.5, cy + 3.5, cy + 6.2):
        for x in (-7.5, 7.5):
            B.box('Colosseum_Arena', (x, y, .61), (11.3, .48, .68), 'brick')
    for x in (-12.7, -8.7, -4.7, 4.7, 8.7, 12.7):
        for y in (cy - 4.8, cy + 4.8):
            B.box('Colosseum_Arena', (x, y, .56), (.42, 2.55, .58), 'brick')

    # Twenty-four tiers of solid stepped cavea; corridors continue all the way inward.
    for row in range(24):
        inner_a, inner_b = 20.85 + row * .52, 13.85 + row * .52
        top = 1.45 + row * .445
        for i in range(n):
            t0, t1 = (i - .5) * TAU / n, (i + .5) * TAU / n
            t = (t0 + t1) / 2
            if access(t):
                continue
            # Missing southern seating opens the ruin for an exterior game camera.
            if math.sin(t) < -.57 and row > 9 + (i % 4):
                continue
            slab_ring('Colosseum_Seating', inner_a, inner_b, inner_a + .515, inner_b + .515,
                      t0, t1, .26, top, 'stone' if row % 5 == 4 else 'limestone')
    # Smooth, level ground routes into the arena through the three paired arcades.
    B.box('Piazza_Paving', (0, cy, .19), (81.0, 2.7, .18), 'gravel')
    B.box('Piazza_Paving', (0, -10.0, .19), (3.0, 36.0, .18), 'gravel')
    for j in range(29):
        t = rng.uniform(math.pi + .70, TAU - .70)
        if access(t):
            continue
        a = rng.uniform(29.2, 32.7)
        b = a - 7.0
        x, y, _ = ellipse(a, b, t)
        B.box('Colosseum_Ruins', (x, y, .50),
              (rng.uniform(.5, 1.1), rng.uniform(.45, .95), rng.uniform(.35, .6)),
              'limestone', rng.uniform(-.8, .8))

    def hip_roof(x, y, w, d, z, h):
        ridge = max(.65, (w - d) / 2)
        verts = [(x - w / 2, y - d / 2, z), (x + w / 2, y - d / 2, z),
                 (x + w / 2, y + d / 2, z), (x - w / 2, y + d / 2, z),
                 (x - ridge, y, z + h), (x + ridge, y, z + h)]
        B.poly('Street_Roofs', verts, [(0, 1, 5, 4), (1, 2, 5),
                                     (2, 3, 4, 5), (3, 0, 4)], 'terracotta')
        B.beam('Street_RoofDetails', verts[4], verts[5], .12, 'terracotta', 8)
        for a, b in ((0, 4), (1, 5), (2, 5), (3, 4)):
            B.beam('Street_RoofDetails', verts[a], verts[b], .11, 'terracotta', 8)
        for side in (-1, 1):
            for k in range(int(w / .7) + 1):
                xx = x - w / 2 + .28 + k * (w - .56) / max(1, int(w / .7))
                near_x = max(x - ridge, min(x + ridge, xx))
                B.beam('Street_RoofDetails', (xx, y + side * d / 2, z + .025),
                       (near_x, y, z + h + .025), .037, 'terracotta', 5)

    def building(x, y, w, d, floors, facing, index):
        height = floors * 3.10 + .60
        mat = 'warm_plaster' if index % 3 else 'plaster'
        B.box('Street_Facades', (x, y, height / 2 + .15), (w, d, height), mat)
        B.box('Street_Trim', (x, y, .57), (w + .13, d + .13, .84), 'stone')
        for z in (3.30, height - .17, height + .12):
            B.box('Street_Trim', (x, y, z), (w + .25, d + .25, .19), 'limestone')
        hip_roof(x, y, w + .72, d + .72, height + .24, 1.7)
        for sign in (-1, 1):
            B.box('Street_RoofDetails', (x + sign * w * .30, y + d * .13, height + 1.25),
                  (.65, .72, 1.4), 'brick')
            B.box('Street_RoofDetails', (x + sign * w * .30, y + d * .13, height + 2.0),
                  (.86, .9, .18), 'terracotta')
        # Facing is outward-normal angle. The facade-local X is the horizontal axis.
        normal = (math.cos(facing), math.sin(facing))
        tangent = (-normal[1], normal[0])
        extent = d / 2 if abs(normal[1]) > .5 else w / 2
        run = w if abs(normal[1]) > .5 else d
        fx, fy = x + normal[0] * extent, y + normal[1] * extent
        rot = facing + math.pi / 2
        def item(name, u, z, size, material, out=.08):
            B.box(name, (fx + tangent[0] * u + normal[0] * out,
                         fy + tangent[1] * u + normal[1] * out, z), size, material, rot)
        cols = max(3, int(run / 2.7))
        for level in range(floors):
            for col in range(cols):
                u = (col - (cols - 1) / 2) * (run - 2.1) / (cols - 1)
                z = 1.70 + level * 3.10
                if level == 0 and abs(u) < 1.1:
                    continue
                item('Street_Windows', u, z, (1.07, .12, 1.72), 'dark_wood', .025)
                item('Street_Windows', u, z, (.87, .08, 1.48), 'glass', .096)
                for du in (-.57, .57):
                    item('Street_Trim', u + du, z, (.13, .19, 1.96), 'limestone', .13)
                for zz in (z - .91, z + .91):
                    item('Street_Trim', u, zz, (1.25, .26, .14), 'limestone', .16)
                item('Street_Windows', u, z, (.047, .11, 1.52), 'wood', .17)
                item('Street_Windows', u, z + .18, (.94, .11, .055), 'wood', .17)
                for sign in (-1, 1):
                    item('Street_Shutters', u + sign * .88, z, (.43, .09, 1.69),
                         'foliage_dark' if index % 2 else 'dark_wood', .12)
                    for slat in range(5):
                        item('Street_Shutters', u + sign * .88, z - .63 + slat * .31,
                             (.40, .10, .035), 'wood', .175)
                if level == 1 and col % 2 == 0:
                    item('Street_Balconies', u, z - .90, (1.65, .95, .16), 'limestone', .49)
                    item('Street_Balconies', u, z - .17, (1.64, .055, .065), 'metal', .97)
                    for rail in range(7):
                        item('Street_Balconies', u - .72 + rail * .24, z - .51,
                             (.035, .035, .65), 'metal', .97)
        item('Street_Doors', 0, 1.29, (1.38, .20, 2.28), 'dark_wood', .13)
        for u in (-.77, .77):
            item('Street_Trim', u, 1.34, (.18, .29, 2.47), 'limestone', .19)
        item('Street_Trim', 0, 2.62, (1.72, .33, .18), 'limestone', .19)
        item('Street_Doors', .34, 1.27, (.08, .07, .24), 'bronze', .27)
        for sign in (-1, 1):
            for level in range(floors * 5):
                u = sign * (run / 2 - .18)
                item('Street_Trim', u, .37 + level * .6, (.36, .17, .49), 'limestone', .12)

    for index, x in enumerate((-47.6, -34.0, -20.4, -6.8, 6.8, 20.4, 34.0, 47.6)):
        building(x, 52.1, 12.4, 9.7, 3 + (index % 3 == 0), -math.pi / 2, index)
    for index, (x, y) in enumerate(((-56, -13), (-56, 7), (-56, 28),
                                  (56, -13), (56, 7), (56, 28)), 8):
        building(x, y, 10.5, 14.0, 3 + index % 2, 0 if x < 0 else math.pi, index)

    # Stone pines: exposed branching trunks and broad, flattened umbrella crowns.
    for index, (x, y, height) in enumerate(((-28, -40, 10.8), (28, -40, 11.5),
                                          (-53, -42, 10.2), (53, -42, 11.0),
                                          (-14, -48, 9.8), (14, -48, 10.4))):
        B.beam('Vegetation_Trunks', (x, y, .15), (x + .35, y - .18, height * .77),
               .24, 'wood', 9)
        for k in range(5):
            t = k * TAU / 5 + .4 * index
            end = (x + math.cos(t) * 2.25, y + math.sin(t) * 1.9, height * .83)
            B.beam('Vegetation_Trunks', (x + .22, y, height * .48), end, .105, 'wood', 7)
            ellipsoid('Vegetation_Canopy', (end[0], end[1], height * .90 + .22 * (k % 2)),
                      (2.6, 2.1, 1.3), 'foliage_dark' if k % 2 else 'foliage', index * 71 + k)
        B.cyl('Street_Props', (x, y, .22), 1.1, .26, 'stone', 12)
        B.cyl('Street_Props', (x, y, .37), .96, .05, 'gravel', 12)
    # Slender cypress punctuation between the site and the surrounding streets.
    for index, (x, y) in enumerate(((-41, -27), (41, -27), (-47.6, 36.5),
                                  (47.6, 36.5), (-39, -35), (39, -35))):
        h = 8.3 + .5 * (index % 3)
        B.cyl('Vegetation_Trunks', (x, y, h * .38), .15, h * .76, 'wood', 8)
        verts = []
        profile = ((.12, .24), (.22, .65), (.40, .86), (.60, .94),
                   (.77, .75), (.91, .43), (1, .025))
        for j, (v, radius) in enumerate(profile):
            for k in range(10):
                a = TAU * k / 10
                r = radius * (1 + .065 * math.sin(k * 13 + j * 7))
                verts.append((x + r * math.cos(a), y + r * math.sin(a), .15 + h * v))
        faces = [(j * 10 + k, j * 10 + (k + 1) % 10,
                  (j + 1) * 10 + (k + 1) % 10, (j + 1) * 10 + k)
                 for j in range(len(profile) - 1) for k in range(10)]
        B.poly('Vegetation_Canopy', verts, faces, 'foliage_dark')

    # Quiet street furniture kept clear of all entrances and camera approach routes.
    for x, y in ((-10, -33), (10, -33), (-40, 30), (40, 30), (-32, -46), (32, -46)):
        for z in (.49, .61):
            B.box('Street_Props', (x, y, z), (2.1, .49, .085), 'wood')
        B.box('Street_Props', (x, y + .22, .96), (2.1, .09, .57), 'wood')
        for dx in (-.79, .79):
            B.box('Street_Props', (x + dx, y, .35), (.11, .5, .50), 'metal')
    for x in (-8, 8):
        for y in (-51, -37):
            B.cyl('Street_Props', (x, y, 1.85), .063, 3.7, 'metal', 8)
            B.cyl('Street_Props', (x, y, .33), .17, .6, 'metal', 8)
            B.box('Street_Props', (x, y, 3.78), (.42, .42, .64), 'glass')
            for z in (3.44, 4.11):
                B.box('Street_Props', (x, y, z), (.50, .50, .065), 'metal')
    for x in (-35, -28, -21, -14, 14, 21, 28, 35):
        B.cyl('Street_Props', (x, -30.8, .6), .115, .92, 'stone', 10)
        B.cyl('Street_Props', (x, -30.8, 1.08), .14, .09, 'limestone', 10)

    return {
        'landmark': '罗马斗兽场与意大利街区 / Roman Colosseum',
        'approximate_scale': '约 74 × 60 × 20.5 米；为 140 × 120 米探索区域压缩，非测绘重建',
        'spawn': [0, -52, .35],
        'description': '56 跨椭圆拱廊、三层真实镂空石拱、残缺阁楼层、24 级看台、竞技场遗迹、东/西/南三条通路、罗马石松与柏树、灰泥街屋和陶瓦屋顶。',
    }

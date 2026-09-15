"""Editable, low-cost Venetian palazzi and houses.

``create_building`` uses local +Z as up and -Y as the main facade.  ``height``
is the eaves height; the terracotta roof rises above it.  Geometry is real mesh
geometry, with no textures, booleans, or expensive modifiers.  Each window,
roof material, balcony, and architectural detail remains independently editable.
"""
import math
import random

import bpy

from scene_utils import mat, cube, cyl, mesh, curve, sphere, group_objects


class _Parts:
    """Small mesh accumulator: disconnected details stay editable in Edit Mode."""

    def __init__(self):
        self.verts = []
        self.faces = []

    def add(self, verts, faces):
        base = len(self.verts)
        self.verts.extend(verts)
        self.faces.extend(tuple(base + i for i in face) for face in faces)

    def box(self, center, size, transform=None):
        x, y, z = (s * .5 for s in size)
        cx, cy, cz = center
        vs = [(cx + a, cy + b, cz + c)
              for a, b, c in [(-x, -y, -z), (-x, -y, z), (-x, y, -z),
                              (-x, y, z), (x, -y, -z), (x, -y, z),
                              (x, y, -z), (x, y, z)]]
        if transform:
            vs = [transform(*v) for v in vs]
        fs = [(0, 4, 6, 2), (1, 3, 7, 5), (0, 1, 5, 4),
              (2, 6, 7, 3), (0, 2, 3, 1), (4, 5, 7, 6)]
        # Facade coordinates reflect one axis; their winding already compensates.
        if transform is None:
            fs = [tuple(reversed(f)) for f in fs]
        self.add(vs, fs)

    def ball(self, center, scale, segments=8, rings=4):
        cx, cy, cz = center
        vs = []
        for j in range(rings + 1):
            t = math.pi * j / rings
            for i in range(segments):
                a = math.tau * i / segments
                vs.append((cx + scale[0] * math.sin(t) * math.cos(a),
                           cy + scale[1] * math.sin(t) * math.sin(a),
                           cz + scale[2] * math.cos(t)))
        fs = []
        for j in range(rings):
            for i in range(segments):
                a = j * segments + i
                b = j * segments + (i + 1) % segments
                fs.append((a + segments, b + segments, b, a))
        self.add(vs, fs)

    def object(self, name, material):
        if self.verts:
            return mesh(name, self.verts, self.faces, material)
        return None


def _facade(face, width, depth):
    """Map horizontal u, outward distance, and z to building coordinates."""
    if face == 'front':
        return lambda u, out, z: (u, -depth / 2 - out, z)
    if face == 'right':
        return lambda u, out, z: (width / 2 + out, u, z)
    if face == 'left':
        return lambda u, out, z: (-width / 2 - out, -u, z)
    return lambda u, out, z: (-u, depth / 2 + out, z)


def _arch(cx, bottom, width, height, steps=12):
    rise = min(width * .51, height * .36)
    spring = bottom + height - rise
    pts = [(cx - width / 2, bottom), (cx + width / 2, bottom)]
    pts.extend((cx + width / 2 * math.cos(math.pi * i / steps),
                spring + rise * math.sin(math.pi * i / steps))
               for i in range(steps + 1))
    return pts


def _polygon_prism(name, outline, transform, back, front, material):
    n = len(outline)
    vs = [transform(u, out, z) for out in (back, front) for u, z in outline]
    fs = [tuple(reversed(range(n))), tuple(range(n, n * 2))]
    fs.extend((i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n))
    return mesh(name, vs, fs, material)


def _arch_frame(name, cx, bottom, width, height, transform, material,
                border=.105, out=.09):
    inner = _arch(cx, bottom, width, height)
    # Keeping the spring line constant makes the surround a proper stone arch.
    inner_rise = min(width * .51, height * .36)
    spring = bottom + height - inner_rise
    outer_w = width + border * 2
    outer = [(cx - outer_w / 2, bottom - border),
             (cx + outer_w / 2, bottom - border)]
    outer.extend((cx + outer_w / 2 * math.cos(math.pi * i / 12),
                  spring + (inner_rise + border) * math.sin(math.pi * i / 12))
                 for i in range(13))
    n = len(inner)
    vs = [transform(u, o, z)
          for o in (out - .045, out + .045) for ring in (outer, inner)
          for u, z in ring]
    fs = []
    for i in range(n):
        j = (i + 1) % n
        fs.extend([(i, j, n + j, n + i),
                   (2 * n + i, 3 * n + i, 3 * n + j, 2 * n + j),
                   (i, 2 * n + i, 2 * n + j, j),
                   (n + i, n + j, 3 * n + j, 3 * n + i)])
    return mesh(name, vs, [tuple(reversed(f)) for f in fs], material)


def _window(name, cx, bottom, ww, wh, transform, stone, dark, wood,
            shutter, shutter_highlight, shutters=True):
    _polygon_prism(name + ' | deep arched glass', _arch(cx, bottom, ww, wh),
                   transform, .005, .038, dark)
    _arch_frame(name + ' | carved limestone surround', cx, bottom, ww, wh,
                transform, stone)
    sill = _Parts()
    sill.box((cx, .13, bottom - .08), (ww + .36, .32, .13), transform)
    sill.box((cx, .085, bottom - .18), (ww + .18, .17, .07), transform)
    sill.object(name + ' | projecting stone sill', stone)
    bars = _Parts()
    rise = min(ww * .51, wh * .36)
    bars.box((cx, .062, bottom + wh / 2), (.040, .044, wh - .04), transform)
    bars.box((cx, .062, bottom + wh - rise - .03),
             (ww - .06, .044, .04), transform)
    bars.box((cx, .062, bottom + wh * .40), (ww - .06, .044, .035), transform)
    bars.object(name + ' | timber window mullions', wood)
    if shutters:
        panels = _Parts()
        slats = _Parts()
        sw = ww * .36
        sh = wh - rise * .35
        for side in (-1, 1):
            sx = cx + side * (ww / 2 + .15 + sw / 2)
            panels.box((sx, .070, bottom + sh / 2), (sw, .090, sh), transform)
            for edge in (-1, 1):
                slats.box((sx + edge * (sw / 2 - .028), .132, bottom + sh / 2),
                          (.032, .035, sh), transform)
            for j in range(max(5, int(sh / .16))):
                zz = bottom + .075 + j * (sh - .12) / max(4, int(sh / .16) - 1)
                slats.box((sx, .126, zz), (sw - .065, .056, .036), transform)
            for zz in (bottom + .20, bottom + sh - .20):
                panels.box((sx, .150, zz), (sw + .015, .025, .034), transform)
        panels.object(name + ' | paired painted shutters', shutter)
        slats.object(name + ' | shutter louvers', shutter_highlight)


def _balcony(name, cx, bottom, ww, transform, stone, iron, timber,
             foliage, flowers, rng):
    bw = ww + .66
    floor = _Parts()
    floor.box((cx, .32, bottom - .19), (bw, .72, .15), transform)
    for side in (-1, 1):
        floor.box((cx + side * bw * .32, .22, bottom - .34),
                  (.15, .38, .24), transform)
    floor.object(name + ' | balcony and corbels', stone)
    rail = _Parts()
    bz = bottom - .08
    top = bz + .66
    for z in (bz + .08, top):
        rail.box((cx, .64, z), (bw - .10, .033, .038), transform)
        for side in (-1, 1):
            rail.box((cx + side * (bw / 2 - .06), .34, z),
                     (.038, .60, .038), transform)
    for j in range(9):
        u = cx - bw / 2 + .07 + (bw - .14) * j / 8
        rail.box((u, .64, bz + .35), (.027, .030, .65), transform)
        if j % 2 == 0:
            # Small lozenges reference Venice's delicate wrought-iron rails.
            r = .085
            points = [(u, bz + .28 - r), (u + r, bz + .28),
                      (u, bz + .28 + r), (u - r, bz + .28)]
            inner = [(u + (x - u) * .60, bz + .28 + (z - bz - .28) * .60)
                     for x, z in points]
            vs = [transform(x, .659, z) for x, z in points + inner]
            rail.add(vs, [(i, (i + 1) % 4, (i + 1) % 4 + 4, i + 4)
                          for i in range(4)])
    rail.object(name + ' | iron balcony railing', iron)
    boxes = _Parts()
    boxes.box((cx, .73, bz + .38), (bw * .72, .23, .20), transform)
    boxes.object(name + ' | flower trough', timber)
    leaves = _Parts()
    blooms = _Parts()
    for j in range(6):
        u = cx + (j / 5 - .5) * bw * .65
        pos = transform(u, .74, bz + .52 + rng.uniform(-.018, .035))
        leaves.ball(pos, (.16, .15, .10))
        for k in range(2):
            pos = transform(u + rng.uniform(-.08, .08), .74 + rng.uniform(-.075, .075),
                            bz + .61 + rng.uniform(-.035, .025))
            blooms.ball(pos, (.055, .052, .050), 6, 3)
    leaves.object(name + ' | trailing geranium leaves', foliage)
    blooms.object(name + ' | geranium flowers', flowers)


def _roof(name, width, depth, height, rise, materials):
    rw = width + .52
    rd = depth + .54
    yz = [(-rd / 2, height + .02), (0, height + rise),
          (rd / 2, height + .02), (rd / 2, height - .10),
          (-rd / 2, height - .10)]
    verts = [(x, y, z) for x in (-rw / 2, rw / 2) for y, z in yz]
    faces = [tuple(reversed(range(5))), tuple(range(5, 10))]
    faces.extend((i, (i + 1) % 5, (i + 1) % 5 + 5, i + 5) for i in range(5))
    mesh(name + ' | pitched terracotta roof', verts,
         [tuple(reversed(f)) for f in faces], materials[0])
    tile_batches = [_Parts(), _Parts(), _Parts()]
    cols = max(10, int(rw / .28))
    rows = max(5, int(rd / 2 / .36))
    tile_w = rw / cols
    row_d = rd / 2 / rows
    for side in (-1, 1):
        for row in range(rows):
            for col in range(cols):
                vs = []
                x0 = -rw / 2 + col * tile_w
                for end in (0, 1):
                    ay = max(0, rd / 2 - (row + end) * row_d - end * .055)
                    yy = side * ay
                    zz = height + .025 + (rise - .02) * (1 - ay / (rd / 2))
                    for q in range(5):
                        xx = x0 + tile_w * q / 4
                        vs.append((xx, yy, zz + .028 + .043 * math.sin(math.pi * q / 4)))
                faces = [(q, q + 1, q + 6, q + 5) for q in range(4)]
                if side == 1:
                    faces = [tuple(reversed(f)) for f in faces]
                tile_batches[(col * 7 + row * 3 + (side == 1)) % 3].add(vs, faces)
    for i, batch in enumerate(tile_batches):
        batch.object(name + ' | individually shaped barrel tiles ' + str(i + 1),
                     materials[i])
    ridge = _Parts()
    for col in range(cols):
        xx = -rw / 2 + col * tile_w
        vs = []
        for x in (xx, xx + tile_w + .025):
            for j in range(7):
                a = math.pi * j / 6
                vs.append((x, .115 * math.cos(a), height + rise + .105 * math.sin(a)))
        ridge.add(vs, [(j, j + 1, j + 8, j + 7) for j in range(6)])
    ridge.object(name + ' | terracotta ridge caps', materials[1])


def _awning(name, width, bottom, transform, cream, cloth, iron):
    batches = [_Parts(), _Parts()]
    span = min(width * .46, 2.65)
    bands = 10
    sw = span / bands
    for i in range(bands):
        x0 = -span / 2 + i * sw
        x1 = x0 + sw
        verts = [transform(x0, .13, bottom), transform(x1, .13, bottom),
                 transform(x1, 1.10, bottom - .32),
                 transform(x0, 1.10, bottom - .32)]
        batches[i % 2].add(verts, [(3, 2, 1, 0)])
        # Each cloth stripe ends in its own rounded, solid silhouette.
        valance = [(x0, bottom - .31), (x1, bottom - .31)]
        valance.extend((x0 + sw / 2 + sw / 2 * math.cos(j * math.pi / 8),
                        bottom - .43 - .07 * math.sin(j * math.pi / 8))
                       for j in range(9))
        batches[i % 2].add([transform(x, 1.104, z) for x, z in valance],
                          [tuple(reversed(range(len(valance))))])
    for i, material in enumerate((cream, cloth)):
        batches[i].object(name + ' | cafe canvas stripe ' + str(i + 1), material)
    supports = _Parts()
    for side in (-1, 1):
        supports.box((side * span / 2, .60, bottom - .34), (.035, .98, .035), transform)
    supports.box((0, 1.09, bottom - .32), (span + .05, .035, .035), transform)
    supports.object(name + ' | cafe awning supports', iron)


def create_building(name, loc, width=6, depth=5, height=9,
                    color=(.8, .4, .25), rotation=0.0, seed=0, variant=0):
    """Create a complete house and return its transformable parent Empty.

    Width/depth describe the plaster shell; balconies project towards local -Y.
    Height is the eaves height, floors are selected automatically (2–4), and
    variant % 3 == 1 adds a striped cafe canopy.  All randomness is seed-local.
    """
    before = set(bpy.data.objects)
    rng = random.Random(seed)
    width = max(3.6, float(width))
    depth = max(3.3, float(depth))
    height = max(5.5, float(height))
    floors = max(2, min(4, int(round(height / 3.0))))
    story = height / floors
    color_key = '_'.join(str(int(c * 255)) for c in color[:3])
    plaster = mat('Venice | warm lime plaster ' + color_key, color, .88)
    shade = mat('Venice | shaded lime plaster ' + color_key,
                tuple(c * .91 for c in color[:3]), .9)
    stone = mat('Venice | aged Istrian limestone', (.81, .76, .61), .83)
    stone_top = mat('Venice | pale limestone cornice', (.94, .86, .70), .76)
    glass = mat('Venice | deep blue green window glass', (.032, .073, .080), .22, .15)
    timber = mat('Venice | aged walnut joinery', (.18, .092, .045), .8)
    iron = mat('Venice | charcoal wrought iron', (.041, .056, .050), .55, .55)
    brass = mat('Venice | weathered brass', (.56, .34, .105), .38, .7)
    shutter_colors = [(.12, .27, .23), (.20, .33, .26), (.11, .27, .30), (.28, .34, .23)]
    sc = shutter_colors[(seed + variant) % len(shutter_colors)]
    shutter = mat('Venice | shutter paint ' + str((seed + variant) % 4), sc, .8)
    shutter_light = mat('Venice | shutter louver ' + str((seed + variant) % 4),
                        tuple(c * 1.13 for c in sc), .8)
    terra = [mat('Venice | terracotta ' + str(i), c, .9) for i, c in enumerate(
        [(.50, .18, .075), (.65, .265, .115), (.59, .215, .09)])]
    foliage = mat('Venice | balcony geranium leaves', (.11, .29, .13), .8)
    flowers = mat('Venice | coral geranium flowers', (.85, .115, .16), .6)
    cream = mat('Venice | cafe canvas cream', (.92, .83, .64), .92)
    cloth = mat('Venice | cafe canvas wine red', (.43, .105, .10), .92)

    cube(name + ' | solid plaster walls', (0, 0, height / 2),
         (width, depth, height), plaster)
    cube(name + ' | stone foundation', (0, 0, .22),
         (width + .12, depth + .12, .44), stone)
    cube(name + ' | foundation weathering band', (0, 0, .43),
         (width + .16, depth + .16, .12), stone_top)
    for floor in range(1, floors):
        cube(name + ' | string course ' + str(floor), (0, 0, floor * story - .08),
             (width + .13, depth + .13, .105), stone)
    for i, (z, size, thick) in enumerate([(height - .26, .12, .14),
                                         (height - .10, .29, .16),
                                         (height + .025, .42, .09)]):
        cube(name + ' | stepped eaves cornice ' + str(i), (0, 0, z),
             (width + size, depth + size, thick), stone_top)

    # Alternating narrow corner blocks give the facades their masonry rhythm.
    quoins = _Parts()
    for sx in (-1, 1):
        for sy in (-1, 1):
            for i in range(int((height - .70) / .39)):
                z = .64 + i * .39
                reach = .30 if i % 2 == 0 else .20
                quoins.box((sx * (width / 2 - reach / 2 + .04),
                            sy * (depth / 2 + .035), z), (reach, .09, .31))
                quoins.box((sx * (width / 2 + .035),
                            sy * (depth / 2 - reach / 2 + .04), z), (.09, reach, .31))
    quoins.object(name + ' | alternating limestone corner quoins', stone)

    front = _facade('front', width, depth)
    cols = 3 if width >= 5.3 else 2
    positions = [-width * .31, 0, width * .31] if cols == 3 else [-width * .24, width * .24]
    ww = min(.90, width / cols * .43)
    wh = min(1.78, story * .60)
    for floor in range(1, floors):
        for j, x in enumerate(positions):
            bottom = floor * story + .48
            wn = name + ' | front F' + str(floor + 1) + ' W' + str(j + 1)
            _window(wn, x, bottom, ww, wh, front, stone_top, glass, timber,
                    shutter, shutter_light)
            balcony_here = (floor == 1 and j == cols // 2)
            if variant % 4 == 2 and floor == floors - 1 and j == 0:
                balcony_here = True
            if balcony_here:
                _balcony(wn, x, bottom, ww, front, stone_top, iron, timber,
                         foliage, flowers, rng)

    # Side windows make the module usable at corners, canals, and free-standing lots.
    side_cols = 2 if depth >= 4.3 else 1
    for face in ('left', 'right'):
        trans = _facade(face, width, depth)
        for floor in range(1, floors):
            for j in range(side_cols):
                x = (j - (side_cols - 1) / 2) * depth * .42
                _window(name + ' | ' + face + ' F' + str(floor + 1) + ' W' + str(j + 1),
                        x, floor * story + .48, min(.79, ww), wh, trans,
                        stone_top, glass, timber, shutter, shutter_light,
                        shutters=(j + floor + variant) % 3 != 0)

    # Rear fenestration is restrained, so roof-level city views still read as complete.
    rear = _facade('rear', width, depth)
    for floor in range(1, floors):
        for j in (-1, 1):
            _window(name + ' | rear F' + str(floor + 1) + ' W' + str(j),
                    j * width * .24, floor * story + .48, min(.76, ww), wh,
                    rear, stone, glass, timber, shutter, shutter_light, shutters=False)

    # A tall arched timber entrance, its boards, two leaves, and brass hardware.
    door_w = min(1.12, width * .22)
    door_h = min(2.43, story * .79)
    _polygon_prism(name + ' | arched walnut entrance', _arch(0, .20, door_w, door_h),
                   front, .008, .070, timber)
    _arch_frame(name + ' | entrance limestone portal', 0, .20, door_w, door_h,
                front, stone_top, .145, .12)
    boards = _Parts()
    for i in range(7):
        x = (i - 3) * door_w / 7
        boards.box((x, .082, .22 + door_h * .37), (.021, .022, door_h * .73), front)
    boards.box((0, .086, .22 + door_h * .73), (door_w * .90, .03, .07), front)
    boards.object(name + ' | entrance board grooves', iron)
    hardware = _Parts()
    for x in (-door_w * .15, door_w * .15):
        hardware.ball(front(x, .108, 1.12), (.046, .037, .046), 8, 4)
    hardware.object(name + ' | paired brass door knobs', brass)
    step = _Parts()
    step.box((0, .23, .09), (door_w + .46, .56, .18), front)
    step.object(name + ' | limestone doorstep', stone)
    for j in (-1, 1):
        _window(name + ' | ground floor window ' + str(j), j * width * .30,
                .92, min(.83, ww), min(1.20, story * .40), front,
                stone_top, glass, timber, shutter, shutter_light, shutters=False)
    # Small iron grilles add a convincing ground-level scale cue.
    grilles = _Parts()
    for j in (-1, 1):
        for k in (-1, 0, 1):
            grilles.box((j * width * .30 + k * min(.83, ww) * .24, .16, 1.37),
                        (.022, .025, .83), front)
    grilles.object(name + ' | ground window security grilles', iron)

    # Restrained patches of exposed brick just above the limestone waterline.
    bricks = _Parts()
    for side in (-1, 1):
        for row in range(2):
            for j in range(3 - row):
                x = side * (width * .39 - j * .20) + row * .07
                bricks.box((x, .012, .58 + row * .115), (.18, .030, .09), front)
    bricks.object(name + ' | exposed brick at waterline', terra[1])

    rise = max(.90, min(1.60, depth * .245))
    _roof(name, width, depth, height, rise, terra)
    # One distinctive flared Venetian chimney with a pale projecting crown.
    chimney_x = width * (.27 if seed % 2 else -.27)
    chimney_y = depth * .16
    roof_z = height + rise * (1 - abs(chimney_y) / (depth / 2 + .27))
    cube(name + ' | chimney shaft', (chimney_x, chimney_y, roof_z + .25),
         (.43, .47, .86), shade)
    verts = []
    for z, r in ((roof_z + .46, .24), (roof_z + 1.10, .40)):
        verts.extend((chimney_x + x * r, chimney_y + y * r, z)
                     for x, y in ((-1, -1), (1, -1), (1, 1), (-1, 1)))
    mesh(name + ' | flared Venetian chimney hood', verts,
         [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5),
          (2, 3, 7, 6), (3, 0, 4, 7)], terra[0])
    cube(name + ' | chimney limestone cap', (chimney_x, chimney_y, roof_z + 1.13),
         (.87, .87, .13), stone_top)
    vents = _Parts()
    for sx in (-1, 1):
        for sy in (-1, 1):
            vents.box((chimney_x + sx * .17, chimney_y + sy * .403, roof_z + .98),
                      (.16, .010, .10))
    vents.object(name + ' | chimney vent apertures', iron)
    if variant % 3 == 1:
        _awning(name, width, min(door_h + .51, story - .10), front, cream, cloth, iron)

    parent = group_objects(name, before, loc, rotation)
    parent['asset_type'] = 'Editable Venetian residential architecture'
    parent['width'] = width
    parent['depth'] = depth
    parent['eaves_height'] = height
    parent['floors'] = floors
    parent['procedural_seed'] = seed
    parent['variant'] = variant
    return parent

# Shared module contract

Each asset module exports `build()` and imports `from common import *`. No reset, save, render or scene/world changes in asset modules. All coordinates meters. Default front faces negative Y. Use collection('Name') to set active output collection. Material keys: concrete, concrete_dark, asphalt, steel, rust, iron, white, cream, teal, yellow, red, blue, black, rubber, glass, wood, foliage, foliage_dry, soil, light_cyan, light_warm, screen, silver.

Functions (all return Blender object):
box(name, loc, size, mat, bevel=0.02, rot=(0,0,0))
cyl(name, loc, radius, depth, mat, vertices=16, rot=(0,0,0), radius_top=None)
beam(name, a, b, radius, mat, vertices=8)
curve(name, points, radius, mat, cyclic=False)
mesh(name, verts, faces, mat)
ico(name, loc, scale, mat, subdivisions=2)
torus(name, loc, major, minor, mat, rot=(0,0,0))
text_obj(name, body, loc, size, mat, rot=(pi/2,0,0), align='CENTER')  # upright front facing -Y
photo_plane(name, verts, uvcoords, reference_index) # four verts, uv (0..1), original photo map
material(key) # returns existing shared material
collection(name) # switch output collection

Avoid large unjoined repeated object sets: for >100 repetitions construct a mesh with repeated verts/faces. Bevel boxes only important outlines. Do not create >1500 objects per module. Existing material keys may be reused. For unique materials use bpy.data.materials.new(). Object names use meaningful English/Chinese. All file paths relative to project via Path(__file__).resolve().parents[1].

Root layout: ground spans X=-23..23 Y=-23..29. Entrance y=-17. Left charging canopy x=-11..-3, y=-5..16 roof z=3.9. Equipment front faces +X (rotation z=pi/2). Office center=(10,0) size=(6,5) two levels each 2.8 high; terrace in front y=-3.6..-2.5 z=2.9; stairs east x=14, y=-6..0. Rear warehouse x=-14..20,y=22..29. Crane trucks parked x=6,10,14,18, y=10..16 facing south. Main aisle around x=0 from y=-18..19 must remain open.

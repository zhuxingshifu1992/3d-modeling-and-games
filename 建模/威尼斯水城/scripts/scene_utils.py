"""Reusable geometry helpers for the editable Venetian city scene."""
import bpy
import math
from mathutils import Vector

ACTIVE_COLLECTION = None

def collection(name):
    global ACTIVE_COLLECTION
    c = bpy.data.collections.get(name)
    if c is None:
        c = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(c)
    ACTIVE_COLLECTION = c
    return c

def register(obj):
    if ACTIVE_COLLECTION:
        for c in list(obj.users_collection):
            c.objects.unlink(obj)
        ACTIVE_COLLECTION.objects.link(obj)
    return obj

def mat(name, color, roughness=0.55, metallic=0.0):
    existing = bpy.data.materials.get(name)
    if existing:
        return existing
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color[:3], color[3] if len(color)>3 else 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = m.diffuse_color
    p.inputs['Roughness'].default_value = roughness
    p.inputs['Metallic'].default_value = metallic
    return m

def mesh(name, verts, faces, material=None):
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    (ACTIVE_COLLECTION or bpy.context.scene.collection).objects.link(obj)
    if material:
        data.materials.append(material)
    return obj

def cube(name, loc, size, material=None, bevel=0.0):
    x,y,z=[s/2 for s in size]
    verts=[(-x,-y,-z),(-x,-y,z),(-x,y,-z),(-x,y,z),(x,-y,-z),(x,-y,z),(x,y,-z),(x,y,z)]
    ob=mesh(name,verts,[(2,6,4,0),(5,7,3,1),(4,5,1,0),(3,7,6,2),(1,3,2,0),(6,7,5,4)],material)
    ob.location=loc
    if bevel:
        mod=ob.modifiers.new('Soft worn edges','BEVEL'); mod.width=bevel; mod.segments=2
    return ob

def cyl(name, loc, radius, depth, material=None, vertices=16):
    verts=[]
    for z in [-depth/2,depth/2]:
        verts += [(radius*math.cos(2*math.pi*i/vertices),radius*math.sin(2*math.pi*i/vertices),z) for i in range(vertices)]
    faces=[tuple(reversed(range(vertices))),tuple(range(vertices,2*vertices))]
    faces += [(i,(i+1)%vertices,(i+1)%vertices+vertices,i+vertices) for i in range(vertices)]
    ob=mesh(name,verts,faces,material); ob.location=loc
    return ob

def curve(name, points, radius, material=None, cyclic=False):
    d=bpy.data.curves.new(name,'CURVE'); d.dimensions='3D'; d.resolution_u=1
    d.bevel_depth=radius; d.bevel_resolution=1
    s=d.splines.new('POLY'); s.points.add(len(points)-1)
    for p,co in zip(s.points,points): p.co=(*co,1)
    s.use_cyclic_u=cyclic
    ob=bpy.data.objects.new(name,d)
    (ACTIVE_COLLECTION or bpy.context.scene.collection).objects.link(ob)
    if material: d.materials.append(material)
    return ob

def sphere(name,loc,scale,material=None,segments=16,rings=8):
    verts=[]; faces=[]
    for j in range(rings+1):
        t=math.pi*j/rings
        for i in range(segments):
            a=math.tau*i/segments
            verts.append((scale[0]*math.sin(t)*math.cos(a),scale[1]*math.sin(t)*math.sin(a),scale[2]*math.cos(t)))
    for j in range(rings):
        for i in range(segments):
            a=j*segments+i; b=j*segments+(i+1)%segments
            faces.append((a,a+segments,b+segments,b))
    ob=mesh(name,verts,faces,material); ob.location=loc
    for p in ob.data.polygons:p.use_smooth=True
    return ob

def group_objects(name, before, loc=(0,0,0), rotation=0):
    members=[o for o in bpy.data.objects if o not in before]
    parent=bpy.data.objects.new(name,None)
    (ACTIVE_COLLECTION or bpy.context.scene.collection).objects.link(parent)
    for o in members:
        if o.parent is None:o.parent=parent
    parent.location=loc; parent.rotation_euler[2]=rotation
    return parent

def aim(obj, target):
    obj.rotation_euler=(Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler()

def beam(name,a,b,radius,material):
    return curve(name,[a,b],radius,material)

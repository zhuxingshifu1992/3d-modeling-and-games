"""Metric geometry and portable textured PBR materials for the charging yard."""
import bpy, bmesh, math, random
import numpy as np
from math import pi, sin, cos
from mathutils import Vector
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
_COL=None
_MATS={}
_FONT=None

def collection(name):
    global _COL
    c=bpy.data.collections.get(name)
    if c is None:
        c=bpy.data.collections.new(name); bpy.context.scene.collection.children.link(c)
    _COL=c
    return c

def _link(obj):
    c=_COL or bpy.context.scene.collection
    for old in list(obj.users_collection): old.objects.unlink(obj)
    c.objects.link(obj)
    return obj

def material(key):
    if isinstance(key,bpy.types.Material): return key
    return _MATS.get(key) or bpy.data.materials.get(key) or _MATS['steel']

def _uv(obj):
    me=obj.data
    if not isinstance(me,bpy.types.Mesh):return
    me.update()
    uv=me.uv_layers.active or me.uv_layers.new(name='UVMap')
    for p in me.polygons:
        ax=max(range(3),key=lambda i:abs(p.normal[i]))
        a,b=((1,2),(0,2),(0,1))[ax]
        for li in p.loop_indices:
            co=me.vertices[me.loops[li].vertex_index].co
            uv.data[li].uv=(co[a]/1.7,co[b]/1.7)

def _finish(obj,name,mat,uv=True):
    obj.name=name;_link(obj)
    obj.data.materials.append(material(mat))
    if uv:_uv(obj)
    return obj

def mesh(name,verts,faces,mat):
    me=bpy.data.meshes.new(name+'_Mesh');me.from_pydata(verts,[],faces);me.update()
    ob=bpy.data.objects.new(name,me);(_COL or bpy.context.scene.collection).objects.link(ob)
    me.materials.append(material(mat));_uv(ob)
    return ob

def box(name,loc,size,mat,bevel=.02,rot=(0,0,0)):
    x,y,z=[s/2 for s in size]
    v=[(-x,-y,-z),(x,-y,-z),(x,y,-z),(-x,y,-z),(-x,-y,z),(x,-y,z),(x,y,z),(-x,y,z)]
    ob=mesh(name,v,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],mat)
    ob.location=loc;ob.rotation_euler=rot
    if bevel>0:
        mod=ob.modifiers.new('Manufactured edge radius','BEVEL');mod.width=min(bevel,min(size)*.48);mod.segments=2
    return ob

def cyl(name,loc,radius,depth,mat,vertices=16,rot=(0,0,0),radius_top=None):
    rt=radius if radius_top is None else radius_top
    vs=[(r*cos(j*2*pi/vertices),r*sin(j*2*pi/vertices),z) for r,z in [(radius,-depth/2),(rt,depth/2)] for j in range(vertices)]
    fs=[tuple(reversed(range(vertices))),tuple(range(vertices,vertices*2))]+[(j,(j+1)%vertices,(j+1)%vertices+vertices,j+vertices) for j in range(vertices)]
    ob=mesh(name,vs,fs,mat);ob.location=loc;ob.rotation_euler=rot
    for p in ob.data.polygons:p.use_smooth=len(p.vertices)==4
    return ob

def beam(name,a,b,radius,mat,vertices=8):
    a,b=Vector(a),Vector(b);d=b-a
    ob=cyl(name,(a+b)/2,radius,max(d.length,.0001),mat,vertices)
    ob.rotation_euler=d.to_track_quat('Z','Y').to_euler();return ob

def curve(name,points,radius,mat,cyclic=False):
    cu=bpy.data.curves.new(name+'_Path','CURVE');cu.dimensions='3D';cu.resolution_u=12
    cu.bevel_depth=radius;cu.bevel_resolution=2;cu.resolution_u=10
    sp=cu.splines.new('BEZIER');sp.bezier_points.add(len(points)-1)
    for p,co in zip(sp.bezier_points,points):p.co=co;p.handle_left_type='AUTO';p.handle_right_type='AUTO'
    sp.use_cyclic_u=cyclic
    ob=bpy.data.objects.new(name,cu);(_COL or bpy.context.scene.collection).objects.link(ob);cu.materials.append(material(mat));return ob

def ico(name,loc,scale,mat,subdivisions=2):
    me=bpy.data.meshes.new(name+'_Mesh');bm=bmesh.new();bmesh.ops.create_icosphere(bm,subdivisions=subdivisions,radius=1);bm.to_mesh(me);bm.free()
    ob=bpy.data.objects.new(name,me);(_COL or bpy.context.scene.collection).objects.link(ob);ob.location=loc
    for v in ob.data.vertices:
        v.co.x*=scale[0];v.co.y*=scale[1];v.co.z*=scale[2]
    _finish(ob,name,mat)
    for p in ob.data.polygons:p.use_smooth=True
    return ob

def torus(name,loc,major,minor,mat,rot=(0,0,0)):
    vs=[];fs=[]
    for i in range(32):
        a=i*2*pi/32
        for j in range(8):
            b=j*2*pi/8;r=major+minor*cos(b);vs.append((r*cos(a),r*sin(a),minor*sin(b)))
    for i in range(32):
        for j in range(8):fs.append((i*8+j,((i+1)%32)*8+j,((i+1)%32)*8+(j+1)%8,i*8+(j+1)%8))
    ob=mesh(name,vs,fs,mat);ob.location=loc;ob.rotation_euler=rot
    for p in ob.data.polygons:p.use_smooth=True
    return ob

def text_obj(name,body,loc,size,mat,rot=(pi/2,0,0),align='CENTER'):
    cu=bpy.data.curves.new(name+'_Type','FONT');cu.body=body;cu.size=size;cu.align_x=align;cu.align_y='CENTER';cu.extrude=.001
    if _FONT:cu.font=_FONT
    ob=bpy.data.objects.new(name,cu);(_COL or bpy.context.scene.collection).objects.link(ob);ob.location=loc;ob.rotation_euler=rot
    cu.materials.append(material(mat));return ob

def photo_plane(name,verts,uvcoords,reference_index):
    # Public edition uses a neutral equipment panel in place of photo-derived labels.
    return mesh(name,verts,[(0,1,2,3)],material('teal'))


def _noise(n,grid,rng):
    a=rng.random((grid+1,grid+1));a[-1]=a[0];a[:,-1]=a[:,0]
    x=np.linspace(0,grid,n,endpoint=False);ix=x.astype(int);f=x-ix;f=f*f*(3-2*f)
    v=a[:,ix]*(1-f)+a[:,ix+1]*f
    return v[ix,:]*(1-f[:,None])+v[ix+1,:]*f[:,None]

def _image(name,arr,folder,noncolor=False):
    n=arr.shape[0];data=np.ones((n,n,4),dtype=np.float32)
    data[:,:,:3]=arr[:,:,None] if arr.ndim==2 else arr
    im=bpy.data.images.new(name,width=n,height=n,alpha=False)
    if noncolor:im.colorspace_settings.name='Non-Color'
    im.pixels.foreach_set(data.ravel());im.filepath_raw=str(folder/(name+'.png'));im.file_format='PNG';im.save();im.pack()
    return im

def create_materials():
    global _FONT
    folder=ROOT/'assets'/'textures';folder.mkdir(parents=True,exist_ok=True)
    # Colors deliberately dusty and restrained. Rust is iron oxide, not saturated orange.
    specs={
      'concrete':('79766a',0,.92,'stone'), 'concrete_dark':('41453d',0,.96,'stone'),
      'asphalt':('53514b',0,.96,'stone'), 'steel':('666d68',.65,.65,'paint'),
      'rust':('6d3922',.32,.91,'rust'), 'iron':('252c2c',.7,.64,'paint'),
      'white':('ccc9b7',.15,.7,'paint'), 'cream':('b4a990',0,.89,'paint'),
      'teal':('23685e',.34,.68,'paint'), 'yellow':('aa813e',.22,.7,'paint'),
      'red':('982f24',.18,.69,'paint'), 'blue':('36545e',.3,.74,'paint'),
      'black':('161c1b',.2,.75,'plain'), 'rubber':('161917',0,.96,'plain'),
      'glass':('253c3f',.48,.18,'glass'), 'wood':('4b3d29',0,.95,'wood'),
      'foliage':('414b25',0,.91,'leaf'), 'foliage_dry':('77704a',0,.98,'leaf'),
      'soil':('413d2b',0,1,'stone'), 'silver':('969d96',.8,.44,'paint'),
      'screen':('092327',.2,.21,'glass'),
    }
    n=512
    for i,(key,(rgb,metal,rough,kind)) in enumerate(specs.items()):
        rng=np.random.default_rng(820+i);co=np.array([int(rgb[j:j+2],16)/255 for j in (0,2,4)])
        large=_noise(n,7,rng);mid=_noise(n,39,rng);fine=rng.random((n,n));speck=_noise(n,120,rng)
        h=.4*large+.34*mid+.16*fine+.10*speck
        col=np.clip(co[None,None,:]*(.79+.36*h[:,:,None]),0,1)
        if kind=='paint':
            mask=np.clip((large*.66+mid*.34-.66)*6,0,.82)
            oxide=np.array([.20,.105,.048])[None,None,:]*(.5+h[:,:,None])
            if key in ('white','cream','silver'):
                # Plastic shells and stainless appliances collect dirt, not steel rust.
                mask*=.35
                oxide=np.array([.27,.28,.24])[None,None,:]*(.7+h[:,:,None]*.4)
            col=col*(1-mask[:,:,None])+oxide*mask[:,:,None]
            h=h-mask*.25
        if kind=='wood':
            xx=np.arange(n)[None,:];streak=(np.sin(xx*.37+large*20)+1)/2
            col*=.65+.4*streak[:,:,None];h=.5*h+.5*streak
        if kind=='glass':
            col=np.broadcast_to(co,(n,n,3)).copy()*(.88+.18*large[:,:,None]);h=np.zeros((n,n))+.5
        if kind=='rust':col*=.7+.65*mid[:,:,None]
        base=_image(key+'_color',col,folder)
        rr=np.clip(rough+(h-.5)*.25,.05,1);rimg=_image(key+'_roughness',rr,folder,True)
        bump_strength=.32 if kind in ('stone','rust','wood') else .12
        dx=(np.roll(h,-1,1)-np.roll(h,1,1))*bump_strength
        dy=(np.roll(h,-1,0)-np.roll(h,1,0))*bump_strength
        nm=np.stack((-dx,-dy,np.ones_like(h)),axis=-1);nm/=np.linalg.norm(nm,axis=-1)[:,:,None]
        normal=_image(key+'_normal',nm*.5+.5,folder,True)
        mat=bpy.data.materials.new(key);mat.use_nodes=True;mat.diffuse_color=(*co,1)
        nt=mat.node_tree;bs=nt.nodes.get('Principled BSDF');bs.inputs['Metallic'].default_value=metal;bs.inputs['Roughness'].default_value=rough
        tx=nt.nodes.new('ShaderNodeTexImage');tx.image=base;tx.location=(-650,220);nt.links.new(tx.outputs['Color'],bs.inputs['Base Color'])
        tr=nt.nodes.new('ShaderNodeTexImage');tr.image=rimg;tr.location=(-650,-30);nt.links.new(tr.outputs['Color'],bs.inputs['Roughness'])
        tn=nt.nodes.new('ShaderNodeTexImage');tn.image=normal;tn.location=(-650,-260)
        no=nt.nodes.new('ShaderNodeNormalMap');no.inputs['Strength'].default_value=.65;no.location=(-360,-200)
        nt.links.new(tn.outputs['Color'],no.inputs['Color']);nt.links.new(no.outputs['Normal'],bs.inputs['Normal'])
        _MATS[key]=mat
    for key,co,power in [('light_cyan',(.06,.8,.57),3),('light_warm',(1,.42,.1),3.5)]:
        mat=bpy.data.materials.new(key);mat.use_nodes=True;mat.diffuse_color=(*co,1)
        bs=mat.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(*co,1)
        bs.inputs['Emission Color'].default_value=(*co,1);bs.inputs['Emission Strength'].default_value=power
        _MATS[key]=mat
    for path in [ROOT/'assets/fonts/NotoSansSC.ttf']:
        if Path(path).exists():
            try:_FONT=bpy.data.fonts.load(path);break
            except Exception:pass
    return _MATS

def batched_boxes(name,boxes,mat):
    verts=[];faces=[]
    for loc,size,angle in boxes:
        x,y,z=loc;sx,sy,sz=[s/2 for s in size];c,s=cos(angle),sin(angle);off=len(verts)
        for a,b,d in [(-sx,-sy,-sz),(sx,-sy,-sz),(sx,sy,-sz),(-sx,sy,-sz),(-sx,-sy,sz),(sx,-sy,sz),(sx,sy,sz),(-sx,sy,sz)]:verts.append((x+a*c-b*s,y+a*s+b*c,z+d))
        faces.extend(tuple(off+j for j in f) for f in [(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)])
    return mesh(name,verts,faces,mat)

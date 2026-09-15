"""Batched, metric Blender geometry and portable image-based PBR materials."""
import bpy, bmesh, math, random
import numpy as np
from mathutils import Vector
from pathlib import Path

PALETTE = {
 'limestone':('baa98f','stone',0,.84,2.4), 'stone':('929089','stone',0,.9,2),
 'plaster':('d3c9b4','plaster',0,.85,3), 'warm_plaster':('bda083','plaster',0,.85,3),
 'brick':('986955','brick',0,.85,2), 'terracotta':('805243','roof',0,.82,1.8),
 'slate':('404b51','roof',0,.72,2), 'metal':('3c4445','metal',.75,.42,3),
 'bronze':('796753','metal',.68,.48,3), 'glass':('2e4957','glass',.28,.16,3),
 'wood':('78604b','wood',0,.83,1.6), 'dark_wood':('4c3c31','wood',0,.84,1.6),
 'grass':('647156','grass',0,.98,7), 'foliage':('526344','grass',0,.97,3),
 'foliage_dark':('364d3a','grass',0,.98,3), 'gravel':('a79880','gravel',0,.99,3),
 'paving':('a49f91','paving',0,.88,4), 'water':('426d74','water',.22,.21,8),
 'snow':('e2e7e4','snow',0,.82,6), 'rock':('858783','rock',0,.94,5),
 'rock_dark':('626b6c','rock',0,.94,5), 'white':('dedcd0','plaster',0,.76,3),
 'red':('963c31','plaster',0,.75,3), 'gold':('b79b60','metal',.7,.4,2),
 'asphalt':('545754','gravel',0,.94,5),
 'parquet':('947354','wood',0,.43,3), 'marble':('cac8bb','stone',0,.28,3),
 'fabric':('768a87','plaster',0,.94,1.5), 'leather':('685044','wood',0,.58,2),
 'wallpaper':('beb69a','plaster',0,.84,2), 'ceiling':('e2dcca','plaster',0,.88,4),
 'emissive':('fff1cb','plaster',0,.3,1),
}

def material_library(folder):
    folder=Path(folder); folder.mkdir(exist_ok=True)
    mats={}; n=512
    yy,xx=np.mgrid[0:n,0:n].astype(np.float32); u=xx/n; v=yy/n
    for index,(name,(rgb,kind,metal,rough,tile)) in enumerate(PALETTE.items()):
        rng=np.random.default_rng(101+index)
        fine=rng.standard_normal((n,n)).astype(np.float32)
        waves=(np.sin(u*math.tau*7+np.sin(v*math.tau*3))*0.45 + np.cos(v*math.tau*9+np.sin(u*math.tau*2))*.3)
        h=.5+.1*waves+.035*fine
        if kind in ('stone','brick','paving','roof'):
            cols,rows={'stone':(4,6),'brick':(6,12),'paving':(7,7),'roof':(7,12)}[kind]
            row=np.floor(v*rows); fx=(u*cols+.5*(row%2))%1; fy=(v*rows)%1
            joint=(fx<.022)|(fy<.045)
            cell=(np.sin(np.floor(u*cols+.5*(row%2))*19+row*7)*.07)
            h+=cell; h[joint]=.18+.025*fine[joint]
            if kind=='roof':h+=.10*np.sin(fx*math.pi)+.07*fy
        elif kind=='wood':
            h+=.13*np.sin(v*math.tau*24+.8*np.sin(u*math.tau*2))+.06*np.sin(v*math.tau*78+u*12)
            h[(v*7)%1<.018]=.17
        elif kind=='grass': h=.5+.055*waves+.10*fine
        elif kind=='rock': h+=.10*np.sin(u*32+v*63+waves*3)+.08*np.cos(u*81-v*40)
        elif kind=='metal': h=.5+.012*fine+.018*np.sin(v*math.tau*56)
        elif kind=='glass': h=np.full((n,n),.5,dtype=np.float32)
        elif kind=='water': h=.5+.07*np.sin(v*math.tau*22+np.sin(u*math.tau*3))
        elif kind=='snow': h=.5+.022*fine+.04*waves
        h=np.clip(h,.08,.95)
        color=np.array([int(rgb[k:k+2],16)/255 for k in (0,2,4)],dtype=np.float32)
        variation=(.82+.34*h)[...,None]
        pixels=np.empty((n,n,4),dtype=np.float32); pixels[:,:,:3]=np.clip(color*variation,0,1); pixels[:,:,3]=1
        image=bpy.data.images.new(name+'_BaseColor',width=n,height=n)
        image.pixels.foreach_set(pixels.ravel()); image.filepath_raw=str(folder/(name+'_BaseColor.png')); image.file_format='PNG'; image.save()
        # Texture is stored as an ordinary PNG and all exported materials use UVs.
        grad_y=(np.roll(h,-1,axis=0)-np.roll(h,1,axis=0))*1.3
        grad_x=(np.roll(h,-1,axis=1)-np.roll(h,1,axis=1))*1.3
        norm=np.stack((-grad_x,-grad_y,np.ones_like(h)),axis=-1)
        norm/=np.linalg.norm(norm,axis=-1)[...,None]
        pixels[:,:,:3]=norm*.5+.5
        normal=bpy.data.images.new(name+'_Normal',width=n,height=n)
        normal.colorspace_settings.name='Non-Color'; normal.pixels.foreach_set(pixels.ravel())
        normal.filepath_raw=str(folder/(name+'_Normal.png')); normal.file_format='PNG'; normal.save()
        mat=bpy.data.materials.new(name); mat.use_nodes=True
        mat.diffuse_color=(*color,1); nodes=mat.node_tree.nodes; links=mat.node_tree.links
        bsdf=nodes.get('Principled BSDF'); bsdf.inputs['Metallic'].default_value=metal; bsdf.inputs['Roughness'].default_value=rough
        tex=nodes.new('ShaderNodeTexImage'); tex.image=image; tex.extension='REPEAT'; tex.location=(-500,160)
        links.new(tex.outputs['Color'],bsdf.inputs['Base Color'])
        nt=nodes.new('ShaderNodeTexImage'); nt.image=normal; nt.location=(-500,-140)
        nm=nodes.new('ShaderNodeNormalMap'); nm.inputs['Strength'].default_value=.35 if kind in ('metal','glass','snow') else .65; nm.location=(-230,-100)
        links.new(nt.outputs['Color'],nm.inputs['Color']);links.new(nm.outputs['Normal'],bsdf.inputs['Normal'])
        mat['uv_tile_meters']=tile; mats[name]=mat
    return mats

class Builder:
    """Named groups batch to meshes. Every coordinate is in the region's local meters."""
    def __init__(self,collection,materials,offset=(0,0,0)):
        self.collection=collection;self.materials=materials;self.offset=Vector(offset);self.groups={};self.buildings=[];self.interactions=[];self.room_lights=[]
    def poly(self,name,verts,faces,mat):
        if mat not in self.materials: raise ValueError('Unknown material '+str(mat))
        group=self.groups.setdefault(name,{'v':[],'f':[],'m':[]})
        start=len(group['v']);group['v'].extend(tuple(p) for p in verts)
        group['f'].extend(tuple(start+i for i in f) for f in faces)
        group['m'].extend([mat]*len(faces))
    def box(self,name,loc,size,mat,rot=0):
        x,y,z=loc; sx,sy,sz=(t/2 for t in size); c,s=math.cos(rot),math.sin(rot)
        raw=[(-sx,-sy,-sz),(sx,-sy,-sz),(sx,sy,-sz),(-sx,sy,-sz),(-sx,-sy,sz),(sx,-sy,sz),(sx,sy,sz),(-sx,sy,sz)]
        vs=[(x+a*c-b*s,y+a*s+b*c,z+d) for a,b,d in raw]
        self.poly(name,vs,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],mat)
    def beam(self,name,start,end,radius,mat,sides=4):
        a,b=Vector(start),Vector(end);axis=b-a
        if axis.length<1e-7:return
        axis.normalize();ref=Vector((0,0,1)) if abs(axis.z)<.95 else Vector((1,0,0))
        u=axis.cross(ref).normalized()*radius;v=axis.cross(u).normalized()*radius
        vs=[tuple(p+u*math.cos(i*math.tau/sides)+v*math.sin(i*math.tau/sides)) for p in (a,b) for i in range(sides)]
        fs=[tuple(reversed(range(sides))),tuple(range(sides,2*sides))]
        fs +=[(i,(i+1)%sides,(i+1)%sides+sides,i+sides) for i in range(sides)]
        self.poly(name,vs,fs,mat)
    def cyl(self,name,loc,radius,depth,mat,vertices=16,radius_top=None):
        if radius_top is None: radius_top=radius
        x,y,z=loc;vs=[]
        for dz,r in ((-depth/2,radius),(depth/2,radius_top)):
            vs.extend((x+r*math.cos(i*math.tau/vertices),y+r*math.sin(i*math.tau/vertices),z+dz) for i in range(vertices))
        fs=[tuple(reversed(range(vertices))),tuple(range(vertices,2*vertices))]+[(i,(i+1)%vertices,(i+1)%vertices+vertices,i+vertices) for i in range(vertices)]
        self.poly(name,vs,fs,mat)
    def arch(self,name,center,width,height,depth,mat,rotation=0,segments=12,thickness=.3):
        # Extruded wedge ring + separate uprights leave an actual empty opening.
        x,y,z=center;r=width/2; spring=height-r;c,s=math.cos(rotation),math.sin(rotation)
        def tx(a,b,d):return (x+a*c-b*s,y+a*s+b*c,z+d)
        for side in (-1,1):
            q=side*(r+thickness/2)
            self.box(name,tx(q,0,spring/2),(thickness,depth,spring),mat,rotation)
        for i in range(segments):
            a=i*math.pi/segments;b=(i+1)*math.pi/segments
            profile=[(r*math.cos(a),spring+r*math.sin(a)),((r+thickness)*math.cos(a),spring+(r+thickness)*math.sin(a)),((r+thickness)*math.cos(b),spring+(r+thickness)*math.sin(b)),(r*math.cos(b),spring+r*math.sin(b))]
            vs=[tx(px,dy,pz) for dy in (-depth/2,depth/2) for px,pz in profile]
            self.poly(name,vs,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],mat)
    def roof(self,name,loc,width,depth,height,mat):
        x,y,z=loc;w=width/2;d=depth/2
        self.poly(name,[(x-w,y-d,z),(x+w,y-d,z),(x+w,y+d,z),(x-w,y+d,z),(x,y-d,z+height),(x,y+d,z+height)],[(0,1,4),(3,5,2),(0,4,5,3),(1,2,5,4),(0,3,2,1)],mat)
    def pine(self,name,x,y,z,height):
        rng=random.Random(round(x*83+y*170+height*92))
        self.cyl(name+'_Trunks',(x,y,z+height*.45),height*.025,height*.9,'dark_wood',8,radius_top=height*.009)
        for layer in range(7):
            zz=z+height*(.23+layer*.103); r=height*(.21-layer*.025)
            count=11;verts=[(x,y,zz+height*.29)]
            for j in range(count):
                a=j*math.tau/count;rr=r*rng.uniform(.78,1.15)
                verts.append((x+rr*math.cos(a),y+rr*math.sin(a),zz+rng.uniform(-.12,.12)))
            self.poly(name+'_Needles',verts,[(0,j+1,(j+1)%count+1) for j in range(count)]+[tuple(range(1,count+1))],'foliage_dark' if layer%2 else 'foliage')
    def tree(self,name,x,y,z,height):
        self.cyl(name+'_Trunks',(x,y,z+height*.3),height*.035,height*.6,'wood',9,radius_top=height*.019)
        rng=random.Random(round(x*193+y*81))
        # Branched irregular clusters break up the silhouette instead of five large balls.
        for k in range(17):
            a=k*2.39996;rad=height*(.09+.2*math.sqrt(k/17))
            center=Vector((x+math.cos(a)*rad,y+math.sin(a)*rad,z+height*(.62+.22*rng.random())))
            self.beam(name+'_Trunks',(x,y,z+height*.38),tuple(center),height*.009,'wood',5)
            vs=[];seg=9;rings=5;cluster=height*rng.uniform(.105,.15)
            vs.append(tuple(center+Vector((0,0,cluster))))
            for row in range(1,rings):
                ang=row*math.pi/rings
                for col in range(seg):
                    phi=col*math.tau/seg;rr=cluster*rng.uniform(.74,1.18)
                    vs.append(tuple(center+Vector((rr*math.sin(ang)*math.cos(phi),rr*math.sin(ang)*math.sin(phi),rr*math.cos(ang)))))
            vs.append(tuple(center-Vector((0,0,cluster*.83))));bottom=len(vs)-1
            fs=[(0,1+j,1+(j+1)%seg) for j in range(seg)]
            fs +=[(1+i*seg+j,1+i*seg+(j+1)%seg,1+(i+1)*seg+(j+1)%seg,1+(i+1)*seg+j) for i in range(rings-2) for j in range(seg)]
            fs +=[(bottom,1+(rings-2)*seg+(j+1)%seg,1+(rings-2)*seg+j) for j in range(seg)]
            self.poly(name+'_Canopy',vs,fs,'foliage' if k%3 else 'foliage_dark')
            for leaf in range(9):
                theta=rng.random()*math.tau;phi=rng.random()*math.pi
                p=center+Vector((math.cos(theta)*math.sin(phi),math.sin(theta)*math.sin(phi),math.cos(phi)))*cluster
                u=Vector((math.cos(theta),math.sin(theta),.3))*height*.034
                v=Vector((-math.sin(theta)*.45,math.cos(theta)*.45,.6))*height*.034
                self.poly(name+'_Leaves',[tuple(p-u),tuple(p-v),tuple(p+u),tuple(p+v)],[(0,1,2),(0,2,3)],'foliage')
    def finish(self):
        output=[]
        for name,g in self.groups.items():
            me=bpy.data.meshes.new(name+'_Mesh');me.from_pydata(g['v'],[],g['f']);me.update()
            keys=list(dict.fromkeys(g['m']));mi={m:i for i,m in enumerate(keys)}
            for m in keys: me.materials.append(self.materials[m])
            for p,m in zip(me.polygons,g['m']):p.material_index=mi[m]
            bm=bmesh.new();bm.from_mesh(me)
            # Recalculate closed solids only. Open walkable surfaces have an
            # authored upward winding, which volume-based recalculation can flip.
            pending=set(bm.faces);closed=[]
            while pending:
                seed=pending.pop();component=[seed];stack=[seed];is_closed=True
                while stack:
                    face=stack.pop()
                    for edge in face.edges:
                        if len(edge.link_faces)!=2:is_closed=False
                        for neighbor in edge.link_faces:
                            if neighbor in pending:
                                pending.remove(neighbor);component.append(neighbor);stack.append(neighbor)
                if is_closed:closed.extend(component)
            if closed:bmesh.ops.recalc_face_normals(bm,faces=closed)
            bm.to_mesh(me);bm.free();me.update()
            uv=me.uv_layers.new(name='UVMap');coords=np.zeros((len(me.loops),2),dtype=np.float32)
            for p in me.polygons:
                n=p.normal; axis=max(range(3),key=lambda i:abs(n[i]));dims=((1,2),(0,2),(0,1))[axis]
                tile=PALETTE[keys[p.material_index]][4]
                for li in p.loop_indices:
                    co=me.vertices[me.loops[li].vertex_index].co;coords[li]=(co[dims[0]]/tile,co[dims[1]]/tile)
            uv.data.foreach_set('uv',coords.ravel())
            ob=bpy.data.objects.new(name,me);self.collection.objects.link(ob);ob.location=self.offset
            ob['region']=self.collection.name;ob['role']='visual';output.append(ob)
        return output

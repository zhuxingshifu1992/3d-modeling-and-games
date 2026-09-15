import bpy,math
from pathlib import Path
from mathutils import Vector
BASE=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(BASE/'source/rider/rider_realistic.blend'))
s=bpy.context.scene;s.render.engine='CYCLES';s.cycles.device='CPU';s.cycles.samples=24;s.cycles.use_denoising=True
s.render.resolution_x=900;s.render.resolution_y=900;s.render.resolution_percentage=100
if s.world is None:s.world=bpy.data.worlds.new('StudioWorld')
s.world.color=(.3,.3,.3)
s.view_settings.view_transform='AgX'
bpy.ops.object.camera_add(location=(2.6,-3.4,1.85));cam=bpy.context.object;cam.rotation_euler=(Vector((0,0,.84))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.lens=65;s.camera=cam
for loc,energy,size in [((3,-4,5),500,4),((-3,1,3),300,3),((0,3,4),450,3)]:
 bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.data.energy=energy;o.data.shape='DISK';o.data.size=size;o.rotation_euler=(Vector((0,0,.8))-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.mesh.primitive_plane_add(size=200);floor=bpy.context.object;floor.location.z=-.004
m=bpy.data.materials.new('StudioGround');m.diffuse_color=(.13,.17,.18,1);floor.data.materials.append(m)
s.render.filepath=str(BASE/'source/rider/rider_studio.png');bpy.ops.render.render(write_still=True)
print('RIDER_RENDER_DONE')

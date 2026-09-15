"""Render honest Blender views of the delivered scene, with no painted-in geometry."""
import bpy,sys,math
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'))
from geometry import Builder
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'欧洲四国旅行场景.blend'))
scene=bpy.context.scene
regions={'france':'FR_Paris','italy':'IT_Rome','switzerland':'CH_Alps','germany':'DE_Bavaria'}
offsets={'france':(-80,72,0),'italy':(80,72,0),'switzerland':(-80,-72,0),'germany':(80,-72,0)}
scene.cycles.samples=36;scene.render.resolution_x=1600;scene.render.resolution_y=1200
selection=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
keys=selection or ['overview']+list(regions)+[k+'_detail' for k in regions]+['switzerland_village_detail']
stage=bpy.data.collections.new('Preview_Only_Backdrop');scene.collection.children.link(stage)
B=Builder(stage,{m.name:m for m in bpy.data.materials});B.box('Preview_Ground',(0,0,-.23),(4000,4000,.4),'grass');B.finish()
stage.hide_render=True
detail={
 'france':((46,-75,19),(0,8,32),30),
 'italy':((55,-61,8),(0,8,11),35),
 'switzerland':((44,-85,20),(0,24,33),33),
 'germany':((64,-91,29),(0,10,33),40)
}
bg=scene.world.node_tree.nodes.get('Background');sky=scene.world.node_tree.nodes.new('ShaderNodeTexSky');sky.sky_type='MULTIPLE_SCATTERING';sky.sun_elevation=math.radians(32);sky.sun_rotation=math.radians(-30);sky.sun_disc=False
for key in keys:
    is_detail=key.endswith('_detail');region='switzerland' if key=='switzerland_village_detail' else key.replace('_detail','')
    for k,name in regions.items():bpy.data.collections[name].hide_render=(key!='overview' and k!=region)
    stage.hide_render=not is_detail
    if is_detail:
        scene.world.node_tree.links.new(sky.outputs['Color'],bg.inputs['Color']);bg.inputs['Strength'].default_value=.35
        loc,target,lens=((44,-62,15),(3,-24,5),43) if key=='switzerland_village_detail' else detail[region];off=Vector(offsets[region])
        data=bpy.data.cameras.new(key);cam=bpy.data.objects.new(key,data);scene.collection.objects.link(cam)
        cam.location=Vector(loc)+off;cam.rotation_euler=(Vector(target)+off-cam.location).to_track_quat('-Z','Y').to_euler();data.lens=lens;data.clip_end=5000
        scene.camera=cam;scene.render.resolution_x=1920;scene.render.resolution_y=1080
    else:
        for link in list(bg.inputs['Color'].links):scene.world.node_tree.links.remove(link)
        bg.inputs['Color'].default_value=(.60,.72,.88,1);bg.inputs['Strength'].default_value=.45
        scene.camera=bpy.data.objects['Camera_Europe_Overview' if key=='overview' else 'Camera_'+regions[key]]
        scene.render.resolution_x=1920 if key=='overview' else 1600;scene.render.resolution_y=1440 if key=='overview' else 1200
    scene.render.filepath=str(ROOT/'previews'/(key+'.png'));print('PREVIEW '+key,flush=True)
    bpy.ops.render.render(write_still=True)
print('PREVIEWS COMPLETE',flush=True)

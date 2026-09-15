"""Independent Blender re-import and rendered smoke test of exported GLBs."""
import json
import pathlib
import bpy
from mathutils import Vector

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "assets"
bpy.ops.wm.read_factory_settings(use_empty=True)
counts = {}
for filename in ("city.glb", "gondola.glb"):
    existing = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(OUT / filename))
    imported = set(bpy.data.objects) - existing
    meshes = [ob for ob in imported if ob.type == "MESH"]
    assert len(meshes) == 1
    obj = meshes[0]
    obj.data.calc_loop_triangles()
    counts[filename] = {
        "meshes": len(meshes),
        "triangles": len(obj.data.loop_triangles),
        "materials": len(obj.data.materials),
        "has_vertex_colors": bool(obj.data.color_attributes),
        "identity_transform": all(abs(obj.matrix_world[i][j] - float(i == j)) < 1e-5 for i in range(4) for j in range(4)),
    }
    assert counts[filename]["has_vertex_colors"]
    assert counts[filename]["identity_transform"]
    if filename == "gondola.glb":
        obj.location = (0, -18, 0.04)

# Sea is only in this QA image; game water is built by the game renderer.
bpy.ops.mesh.primitive_plane_add(size=300, location=(0, 0, -0.03))
sea = bpy.context.object
material = bpy.data.materials.new("QA sea")
material.use_nodes = True
nodes = material.node_tree.nodes
nodes.clear()
emission = nodes.new("ShaderNodeEmission")
emission.inputs["Color"].default_value = (0.045, 0.29, 0.29, 1)
out = nodes.new("ShaderNodeOutputMaterial")
material.node_tree.links.new(emission.outputs[0], out.inputs["Surface"])
sea.data.materials.append(material)
camera_data = bpy.data.cameras.new("Asset QA camera")
camera = bpy.data.objects.new("Asset QA camera", camera_data)
bpy.context.scene.collection.objects.link(camera)
camera.location = (67, -91, 77)
camera.rotation_euler = (Vector((0, 0, 5)) - camera.location).to_track_quat("-Z", "Y").to_euler()
camera_data.type = "ORTHO"
camera_data.ortho_scale = 92
scene = bpy.context.scene
scene.camera = camera
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 4
scene.cycles.use_denoising = True
scene.render.resolution_x = 1000
scene.render.resolution_y = 800
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = "Standard"
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(OUT / "asset_preview.png")
scene.world = bpy.data.worlds.new("QA world")
scene.world.color = (0.3, 0.3, 0.3)
bpy.ops.render.render(write_still=True)
(OUT / "asset_import_validation.json").write_text(json.dumps({"status": "PASS", "independent_blender_reimport": counts}, indent=2), encoding="utf-8")
print(json.dumps(counts, indent=2), flush=True)

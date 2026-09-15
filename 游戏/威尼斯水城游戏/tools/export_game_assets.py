"""Export the original Venice scene as compact, self-contained game GLBs.

Run with Blender in background mode. The source .blend is only read; this
script writes solely to the adjacent assets folder. No Blender runtime is
needed by the delivered game.
"""
from __future__ import annotations

import array
import collections
import json
import math
import pathlib
import struct
import time

import bpy
import bmesh
from mathutils import Matrix, Vector


ROOT = pathlib.Path(__file__).resolve().parents[1]
CATEGORIZED_SOURCE = ROOT.parent.parent / "建模" / "威尼斯水城" / "威尼斯水城.blend"
LEGACY_SOURCE = ROOT.parent / "威尼斯水城" / "威尼斯水城.blend"
SOURCE = CATEGORIZED_SOURCE if CATEGORIZED_SOURCE.is_file() else LEGACY_SOURCE
OUT = ROOT / "assets"
SUN = Vector((-0.40, -0.65, 0.75)).normalized()
TRIANGLE_BUDGET = 240_000


def descendants(root):
    found = set()
    pending = list(root.children)
    while pending:
        ob = pending.pop()
        found.add(ob)
        pending.extend(ob.children)
    return found


def base_color(material):
    if material is None:
        return (0.65, 0.62, 0.53, 1.0)
    # Procedural source materials deliberately expose their authored palette
    # through diffuse_color, also used by the source's material preview.
    return tuple(material.diffuse_color)


def source_mesh(ob, depsgraph):
    """Get evaluated mesh, with roof tiles reduced from 4 to 2 cross sections."""
    if "individually shaped barrel tiles" in ob.name:
        src = ob.data
        verts, faces = [], []
        # Each independent roof tile is exactly two rows of five vertices.
        # Keep the two rims and center crest, preserving the barrel profile.
        for offset in range(0, len(src.vertices), 10):
            chosen = (0, 2, 4, 5, 7, 9)
            first = len(verts)
            verts.extend(tuple(src.vertices[offset + i].co) for i in chosen)
            for q in range(2):
                face = (first + q, first + q + 1, first + q + 4, first + q + 3)
                # Keep the winding of the original tile's first quad.
                old = src.polygons[(offset // 10) * 4]
                if old.vertices[0] != offset:
                    face = tuple(reversed(face))
                faces.append(face)
        result = bpy.data.meshes.new("game_tile_simplification")
        result.from_pydata(verts, [], faces)
        for mat in src.materials:
            result.materials.append(mat)
        result.update()
        return result
    evaluated = ob.evaluated_get(depsgraph)
    return bpy.data.meshes.new_from_object(evaluated, depsgraph=depsgraph)


def gather(objects, transform=Matrix.Identity(4)):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    verts, faces, colors = [], [], []
    by_kind = collections.Counter()
    for index, ob in enumerate(objects):
        geometry = source_mesh(ob, depsgraph)
        if not geometry.vertices or not geometry.polygons:
            bpy.data.meshes.remove(geometry)
            continue
        # Repair inconsistent winding on disconnected, closed source details.
        # Open roofs retain their authored orientation below when shading.
        bm = bmesh.new()
        bm.from_mesh(geometry)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(geometry)
        bm.free()
        geometry.calc_loop_triangles()
        world = transform @ ob.matrix_world
        start = len(verts)
        verts.extend(tuple(world @ vertex.co) for vertex in geometry.vertices)
        palette = [base_color(mat) for mat in geometry.materials]
        if not palette:
            palette = [base_color(None)]
        for tri in geometry.loop_triangles:
            faces.append(tuple(start + i for i in tri.vertices))
            color = palette[min(tri.material_index, len(palette) - 1)]
            colors.append(color)
        by_kind[ob.type] += len(geometry.loop_triangles)
        bpy.data.meshes.remove(geometry)
        if index and index % 1000 == 0:
            print(f"Gathered {index}/{len(objects)} objects, {len(faces)} triangles", flush=True)
    return verts, faces, colors, by_kind


def simplify_to_budget(verts, faces, colors, budget):
    if len(faces) <= budget:
        return verts, faces, colors, 1.0
    # The city is already composed of low-poly solids. A bounded collapse pass
    # only runs if source complexity exceeds the portable-renderer budget.
    mesh = bpy.data.meshes.new("game_budget_mesh")
    mesh.from_pydata(verts, [], faces)
    unique = list(dict.fromkeys(colors))
    indices = {c: i for i, c in enumerate(unique)}
    for color in unique:
        mat = bpy.data.materials.new("game_budget_palette")
        mat.diffuse_color = color
        mesh.materials.append(mat)
    for poly, color in zip(mesh.polygons, colors):
        poly.material_index = indices[color]
    mesh.update()
    ob = bpy.data.objects.new("game_budget_working_object", mesh)
    bpy.context.scene.collection.objects.link(ob)
    modifier = ob.modifiers.new("Portable GPU triangle budget", "DECIMATE")
    modifier.ratio = min(1.0, budget * 0.985 / len(faces))
    modifier.use_collapse_triangulate = True
    bpy.context.view_layer.update()
    reduced = bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    reduced.calc_loop_triangles()
    output_verts = [tuple(v.co) for v in reduced.vertices]
    output_faces = [tuple(t.vertices) for t in reduced.loop_triangles]
    output_colors = [unique[t.material_index] for t in reduced.loop_triangles]
    ratio = len(output_faces) / len(faces)
    bpy.data.objects.remove(ob, do_unlink=True)
    bpy.data.meshes.remove(mesh)
    bpy.data.meshes.remove(reduced)
    return output_verts, output_faces, output_colors, ratio


def write_glb(path, name, verts, faces, palette, boat=False):
    """One primitive, one material; weld equal position/normal/color corners."""
    positions, normals, rgba, indices = array.array("f"), array.array("f"), bytearray(), array.array("I")
    welded = {}
    low, high = [math.inf] * 3, [-math.inf] * 3
    degenerate = 0
    for face, color in zip(faces, palette):
        points = [Vector(verts[i]) for i in face]
        normal = (points[1] - points[0]).cross(points[2] - points[0])
        if normal.length_squared < 1e-15:
            degenerate += 1
            continue
        normal.normalize()
        # Soft, immutable daytime lighting avoids per-pixel lights and shadows.
        # A small upward bias keeps the backs of thin authored open roof tiles
        # pleasantly lit while double-sided rendering guarantees visibility.
        shade_normal = normal.copy()
        if shade_normal.z < -0.20 and min(p.z for p in points) > 4:
            shade_normal = -shade_normal
        shade = 0.68 + 0.27 * max(0.0, shade_normal.dot(SUN)) + 0.05 * max(0.0, shade_normal.z)
        c = tuple(max(0, min(255, round(component * shade * 255))) for component in color[:3]) + (255,)
        # OpenGL/glTF and Godot are Y-up: Blender (x,y,z) -> (x,z,-y).
        n = (round(normal.x, 5), round(normal.z, 5), round(-normal.y, 5))
        for p in points:
            point = (round(p.x, 5), round(p.z, 5), round(-p.y, 5))
            key = point + n + c
            vertex_index = welded.get(key)
            if vertex_index is None:
                vertex_index = len(welded)
                welded[key] = vertex_index
                positions.extend(point)
                normals.extend(n)
                rgba.extend(c)
                for axis in range(3):
                    low[axis] = min(low[axis], point[axis])
                    high[axis] = max(high[axis], point[axis])
            indices.append(vertex_index)
    chunks = [positions.tobytes(), normals.tobytes(), bytes(rgba), indices.tobytes()]
    buffer_views, blob = [], bytearray()
    for i, chunk in enumerate(chunks):
        while len(blob) % 4:
            blob.append(0)
        buffer_views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(chunk), "target": 34963 if i == 3 else 34962})
        blob.extend(chunk)
    count = len(welded)
    doc = {
        "asset": {"version": "2.0", "generator": "Venice portable game exporter"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": name, "mesh": 0}],
        "meshes": [{"name": name, "primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "COLOR_0": 2}, "indices": 3, "material": 0, "mode": 4}]}],
        "materials": [{"name": "Baked Venetian palette", "doubleSided": True, "alphaMode": "OPAQUE", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0, "roughnessFactor": 1}, "extensions": {"KHR_materials_unlit": {}}}],
        "extensionsUsed": ["KHR_materials_unlit"],
        "extensionsRequired": ["KHR_materials_unlit"],
        "buffers": [{"byteLength": len(blob)}],
        "bufferViews": buffer_views,
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": count, "type": "VEC3", "min": low, "max": high},
            {"bufferView": 1, "componentType": 5126, "count": count, "type": "VEC3"},
            {"bufferView": 2, "componentType": 5121, "normalized": True, "count": count, "type": "VEC4"},
            {"bufferView": 3, "componentType": 5125, "count": len(indices), "type": "SCALAR"},
        ],
    }
    json_bytes = json.dumps(doc, separators=(",", ":"), ensure_ascii=True).encode("utf-8")
    json_bytes += b" " * (-len(json_bytes) % 4)
    blob += b"\0" * (-len(blob) % 4)
    total = 12 + 8 + len(json_bytes) + 8 + len(blob)
    with path.open("wb") as stream:
        stream.write(struct.pack("<III", 0x46546C67, 2, total))
        stream.write(struct.pack("<II", len(json_bytes), 0x4E4F534A))
        stream.write(json_bytes)
        stream.write(struct.pack("<II", len(blob), 0x004E4942))
        stream.write(blob)
    return {"file": path.name, "bytes": path.stat().st_size, "triangles": len(indices) // 3, "render_vertices": count, "meshes": 1, "surfaces": 1, "materials": 1, "bounds_godot": {"min": low, "max": high}, "degenerate_triangles_removed": degenerate}


def validate_glb(path):
    payload = path.read_bytes()
    magic, version, length = struct.unpack_from("<III", payload)
    assert magic == 0x46546C67 and version == 2 and length == len(payload)
    json_size, json_type = struct.unpack_from("<II", payload, 12)
    assert json_type == 0x4E4F534A
    doc = json.loads(payload[20:20 + json_size])
    assert len(doc["meshes"]) == len(doc["materials"]) == 1
    assert len(doc["meshes"][0]["primitives"]) == 1
    assert "animations" not in doc and "images" not in doc
    assert "matrix" not in doc["nodes"][0] and "translation" not in doc["nodes"][0]
    assert doc["materials"][0]["doubleSided"]
    assert doc["materials"][0]["alphaMode"] == "OPAQUE"
    binary_start = 20 + json_size + 8
    for view in doc["bufferViews"]:
        assert binary_start + view["byteOffset"] + view["byteLength"] <= len(payload)
    index_view = doc["bufferViews"][3]
    index_data = array.array("I")
    start = binary_start + index_view["byteOffset"]
    index_data.frombytes(payload[start:start + index_view["byteLength"]])
    assert max(index_data) < doc["accessors"][0]["count"]
    assert len(index_data) % 3 == 0
    return "PASS: binary chunks, accessors, indices, one surface, no animations/textures, opaque double-sided"


def main():
    started = time.perf_counter()
    OUT.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    bpy.context.scene.frame_set(1)
    roots = [o for o in bpy.context.scene.objects if o.type == "EMPTY" and o.name.startswith("Gondola")]
    assert len(roots) == 6, [o.name for o in roots]
    moving = set(roots)
    for root in roots:
        moving.update(descendants(root))
    hero = bpy.data.objects.get("Gondola • foreground")
    assert hero is not None
    hero_parts = sorted([o for o in descendants(hero) if o.type in {"MESH", "CURVE"}], key=lambda o: o.name)
    source_count = sum(o.type == "MESH" for o in bpy.context.scene.objects)
    for ob in bpy.context.scene.objects:
        # Tiny bevels were authored for offline Cycles closeups.
        for modifier in ob.modifiers:
            if modifier.type == "BEVEL":
                modifier.show_viewport = False
                modifier.show_render = False
        if ob.type == "CURVE":
            ob.data.bevel_resolution = 0
            ob.data.resolution_u = 1
    bpy.context.view_layer.update()
    static = sorted([o for o in bpy.context.scene.objects if o.type in {"MESH", "CURVE"} and o not in moving and "lagoon water" not in o.name.lower()], key=lambda o: o.name)
    print(f"Source meshes {source_count}; static objects {len(static)}; hero components {len(hero_parts)}", flush=True)
    vertices, triangles, colors, kinds = gather(static)
    original_triangles = len(triangles)
    print(f"Static preliminary triangles {original_triangles}", flush=True)
    vertices, triangles, colors, reduction = simplify_to_budget(vertices, triangles, colors, TRIANGLE_BUDGET)
    city = write_glb(OUT / "city.glb", "VeniceCity", vertices, triangles, colors)
    boat_verts, boat_tris, boat_colors, _ = gather(hero_parts, hero.matrix_world.inverted())
    # Hull reference x/y stays at its authored center; remove tiny oar/boat
    # penetration so the exported baseline is precisely Godot y=0.
    baseline = min(v[2] for v in boat_verts)
    boat_verts = [(v[0], v[1], v[2] - baseline) for v in boat_verts]
    boat = write_glb(OUT / "gondola.glb", "PlayerGondola", boat_verts, boat_tris, boat_colors, boat=True)
    city["validation"] = validate_glb(OUT / "city.glb")
    boat["validation"] = validate_glb(OUT / "gondola.glb")
    report = {
        "status": "PASS", "source": str(SOURCE), "source_saved_or_modified": False,
        "blender": bpy.app.version_string, "source_mesh_objects": source_count,
        "excluded_animated_gondola_groups": len(roots), "static_source_objects": len(static),
        "source_triangles_after_detail_simplification": original_triangles,
        "budget_collapse_ratio": reduction, "city_triangle_budget": TRIANGLE_BUDGET,
        "axis_conversion": "Blender (x,y,z) -> Godot/glTF (x,z,-y); transforms baked; nodes identity",
        "gondola_origin": "Authored hull center in x/y; lowest geometry y=0 in Godot",
        "gondola_long_axis": "+X; game can rotate by yaw + PI/2 for default -Z travel",
        "materials": "One opaque double-sided KHR_materials_unlit vertex-color material per asset; gentle directional and ambient lighting baked in linear colors",
        "optimization": ["All static meshes merged into one draw surface", "Roof barrel tile cross sections halved", "Decorative bevel modifiers omitted", "Curve bevel resolution reduced to four-sided profiles", "Degenerate triangles removed", "Shared position/normal/color vertices welded"],
        "contains_water": False, "contains_physics_collision": False,
        "external_dependencies": [], "assets": {"city": city, "gondola": boat},
        "elapsed_seconds": round(time.perf_counter() - started, 2),
    }
    assert city["triangles"] < 250_000, city
    (OUT / "asset_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=True, indent=2), flush=True)


if __name__ == "__main__":
    main()

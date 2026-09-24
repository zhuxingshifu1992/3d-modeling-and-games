"""Auditable conversion of the author's legacy Unicorn OBJ materials.

Run ``python tools/unicorn_materials.py`` once to prepare derived PNG textures.
After OBJ import, call ``configure_materials(objects=imported_meshes)`` in Blender.
COL JPEG files are used directly and never rewritten. The converter is a
documented legacy-material approximation, not a claim of recovered native PBR.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import shlex

import numpy as np

PROJECT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = PROJECT / "source/external/unicorn_sketchfab/author_source"
VERSION = "1.0.0"
REFERENCES = [
    "https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html",
    "https://docs.blender.org/manual/en/3.6/addons/import_export/scene_gltf2.html",
]
LIMITATIONS = [
    "Author files contain legacy diffuse, bump and specular-intensity maps, not native metallic/roughness PBR.",
    "Original COL pixels, including baked lighting, wear, panel lines and markings, remain unchanged; baked shading can compound with runtime lighting.",
    "SPEC intensity supplies bounded roughness variation only; no measured glossiness, IOR or true metallic masks exist.",
    "Dark mixed atlases use a conservative artistic metal fraction with bright COL regions masked toward dielectric paint; this does not recover physical material identity.",
    "Tangent normals assume white-is-high bump and OpenGL +Y; height scale is artistic, since MTL bump amplitude has no reliable physical unit.",
    "Emission is a restrained artistic treatment for the eight RED COL atlases, masked by red chroma; the untextured red material remains non-emissive because its identity is unknown.",
    "MTL illum=4, Tf=1 and Ni=1 are legacy exporter defaults and do not establish transparent armor; the converted materials are opaque with transmission zero.",
]


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def parse_mtl(path):
    """Read this MTL's actual relationships, including options after filenames."""
    result = {}
    current = None
    roles = {"map_Kd": "color", "map_Ks": "specular", "bump": "bump", "map_bump": "bump"}
    for raw in Path(path).read_text(encoding="utf-8-sig").splitlines():
        tokens = shlex.split(raw, comments=True, posix=False)
        if not tokens:
            continue
        key, *values = tokens
        if key == "newmtl":
            current = {"name": " ".join(values), "maps": {}, "bump_multiplier": 1.0}
            result[current["name"]] = current
        elif current is None:
            continue
        elif key in roles:
            filenames = [value.strip('"') for value in values if re.search(r"\.(jpg|jpeg|png|tif|tiff)$", value, re.I)]
            if len(filenames) != 1:
                raise ValueError(f"Ambiguous texture record: {raw}")
            current["maps"][roles[key]] = filenames[0]
            if "-bm" in values:
                current["bump_multiplier"] = float(values[values.index("-bm") + 1])
        elif key in {"Kd", "Ka", "Ks", "Tf"}:
            current[key] = [float(v) for v in values]
        elif key in {"Ni", "Ns", "d", "Tr", "illum"}:
            current[key] = float(values[0])
    return result


def height_to_normal(height, slope_scale):
    """Return RGB tangent normal bytes from top-down scalar height pixels.

    +U is image-right; +V is image-up, so image-down dH/dy changes green
    with the opposite sign to red. Pixel-space finite differences avoid
    an undocumented dependence on the assumed physical size of a UV island.
    """
    dy, dx = np.gradient(np.asarray(height, dtype=np.float32))
    normal = np.stack((-dx * slope_scale, dy * slope_scale, np.ones_like(dx)), axis=-1)
    normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
    return np.rint(np.clip(normal * 0.5 + 0.5, 0, 1) * 255).astype(np.uint8)


def _smoothstep(low, high, value):
    value = np.clip((value - low) / (high - low), 0.0, 1.0)
    return value * value * (3.0 - 2.0 * value)


def _profile(semantic):
    if semantic.endswith("_WHITE"):
        return dict(kind="painted_white", metallic=0.0, roughness=0.48, emission_strength=0.0)
    if semantic.endswith("_RED"):
        return dict(kind="red_psychoframe_approximation", metallic=0.08, roughness=0.38, emission_strength=0.65)
    if semantic == "UC_UNTEXTURED_RUBY":
        return dict(kind="unknown_untextured_red", metallic=0.0, roughness=0.44, emission_strength=0.0)
    return dict(kind="mixed_dark_mechanism", metallic=0.35, roughness=0.52, emission_strength=0.0)


def _paths(source_dir=None, derived_dir=None):
    source = Path(source_dir or DEFAULT_SOURCE).resolve()
    derived = Path(derived_dir or source.parent / "derived").resolve()
    if derived == source or source in derived.parents:
        raise ValueError("Derived outputs must not be written inside immutable author_source")
    return source, derived


def _file_record(path, relative_to):
    from PIL import Image
    with Image.open(path) as image:
        size = list(image.size)
        mode = image.mode
    return {"path": Path(path).relative_to(relative_to).as_posix(), "sha256": sha256(path), "size": size, "mode": mode, "bytes": Path(path).stat().st_size}


def _cached_output_valid(record, root):
    path = root / record["path"]
    return path.is_file() and sha256(path) == record["sha256"]


def prepare_materials(source_dir=None, derived_dir=None, force=False):
    """Prepare one normal/MR map per atlas, plus eight masked emission maps.

    Requires Pillow/numpy in ordinary Python. A content-validated cache avoids
    recompressing derived images. Returns and writes materials_manifest.json.
    """
    from PIL import Image, ImageFilter
    source, derived = _paths(source_dir, derived_dir)
    derived.mkdir(parents=True, exist_ok=True)
    textures_dir = derived / "textures"
    textures_dir.mkdir(exist_ok=True)
    mtl_path = source / "UNICORN_GUNDAM_OBJ.mtl"
    obj_path = source / "UNICORN_GUNDAM_OBJ.obj"
    source_records = {path.name: _file_record(path, source) for path in sorted(source.glob("*.jpg"))}
    source_fingerprint = {
        "converter_version": VERSION,
        "converter_sha256": sha256(Path(__file__)),
        "mtl_sha256": sha256(mtl_path),
        "obj_sha256": sha256(obj_path),
        "textures": {name: record["sha256"] for name, record in source_records.items()},
    }
    manifest_path = derived / "materials_manifest.json"
    if not force and manifest_path.is_file():
        cached = json.loads(manifest_path.read_text(encoding="utf-8"))
        if cached.get("source_fingerprint") == source_fingerprint:
            if all(_cached_output_valid(record, derived) for material in cached["materials"] for record in material["derived"].values()):
                return cached
    definitions = parse_mtl(mtl_path)
    used = Counter()
    current = None
    for line in obj_path.read_text(encoding="utf-8").splitlines():
        if line.startswith("usemtl "):
            current = line.split(maxsplit=1)[1]
        elif line.startswith("f ") and current:
            used[current] += 1
    unknown_materials = sorted(set(used) - set(definitions))
    referenced = {filename for definition in definitions.values() for filename in definition["maps"].values()}
    missing = sorted(referenced - set(source_records))
    unreferenced = sorted(set(source_records) - referenced)
    if missing or unknown_materials:
        raise ValueError(f"Invalid author material references: missing={missing}, unknown={unknown_materials}")
    manifest = {
        "schema": 1, "converter_version": VERSION, "source_fingerprint": source_fingerprint,
        "source_directory": source.as_posix(), "derived_directory": derived.as_posix(),
        "references": REFERENCES, "limitations": LIMITATIONS,
        "source_audit": {
            "missing_referenced_textures": missing,
            "unreferenced_source_textures": unreferenced,
            "obj_used_materials": dict(sorted(used.items())),
            "all_source_textures": source_records,
            "unused_mtl_materials": sorted(set(definitions) - set(used)),
        },
        "materials": [],
    }
    for original_name, definition in definitions.items():
        color_filename = definition["maps"].get("color")
        semantic = Path(color_filename).stem.removesuffix("_COL") if color_filename else "UC_UNTEXTURED_RUBY"
        parameters = _profile(semantic)
        parameters.update({"alpha": 1.0, "transmission": 0.0, "ior": 1.5, "specular_ior_level": 0.5})
        material = {
            "original_name": original_name, "semantic_name": semantic,
            "obj_face_count": used[original_name], "legacy_mtl": definition,
            "parameters": parameters, "inputs": {}, "derived": {}, "notes": [],
        }
        for role, name in definition["maps"].items():
            material["inputs"][role] = source_records[name]
        if not color_filename:
            material["base_color_factor"] = definition.get("Kd", [0.5, 0.5, 0.5]) + [1.0]
            material["notes"].append("No texture is referenced in MTL; use author Kd and do not invent a missing map or part identity.")
            manifest["materials"].append(material)
            continue
        color_image = Image.open(source / color_filename).convert("RGB")
        color = np.asarray(color_image, dtype=np.float32) / 255.0
        spec_filename = definition["maps"].get("specular")
        bump_filename = definition["maps"].get("bump")
        spec_aliases_bump = spec_filename is not None and spec_filename == bump_filename
        if spec_aliases_bump:
            material["notes"].append("Author map_Ks aliases BUMP. It is not a missing SPEC image; do not treat height as specular or metallic. Use constant base roughness.")
            roughness = np.full(color.shape[:2], parameters["roughness"], dtype=np.float32)
        elif spec_filename:
            spec_rgb = np.asarray(Image.open(source / spec_filename).convert("RGB"), dtype=np.float32) / 255.0
            spec_luma = spec_rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
            roughness = parameters["roughness"] + 0.14 * (0.5 - spec_luma)
        else:
            roughness = np.full(color.shape[:2], parameters["roughness"], dtype=np.float32)
        metallic = np.full(color.shape[:2], parameters["metallic"], dtype=np.float32)
        if parameters["kind"] == "mixed_dark_mechanism":
            color_luma = color @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
            metallic *= 1.0 - _smoothstep(0.24, 0.52, color_luma)
        mr = np.stack((np.ones_like(roughness), roughness, metallic), axis=-1)
        mr_path = textures_dir / f"{semantic}_MR.png"
        Image.fromarray(np.rint(np.clip(mr, 0, 1) * 255).astype(np.uint8)).save(mr_path, compress_level=6)
        material["derived"]["metallic_roughness"] = _file_record(mr_path, derived)
        material["derived"]["metallic_roughness"].update({
            "color_space": "Non-Color", "channels": {"R": "unused constant 1 (not baked AO)", "G": "roughness", "B": "metallic"},
            "roughness_formula": "base + 0.14 * (0.5 - SPEC luminance in raw image encoding)" if spec_filename and not spec_aliases_bump else "constant base",
            "roughness_range": [float(roughness.min()), float(roughness.max())],
            "metallic_formula": "0.35 * (1 - smoothstep(0.24, 0.52, COL encoded luminance))" if parameters["kind"] == "mixed_dark_mechanism" else "constant material prior; independent of SPEC",
            "metallic_range": [float(metallic.min()), float(metallic.max())],
        })
        if bump_filename:
            bump_image = Image.open(source / bump_filename).convert("L").filter(ImageFilter.GaussianBlur(0.6))
            height = np.asarray(bump_image, dtype=np.float32) / 255.0
            slope_scale = 2.0 * definition["bump_multiplier"] / 0.05
            normal_path = textures_dir / f"{semantic}_NORMAL.png"
            Image.fromarray(height_to_normal(height, slope_scale)).save(normal_path, compress_level=6)
            material["derived"]["normal"] = _file_record(normal_path, derived)
            material["derived"]["normal"].update({
                "color_space": "Non-Color", "space": "TANGENT", "convention": "OpenGL +Y", "height_white_is_high": True,
                "slope_scale": slope_scale, "legacy_bump_multiplier": definition["bump_multiplier"],
                "gaussian_blur_radius_px": 0.6, "derivative": "numpy central difference per pixel; one-sided boundary",
                "normal_formula": "normalize(-dH/dx*slope, +dH/dy*slope, 1), source image rows point down",
                "normal_map_strength": 1.0,
            })
        if parameters["emission_strength"]:
            chroma = color[:, :, 0] - np.maximum(color[:, :, 1], color[:, :, 2])
            mask = _smoothstep(0.08, 0.28, chroma) * _smoothstep(0.12, 0.35, color[:, :, 0])
            emission = color * mask[:, :, None]
            emission_path = textures_dir / f"{semantic}_EMISSION.png"
            Image.fromarray(np.rint(emission * 255).astype(np.uint8)).save(emission_path, compress_level=6)
            material["derived"]["emission"] = _file_record(emission_path, derived)
            material["derived"]["emission"].update({"color_space": "sRGB", "mask_formula": "smoothstep(.08,.28,R-max(G,B)) * smoothstep(.12,.35,R), encoded COL values", "strength": parameters["emission_strength"], "mask_mean": float(mask.mean())})
        manifest["materials"].append(material)
    manifest["statistics"] = {
        "materials": len(manifest["materials"]), "textured_materials": sum(bool(m["inputs"].get("color")) for m in manifest["materials"]),
        "source_texture_count": len(source_records), "source_color_maps": sum("_COL" in name for name in source_records),
        "source_bump_maps": sum("_BUMP" in name for name in source_records), "source_spec_maps": sum("_SPEC" in name for name in source_records),
        "derived_normal_maps": sum("normal" in m["derived"] for m in manifest["materials"]),
        "derived_metallic_roughness_maps": sum("metallic_roughness" in m["derived"] for m in manifest["materials"]),
        "derived_emission_maps": sum("emission" in m["derived"] for m in manifest["materials"]),
        "specular_aliases_bump": sum(m["inputs"].get("specular", {}).get("path") == m["inputs"].get("bump", {}).get("path") for m in manifest["materials"] if m["inputs"].get("bump")),
    }
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return manifest


def configure_materials(source_dir=None, derived_dir=None, objects=None):
    """Configure imported OBJ materials in Blender; return/write binding report.

    ``objects`` should be the imported Unicorn mesh list. Omitting it considers
    all current mesh objects, but only materials with original/semantic names
    in this source MTL are touched. Repeated calls replace the same node trees.
    Call prepare_materials() with ordinary Python before Blender conversion.
    """
    import bpy
    source, derived = _paths(source_dir, derived_dir)
    manifest_path = derived / "materials_manifest.json"
    if not manifest_path.is_file():
        raise FileNotFoundError("Run tools/unicorn_materials.py with the bundled Python runtime before Blender conversion")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    fingerprint = manifest["source_fingerprint"]
    if fingerprint["converter_version"] != VERSION or fingerprint["converter_sha256"] != sha256(Path(__file__)) or fingerprint["mtl_sha256"] != sha256(source / "UNICORN_GUNDAM_OBJ.mtl"):
        raise ValueError("Stale material manifest: run prepare_materials() again")
    for filename, expected in fingerprint["textures"].items():
        if sha256(source / filename) != expected:
            raise ValueError(f"Source texture changed after preparation: {filename}")
    for entry in manifest["materials"]:
        for record in entry["derived"].values():
            if not _cached_output_valid(record, derived):
                raise ValueError(f"Derived texture changed/missing: {record['path']}")
    targets = list(objects) if objects is not None else [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    available = {mat for obj in targets if obj.type == "MESH" for mat in obj.data.materials if mat}
    entries = {entry["original_name"]: entry for entry in manifest["materials"]}
    entries.update({entry["semantic_name"]: entry for entry in manifest["materials"]})
    bindings = []

    def texture(nodes, links, path, name, color_space, location):
        image = bpy.data.images.load(str(path), check_existing=True)
        image.colorspace_settings.name = color_space
        node = nodes.new("ShaderNodeTexImage")
        node.name = node.label = name
        node.image = image
        node.interpolation = "Linear"
        node.extension = "REPEAT"
        node.location = location
        return node

    for material in sorted(available, key=lambda item: item.name):
        lookup = material.get("unicorn_source_material") or material.name
        entry = entries.get(lookup) or entries.get(re.sub(r"\.\d{3}$", "", lookup))
        if entry is None:
            continue
        material.name = entry["semantic_name"]
        material["unicorn_source_material"] = entry["original_name"]
        material["unicorn_material_conversion"] = VERSION
        material["unicorn_material_manifest"] = str(manifest_path)
        material.use_nodes = True
        material.use_backface_culling = False
        if hasattr(material, "blend_method"):
            material.blend_method = "OPAQUE"
        nodes = material.node_tree.nodes
        links = material.node_tree.links
        nodes.clear()
        output = nodes.new("ShaderNodeOutputMaterial")
        output.location = (680, 60)
        shader = nodes.new("ShaderNodeBsdfPrincipled")
        shader.location = (360, 60)
        links.new(shader.outputs["BSDF"], output.inputs["Surface"])
        parameters = entry["parameters"]
        shader.inputs["Alpha"].default_value = 1.0
        shader.inputs["Metallic"].default_value = parameters["metallic"]
        shader.inputs["Roughness"].default_value = parameters["roughness"]
        shader.inputs["IOR"].default_value = parameters["ior"]
        for name in ("Transmission Weight", "Transmission"):
            if name in shader.inputs:
                shader.inputs[name].default_value = 0.0
        for name in ("Specular IOR Level", "Specular"):
            if name in shader.inputs:
                shader.inputs[name].default_value = 0.5
        color = entry["inputs"].get("color")
        if color:
            col = texture(nodes, links, source / color["path"], "Original COL (unchanged)", "sRGB", (-520, 350))
            links.new(col.outputs["Color"], shader.inputs["Base Color"])
        else:
            shader.inputs["Base Color"].default_value = entry["base_color_factor"]
        if "metallic_roughness" in entry["derived"]:
            mr = texture(nodes, links, derived / entry["derived"]["metallic_roughness"]["path"], "Derived MR (G roughness / B metallic)", "Non-Color", (-520, 80))
            split = nodes.new("ShaderNodeSeparateColor")
            split.mode = "RGB"
            split.location = (-100, 80)
            links.new(mr.outputs["Color"], split.inputs["Color"])
            links.new(split.outputs["Green"], shader.inputs["Roughness"])
            links.new(split.outputs["Blue"], shader.inputs["Metallic"])
        if "normal" in entry["derived"]:
            normal = texture(nodes, links, derived / entry["derived"]["normal"]["path"], "BUMP-derived tangent normal +Y", "Non-Color", (-520, -240))
            normal_map = nodes.new("ShaderNodeNormalMap")
            normal_map.space = "TANGENT"
            normal_map.inputs["Strength"].default_value = 1.0
            normal_map.location = (-100, -190)
            links.new(normal.outputs["Color"], normal_map.inputs["Color"])
            links.new(normal_map.outputs["Normal"], shader.inputs["Normal"])
        emission_name = "Emission Color" if "Emission Color" in shader.inputs else "Emission"
        shader.inputs[emission_name].default_value = (0, 0, 0, 1)
        if "emission" in entry["derived"]:
            emission = texture(nodes, links, derived / entry["derived"]["emission"]["path"], "Red chroma masked emission", "sRGB", (-520, -520))
            links.new(emission.outputs["Color"], shader.inputs[emission_name])
            shader.inputs["Emission Strength"].default_value = parameters["emission_strength"]
        elif "Emission Strength" in shader.inputs:
            shader.inputs["Emission Strength"].default_value = 0.0
        bindings.append({"source_material": entry["original_name"], "material": material.name, "node_count": len(nodes), "alpha": 1.0, "transmission": 0.0, "textures": [node.image.name for node in nodes if node.type == "TEX_IMAGE"]})
    binding_report = {"manifest": str(manifest_path), "statistics": manifest["statistics"], "configured_material_count": len(bindings), "bindings": bindings, "limitations": manifest["limitations"]}
    (derived / "materials_binding_report.json").write_text(json.dumps(binding_report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return binding_report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--derived-dir", type=Path)
    parser.add_argument("--force", action="store_true")
    arguments = parser.parse_args()
    result = prepare_materials(arguments.source_dir, arguments.derived_dir, arguments.force)
    print(json.dumps(result["statistics"], indent=2))

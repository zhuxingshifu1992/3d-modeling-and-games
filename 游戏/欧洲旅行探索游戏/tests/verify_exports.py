"""Re-import the four shipped visual GLBs and FBXs in clean Blender scenes.

Run only after build_world.py has finished::

  Blender/blender.exe --background --python-exit-code 1 --python tests/verify_exports.py

Each export is copied into a temporary directory before import. FBX extraction
therefore cannot create sidecar files beside the delivery files. This test does
not save or modify the source scene. Results are written to
docs/export_validation.json. Coordinates in this report use Blender Z-up meters.
"""

import argparse
import hashlib
import json
import math
import struct
import sys
import tempfile
import time
import traceback
from datetime import datetime, timezone
from pathlib import Path
from shutil import copyfile

import bpy
import numpy as np


ROOT = Path(__file__).resolve().parents[1]
REGIONS = ('FR_Paris', 'IT_Rome', 'CH_Alps', 'DE_Bavaria')
SOURCE = ROOT / 'source/欧洲漫游_可进入建筑.blend'
MANIFEST = ROOT / 'assets/world_manifest.json'
BUILD_REPORT = ROOT / 'docs/world_build_report.json'
BOUNDS_TOLERANCE = 0.01
TRIANGLE_RELATIVE_TOLERANCE = 0.001
TRIANGLE_ABSOLUTE_TOLERANCE = 8


def stamp(path):
    stat = path.stat()
    return {'bytes': stat.st_size, 'modified_ns': stat.st_mtime_ns}


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def glb_embedding(path):
    raw = path.read_bytes()
    magic, version, declared = struct.unpack_from('<4sII', raw)
    if magic != b'glTF' or version != 2 or declared != len(raw):
        raise ValueError('Invalid GLB header or byte length')
    cursor = 12
    document = None
    binary_bytes = 0
    while cursor < len(raw):
        length, kind = struct.unpack_from('<I4s', raw, cursor)
        cursor += 8
        payload = raw[cursor:cursor + length]
        if len(payload) != length:
            raise ValueError('Truncated GLB chunk')
        if kind == b'JSON':
            document = json.loads(payload)
        elif kind == b'BIN\0':
            binary_bytes += length
        cursor += length
    if document is None:
        raise ValueError('GLB JSON chunk missing')
    views = document.get('bufferViews', [])
    images = document.get('images', [])
    embedded = []
    missing = []
    for index, image in enumerate(images):
        view_index = image.get('bufferView')
        if not isinstance(view_index, int) or not 0 <= view_index < len(views):
            missing.append(index)
            continue
        view = views[view_index]
        size = int(view.get('byteLength', 0))
        begin = int(view.get('byteOffset', 0))
        if size <= 0 or begin + size > binary_bytes or view.get('buffer', 0) != 0:
            missing.append(index)
        else:
            embedded.append(size)
    return {'format': 'GLB 2', 'declared_images': len(images),
            'embedded_images': len(embedded), 'embedded_image_bytes': sum(embedded),
            'missing_embedded_image_indices': missing,
            'external_image_uris': [i['uri'] for i in images if 'uri' in i]}


def fbx_embedding(path):
    """Read binary FBX Video/Content payloads without trusting external paths."""
    raw = path.read_bytes()
    if not raw.startswith(b'Kaydara FBX Binary  \0\x1a\0'):
        raise ValueError('Expected a binary FBX export')
    version = struct.unpack_from('<I', raw, 23)[0]
    wide = version >= 7500
    fmt = '<QQQB' if wide else '<IIIB'
    header_size = struct.calcsize(fmt)
    content_bytes = []
    videos = 0

    def properties(cursor, count, limit):
        result = []
        fixed = {'Y': 2, 'C': 1, 'I': 4, 'F': 4, 'D': 8, 'L': 8}
        for _ in range(count):
            kind = chr(raw[cursor])
            cursor += 1
            if kind in fixed:
                cursor += fixed[kind]
                result.append(None)
            elif kind in ('S', 'R'):
                length = struct.unpack_from('<I', raw, cursor)[0]
                cursor += 4
                result.append(length if kind == 'R' else None)
                cursor += length
            elif kind in ('f', 'd', 'l', 'i', 'b', 'c'):
                _, _, size = struct.unpack_from('<III', raw, cursor)
                cursor += 12 + size
                result.append(None)
            else:
                raise ValueError('Unknown FBX property type ' + repr(kind))
            if cursor > limit:
                raise ValueError('FBX property overran its node')
        return cursor, result

    def node(cursor, ancestors=()):
        nonlocal videos
        end, count, property_bytes, name_bytes = struct.unpack_from(fmt, raw, cursor)
        if end == 0:
            return None
        if not cursor < end <= len(raw):
            raise ValueError('Invalid FBX node end offset')
        cursor += header_size
        name = raw[cursor:cursor + name_bytes].decode('utf-8', errors='replace')
        cursor += name_bytes
        property_begin = cursor
        cursor, values = properties(cursor, count, end)
        if cursor - property_begin != property_bytes:
            raise ValueError('FBX property byte count mismatch')
        if name == 'Video':
            videos += 1
        if name == 'Content' and 'Video' in ancestors:
            content_bytes.extend(v for v in values if isinstance(v, int) and v > 0)
        while cursor + header_size <= end:
            next_cursor = node(cursor, ancestors + (name,))
            if next_cursor is None:
                break
            cursor = next_cursor
        return end

    cursor = 27
    while cursor + header_size < len(raw):
        next_cursor = node(cursor)
        if next_cursor is None:
            break
        cursor = next_cursor
    return {'format': 'FBX binary', 'version': version, 'declared_images': videos,
            'embedded_images': len(content_bytes),
            'embedded_image_bytes': sum(content_bytes)}


def snapshot(objects, offset=(0, 0, 0), inspect_images=True):
    result = {'meshes': 0, 'vertices': 0, 'polygons': 0, 'triangles': 0,
              'empty_meshes': [], 'missing_uv_meshes': [], 'invalid_uv_meshes': [],
              'nonfinite_meshes': [], 'invalid_material_meshes': [],
              'uv_loops': 0, 'bounds_min': None, 'bounds_max': None}
    minimum = np.full(3, np.inf)
    maximum = np.full(3, -np.inf)
    materials = {}
    for ob in objects:
        if ob.type != 'MESH':
            continue
        mesh = ob.data
        result['meshes'] += 1
        if not len(mesh.vertices) or not len(mesh.polygons):
            result['empty_meshes'].append(ob.name)
            continue
        mesh.calc_loop_triangles()
        result['vertices'] += len(mesh.vertices)
        result['polygons'] += len(mesh.polygons)
        result['triangles'] += len(mesh.loop_triangles)
        coords = np.empty(len(mesh.vertices) * 3, dtype=np.float32)
        mesh.vertices.foreach_get('co', coords)
        coords = coords.reshape((-1, 3)).astype(np.float64)
        matrix = np.array(ob.matrix_world, dtype=np.float64)
        coords = coords @ matrix[:3, :3].T + matrix[:3, 3] - np.array(offset)
        if not np.isfinite(coords).all():
            result['nonfinite_meshes'].append(ob.name)
        else:
            minimum = np.minimum(minimum, coords.min(axis=0))
            maximum = np.maximum(maximum, coords.max(axis=0))
        if not mesh.uv_layers or len(mesh.uv_layers.active.data) != len(mesh.loops):
            result['missing_uv_meshes'].append(ob.name)
        else:
            uv = np.empty(len(mesh.loops) * 2, dtype=np.float32)
            mesh.uv_layers.active.data.foreach_get('uv', uv)
            result['uv_loops'] += len(mesh.loops)
            if not np.isfinite(uv).all():
                result['invalid_uv_meshes'].append(ob.name)
        indices = {polygon.material_index for polygon in mesh.polygons}
        valid = True
        for index in indices:
            if index >= len(mesh.materials) or mesh.materials[index] is None:
                valid = False
            else:
                material = mesh.materials[index]
                materials[material.name] = material
        if not valid:
            result['invalid_material_meshes'].append(ob.name)
    if np.isfinite(minimum).all():
        result['bounds_min'] = minimum.tolist()
        result['bounds_max'] = maximum.tolist()
    result['materials'] = len(materials)
    result['material_names'] = sorted(materials)
    if inspect_images:
        images = {}
        missing_textures = []
        for name, material in materials.items():
            nodes = material.node_tree.nodes if material.use_nodes and material.node_tree else []
            used_images = [node.image for node in nodes if node.type == 'TEX_IMAGE' and node.image]
            if not used_images:
                missing_textures.append(name)
            for image in used_images:
                images[image.name] = image
        result['materials_without_image_texture'] = missing_textures
        result['images'] = [{'name': image.name, 'width': int(image.size[0]),
                             'height': int(image.size[1]), 'has_data': bool(image.has_data),
                             'packed': bool(image.packed_file)} for image in images.values()]
        result['unreadable_images'] = [i['name'] for i in result['images']
                                       if not i['has_data'] or i['width'] <= 0 or i['height'] <= 0]
    return result


def compare(reference, actual):
    delta = abs(reference['triangles'] - actual['triangles'])
    tolerance = max(TRIANGLE_ABSOLUTE_TOLERANCE,
                    reference['triangles'] * TRIANGLE_RELATIVE_TOLERANCE)
    bound_delta = None
    if reference['bounds_min'] is not None and actual['bounds_min'] is not None:
        bound_delta = float(np.abs(np.array([reference['bounds_min'], reference['bounds_max']]) -
                                  np.array([actual['bounds_min'], actual['bounds_max']])).max())
    return {'triangle_delta': delta, 'triangle_tolerance': tolerance,
            'triangles_match': delta <= tolerance, 'bounds_max_delta_m': bound_delta,
            'bounds_match': bound_delta is not None and bound_delta <= BOUNDS_TOLERANCE,
            'materials_count_match': reference['materials'] == actual['materials']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'docs/export_validation.json')
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    options = parser.parse_args(argv)
    began = time.time()
    report = {'started_utc': datetime.now(timezone.utc).isoformat(),
              'blender_version': bpy.app.version_string,
              'method': 'Final source visual collections compared with isolated clean-scene re-imports of all 4 visual GLBs and 4 FBXs; no source regeneration.',
              'coordinate_system': 'Region-local Blender XYZ, Z up, meters',
              'bounds_tolerance_m': BOUNDS_TOLERANCE,
              'triangle_relative_tolerance': TRIANGLE_RELATIVE_TOLERANCE,
              'triangle_absolute_tolerance': TRIANGLE_ABSOLUTE_TOLERANCE,
              'scope': 'Geometry/UV/material/image-data portability, not rendered appearance or gameplay collision.',
              'regions': [], 'failures': []}

    def fail(region, kind, **details):
        report['failures'].append({'region': region, 'kind': kind, **details})

    inputs = [SOURCE, MANIFEST, BUILD_REPORT]
    inputs += [ROOT / folder / (rid + extension) for rid in REGIONS
               for folder, extension in [('assets/models', '.glb'), ('source', '.fbx')]]
    initial = {}
    try:
        for path in inputs:
            initial[str(path)] = stamp(path)
        manifest = json.loads(MANIFEST.read_text(encoding='utf-8-sig'))
        build = json.loads(BUILD_REPORT.read_text(encoding='utf-8-sig'))
        positions = {region['id']: (region['position'][0], -region['position'][2], region['position'][1])
                     for region in manifest['regions']}
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.wm.open_mainfile(filepath=str(SOURCE), load_ui=False)
        references = {}
        for rid in REGIONS:
            collection = bpy.data.collections.get(rid)
            if collection is None:
                raise ValueError('Source visual collection missing: ' + rid)
            references[rid] = snapshot([ob for ob in collection.objects if not ob.name.startswith('COL_')],
                                       offset=positions[rid], inspect_images=False)
            expected = build['regions'][rid]['visual_triangles']
            if references[rid]['triangles'] != expected:
                fail(rid, 'source_build_report_triangle_mismatch', source=references[rid]['triangles'], report=expected)
        for rid in REGIONS:
            record = {'id': rid, 'source_visual': references[rid], 'formats': {}}
            report['regions'].append(record)
            for extension, folder in (('.glb', 'assets/models'), ('.fbx', 'source')):
                key = extension[1:]
                path = ROOT / folder / (rid + extension)
                entry = {'path': str(path.relative_to(ROOT)), **initial[str(path)], 'sha256': digest(path)}
                record['formats'][key] = entry
                try:
                    entry['embedding'] = glb_embedding(path) if key == 'glb' else fbx_embedding(path)
                    embedding = entry['embedding']
                    if (embedding['embedded_images'] <= 0 or
                            embedding['embedded_images'] != embedding['declared_images'] or
                            embedding.get('external_image_uris') or embedding.get('missing_embedded_image_indices')):
                        fail(rid, 'incomplete_embedded_images', format=key, embedding=embedding)
                    with tempfile.TemporaryDirectory(prefix='europe_export_qa_') as temporary:
                        staged = Path(temporary) / path.name
                        copyfile(path, staged)
                        bpy.ops.wm.read_factory_settings(use_empty=True)
                        if key == 'glb':
                            bpy.ops.import_scene.gltf(filepath=str(staged))
                        else:
                            bpy.ops.import_scene.fbx(filepath=str(staged), use_image_search=False)
                        actual = snapshot(bpy.context.scene.objects)
                        entry['imported'] = actual
                        entry['source_comparison'] = compare(references[rid], actual)
                        for name in ('empty_meshes', 'missing_uv_meshes', 'invalid_uv_meshes',
                                     'nonfinite_meshes', 'invalid_material_meshes',
                                     'materials_without_image_texture', 'unreadable_images'):
                            if actual[name]:
                                fail(rid, name, format=key, items=actual[name])
                        if actual['meshes'] == 0 or actual['triangles'] == 0 or actual['materials'] == 0:
                            fail(rid, 'empty_import', format=key)
                        for name in ('triangles_match', 'bounds_match', 'materials_count_match'):
                            if not entry['source_comparison'][name]:
                                fail(rid, 'source_' + name, format=key, comparison=entry['source_comparison'])
                        # Release extracted image handles before cleaning the temporary directory.
                        bpy.ops.wm.read_factory_settings(use_empty=True)
                    print('EXPORT_QA', rid, key, actual['meshes'], 'meshes', actual['triangles'], 'triangles', flush=True)
                except Exception as exc:
                    entry['error'] = str(exc)
                    fail(rid, 'import_or_inspection_error', format=key, message=str(exc), traceback=traceback.format_exc())
            if all('imported' in record['formats'].get(key, {}) for key in ('glb', 'fbx')):
                comparison = compare(record['formats']['glb']['imported'], record['formats']['fbx']['imported'])
                record['glb_fbx_comparison'] = comparison
                if not all(comparison[name] for name in ('triangles_match', 'bounds_match', 'materials_count_match')):
                    fail(rid, 'glb_fbx_mismatch', comparison=comparison)
    except Exception as exc:
        fail('all', 'setup_or_source_error', message=str(exc), traceback=traceback.format_exc())
    finally:
        for path in inputs:
            try:
                if initial.get(str(path)) != stamp(path):
                    fail('all', 'input_changed_during_validation', path=str(path))
            except OSError as exc:
                fail('all', 'input_missing', path=str(path), message=str(exc))
        report['source_file'] = {'path': str(SOURCE.relative_to(ROOT)), **initial.get(str(SOURCE), {})}
        report['completed_utc'] = datetime.now(timezone.utc).isoformat()
        report['seconds'] = round(time.time() - began, 2)
        report['passed'] = not report['failures'] and len(report['regions']) == len(REGIONS)
        options.output.parent.mkdir(parents=True, exist_ok=True)
        options.output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
        print('EXPORT_VALIDATION_RESULT', json.dumps({'passed': report['passed'], 'failures': report['failures'],
                                                    'report': str(options.output)}, ensure_ascii=False), flush=True)
    if not report['passed']:
        raise RuntimeError('Export validation failed; inspect ' + str(options.output))


if __name__ == '__main__':
    main()

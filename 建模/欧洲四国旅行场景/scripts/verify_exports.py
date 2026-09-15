"""Read-only Blender/GLB/FBX interoperability audit for the delivered asset pack.

Run with Blender background. Original artifacts are never saved or overwritten.
FBX extraction is confined to disposable copies in a temporary directory.
"""
import bpy
import json
import math
import shutil
import struct
import tempfile
import time
import traceback
from datetime import datetime, timezone
from pathlib import Path
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
BLEND = ROOT / '欧洲四国旅行场景.blend'
EXPORTS = ROOT / 'exports'
REGIONS = {
    'FR_Paris': (-80, 72, 0),
    'IT_Rome': (80, 72, 0),
    'CH_Alps': (-80, -72, 0),
    'DE_Bavaria': (80, -72, 0),
}
REPORT = {
    'started_utc': datetime.now(timezone.utc).isoformat(),
    'blender_version': bpy.app.version_string,
    'scope': 'Offline Blender source and export reimport validation; no engine performance or collision integration claim.',
    'source_blend': str(BLEND),
    'source': {},
    'primary_exports': {},
    'lod1': {},
    'collision': {},
    'failures': [],
    'warnings': [],
}
LOG_LINES = []


def log(message):
    line = 'VERIFY | ' + message
    print(line, flush=True)
    LOG_LINES.append(line)


def failure(context, message):
    REPORT['failures'].append({'context': context, 'message': message})
    log('FAIL ' + context + ': ' + message)


def warning(context, message):
    REPORT['warnings'].append({'context': context, 'message': message})
    log('WARN ' + context + ': ' + message)


def guard(context, operation):
    try:
        return operation()
    except Exception as exc:
        failure(context, type(exc).__name__ + ': ' + str(exc))
        LOG_LINES.append(traceback.format_exc())
        return None


def image_evidence(image):
    packed = bool(getattr(image, 'packed_file', None))
    packed = packed or bool(getattr(image, 'packed_files', []))
    path = image.filepath or ''
    resolved = bpy.path.abspath(path, library=image.library) if path else ''
    exists = bool(resolved and Path(resolved).is_file())
    generated = image.source in {'GENERATED', 'VIEWER'}
    available = packed or exists or (generated and image.has_data)
    return {
        'name': image.name,
        'source': image.source,
        'packed': packed,
        'filepath': path,
        'resolved_path': resolved,
        'external_file_exists_at_check': exists,
        'loaded_pixel_data': bool(image.has_data),
        'dimensions': list(image.size),
        'available': available,
    }


def audit_meshes(objects, context, origin=(0, 0, 0), materials_required=True):
    objects = [obj for obj in objects if obj.type == 'MESH']
    if not objects:
        failure(context, 'No mesh objects.')
    lo, hi = [math.inf] * 3, [-math.inf] * 3
    total_triangles, total_vertices = 0, 0
    missing_uv, empty_materials, bad_coordinate_objects, bad_transforms = [], [], [], []
    materials, object_details = {}, {}
    origin = Vector(origin)
    for obj in objects:
        mesh = obj.data
        mesh.calc_loop_triangles()
        triangles = len(mesh.loop_triangles)
        total_triangles += triangles
        total_vertices += len(mesh.vertices)
        if not mesh.uv_layers:
            missing_uv.append(obj.name)
        if materials_required and not mesh.materials:
            empty_materials.append(obj.name)
        transform_values = [value for row in obj.matrix_world for value in row]
        transform_ok = all(math.isfinite(value) for value in transform_values)
        if not transform_ok:
            bad_transforms.append(obj.name)
        finite = True
        for vertex in mesh.vertices:
            point = obj.matrix_world @ vertex.co - origin
            if not all(math.isfinite(value) for value in point):
                finite = False
                continue
            for i, value in enumerate(point):
                lo[i], hi[i] = min(lo[i], value), max(hi[i], value)
        if not finite:
            bad_coordinate_objects.append(obj.name)
        if obj.parent and obj.parent.name not in bpy.data.objects:
            failure(context, 'Unresolved parent on ' + obj.name)
        object_details[obj.name] = {
            'vertices': len(mesh.vertices), 'triangles': triangles,
            'uv_layers': len(mesh.uv_layers),
            'materials': [mat.name for mat in mesh.materials if mat],
            'parent': obj.parent.name if obj.parent else None,
            'matrix_world_finite': transform_ok,
            'role': obj.get('role', ''),
        }
        for mat in mesh.materials:
            if mat is not None:
                materials[mat.name] = mat
    for names, label in [(missing_uv, 'Missing UV layer'), (empty_materials, 'Missing materials'),
                         (bad_coordinate_objects, 'Nonfinite vertex coordinates'),
                         (bad_transforms, 'Nonfinite object transforms')]:
        if names:
            failure(context, label + ': ' + ', '.join(names))
    material_details, images = {}, {}
    for name, mat in materials.items():
        nodes = list(mat.node_tree.nodes) if mat.use_nodes and mat.node_tree else []
        texture_nodes = [node for node in nodes if node.type == 'TEX_IMAGE']
        populated_nodes = [node for node in texture_nodes if node.image is not None]
        if materials_required and not populated_nodes:
            failure(context, 'Material has no image texture: ' + name)
        unpopulated = [node.name for node in texture_nodes if node.image is None]
        if unpopulated:
            warning(context, 'Empty image texture nodes in material ' + name + ': ' + ', '.join(unpopulated))
        material_details[name] = {
            'image_texture_nodes': len(texture_nodes),
            'populated_image_nodes': len(populated_nodes),
            'images': [node.image.name for node in populated_nodes],
        }
        for node in populated_nodes:
            if node.image.name not in images:
                entry = image_evidence(node.image)
                images[node.image.name] = entry
                if not entry['available']:
                    failure(context, 'Missing image data/file: ' + node.image.name + ' (' + entry['filepath'] + ')')
                if entry['dimensions'][0] <= 0 or entry['dimensions'][1] <= 0:
                    failure(context, 'Image has zero dimensions: ' + node.image.name)
    glass = [name for name in materials if name.split('.')[0].casefold() == 'glass']
    if materials_required and not glass:
        failure(context, 'Expected glass material is absent.')
    if not objects or not all(math.isfinite(x) for x in lo + hi):
        bounds, extent = None, None
    else:
        bounds = {'min': lo, 'max': hi}
        extent = [hi[i] - lo[i] for i in range(3)]
    return {
        'mesh_objects': len(objects), 'vertices': total_vertices,
        'triangles': total_triangles, 'bounds_in_region_meters': bounds,
        'extent_meters': extent, 'glass_materials': glass,
        'material_count': len(materials), 'image_count': len(images),
        'objects': object_details, 'materials': material_details, 'images': images,
    }


def read_glb(path, context):
    data = path.read_bytes()
    if len(data) < 28:
        raise ValueError('GLB is too small or empty.')
    magic, version, byte_length = struct.unpack_from('<4sII', data, 0)
    if magic != b'glTF' or version != 2 or byte_length != len(data):
        raise ValueError('Invalid GLB 2.0 header or declared file length.')
    cursor, document, binary_bytes = 12, None, 0
    while cursor + 8 <= len(data):
        chunk_length, chunk_type = struct.unpack_from('<II', data, cursor)
        cursor += 8
        if cursor + chunk_length > len(data):
            raise ValueError('GLB chunk exceeds file length.')
        chunk = data[cursor:cursor + chunk_length]
        if chunk_type == 0x4E4F534A:
            document = json.loads(chunk.decode('utf-8').rstrip(' \x00'))
        elif chunk_type == 0x004E4942:
            binary_bytes += len(chunk)
        cursor += chunk_length
    if cursor != len(data) or document is None:
        raise ValueError('Missing JSON or invalid trailing GLB bytes.')
    if not document.get('meshes') or not document.get('nodes') or not binary_bytes:
        raise ValueError('GLB has no mesh/node/binary payload.')
    accessors = document.get('accessors', [])
    triangles = 0
    for mesh in document['meshes']:
        for primitive in mesh.get('primitives', []):
            index = primitive.get('indices', primitive.get('attributes', {}).get('POSITION'))
            if index is None or index >= len(accessors):
                raise ValueError('Mesh primitive has no valid vertex/index accessor.')
            count = accessors[index]['count']
            mode = primitive.get('mode', 4)
            if mode == 4:
                triangles += count // 3
                if count % 3:
                    failure(context, 'Triangle index count is not divisible by 3.')
            elif mode in (5, 6):
                triangles += max(0, count - 2)
            else:
                warning(context, 'Non-triangle glTF primitive mode: ' + str(mode))
    if triangles <= 0:
        raise ValueError('GLB contains no triangles.')
    return {
        'path': str(path), 'bytes': len(data), 'glb_version': version,
        'declared_length_matches': True, 'mesh_count': len(document['meshes']),
        'node_count': len(document['nodes']), 'binary_payload_bytes': binary_bytes,
        'triangles_from_accessors': triangles,
        'embedded_image_count': sum('bufferView' in image for image in document.get('images', [])),
    }


def compare_import(imported, source, context):
    if imported['triangles'] != source['triangles']:
        failure(context, 'Triangle total changed: original ' + str(source['triangles']) +
                ', reimported ' + str(imported['triangles']) + '.')
    original_names, imported_names = set(source['objects']), set(imported['objects'])
    if original_names != imported_names:
        failure(context, 'Mesh identity mismatch. Missing=' + str(sorted(original_names - imported_names)) +
                '; unexpected=' + str(sorted(imported_names - original_names)))
    for name in original_names & imported_names:
        before, after = source['objects'][name], imported['objects'][name]
        if before['triangles'] != after['triangles']:
            failure(context, 'Per-object triangle count changed for ' + name + ': ' +
                    str(before['triangles']) + ' -> ' + str(after['triangles']))
        if before['parent'] != after['parent']:
            failure(context, 'Hierarchy parent changed for ' + name)
    a, b = imported['bounds_in_region_meters'], source['bounds_in_region_meters']
    if a and b:
        delta = max(abs(a[side][i] - b[side][i]) for side in ('min', 'max') for i in range(3))
        imported['max_bounds_delta_meters'] = delta
        if delta > .02:
            failure(context, 'Local-origin scale/extent mismatch: maximum bounds delta ' + str(delta) + ' m.')


def inspect_original():
    bpy.ops.wm.open_mainfile(filepath=str(BLEND), load_ui=False)
    for name, offset in REGIONS.items():
        def inspect_region():
            collection = bpy.data.collections.get(name)
            if collection is None:
                raise ValueError('Required visual collection missing: ' + name)
            meshes = [obj for obj in collection.all_objects if obj.type == 'MESH' and obj.get('role') == 'visual']
            unexpected = [obj.name for obj in collection.all_objects if obj.type == 'MESH' and obj.get('role') != 'visual']
            if unexpected:
                warning('source/' + name, 'Nonvisual mesh members excluded: ' + ', '.join(unexpected))
            entry = audit_meshes(meshes, 'source/' + name, origin=offset)
            REPORT['source'][name] = entry
            log(name + ' original: ' + str(entry['mesh_objects']) + ' meshes / ' + str(entry['triangles']) + ' triangles')
        guard('source/' + name, inspect_region)


def import_primary(region, extension, temp_root):
    context = region + extension
    original_path = EXPORTS / context
    if not original_path.is_file():
        raise FileNotFoundError(str(original_path))
    before_bytes = original_path.stat().st_size
    if extension == '.glb':
        container = read_glb(original_path, context)
        import_path = original_path
    else:
        container = {'path': str(original_path), 'bytes': before_bytes}
        folder = temp_root / region
        folder.mkdir(exist_ok=True)
        import_path = folder / original_path.name
        shutil.copy2(original_path, import_path)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if extension == '.glb':
        bpy.ops.import_scene.gltf(filepath=str(import_path))
    else:
        bpy.ops.import_scene.fbx(filepath=str(import_path), use_image_search=True)
    entry = audit_meshes(list(bpy.context.scene.objects), context)
    entry['container'] = container
    if extension == '.fbx':
        entry['embedded_texture_extraction'] = {
            'temporary_import_copy': True,
            'packed_image_count': sum(image['packed'] for image in entry['images'].values()),
            'external_image_files_count': sum(image['external_file_exists_at_check'] for image in entry['images'].values()),
            'extracted_files': [str(p.relative_to(temp_root)) for p in temp_root.rglob('*')
                                if p.is_file() and p.suffix.lower() not in {'.fbx'}],
            'note': 'Embedded FBX images may be loaded directly as packed Blender images without disk extraction. Temporary files, if created, are removed after the audit; existence is recorded at import time.',
        }
    REPORT['primary_exports'][context] = entry
    if region in REPORT['source']:
        compare_import(entry, REPORT['source'][region], context)
    else:
        failure(context, 'Cannot compare because source collection validation failed.')
    log(context + ': ' + str(entry['mesh_objects']) + ' meshes / ' + str(entry['triangles']) + ' triangles / ' +
        str(entry['image_count']) + ' images')


def import_lod(region):
    context = region + '_LOD1.glb'
    path = EXPORTS / context
    container = read_glb(path, context)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(path))
    entry = audit_meshes(list(bpy.context.scene.objects), context)
    entry['container'] = container
    original = REPORT['source'].get(region, {}).get('triangles')
    entry['original_triangles'] = original
    if original:
        entry['triangle_ratio_to_original'] = entry['triangles'] / original
        if not 0 < entry['triangles'] < original:
            failure(context, 'LOD1 is not smaller than the original geometry.')
    else:
        failure(context, 'Source triangle count is unavailable for LOD comparison.')
    REPORT['lod1'][region] = entry
    log(context + ': ' + str(entry['triangles']) + ' triangles; original ' + str(original))


def main():
    started = time.time()
    log('Starting Blender source and export audit.')
    guard('source_blend', inspect_original)
    with tempfile.TemporaryDirectory(prefix='europe_fbx_verify_') as temp:
        temp_root = Path(temp)
        for region in REGIONS:
            for extension in ('.glb', '.fbx'):
                guard(region + extension, lambda r=region, e=extension: import_primary(r, e, temp_root))
            guard(region + '_LOD1.glb', lambda r=region: import_lod(r))
            context = region + '_Collision.glb'
            collision = guard(context, lambda p=EXPORTS / context, c=context: read_glb(p, c))
            if collision:
                REPORT['collision'][region] = collision
                log(context + ': valid GLB 2.0, ' + str(collision['triangles_from_accessors']) + ' triangles')
    expected = [('source', 4), ('primary_exports', 8), ('lod1', 4), ('collision', 4)]
    for field, count in expected:
        if len(REPORT[field]) != count:
            failure('coverage', field + ': expected ' + str(count) + ', recorded ' + str(len(REPORT[field])))
    REPORT['completed_utc'] = datetime.now(timezone.utc).isoformat()
    REPORT['elapsed_seconds'] = round(time.time() - started, 2)
    REPORT['summary'] = {
        'passed': not REPORT['failures'],
        'failure_count': len(REPORT['failures']), 'warning_count': len(REPORT['warnings']),
        'original_triangles_total': sum(row['triangles'] for row in REPORT['source'].values()),
        'primary_reimports_checked': len(REPORT['primary_exports']),
        'lod_reimports_checked': len(REPORT['lod1']),
        'collision_containers_checked': len(REPORT['collision']),
    }
    log('DONE ' + json.dumps(REPORT['summary'], ensure_ascii=False))
    (ROOT / 'export_verification.json').write_text(json.dumps(REPORT, ensure_ascii=False, indent=2), encoding='utf-8')
    (ROOT / 'export_verification.log').write_text('\n'.join(LOG_LINES) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()

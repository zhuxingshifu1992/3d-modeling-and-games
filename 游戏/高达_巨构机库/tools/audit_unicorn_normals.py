"""Read-only OBJ head winding/corner-normal audit; emits reports, never an asset."""
from pathlib import Path
import collections
import hashlib
import json
import sys
import bpy
import bmesh
from mathutils import Vector
from mathutils.kdtree import KDTree

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'source/external/unicorn_sketchfab/author_source/UNICORN_GUNDAM_OBJ.obj'
OUT = ROOT / 'previews/refined_unicorn'
HEAD_MATERIALS = {'blinn1SG', 'blinn2SG', 'blinn4SG'}


def sha256(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(4 * 1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def ranges(ids):
    ids = sorted(ids)
    result = []
    for i in ids:
        if result and i == result[-1][1] + 1:
            result[-1][1] = i
        else:
            result.append([i, i])
    return result


def bbox(points):
    return [[min(v[a] for v in points) for a in range(3)],
            [max(v[a] for v in points) for a in range(3)]]


def validate_derived():
    target = ROOT / 'assets/models/unicorn_refined.glb'
    hash_before = sha256(target)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(target))
    objects = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    all_points = [o.matrix_world @ v.co for o in objects for v in o.data.vertices]
    data = {'target': str(target), 'sha256_before': hash_before,
            'blender_version': bpy.app.version_string,
            'bounds_world': bbox(all_points), 'meshes': [], 'components': []}
    component_points = {}
    for obj in objects:
        mesh = obj.data
        names = [m.name if m else '' for m in mesh.materials]
        selected = {p.index for p in mesh.polygons if 'HEAD_WHITE' in names[p.material_index].upper()}
        data['meshes'].append({'name': obj.name, 'materials': names,
                               'head_white_faces': len(selected), 'has_custom_normals': mesh.has_custom_normals})
        if not selected:
            continue
        # glTF duplicates vertices at UV/smoothing seams; exact source positions
        # are retained. Canonicalize positions at 0.1 micrometre for connectivity.
        world = [obj.matrix_world @ v.co for v in mesh.vertices]
        canonical = [tuple(round(c, 7) for c in p) for p in world]
        edge_faces = collections.defaultdict(list)
        for i in selected:
            vs = [canonical[v] for v in mesh.polygons[i].vertices]
            for a,b in zip(vs, vs[1:] + vs[:1]):
                if a != b:
                    edge_faces[tuple(sorted((a,b)))].append((i, 1 if a < b else -1))
        neighbors = collections.defaultdict(set)
        for linked in edge_faces.values():
            for i,_ in linked:
                neighbors[i].update(j for j,_ in linked if j != i)
        remaining = set(selected)
        components = []
        while remaining:
            seed = min(remaining)
            remaining.remove(seed)
            todo = [seed]
            inds = []
            while todo:
                i = todo.pop()
                inds.append(i)
                for j in neighbors[i]:
                    if j in remaining:
                        remaining.remove(j)
                        todo.append(j)
            components.append(inds)
        normals = mesh.corner_normals
        for inds in components:
            ids = set(inds)
            verts = {v for i in inds for v in mesh.polygons[i].vertices}
            points = [world[v] for v in verts]
            center = sum(points, Vector()) / len(points)
            edges = {tuple(sorted((a,b))) for i in inds
                     for vs in [[canonical[v] for v in mesh.polygons[i].vertices]]
                     for a,b in zip(vs, vs[1:] + vs[:1]) if a != b}
            boundary = sum(len(edge_faces[e]) == 1 for e in edges)
            nonmanifold = sum(len(edge_faces[e]) > 2 for e in edges)
            inconsistent = sum(len(edge_faces[e]) == 2 and sum(s for _,s in edge_faces[e]) != 0 for e in edges)
            volume = 0.
            mean_dots = []
            for i in inds:
                p = mesh.polygons[i]
                assert len(p.vertices) == 3, 'Expected glTF triangles'
                a,b,c = [world[v] - center for v in p.vertices]
                volume += a.dot(b.cross(c))/6.
                mean_dots.append(sum(p.normal.dot(normals[l].vector) for l in p.loop_indices)/p.loop_total)
            component_points[len(data['components'])] = points
            data['components'].append({'object': obj.name, 'component': len(data['components']),
               'triangles': len(inds), 'bounds_world': bbox(points), 'signed_volume': volume,
               'boundary_edges': boundary, 'nonmanifold_edges': nonmanifold,
               'inconsistent_internal_edges': inconsistent, 'closed_manifold': boundary == 0 and nonmanifold == 0,
               'mean_face_corner_dot': sum(mean_dots)/len(mean_dots),
               'negative_mean_dot_faces': sum(d < -.05 for d in mean_dots),
               'min_mean_face_corner_dot': min(mean_dots),
               'polygon_index_ranges': ranges(inds)})
    # Match observed derived bounds against source-audit components after the
    # independently specified sole-to-head 21.7 m calibration and 180deg yaw.
    baseline = json.loads((OUT/'normals_geometry_audit.json').read_text(encoding='utf8'))
    source_geometry = json.loads((OUT/'source_geometry.json').read_text(encoding='utf8'))
    source_components = baseline['objects'][0]['head_components']
    floor = source_geometry['bounds'][0][2]
    antenna = max(c['bounds_world'][1][2] for c in source_components)
    scale = 21.7/(antenna-floor)
    comparisons = []
    for ci in [23,24,25,32,33,34]:
        src = source_components[ci]
        lo,hi = src['bounds_world']
        expected = [[-scale*hi[0], -scale*hi[1], scale*(lo[2]-floor)],
                    [-scale*lo[0], -scale*lo[1], scale*(hi[2]-floor)]]
        found = min(data['components'], key=lambda c: max(abs(c['bounds_world'][j][k]-expected[j][k])
                                                          for j in range(2) for k in range(3)))
        err = max(abs(found['bounds_world'][j][k]-expected[j][k]) for j in range(2) for k in range(3))
        expected_volume = abs(src['signed_volume'])*scale**3
        comp = {'source_component': ci, 'role': 'repaired_left_source_shell' if ci<30 else 'original_right_source_reference',
                'derived_component': found['component'], 'bounds_max_error_m': err,
                'source_polygon_count': src['face_count'], 'derived_triangles': found['triangles'],
                'signed_volume_m3': found['signed_volume'], 'expected_positive_volume_m3': expected_volume,
                'volume_absolute_error_m3': abs(found['signed_volume']-expected_volume),
                'volume_relative_error_to_source': abs(found['signed_volume']-expected_volume)/expected_volume,
                'closed_manifold': found['closed_manifold'], 'boundary_edges': found['boundary_edges'],
                'inconsistent_internal_edges': found['inconsistent_internal_edges'],
                'mean_face_corner_dot': found['mean_face_corner_dot'],
                'negative_mean_dot_faces': found['negative_mean_dot_faces']}
        comp['passed'] = (err < 2e-5 and found['signed_volume'] > 0
             and found['inconsistent_internal_edges'] == 0 and found['mean_face_corner_dot'] > .5
             and found['negative_mean_dot_faces'] == 0
             and found['closed_manifold'] == src['closed_manifold'])
        comparisons.append(comp)
    pairs = []
    for left,right in zip(comparisons[:3],comparisons[3:]):
        lp = component_points[left['derived_component']]
        rp = component_points[right['derived_component']]
        tree = KDTree(len(rp))
        for n,p in enumerate(rp):
            tree.insert(p,n)
        tree.balance()
        max_dist = max(tree.find(Vector((-p.x,p.y,p.z)))[2] for p in lp)
        volume_delta = abs(left['signed_volume_m3']-right['signed_volume_m3'])
        rel_delta = volume_delta/right['signed_volume_m3']
        pair = {'left_source_component': left['source_component'], 'right_source_component':right['source_component'],
                'max_mirrored_vertex_distance_m': max_dist,
                'signed_volume_difference_m3': volume_delta, 'relative_signed_volume_difference': rel_delta,
                'equal_triangle_counts': left['derived_triangles'] == right['derived_triangles'],
                'equal_boundary_edge_counts': left['boundary_edges'] == right['boundary_edges']}
        pair['passed'] = (max_dist<2e-6 and rel_delta<2e-5 and pair['equal_triangle_counts']
                          and pair['equal_boundary_edge_counts'])
        pairs.append(pair)
    data['normalization_reference'] = {'source_floor': floor, 'source_antenna': antenna, 'uniform_scale': scale,
        'basis': 'Prior raw-source geometry audit; no converter success assertion used'}
    data['six_shell_comparisons'] = comparisons
    data['exported_mirrored_pair_checks'] = pairs
    data['sha256_after'] = sha256(target)
    data['passed'] = all(c['passed'] for c in comparisons+pairs) and data['sha256_after'] == hash_before
    data['limitations'] = ['609 source polygons are triangulated in GLB; verification matches the six shell bounds and signed volumes, not original polygon indices.',
        'The third shell on each side is open (12 original boundary edges, subdivided in the derived mesh); its volume sign alone is not sufficient, so mirrored vertex geometry, signed volumes, triangle counts, boundary counts, and corner normal agreement are also checked.',
        'Compared with the original source polygons, converter bisect operations add subdivisions; triangulation of nonplanar polygons changes signed volumes slightly (about 0.15 percent maximum observed). Exported left/right counterparts agree much more closely and are checked independently.',
        'This check establishes orientation in exported geometry, not exact preservation of the original custom normal vectors.']
    path = OUT/'derived_head_normals_validation.json'
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf8')
    print('DERIVED_HEAD_NORMALS', json.dumps({'passed': data['passed'], 'target_sha256': hash_before,
        'comparisons': comparisons},ensure_ascii=False),flush=True)
    print('REPORT',path,flush=True)
    assert data['passed'], 'Derived shell validation failed; inspect report'


if '--derived' in sys.argv:
    validate_derived()
    sys.exit(0)


source_hash = sha256(SOURCE)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.obj_import(filepath=str(SOURCE), use_split_objects=True, use_split_groups=False)
report = {'source': str(SOURCE), 'source_sha256_before': source_hash,
          'blender_version': bpy.app.version_string, 'objects': []}

for obj in [o for o in bpy.context.scene.objects if o.type == 'MESH']:
    mesh = obj.data
    mesh.calc_loop_triangles()
    mats = [m.name if m else '' for m in mesh.materials]
    head_indices = {p.index for p in mesh.polygons if mats[p.material_index] in HEAD_MATERIALS}
    material_stats = {}
    corner_normals = mesh.corner_normals
    for p in mesh.polygons:
        name = mats[p.material_index]
        st = material_stats.setdefault(name, {'faces': 0, 'loops': 0, 'negative_corner_dot': 0,
                     'negative_mean_corner_dot_faces': 0, 'corner_dot_min': 1.,
                     'corner_dot_sum': 0., 'area': 0., 'negative_mean_dot_area': 0.})
        st['faces'] += 1
        st['area'] += p.area
        dots = [float(p.normal.dot(corner_normals[i].vector)) for i in p.loop_indices]
        st['loops'] += len(dots)
        st['negative_corner_dot'] += sum(d < -.05 for d in dots)
        st['corner_dot_min'] = min(st['corner_dot_min'], min(dots))
        st['corner_dot_sum'] += sum(dots)
        if sum(dots) / len(dots) < -.05:
            st['negative_mean_corner_dot_faces'] += 1
            st['negative_mean_dot_area'] += p.area
    for st in material_stats.values():
        st['corner_dot_mean'] = st.pop('corner_dot_sum') / st['loops']

    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.faces.ensure_lookup_table()
    bm.verts.ensure_lookup_table()
    bm.normal_update()
    initial_normals = {i: bm.faces[i].normal.copy() for i in head_indices}
    remaining = set(head_indices)
    components = []
    while remaining:
        seed = min(remaining)
        stack = [seed]
        remaining.remove(seed)
        inds = []
        while stack:
            fi = stack.pop()
            inds.append(fi)
            for edge in bm.faces[fi].edges:
                for neighbor in edge.link_faces:
                    if neighbor.index in remaining:
                        remaining.remove(neighbor.index)
                        stack.append(neighbor.index)
        components.append(sorted(inds))

    triangles = collections.defaultdict(list)
    for tri in mesh.loop_triangles:
        if tri.polygon_index in head_indices:
            triangles[tri.polygon_index].append(tri)
    comp_reports = []
    for ci, inds in enumerate(components):
        face_set = set(inds)
        vertices = {v for i in inds for v in mesh.polygons[i].vertices}
        points = [mesh.vertices[v].co for v in vertices]
        center = sum(points, Vector()) / len(points)
        volume = 0.
        area = 0.
        for i in inds:
            p = mesh.polygons[i]
            area += p.area
            for tri in triangles[i]:
                a, b, c = [mesh.vertices[v].co - center for v in tri.vertices]
                volume += a.dot(b.cross(c)) / 6.
        edges = {e for i in inds for e in bm.faces[i].edges}
        boundary = sum(sum(f.index in face_set for f in e.link_faces) == 1 for e in edges)
        nonmanifold = sum(sum(f.index in face_set for f in e.link_faces) > 2 for e in edges)
        inconsistent = sum(len(e.link_faces) == 2 and not e.is_contiguous for e in edges)
        dots = [float(mesh.polygons[i].normal.dot(corner_normals[l].vector))
                for i in inds for l in mesh.polygons[i].loop_indices]
        comp_reports.append({'component': ci, 'face_count': len(inds), 'vertex_count': len(vertices),
          'materials': dict(collections.Counter(mats[mesh.polygons[i].material_index] for i in inds)),
          'bounds_local': bbox(points), 'bounds_world': bbox([obj.matrix_world @ p for p in points]),
          'boundary_edges': boundary, 'nonmanifold_edges': nonmanifold,
          'inconsistent_internal_edges': inconsistent,
          'closed_manifold': boundary == 0 and nonmanifold == 0,
          'signed_volume': volume, 'surface_area': area,
          'negative_corner_dot': sum(d < -.05 for d in dots),
          'corner_dot_mean': sum(dots) / len(dots),
          'face_index_ranges': ranges(inds)})

    # In-memory counterfactual: standard head-only winding repair.
    bmesh.ops.recalc_face_normals(bm, faces=[bm.faces[i] for i in sorted(head_indices)])
    bm.normal_update()
    changed = {i for i in head_indices if bm.faces[i].normal.dot(initial_normals[i]) < -.5}
    for st, inds in zip(comp_reports, components):
        st['recalc_flipped_faces'] = sum(i in changed for i in inds)
        st['recalc_flipped_face_ranges'] = ranges(i for i in inds if i in changed)
    # The only three globally opposing components also match the correctly
    # wound, mirrored right-side components. Check that independent evidence.
    bad_components = [st for st in comp_reports if st['corner_dot_mean'] < -.5]
    bad_faces = {i for st in bad_components for i in components[st['component']]}
    for bad in bad_components:
        bi = components[bad['component']]
        bverts = {v for i in bi for v in mesh.polygons[i].vertices}
        candidates = [st for st in comp_reports if st['face_count'] == bad['face_count']
                      and st['corner_dot_mean'] > .5]
        matches = []
        for good in candidates:
            gverts = {v for i in components[good['component']] for v in mesh.polygons[i].vertices}
            tree = KDTree(len(gverts))
            for n, vi in enumerate(gverts):
                tree.insert(mesh.vertices[vi].co, n)
            tree.balance()
            max_dist = max(tree.find(Vector((-mesh.vertices[v].co.x,
                             mesh.vertices[v].co.y, mesh.vertices[v].co.z)))[2] for v in bverts)
            matches.append({'component': good['component'], 'max_mirrored_vertex_distance': max_dist,
                            'signed_volume': good['signed_volume']})
        bad['mirrored_reference'] = min(matches, key=lambda m: m['max_mirrored_vertex_distance'])

    # Validate a targeted mesh-level repair on an in-memory copy. Preserve
    # authored corner normal vectors and UV association for each polygon vertex.
    candidate = mesh.copy()
    old_normals = [tuple(n.vector) for n in candidate.corner_normals]
    original_corners = {i: {candidate.loops[l].vertex_index: old_normals[l]
                            for l in candidate.polygons[i].loop_indices} for i in bad_faces}
    original_uv = {i: {candidate.loops[l].vertex_index: tuple(candidate.uv_layers.active.data[l].uv)
                       for l in candidate.polygons[i].loop_indices} for i in bad_faces}
    original_poly_normals = {i: candidate.polygons[i].normal.copy() for i in bad_faces}
    for i in sorted(bad_faces):
        candidate.polygons[i].flip()
    candidate.update()
    restore_normals = list(old_normals)
    for i in bad_faces:
        for l in candidate.polygons[i].loop_indices:
            restore_normals[l] = original_corners[i][candidate.loops[l].vertex_index]
    candidate.normals_split_custom_set(restore_normals)
    candidate.update()
    after_normals = candidate.corner_normals
    uv_errors = 0
    corrected_mean_dots = {}
    for i in bad_faces:
        for l in candidate.polygons[i].loop_indices:
            uv_errors += tuple(candidate.uv_layers.active.data[l].uv) != original_uv[i][candidate.loops[l].vertex_index]
        corrected_mean_dots[i] = sum(candidate.polygons[i].normal.dot(after_normals[l].vector)
                                    for l in candidate.polygons[i].loop_indices) / candidate.polygons[i].loop_total
    normal_max_error = max((Vector(restore_normals[l]) - after_normals[l].vector).length
                           for l in range(len(restore_normals)))
    candidate.calc_loop_triangles()
    volumes_after = {}
    for st in bad_components:
        inds = set(components[st['component']])
        verts = {v for i in inds for v in candidate.polygons[i].vertices}
        center = sum((candidate.vertices[v].co for v in verts), Vector()) / len(verts)
        volume = 0.
        for t in candidate.loop_triangles:
            if t.polygon_index in inds:
                a, b, c = [candidate.vertices[v].co - center for v in t.vertices]
                volume += a.dot(b.cross(c)) / 6.
        volumes_after[str(st['component'])] = volume
    verification = {'method': 'MeshPolygon.flip only on identified 609 faces; restore custom normals by polygon+vertex identity',
                    'flipped_faces': len(bad_faces), 'flipped_face_ranges': ranges(bad_faces),
                    'uv_mapping_errors': uv_errors,
                    'custom_normal_max_vector_error': normal_max_error,
                    'corrected_faces_still_negative_mean_dot': sum(v < -.05 for v in corrected_mean_dots.values()),
                    'corrected_mean_dot_min': min(corrected_mean_dots.values()),
                    'signed_volumes_after': volumes_after,
                    'unchanged_vertex_coordinates': all(a.co == b.co for a,b in zip(mesh.vertices, candidate.vertices)),
                    'unchanged_material_indices': all(a.material_index == b.material_index for a,b in zip(mesh.polygons,candidate.polygons)),
                    'unchanged_polygon_vertex_sets': all(set(a.vertices) == set(b.vertices) for a,b in zip(mesh.polygons,candidate.polygons)),
                    'other_faces_winding_unchanged': all(tuple(mesh.polygons[i].vertices) == tuple(candidate.polygons[i].vertices)
                                                        for i in range(len(mesh.polygons)) if i not in bad_faces)}
    residuals = []
    for i in sorted(head_indices - bad_faces):
        p = mesh.polygons[i]
        dot = sum(p.normal.dot(corner_normals[l].vector) for l in p.loop_indices) / p.loop_total
        if dot < -.05:
            residuals.append({'face': i, 'material': mats[p.material_index], 'mean_dot': dot,
                              'area': p.area, 'vertices': [list(mesh.vertices[v].co) for v in p.vertices],
                              'component': next(st['component'] for st, inds in zip(comp_reports,components) if i in inds)})
    verification['negative_mean_dot_faces_outside_identified_inward_components'] = residuals
    assert verification['flipped_faces'] == 609
    assert verification['uv_mapping_errors'] == 0
    assert verification['corrected_faces_still_negative_mean_dot'] == 0
    assert verification['custom_normal_max_vector_error'] < 1e-3
    assert all(v > 0 for v in volumes_after.values())
    assert all(verification[k] for k in ['unchanged_vertex_coordinates', 'unchanged_material_indices',
               'unchanged_polygon_vertex_sets', 'other_faces_winding_unchanged'])
    bpy.data.meshes.remove(candidate)
    report['objects'].append({'name': obj.name, 'has_custom_normals': mesh.has_custom_normals,
      'material_stats': material_stats, 'head_faces': len(head_indices),
      'head_components': comp_reports,
      'head_recalc_changed_face_count': len(changed),
      'head_recalc_changed_face_ranges': ranges(changed),
      'targeted_repair_verification': verification})
    bm.free()

report['source_sha256_after'] = sha256(SOURCE)
assert report['source_sha256_after'] == source_hash, 'Source mutated'
OUT.mkdir(parents=True, exist_ok=True)
path = OUT / 'normals_geometry_audit.json'
path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
for o in report['objects']:
    print('NORMALS_AUDIT', o['name'], 'custom=', o['has_custom_normals'],
          'head_faces=', o['head_faces'], 'components=', len(o['head_components']),
          'recalc_flipped=', o['head_recalc_changed_face_count'], flush=True)
    for mat, st in o['material_stats'].items():
        print('MATERIAL', mat, json.dumps(st), flush=True)
    for comp in o['head_components']:
        print('COMPONENT', json.dumps({k: v for k, v in comp.items() if 'ranges' not in k}), flush=True)
print('REPORT', path, flush=True)

"""Read a downloaded GLB without executing embedded content or changing the file."""
import argparse
import hashlib
import json
import struct
from pathlib import Path


def image_size(data):
    if data[:8] == b'\x89PNG\r\n\x1a\n':
        return list(struct.unpack_from('>II', data, 16))
    if data[:2] == b'\xff\xd8':
        pos = 2
        while pos + 9 < len(data):
            if data[pos] != 255:
                pos += 1
                continue
            marker = data[pos + 1]
            pos += 2
            if marker in (0xD8, 0xD9) or marker == 0:
                continue
            if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
                height, width = struct.unpack_from('>HH', data, pos + 3)
                return [width, height]
            pos += struct.unpack_from('>H', data, pos)[0]
    return None


parser = argparse.ArgumentParser()
parser.add_argument('source', type=Path)
parser.add_argument('report', type=Path)
args = parser.parse_args()
raw = args.source.read_bytes()
magic, version, declared = struct.unpack_from('<III', raw)
assert magic == 0x46546C67 and version == 2, 'Not GLB 2.0'
assert declared == len(raw), 'Incomplete GLB: header length differs from file length'
chunks = []
offset = 12
while offset < len(raw):
    size, kind = struct.unpack_from('<II', raw, offset)
    assert offset + 8 + size <= len(raw), 'Truncated GLB chunk'
    chunks.append((kind, raw[offset + 8:offset + 8 + size]))
    offset += size + 8
assert offset == len(raw)
document = json.loads(next(data for kind, data in chunks if kind == 0x4E4F534A))
binary = next(data for kind, data in chunks if kind == 0x004E4942)
external = [b.get('uri') for b in document.get('buffers', []) if b.get('uri')]
external += [i.get('uri') for i in document.get('images', []) if i.get('uri') and not i['uri'].startswith('data:')]
for view in document.get('bufferViews', []):
    assert view.get('buffer', 0) == 0
    assert view.get('byteOffset', 0) + view['byteLength'] <= len(binary), 'Out-of-range buffer view'
images = []
for i, item in enumerate(document.get('images', [])):
    view = document['bufferViews'][item['bufferView']] if 'bufferView' in item else None
    data = binary[view.get('byteOffset', 0):view.get('byteOffset', 0) + view['byteLength']] if view else b''
    images.append({'index': i, 'name': item.get('name'), 'mimeType': item.get('mimeType'),
                   'size': image_size(data), 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
meshes = []
for mesh in document.get('meshes', []):
    primitives = []
    for p in mesh['primitives']:
        position = document['accessors'][p['attributes']['POSITION']]
        count = document['accessors'][p['indices']]['count'] if 'indices' in p else position['count']
        mode = p.get('mode', 4)
        triangles = count // 3 if mode == 4 else max(0, count - 2) if mode in (5, 6) else 0
        primitives.append({'vertices': position['count'], 'triangles': triangles, 'material': p.get('material'),
                           'mode': mode, 'attributes': list(p['attributes']), 'min': position.get('min'), 'max': position.get('max')})
    meshes.append({'name': mesh.get('name'), 'primitives': primitives})
report = {'source': str(args.source), 'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest(),
          'valid_glb_2': True, 'external_references': external, 'asset': document.get('asset'),
          'extensions_used': document.get('extensionsUsed', []), 'images': images, 'meshes': meshes,
          'triangles': sum(p['triangles'] for m in meshes for p in m['primitives']),
          'materials': document.get('materials', []), 'nodes': document.get('nodes', []),
          'skins': [{'name': s.get('name'), 'joints': len(s['joints'])} for s in document.get('skins', [])],
          'animations': [{'name': a.get('name'), 'channels': len(a['channels'])} for a in document.get('animations', [])]}
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({k: report[k] for k in ('bytes', 'sha256', 'valid_glb_2', 'external_references', 'triangles', 'skins', 'animations')}, ensure_ascii=False))
print('MATERIALS', len(report['materials']), 'IMAGES', len(images), 'SIZES', sorted({str(i['size']) for i in images}))
print('REPORT', args.report)

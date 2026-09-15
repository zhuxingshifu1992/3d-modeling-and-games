"""Build 26 camera-only building AABBs from the original, read-only scene.

Run from any directory with Blender (no GLB export or source .blend save):
    blender --background --factory-startup --disable-autoexec --python export_camera_occluders.py
Add ``-- --check`` to verify the committed JSON without writing it.

The authored parent groups distinguish individual buildings from islands,
quays, water, bridges, boats, trees, and street furniture. Bounds combine all
evaluated mesh/curve vertices below each building parent in world space.
Runtime camera clearance is intentionally not baked into this data.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy


ROOT = Path(__file__).resolve().parents[1]
CATEGORIZED_SOURCE = ROOT.parent.parent / "建模" / "威尼斯水城" / "威尼斯水城.blend"
LEGACY_SOURCE = ROOT.parent / "威尼斯水城" / "威尼斯水城.blend"
SOURCE = CATEGORIZED_SOURCE if CATEGORIZED_SOURCE.is_file() else LEGACY_SOURCE
OUTPUT = ROOT / "assets" / "camera_occluders.json"
BUILDING_NAMES = tuple(f"House {index:02d}" for index in range(1, 24)) + (
    "Basilica of the lagoon",
    "Piazza campanile",
    "Canal-side palazzo",
)
BUILDING_COLLECTIONS = {
    "03 • Venetian houses",
    "04 • Basilica, campanile & palazzo",
}
PRECISION = 100_000


def descendants(root):
    pending = list(root.children)
    while pending:
        child = pending.pop()
        yield child
        pending.extend(child.children)


def world_bounds(root, depsgraph):
    low = [math.inf] * 3
    high = [-math.inf] * 3
    vertex_count = 0
    for child in sorted(descendants(root), key=lambda item: item.name):
        if child.type not in {"MESH", "CURVE"}:
            continue
        assert any(collection.name in BUILDING_COLLECTIONS for collection in child.users_collection), child.name
        evaluated = child.evaluated_get(depsgraph)
        geometry = evaluated.to_mesh()
        try:
            if geometry is None:
                continue
            for vertex in geometry.vertices:
                point = evaluated.matrix_world @ vertex.co
                godot = (point.x, point.z, -point.y)
                for axis, value in enumerate(godot):
                    assert math.isfinite(value), (child.name, value)
                    low[axis] = min(low[axis], value)
                    high[axis] = max(high[axis], value)
                vertex_count += 1
        finally:
            evaluated.to_mesh_clear()
    assert vertex_count > 0, root.name
    # Round outwards so serialization never shrinks the source bounds.
    low = [math.floor(value * PRECISION) / PRECISION for value in low]
    high = [math.ceil(value * PRECISION) / PRECISION for value in high]
    assert all(a < b for a, b in zip(low, high)), (root.name, low, high)
    assert high[1] - low[1] > 5.0, (root.name, "not a tall obstacle")
    assert high[0] - low[0] < 20.0 and high[2] - low[2] < 20.0, (root.name, "unexpectedly broad obstacle")
    return {"name": root.name, "min": low, "max": high}


def build_document():
    original_hash = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    original_stat = SOURCE.stat()
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE), load_ui=False)
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    roots = [
        item for item in bpy.context.scene.objects
        if item.type == "EMPTY" and any(
            collection.name in BUILDING_COLLECTIONS for collection in item.users_collection
        )
    ]
    assert {item.name for item in roots} == set(BUILDING_NAMES), [item.name for item in roots]
    assert all(item.parent is None for item in roots), "Building groups must be world roots"
    depsgraph = bpy.context.evaluated_depsgraph_get()
    by_name = {item.name: item for item in roots}
    boxes = [world_bounds(by_name[name], depsgraph) for name in BUILDING_NAMES]
    assert len(boxes) == 26
    # The source is never saved; verify both bytes and filesystem timestamp.
    assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == original_hash
    assert SOURCE.stat().st_mtime_ns == original_stat.st_mtime_ns
    return {
        "schema_version": 1,
        "source": "威尼斯水城/威尼斯水城.blend",
        "source_sha256": original_hash,
        "axis_conversion": "Blender (x,y,z) -> Godot (x,z,-y)",
        "bounds_method": "Union of evaluated mesh and curve vertices below each authored building parent, in world space",
        "padding": 0.0,
        "boxes": boxes,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Recompute and compare; do not write any file")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    document = build_document()
    if args.check:
        assert json.loads(OUTPUT.read_text(encoding="utf-8")) == document, "Camera occluder JSON differs from source"
        print(f"PASS: {len(document['boxes'])} building bounds reproduce exactly; source unchanged", flush=True)
    else:
        OUTPUT.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"Wrote {OUTPUT}: {len(document['boxes'])} building bounds; source unchanged", flush=True)
    for box in document["boxes"]:
        print(f"  {box['name']}: {box['min']} -> {box['max']}", flush=True)


if __name__ == "__main__":
    main()

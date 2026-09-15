"""Blender-side regression: the shared house must have a real traversable entry."""
import sys,unittest,importlib.util
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'/'model'))

class InteriorsTest(unittest.TestCase):
    def test_real_doorway_and_catalog(self):
        self.assertTrue((ROOT/'tools'/'model'/'interiors.py').exists(),'Missing enterable-building generator')
        import bpy
        from geometry import Builder,PALETTE
        from interiors import make_building
        from mathutils.bvhtree import BVHTree
        from mathutils import Vector
        bpy.ops.wm.read_factory_settings(use_empty=True)
        mats={}
        for n in PALETTE:mats[n]=bpy.data.materials.new(n)
        col=bpy.data.collections.new('Test');bpy.context.scene.collection.children.link(col)
        B=Builder(col,mats)
        spec=make_building(B,'test_house','Test',0,0,12,12,0,9,'french',floors=3)
        obs=B.finish()
        verts=[];faces=[]
        for o in obs:
            if not o.name.startswith('COL_'):continue
            offset=len(verts);verts.extend(v.co[:] for v in o.data.vertices);faces.extend(tuple(offset+i for i in p.vertices) for p in o.data.polygons)
        tree=BVHTree.FromPolygons(verts,faces)
        # Chest-height path must remain empty across the door and front hall.
        hit=tree.ray_cast(Vector((0,-8,1.5)),Vector((0,1,0)),5)[0]
        self.assertIsNone(hit,'Solid geometry blocks the entrance')
        self.assertEqual(len(B.buildings),1);self.assertEqual(spec['floors'],3)
        self.assertTrue(any('Furniture' in o.name for o in obs))
        self.assertTrue(any('Stair' in o.name for o in obs))
        self.assertEqual(len(spec['floor_levels']),3)
        sloped_faces=0
        for o in obs:
            if not o.name.startswith('COL_') or 'Stairs' not in o.name:continue
            for p in o.data.polygons:
                if .01<abs(p.normal.z)<.99:
                    sloped_faces+=1
                    self.assertGreater(p.normal.z,0,'Both stair collision slopes must face upward for engine backface culling')
        self.assertEqual(sloped_faces,4)

suite=unittest.defaultTestLoader.loadTestsFromTestCase(InteriorsTest)
result=unittest.TextTestRunner(verbosity=2).run(suite)
if not result.wasSuccessful():raise SystemExit(1)

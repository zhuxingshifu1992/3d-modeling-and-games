from pathlib import Path
BASE=Path(__file__).resolve().parents[1]
code=(BASE/'tools/rider_build.py').read_text().split('for obj in [body,tee,shorts,shoes]:')[0]
exec(code)
for obj in [tee,shorts]:
    bm=bmesh.new();bm.from_mesh(obj.data)
    pending=set(v for v in bm.verts if v.is_boundary)
    while pending:
        v=pending.pop();stack=[v];part=[v]
        while stack:
            for e in stack.pop().link_edges:
                if not e.is_boundary:continue
                for nv in e.verts:
                    if nv in pending:pending.remove(nv);stack.append(nv);part.append(nv)
        co=np.array([list(v.co) for v in part]);print('BOUNDARY',obj.name,len(part),co.min(axis=0).tolist(),co.max(axis=0).tolist())
    bm.free()

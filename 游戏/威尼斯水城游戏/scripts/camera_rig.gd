extends RefCounted

## Lightweight line-of-sight against architectural AABBs, not city triangle physics.
static func load_boxes(path: String) -> Array[AABB]:
	var boxes: Array[AABB] = []
	if not FileAccess.file_exists(path): return boxes
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary: return boxes
	for entry: Dictionary in data.get("boxes",[]):
		var lo: Array = entry.get("min",[])
		var hi: Array = entry.get("max",[])
		if lo.size()!=3 or hi.size()!=3: continue
		var origin := Vector3(float(lo[0]),float(lo[1]),float(lo[2]))
		var end := Vector3(float(hi[0]),float(hi[1]),float(hi[2]))
		if origin.is_finite() and end.is_finite():
			boxes.append(AABB(origin,end-origin))
	return boxes

static func line_clear(from: Vector3,to: Vector3,boxes: Array[AABB]) -> bool:
	var direction := to-from
	for source: AABB in boxes:
		var box: AABB = source.grow(0.25)
		var near_t: float = 0.0
		var far_t: float = 1.0
		var intersects: bool = true
		for axis: int in range(3):
			if absf(direction[axis]) < 0.000001:
				if from[axis] < box.position[axis] or from[axis] > box.end[axis]:
					intersects = false
					break
			else:
				var a: float = (box.position[axis]-from[axis])/direction[axis]
				var b: float = (box.end[axis]-from[axis])/direction[axis]
				near_t = maxf(near_t,minf(a,b))
				far_t = minf(far_t,maxf(a,b))
				if near_t > far_t:
					intersects = false
					break
		if intersects: return false
	return true

static func safe_follow(focus: Vector3,desired: Vector3,boxes: Array[AABB]) -> Vector3:
	if line_clear(focus,desired,boxes): return desired
	var offset: Vector3 = desired-focus
	var height: float = maxf(18.0,offset.y)
	# Lift and tighten the orbit while retaining eye-to-boat visibility. Only
	# move back out gradually in the caller; never interpolate through a facade.
	for scale_horizontal: float in [1.0,0.75,0.5,0.25,0.1,0.0]:
		var candidate := focus+Vector3(offset.x*scale_horizontal,height,offset.z*scale_horizontal)
		if line_clear(focus,candidate,boxes): return candidate
	return focus+Vector3(0,maxf(32.0,height),0)

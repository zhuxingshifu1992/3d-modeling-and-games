extends Control

var regions: Array = []
var landmarks: Array = []
var collected: Array[String] = []
var traveler: Vector3 = Vector3.ZERO
var heading: float = 0.0
var region_colors: Array[Color] = [Color("b8c4b6"), Color("d6c7ad"), Color("b7c8ce"), Color("bec5ac")]

func _ready() -> void:
	custom_minimum_size = Vector2(500, 460)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func project(point: Vector3) -> Vector2:
	var usable: Vector2 = size - Vector2(44, 60)
	var scale: float = minf(usable.x / 400.0, usable.y / 360.0)
	return Vector2(size.x / 2.0 + point.x * scale, size.y / 2.0 + point.z * scale)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("efece2"))
	var font: Font = get_theme_default_font()
	for x: int in range(0, int(size.x), 32):
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.7, 0.72, 0.68, 0.17))
	for y: int in range(0, int(size.y), 32):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.7, 0.72, 0.68, 0.17))
	var center: Vector2 = project(Vector3.ZERO)
	draw_line(Vector2(22, center.y), Vector2(size.x - 22, center.y), Color("c7bba6"), 9)
	draw_line(Vector2(center.x, 30), Vector2(center.x, size.y - 24), Color("c7bba6"), 9)
	for i: int in range(regions.size()):
		var region: Dictionary = regions[i]
		var p: Array = region.get("position", [0, 0, 0])
		var world: Vector3 = Vector3(float(p[0]), float(p[1]), float(p[2]))
		var area: Vector2 = Vector2(140, 120)
		var top: Vector2 = project(world - Vector3(area.x / 2, 0, area.y / 2))
		var bottom: Vector2 = project(world + Vector3(area.x / 2, 0, area.y / 2))
		draw_style_box(_region_style(region_colors[i % region_colors.size()]), Rect2(top, bottom - top))
		draw_string(font, top + Vector2(12, 26), str(region.get("name", region.get("id", ""))), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("273d3d"))
		var station: Array = region.get("spawn", p)
		var at: Vector2 = project(Vector3(float(station[0]), float(station[1]), float(station[2])))
		draw_rect(Rect2(at - Vector2(4, 4), Vector2(8, 8)), Color("354e4d"))
	for landmark: Dictionary in landmarks:
		var p: Array = landmark.get("position", [0, 0, 0])
		var at: Vector2 = project(Vector3(float(p[0]), float(p[1]), float(p[2])))
		var earned: bool = str(landmark.get("id", "")) in collected
		draw_circle(at, 6, Color("bd8544") if earned else Color("f8f4e8"))
		draw_arc(at, 7, 0, TAU, 24, Color("785c36"), 1.5)
	var at: Vector2 = project(traveler)
	draw_circle(at, 10, Color(1, 1, 1, 0.65))
	var triangle: PackedVector2Array = PackedVector2Array([Vector2(0, -9), Vector2(6, 6), Vector2(-6, 6)])
	for i: int in range(triangle.size()):
		triangle[i] = triangle[i].rotated(-heading) + at
	draw_colored_polygon(triangle, Color("183f47"))
	draw_string(font, Vector2(18, size.y - 15), "▲ 当前位置    □ 车站    ○ 地标 / 金色为已盖章", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("4b625e"))
	draw_string(font, Vector2(size.x - 40, 23), "北", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("34524f"))

func _region_style(color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 9
	style.corner_radius_top_right = 9
	style.corner_radius_bottom_left = 9
	style.corner_radius_bottom_right = 9
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.2, 0.3, 0.27, 0.25)
	return style

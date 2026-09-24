extends RefCounted

static func machines() -> Array[Dictionary]:
	var rows := [
		["rx78", "RX-78-2", "元祖高达", 18.0, "头顶高", Color("e6b74b"), "A1", -22.0, 30.0, -PI / 2.0, "经典三色装甲 · 核心区块", "UC 0079"],
		["unicorn", "RX-0", "独角兽高达", 21.7, "全高 · 毁灭模式", Color("ff5869"), "A2", -22.0, 0.0, -PI / 2.0, "毁灭模式 · 精神感应框架", "UC 0096"],
		["nu", "RX-93", "ν 高达", 22.0, "头顶高", Color("86bbde"), "A3", -22.0, -30.0, -PI / 2.0, "双侧浮游炮 · 作者改型", "UC 0093"],
		["freedom", "ZGMF-X20A", "强袭自由高达", 18.88, "本体全高", Color("69a7ff"), "B1", 22.0, 30.0, PI / 2.0, "金色骨架 · 超级龙骑兵", "CE 73"],
		["wing", "XXXG-00W0", "飞翼零式 EW", 16.7, "机体高度", Color("b9dfd7"), "B2", 22.0, 0.0, PI / 2.0, "羽翼式背包 · ZERO SYSTEM", "AC 195"],
		["exia", "GN-001", "能天使高达", 18.3, "全高", Color("5dd5bc"), "B3", 22.0, -30.0, PI / 2.0, "PG 造型 · 无手持武器整备", "AD 2307"]
	]
	var result: Array[Dictionary] = []
	for row in rows:
		result.append({"id": row[0], "model": row[1], "name": row[2], "height": row[3], "height_note": row[4], "color": row[5], "bay": row[6], "position": Vector3(row[7], 0, row[8]), "yaw": row[9], "feature": row[10], "era": row[11], "model_path": "res://assets/models/" + row[0] + ".glb"})
	result[0].model_path = "res://assets/models/rx78_refined.glb"
	result[0]["refined"] = true
	result[0]["cockpit"] = {"floor_y": 12.65, "portal_z": -2.50, "interior_front_z": -1.45,
		"rear_z": 0.40, "seat_offset_z": -0.90, "screen_z": -1.25, "wait_z": -5.20, "gate_z": -4.80,
		"hatch_travel": 0.55, "hatch_angle": 90.0}
	result[1].model_path = "res://assets/models/unicorn_refined.glb"
	result[1]["refined"] = true
	result[1]["service_person_x"] = -7.0
	result[1]["cockpit"] = {"floor_y": 15.25, "portal_z": -2.45, "bridge_end_z": -4.87, "interior_front_z": -0.88,
		"rear_z": 1.05, "seat_offset_z": -0.18, "screen_z": -0.50, "wait_z": -5.23, "gate_z": -4.87,
		"console_offset_z": 0.30, "console_x": 0.48, "screen_side_x": 0.35,
		"screen_fold_yaw_zero": true, "screen_fold_height": 1.96,
		"hatch_travel": 1.35, "hatch_angle": 90.0, "docking_width": 0.73, "entry_half_width": 0.06,
		"head_clearance_min_y": 18.55, "head_clearance_max_y": 21.75, "head_clearance_half_width": 1.90,
		"head_clearance_min_z": -1.65, "head_clearance_max_z": 1.65,
		"clearance_entry_min_z": -2.30, "clearance_entry_max_z": -0.90}
	result[2].model_path = "res://assets/models/nu_refined.glb"
	result[2]["refined"] = true
	result[2]["cockpit"] = {"floor_y": 16.04, "portal_z": -3.35, "interior_front_z": -1.45,
		"rear_z": 0.55, "seat_offset_z": -0.60, "screen_z": -1.10, "wait_z": -6.10, "gate_z": -5.70,
		"console_offset_z": 0.15, "console_x": 0.48, "screen_side_x": 0.35, "screen_fold_yaw_zero": true, "screen_fold_height": 1.96,
		"hatch_travel": 0.15, "hatch_angle": 120.0, "docking_width": 0.73, "entry_half_width": 0.06,
		"head_clearance_min_y": 18.45, "head_clearance_max_y": 23.0, "head_clearance_half_width": 2.0,
		"head_clearance_min_z": -4.5, "head_clearance_max_z": 2.5,
		"clearance_entry_min_z": -3.0, "clearance_entry_max_z": -1.50}
	result[5].model_path = "res://assets/models/exia_refined.glb"
	result[5]["refined"] = true
	result[5]["cockpit"] = {"floor_y": 12.08, "portal_z": -2.30, "bridge_end_z": -4.70, "interior_front_z": -0.85,
		"rear_z": 1.0, "seat_offset_z": -0.18, "screen_z": -0.45, "wait_z": -5.05, "gate_z": -4.70,
		"console_offset_z": 0.30, "console_x": 0.48, "screen_side_x": 0.35,
		"screen_fold_yaw_zero": true, "screen_fold_height": 1.96,
		"hatch_travel": 1.30, "hatch_angle": -100.0, "docking_width": 0.73, "entry_half_width": 0.06,
		"head_clearance_min_y": 15.74, "head_clearance_max_y": 18.35, "head_clearance_half_width": 1.7,
		"head_clearance_min_z": -1.70, "head_clearance_max_z": 1.20,
		"clearance_entry_min_z": -2.0, "clearance_entry_max_z": -0.90}
	result[3].model_path = "res://assets/models/freedom_refined.glb"
	result[3]["refined"] = true
	result[3]["work_fixture_z"] = 5.90
	result[3]["cockpit"] = {"floor_y": 13.75, "portal_z": -3.12, "bridge_end_z": -5.40, "interior_front_z": -0.88,
		"rear_z": 1.05, "seat_offset_z": -0.18, "screen_z": -0.50, "wait_z": -5.76, "gate_z": -5.40,
		"console_offset_z": 0.30, "console_x": 0.48, "screen_side_x": 0.35,
		"screen_fold_yaw_zero": true, "screen_fold_height": 1.96,
		"hatch_travel": 1.40, "hatch_angle": 90.0, "docking_width": 0.73, "entry_half_width": 0.06,
		"head_clearance_min_y": 15.95, "head_clearance_max_y": 18.90, "head_clearance_half_width": 1.70,
		"head_clearance_min_z": -1.35, "head_clearance_max_z": 1.15,
		"clearance_entry_min_z": -2.90, "clearance_entry_max_z": -0.90}
	# Public snapshot: use the project-authored procedural Wing model.
	# The downloaded refined Wing asset is excluded due to unresolved provenance.
	return result

static func exhibits() -> Array[Dictionary]:
	# Author's desert variant; display height is provisional, not an official specification.
	return [{"id": "zaku_desert", "model": "ZAKU / DESERT CUSTOM", "name": "沙漠扎古", "height": 17.5,
		"position": Vector3(0, 0, -38.0), "yaw": PI,
		"model_path": "res://assets/models/zaku_desert_refined.glb"}]

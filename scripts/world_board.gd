class_name WorldBoard
extends Control

signal selected(id: String)
var definition: Dictionary = {}
var positions: Array[String] = []
var reachable: Array = []
var local: bool = false
var map_texture: Texture2D
var nodes: Array = []
var roads: Array = []
var markers: Array[Button] = []
var map_rect := Rect2()

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	var path := String(definition.get("image", ""))
	if ResourceLoader.exists(path):
		map_texture = load(path)
	nodes = definition.get("nodes", [])
	roads = definition.get("roads", [])
	for entry: Dictionary in nodes:
		var id := String(entry.get("id", entry.get("name", "")))
		var label := String(entry.get("label", id)).replace("_", " ")
		var button := Button.new()
		button.text = ""
		button.tooltip_text = label + (" · G1" if positions.size() > 0 and id == positions[0] else "") + (" · G2" if positions.size() > 1 and id == positions[1] else "")
		button.add_theme_font_size_override("font_size", 13 if not local else 10)
		var tint := ArkUI.MINT if id in reachable else ArkUI.EDGE
		if id in positions:
			tint = ArkUI.GOLD
		button.add_theme_stylebox_override("normal", ArkUI.box(Color(0.03, 0.12, 0.16, 0.95), 12, tint))
		var compact: StyleBoxFlat = button.get_theme_stylebox("normal").duplicate()
		compact.content_margin_left = 0
		compact.content_margin_right = 0
		compact.content_margin_top = 0
		compact.content_margin_bottom = 0
		button.add_theme_stylebox_override("normal", compact)
		for state_name: String in ["hover", "pressed", "focus"]:
			var state_style := compact.duplicate() as StyleBoxFlat
			state_style.border_color = ArkUI.GOLD
			button.add_theme_stylebox_override(state_name, state_style)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.pressed.connect(func() -> void: selected.emit(id))
		add_child(button)
		markers.append(button)
		if id in positions:
			var who := ""
			for player_index in positions.size():
				if positions[player_index] == id: who += (" / " if not who.is_empty() else "") + "G%d" % (player_index + 1)
			var badge := ArkUI.label(who, 13, ArkUI.GOLD)
			badge.name = "PositionBadge%d" % index_of(id)
			button.add_child(badge)
			badge.position = Vector2(14, -19)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	map_rect = Rect2(Vector2.ZERO, size)
	if map_texture:
		var source := Vector2(map_texture.get_size())
		var factor := minf(size.x / source.x, size.y / source.y)
		map_rect.size = source * factor
		map_rect.position = (size - map_rect.size) * 0.5
	for index in markers.size():
		var node: Dictionary = nodes[index]
		var point := map_rect.position + Vector2(float(node.get("x", 50)), float(node.get("y", 50))) * map_rect.size / 100.0
		var dimensions := Vector2(16, 16) if local else Vector2(18, 18)
		markers[index].size = dimensions
		markers[index].position = point - dimensions * 0.5
	queue_redraw()

func index_of(id: String) -> int:
	for index in nodes.size():
		if String(nodes[index].get("id", "")) == id: return index
	return 0

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("06131c"))
	if map_texture:
		draw_texture_rect(map_texture, map_rect, false, Color(0.8, 0.86, 0.85))
	var lookup: Dictionary = {}
	for node: Dictionary in nodes:
		lookup[String(node.get("id", ""))] = Vector2(float(node.get("x", 50)), float(node.get("y", 50)))
	for road: Variant in roads:
		var from: String
		var to: String
		var bends: Array = []
		if road is Array:
			from = String(road[0]); to = String(road[1])
		else:
			from = String(road.get("from", "")); to = String(road.get("to", ""))
			bends = road.get("points", [])
		if not lookup.has(from) or not lookup.has(to):
			continue
		var points := PackedVector2Array()
		points.append(lookup[from])
		for bend: Dictionary in bends:
			points.append(Vector2(float(bend.x), float(bend.y)))
		points.append(lookup[to])
		for index in range(points.size() - 1):
			var start := map_rect.position + points[index] * map_rect.size / 100.0
			var end := map_rect.position + points[index + 1] * map_rect.size / 100.0
			draw_line(start, end, Color(0.02, 0.04, 0.06, 0.8), 5.0, true)
			draw_line(start, end, Color(0.9, 0.77, 0.5, 0.65), 2.0, true)

class_name WorldBoard
extends Control

signal selected(id: String)
var definition: Dictionary = {}
var positions: Array[String] = []
var reachable: Array = []
var local: bool = false
var active_player: int = 0
var map_texture: Texture2D
var nodes: Array = []
var roads: Array = []
var markers: Array[Button] = []
var avatars: Array[Control] = []
var map_rect := Rect2()
var road_layouts: Dictionary = {}
var road_opacity: float = 0.42

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	var path: String = str(definition.get("image", ""))
	if ResourceLoader.exists(path): map_texture = load(path)
	nodes = definition.get("nodes", []).duplicate(true)
	roads = definition.get("roads", [])
	if local and active_player >= 0 and active_player < positions.size():
		var current: String = positions[active_player]
		for road: Dictionary in roads:
			var from: String = str(road.get("from", ""))
			var to: String = str(road.get("to", ""))
			var destination: String = to if from == current else (from if to == current else "")
			if not destination.is_empty() and destination not in reachable:
				reachable.append(destination)
	if not local:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/site_theme.json"))
		if parsed is Dictionary:
			var layouts: Dictionary = parsed.get("layouts", {})
			var authored: Dictionary = layouts.get("mainMapNodes", {})
			road_layouts = layouts.get("mainMapRoads", {})
			road_opacity = float(parsed.get("ui", {}).get("mainMapRoadOpacity", 0.42))
			for node: Dictionary in nodes:
				if authored.has(str(node.id)):
					node.x = authored[str(node.id)].x
					node.y = authored[str(node.id)].y
	for entry: Dictionary in nodes:
		var id: String = str(entry.get("id", ""))
		var marker := Button.new()
		marker.text = ""
		marker.tooltip_text = str(entry.get("label", id)).replace("_", " ")
		marker.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
			marker.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		marker.pressed.connect(func() -> void: selected.emit(id))
		add_child(marker)
		markers.append(marker)
		if local:
			var dot := ColorRect.new()
			dot.color = Color(1, 1, 1, 0.85) if id not in positions else Color("7dd3fc")
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			dot.position = Vector2(5, 5)
			dot.size = Vector2(6, 6)
			marker.add_child(dot)
		else:
			var kind: String = str(entry.get("tipo", "citta"))
			var icon_name: String = "start_location" if id == "Pordenone" else ("route" if kind == "percorso" else ("countries" if kind == "villaggio" else "cities"))
			var icon := ArkUI.texture("res://assets/ui/original/%s.png" % icon_name)
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			marker.add_child(icon)
			ArkUI.fill(icon)
			var label := ArkUI.label(id.replace("_", " ").replace("ReggioCalabria", "Reggio Calabria"), 10, Color.WHITE)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.add_theme_color_override("font_shadow_color", Color.BLACK)
			label.add_theme_constant_override("shadow_offset_x", 1)
			label.add_theme_constant_override("shadow_offset_y", 1)
			label.position = Vector2(-69, 23)
			label.size = Vector2(160, 17)
			marker.add_child(label)
	for player_index in positions.size():
		var avatar := Control.new()
		avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		avatar.modulate.a = 1.0 if player_index == active_player else 0.8
		add_child(avatar)
		var art := ArkUI.texture("res://assets/ui/original/player%d.png" % (player_index + 1))
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		avatar.add_child(art)
		ArkUI.fill(art)
		var badge := ArkUI.label("G%d" % (player_index + 1), 10, Color.WHITE)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.position = Vector2(20, 57)
		badge.size = Vector2(30, 16)
		badge.add_theme_color_override("font_shadow_color", Color("9f1239") if player_index == 0 else Color("0369a1"))
		badge.add_theme_constant_override("shadow_outline_size", 4)
		avatar.add_child(badge)
		avatars.append(avatar)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	map_rect = Rect2(Vector2.ZERO, size)
	for index in markers.size():
		var node: Dictionary = nodes[index]
		var point := Vector2(float(node.get("x", 50)), float(node.get("y", 50))) * size / 100.0
		var side: float = 16.0 if local or str(node.get("tipo", "")) == "percorso" and str(node.id) != "Pordenone" else 22.4
		markers[index].size = Vector2.ONE * side
		markers[index].position = point - Vector2.ONE * side * 0.5
	for index in avatars.size():
		var found: bool = false
		for node: Dictionary in nodes:
			if str(node.id) != positions[index]: continue
			var same: bool = positions.size() > 1 and positions[0] == positions[1]
			var offset: float = (-44.0 if index == 0 else -12.0) if same else -27.0
			avatars[index].position = Vector2(float(node.x), float(node.y)) * size / 100.0 + Vector2(offset, -81.0)
			avatars[index].size = Vector2(72, 72)
			found = true
			break
		avatars[index].visible = found
	queue_redraw()

func index_of(id: String) -> int:
	for index in nodes.size():
		if str(nodes[index].get("id", "")) == id: return index
	return 0

func _draw() -> void:
	if map_texture:
		var texture_size: Vector2 = map_texture.get_size()
		var scale_factor: float = maxf(size.x / texture_size.x, size.y / texture_size.y)
		var drawn: Vector2 = texture_size * scale_factor
		draw_texture_rect(map_texture, Rect2((size - drawn) * 0.5, drawn), false)
	if not local: draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.2))
	var lookup: Dictionary = {}
	for node: Dictionary in nodes: lookup[str(node.id)] = Vector2(float(node.x), float(node.y))
	for road: Variant in roads:
		var from: String = str(road[0]) if road is Array else str(road.get("from", ""))
		var to: String = str(road[1]) if road is Array else str(road.get("to", ""))
		if not lookup.has(from) or not lookup.has(to): continue
		var bends: Array = road.get("points", []) if road is Dictionary else []
		var authored: Array = road_layouts.get(from + "__" + to, [])
		var points: Array[Vector2] = [lookup[from]]
		if authored.size() >= 2:
			for index in range(1, authored.size() - 1): points.append(Vector2(float(authored[index].x), float(authored[index].y)))
		else:
			for bend: Dictionary in bends: points.append(Vector2(float(bend.x), float(bend.y)))
		points.append(lookup[to])
		var pixels := PackedVector2Array()
		for index in points.size():
			var point: Vector2 = points[index] * size / 100.0
			if not local and index > 0:
				var previous: Vector2 = points[index - 1] * size / 100.0
				if absf(previous.x - point.x) > 0.1 and absf(previous.y - point.y) > 0.1:
					pixels.append(Vector2(point.x, previous.y))
			pixels.append(point)
		if pixels.size() >= 2:
			draw_polyline(pixels, Color(0, 0, 0, 0.92), 3.0 if local else 14.0, true)
			draw_polyline(pixels, Color(0.9, 0.9, 0.9, road_opacity), 1.5 if local else 10.0, true)
	var current: String = positions[active_player] if active_player >= 0 and active_player < positions.size() else ""
	for node: Dictionary in nodes:
		var id: String = str(node.get("id", ""))
		if id != current and id not in reachable:
			continue
		var point := Vector2(float(node.get("x", 50)), float(node.get("y", 50))) * size / 100.0
		var radius: float = 13.0 if local else (15.0 if str(node.get("tipo", "")) == "percorso" else 18.0)
		var color: Color = Color("7dd3fc") if id == current else Color("bef264")
		draw_circle(point, radius + 3.0, Color(color, 0.17), true)
		draw_arc(point, radius, 0.0, TAU, 48, Color(0, 0, 0, 0.85), 4.0, true)
		draw_arc(point, radius, 0.0, TAU, 48, color, 2.0, true)

class_name MapBoard
extends Control

signal stop_selected(index: int)

const POINTS := [Vector2(0.13, 0.74), Vector2(0.32, 0.50), Vector2(0.49, 0.66), Vector2(0.67, 0.36), Vector2(0.85, 0.53)]
const NAMES := ["Laboratorio", "Prato dei sussurri", "Sorgente", "Bosco di cenere", "La radura"]
var progress: int = 0
var buttons: Array[Button] = []

func _ready() -> void:
	clip_contents = true
	var background := ArkUI.texture("res://assets/backgrounds/route_1.webp")
	add_child(background)
	ArkUI.fill(background)
	background.modulate = Color(0.55, 0.68, 0.68)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.08, 0.1, 0.3)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	ArkUI.fill(dim)
	var lines := Control.new()
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lines)
	lines.draw.connect(_draw_route.bind(lines))
	for index in POINTS.size():
		var node := ArkUI.button(str(index + 1), func() -> void: stop_selected.emit(index))
		node.custom_minimum_size = Vector2(58, 58)
		node.size = Vector2(58, 58)
		node.tooltip_text = NAMES[index]
		node.disabled = index > progress + 1
		if index <= progress:
			node.add_theme_stylebox_override("normal", ArkUI.box(Color("245347"), 28, ArkUI.MINT))
		else:
			node.add_theme_stylebox_override("normal", ArkUI.box(ArkUI.INK, 28, ArkUI.GOLD))
		add_child(node)
		buttons.append(node)
		var name_label := ArkUI.label(NAMES[index], 17)
		name_label.name = "StopLabel%d" % index
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_color_override("font_shadow_color", Color.BLACK)
		name_label.add_theme_constant_override("shadow_offset_x", 2)
		name_label.add_theme_constant_override("shadow_offset_y", 2)
		add_child(name_label)
	resized.connect(func() -> void: _layout(); lines.queue_redraw())
	_layout()

func _layout() -> void:
	for index in buttons.size():
		var point: Vector2 = POINTS[index] * size
		buttons[index].position = point - Vector2(29, 29)
		var name_label := get_node("StopLabel%d" % index) as Label
		name_label.position = point + Vector2(-90, 38)
		name_label.size.x = 180

func _draw_route(target: Control) -> void:
	for index in range(POINTS.size() - 1):
		var start: Vector2 = POINTS[index] * size
		var finish: Vector2 = POINTS[index + 1] * size
		target.draw_line(start, finish, Color(0.02, 0.07, 0.09, 0.6), 13, true)
		target.draw_dashed_line(start, finish, ArkUI.MINT if index < progress else ArkUI.GOLD, 4, 10, true)

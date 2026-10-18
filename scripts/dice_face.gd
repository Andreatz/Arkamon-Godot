class_name DiceFace
extends Control

var value: int = 1
var tint: Color = ArkUI.MINT

func _ready() -> void:
	custom_minimum_size = Vector2(42, 42)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	draw_style_box(ArkUI.box(Color("16323c"), 9, tint), Rect2(Vector2.ZERO, size))
	var pips: Array[Vector2] = []
	if value % 2 == 1:
		pips.append(Vector2(0.5, 0.5))
	if value >= 2:
		pips.append_array([Vector2(0.27, 0.27), Vector2(0.73, 0.73)])
	if value >= 4:
		pips.append_array([Vector2(0.73, 0.27), Vector2(0.27, 0.73)])
	if value == 6:
		pips.append_array([Vector2(0.27, 0.5), Vector2(0.73, 0.5)])
	for pip in pips:
		draw_circle(pip * size, 3.0, tint, true, -1, true)

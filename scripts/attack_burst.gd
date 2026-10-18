extends Control

var progress: float = 0.0
var tint: Color = Color.WHITE

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween := create_tween()
	tween.tween_property(self, "progress", 1.0, 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(queue_free)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var color := Color(tint, 1.0 - progress)
	var center := size * 0.5
	draw_arc(center, 15 + progress * 85, 0.0, TAU, 48, color, 5.0, true)
	for index in 12:
		var vector := Vector2.from_angle(TAU * float(index) / 12)
		draw_line(center + vector * (10 + progress * 50), center + vector * (30 + progress * 100), color, 4.0, true)

class_name CreatureActor
extends Control

var image: TextureRect
var floating: Tween
var animated: bool = true
var base_position := Vector2.ZERO
var atlas: AtlasTexture
var animation: Dictionary = {}
var elapsed: float = 0.0
var current_frame: int = -1
static var animation_catalogue: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	image = TextureRect.new()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(image)
	resized.connect(_layout)
	_layout()

func setup(species_id: int, face_left: bool = false, motion: bool = true) -> void:
	animated = motion
	var path := "res://assets/creatures/%d.png" % species_id
	if ResourceLoader.exists(path):
		image.texture = load(path)
	_load_idle(species_id)
	image.flip_h = face_left
	_layout()
	_idle()

func _load_idle(species_id: int) -> void:
	atlas = null
	animation = {}
	elapsed = 0.0
	current_frame = -1
	if animation_catalogue.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/animations.json"))
		if parsed is Dictionary:
			animation_catalogue = parsed.get("idle", {})
	if not animated or not animation_catalogue.has(str(species_id)):
		return
	animation = animation_catalogue[str(species_id)]
	if not ResourceLoader.exists(String(animation.texture)):
		animation = {}
		return
	atlas = AtlasTexture.new()
	atlas.atlas = load(String(animation.texture))
	atlas.filter_clip = true
	image.texture = atlas
	_update_frame()

func _process(delta: float) -> void:
	if atlas == null or animation.is_empty():
		return
	elapsed += delta
	_update_frame()

func _update_frame() -> void:
	var frame := int(elapsed * float(animation.fps)) % int(animation.frame_count)
	if frame == current_frame:
		return
	current_frame = frame
	var cell := Vector2(float(animation.cell_size[0]), float(animation.cell_size[1]))
	var columns := int(animation.columns)
	atlas.region = Rect2(Vector2(float(frame % columns), floorf(float(frame) / float(columns))) * cell, cell)

func _layout() -> void:
	if not is_instance_valid(image):
		return
	image.position = Vector2(12, 0)
	image.size = Vector2(maxf(1.0, size.x - 24), maxf(1.0, size.y - 25))
	image.pivot_offset = image.size * 0.5
	base_position = image.position
	queue_redraw()

func _draw() -> void:
	draw_set_transform(Vector2(size.x * 0.5, size.y - 18), 0.0, Vector2(1.0, 0.16))
	draw_circle(Vector2.ZERO, size.x * 0.3, Color(0.01, 0.04, 0.06, 0.35), true)
	draw_set_transform(Vector2.ZERO)

func _idle() -> void:
	if floating and floating.is_valid():
		floating.kill()
	if not animated:
		image.position = base_position
		return
	floating = create_tween().set_loops()
	floating.tween_property(image, "position:y", base_position.y - 7.0, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	floating.tween_property(image, "position:y", base_position.y, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func strike(direction: float) -> void:
	if not animated:
		return
	if floating and floating.is_valid():
		floating.kill()
	var tween := create_tween()
	tween.tween_property(image, "position:x", base_position.x + 55 * direction, 0.12).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(image, "position:x", base_position.x, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished
	_idle()

func hit() -> void:
	var tween := create_tween()
	tween.tween_property(image, "modulate", Color(2.0, 0.5, 0.5), 0.07)
	tween.tween_property(image, "modulate", Color.WHITE, 0.2)
	if animated:
		tween.parallel().tween_property(image, "rotation", 0.06, 0.07)
		tween.tween_property(image, "rotation", 0.0, 0.1)

func knocked_out() -> void:
	if floating and floating.is_valid():
		floating.kill()
	var tween := create_tween()
	tween.tween_property(image, "modulate:a", 0.2, 0.4 if animated else 0.01)
	if animated:
		tween.parallel().tween_property(image, "position:y", base_position.y + 30, 0.4)

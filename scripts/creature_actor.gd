class_name CreatureActor
extends Control
## Original frame animations with one shared logical viewport across every action.

signal animation_finished(state: String)

var image: TextureRect
var floating: Tween
var animated: bool = true
var playback_speed: float = 1.0
var base_position := Vector2.ZERO
var atlas: AtlasTexture
var animation: Dictionary = {}
var elapsed: float = 0.0
var current_frame: int = -1
var current_state: String = "idle"
var species_id: int = 0
var state_complete: bool = false
var _face_left: bool = false
var _motion_tween: Tween
var _state_serial: int = 0
static var animation_catalogue: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	_ensure_image()
	resized.connect(_layout)
	_layout()


func _ensure_image() -> void:
	if is_instance_valid(image):
		return
	image = TextureRect.new()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_SCALE
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(image)


func setup(id: int, face_left: bool = false, motion: bool = true) -> void:
	_ensure_image()
	_kill_motion()
	species_id = id
	animated = motion
	_face_left = face_left
	image.flip_h = face_left
	image.modulate = Color.WHITE
	image.rotation = 0.0
	_load_catalogue()
	play_state("idle")


static func _load_catalogue() -> void:
	if not animation_catalogue.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/animations.json"))
	if parsed is Dictionary:
		animation_catalogue = parsed.get("animations", {})
		# Keep projects using the first idle-only manifest readable.
		if animation_catalogue.is_empty():
			for key: String in parsed.get("idle", {}):
				animation_catalogue[key] = {"idle": parsed.idle[key]}


func play_state(state: String) -> float:
	_ensure_image()
	_kill_motion()
	_state_serial += 1
	current_state = state
	state_complete = false
	elapsed = 0.0
	current_frame = -1
	animation = {}
	atlas = null
	var states: Dictionary = animation_catalogue.get(str(species_id), {})
	if animated and states.has(state):
		var definition: Dictionary = states[state]
		var path: String = str(definition.get("texture", ""))
		if ResourceLoader.exists(path):
			animation = definition
			atlas = AtlasTexture.new()
			atlas.atlas = load(path)
			atlas.filter_clip = true
			image.texture = atlas
			_update_frame()
			_layout()
			return _duration() / maxf(0.01, playback_speed)
	var portrait: String = "res://assets/creatures/%d.png" % species_id
	image.texture = load(portrait) if ResourceLoader.exists(portrait) else null
	_layout()
	if state == "idle":
		_idle()
	return 0.0


func _duration() -> float:
	return float(animation.get("frame_count", 0)) / maxf(1.0, float(animation.get("fps", 24.0)))


func _process(delta: float) -> void:
	if atlas == null or animation.is_empty() or state_complete:
		return
	elapsed += maxf(0.0, delta) * maxf(0.01, playback_speed)
	var duration: float = _duration()
	if current_state != "idle" and elapsed >= duration:
		current_frame = int(animation.frame_count) - 1
		_set_frame(current_frame)
		state_complete = true
		var finished_state: String = current_state
		var serial: int = _state_serial
		animation_finished.emit(finished_state)
		# Signal handlers may start another state or remove this actor.
		if serial == _state_serial and not is_queued_for_deletion() and finished_state not in ["ko", "victory"]:
			play_state("idle")
		return
	_update_frame()


func _update_frame() -> void:
	var count: int = maxi(1, int(animation.get("frame_count", 1)))
	var frame: int = int(elapsed * float(animation.get("fps", 24.0))) % count
	if frame != current_frame:
		current_frame = frame
		_set_frame(frame)


func _set_frame(frame: int) -> void:
	var cell := Vector2(float(animation.cell_size[0]), float(animation.cell_size[1]))
	var columns: int = maxi(1, int(animation.columns))
	atlas.region = Rect2(Vector2(float(frame % columns), floorf(float(frame) / float(columns))) * cell, cell)


func _layout() -> void:
	if not is_instance_valid(image):
		return
	var area := Vector2(maxf(1.0, size.x - 24.0), maxf(1.0, size.y - 25.0))
	if atlas != null and not animation.is_empty():
		var cell := Vector2(float(animation.cell_size[0]), float(animation.cell_size[1]))
		var viewport: Dictionary = animation.get("viewport", {})
		var logical_size := Vector2(float(viewport.get("width", cell.x)), float(viewport.get("height", cell.y)))
		var logical_origin := Vector2(float(viewport.get("left", 0.0)), float(viewport.get("top", 0.0)))
		# Mirroring the full cell also mirrors the logical viewport's origin.
		if _face_left:
			logical_origin.x = cell.x - logical_origin.x - logical_size.x
		var pixels_per_unit: float = minf(area.x / maxf(1.0, logical_size.x), area.y / maxf(1.0, logical_size.y))
		var logical_top_left := Vector2(12.0 + (area.x - logical_size.x * pixels_per_unit) * 0.5, area.y - logical_size.y * pixels_per_unit)
		image.size = cell * pixels_per_unit
		image.position = logical_top_left - logical_origin * pixels_per_unit
	else:
		var side: float = minf(area.x, area.y)
		image.size = Vector2.ONE * side
		image.position = Vector2(12.0 + (area.x - side) * 0.5, area.y - side)
	image.pivot_offset = image.size * 0.5
	base_position = image.position
	queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2(size.x * 0.5, size.y - 18), 0.0, Vector2(1.0, 0.16))
	draw_circle(Vector2.ZERO, size.x * 0.3, Color(0.01, 0.04, 0.06, 0.35), true)
	draw_set_transform(Vector2.ZERO)


func _kill_motion() -> void:
	if floating and floating.is_valid():
		floating.kill()
	if _motion_tween and _motion_tween.is_valid():
		_motion_tween.kill()
	if is_instance_valid(image):
		image.rotation = 0.0
		image.position = base_position
		image.modulate = Color.WHITE


func _idle() -> void:
	# Real idle frames already contain the creature's motion.
	if not animated or atlas != null or not is_inside_tree():
		return
	floating = create_tween().set_loops()
	floating.tween_property(image, "position:y", base_position.y - 7.0, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	floating.tween_property(image, "position:y", base_position.y, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func strike(direction: float) -> void:
	var duration: float = play_state("attack")
	if duration > 0.0:
		await get_tree().create_timer(duration).timeout
		return
	if not animated:
		return
	var serial: int = _state_serial
	_motion_tween = create_tween()
	_motion_tween.tween_property(image, "position:x", base_position.x + 45.0 * direction, 0.12).set_trans(Tween.TRANS_CUBIC)
	_motion_tween.tween_property(image, "position:x", base_position.x, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await _motion_tween.finished
	if serial == _state_serial:
		play_state("idle")


func hit() -> void:
	if current_state == "ko":
		return
	if play_state("hit") > 0.0:
		return
	_motion_tween = create_tween()
	_motion_tween.tween_property(image, "modulate", Color(2.0, 0.5, 0.5), 0.07)
	_motion_tween.tween_property(image, "modulate", Color.WHITE, 0.2)
	var serial: int = _state_serial
	_motion_tween.tween_callback(func() -> void:
		if serial == _state_serial:
			play_state("idle")
	)


func knocked_out() -> void:
	if play_state("ko") > 0.0:
		return
	_motion_tween = create_tween()
	_motion_tween.tween_property(image, "modulate:a", 0.2, 0.4 if animated else 0.01)
	if animated:
		_motion_tween.parallel().tween_property(image, "position:y", base_position.y + 30.0, 0.4)


func victory() -> void:
	play_state("victory")

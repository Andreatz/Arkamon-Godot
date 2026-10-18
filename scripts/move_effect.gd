class_name MoveEffect
extends Control
## Existing Beta type VFX. Original frame counts/FPS are preserved.

signal finished

var image: TextureRect
var atlas: AtlasTexture
var animation: Dictionary = {}
var elapsed: float = 0.0
var current_frame: int = -1
var completed: bool = false
var playback_speed: float = 1.0
static var catalogue: Dictionary = {}


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
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(image)


func setup(move_id: int, move_type: String, target_rect: Rect2 = Rect2()) -> float:
	_ensure_image()
	if target_rect.size != Vector2.ZERO:
		position = target_rect.position
		size = target_rect.size
	if catalogue.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/vfx.json"))
		if parsed is Dictionary:
			catalogue = parsed
	var mapped_type: String = str(catalogue.get("moves", {}).get(str(move_id), move_type))
	var types: Dictionary = catalogue.get("types", {})
	animation = types.get(mapped_type, types.get(move_type, types.get("Normale", {})))
	elapsed = 0.0
	current_frame = -1
	completed = false
	if animation.is_empty() or not ResourceLoader.exists(str(animation.get("texture", ""))):
		completed = true
		queue_free()
		return 0.0
	atlas = AtlasTexture.new()
	atlas.atlas = load(str(animation.texture))
	atlas.filter_clip = true
	image.texture = atlas
	image.material = null
	if str(animation.get("blend_mode", "normal")) == "screen":
		var additive := CanvasItemMaterial.new()
		additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		image.material = additive
	_update_frame(0)
	_layout()
	return float(animation.frame_count) / maxf(1.0, float(animation.fps)) / maxf(0.01, playback_speed)


func _layout() -> void:
	if is_instance_valid(image):
		image.position = Vector2.ZERO
		image.size = size


func _process(delta: float) -> void:
	if completed or atlas == null or animation.is_empty():
		return
	elapsed += maxf(0.0, delta) * maxf(0.01, playback_speed)
	var frame: int = int(elapsed * float(animation.fps))
	if frame >= int(animation.frame_count):
		completed = true
		finished.emit()
		queue_free()
		return
	_update_frame(frame)


func _update_frame(frame: int) -> void:
	if current_frame == frame:
		return
	current_frame = frame
	var cell := Vector2(float(animation.cell_size[0]), float(animation.cell_size[1]))
	var columns: int = maxi(1, int(animation.columns))
	atlas.region = Rect2(Vector2(float(frame % columns), floorf(float(frame) / float(columns))) * cell, cell)

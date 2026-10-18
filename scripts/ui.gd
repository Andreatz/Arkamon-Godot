class_name ArkUI
extends RefCounted

const INK := Color("111827")
const PANEL := Color("102842")
const EDGE := Color("4c82b3")
const TEXT := Color("f3f9ff")
const MUTED := Color("bbd0e6")
const MINT := Color("9fdeff")
const GOLD := Color("ffd15a")
const RED := Color("ff8395")
const KIT := "res://assets/ui/original/player-kit/"
static var _frames: Dictionary = {}
static var _portraits: Dictionary = {}

## Match CSS border-image slices, including its independently sized x/y borders.
static func kit_style(id: String, slice: int = 61, margin: int = 18) -> StyleBoxTexture:
	var is_button := id.begins_with("button-") or id.begins_with("command-")
	var edge_x := 18 if is_button else 25
	var edge_y := 11 if is_button else 25
	if id.begins_with("slot-") or id.begins_with("card-"):
		edge_x = 18
		edge_y = 13
	var key := "%s:%d:%d:%d" % [id, slice, edge_x, edge_y]
	if not _frames.has(key):
		var source := load(KIT + id + ".svg") as Texture2D
		if source:
			var pixels := source.get_image()
			pixels.resize(maxi(2, roundi(source.get_width() * float(edge_x) / slice)), maxi(2, roundi(source.get_height() * float(edge_y) / slice)), Image.INTERPOLATE_LANCZOS)
			_frames[key] = ImageTexture.create_from_image(pixels)
	var style := StyleBoxTexture.new()
	style.texture = _frames.get(key)
	for side in [SIDE_LEFT, SIDE_RIGHT]: style.set_texture_margin(side, edge_x)
	for side in [SIDE_TOP, SIDE_BOTTOM]: style.set_texture_margin(side, edge_y)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]: style.set_content_margin(side, margin)
	return style

static func box(color: Color = PANEL, radius: int = 18, border: Color = EDGE) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = border
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0
	return style

static func make_theme() -> Theme:
	var result := Theme.new()
	result.default_font = load("res://assets/fonts/Norwester.ttf")
	result.default_font_size = 16
	result.set_color("font_color", "Label", TEXT)
	result.set_color("font_color", "Button", TEXT)
	result.set_color("font_hover_color", "Button", TEXT)
	result.set_color("font_pressed_color", "Button", TEXT)
	result.set_color("font_disabled_color", "Button", Color("72838c"))
	result.set_stylebox("normal", "Button", kit_style("button-default", 48, 12))
	var hover := kit_style("button-default", 48, 12)
	hover.modulate_color = Color(1.12, 1.12, 1.12)
	result.set_stylebox("hover", "Button", hover)
	result.set_stylebox("pressed", "Button", kit_style("button-primary", 44, 12))
	var disabled := kit_style("button-default", 48, 12)
	disabled.modulate_color = Color(1, 1, 1, 0.45)
	result.set_stylebox("disabled", "Button", disabled)
	var focus_style := box(Color(0, 0, 0, 0), 3, Color("effcff"))
	focus_style.border_width_left = 2
	focus_style.border_width_top = 2
	focus_style.border_width_right = 2
	focus_style.border_width_bottom = 2
	result.set_stylebox("focus", "Button", focus_style)
	result.set_stylebox("panel", "PanelContainer", kit_style("panel-medium", 97))
	result.set_constant("separation", "VBoxContainer", 12)
	result.set_constant("separation", "HBoxContainer", 12)
	result.set_stylebox("background", "ProgressBar", box(Color("0c192a"), 4, Color("738ba8")))
	result.set_stylebox("fill", "ProgressBar", box(Color("1fab77"), 4, Color("67eba9")))
	for control: String in ["LineEdit", "TextEdit", "SpinBox"]:
		result.set_stylebox("normal", control, box(Color("0d1e34"), 6, Color("5285b5")))
		result.set_color("font_color", control, TEXT)
	result.set_stylebox("normal", "OptionButton", kit_style("button-default", 48, 10))
	result.set_stylebox("hover", "OptionButton", hover)
	result.set_stylebox("pressed", "OptionButton", kit_style("button-primary", 44, 10))
	result.set_stylebox("panel", "PopupMenu", box(Color("0d1e34"), 4, EDGE))
	result.set_stylebox("panel", "AcceptDialog", kit_style("panel-medium", 97, 24))
	return result

static func label(text: String, size: int = 20, color: Color = TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

static func button(text: String, action: Callable, primary: bool = false) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size.y = 42
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if primary:
		node.add_theme_stylebox_override("normal", kit_style("button-primary", 44, 12))
		node.add_theme_color_override("font_color", TEXT)
	node.pressed.connect(action)
	return node

static func panel(kind: String = "panel-medium") -> PanelContainer:
	var node := PanelContainer.new()
	var slices := {"panel-wide": 163, "panel-medium": 97, "card-default": 61, "card-selected-cyan": 56, "card-selected-violet": 58, "card-portrait": 99, "slot-default": 62, "slot-selected": 60, "slot-cyan": 62}
	node.add_theme_stylebox_override("panel", kit_style(kind, int(slices.get(kind, 61)), 18))
	return node

static func icon(id: String, size: int = 30) -> TextureRect:
	var node := texture(KIT + id + ".svg")
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.custom_minimum_size = Vector2(size, size)
	return node

static func portrait(species_id: int, size: int = 68) -> Control:
	var node := Control.new()
	node.custom_minimum_size = Vector2(size, size)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var circle := icon("circle-default", 0)
	node.add_child(circle)
	fill(circle)
	var path := "res://assets/creatures/%d.png" % species_id
	var art := texture(path)
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if not _portraits.has(species_id) and art.texture:
		var image := art.texture.get_image()
		var bounds := image.get_used_rect()
		var dimension := maxf(bounds.size.x, bounds.size.y) * 1.16
		var origin := Vector2(bounds.position) + (Vector2(bounds.size) - Vector2.ONE * dimension) * 0.5
		var framed := Image.create(roundi(dimension), roundi(dimension), false, Image.FORMAT_RGBA8)
		framed.blit_rect(image, bounds, Vector2i(Vector2(bounds.position) - origin))
		_portraits[species_id] = ImageTexture.create_from_image(framed)
	if _portraits.has(species_id): art.texture = _portraits[species_id]
	node.add_child(art)
	fill(art)
	return node

static func typebadge(type: String) -> Control:
	var panel_node := PanelContainer.new()
	var style := box(Color("0f2340"), 5, Color("527ba8"))
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	panel_node.add_theme_stylebox_override("panel", style)
	var row := hbox(6)
	panel_node.add_child(row)
	var ids := {"Normale": "normal", "Elettro": "electric", "Fuoco": "fire", "Terra": "earth", "Acqua": "water", "Erba": "grass", "Oscurità": "dark", "Psico": "psychic"}
	row.add_child(icon("type-" + String(ids.get(type, "normal")), 21))
	row.add_child(label(type, 12))
	return panel_node

static func vbox(gap: int = 12) -> VBoxContainer:
	var node := VBoxContainer.new()
	node.add_theme_constant_override("separation", gap)
	return node

static func hbox(gap: int = 12) -> HBoxContainer:
	var node := HBoxContainer.new()
	node.add_theme_constant_override("separation", gap)
	return node

static func paragraph(text: String, size: int = 20, color: Color = MUTED) -> Label:
	var node := label(text, size, color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return node

static func fill(node: Control) -> void:
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

static func texture(path: String) -> TextureRect:
	var node := TextureRect.new()
	if ResourceLoader.exists(path):
		node.texture = load(path)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

static func spacer() -> Control:
	var node := Control.new()
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node

static func type_color(type: String) -> Color:
	return {"Fuoco": Color("f7a070"), "Acqua": Color("76c3f5"),
		"Erba": Color("9cdb9c"), "Oscurità": Color("c2a7ed"),
		"Psico": Color("efa8d6"), "Elettro": GOLD}.get(type, MINT)

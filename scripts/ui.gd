class_name ArkUI
extends RefCounted

const INK := Color("0a1724")
const PANEL := Color("102432")
const EDGE := Color("2a4553")
const TEXT := Color("f5f0e3")
const MUTED := Color("a7bdc5")
const MINT := Color("7ce3c6")
const GOLD := Color("e9c57b")
const RED := Color("f58b89")

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
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Segoe UI", "DejaVu Sans", "Arial"])
	result.default_font = font
	result.default_font_size = 20
	result.set_color("font_color", "Label", TEXT)
	result.set_color("font_color", "Button", TEXT)
	result.set_color("font_hover_color", "Button", TEXT)
	result.set_color("font_pressed_color", "Button", INK)
	result.set_color("font_disabled_color", "Button", Color("72838c"))
	result.set_stylebox("normal", "Button", box(Color("193340"), 12))
	result.set_stylebox("hover", "Button", box(Color("244b56"), 12, MINT))
	result.set_stylebox("pressed", "Button", box(MINT, 12, MINT))
	result.set_stylebox("disabled", "Button", box(Color("14232c"), 12, Color("26343d")))
	var focus_style := box(Color(0, 0, 0, 0), 12, GOLD)
	focus_style.border_width_left = 3
	focus_style.border_width_top = 3
	focus_style.border_width_right = 3
	focus_style.border_width_bottom = 3
	result.set_stylebox("focus", "Button", focus_style)
	result.set_stylebox("panel", "PanelContainer", box())
	result.set_constant("separation", "VBoxContainer", 12)
	result.set_constant("separation", "HBoxContainer", 12)
	result.set_stylebox("background", "ProgressBar", box(Color("071722"), 5, Color("223c48")))
	result.set_stylebox("fill", "ProgressBar", box(MINT, 5, MINT))
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
	node.custom_minimum_size.y = 54
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if primary:
		node.add_theme_stylebox_override("normal", box(Color("245347"), 12, MINT))
		node.add_theme_color_override("font_color", MINT)
	node.pressed.connect(action)
	return node

static func panel() -> PanelContainer:
	return PanelContainer.new()

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

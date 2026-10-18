class_name SiteShell
extends RefCounted
## Native equivalent of the production PlayerUi chrome and legacy scene stage.

static func build(game) -> void:
	var base := ColorRect.new()
	base.color = ArkUI.INK
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.add_child(base)
	ArkUI.fill(base)
	game.backdrop = ArkUI.texture("res://assets/backgrounds/laboratory.webp")
	game.add_child(game.backdrop)
	ArkUI.fill(game.backdrop)
	game.title_video = VideoStreamPlayer.new()
	game.title_video.expand = true
	game.title_video.loop = true
	game.title_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.add_child(game.title_video)
	ArkUI.fill(game.title_video)
	game.site_shade = ColorRect.new()
	game.site_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.add_child(game.site_shade)
	ArkUI.fill(game.site_shade)
	game.shell = MarginContainer.new()
	game.add_child(game.shell)
	ArkUI.fill(game.shell)
	game.page = ArkUI.vbox(10)
	game.shell.add_child(game.page)
	game.toast_label = ArkUI.label("", 15, ArkUI.MINT)
	game.toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game.toast_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	game.toast_label.offset_top = -28
	game.toast_label.offset_bottom = -5
	game.toast_label.z_index = 20
	game.add_child(game.toast_label)
	game.site_menu_button = ArkUI.button("Partita", game._show_tools)
	game.site_menu_button.custom_minimum_size = Vector2(80, 34)
	game.site_menu_button.add_theme_font_size_override("font_size", 12)
	game.site_menu_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	game.site_menu_button.offset_left = 12
	game.site_menu_button.offset_right = 92
	game.site_menu_button.offset_top = -44
	game.site_menu_button.offset_bottom = -10
	game.add_child(game.site_menu_button)
	game.site_audio_button = ArkUI.button("Audio ON", game._toggle_sound)
	game.site_audio_button.custom_minimum_size = Vector2(64, 28)
	game.site_audio_button.add_theme_font_size_override("font_size", 10)
	var audio_style := ArkUI.box(Color(0, 0, 0, 0.7), 4, Color(1, 1, 1, 0.15))
	audio_style.content_margin_left = 6
	audio_style.content_margin_right = 6
	audio_style.content_margin_top = 4
	audio_style.content_margin_bottom = 4
	game.site_audio_button.add_theme_stylebox_override("normal", audio_style)
	game.site_audio_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	game.site_audio_button.offset_left = -76
	game.site_audio_button.offset_right = -12
	game.site_audio_button.offset_top = -40
	game.site_audio_button.offset_bottom = -12
	game.add_child(game.site_audio_button)

static func clear(game, next_screen: String) -> void:
	game.screen = next_screen
	for child in game.page.get_children():
		game.page.remove_child(child)
		child.queue_free()
	game.action_buttons.clear()
	game.toast_label.text = ""
	game.title_video.stop()
	game.title_video.hide()
	game.backdrop.modulate = Color.WHITE
	var full_stage := next_screen in ["title", "starters", "world", "location", "battle"]
	for edge in ["left", "right"]: game.shell.add_theme_constant_override("margin_" + edge, 0 if full_stage else 20)
	for edge in ["top", "bottom"]: game.shell.add_theme_constant_override("margin_" + edge, 0 if full_stage else 10)
	game.site_shade.color = Color(0, 0, 0, 0)
	game.site_menu_button.visible = full_stage and next_screen != "battle"
	game.site_audio_button.visible = full_stage
	game.site_audio_button.text = "Audio ON" if game.sound_enabled else "Audio OFF"
	if not full_stage:
		game._background("deposito")
		game.site_shade.color = Color(0.04, 0.10, 0.18, 0.9)
		if game.model.state.is_empty():
			var header := ArkUI.hbox()
			header.add_child(_logo(165, 42))
			header.add_child(ArkUI.spacer())
			header.add_child(ArkUI.button("Titolo", game._show_title))
			game.page.add_child(header)
		else:
			_header(game)
			_navigation(game)

static func _logo(width: int, height: int) -> TextureRect:
	var logo := ArkUI.texture("res://assets/ui/original/logo_arkamon.png")
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(width, height)
	return logo

static func _header(game) -> void:
	var panel := ArkUI.panel("panel-wide")
	var frame := ArkUI.kit_style("panel-wide", 163, 8)
	frame.content_margin_left = 20
	frame.content_margin_right = 20
	panel.add_theme_stylebox_override("panel", frame)
	game.page.add_child(panel)
	var row := ArkUI.hbox(24)
	panel.add_child(row)
	var brand := ArkUI.vbox(2)
	brand.add_child(_logo(165, 36))
	brand.add_child(ArkUI.label("Strumenti dell’allenatore", 10, ArkUI.MUTED))
	row.add_child(brand)
	var person: Dictionary = game.model.player()
	var position := ArkUI.vbox(3)
	position.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	position.add_child(ArkUI.label("Posizione di G%d" % (int(game.model.state.active_player) + 1), 12, ArkUI.MUTED))
	position.add_child(ArkUI.label(game._place(person.location), 16))
	row.add_child(position)
	for index in 2:
		var entry: Dictionary = game.model.player(index)
		var button := ArkUI.button("%s · G%d" % [entry.name, index + 1], game._show_dex_for.bind(index), index == int(game.model.state.active_player))
		button.tooltip_text = "Consulta le scoperte di " + String(entry.name)
		if not entry.party.is_empty():
			button.icon = load("res://assets/creatures/%d.png" % int(entry.party[0].species_id))
			button.expand_icon = true
			button.add_theme_constant_override("icon_max_width", 27)
		button.add_theme_font_size_override("font_size", 14)
		row.add_child(button)
	row.add_child(ArkUI.icon("item-coin", 34))
	game.inventory_label = ArkUI.label("%d ₳" % int(person.coins), 24, ArkUI.GOLD)
	row.add_child(game.inventory_label)

static func _navigation(game) -> void:
	var panel := ArkUI.panel("panel-wide")
	var frame := ArkUI.kit_style("panel-wide", 163, 6)
	frame.content_margin_left = 16
	frame.content_margin_right = 16
	panel.add_theme_stylebox_override("panel", frame)
	game.page.add_child(panel)
	var row := ArkUI.hbox(8)
	panel.add_child(row)
	var entries := [["Menù Partita", "icon-home", "tools", game._show_tools], ["Squadra", "icon-team", "party", game._show_party], ["Deposito", "icon-box", "box", game._show_box], ["Arkadex", "icon-book", "dex", game._show_dex], ["Analisi", "icon-analysis", "analysis", game._show_active_analysis], ["Borsa", "icon-bag", "bag", game._show_bag]]
	for entry: Array in entries:
		var button := ArkUI.button(entry[0], entry[3], game.screen == entry[2])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.icon = load(ArkUI.KIT + entry[1] + ".svg")
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 27)
		button.add_theme_font_size_override("font_size", 14)
		row.add_child(button)

static func footer(game, back: Callable) -> void:
	var row := ArkUI.hbox(12)
	if not game.model.state.is_empty():
		row.add_child(ArkUI.label("Turno di G%d · %d azioni disponibili" % [int(game.model.state.active_player) + 1, int(game.model.state.actions_left)], 12, ArkUI.MUTED))
	row.add_child(ArkUI.spacer())
	row.add_child(ArkUI.label("Esc · Torna al viaggio", 12, ArkUI.MUTED))
	var button := ArkUI.button("Riprendi il Viaggio", back, true)
	button.icon = load(ArkUI.KIT + "icon-home.svg")
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 23)
	row.add_child(button)
	game.page.add_child(row)
	game._focus_first()

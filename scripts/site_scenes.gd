class_name SiteScenes
extends RefCounted
## Original website composition on a native 1440x810 stage.

static func _stage(game, screen: String) -> Control:
	game._clear_page(screen)
	var stage := Control.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game.page.add_child(stage)
	return stage

static func _put(parent: Control, node: Control, x: float, y: float, w: float, h: float) -> Control:
	parent.add_child(node)
	node.position = Vector2(x, y)
	node.size = Vector2(w, h)
	return node

static func _percent(parent: Control, node: Control, rect: Dictionary) -> Control:
	return _put(parent, node, float(rect.get("x", 0)) * 14.4, float(rect.get("y", 0)) * 8.1, float(rect.get("w", 10)) * 14.4, float(rect.get("h", 5)) * 8.1)

static func _small_button(text: String, action: Callable, primary: bool = false) -> Button:
	var button := ArkUI.button(text, action, primary)
	button.custom_minimum_size = Vector2.ZERO
	button.add_theme_font_size_override("font_size", 14)
	return button

static func _violet(text: String, font_size: int = 14) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := ArkUI.box(Color(0.141, 0.098, 0.239, 0.85), 0, Color("7c3aed"))
	style.content_margin_left = 9; style.content_margin_right = 9
	style.content_margin_top = 4; style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(ArkUI.label(text, font_size, Color("f8fafc")))
	return panel

static func title(game) -> void:
	game.busy = false
	var stage := _stage(game, "title")
	game._background("title")
	game.site_shade.color = Color(0.067, 0.094, 0.153, 0.45)
	if (not game.testing or "--animate-title" in OS.get_cmdline_user_args()) and not game.reduced_motion and ResourceLoader.exists("res://assets/backgrounds/title.ogv"):
		game.title_video.stream = load("res://assets/backgrounds/title.ogv")
		game.title_video.show()
		game.title_video.play()
	var logo := ArkUI.texture("res://assets/ui/original/logo_arkamon.png")
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_put(stage, logo, 470, 165, 500, 190)
	_put(stage, _small_button("Nuova Partita", game._request_new_game, true), 612, 462, 216, 39)
	if SaveStore.has_save(game.save_path):
		_put(stage, _small_button("Continua", game._continue_game), 612, 510, 216, 39)
	game._focus_first()

static func _lab_label(stage: Control, text: String, y: float, font_size: int, color: Color = Color.WHITE) -> void:
	var label := ArkUI.label(text, font_size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_outline_color", Color("111111"))
	label.add_theme_constant_override("outline_size", 2)
	_put(stage, label, 390, y, 660, 42)

static func starters(game) -> void:
	game._background("laboratory")
	var stage := _stage(game, "starters")
	game.name_inputs.clear()
	for index in 2:
		var avatar := ArkUI.texture("res://assets/ui/original/player%d.png" % (index + 1))
		avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_put(stage, avatar, -216 if index == 0 else 1008, 283 if index == 0 else 97, 871 if index == 0 else 432, 486 if index == 0 else 713)
	if not game.starter_names_confirmed:
		_lab_label(stage, "Laboratorio del Professore", 205, 30, Color("c084fc"))
		var form := PanelContainer.new()
		var style := ArkUI.box(Color(0.141, 0.098, 0.239, 0.85), 0, Color("7c3aed"))
		style.content_margin_left = 20
		style.content_margin_right = 20
		form.add_theme_stylebox_override("panel", style)
		_put(stage, form, 516, 265, 408, 282)
		var column := ArkUI.vbox(12)
		form.add_child(column)
		var intro := ArkUI.label("Inserisci i nomi dei giocatori", 18)
		intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(intro)
		for index in 2:
			column.add_child(ArkUI.label("Giocatore %d" % (index + 1), 14))
			var edit := LineEdit.new()
			edit.text = game.player_names[index]
			edit.max_length = 24
			edit.custom_minimum_size.y = 36
			edit.text_changed.connect(func(value: String) -> void: game.player_names[index] = value.strip_edges() if not value.strip_edges().is_empty() else "Giocatore %d" % (index + 1))
			column.add_child(edit)
			game.name_inputs.append(edit)
		column.add_child(_small_button("Continua", func() -> void: game.starter_names_confirmed = true; game._show_starters(), true))
		game._focus_starter_name.call_deferred()
		return
	var selected: int = mini(game.starter_choices.size(), 1)
	_lab_label(stage, "Laboratorio del Professore", 265, 30, Color("c084fc"))
	_lab_label(stage, "%s, scegli il tuo Starter." % str(game.player_names[selected]), 305, 16)
	for index in 3:
		var id: int = [1, 5, 9][index]
		var member: Dictionary = game.rules.creature(id, 5)
		var card := Button.new()
		var style := ArkUI.box(Color(0.141, 0.098, 0.239, 0.85), 0, Color("7c3aed"))
		for state: String in ["normal", "hover", "pressed", "disabled"]:
			card.add_theme_stylebox_override(state, style)
		card.pressed.connect(game._new_game.bind(id))
		card.disabled = id in game.starter_choices
		card.modulate.a = 0.4 if card.disabled else 1.0
		_put(stage, card, 450 + index * 186, 350, 168, 190)
		var sprite := ArkUI.texture("res://assets/creatures/%d.png" % id)
		sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_put(card, sprite, 36, 18, 96, 96)
		var name := ArkUI.label(str(member.name), 24)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_put(card, name, 0, 121, 168, 32)
		var kind := ArkUI.label(str(member.type), 14, Color("c4b5fd"))
		kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_put(card, kind, 0, 156, 168, 24)
	game._focus_first()

static func world(game) -> void:
	game.busy = false
	game.session = null
	var stage := _stage(game, "world")
	var person: Dictionary = game.model.player()
	var definition: Dictionary = game.world_data.get("main_map", {})
	var board := WorldBoard.new()
	board.definition = definition
	board.positions = [str(game.model.player(0).location), str(game.model.player(1).location)]
	board.active_player = int(game.model.state.active_player)
	board.reachable = game.model.available_destinations()
	_put(stage, board, 0, 0, 1440, 810)
	board.selected.connect(func(destination: String) -> void:
		if destination == str(person.location): game._enter_location()
		else: game._travel(destination)
	)
	var layouts: Dictionary = game._json("res://data/site_theme.json").get("layouts", {}).get("mainMapUi", {})
	var texts := {"turnPanel": "Turno di %s · G%d" % [person.name, int(game.model.state.active_player) + 1], "coinsPanel": "%d monete" % int(person.coins), "positionPanel": game._place(str(person.location)), "actionsPanel": "Azioni rimaste: %d / 2" % int(game.model.state.actions_left)}
	for key: String in texts:
		if layouts.has(key): _percent(stage, _violet(texts[key], 14), layouts[key])
	var buttons := {"enterButton": ["Entra in " + game._place(str(person.location)), game._enter_location], "passButton": ["Passa turno", game._end_turn], "depositButton": ["Deposito", game._show_box], "titleButton": ["Titolo", game._show_title]}
	for key: String in buttons:
		if layouts.has(key): _percent(stage, _small_button(buttons[key][0], buttons[key][1], key == "enterButton"), layouts[key])
	if str(person.location) == "Roma":
		_put(stage, _small_button("Lega di Arkamon", game._show_league, true), 1170, 16, 250, 42)
	var destinations: Array = game.model.available_destinations()
	if CampaignModel.SECRET_LOCATION in destinations:
		var secret := _small_button("Percorso segreto", game._travel.bind(CampaignModel.SECRET_LOCATION), true)
		secret.disabled = int(game.model.state.actions_left) <= 0
		_put(stage, secret, 1170, 68, 250, 42)
	if layouts.has("legend"):
		var legend := _violet("", 12)
		legend.get_child(0).queue_free()
		var list := ArkUI.vbox(3)
		legend.add_child(list)
		for item: Array in [["start_location", "Start"], ["cities", "Città"], ["countries", "Villaggio"], ["route", "Percorso"]]:
			var row := ArkUI.hbox(7)
			var icon := ArkUI.texture("res://assets/ui/original/%s.png" % item[0])
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(15, 15)
			row.add_child(icon)
			row.add_child(ArkUI.label(item[1], 11))
			list.add_child(row)
		_percent(stage, legend, layouts.legend)
	game._focus_first()

static func location(game) -> void:
	var stage := _stage(game, "location")
	var person: Dictionary = game.model.player()
	var place: String = str(person.location)
	game._background_for(place)
	var maps: Dictionary = game.world_data.get("local_maps", {})
	var definition: Dictionary = maps.get(place, {})
	if not definition.is_empty():
		var board := WorldBoard.new()
		board.local = true
		board.definition = definition
		board.positions = [str(game.model.player(0).get("local_positions", {}).get(place, "")) if str(game.model.player(0).location) == place else "", str(game.model.player(1).get("local_positions", {}).get(place, "")) if str(game.model.player(1).location) == place else ""]
		board.active_player = int(game.model.state.active_player)
		_put(stage, board, 0, 0, 1440, 810)
		board.selected.connect(game._local_move)
	_put(stage, _small_button("← Mappa principale", game._show_world), 18, 15, 190, 42)
	_put(stage, _violet(game._place(place), 24), 525, 15, 390, 47)
	_put(stage, _violet("G%d · %s · %d azioni" % [int(game.model.state.active_player) + 1, person.name, int(game.model.state.actions_left)], 14), 1030, 15, 390, 42)
	var action_button := _small_button("Attività del luogo", func() -> void: _activities(game, stage), true)
	_put(stage, action_button, 1185, 681, 235, 42)
	_put(stage, _small_button("Interagisci", game._interact_current, true), 1185, 731, 235, 42)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 7)
	_put(stage, bottom, 190, 749, 975, 43)
	bottom.add_child(_small_button("Passa il turno", game._end_turn))
	for destination: Variant in game.model.available_destinations():
		bottom.add_child(_small_button(game._place(str(destination)), game._travel.bind(str(destination))))
	game._focus_first()

static func _activities(game, stage: Control) -> void:
	if stage.has_node("LocationActivities"):
		stage.get_node("LocationActivities").queue_free()
		return
	var panel := ArkUI.panel("panel-medium")
	panel.name = "LocationActivities"
	_put(stage, panel, 1000, 74, 420, 590)
	var column: VBoxContainer = game._scroll_column(panel)
	column.add_child(ArkUI.label("Attività del luogo", 22))
	column.add_child(_small_button("Chiudi  ×", panel.queue_free))
	var person: Dictionary = game.model.player()
	var place: String = str(person.location)
	if not place.begins_with("Percorso_"):
		column.add_child(_small_button("Centro cure", game._heal_party, true))
		column.add_child(_small_button("Arkastore", game._show_shop))
		column.add_child(_small_button("Deposito", game._show_box))
	for bush: String in game.model.encounters_here():
		var consumed: bool = "%s:%s" % [place, bush] in person.consumed
		var encounter := _small_button(("✓ " if consumed else "") + "Cespuglio " + bush, game._wild_encounter.bind(bush), true)
		encounter.disabled = consumed
		column.add_child(encounter)
	for trainer: Dictionary in game.model.trainers_here():
		var defeated: bool = int(trainer.id) in person.defeated
		var encounter := _small_button(("✓ " if defeated else "Sfida: ") + str(trainer.nome), game._trainer_encounter.bind(int(trainer.id)))
		encounter.disabled = defeated
		column.add_child(encounter)
	var other: Dictionary = game.model.player(1 - int(game.model.state.active_player))
	if str(other.location) == place:
		column.add_child(_small_button("Sfida " + str(other.name), game._start_pvp, true))
	if place == "Roma": column.add_child(_small_button("Lega di Arkamon", game._show_league, true))
	column.add_child(_small_button("Squadra", game._show_party))
	column.add_child(_small_button("Borsa", game._show_bag))
	column.add_child(_small_button("Interagisci sul punto", game._interact_current, true))

static func tools(game) -> void:
	game._clear_page("tools")
	var started: bool = not game.model.state.is_empty()
	var row := ArkUI.hbox(18)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	game.page.add_child(row)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	row.add_child(grid)
	var tiles := [["Diario", "Luoghi, incontri e progressi", "icon-book", func() -> void: _journal(game)], ["Backup", "Salva e importa la tua partita", "icon-box", func() -> void: _backup_menu(game)], ["Impostazioni", "Audio, animazioni e preferenze", "icon-options", game._show_settings], ["Cronache", "Rivivi le battaglie concluse", "icon-activity", game._show_archive], ["Registro del match", "Ripercorri gli eventi dell’avventura", "icon-activity", func() -> void: _journal(game)], ["Sfide", "Seed e Fanta-Team Builder", "icon-activity", game._show_challenges]]
	for index in tiles.size():
		var item: Array = tiles[index]
		var tile := Button.new()
		tile.custom_minimum_size = Vector2(310, 145)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tile.add_theme_stylebox_override("normal", ArkUI.kit_style("panel-wide" if index == 0 else "panel-medium", 163 if index == 0 else 97, 20))
		tile.add_theme_stylebox_override("hover", ArkUI.kit_style("panel-medium", 97, 20))
		tile.pressed.connect(item[3])
		tile.disabled = not started and index in [0, 3, 4]
		grid.add_child(tile)
		var icon := ArkUI.icon(item[2], 0)
		_put(tile, icon, 22, 25, 45, 45)
		_put(tile, ArkUI.label(item[0].to_upper(), 23), 83, 25, 250, 35)
		_put(tile, ArkUI.paragraph(item[1], 13), 83, 67, 230, 50)
		_put(tile, ArkUI.label("%02d" % (index + 1), 14, ArkUI.MUTED), 290, 15, 34, 24)
	var profile := ArkUI.panel()
	profile.custom_minimum_size.x = 340
	row.add_child(profile)
	var info: VBoxContainer = game._scroll_column(profile)
	info.add_child(ArkUI.label("CARTA ALLENATORE", 12, ArkUI.MINT))
	if started:
		var person: Dictionary = game.model.player()
		info.add_child(ArkUI.label(str(person.name), 28))
		var photo := ArkUI.texture(str(game.world_data.get("backgrounds", {}).get(str(person.location), "res://assets/backgrounds/laboratory.webp")))
		photo.custom_minimum_size.y = 140
		info.add_child(photo)
		info.add_child(ArkUI.label(game._place(str(person.location)), 22))
		info.add_child(ArkUI.paragraph("Turno di G%d · %d azioni\nSquadra %d / 6\nMedaglie %d / 8\n%d monete" % [int(game.model.state.active_player) + 1, int(game.model.state.actions_left), person.party.size(), person.badges.size(), int(person.coins)], 17))
		var team := ArkUI.hbox(3)
		for member: Dictionary in person.party: team.add_child(ArkUI.portrait(int(member.species_id), 42))
		info.add_child(team)
	else:
		info.add_child(ArkUI.label("Prima dell’avventura", 25))
		info.add_child(ArkUI.paragraph("Scegli il tuo starter nel laboratorio per iniziare. Ogni giocatore ha una squadra, un deposito e scoperte indipendenti.", 17))
	var editor := _small_button("Editor delle interazioni", game._show_interaction_editor)
	editor.disabled = not started
	info.add_child(editor)
	var help := _small_button("Come si gioca", game._show_help)
	help.disabled = not started
	info.add_child(help)
	var migration := _small_button("Importa partita della demo", game._migrate_demo)
	migration.disabled = not SaveStore.has_save(game.SAVE_PATH)
	info.add_child(migration)
	SiteShell.footer(game, game._return_to_campaign if started else game._show_title)

static func _journal(game) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Diario della campagna"
	game.add_child(dialog)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(670, 420)
	dialog.add_child(scroll)
	var column := ArkUI.vbox(12)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	for entry: Variant in game.model.player().get("journal", []):
		var text: String = str(entry.get("message", entry.get("text", entry.get("title", "")))) if entry is Dictionary else str(entry)
		column.add_child(ArkUI.paragraph(text, 17))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(720, 490))

static func _backup_menu(game) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Backup della partita"
	game.add_child(dialog)
	var column := ArkUI.vbox(12)
	column.custom_minimum_size = Vector2(400, 110)
	dialog.add_child(column)
	var export_button := _small_button("Esporta backup", func() -> void: dialog.queue_free(); game._backup_export())
	export_button.disabled = game.model.state.is_empty()
	column.add_child(export_button)
	column.add_child(_small_button("Ripristina backup", func() -> void: dialog.queue_free(); game._backup_import()))
	var migration := _small_button("Importa partita della demo", func() -> void: dialog.queue_free(); game._migrate_demo())
	migration.disabled = not SaveStore.has_save(game.SAVE_PATH)
	column.add_child(migration)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(450, 250))

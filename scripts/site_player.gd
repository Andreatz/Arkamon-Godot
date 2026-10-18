class_name SitePlayer
extends RefCounted
## Native implementation of the production src/player-ui kit at Beta 7ec91d1f.
## The host owns the topbar/navigation and domain operations; this builds content.

const INK := Color("f3f9ff")
const MUTED := Color("bbd0e6")
const CYAN := Color("9fdeff")
const GOLD := Color("f5d261")
const ITEM_ICONS := {"potion": "item-potion", "super-potion": "item-superpotion", "revive": "item-revive", "antidote": "item-antidote", "paralysis-heal": "type-electric", "awakening": "type-psychic", "masterball": "item-sphere"}


static func build_party(game, selected_index: int = 0) -> void:
	var party: Array = game.model.player().party
	selected_index = clampi(selected_index, 0, maxi(0, party.size() - 1))
	_heading(game, "La tua squadra · " + str(game.model.player().name), "Gestione squadra", "%d / 6 Arkamon" % party.size())
	var row := _body(game)
	var roster := _scroll(row, 1.15)
	for index: int in range(6):
		var member: Dictionary = party[index] if index < party.size() else {}
		var button := _card_button("card-selected-violet" if index == selected_index else "card-default", func() -> void: _open(game, "party", index))
		button.custom_minimum_size.y = 62
		button.disabled = member.is_empty()
		roster.add_child(button)
		var contents := _button_contents(button, 7, 4)
		var line := ArkUI.hbox(8)
		contents.add_child(line)
		line.add_child(ArkUI.label(str(index + 1), 11, MUTED))
		if member.is_empty():
			line.add_child(ArkUI.label("Posto libero", 16, MUTED))
			continue
		line.add_child(ArkUI.portrait(int(member.species_id), 54))
		var copy := _column(line)
		copy.add_theme_constant_override("separation", 2)
		var title := ArkUI.hbox(5)
		copy.add_child(title)
		title.add_child(ArkUI.label(str(member.name), 18, INK))
		title.add_child(ArkUI.spacer())
		title.add_child(ArkUI.label("Lv. %d" % int(member.level), 14, INK))
		_health(copy, member, true)
		var metadata := ArkUI.hbox(5)
		copy.add_child(metadata)
		metadata.add_child(_small_typebadge(str(member.type)))
		var condition: String = game.rules.status_name(member)
		if int(member.hp) <= 0 or not condition.is_empty():
			metadata.add_child(ArkUI.label("KO" if int(member.hp) <= 0 else condition, 12, GOLD))
		_ignore(contents)
	var limits := _panel(roster, "panel-medium", 12)
	var range_value: Vector2i = _level_range(party)
	limits.add_child(ArkUI.paragraph("Squadra in equilibrio · Δ %d livelli\nFascia attuale: Lv. %d–%d. Differenza massima: 5." % [range_value.y - range_value.x, range_value.x, range_value.y], 13, MUTED))
	roster.add_child(_button("Apri deposito", game._show_box, "icon-box"))
	if not party.is_empty():
		var member: Dictionary = party[selected_index]
		_hero(row, member, 0.9)
		var detail := _panel(row)
		detail.size_flags_stretch_ratio = 1.0
		var info := _scroll(detail)
		info.add_child(_kicker("Condizioni del compagno"))
		info.add_child(ArkUI.label("Arkamon esausto" if int(member.hp) <= 0 else "Pronto al viaggio", 23, INK))
		_health(info, member)
		info.add_child(ArkUI.paragraph("Gli HP restano dopo ogni scontro. La cura è sempre esplicita.", 13, MUTED))
		info.add_child(ArkUI.label("Mosse disponibili", 17, INK))
		_moves(game, info, member)
		var choose := _button("In campo" if int(game.model.player().active) == selected_index else "Schiera", game._choose_companion.bind(selected_index), "icon-team", true)
		choose.disabled = int(member.hp) <= 0 or int(game.model.player().active) == selected_index
		info.add_child(choose)
		info.add_child(_button("Analizza Arkamon", game._show_creature_details.bind(member.duplicate(true), game._show_party), "icon-analysis"))
		info.add_child(_button("Apri borsa", game._show_bag, "icon-bag"))
		var deposit := _button("Deposita", game._deposit.bind(selected_index), "icon-box")
		deposit.disabled = party.size() <= 1
		info.add_child(deposit)
		var definition: Dictionary = game.rules.species[int(member.species_id)]
		if int(definition.get("evoluzioneId", 0)) > 0 and int(member.level) >= int(definition.get("livelloEvoluzione", 101)):
			info.add_child(_button("Evolvi", game._evolve.bind(selected_index), "icon-activity", true))
	_footer(game)


static func build_box(game, selected_slot: String = "") -> void:
	var person: Dictionary = game.model.player()
	var toolbar := ArkUI.hbox(10)
	game.page.add_child(toolbar)
	toolbar.add_child(_button("←", func() -> void: game.box_page = 30 if int(game.box_page) == 1 else int(game.box_page) - 1; _open(game, "box")))
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(170, 34)
	for index: int in range(1, 31):
		picker.add_item("Box %d" % index, index)
	picker.select(int(game.box_page) - 1)
	picker.item_selected.connect(func(index: int) -> void: game.box_page = index + 1; _open(game, "box"))
	toolbar.add_child(picker)
	toolbar.add_child(_button("→", func() -> void: game.box_page = 1 if int(game.box_page) == 30 else int(game.box_page) + 1; _open(game, "box")))
	toolbar.add_child(ArkUI.spacer())
	toolbar.add_child(ArkUI.label("30 box · 35 posti ciascuno", 14, MUTED))
	var row := _body(game)
	var panel := _panel(row)
	panel.add_theme_stylebox_override("panel", ArkUI.kit_style("panel-medium", 97, 12))
	panel.size_flags_stretch_ratio = 1.7
	var left := _scroll(panel)
	left.add_theme_constant_override("separation", 7)
	var occupied: int = 0
	for index: int in range(1, 36):
		if person.box.has("%d:%d" % [int(game.box_page), index]):
			occupied += 1
	var title := ArkUI.hbox()
	left.add_child(title)
	title.add_child(ArkUI.label("Compagni in riserva", 23, INK))
	title.add_child(ArkUI.spacer())
	title.add_child(ArkUI.label("%d / 35 posti" % occupied, 14, MUTED))
	_box_filters(game, left, selected_slot)
	left.add_child(ArkUI.paragraph("Seleziona un compagno. I posti vuoti restano nella loro posizione.", 13, MUTED))
	var grid := GridContainer.new()
	grid.columns = 7
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 7)
	grid.add_theme_constant_override("v_separation", 6)
	left.add_child(grid)
	for index: int in range(1, 36):
		var key: String = "%d:%d" % [int(game.box_page), index]
		var member: Dictionary = person.box.get(key, {})
		var button := _card_button("slot-selected" if key == selected_slot else "slot-default", func() -> void: _open(game, "box", key))
		button.custom_minimum_size = Vector2(38, 38)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.tooltip_text = "Posto %d: %s" % [index, "vuoto" if member.is_empty() else str(member.name)]
		grid.add_child(button)
		var circle := ArkUI.icon("circle-selected" if key == selected_slot else "circle-default", 0)
		button.add_child(circle)
		ArkUI.fill(circle)
		if member.is_empty():
			button.text = str(index)
			button.add_theme_font_size_override("font_size", 13)
		else:
			var art := ArkUI.texture("res://assets/creatures/%d.png" % int(member.species_id))
			art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			button.add_child(art)
			ArkUI.fill(art)
			if key != selected_slot and not _box_matches(game, member):
				art.modulate.a = 0.22
			var level := ArkUI.label("Lv. %d" % int(member.level), 11, INK)
			level.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
			level.position = Vector2(-45, -17)
			level.size = Vector2(43, 15)
			button.add_child(level)
		_ignore(button, false)
	left.add_child(ArkUI.label("La tua squadra · %d / 6" % person.party.size(), 17, INK))
	var squad := GridContainer.new()
	squad.columns = 6
	squad.add_theme_constant_override("h_separation", 8)
	left.add_child(squad)
	for index: int in range(6):
		var member: Dictionary = person.party[index] if index < person.party.size() else {}
		var button := _card_button("slot-default", game._show_party)
		button.custom_minimum_size = Vector2(48, 54)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = member.is_empty()
		squad.add_child(button)
		var contents := _button_contents(button, 3, 2)
		if not member.is_empty():
			var art := ArkUI.portrait(int(member.species_id), 34)
			contents.add_child(art)
			contents.add_child(ArkUI.label(str(member.name), 11, INK))
		else:
			contents.add_child(ArkUI.label("Posto %d" % (index + 1), 11, MUTED))
		_ignore(contents)
	var limits: Vector2i = _level_range(person.party)
	left.add_child(ArkUI.label("Squadra in equilibrio · Lv. %d–%d · differenza %d / 5." % [limits.x, limits.y, limits.y - limits.x], 12, MUTED))
	var detail := _panel(row)
	detail.size_flags_stretch_ratio = 0.9
	var info := _scroll(detail)
	var selected: Dictionary = person.box.get(selected_slot, {})
	if selected.is_empty() and not person.party.is_empty():
		selected = person.party[0]
	if not selected.is_empty():
		_hero(info, selected, 1.0, 160)
		_health(info, selected)
		_facts(info, [{"label": "Livello", "value": str(selected.level)}, {"label": "Crescita", "value": str(game.rules.species[int(selected.species_id)].get("categoria", "—"))}])
		info.add_child(ArkUI.paragraph("Seleziona un compagno del box per ritirarlo o scambiarlo con la squadra.", 13, MUTED))
		if not selected_slot.is_empty() and person.box.has(selected_slot):
			info.add_child(_button("Sposta o scambia", game._box_dialog.bind(selected_slot), "icon-box", true))
			info.add_child(_button("Ritira in squadra", func() -> void:
				var result: Dictionary = game.model.withdraw(selected_slot)
				game._save()
				_open(game, "box")
				game._notify(str(result.message), not bool(result.ok)), "icon-team"))
			info.add_child(_button("Analizza Arkamon", game._show_creature_details.bind(selected.duplicate(true), game._show_box), "icon-analysis"))
	_footer(game)


static func build_dex(game, selected_id: int = 0) -> void:
	var person: Dictionary = game.model.player() if int(game.view_player) < 0 else game.model.player(int(game.view_player))
	_heading(game, "Le tue scoperte", "Arkadex", "%d / 110 viste · %d / 110 ottenute" % [person.dex_seen.size(), person.dex_obtained.size()])
	var switcher := ArkUI.hbox()
	game.page.add_child(switcher)
	switcher.add_child(ArkUI.label("Giocatore dell’Arkadex", 13, MUTED))
	for index: int in range(2):
		switcher.add_child(_button("G%d · %s" % [index + 1, game.model.player(index).name], func() -> void:
			game.view_player = index
			game.dex_search = ""
			game.dex_page = 0
			game.set_meta("site_dex_status", 0)
			game.set_meta("site_dex_type", "")
			game.set_meta("site_dex_tab", 0)
			_open(game, "dex", 0)))
	var row := _body(game)
	var index_panel := _panel(row)
	index_panel.size_flags_stretch_ratio = 0.95
	var list := ArkUI.vbox(5)
	index_panel.add_child(list)
	list.add_child(ArkUI.label("Cerca specie scoperta o numero", 12, MUTED))
	var search := LineEdit.new()
	search.placeholder_text = "Nome o numero · Invio per cercare"
	search.text = str(game.dex_search)
	search.custom_minimum_size.y = 32
	_compact_field(search)
	search.text_submitted.connect(func(value: String) -> void: game.dex_search = value; game.dex_page = 0; game.set_meta("site_dex_tab", 0); _open(game, "dex", selected_id))
	list.add_child(search)
	var filters := ArkUI.hbox(6)
	list.add_child(filters)
	var status_picker := OptionButton.new()
	for label: String in ["Tutte le scoperte", "Da scoprire", "Viste", "Ottenute"]:
		status_picker.add_item(label)
	status_picker.select(int(game.get_meta("site_dex_status", 0)))
	status_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_compact_field(status_picker)
	status_picker.item_selected.connect(func(index: int) -> void: game.set_meta("site_dex_status", index); game.dex_page = 0; game.set_meta("site_dex_tab", 0); _open(game, "dex", selected_id))
	filters.add_child(status_picker)
	var type_picker := _type_picker(str(game.get_meta("site_dex_type", "")))
	type_picker.item_selected.connect(func(index: int) -> void: game.set_meta("site_dex_type", str(type_picker.get_item_metadata(index))); game.dex_page = 0; game.set_meta("site_dex_tab", 0); _open(game, "dex", selected_id))
	filters.add_child(type_picker)
	list.add_child(_button("Azzera filtri", func() -> void: game.dex_search = ""; game.set_meta("site_dex_status", 0); game.set_meta("site_dex_type", ""); game.set_meta("site_dex_tab", 0); game.dex_page = 0; _open(game, "dex", selected_id)))
	var ids: Array = []
	for id: int in range(1, 111):
		var known: bool = _known(person, id)
		var query: String = str(game.dex_search).strip_edges().to_lower()
		var obtained: bool = id in person.dex_obtained
		var status_filter: int = int(game.get_meta("site_dex_status", 0))
		var status_match: bool = status_filter == 0 or (status_filter == 1 and not known) or (status_filter == 2 and known and not obtained) or (status_filter == 3 and obtained)
		var type_filter: String = str(game.get_meta("site_dex_type", ""))
		var type_match: bool = type_filter.is_empty() or (known and str(game.rules.species[id].tipo) == type_filter)
		if status_match and type_match and (query.is_empty() or str(id).contains(query) or (known and str(game.rules.species[id].nome).to_lower().contains(query))):
			ids.append(id)
	var page_count: int = maxi(1, int(ceil(float(ids.size()) / 6.0)))
	game.dex_page = clampi(int(game.dex_page), 0, page_count - 1)
	if selected_id not in ids:
		selected_id = int(ids[0]) if not ids.is_empty() else 0
		for id: int in ids:
			if _known(person, id):
				selected_id = id
				break
	list.add_child(ArkUI.label("%d schede corrispondenti" % ids.size(), 12, MUTED))
	var species_list := _scroll(list)
	species_list.add_theme_constant_override("separation", 5)
	for position: int in range(int(game.dex_page) * 6, mini(ids.size(), int(game.dex_page) * 6 + 6)):
		var id: int = int(ids[position])
		var definition: Dictionary = game.rules.species[id]
		var known: bool = _known(person, id)
		var obtained: bool = id in person.dex_obtained
		var button := _card_button("button-primary" if selected_id == id else "button-default", func() -> void: game.set_meta("site_dex_tab", 0); _open(game, "dex", id))
		button.custom_minimum_size.y = 47
		species_list.add_child(button)
		var contents := _button_contents(button, 8, 3)
		var line := ArkUI.hbox(8)
		contents.add_child(line)
		if known:
			line.add_child(ArkUI.portrait(id, 34))
		else:
			line.add_child(ArkUI.icon("circle-default", 34))
			line.add_child(ArkUI.label("?", 21, CYAN))
		var copy := _column(line)
		copy.add_child(ArkUI.label("Nº %03d · %s" % [id, definition.nome if known else "???"], 16, INK))
		copy.add_child(ArkUI.label("Ottenuto" if obtained else ("Visto" if known else "Da scoprire"), 12, MUTED))
		line.add_child(ArkUI.icon("icon-book" if obtained else "icon-analysis", 20))
		_ignore(contents)
	var pagination := ArkUI.hbox()
	list.add_child(pagination)
	var previous := _button("←", func() -> void: game.dex_page = maxi(0, int(game.dex_page) - 1); _open(game, "dex", selected_id))
	previous.disabled = int(game.dex_page) <= 0
	pagination.add_child(previous)
	pagination.add_child(ArkUI.label("Pagina %d / %d" % [int(game.dex_page) + 1, page_count], 13, MUTED))
	var next := _button("→", func() -> void: game.dex_page = mini(page_count - 1, int(game.dex_page) + 1); _open(game, "dex", selected_id))
	next.disabled = int(game.dex_page) + 1 >= page_count
	pagination.add_child(next)
	var known: bool = selected_id > 0 and _known(person, selected_id)
	var selected: Dictionary = game.rules.creature(selected_id, 5) if known else {}
	var has_specimen: bool = false
	if known:
		for member: Dictionary in person.party + person.box.values():
			if int(member.species_id) == selected_id:
				selected = member
				has_specimen = true
				break
	_hero(row, selected, 1.16, 230, "Ottenuto" if selected_id in person.dex_obtained else "Visto", selected_id)
	var detail := _panel(row)
	var info := _scroll(detail)
	if known:
		info.add_child(_kicker("Arkadex · Nº %03d" % selected_id))
		info.add_child(ArkUI.label(str(selected.name), 24, INK))
		var discovery: String = "Ottenuto" if selected_id in person.dex_obtained else "Visto"
		info.add_child(ArkUI.paragraph(discovery if has_specimen else discovery + " · Dati di riferimento al livello 5", 14, MUTED))
		var tabs := ArkUI.hbox(5)
		info.add_child(tabs)
		var selected_tab: int = int(game.get_meta("site_dex_tab", 0))
		var tab_names: Array = ["Informazioni", "Mosse", "Evoluzioni"]
		for index: int in range(3):
			tabs.add_child(_button(str(tab_names[index]), func() -> void: game.set_meta("site_dex_tab", index); _open(game, "dex", selected_id), "", selected_tab == index))
		match selected_tab:
			0:
				_facts(info, [{"label": "Tipo", "value": str(selected.type)}, {"label": "Categoria", "value": str(game.rules.species[selected_id].categoria)}, {"label": "HP massimi", "value": str(selected.max_hp)}, {"label": "HP attuali", "value": str(selected.hp) if has_specimen else "—"}, {"label": "Tasso cattura", "value": "%d / 5" % int(game.rules.species[selected_id].get("tassoCattura", 0))}, {"label": "Livello", "value": str(selected.level)}])
				if has_specimen:
					var status_name: String = game.rules.status_name(selected)
					info.add_child(ArkUI.paragraph("Status: %s." % ("nessuno" if status_name.is_empty() else status_name), 14, MUTED))
			1:
				info.add_child(ArkUI.label("Mosse al livello %d" % int(selected.level), 19, INK))
				_moves(game, info, selected)
			2:
				info.add_child(ArkUI.label("Linea evolutiva", 19, INK))
				_dex_evolution(game, info, selected_id, person)
		info.add_child(_button("Analizza Arkamon", game._show_creature_details.bind(selected.duplicate(true), func() -> void: _open(game, "dex", selected_id)), "icon-analysis", true))
	else:
		info.add_child(_kicker("Arkadex" if selected_id == 0 else "Arkadex · Nº %03d" % selected_id))
		info.add_child(ArkUI.label("Nessuna scheda" if selected_id == 0 else "Specie da scoprire", 24, INK))
		info.add_child(ArkUI.paragraph("Nessuna specie corrisponde ai filtri scelti." if selected_id == 0 else "Incontra questa specie durante la partita per rivelarne nome, tipo e mosse.", 15, MUTED))
	_footer(game)


static func build_shop(game) -> void:
	var person: Dictionary = game.model.player()
	_heading(game, "Scorte di viaggio · " + str(person.name), "Arkastore · " + str(person.location).replace("_", " "), "%d ₳" % int(person.coins))
	var row := _body(game)
	var catalog := _panel(row)
	catalog.size_flags_stretch_ratio = 1.1
	var list := ArkUI.vbox(5)
	catalog.add_child(list)
	list.add_child(ArkUI.label("Catalogo · 7 articoli", 19, INK))
	var selected_id: String = str(game.get_meta("site_item", "potion"))
	var selected: Dictionary = game.model.item_definition(selected_id)
	if selected.is_empty():
		selected = game.model.catalog[0]
	var cart_panel := _panel(row)
	# Insert the detail column between catalogue and cart after all references exist.
	var detail := _panel(row)
	row.move_child(detail, 1)
	detail.size_flags_stretch_ratio = 1.0
	cart_panel.size_flags_stretch_ratio = 0.8
	var cart_column := ArkUI.vbox(8)
	cart_panel.add_child(cart_column)
	cart_column.add_child(ArkUI.label("Carrello", 23, INK))
	var cart_lines := ArkUI.vbox(6)
	cart_lines.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cart_column.add_child(cart_lines)
	for item: Dictionary in game.model.catalog:
		var line := ArkUI.hbox(6)
		list.add_child(line)
		var button := _button("", func() -> void: game.set_meta("site_item", str(item.id)); _open(game, "shop"), "", str(item.id) == str(selected.id))
		button.custom_minimum_size.y = 57
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(button)
		var contents := _button_contents(button, 10, 4)
		var copy := ArkUI.hbox(10)
		contents.add_child(copy)
		copy.add_child(ArkUI.icon(str(ITEM_ICONS.get(str(item.id), "item-sphere")), 36))
		var names := _column(copy)
		names.add_child(ArkUI.label(str(item.name), 16, INK))
		names.add_child(ArkUI.label("%d ₳ · In borsa: %d" % [int(item.price), int(person.bag.get(item.id, 0))], 12, MUTED))
		_ignore(contents)
		var quantity := SpinBox.new()
		quantity.min_value = 0
		quantity.max_value = 99
		quantity.step = 1
		quantity.custom_minimum_size = Vector2(70, 36)
		_compact_field(quantity)
		quantity.value = int(game.cart.get(item.id, 0))
		quantity.value_changed.connect(func(value: float) -> void:
			game.cart[item.id] = int(value)
			game._update_cart_total()
			_cart_contents(game, cart_lines))
		line.add_child(quantity)
	var info := _scroll(detail)
	info.add_child(_kicker("Articolo selezionato"))
	_item_hero(info, selected)
	info.add_child(ArkUI.label(str(selected.name), 24, INK))
	info.add_child(ArkUI.paragraph(_item_description(selected), 15, MUTED))
	info.add_child(ArkUI.label("%d ₳ ciascuno · In borsa: %d" % [int(selected.price), int(person.bag.get(selected.id, 0))], 14, MUTED))
	_cart_contents(game, cart_lines)
	game.snapshot_label = ArkUI.paragraph("", 21, GOLD)
	cart_column.add_child(game.snapshot_label)
	game._update_cart_total()
	cart_column.add_child(_button("Svuota carrello", func() -> void: game.cart.clear(); _open(game, "shop")))
	cart_column.add_child(_button("Acquista carrello", game._purchase, "icon-shop", true))
	_footer(game)


static func build_bag(game) -> void:
	var person: Dictionary = game.model.player()
	_heading(game, "I tuoi strumenti · " + str(person.name), "Borsa oggetti", "Le scorte per il prossimo incontro")
	var row := _body(game)
	var panel := _panel(row)
	panel.size_flags_stretch_ratio = 1.6
	var column := ArkUI.vbox(12)
	panel.add_child(column)
	column.add_child(ArkUI.label("La tua borsa", 23, INK))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	column.add_child(grid)
	var selected_id: String = str(game.get_meta("site_bag_item", "potion"))
	var selected: Dictionary = game.model.item_definition(selected_id)
	if selected.is_empty():
		selected = game.model.catalog[0]
	for item: Dictionary in game.model.catalog:
		var button := _card_button("slot-selected" if str(item.id) == str(selected.id) else "slot-default", func() -> void: game.set_meta("site_bag_item", str(item.id)); _open(game, "bag"))
		button.custom_minimum_size = Vector2(125, 150)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(button)
		var contents := _button_contents(button, 10, 8)
		var icon := ArkUI.icon(str(ITEM_ICONS.get(str(item.id), "item-sphere")), 85)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		contents.add_child(icon)
		contents.add_child(ArkUI.label(str(item.name), 14, INK))
		contents.add_child(ArkUI.label("× %d" % int(person.bag.get(item.id, 0)), 12, MUTED))
		_ignore(contents)
	var detail := _panel(row)
	detail.size_flags_stretch_ratio = 0.9
	var info := _scroll(detail)
	info.add_child(_kicker("Oggetto selezionato"))
	_item_hero(info, selected)
	info.add_child(ArkUI.label(str(selected.name), 24, INK))
	info.add_child(ArkUI.paragraph(_item_description(selected), 15, MUTED))
	info.add_child(ArkUI.label("In borsa: %d" % int(person.bag.get(selected.id, 0)), 14, CYAN))
	if str(selected.effect) == "masterball":
		info.add_child(ArkUI.paragraph("La Masterball si usa soltanto durante una battaglia selvatica.", 14, MUTED))
	else:
		info.add_child(ArkUI.label("Usa su un compagno", 18, INK))
		for index: int in range(person.party.size()):
			var member: Dictionary = person.party[index]
			var button := _button("%s · %d / %d HP" % [member.name, int(member.hp), int(member.max_hp)], func() -> void: game.chosen_item = str(selected.id); game._apply_item(index))
			button.disabled = int(person.bag.get(selected.id, 0)) <= 0
			info.add_child(button)
	_footer(game)


static func build_details(game, member: Dictionary, back: Callable) -> void:
	_heading(game, "Scheda del compagno", "Analisi Arkamon", "Conosci il tuo compagno. Prepara la prossima mossa.")
	var row := _body(game)
	_hero(row, member, 1.0)
	var panel := _panel(row)
	panel.size_flags_stretch_ratio = 1.25
	var info := _scroll(panel)
	info.add_child(_kicker("Arkamon selezionato · Nº %03d" % int(member.species_id)))
	info.add_child(ArkUI.label(str(member.name), 27, INK))
	_health(info, member)
	_facts(info, [{"label": "Livello", "value": str(member.level)}, {"label": "Categoria", "value": str(game.rules.species[int(member.species_id)].categoria)}, {"label": "Tasso cattura", "value": "%d / 5" % int(game.rules.species[int(member.species_id)].get("tassoCattura", 0))}])
	info.add_child(ArkUI.label("Mosse al livello %d" % int(member.level), 20, INK))
	_moves(game, info, member)
	_evolution(game, info, member)
	_footer(game, back)


static func _open(game, view: String, value: Variant = null) -> void:
	game._clear_page(view)
	match view:
		"party": build_party(game, int(value) if value != null else 0)
		"box": build_box(game, str(value) if value != null else "")
		"dex": build_dex(game, int(value) if value != null else 0)
		"shop": build_shop(game)
		"bag": build_bag(game)


static func _heading(game, kicker: String, title: String, context: String = "") -> void:
	var row := ArkUI.hbox(12)
	game.page.add_child(row)
	var column := ArkUI.vbox(2)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)
	column.add_child(_kicker(kicker))
	column.add_child(ArkUI.label(title.to_upper(), 27, INK))
	if not context.is_empty():
		row.add_child(ArkUI.label(context, 15, MUTED))


static func _body(game) -> HBoxContainer:
	var row := ArkUI.hbox(18)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	game.page.add_child(row)
	return row


static func _column(parent: Node, ratio: float = 1.0) -> VBoxContainer:
	var column := ArkUI.vbox(5)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = ratio
	parent.add_child(column)
	return column


static func _panel(parent: Node, asset: String = "panel-medium", margin: int = 18) -> PanelContainer:
	var panel := ArkUI.panel()
	panel.add_theme_stylebox_override("panel", ArkUI.kit_style(asset, 97 if asset == "panel-medium" else 61, margin))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	return panel


static func _scroll(parent: Node, ratio: float = 1.0) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = ratio
	scroll.follow_focus = true
	parent.add_child(scroll)
	return _column(scroll)


static func _card_button(asset: String, action: Callable) -> Button:
	var button := ArkUI.button("", action)
	var slice: int = int({"card-default": 61, "card-selected-violet": 58, "slot-default": 62, "slot-selected": 60, "button-primary": 44, "button-default": 48}.get(asset, 61))
	var style := ArkUI.kit_style(asset, slice, 0)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("disabled", style)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button


static func _button_contents(button: Button, horizontal: int, vertical: int) -> VBoxContainer:
	var margin := MarginContainer.new()
	button.add_child(margin)
	ArkUI.fill(margin)
	margin.add_theme_constant_override("margin_left", horizontal)
	margin.add_theme_constant_override("margin_right", horizontal)
	margin.add_theme_constant_override("margin_top", vertical)
	margin.add_theme_constant_override("margin_bottom", vertical)
	var column := ArkUI.vbox(3)
	margin.add_child(column)
	return column


static func _button(text: String, action: Callable, icon_id: String = "", primary: bool = false) -> Button:
	var button := ArkUI.button(text, action, primary)
	button.custom_minimum_size.y = 36
	button.add_theme_font_size_override("font_size", 14)
	if not icon_id.is_empty():
		var path: String = "res://assets/ui/original/player-kit/%s.svg" % icon_id
		if ResourceLoader.exists(path):
			button.icon = load(path)
			button.expand_icon = true
			button.add_theme_constant_override("icon_max_width", 23)
	return button


static func _hero(parent: Node, member: Dictionary, ratio: float = 1.0, portrait_size: int = 230, discovery: String = "", reference_id: int = 0) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = ratio
	var style := StyleBoxFlat.new()
	style.bg_color = Color("10294488")
	style.border_color = Color("82add044")
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	style.content_margin_left = 10
	style.content_margin_right = 10
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var column := ArkUI.vbox(9)
	panel.add_child(column)
	column.add_child(ArkUI.label("ARKA / %03d" % int(member.get("species_id", reference_id)), 12, MUTED))
	var space_above := Control.new()
	space_above.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(space_above)
	if member.is_empty():
		var unknown := ArkUI.icon("icon-book", 100)
		unknown.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(unknown)
		var question := ArkUI.label("?", 72, CYAN)
		question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(question)
	else:
		var portrait := ArkUI.portrait(int(member.species_id), portrait_size)
		portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(portrait)
	var space_below := Control.new()
	space_below.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(space_below)
	var caption: String = discovery if not discovery.is_empty() else "Compagno selezionato · Lv. %d" % int(member.get("level", 5))
	var kicker := _kicker(caption if not member.is_empty() else "Da scoprire")
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(kicker)
	var name_label := ArkUI.label(str(member.get("name", "Specie da scoprire")).to_upper(), 27, INK)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(name_label)
	if not member.is_empty():
		var badge := ArkUI.typebadge(str(member.type))
		badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(badge)
	return panel


static func _health(parent: Node, member: Dictionary, compact: bool = false) -> void:
	var column := ArkUI.vbox(2)
	parent.add_child(column)
	var line: Container = ArkUI.hbox(6) if compact else column
	if compact:
		column.add_child(line)
	var bar := ProgressBar.new()
	bar.max_value = maxi(1, int(member.max_hp))
	bar.value = int(member.hp)
	bar.show_percentage = false
	bar.custom_minimum_size.y = 8
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var background := StyleBoxFlat.new()
	background.bg_color = Color("0c192a")
	background.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", background)
	var fill := background.duplicate() as StyleBoxFlat
	var fraction: float = float(member.hp) / maxf(1, float(member.max_hp))
	fill.bg_color = Color("1fab77") if fraction > 0.5 else (Color("e5ad36") if fraction > 0.25 else Color("e45166"))
	bar.add_theme_stylebox_override("fill", fill)
	line.add_child(bar)
	line.add_child(ArkUI.label("%d / %d HP" % [int(member.hp), int(member.max_hp)], 11 if compact else 13, MUTED))


static func _small_typebadge(type: String) -> Control:
	var badge := ArkUI.typebadge(type)
	if badge is PanelContainer:
		var style := ArkUI.box(Color("0f2340"), 4, Color("527ba8"))
		style.content_margin_left = 4
		style.content_margin_right = 4
		style.content_margin_top = 1
		style.content_margin_bottom = 1
		badge.add_theme_stylebox_override("panel", style)
		var row: HBoxContainer = badge.get_child(0)
		(row.get_child(0) as Control).custom_minimum_size = Vector2(12, 12)
		(row.get_child(1) as Label).add_theme_font_size_override("font_size", 11)
	return badge


static func _moves(game, parent: Node, member: Dictionary) -> void:
	for move: Dictionary in game.rules.available_moves(member):
		var row := ArkUI.hbox(7)
		parent.add_child(row)
		var copy := _column(row)
		copy.add_child(ArkUI.label(str(move.name), 16, INK))
		copy.add_child(ArkUI.typebadge(str(move.type)))
		var effect: String = str(move.get("effect", ""))
		var value: String = "%dd6 +%d" % [int(move.dice), int(move.bonus)]
		if effect in ["CURA", "CURA_PCT"]:
			value = "Cura %d%s" % [int(move.get("value", 0)), "%" if effect == "CURA_PCT" else " HP"]
		elif bool(move.get("status_only", false)):
			value = "Stato"
		row.add_child(ArkUI.label(value, 14, CYAN))


static func _facts(parent: Node, entries: Array) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	parent.add_child(grid)
	for entry: Dictionary in entries:
		var column := ArkUI.vbox(2)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(column)
		column.add_child(ArkUI.label(str(entry.label), 12, MUTED))
		column.add_child(ArkUI.label(str(entry.value), 17, INK))


static func _evolution(game, parent: Node, member: Dictionary) -> void:
	var definition: Dictionary = game.rules.species[int(member.species_id)]
	if int(definition.get("evoluzioneId", 0)) > 0:
		parent.add_child(ArkUI.paragraph("Linea evolutiva · Prossima forma dal livello %d." % int(definition.get("livelloEvoluzione", 0)), 14, MUTED))
	else:
		parent.add_child(ArkUI.paragraph("Questa forma non ha ulteriori evoluzioni.", 14, MUTED))


static func _dex_evolution(game, parent: Node, species_id: int, person: Dictionary) -> void:
	var first: int = species_id
	var visited: Array = [first]
	while true:
		var previous: int = 0
		for definition: Dictionary in game.rules.species.values():
			if int(definition.get("evoluzioneId", 0)) == first:
				previous = int(definition.id)
		if previous == 0 or previous in visited:
			break
		visited.append(previous)
		first = previous
	var row := ArkUI.hbox(8)
	parent.add_child(row)
	visited.clear()
	var current: int = first
	var previous_level: int = 0
	var previous_known: bool = false
	while current > 0 and current not in visited and game.rules.species.has(current):
		visited.append(current)
		var definition: Dictionary = game.rules.species[current]
		var column := _column(row)
		if _known(person, current):
			column.add_child(ArkUI.portrait(current, 65))
		else:
			column.add_child(ArkUI.icon("circle-default", 65))
		column.add_child(ArkUI.label(str(definition.nome) if _known(person, current) else "Da scoprire", 12, INK))
		column.add_child(ArkUI.label("Base" if visited.size() == 1 else ("Lv. %d" % previous_level if previous_known else "Da scoprire"), 12, MUTED))
		previous_level = int(definition.get("livelloEvoluzione", 0))
		previous_known = _known(person, current)
		current = int(definition.get("evoluzioneId", 0))


static func _item_hero(parent: Node, item: Dictionary) -> void:
	var icon := ArkUI.icon(str(ITEM_ICONS.get(str(item.id), "item-sphere")), 140)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	parent.add_child(icon)


static func _box_filters(game, parent: Node, selected_slot: String) -> void:
	var row := ArkUI.hbox(6)
	parent.add_child(row)
	var search := LineEdit.new()
	search.placeholder_text = "Nome o numero"
	search.text = str(game.get_meta("site_box_search", ""))
	search.custom_minimum_size = Vector2(130, 32)
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_compact_field(search)
	search.text_submitted.connect(func(value: String) -> void: game.set_meta("site_box_search", value); _open(game, "box", selected_slot))
	row.add_child(search)
	var type_picker := _type_picker(str(game.get_meta("site_box_type", "")))
	type_picker.item_selected.connect(func(index: int) -> void: game.set_meta("site_box_type", str(type_picker.get_item_metadata(index))); _open(game, "box", selected_slot))
	row.add_child(type_picker)
	var condition := OptionButton.new()
	for label: String in ["Tutte", "In salute", "Status", "KO"]:
		condition.add_item(label)
	condition.select(int(game.get_meta("site_box_condition", 0)))
	_compact_field(condition)
	condition.item_selected.connect(func(index: int) -> void: game.set_meta("site_box_condition", index); _open(game, "box", selected_slot))
	row.add_child(condition)
	var level_row := ArkUI.hbox(6)
	parent.add_child(level_row)
	level_row.add_child(ArkUI.label("Livello min.", 12, MUTED))
	var minimum := SpinBox.new()
	minimum.min_value = 5
	minimum.max_value = 100
	minimum.value = int(game.get_meta("site_box_min", 5))
	minimum.custom_minimum_size = Vector2(65, 30)
	_compact_field(minimum)
	minimum.value_changed.connect(func(value: float) -> void: game.set_meta("site_box_min", int(value)); _open(game, "box", selected_slot))
	level_row.add_child(minimum)
	level_row.add_child(ArkUI.label("Livello max.", 12, MUTED))
	var maximum := SpinBox.new()
	maximum.min_value = 5
	maximum.max_value = 100
	maximum.value = int(game.get_meta("site_box_max", 100))
	maximum.custom_minimum_size = Vector2(65, 30)
	_compact_field(maximum)
	maximum.value_changed.connect(func(value: float) -> void: game.set_meta("site_box_max", int(value)); _open(game, "box", selected_slot))
	level_row.add_child(maximum)
	level_row.add_child(_button("Azzera filtri", func() -> void:
		for key: String in ["site_box_search", "site_box_type", "site_box_condition", "site_box_min", "site_box_max"]:
			game.remove_meta(key)
		_open(game, "box", selected_slot)))


static func _box_matches(game, member: Dictionary) -> bool:
	var query: String = str(game.get_meta("site_box_search", "")).strip_edges().to_lower()
	var type: String = str(game.get_meta("site_box_type", ""))
	var condition: int = int(game.get_meta("site_box_condition", 0))
	var status: String = game.rules.status_name(member)
	return (query.is_empty() or str(member.name).to_lower().contains(query) or str(member.species_id).contains(query)) and (type.is_empty() or str(member.type) == type) and int(member.level) >= int(game.get_meta("site_box_min", 5)) and int(member.level) <= int(game.get_meta("site_box_max", 100)) and (condition == 0 or (condition == 1 and int(member.hp) > 0 and status.is_empty()) or (condition == 2 and not status.is_empty()) or (condition == 3 and int(member.hp) == 0))


static func _type_picker(selected: String = "") -> OptionButton:
	var picker := OptionButton.new()
	picker.add_item("Tutti i tipi")
	picker.set_item_metadata(0, "")
	for type: String in ["Normale", "Elettro", "Fuoco", "Terra", "Acqua", "Erba", "Oscurità", "Psico"]:
		picker.add_item(type)
		picker.set_item_metadata(picker.item_count - 1, type)
		if type == selected:
			picker.select(picker.item_count - 1)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_compact_field(picker)
	return picker


## Local controls keep the source's compact text metrics without changing the host theme.
static func _compact_field(control: Control) -> void:
	var field: Control = control.get_line_edit() if control is SpinBox else control
	field.add_theme_font_size_override("font_size", 14)
	if field is OptionButton:
		for state: String in ["normal", "hover", "pressed", "disabled"]:
			field.add_theme_stylebox_override(state, ArkUI.kit_style("button-default", 48, 6))
	elif field is LineEdit:
		var style := ArkUI.box(Color("0d1e34"), 6, Color("5285b5"))
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 5
		style.content_margin_bottom = 5
		field.add_theme_stylebox_override("normal", style)


static func _item_description(item: Dictionary) -> String:
	return str({"potion": "Recupera il 25% degli HP massimi di un Arkamon vivo. Non cura gli status.", "super-potion": "Recupera il 50% degli HP massimi di un Arkamon vivo. Non cura gli status.", "revive": "Rianima un Arkamon KO con il 50% degli HP massimi. Gli status restano.", "antidote": "Rimuove lo status Avvelenato da un Arkamon vivo.", "paralysis-heal": "Rimuove lo status Paralizzato da un Arkamon vivo.", "awakening": "Rimuove lo status Addormentato da un Arkamon vivo.", "masterball": "Cattura garantita di un Arkamon selvatico. Si usa soltanto durante una battaglia selvatica."}.get(str(item.id), ""))


static func _cart_contents(game, parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
	var count: int = 0
	for item: Dictionary in game.model.catalog:
		var quantity: int = int(game.cart.get(item.id, 0))
		if quantity <= 0:
			continue
		count += quantity
		var row := ArkUI.hbox(7)
		parent.add_child(row)
		row.add_child(ArkUI.icon(str(ITEM_ICONS.get(str(item.id), "item-sphere")), 24))
		var text := ArkUI.paragraph("%s ×%d" % [item.name, quantity], 14, INK)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		row.add_child(ArkUI.label("%d ₳" % (quantity * int(item.price)), 14, GOLD))
	if count == 0:
		parent.add_child(ArkUI.paragraph("Il carrello è vuoto. Scegli le quantità nel catalogo.", 14, MUTED))


static func _known(person: Dictionary, id: int) -> bool:
	return id in person.dex_seen or str(id) in person.dex_seen


static func _level_range(team: Array) -> Vector2i:
	if team.is_empty():
		return Vector2i.ZERO
	var result := Vector2i(100, 5)
	for member: Dictionary in team:
		result.x = mini(result.x, int(member.level))
		result.y = maxi(result.y, int(member.level))
	return result


static func _kicker(text: String) -> Label:
	return ArkUI.label(text.to_upper(), 11, CYAN)


static func _footer(game, back: Callable = Callable()) -> void:
	var row := ArkUI.hbox(12)
	game.page.add_child(row)
	row.add_child(ArkUI.label("Turno di G%d · %d azioni disponibili" % [int(game.model.state.active_player) + 1, int(game.model.state.actions_left)], 12, MUTED))
	row.add_child(ArkUI.spacer())
	row.add_child(ArkUI.label("Esc · Torna al viaggio", 12, MUTED))
	row.add_child(_button("Riprendi il viaggio", game._return_to_campaign if not back.is_valid() else back, "icon-home", true))
	game._focus_first()


static func _ignore(node: Node, include_self: bool = true) -> void:
	if include_self and node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children():
		_ignore(child)

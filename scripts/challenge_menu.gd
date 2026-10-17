class_name ChallengeMenu
extends Control
## Independent challenge setup. Emits canonical initial teams; never writes campaign data.

signal battle_requested(descriptor: Dictionary)
signal back_requested

const Model = preload("res://scripts/core/challenge_model.gd")
var model: ChallengeModel
var rules: BattleRules
var descriptor: Dictionary = {}
var seed_input: LineEdit
var mode_picker: OptionButton
var version_picker: OptionButton
var slots: Array[OptionButton] = []
var budget_label: Label
var feedback: Label
var preview_label: Label
var code_input: TextEdit
var ranking: VBoxContainer
var start_button: Button
var _building: bool = false


func setup(battle_rules: BattleRules) -> void:
	rules = battle_rules
	model = Model.new()
	model.configure(rules)
	if is_inside_tree():
		_build()


func _ready() -> void:
	if rules == null:
		rules = BattleRules.new()
		rules.load_data()
		setup(rules)
	else:
		_build()


func _build() -> void:
	_building = true
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	slots.clear()
	theme = ArkUI.make_theme()
	var background: ColorRect = ColorRect.new()
	background.color = ArkUI.INK
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	ArkUI.fill(background)
	var outer_scroll: ScrollContainer = ScrollContainer.new()
	outer_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(outer_scroll)
	ArkUI.fill(outer_scroll)
	var margin: MarginContainer = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_scroll.add_child(margin)
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	var page: VBoxContainer = ArkUI.vbox(12)
	margin.add_child(page)
	var header: HBoxContainer = ArkUI.hbox()
	page.add_child(header)
	header.add_child(ArkUI.label("SFIDE E FANTA-TEAM", 30, ArkUI.GOLD))
	header.add_child(ArkUI.spacer())
	header.add_child(ArkUI.button("← Torna al titolo", func() -> void: back_requested.emit()))
	page.add_child(ArkUI.paragraph("Sei Arkamon al livello 20, cento crediti, nessuna specie ripetuta. Le sfide hanno una classifica locale separata dalla campagna.", 19))
	var controls: HBoxContainer = ArkUI.hbox()
	page.add_child(controls)
	controls.add_child(ArkUI.label("Seed", 20, ArkUI.MINT))
	seed_input = LineEdit.new()
	seed_input.text = "ARKAMON-2026"
	seed_input.placeholder_text = "Da 1 a 64 caratteri"
	seed_input.max_length = 128
	seed_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(seed_input)
	mode_picker = OptionButton.new()
	mode_picker.add_item("Sfida a seed", 0)
	mode_picker.add_item("Fanta-Team", 1)
	controls.add_child(mode_picker)
	version_picker = OptionButton.new()
	version_picker.add_item("Regole aggiornate v2", 2)
	version_picker.add_item("Regole classiche v1", 1)
	controls.add_child(version_picker)
	controls.add_child(ArkUI.button("Prepara sfida", _prepare, true))
	var content: HBoxContainer = ArkUI.hbox(18)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(content)
	var team_panel: PanelContainer = ArkUI.panel()
	team_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(team_panel)
	var team_column: VBoxContainer = ArkUI.vbox(8)
	team_panel.add_child(team_column)
	team_column.add_child(ArkUI.label("LA TUA SQUADRA", 20, ArkUI.MINT))
	budget_label = ArkUI.label("Budget 100 crediti", 19, ArkUI.GOLD)
	team_column.add_child(budget_label)
	var ids: Array = rules.species.keys()
	ids.sort()
	for index: int in range(6):
		var row: HBoxContainer = ArkUI.hbox(8)
		team_column.add_child(row)
		row.add_child(ArkUI.label(str(index + 1), 18, ArkUI.MUTED))
		var picker: OptionButton = OptionButton.new()
		picker.custom_minimum_size.y = 40
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(picker)
		for id: int in ids:
			picker.add_item("%03d · %s · %d crediti" % [id, str(rules.species[id].nome), model.species_cost(id)], id)
		picker.select(index)
		picker.item_selected.connect(_selection_changed)
		slots.append(picker)
	preview_label = ArkUI.paragraph("", 17, ArkUI.TEXT)
	team_column.add_child(preview_label)
	var right: VBoxContainer = ArkUI.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(right)
	var share_panel: PanelContainer = ArkUI.panel()
	right.add_child(share_panel)
	var share: VBoxContainer = ArkUI.vbox(8)
	share_panel.add_child(share)
	share.add_child(ArkUI.label("CONDIVIDI LA CONFIGURAZIONE", 19, ArkUI.MINT))
	code_input = TextEdit.new()
	code_input.custom_minimum_size.y = 120
	code_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	code_input.placeholder_text = "Incolla qui il codice JSON di una sfida Beta o Godot."
	share.add_child(code_input)
	var share_buttons: HBoxContainer = ArkUI.hbox()
	share.add_child(share_buttons)
	share_buttons.add_child(ArkUI.button("Copia codice", _copy_code))
	share_buttons.add_child(ArkUI.button("Importa codice", _import_code))
	var ranking_panel: PanelContainer = ArkUI.panel()
	ranking_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(ranking_panel)
	var ranking_column: VBoxContainer = ArkUI.vbox(8)
	ranking_panel.add_child(ranking_column)
	ranking_column.add_child(ArkUI.label("CLASSIFICA DI QUESTA CONFIGURAZIONE", 17, ArkUI.GOLD))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ranking_column.add_child(scroll)
	ranking = ArkUI.vbox(8)
	ranking.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(ranking)
	feedback = ArkUI.label("", 18, ArkUI.MINT)
	page.add_child(feedback)
	page.add_child(ArkUI.paragraph("Stessi seed e regole generano le stesse squadre della Beta. I tiri di combattimento usano il generatore di Godot: i risultati non sono confrontabili tra motori.", 16))
	start_button = ArkUI.button("Inizia la sfida →", _launch, true)
	page.add_child(start_button)
	seed_input.text_changed.connect(func(_text: String) -> void: _invalidate())
	mode_picker.item_selected.connect(_selection_changed)
	version_picker.item_selected.connect(_version_changed)
	_building = false
	_prepare()


func _version() -> int:
	return version_picker.get_selected_id()


func _ids() -> Array:
	var ids: Array = []
	for picker: OptionButton in slots:
		ids.append(picker.get_selected_id())
	return ids


func _selection_changed(_index: int = 0) -> void:
	if _building:
		return
	_invalidate()
	_update_budget()


func _version_changed(_index: int) -> void:
	_building = true
	_refresh_prices()
	_building = false
	_invalidate()
	_update_budget()


func _refresh_prices() -> void:
	for picker: OptionButton in slots:
		for item_index: int in range(picker.item_count):
			var id: int = picker.get_item_id(item_index)
			picker.set_item_text(item_index, "%03d · %s · %d crediti" % [id, str(rules.species[id].nome), model.species_cost(id, _version())])


func _invalidate() -> void:
	if _building:
		return
	descriptor = {}
	start_button.disabled = true
	feedback.text = "Premi Prepara sfida per aggiornare squadre e codice."
	feedback.add_theme_color_override("font_color", ArkUI.MUTED)


func _prepare() -> void:
	var prepared: Dictionary = model.create(seed_input.text, _ids(), "fantateam" if mode_picker.selected == 1 else "challenge", _version())
	if not prepared.ok:
		descriptor = {}
		start_button.disabled = true
		_feedback(str(prepared.message), true)
		_update_budget()
		return
	_apply_descriptor(prepared)


func _apply_descriptor(prepared: Dictionary) -> void:
	descriptor = prepared
	_building = true
	seed_input.text = str(descriptor.seed)
	mode_picker.select(1 if str(descriptor.mode) == "fanta" else 0)
	version_picker.select(0 if int(descriptor.version) == 2 else 1)
	_refresh_prices()
	for index: int in range(slots.size()):
		var picker: OptionButton = slots[index]
		picker.select(picker.get_item_index(int(descriptor.team_ids[index])))
	code_input.text = str(descriptor.code)
	_building = false
	start_button.disabled = false
	_update_budget()
	var enemy_names: PackedStringArray = PackedStringArray()
	for creature: Dictionary in descriptor.enemy:
		enemy_names.append(str(creature.name))
	preview_label.text = "AVVERSARI\n" + ", ".join(enemy_names)
	_feedback("Sfida pronta · %s · seed %s" % [str(descriptor.id), str(descriptor.seed)])
	_show_ranking()


func _update_budget() -> void:
	var is_fanta: bool = mode_picker.selected == 1
	for picker: OptionButton in slots:
		picker.disabled = not is_fanta
	var checked: Dictionary = model.validate_team(_ids(), true, _version())
	budget_label.text = "%d / 100 crediti · Livello 20" % model.team_cost(_ids(), _version())
	budget_label.add_theme_color_override("font_color", ArkUI.GOLD if checked.ok else ArkUI.RED)


func _copy_code() -> void:
	if descriptor.is_empty():
		_prepare()
	if not descriptor.is_empty():
		DisplayServer.clipboard_set(str(descriptor.code))
		_feedback("Codice copiato. Condivide seed, squadra e versione delle regole.")


func _import_code() -> void:
	var imported: Dictionary = model.decode(code_input.text)
	if not imported.ok:
		_feedback(str(imported.message), true)
		return
	_apply_descriptor(imported)


func _launch() -> void:
	if descriptor.is_empty():
		_prepare()
	if descriptor.is_empty():
		return
	# Each launch is a separate attempt, while the configuration ID stays fixed.
	var fresh: Dictionary = model.decode(str(descriptor.code))
	if fresh.ok:
		descriptor = fresh
		battle_requested.emit(fresh.duplicate(true))


func refresh() -> void:
	if model:
		model.load_results()
	if is_instance_valid(ranking):
		_show_ranking()


func show_result(value: Dictionary, won: bool, turns: int, remaining_hp: int = 0) -> Dictionary:
	var recorded: Dictionary = model.record_result(value, won, turns, remaining_hp)
	if recorded.ok:
		descriptor = value.duplicate(true)
	if is_instance_valid(feedback):
		_feedback(str(recorded.message), not bool(recorded.ok))
		_show_ranking()
	return recorded


func _show_ranking() -> void:
	for child: Node in ranking.get_children():
		ranking.remove_child(child)
		child.queue_free()
	var entries: Array = model.leaderboard(descriptor)
	if entries.is_empty():
		ranking.add_child(ArkUI.paragraph("Nessun risultato per questo seed, squadra e versione delle regole.", 17))
	else:
		for index: int in range(entries.size()):
			var entry: Dictionary = entries[index]
			ranking.add_child(ArkUI.paragraph("%d. %s · %d turni · %d PV rimasti" % [index + 1, str(entry.outcome), int(entry.turns), int(entry.remainingHp)], 17, ArkUI.TEXT))
	if not model.storage_warning.is_empty():
		ranking.add_child(ArkUI.paragraph(model.storage_warning, 17, ArkUI.RED))


func _feedback(message: String, error: bool = false) -> void:
	feedback.text = message
	feedback.add_theme_color_override("font_color", ArkUI.RED if error else ArkUI.MINT)

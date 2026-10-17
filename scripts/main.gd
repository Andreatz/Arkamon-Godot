extends Control

const Burst := preload("res://scripts/attack_burst.gd")
const SAVE_PATH := "user://campaign.json"
const PREFS_PATH := "user://preferences.cfg"
const LOCATIONS := ["Laboratorio", "Prato dei sussurri", "Sorgente", "Bosco di cenere", "La radura"]

var rules: BattleRules
var rng := RandomNumberGenerator.new()
var prototype: Dictionary = {}
var campaign: Dictionary = {}
var screen: String = "title"
var page: VBoxContainer
var shell: MarginContainer
var backdrop: TextureRect
var toast_label: Label
var sound: AudioStreamPlayer
var sound_enabled: bool = true
var reduced_motion: bool = false
var busy: bool = false
var fast_mode: bool = false
var save_path: String = SAVE_PATH
var preferences_path: String = PREFS_PATH
var testing: bool = false
var enemy: Dictionary = {}
var battle_step: int = 0
var battle_finished: bool = false
var player_actor: CreatureActor
var enemy_actor: CreatureActor
var player_hp: ProgressBar
var enemy_hp: ProgressBar
var player_health: Label
var enemy_health: Label
var battle_message: Label
var dice_row: HBoxContainer
var action_buttons: Array[Button] = []
var action_panel: VBoxContainer
var arena: Control
var inventory_label: Label
var player_summary: Label
var battle_log_scroll: ScrollContainer
var turn_count: int = 0
var history: Array[String] = []

func _ready() -> void:
	theme = ArkUI.make_theme()
	rng.randomize()
	var smoke_requested := "--smoke-test" in OS.get_cmdline_user_args()
	if smoke_requested:
		testing = true
		save_path = "user://smoke-test/campaign.json"
		preferences_path = "user://smoke-test/preferences.cfg"
	if not testing:
		_load_preferences()
	fast_mode = fast_mode or smoke_requested
	if fast_mode:
		rng.seed = 19671017
		sound_enabled = false
	rules = BattleRules.new()
	if not rules.load_data():
		var problem := ArkUI.paragraph("Impossibile caricare i dati di Arkamon. Apri il progetto completo, includendo la cartella data.", 26)
		add_child(problem)
		ArkUI.fill(problem)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/prototype.json"))
	if parsed is Dictionary:
		prototype = parsed
	if not prototype.has("starters"):
		prototype["starters"] = [1, 5, 9]
	if not prototype.has("encounters"):
		prototype["encounters"] = [28, 32, 42, 56]
	sound = AudioStreamPlayer.new()
	sound.volume_db = -9.0
	add_child(sound)
	_build_shell()
	_show_title()
	if smoke_requested:
		_run_smoke_test.call_deferred()
	elif "--screenshot" in OS.get_cmdline_user_args():
		_take_preview.call_deferred()

func _build_shell() -> void:
	var base := ColorRect.new()
	base.color = ArkUI.INK
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)
	ArkUI.fill(base)
	backdrop = ArkUI.texture("res://assets/backgrounds/laboratory.webp")
	add_child(backdrop)
	ArkUI.fill(backdrop)
	backdrop.modulate = Color(0.22, 0.31, 0.35)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.06, 0.1, 0.45)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	ArkUI.fill(shade)
	shell = MarginContainer.new()
	add_child(shell)
	ArkUI.fill(shell)
	for edge in ["left", "right"]:
		shell.add_theme_constant_override("margin_" + edge, 40)
	shell.add_theme_constant_override("margin_top", 24)
	shell.add_theme_constant_override("margin_bottom", 20)
	page = ArkUI.vbox(18)
	shell.add_child(page)
	toast_label = ArkUI.label("", 17, ArkUI.MINT)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	toast_label.offset_top = -27
	toast_label.offset_bottom = -3
	add_child(toast_label)

func _clear_page(next_screen: String) -> void:
	screen = next_screen
	for child in page.get_children():
		page.remove_child(child)
		child.queue_free()
	action_buttons.clear()
	toast_label.text = ""
	var header := ArkUI.hbox(16)
	header.add_child(ArkUI.label("◈  A R K A M O N", 26, ArkUI.GOLD))
	header.add_child(ArkUI.spacer())
	if not campaign.is_empty() and next_screen != "title":
		inventory_label = ArkUI.label("", 18, ArkUI.MUTED)
		header.add_child(inventory_label)
		_refresh_inventory()
	var mute := ArkUI.button("Audio: sì" if sound_enabled else "Audio: no", _toggle_sound)
	mute.custom_minimum_size.y = 42
	header.add_child(mute)
	var full := ArkUI.button("Schermo intero", _toggle_fullscreen)
	full.custom_minimum_size.y = 42
	header.add_child(full)
	page.add_child(header)

func _background(name: String) -> void:
	var path := "res://assets/backgrounds/%s.webp" % name
	if ResourceLoader.exists(path):
		backdrop.texture = load(path)

func _heading(kicker: String, title: String, description: String = "") -> void:
	page.add_child(ArkUI.label(kicker.to_upper(), 16, ArkUI.MINT))
	page.add_child(ArkUI.label(title, 40))
	if not description.is_empty():
		page.add_child(ArkUI.paragraph(description, 20))

func _show_title() -> void:
	busy = false
	_background("laboratory")
	_clear_page("title")
	var content := ArkUI.hbox(36)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(content)
	var intro := ArkUI.vbox(18)
	intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	intro.size_flags_stretch_ratio = 1.15
	content.add_child(intro)
	var upper_space := Control.new()
	upper_space.custom_minimum_size.y = 50
	intro.add_child(upper_space)
	intro.add_child(ArkUI.label("IL PRIMO VIAGGIO", 18, ArkUI.MINT))
	intro.add_child(ArkUI.label("Un legame.\nUn lancio.\nLa tua avventura.", 60))
	intro.add_child(ArkUI.paragraph("Scegli il tuo Arkamon, attraversa il bosco e lascia che i dadi scrivano la prossima mossa.", 23))
	var play := ArkUI.button("Inizia il viaggio  →", _request_new_game, true)
	intro.add_child(play)
	var resume := ArkUI.button("Riprendi il viaggio", _continue_game)
	resume.disabled = not SaveStore.has_save(save_path)
	intro.add_child(resume)
	var options := ArkUI.hbox()
	options.add_child(ArkUI.button("Impostazioni", _show_settings))
	options.add_child(ArkUI.button("Esci", func() -> void: get_tree().quit()))
	intro.add_child(options)
	var hero_panel := ArkUI.panel()
	hero_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(hero_panel)
	var hero_column := ArkUI.vbox()
	hero_panel.add_child(hero_column)
	var hero := CreatureActor.new()
	hero.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero_column.add_child(hero)
	hero.setup(5, false, not reduced_motion)
	hero_column.add_child(ArkUI.label("DARKLAW", 30, ArkUI.GOLD))
	hero_column.add_child(ArkUI.paragraph("Il bosco custodisce incontri, alleati e una sfida finale. Ogni scelta lascia il segno.", 21))
	page.add_child(ArkUI.label("Avventura breve · Combattimenti a turni · Salvataggio automatico", 17, ArkUI.MUTED))
	_focus_first()

func _request_new_game() -> void:
	if SaveStore.has_save(save_path):
		var dialog := ConfirmationDialog.new()
		dialog.title = "Iniziare un nuovo viaggio?"
		dialog.dialog_text = "Il viaggio salvato verrà sostituito quando sceglierai il nuovo compagno."
		dialog.ok_button_text = "Scegli il compagno"
		dialog.cancel_button_text = "Annulla"
		dialog.confirmed.connect(_show_starters)
		dialog.confirmed.connect(dialog.queue_free)
		dialog.canceled.connect(dialog.queue_free)
		add_child(dialog)
		dialog.popup_centered(Vector2i(540, 190))
	else:
		_show_starters()

func _show_starters() -> void:
	_background("laboratory")
	_clear_page("starters")
	_heading("Il laboratorio", "Con chi partirai?", "Tre compagni, tre modi di affrontare il viaggio. Tutti iniziano al livello 5.")
	var cards := ArkUI.hbox(20)
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(cards)
	for raw_id in prototype.starters:
		var id := int(raw_id)
		var creature: Dictionary = rules.creature(id, 5)
		var card := ArkUI.panel()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cards.add_child(card)
		var column := ArkUI.vbox(16)
		card.add_child(column)
		column.add_child(ArkUI.label(String(creature.type).to_upper(), 17, ArkUI.type_color(creature.type)))
		var actor := CreatureActor.new()
		actor.size_flags_vertical = Control.SIZE_EXPAND_FILL
		actor.custom_minimum_size.y = 230
		column.add_child(actor)
		actor.setup(id, false, not reduced_motion)
		column.add_child(ArkUI.label(creature.name, 32))
		column.add_child(ArkUI.label("%d punti vita · Dadi D6" % int(creature.max_hp), 19, ArkUI.MUTED))
		var move_names := PackedStringArray()
		for move in rules.available_moves(creature):
			move_names.append(String(move.name))
		column.add_child(ArkUI.paragraph("Mosse: " + ", ".join(move_names), 18))
		column.add_child(ArkUI.button("Scegli " + String(creature.name), _new_game.bind(id), true))
	page.add_child(ArkUI.button("← Torna al titolo", _show_title))
	_focus_first()

func _new_game(id: int) -> void:
	campaign = {"starter": id, "party": [rules.creature(id, 5)], "active": 0,
		"checkpoint": 0, "coins": 0, "potions": 3, "orbs": 6,
		"wins": 0, "captures": 0, "completed": false}
	_save()
	_play("confirm")
	_show_world()

func _continue_game() -> void:
	var loaded: Dictionary = SaveStore.load_game(save_path)
	if not _valid_campaign(loaded):
		_notify("Il salvataggio non è leggibile. Puoi iniziare un nuovo viaggio.", true)
		return
	campaign = loaded
	# Rebuild move/stat definitions from the bundled catalogue; only progress is restored.
	var party: Array = []
	for member in campaign.party:
		var rebuilt: Dictionary = rules.creature(int(member.species_id), int(member.level))
		rebuilt.hp = clampi(int(member.hp), 0, int(rebuilt.max_hp))
		party.append(rebuilt)
	campaign.party = party
	_show_world()
	_notify("Viaggio ripreso.")

func _valid_campaign(value: Dictionary) -> bool:
	for key in ["starter", "active", "checkpoint", "coins", "potions", "orbs", "wins", "captures", "completed", "party"]:
		if not value.has(key):
			return false
	if not value.party is Array or value.party.is_empty() or value.party.size() > 6:
		return false
	if not value.completed is bool:
		return false
	for key in ["starter", "active", "checkpoint", "coins", "potions", "orbs", "wins", "captures"]:
		if not (value[key] is int or value[key] is float):
			return false
		if float(value[key]) != float(int(value[key])) or int(value[key]) < 0 or int(value[key]) > 99999:
			return false
	if int(value.active) >= value.party.size() or int(value.checkpoint) > 4:
		return false
	for member in value.party:
		if not member is Dictionary:
			return false
		for key in ["species_id", "level", "hp"]:
			if not member.has(key) or not (member[key] is int or member[key] is float):
				return false
		if not rules.species.has(int(member.species_id)) or int(member.level) < 5 or int(member.level) > 100:
			return false
	return true

func _active() -> Dictionary:
	return campaign.party[int(campaign.active)]

func _show_world() -> void:
	busy = false
	_background("route_1")
	_clear_page("world")
	_heading("Spedizione · %d / 4 tappe" % int(campaign.checkpoint), "Il sentiero ti aspetta", "Scegli una tappa illuminata. Puoi tornare al laboratorio o alla sorgente per recuperare le forze.")
	var row := ArkUI.hbox(20)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(row)
	var map_panel := ArkUI.panel()
	map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_panel.size_flags_stretch_ratio = 2.2
	row.add_child(map_panel)
	var map_column := ArkUI.vbox()
	map_panel.add_child(map_column)
	map_column.add_child(ArkUI.label("PERCORSO 1", 18, ArkUI.GOLD))
	var board := MapBoard.new()
	board.progress = int(campaign.checkpoint)
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.custom_minimum_size.y = 300
	map_column.add_child(board)
	board.stop_selected.connect(_select_stop)
	map_column.add_child(ArkUI.label("1  Cura     2  Incontro     3  Riposo     4  Incontro     5  Sfida finale", 15, ArkUI.MUTED))
	var info := ArkUI.panel()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var column := ArkUI.vbox(10)
	info.add_child(column)
	column.add_child(ArkUI.label("IL TUO COMPAGNO", 16, ArkUI.MINT))
	var member: Dictionary = _active()
	column.add_child(ArkUI.label(String(member.name), 28))
	column.add_child(ArkUI.label("%s · Livello %d" % [member.type, int(member.level)], 18, ArkUI.type_color(member.type)))
	var actor := CreatureActor.new()
	actor.custom_minimum_size.y = 160
	actor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(actor)
	actor.setup(int(member.species_id), false, not reduced_motion)
	column.add_child(ArkUI.label("PV  %d / %d" % [int(member.hp), int(member.max_hp)], 21))
	column.add_child(ArkUI.button("Squadra · %d / 6" % campaign.party.size(), _show_party))
	var next_step := mini(int(campaign.checkpoint) + 1, 4)
	column.add_child(ArkUI.button("Vai: " + LOCATIONS[next_step], _select_stop.bind(next_step), true))
	if bool(campaign.completed):
		column.add_child(ArkUI.button("Rivedi il viaggio", _show_complete))
	var footer := ArkUI.hbox()
	footer.add_child(ArkUI.button("Salva il viaggio", func() -> void: _save(true)))
	footer.add_child(ArkUI.button("Guida ai dadi", _show_help))
	footer.add_child(ArkUI.spacer())
	footer.add_child(ArkUI.button("Torna al titolo", _show_title))
	page.add_child(footer)
	_focus_first()

func _select_stop(index: int) -> void:
	if busy or index < 0 or index > 4 or index > int(campaign.checkpoint) + 1:
		return
	if index == 0 or index == 2:
		for member in campaign.party:
			rules.heal(member)
		campaign.checkpoint = maxi(int(campaign.checkpoint), index)
		_save()
		_show_world()
		_play("heal")
		_notify("Squadra curata. Tutti pronti a ripartire!")
		return
	if int(_active().hp) <= 0:
		_notify("Il tuo compagno è esausto. Riposa al laboratorio o alla sorgente.", true)
		return
	_start_battle(index)

func _start_battle(index: int) -> void:
	battle_step = index
	var encounter_index := 0 if index == 1 else (1 if index == 3 else 3)
	if index == 1 and rng.randi_range(0, 1) == 1:
		encounter_index = 2
	var enemy_id := int(prototype.encounters[encounter_index % prototype.encounters.size()])
	var level := 5 if index == 1 else (6 if index == 3 else 7)
	enemy = rules.creature(enemy_id, level)
	battle_finished = false
	turn_count = 1
	history.clear()
	busy = false
	_show_battle()
	_log("Un %s selvatico si avvicina. Scegli la tua mossa." % enemy.name)

func _show_battle() -> void:
	_background("battle_forest")
	_clear_page("battle")
	var title_row := ArkUI.hbox()
	title_row.add_child(ArkUI.label(LOCATIONS[battle_step], 29))
	title_row.add_child(ArkUI.spacer())
	title_row.add_child(ArkUI.label("INCONTRO SELVATICO", 16, ArkUI.GOLD))
	page.add_child(title_row)
	var stage_panel := ArkUI.panel()
	stage_panel.add_theme_stylebox_override("panel", ArkUI.box(Color(0.03, 0.11, 0.13, 0.7), 20))
	stage_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(stage_panel)
	var stage_column := ArkUI.vbox(8)
	stage_panel.add_child(stage_column)
	var stats := ArkUI.hbox(80)
	stage_column.add_child(stats)
	var left := _health_panel(_active(), true)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.add_child(left)
	var right := _health_panel(enemy, false)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.add_child(right)
	arena = Control.new()
	arena.custom_minimum_size.y = 240
	arena.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_column.add_child(arena)
	player_actor = CreatureActor.new()
	player_actor.anchor_left = 0.04
	player_actor.anchor_right = 0.45
	player_actor.anchor_bottom = 1.0
	arena.add_child(player_actor)
	player_actor.setup(int(_active().species_id), false, not reduced_motion)
	enemy_actor = CreatureActor.new()
	enemy_actor.anchor_left = 0.55
	enemy_actor.anchor_right = 0.96
	enemy_actor.anchor_bottom = 1.0
	arena.add_child(enemy_actor)
	enemy_actor.setup(int(enemy.species_id), true, not reduced_motion)
	var dice_panel := ArkUI.panel()
	dice_panel.add_theme_stylebox_override("panel", ArkUI.box(Color("0b202c"), 12))
	stage_column.add_child(dice_panel)
	var dice_box := ArkUI.hbox(16)
	dice_panel.add_child(dice_box)
	dice_box.add_child(ArkUI.label("IL LANCIO", 16, ArkUI.GOLD))
	dice_row = ArkUI.hbox(8)
	dice_row.custom_minimum_size.y = 42
	dice_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dice_box.add_child(dice_row)
	dice_row.add_child(ArkUI.label("I dadi compariranno qui", 18, ArkUI.MUTED))
	var lower := ArkUI.hbox(18)
	lower.custom_minimum_size.y = 202
	page.add_child(lower)
	var message_panel := ArkUI.panel()
	message_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message_panel.size_flags_stretch_ratio = 1.1
	lower.add_child(message_panel)
	var message_box := ArkUI.vbox(10)
	message_panel.add_child(message_box)
	message_box.add_child(ArkUI.label("CRONACA DELLO SCONTRO", 15, ArkUI.MINT))
	var log_scroll := ScrollContainer.new()
	battle_log_scroll = log_scroll
	log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	message_box.add_child(log_scroll)
	battle_message = ArkUI.paragraph("", 19, ArkUI.TEXT)
	battle_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_scroll.add_child(battle_message)
	var flee := ArkUI.button("Ritirata · Torna al sentiero", _flee)
	message_box.add_child(flee)
	action_buttons.append(flee)
	var controls := ArkUI.panel()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lower.add_child(controls)
	action_panel = ArkUI.vbox(10)
	controls.add_child(action_panel)
	_build_actions()
	_focus_first()

func _health_panel(member: Dictionary, is_player: bool) -> VBoxContainer:
	var column := ArkUI.vbox(5)
	var name_row := ArkUI.hbox()
	name_row.add_child(ArkUI.label(String(member.name), 28))
	name_row.add_child(ArkUI.spacer())
	var summary := ArkUI.label("Lv. %d · %s" % [int(member.level), member.type], 18, ArkUI.type_color(member.type))
	name_row.add_child(summary)
	if is_player:
		player_summary = summary
	column.add_child(name_row)
	var bar := ProgressBar.new()
	bar.custom_minimum_size.y = 16
	bar.show_percentage = false
	bar.max_value = float(member.max_hp)
	bar.value = float(member.hp)
	column.add_child(bar)
	var health := ArkUI.label("PV %d / %d" % [int(member.hp), int(member.max_hp)], 17, ArkUI.MUTED)
	column.add_child(health)
	if is_player:
		player_hp = bar
		player_health = health
	else:
		enemy_hp = bar
		enemy_health = health
	return column

func _build_actions() -> void:
	_refresh_inventory()
	for child in action_panel.get_children():
		action_panel.remove_child(child)
		child.queue_free()
	# The retreat button lives outside action_panel.
	while action_buttons.size() > 1:
		action_buttons.pop_back()
	if battle_finished:
		var next := ArkUI.button("Prosegui  →", _leave_battle, true)
		action_panel.add_child(next)
		action_buttons.append(next)
		next.grab_focus()
		return
	action_panel.add_child(ArkUI.label("TURNO %d · SCEGLI L'AZIONE" % turn_count, 15, ArkUI.GOLD))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	action_panel.add_child(grid)
	var available: Array = rules.available_moves(_active())
	for index in mini(available.size(), 2):
		var move: Dictionary = available[index]
		var text := "%d  %s" % [index + 1, move.name]
		var node := ArkUI.button(text, _choose_move.bind(int(move.id)), true)
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		node.tooltip_text = "%s · %d dadi D6 · bonus %d" % [move.type, int(move.dice), int(move.bonus)]
		grid.add_child(node)
		action_buttons.append(node)
	var potion := ArkUI.button("3  Pozione (%d)" % int(campaign.potions), _use_potion)
	potion.disabled = int(campaign.potions) <= 0 or int(_active().hp) >= int(_active().max_hp)
	grid.add_child(potion)
	action_buttons.append(potion)
	var capture := ArkUI.button("4  Cattura (%d)" % int(campaign.orbs), _try_capture)
	capture.disabled = int(campaign.orbs) <= 0 or campaign.party.size() >= 6
	capture.tooltip_text = "Indebolisci l'avversario per aumentare le possibilità. Squadra: massimo 6."
	grid.add_child(capture)
	action_buttons.append(capture)

func _set_busy(value: bool) -> void:
	busy = value
	for node in action_buttons:
		if is_instance_valid(node):
			node.disabled = value
	if not value:
		_build_actions()

func _choose_move(move_id: int) -> void:
	if busy or battle_finished:
		return
	_set_busy(true)
	var our_roll := rng.randi_range(1, 6)
	var their_roll := rng.randi_range(1, 6)
	while our_roll == their_roll:
		our_roll = rng.randi_range(1, 6)
		their_roll = rng.randi_range(1, 6)
	_show_dice([our_roll, their_roll])
	_log("Iniziativa: tu %d · avversario %d. %s attacca per primo." % [our_roll, their_roll, _active().name if our_roll > their_roll else enemy.name])
	await _pause(0.6)
	if our_roll > their_roll:
		await _perform_attack(true, move_id)
		if not await _check_battle_end():
			await _enemy_turn()
	else:
		await _enemy_turn()
		if int(_active().hp) > 0 and int(enemy.hp) > 0:
			await _perform_attack(true, move_id)
	await _end_round()

func _enemy_turn() -> void:
	var available: Array = rules.available_moves(enemy)
	if available.is_empty():
		return
	var selected: Dictionary = available[rng.randi_range(0, available.size() - 1)]
	await _perform_attack(false, int(selected.id))

func _perform_attack(ours: bool, move_id: int) -> void:
	var attacker: Dictionary = _active() if ours else enemy
	var defender: Dictionary = enemy if ours else _active()
	var actor: CreatureActor = player_actor if ours else enemy_actor
	var target: CreatureActor = enemy_actor if ours else player_actor
	actor.strike(1.0 if ours else -1.0)
	await _pause(0.16)
	var result: Dictionary = rules.attack(attacker, defender, move_id, rng)
	_show_dice(result.get("dice", []), ArkUI.MINT if ours else ArkUI.GOLD)
	_log(String(result.get("text", "La mossa non ha effetto.")))
	if int(result.get("damage", 0)) > 0:
		target.hit()
		_burst(target, ArkUI.type_color(String(attacker.type)))
		_float_text(target, "−%d" % int(result.damage), ArkUI.RED)
		_play("hit")
	if int(result.get("heal", 0)) > 0:
		_float_text(actor, "+%d" % int(result.heal), ArkUI.MINT)
		_play("heal")
	_refresh_health()
	await _pause(0.95)

func _use_potion() -> void:
	if busy or battle_finished or int(campaign.potions) <= 0 or int(_active().hp) >= int(_active().max_hp):
		return
	_set_busy(true)
	campaign.potions = int(campaign.potions) - 1
	var amount := mini(20, int(_active().max_hp) - int(_active().hp))
	_active().hp = int(_active().hp) + amount
	_log("Una pozione restituisce %d PV a %s." % [amount, _active().name])
	_float_text(player_actor, "+%d" % amount, ArkUI.MINT)
	_refresh_health()
	_play("heal")
	await _pause(0.65)
	await _enemy_turn()
	await _end_round()

func _try_capture() -> void:
	if busy or battle_finished or int(campaign.orbs) <= 0 or campaign.party.size() >= 6:
		return
	_set_busy(true)
	campaign.orbs = int(campaign.orbs) - 1
	var result: Dictionary = rules.capture(enemy, rng)
	_show_dice(result.dice, ArkUI.GOLD)
	_log(String(result.text))
	_burst(enemy_actor, ArkUI.GOLD)
	_play("capture")
	await _pause(0.9)
	if bool(result.success):
		campaign.party.append(enemy.duplicate(true))
		campaign.captures = int(campaign.captures) + 1
		_finish_battle(true, true)
	else:
		await _enemy_turn()
		await _end_round()

func _end_round() -> void:
	if not battle_finished:
		await _check_battle_end()
	if not battle_finished:
		turn_count += 1
	_set_busy(false)

func _check_battle_end() -> bool:
	if battle_finished:
		return true
	if int(enemy.hp) <= 0:
		enemy_actor.knocked_out()
		_finish_battle(true, false)
		return true
	if int(_active().hp) <= 0:
		player_actor.knocked_out()
		_finish_battle(false, false)
		return true
	return false

func _finish_battle(won: bool, caught: bool) -> void:
	battle_finished = true
	if won:
		campaign.checkpoint = maxi(int(campaign.checkpoint), battle_step)
		campaign.coins = int(campaign.coins) + 15
		campaign.wins = int(campaign.wins) + 1
		var member: Dictionary = _active()
		var leveled: Dictionary = rules.creature(int(member.species_id), mini(int(member.level) + 1, 100))
		leveled.hp = mini(int(leveled.max_hp), int(member.hp) + int(leveled.max_hp) - int(member.max_hp))
		campaign.party[int(campaign.active)] = leveled
		_refresh_health()
		if battle_step == 4:
			campaign.completed = true
		_log(("%s è nella tua squadra!" % enemy.name if caught else "Scontro vinto!") + " +15 monete · %s sale al livello %d." % [leveled.name, int(leveled.level)])
		_play("confirm")
	else:
		_log("%s è esausto. Il laboratorio e la sorgente possono curare tutta la squadra." % _active().name)
	_save()
	busy = false
	_build_actions()

func _flee() -> void:
	if busy:
		return
	_save()
	_show_world()
	_notify("Sei tornato al sentiero. I PV e gli oggetti usati sono conservati.")

func _leave_battle() -> void:
	if busy:
		return
	if bool(campaign.completed) and battle_step == 4:
		_show_complete()
	else:
		_show_world()

func _refresh_health() -> void:
	player_summary.text = "Lv. %d · %s" % [int(_active().level), _active().type]
	for pair in [[_active(), player_hp, player_health], [enemy, enemy_hp, enemy_health]]:
		var member: Dictionary = pair[0]
		var bar: ProgressBar = pair[1]
		var health: Label = pair[2]
		bar.max_value = float(member.max_hp)
		health.text = "PV %d / %d" % [int(member.hp), int(member.max_hp)]
		if fast_mode or reduced_motion:
			bar.value = float(member.hp)
		else:
			create_tween().tween_property(bar, "value", float(member.hp), 0.25)

func _show_dice(values: Array, color: Color = ArkUI.MINT) -> void:
	for child in dice_row.get_children():
		dice_row.remove_child(child)
		child.queue_free()
	for value in values:
		var die := DiceFace.new()
		die.value = clampi(int(value), 1, 6)
		die.tint = color
		dice_row.add_child(die)
	if values.is_empty():
		dice_row.add_child(ArkUI.label("Nessun dado richiesto", 17, ArkUI.MUTED))

func _log(message: String) -> void:
	history.append(message)
	while history.size() > 2:
		history.pop_front()
	battle_message.text = "\n".join(history)
	_scroll_log.call_deferred()

func _scroll_log() -> void:
	if screen == "battle" and is_instance_valid(battle_log_scroll):
		battle_log_scroll.scroll_vertical = int(battle_log_scroll.get_v_scroll_bar().max_value)

func _refresh_inventory() -> void:
	if is_instance_valid(inventory_label) and not campaign.is_empty():
		inventory_label.text = "%d monete   ·   %d pozioni   ·   %d sfere" % [int(campaign.coins), int(campaign.potions), int(campaign.orbs)]

func _burst(target: CreatureActor, color: Color) -> void:
	if reduced_motion:
		return
	var effect := Burst.new()
	effect.tint = color
	effect.position = target.position
	effect.size = target.size
	arena.add_child(effect)

func _float_text(target: CreatureActor, text: String, color: Color) -> void:
	var node := ArkUI.label(text, 40, color)
	node.position = target.position + target.size * Vector2(0.46, 0.2)
	arena.add_child(node)
	var tween := create_tween()
	tween.tween_property(node, "position:y", node.position.y - 45, 0.6)
	tween.parallel().tween_property(node, "modulate:a", 0.0, 0.7)
	tween.tween_callback(node.queue_free)

func _show_party() -> void:
	_clear_page("party")
	_heading("I tuoi alleati", "La squadra", "Scegli il compagno da portare nel prossimo incontro. I compagni esausti si curano ai punti di riposo.")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	var list := ArkUI.vbox(12)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for index in campaign.party.size():
		var member: Dictionary = campaign.party[index]
		var panel := ArkUI.panel()
		list.add_child(panel)
		var row := ArkUI.hbox(20)
		panel.add_child(row)
		var icon := ArkUI.texture("res://assets/creatures/%d.png" % int(member.species_id))
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(110, 95)
		row.add_child(icon)
		var details := ArkUI.vbox(5)
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(details)
		details.add_child(ArkUI.label(String(member.name), 25))
		details.add_child(ArkUI.label("%s · Lv. %d · PV %d / %d" % [member.type, int(member.level), int(member.hp), int(member.max_hp)], 19, ArkUI.MUTED))
		var choose := ArkUI.button("In campo" if int(campaign.active) == index else "Scegli compagno", _choose_companion.bind(index), int(campaign.active) == index)
		choose.disabled = int(member.hp) <= 0 or int(campaign.active) == index
		row.add_child(choose)
	page.add_child(ArkUI.button("← Torna al sentiero", _show_world))
	_focus_first()

func _choose_companion(index: int) -> void:
	if index < 0 or index >= campaign.party.size() or int(campaign.party[index].hp) <= 0:
		return
	campaign.active = index
	_save()
	_show_party()

func _show_complete() -> void:
	_clear_page("complete")
	_heading("Il primo viaggio è compiuto", "Ogni grande storia comincia così.", "Hai raggiunto la radura. Il sentiero resta aperto: puoi tornare agli incontri e trovare nuovi compagni.")
	var panel := ArkUI.panel()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(panel)
	var column := ArkUI.vbox(12)
	panel.add_child(column)
	var actor := CreatureActor.new()
	actor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(actor)
	actor.setup(int(_active().species_id), false, not reduced_motion)
	var stats := ArkUI.label("%d scontri vinti     ·     %d catture     ·     %d monete" % [int(campaign.wins), int(campaign.captures), int(campaign.coins)], 25, ArkUI.GOLD)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(stats)
	page.add_child(ArkUI.button("Continua a esplorare  →", _show_world, true))
	page.add_child(ArkUI.button("Torna al titolo", _show_title))
	_focus_first()

func _show_help() -> void:
	_clear_page("help")
	_heading("Tutto parte da un lancio", "Come si gioca")
	var panel := ArkUI.panel()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var guide := ArkUI.paragraph("IL SENTIERO\nVisita le tappe in ordine. Laboratorio e sorgente curano gratis tutta la squadra. Ogni scontro vinto o cattura sblocca la tappa successiva.\n\nI DADI\nA ogni turno, un D6 per parte decide chi agisce prima. Il danno di una mossa è la somma dei suoi dadi più il bonus; le affinità tra tipi modificano il risultato.\n\nLA SQUADRA\nIndebolisci una creatura prima di catturarla. La squadra può contenere sei compagni. Una pozione recupera fino a 20 PV e lascia agire l'avversario. Una vittoria assegna un livello e 15 monete.\n\nI COMANDI\nMouse oppure Tab e Invio. In battaglia: 1–2 mosse, 3 pozione, 4 cattura. F11 schermo intero · M audio. I progressi si salvano al termine di ogni incontro e a ogni tappa di riposo.", 22, ArkUI.TEXT)
	guide.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(guide)
	page.add_child(ArkUI.button("← Torna al sentiero", _show_world))
	_focus_first()

func _show_settings() -> void:
	_clear_page("settings")
	_heading("Fai spazio al tuo viaggio", "Impostazioni")
	var panel := ArkUI.panel()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(panel)
	var column := ArkUI.vbox(22)
	panel.add_child(column)
	column.add_child(ArkUI.label("Audio degli effetti", 26))
	column.add_child(ArkUI.button("Attivo" if sound_enabled else "Disattivato", func() -> void: _toggle_sound(); _show_settings()))
	column.add_child(ArkUI.label("Movimento ridotto", 26))
	column.add_child(ArkUI.paragraph("Riduce oscillazioni e movimenti degli attacchi. I risultati degli scontri restano gli stessi.", 20))
	column.add_child(ArkUI.button("Attivo" if reduced_motion else "Disattivato", func() -> void: reduced_motion = not reduced_motion; _save_preferences(); _show_settings()))
	column.add_child(ArkUI.button("Schermo intero / finestra · F11", _toggle_fullscreen))
	page.add_child(ArkUI.button("← Torna al titolo", _show_title))
	_focus_first()

func _save(announce: bool = false) -> void:
	var error := SaveStore.save_game(campaign, save_path)
	if error != OK:
		_notify("Salvataggio non riuscito. Controlla lo spazio disponibile sul PC.", true)
	elif announce:
		_notify("Viaggio salvato.")

func _notify(message: String, error: bool = false) -> void:
	toast_label.text = message
	toast_label.add_theme_color_override("font_color", ArkUI.RED if error else ArkUI.MINT)

func _play(name: String) -> void:
	if not sound_enabled:
		return
	var path := "res://assets/audio/%s.ogg" % name
	if ResourceLoader.exists(path):
		sound.stream = load(path)
		sound.play()

func _toggle_sound() -> void:
	sound_enabled = not sound_enabled
	if not sound_enabled:
		sound.stop()
	_save_preferences()
	# Updating the top button does not rebuild an active battle.
	var header: HBoxContainer = page.get_child(0)
	for node in header.get_children():
		if node is Button and node.text.begins_with("Audio:"):
			node.text = "Audio: sì" if sound_enabled else "Audio: no"

func _toggle_fullscreen() -> void:
	var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)

func _save_preferences() -> void:
	var config := ConfigFile.new()
	config.set_value("preferences", "audio", sound_enabled)
	config.set_value("preferences", "reduced_motion", reduced_motion)
	if not testing:
		config.save(preferences_path)

func _load_preferences() -> void:
	var config := ConfigFile.new()
	if config.load(preferences_path) == OK:
		sound_enabled = bool(config.get_value("preferences", "audio", true))
		reduced_motion = bool(config.get_value("preferences", "reduced_motion", false))

func _pause(seconds: float) -> void:
	await get_tree().create_timer(0.001 if fast_mode else seconds).timeout

func _focus_first() -> void:
	_focus_deferred.call_deferred()

func _focus_deferred() -> void:
	var candidates: Array[Node] = page.find_children("*", "Button", true, false)
	var header: Node = page.get_child(0)
	for node in candidates:
		if node is Button and not node.disabled and not header.is_ancestor_of(node):
			node.grab_focus()
			return

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F11:
		_toggle_fullscreen()
	elif event.keycode == KEY_M:
		_toggle_sound()
	elif screen == "battle" and not busy and not battle_finished:
		var available: Array = rules.available_moves(_active())
		if event.keycode == KEY_1 and available.size() > 0:
			_choose_move(int(available[0].id))
		elif event.keycode == KEY_2 and available.size() > 1:
			_choose_move(int(available[1].id))
		elif event.keycode == KEY_3:
			_use_potion()
		elif event.keycode == KEY_4:
			_try_capture()

func _take_preview() -> void:
	# Used by the local visual check; never writes player progress.
	_new_game_preview()
	var args := OS.get_cmdline_user_args()
	var mode_index := args.find("--preview-screen")
	var mode := args[mode_index + 1] if mode_index >= 0 and mode_index + 1 < args.size() else "battle"
	match mode:
		"title": _show_title()
		"starters": _show_starters()
		"world": _show_world()
		"party": _show_party()
		"help": _show_help()
		"settings": _show_settings()
		"complete": _show_complete()
		"battle-log":
			_log("Darklaw usa Dardo di Fiamma! È superefficace! Silvard perde 8 PV.")
			_log("Silvard usa Frustata! Darklaw perde 4 PV. Scegli la tua prossima mossa.")
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var index := args.find("--screenshot")
	var path := args[index + 1] if index + 1 < args.size() else "user://preview.png"
	var result := image.save_png(path)
	print("PREVIEW ", path, " result=", result)
	get_tree().quit(result)

func _new_game_preview() -> void:
	campaign = {"starter": 5, "party": [rules.creature(5, 5)], "active": 0,
		"checkpoint": 0, "coins": 0, "potions": 3, "orbs": 6, "wins": 0, "captures": 0, "completed": false}
	_start_battle(1)
	_show_dice([3, 5], ArkUI.GOLD)

func _run_smoke_test() -> void:
	# End-to-end scene flow using a separate save path is covered by tests/test_flow.gd.
	print("SMOKE_READY")
	get_tree().quit(0)

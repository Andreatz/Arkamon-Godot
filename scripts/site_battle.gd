class_name SiteBattle
extends RefCounted
## Native presentation of the original site's BattlePresentation/BattagliaScene.
## Percentage rectangles follow arkamon-theme.json; battle_layout.json is legacy.
## This helper owns presentation only. BattleSession and CampaignModel own actions.

const ART: String = "res://assets/ui/original/"
const FONT: String = "res://assets/fonts/Norwester.ttf"
const WHITE: Color = Color("f8fafc")
const MUTED: Color = Color("c4b5fd")
const GOLD: Color = Color("fbbf24")
const HP_HIGH: Color = Color("22c55e")
const HP_MID: Color = Color("facc15")
const HP_LOW: Color = Color("ff3856")
const MOVES_RECT: Rect2 = Rect2(46.0608, 71.7748, 52.9392, 25.7252)
const OVERLAY_RECT: Rect2 = Rect2(33.0, 59.0, 65.0, 38.0)


static func build(game) -> void:
	game._clear_page("battle")
	game._background("battle_forest")
	var backgrounds: Dictionary = game.world_data.get("backgrounds", {})
	var location: String = String(game.model.player().get("location", ""))
	var background_path: String = String(backgrounds.get(location, "res://assets/backgrounds/battle_forest.webp"))
	if ResourceLoader.exists(background_path):
		game.backdrop.texture = load(background_path)
	# The battle has its own edge-to-edge composition, like the 16:9 web stage.
	# Keep the shared header node alive for audio callbacks, but reclaim its space.
	if game.page.get_child_count() > 0:
		(game.page.get_child(0) as Control).hide()
	game.backdrop.modulate = Color.WHITE
	var stage := Control.new()
	stage.name = "SiteBattleStage"
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.page.add_child(stage)
	game.arena = stage
	_add_shade(stage)
	var caption: String = String(game.battle_context.get("title", game.battle_context.get("name", "Battaglia")))
	var place_label := _label(game._place(location), 17, WHITE)
	place_label.name = "BattleLocation"
	place_label.tooltip_text = caption
	stage.add_child(place_label)
	_rect(place_label, Rect2(2.5, 2.3, 31.0, 3.7))
	var encounter_label := _label(caption, 14, MUTED)
	encounter_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stage.add_child(encounter_label)
	_rect(encounter_label, Rect2(2.5, 6.0, 30.0, 3.5))
	var turn_panel := _surface(stage, "player-kit/button-primary.svg", Rect2(39.0, 4.0, 22.0, 5.0))
	var turn_label := _label("", 17, WHITE)
	turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	turn_panel.add_child(turn_label)
	_rect(turn_label, Rect2(7.0, 8.0, 86.0, 84.0))
	stage.set_meta("site_turn", turn_label)
	_make_actor(game, stage, "enemy", Rect2(74.0, 14.0, 19.0, 34.0))
	_make_actor(game, stage, "player", Rect2(6.0, 47.0, 23.0, 41.0))
	_health(game, stage, "enemy", Rect2(25.1891, 11.4865, 40.4897, 9.8919))
	_health(game, stage, "player", Rect2(56.1082, 60.2152, 41.8242, 10.0))
	_squad(game, stage, "enemy", Rect2(56.7908, 8.8, 16.0, 3.0))
	_squad(game, stage, "player", Rect2(86.0, 56.8, 12.0, 3.0))
	var info := _surface(stage, "infobox.png", Rect2(34.6892, 27.8378, 35.6689, 23.5676))
	info.name = "BattleInfoBox"
	game.battle_log_scroll = ScrollContainer.new()
	game.battle_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	game.battle_log_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	info.add_child(game.battle_log_scroll)
	_rect(game.battle_log_scroll, Rect2(8.0, 16.0, 84.0, 72.0))
	game.battle_message = _label("\n".join(game.history), 21, WHITE)
	game.battle_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game.battle_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game.battle_message.size_flags_vertical = Control.SIZE_EXPAND_FILL
	game.battle_log_scroll.add_child(game.battle_message)
	var chronicle := _button("Cronaca", Callable(), "player-kit/button-default.svg", 15)
	chronicle.toggle_mode = true
	chronicle.button_pressed = true
	chronicle.toggled.connect(func(visible: bool) -> void: info.visible = visible)
	stage.add_child(chronicle)
	_rect(chronicle, Rect2(2.5, 11.0, 11.0, 4.7))
	var dice_scroll := ScrollContainer.new()
	dice_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	dice_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stage.add_child(dice_scroll)
	_rect(dice_scroll, Rect2(35.5, 52.4, 33.0, 6.5))
	game.dice_row = HBoxContainer.new()
	game.dice_row.add_theme_constant_override("separation", 6)
	game.dice_row.alignment = BoxContainer.ALIGNMENT_CENTER
	game.dice_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dice_scroll.add_child(game.dice_row)
	game.action_panel = VBoxContainer.new()
	game.action_panel.name = "BattleCommands"
	game.action_panel.add_theme_constant_override("separation", 6)
	stage.add_child(game.action_panel)
	_rect(game.action_panel, MOVES_RECT)
	# Main's busy/focus logic reserves index zero for the external retreat command.
	var retreat := _button("Ritirata" if game.session.kind == "wild" else "Abbandona", game._flee, "player-kit/button-default.svg", 16)
	stage.add_child(retreat)
	_rect(retreat, Rect2(2.4687, 90.5926, 13.0, 5.7037))
	game.action_buttons.append(retreat)
	refresh(game)
	actions(game)
	game._focus_first()


static func actions(game) -> void:
	if not is_instance_valid(game.action_panel) or game.session == null:
		return
	game._refresh_inventory()
	_clear_commands(game)
	_rect(game.action_panel, MOVES_RECT)
	var session: BattleSession = game.session
	_update_turn(game)
	if session.finished:
		_rect(game.action_panel, Rect2(33.0, 73.0, 40.0, 21.0))
		var result: Dictionary = session.result
		var winner: String = String(result.get("winner", ""))
		var heading: String = "Battaglia conclusa"
		if String(result.get("reason", "")) == "capture":
			heading = "Cattura riuscita!"
		elif winner == "player":
			heading = "Vittoria!"
		elif winner == "enemy":
			heading = "Sconfitta"
		var result_label := _label(heading, 28, GOLD)
		result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		game.action_panel.add_child(result_label)
		var next := _button("Prosegui  →", game._leave_battle, "player-kit/button-primary.svg", 21)
		next.custom_minimum_size.y = 56
		game.action_panel.add_child(next)
		game.action_buttons.append(next)
		next.grab_focus()
		return
	if not session.needs_switch.is_empty():
		prepare_overlay(game)
		game.action_panel.add_child(_label("SCEGLI CHI ENTRA IN CAMPO", 19, GOLD))
		game._add_switch_buttons(String(session.needs_switch[0]), true)
		return
	var member: Dictionary = session.active_creature(String(game.input_side))
	var moves: Array = game.rules.available_moves(member)
	var commands := Control.new()
	commands.name = "BattleMoveCards"
	commands.custom_minimum_size.y = 194
	commands.size_flags_vertical = Control.SIZE_EXPAND_FILL
	commands.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.action_panel.add_child(commands)
	var move_row := HBoxContainer.new()
	move_row.add_theme_constant_override("separation", 4)
	commands.add_child(move_row)
	_rect(move_row, Rect2(0.0, 0.0, 74.0, 77.0))
	for index: int in moves.size():
		var move: Dictionary = moves[index]
		var card := _move_button(game, move, index)
		move_row.add_child(card)
		game.action_buttons.append(card)
	var supreme := _button("Mossa\nSuprema\n×2 · −%d HP" % maxi(1, int(int(member.get("max_hp", 1)) * 0.5)), game._supreme_dialog, "", 20)
	_style_supreme(supreme)
	var can_supreme: bool = false
	for move: Dictionary in moves:
		if not bool(move.get("status_only", false)) and not String(move.get("effect", "")).begins_with("CURA"):
			can_supreme = true
	supreme.disabled = not can_supreme
	supreme.tooltip_text = "Danno doppio; contraccolpo del 50% dei PV massimi dopo l'eventuale salita di livello."
	commands.add_child(supreme)
	_rect(supreme, Rect2(76.0, 0.0, 24.0, 77.0))
	game.action_buttons.append(supreme)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 7)
	commands.add_child(tools)
	_rect(tools, Rect2(0.0, 79.0, 100.0, 21.0))
	var change := _button("Cambia", game._show_battle_switch, "player-kit/button-default.svg", 17)
	tools.add_child(change)
	game.action_buttons.append(change)
	if session.kind == "wild":
		var capture := _button("Cattura", game._queue_action.bind({"type": "capture"}), "", 17)
		_style_action(capture)
		tools.add_child(capture)
		game.action_buttons.append(capture)
	var bag := _button("Borsa", game._show_battle_bag, "player-kit/button-default.svg", 17)
	bag.disabled = String(game.input_side) != "player" or session.kind == "pvp" or not game.challenge_descriptor.is_empty()
	tools.add_child(bag)
	game.action_buttons.append(bag)
	for child: Node in tools.get_children():
		(child as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		(child as Control).custom_minimum_size.y = 39


static func prepare_overlay(game) -> void:
	# Call before the existing bag/switch/Suprema builders. Their VBox API remains.
	_rect(game.action_panel, OVERLAY_RECT)
	game.action_panel.add_theme_constant_override("separation", 7)


static func refresh(game) -> void:
	if not is_instance_valid(game.arena):
		return
	for side: String in ["player", "enemy"]:
		if not game.presented.has(side):
			continue
		var value: Dictionary = game.presented[side]
		var actor: CreatureActor = game.player_actor if side == "player" else game.enemy_actor
		var species_id: int = int(value.get("species_id", 1))
		if int(actor.get_meta("species", 0)) != species_id:
			actor.setup(species_id, side == "enemy", not game.reduced_motion)
			actor.set_meta("species", species_id)
		var bar: ProgressBar = game.player_hp if side == "player" else game.enemy_hp
		var health: Label = game.player_health if side == "player" else game.enemy_health
		var name_label: Label = bar.get_meta("site_name") as Label
		var level_label: Label = bar.get_meta("site_level") as Label
		var status_label: Label = bar.get_meta("site_status") as Label
		bar.max_value = maxi(1, int(value.get("max_hp", 1)))
		bar.value = clampi(int(value.get("hp", 0)), 0, int(bar.max_value))
		name_label.text = String(value.get("name", "Arkamon"))
		level_label.text = "LV. %d" % int(value.get("level", 5))
		health.text = "%d/%d" % [int(bar.value), int(bar.max_value)]
		var ratio: float = bar.value / maxf(1.0, bar.max_value)
		var color: Color = HP_HIGH if ratio > 0.6 else (HP_MID if ratio > 0.25 else HP_LOW)
		bar.add_theme_stylebox_override("fill", _hp_fill(color))
		var condition: Variant = value.get("status", {})
		var status: String = String(condition.get("type", "")) if condition is Dictionary else String(condition)
		status_label.text = status.to_upper()
		status_label.visible = not status.is_empty()
		name_label.tooltip_text = "%s · %s" % [value.get("name", "Arkamon"), value.get("type", "")]
		_update_squad(game, side)
	_update_turn(game)


static func _make_actor(game, stage: Control, side: String, bounds: Rect2) -> void:
	var actor := CreatureActor.new()
	actor.name = "PlayerBattleActor" if side == "player" else "EnemyBattleActor"
	stage.add_child(actor)
	_rect(actor, bounds)
	var member: Dictionary = game.session.active_creature(side)
	actor.playback_speed = float(game.animation_speed)
	actor.setup(int(member.get("species_id", 1)), side == "enemy", not game.reduced_motion)
	actor.set_meta("species", int(member.get("species_id", 1)))
	if side == "player":
		game.player_actor = actor
	else:
		game.enemy_actor = actor


static func _health(game, stage: Control, side: String, bounds: Rect2) -> void:
	var frame := _surface(stage, "hp_bar_%s.png" % side, bounds)
	frame.name = "%sHealthFrame" % side.capitalize()
	var name_label := _label("", 21, WHITE)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	frame.add_child(name_label)
	_rect(name_label, Rect2(15.0, 15.0, 57.0, 35.0))
	var level_label := _label("", 18, WHITE)
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	frame.add_child(level_label)
	_rect(level_label, Rect2(73.0, 15.0, 19.0, 35.0))
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", _hp_fill(Color("19302c")))
	bar.add_theme_stylebox_override("fill", _hp_fill(HP_HIGH))
	frame.add_child(bar)
	_rect(bar, Rect2(10.25, 66.5, 59.7, 33.5))
	# The original layers the shaded PNG over the colored fill using multiply.
	var bar_texture := _texture("hp_bar.png")
	var bar_material := CanvasItemMaterial.new()
	bar_material.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	bar_texture.material = bar_material
	frame.add_child(bar_texture)
	_rect(bar_texture, Rect2(10.25, 66.5, 59.7, 33.5))
	var health := _label("", 17, WHITE)
	health.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	health.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	frame.add_child(health)
	_rect(health, Rect2(10.25, 66.5, 59.7, 33.5))
	var status := _label("", 16, GOLD)
	frame.add_child(status)
	_rect(status, Rect2(0.0, -35.0, 70.0, 30.0))
	bar.set_meta("site_name", name_label)
	bar.set_meta("site_level", level_label)
	bar.set_meta("site_status", status)
	if side == "player":
		game.player_hp = bar
		game.player_health = health
		# Kept separate: game._refresh_health writes the extended type summary.
		game.player_summary = _label("", 15, MUTED)
		frame.add_child(game.player_summary)
		_rect(game.player_summary, Rect2(73.0, 69.0, 27.0, 31.0))
	else:
		game.enemy_hp = bar
		game.enemy_health = health


static func _squad(game, stage: Control, side: String, bounds: Rect2) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(row)
	_rect(row, bounds)
	stage.set_meta("site_squad_" + side, row)
	_update_squad(game, side)


static func _update_squad(game, side: String) -> void:
	var row: HBoxContainer = game.arena.get_meta("site_squad_" + side, null) as HBoxContainer
	if row == null or game.session == null:
		return
	var team: Array = game.session.teams.get(side, [])
	while row.get_child_count() < team.size():
		var marker := Panel.new()
		marker.custom_minimum_size = Vector2(13, 13)
		marker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(marker)
	for index: int in row.get_child_count():
		var marker: Panel = row.get_child(index) as Panel
		marker.visible = index < team.size()
		if index >= team.size():
			continue
		var member: Dictionary = team[index]
		var fill: Color = HP_HIGH if int(member.get("hp", 0)) > 0 else Color("475569")
		var style := StyleBoxFlat.new()
		style.bg_color = fill
		style.set_corner_radius_all(7)
		style.set_border_width_all(1)
		style.border_color = WHITE if int(game.session.active.get(side, 0)) == index else Color("94a3b8")
		marker.add_theme_stylebox_override("panel", style)
		marker.tooltip_text = "%s · Lv.%d · %d HP" % [member.get("name", ""), int(member.get("level", 5)), int(member.get("hp", 0))]


static func _move_button(game, move: Dictionary, index: int) -> Button:
	var button := _button("", game._queue_action.bind({"type": "attack", "move_id": int(move.get("id", 0))}), "move_button.png", 19)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 0)
	button.clip_contents = true
	var title := _label(String(move.get("name", "Mossa")), 22, WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.max_lines_visible = 2
	button.add_child(title)
	_rect(title, Rect2(10.0, 10.0, 80.0, 43.0))
	var facts: String = "%d D6" % int(move.get("dice", 0))
	var bonus: int = int(move.get("bonus", 0))
	if bonus != 0:
		facts += " %+d" % bonus
	var effect: String = String(move.get("effect", ""))
	if bool(move.get("status_only", false)):
		facts = "STATO"
	elif effect.begins_with("CURA"):
		facts = "CURA %d%s" % [int(move.get("value", 0)), "%" if effect == "CURA_PCT" else " HP"]
	var details := _label(facts, 18, WHITE)
	details.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	button.add_child(details)
	_rect(details, Rect2(10.0, 62.0, 65.0, 24.0))
	var type_name: String = String(move.get("type", "Normale"))
	var type_icon := _texture(type_name.to_lower() + ".png")
	type_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	button.add_child(type_icon)
	_rect(type_icon, Rect2(76.0, 64.0, 15.0, 22.0))
	button.tooltip_text = "%d · %s · %s · %s" % [index + 1, move.get("name", "Mossa"), type_name, facts]
	button.set_meta("move_id", int(move.get("id", 0)))
	return button


static func _clear_commands(game) -> void:
	for child: Node in game.action_panel.get_children():
		game.action_panel.remove_child(child)
		child.queue_free()
	while game.action_buttons.size() > 1:
		game.action_buttons.pop_back()


static func _update_turn(game) -> void:
	var label: Label = game.arena.get_meta("site_turn", null) as Label
	if label == null or game.session == null:
		return
	var name: String = String(game.model.player().get("name", "Giocatore 1"))
	if String(game.input_side) == "enemy":
		name = String(game.battle_context.get("name", "Giocatore 2"))
	label.text = "Battaglia finita" if game.session.finished else "Turno %d · %s" % [int(game.turn_count), name]
	label.tooltip_text = "Scegli una mossa" if not game.busy else "Azione in corso…"


static func _surface(parent: Control, filename: String, bounds: Rect2) -> Control:
	var node := Control.new()
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	_rect(node, bounds)
	var image := _texture(filename)
	node.add_child(image)
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return node


static func _texture(filename: String) -> TextureRect:
	var node := TextureRect.new()
	var path: String = ART + filename
	if ResourceLoader.exists(path):
		node.texture = load(path)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_SCALE
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


static func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("111111"))
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	label.add_theme_constant_override("shadow_offset_y", 2)
	if ResourceLoader.exists(FONT):
		label.add_theme_font_override("font", load(FONT) as Font)
	return label


static func _button(text: String, action: Callable, filename: String, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", WHITE)
	button.add_theme_color_override("font_hover_color", WHITE)
	button.add_theme_color_override("font_pressed_color", WHITE)
	button.add_theme_color_override("font_disabled_color", Color("94a3b8"))
	button.add_theme_color_override("font_outline_color", Color("111111"))
	button.add_theme_constant_override("outline_size", 2)
	if ResourceLoader.exists(FONT):
		button.add_theme_font_override("font", load(FONT) as Font)
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		if not filename.is_empty() and ResourceLoader.exists(ART + filename):
			var style := StyleBoxTexture.new()
			style.texture = load(ART + filename) as Texture2D
			style.texture_margin_left = 0
			style.texture_margin_right = 0
			style.texture_margin_top = 0
			style.texture_margin_bottom = 0
			style.modulate_color = Color(1.14, 1.14, 1.14) if state == "hover" else Color.WHITE
			if state == "pressed": style.modulate_color = Color(0.82, 0.82, 0.82)
			if state == "disabled": style.modulate_color = Color(0.6, 0.6, 0.6, 0.65)
			style.content_margin_left = 14
			style.content_margin_right = 14
			style.content_margin_top = 6
			style.content_margin_bottom = 6
			button.add_theme_stylebox_override(state, style)
		else:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = WHITE
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(4)
	button.add_theme_stylebox_override("focus", focus)
	if action.is_valid():
		button.pressed.connect(action)
	return button


static func _style_action(button: Button) -> void:
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("fbbf24") if state != "hover" else Color("fcd34d")
		if state == "pressed": style.bg_color = Color("d97706")
		if state == "disabled": style.bg_color = Color("716241")
		style.set_corner_radius_all(5)
		style.content_margin_left = 12
		style.content_margin_right = 12
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", Color("0f172a"))
	button.add_theme_color_override("font_hover_color", Color("0f172a"))
	button.add_theme_color_override("font_pressed_color", Color("0f172a"))
	button.add_theme_constant_override("outline_size", 0)


static func _style_supreme(button: Button) -> void:
	_style_action(button)
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxTexture.new()
		style.texture = load("res://assets/ui/supreme_gradient.svg")
		style.modulate_color = Color(1.1, 1.1, 1.1) if state == "hover" else Color.WHITE
		if state == "pressed": style.modulate_color = Color(0.9, 0.9, 0.9)
		if state == "disabled": style.modulate_color = Color(1, 1, 1, 0.45)
		button.add_theme_stylebox_override(state, style)


static func _hp_fill(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(9)
	return style


static func _add_shade(stage: Control) -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.48, 0.7, 1.0])
	gradient.colors = PackedColorArray([Color(0.01, 0.02, 0.06, 0.1), Color(0.01, 0.02, 0.06, 0.0), Color(0.01, 0.02, 0.06, 0.2), Color(0.01, 0.02, 0.06, 0.8)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	var shade := TextureRect.new()
	shade.texture = texture
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


static func _rect(node: Control, bounds: Rect2) -> void:
	node.anchor_left = bounds.position.x / 100.0
	node.anchor_top = bounds.position.y / 100.0
	node.anchor_right = bounds.end.x / 100.0
	node.anchor_bottom = bounds.end.y / 100.0
	node.offset_left = 0.0
	node.offset_top = 0.0
	node.offset_right = 0.0
	node.offset_bottom = 0.0

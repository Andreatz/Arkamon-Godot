extends "res://scripts/main.gd"
## Full campaign presentation. Domain rules live in CampaignModel/BattleSession.

var model: CampaignModel
var session: BattleSession
var world_data: Dictionary = {}
var starter_choices: Array = []
var player_names: Array[String] = ["Giocatore 1", "Giocatore 2"]
var name_inputs: Array[LineEdit] = []
var battle_context: Dictionary = {}
var input_side: String = "player"
var queued_pvp: Dictionary = {}
var presented: Dictionary = {}
var box_page: int = 1
var dex_page: int = 0
var view_player: int = -1
var chosen_item: String = ""
var snapshot_label: Label
var cart: Dictionary = {}
var dex_search: String = ""
var battle_events: Array = []
var challenge_menu: ChallengeMenu
var challenge_descriptor: Dictionary = {}
var previous_campaign: Dictionary = {}
var animation_speed: float = 1.0
var title_video: VideoStreamPlayer
var site_shade: ColorRect
var site_menu_button: Button
var site_audio_button: Button
var starter_names_confirmed: bool = false

func _ready() -> void:
	theme = ArkUI.make_theme()
	rng.randomize()
	if not testing:
		save_path = "user://full_campaign.json"
	if not testing:
		_load_preferences()
	var smoke := "--smoke-test" in OS.get_cmdline_user_args()
	var preview_requested := "--screenshot" in OS.get_cmdline_user_args()
	if smoke:
		testing = true
		fast_mode = true
		save_path = "user://full-smoke/campaign.json"
	if preview_requested:
		testing = true
		save_path = "user://preview/campaign.json"
		preferences_path = "user://preview/preferences.cfg"
	rules = BattleRules.new()
	if not rules.load_data():
		push_error(rules.load_error)
		get_tree().quit(1)
		return
	model = CampaignModel.new()
	if not model.configure(rules):
		push_error(model.load_error)
		get_tree().quit(1)
		return
	world_data = _json("res://data/world.json")
	prototype = _json("res://data/prototype.json")
	sound = AudioStreamPlayer.new()
	sound.volume_db = -9
	add_child(sound)
	_build_shell()
	_show_title()
	if smoke:
		print("FULL_CAMPAIGN_READY")
		get_tree().quit.call_deferred(0)
	elif "--screenshot" in OS.get_cmdline_user_args():
		_full_preview.call_deferred()

func _json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

func _bind_player() -> void:
	if model and not model.state.is_empty():
		campaign = model.player()

func _build_shell() -> void:
	SiteShell.build(self)

func _clear_page(next_screen: String) -> void:
	_bind_player()
	SiteShell.clear(self, next_screen)

func _show_dex_for(index: int) -> void:
	view_player = index
	dex_page = 0
	_show_dex()

func _show_active_analysis() -> void:
	if model.state.is_empty(): return
	_show_creature_details(model.player().party[int(model.player().active)], _show_party)

func _heading(kicker: String, title: String, description: String = "") -> void:
	var column := ArkUI.vbox(4)
	column.add_child(ArkUI.label(kicker.to_upper(), 12, ArkUI.MINT))
	column.add_child(ArkUI.label(title.to_upper(), 28))
	if not description.is_empty(): column.add_child(ArkUI.paragraph(description, 14))
	page.add_child(column)

func _refresh_inventory() -> void:
	if not is_instance_valid(inventory_label) or not model or model.state.is_empty(): return
	var person: Dictionary = model.player()
	inventory_label.text = "%d ₳" % int(person.coins)

func _show_title() -> void:
	SiteScenes.title(self)

func _show_starters() -> void:
	SiteScenes.starters(self)

func _request_new_game() -> void:
	starter_choices.clear()
	starter_names_confirmed = false
	super._request_new_game()

func _toggle_sound() -> void:
	sound_enabled = not sound_enabled
	if not sound_enabled: sound.stop()
	_save_preferences()
	if is_instance_valid(site_audio_button): site_audio_button.text = "Audio ON" if sound_enabled else "Audio OFF"

func _focus_deferred() -> void:
	if screen == "battle" and action_buttons.size() > 1:
		for index in range(1, action_buttons.size()):
			if is_instance_valid(action_buttons[index]) and action_buttons[index].is_visible_in_tree() and not action_buttons[index].disabled:
				action_buttons[index].grab_focus()
				return
	for node: Node in page.find_children("*", "Button", true, false):
		if node is Button and node.is_visible_in_tree() and not node.disabled:
			node.grab_focus()
			return

func _focus_starter_name() -> void:
	if screen != "starters" or starter_names_confirmed or name_inputs.is_empty(): return
	var edit := name_inputs[0]
	if is_instance_valid(edit) and edit.is_inside_tree() and edit.is_visible_in_tree(): edit.grab_focus()

func _new_game(id: int) -> void:
	if id in starter_choices or not id in [1, 5, 9]: return
	starter_choices.append(id)
	if starter_choices.size() < 2:
		_show_starters()
		return
	session = null
	model.new_game(starter_choices)
	for index in 2:
		model.state.players[index].name = player_names[index]
	_bind_player()
	_save()
	_show_world()

func _continue_game() -> void:
	var value := SaveStore.load_game(save_path)
	var result: Dictionary = model.load_state(value)
	if not bool(result.get("ok", false)):
		_notify(String(result.get("message", "Salvataggio non valido.")), true)
		return
	_resume_loaded()

func _resume_loaded() -> void:
	session = null
	if int(model.state.league.winner) >= 0:
		_show_complete()
		return
	if model.state.has("battle_checkpoint") and not model.state.get("pending", {}).is_empty():
		var checkpoint: Dictionary = model.state.battle_checkpoint
		session = BattleSession.new()
		session.rules = rules
		if session.restore(checkpoint.get("session", {}), rng):
			battle_context = checkpoint.get("context", {}).duplicate(true)
			battle_events = checkpoint.get("events", []).duplicate(true)
			input_side = "player"
			queued_pvp.clear()
			turn_count = session.round_number + 1
			battle_finished = session.finished
			busy = false
			history.clear()
			_present_snapshot()
			_show_battle()
			_log("Scontro ripreso dall'ultimo turno concluso.")
			return
		_notify("Il punto di ripresa dello scontro non è valido. Ripristina un backup.", true)
		return
	if String(model.state.phase) == "league": _show_league()
	elif String(model.state.phase) == "location": _show_location()
	else: _show_world()

func _active() -> Dictionary:
	if session and screen == "battle": return session.active_creature("player")
	var person: Dictionary = model.player()
	return person.party[int(person.get("active", 0))]

func _save(announce: bool = false) -> void:
	if not model or model.state.is_empty(): return
	if not challenge_descriptor.is_empty(): return
	if session and not session.finished:
		model.state["battle_checkpoint"] = {"session": session.snapshot(), "context": battle_context, "events": battle_events}
	var error := SaveStore.save_game(model.state, save_path)
	if error != OK: _notify("Salvataggio non riuscito. Controlla lo spazio disponibile.", true)
	elif announce: _notify("Campagna salvata.")

func _scroll_column(parent: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var column := ArkUI.vbox(12)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	return column

func _footer(back: Callable = _show_world) -> void:
	SiteShell.footer(self, back)

func _show_world() -> void:
	SiteScenes.world(self)

func _place(value: String) -> String:
	return value.replace("_", " ").replace("ReggioCalabria", "Reggio Calabria")

func _background_for(location: String) -> void:
	var backgrounds: Dictionary = world_data.get("backgrounds", {})
	var path := String(backgrounds.get(location, "res://assets/backgrounds/laboratory.webp"))
	if ResourceLoader.exists(path): backdrop.texture = load(path)

func _travel(destination: String) -> void:
	var result: Dictionary = model.travel(destination)
	_show_world()
	_notify(String(result.get("message", "")), not bool(result.get("ok", false)))
	_save()

func _end_turn() -> void:
	model.end_turn()
	_save()
	_show_world()

func _enter_location() -> void:
	var result: Dictionary = model.enter_location()
	if not bool(result.get("ok", false)):
		_notify(String(result.get("message", "Nessuna azione disponibile.")), true)
		return
	_save()
	_show_location()

func _show_location() -> void:
	SiteScenes.location(self)

func _local_move(node_id: String) -> void:
	var result: Dictionary = model.local_move(node_id)
	_show_location()
	_notify(String(result.get("message", "")), not bool(result.get("ok", false)))
	_save()

func _heal_party() -> void:
	var result: Dictionary = model.heal_party()
	_save()
	_show_location()
	_notify(String(result.get("message", "Squadra curata.")), not bool(result.get("ok", false)))
	_play("heal")

func _wild_encounter(bush: String) -> void:
	var result: Dictionary = model.encounter(bush)
	_begin_descriptor(result)

func _trainer_encounter(id: int) -> void:
	_begin_descriptor(model.trainer_battle(id))

func _begin_descriptor(descriptor: Dictionary) -> void:
	if not bool(descriptor.get("ok", false)):
		_notify(String(descriptor.get("message", "Incontro non disponibile.")), true)
		return
	battle_context = descriptor
	if String(descriptor.get("kind", "")) == "pvp":
		battle_context["name"] = model.player(1 - int(model.state.active_player)).name
	var enemy_team: Array = descriptor.get("team", descriptor.get("enemy_team", descriptor.get("enemy", [])))
	_start_session(enemy_team, String(descriptor.get("kind", "wild")))

func _start_pvp() -> void:
	var other: Dictionary = model.state.players[1 - int(model.state.active_player)]
	var descriptor: Dictionary = model.start_pvp()
	descriptor["name"] = other.name
	_begin_descriptor(descriptor)

func _start_session(team: Array, kind: String) -> void:
	session = BattleSession.new()
	session.rules = rules
	if not session.setup(model.player().party, team, "npc" if kind == "league" else kind, rng):
		_notify("Serve almeno un Arkamon in forze per ogni squadra.", true)
		session = null
		return
	var chosen := int(model.player().active)
	if chosen >= 0 and chosen < session.teams.player.size() and int(session.teams.player[chosen].hp) > 0:
		session.active.player = chosen
	if kind == "pvp":
		var other_active := int(model.player(1 - int(model.state.active_player)).active)
		if other_active >= 0 and other_active < session.teams.enemy.size() and int(session.teams.enemy[other_active].hp) > 0: session.active.enemy = other_active
	session.initial_side = session._initial_priority()
	input_side = "player"
	queued_pvp.clear()
	battle_events.clear()
	busy = false
	battle_finished = false
	turn_count = 1
	history.clear()
	_present_snapshot()
	_show_battle()
	player_actor.playback_speed = animation_speed
	enemy_actor.playback_speed = animation_speed
	_log("%s. Scegli l'azione di %s." % [String(battle_context.get("title", battle_context.get("name", "Un nuovo incontro"))), model.player().name])
	_save()

func _present_snapshot() -> void:
	if not session: return
	presented = {"player": session.active_creature("player").duplicate(true), "enemy": session.active_creature("enemy").duplicate(true)}
	enemy = session.active_creature("enemy")

func _show_battle() -> void:
	battle_step = 1
	SiteBattle.build(self)
	_refresh_health()

func _build_actions() -> void:
	SiteBattle.actions(self)

func _queue_action(action: Dictionary) -> void:
	if busy or session.finished: return
	if String(action.get("type", "")) == "capture" or String(action.get("effect", "")) == "masterball":
		var capacity: Dictionary = model._capture_destination(session.teams.player, model.player().box, session.active_creature("enemy"))
		if not bool(capacity.get("ok", false)):
			_log(String(capacity.get("message", "Non c'è spazio per una nuova cattura.")))
			return
	if session.kind == "pvp" and input_side == "player":
		queued_pvp = action.duplicate(true)
		input_side = "enemy"
		_log("Passa i comandi a %s. Scegli la seconda azione: le scelte saranno risolte insieme." % battle_context.name)
		_build_actions()
		return
	_set_busy(true)
	var resolution: Dictionary = session.play_turn(queued_pvp if session.kind == "pvp" else action, action if session.kind == "pvp" else {})
	if not bool(resolution.get("ok", false)):
		_log(String(resolution.get("error", "Azione non disponibile.")))
		_set_busy(false)
		return
	if action.has("item_id") and bool(resolution.get("accepted", false)):
		model.consume_battle_item(String(action.item_id))
	for event: Dictionary in resolution.get("events", []):
		battle_events.append({"type": event.get("type", ""), "side": event.get("side", ""), "text": event.get("text", ""), "dice": event.get("dice", [])})
		await _animate_event(event)
	input_side = "player"
	queued_pvp.clear()
	turn_count += 1
	battle_finished = session.finished
	if session.finished:
		_settle_session()
	else:
		_save()
	_set_busy(false)
	_refresh_health()

func _animate_event(event: Dictionary) -> void:
	var side := String(event.get("side", "player"))
	var actor: CreatureActor = player_actor if side == "player" else enemy_actor
	var target: CreatureActor = enemy_actor if side == "player" else player_actor
	var type := String(event.get("type", ""))
	var wait_time: float = 0.45 / animation_speed
	if type == "attack":
		var duration: float = actor.play_state("attack") if not reduced_motion else 0.0
		await _pause(maxf(0.2, duration))
	if type in ["damage", "hit"]:
		var hit_duration: float = actor.play_state("hit") if not reduced_motion else 0.0
		if hit_duration <= 0.0: actor.hit()
		wait_time = maxf(0.3, hit_duration)
		if not reduced_motion:
			var effect := MoveEffect.new()
			effect.playback_speed = animation_speed
			arena.add_child(effect)
			var attacker := String(event.get("attacker", "player" if side == "enemy" else "enemy"))
			var member: Dictionary = presented.get(attacker, {})
			effect.setup(int(event.get("move_id", 0)), String(member.get("type", "Normale")), Rect2(actor.position, actor.size))
		_play("hit")
	if type == "ko":
		actor.knocked_out()
		wait_time = maxf(0.3, float(actor.animation.get("duration", 0)) / animation_speed)
	if type == "heal" or type == "item": _play("heal")
	if type == "capture": _play("capture")
	if type == "end" and String(event.get("reason", "")) != "fled":
		actor.victory()
		wait_time = maxf(0.3, float(actor.animation.get("duration", 0)) / animation_speed)
	if event.has("dice"): _show_dice(event.dice, ArkUI.MINT if side == "player" else ArkUI.GOLD)
	if event.has("text") and not String(event.text).is_empty(): _log(String(event.text))
	if event.has("snapshot"):
		presented = event.snapshot.duplicate(true)
		_apply_presented()
	await _pause(0.24 / animation_speed if type in ["status", "xp", "switch"] else wait_time)

func _apply_presented() -> void:
	SiteBattle.refresh(self)

func _refresh_health() -> void:
	if not session: return
	_present_snapshot()
	_apply_presented()
	player_summary.text = "Lv. %d · %s" % [int(session.active_creature().level), session.active_creature().type]

func _settle_session() -> void:
	if not challenge_descriptor.is_empty():
		var challenge := ChallengeModel.new()
		challenge.configure(rules, "user://test-game/challenges.json" if testing else "user://challenges.json")
		var hp: int = 0
		for member: Dictionary in session.teams.player: hp += int(member.hp)
		var recorded: Dictionary = challenge.record_result(challenge_descriptor, String(session.result.get("winner", "")) == "player", session.round_number, hp)
		_log(String(recorded.get("message", "Sfida conclusa.")))
		return
	var result: Dictionary = session.result.duplicate(true)
	result["active_slots"] = session.active.duplicate()
	result["captured"] = session.captured.duplicate(true)
	result["events"] = battle_events.duplicate(true)
	result["enemy_party"] = session.teams.enemy
	result.merge(battle_context, false)
	var settled: Dictionary = model.settle_battle(result, session.teams.player)
	if bool(settled.get("ok", false)):
		model.state.erase("battle_checkpoint")
		model.player().active = int(session.active.player)
		if session.kind == "pvp":
			model.player(1 - int(model.state.active_player)).active = int(session.active.enemy)
	_log(String(settled.get("message", "Scontro concluso.")))
	_save()

func _leave_battle() -> void:
	if busy: return
	if not challenge_descriptor.is_empty():
		challenge_descriptor.clear()
		model.state = previous_campaign.duplicate(true)
		previous_campaign.clear()
		session = null
		campaign = {}
		_show_challenges()
		return
	if not model.state.pending.is_empty():
		_log("Il risultato deve essere registrato prima di lasciare lo scontro. Esporta un backup se il problema persiste.")
		return
	session = null
	if int(model.state.league.winner) >= 0: _show_complete()
	elif String(model.state.phase) == "league": _show_league()
	else: _show_location()

func _flee() -> void:
	if busy: return
	if session.finished: _leave_battle(); return
	if session.kind == "wild":
		_queue_action({"type": "flee"})
		return
	var confirmation := ConfirmationDialog.new()
	confirmation.title = "Abbandonare lo scontro?"
	confirmation.dialog_text = "L'incontro sarà registrato come una sconfitta. PV e oggetti usati resteranno quelli attuali."
	confirmation.confirmed.connect(func() -> void:
		session._finish("enemy", "defeat")
		battle_finished = true
		_settle_session()
		_build_actions()
		confirmation.queue_free())
	confirmation.canceled.connect(confirmation.queue_free)
	add_child(confirmation)
	confirmation.popup_centered(Vector2i(590, 210))

func _add_switch_buttons(side: String, forced: bool = false) -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	action_panel.add_child(grid)
	var team: Array = session.teams[side]
	for index in team.size():
		var member: Dictionary = team[index]
		var button := ArkUI.button("%s · %d PV" % [member.name, int(member.hp)], _switch_battle.bind(side, index, forced))
		button.disabled = int(member.hp) <= 0 or int(session.active[side]) == index
		button.add_theme_font_size_override("font_size", 15)
		grid.add_child(button)
		action_buttons.append(button)

func _show_battle_switch() -> void:
	SiteBattle.prepare_overlay(self)
	for child in action_panel.get_children(): child.queue_free()
	_add_switch_buttons(input_side)
	action_panel.add_child(ArkUI.button("Annulla", _build_actions))

func _switch_battle(side: String, index: int, forced: bool) -> void:
	if forced:
		var result: Dictionary = session.switch_active(side, index)
		if bool(result.get("ok", false)):
			_refresh_health()
			_build_actions()
			_save()
	else:
		_queue_action({"type": "switch", "index": index})

func _supreme_dialog() -> void:
	SiteBattle.prepare_overlay(self)
	for child in action_panel.get_children(): child.queue_free()
	for move: Dictionary in rules.available_moves(session.active_creature(input_side)):
		action_panel.add_child(ArkUI.button("Suprema: " + String(move.name) + " · costo 50% PV massimi", _queue_action.bind({"type": "supreme", "move_id": int(move.id)})))
	action_panel.add_child(ArkUI.button("Annulla", _build_actions))

func _show_battle_bag() -> void:
	SiteBattle.prepare_overlay(self)
	for child in action_panel.get_children(): child.queue_free()
	var grid := GridContainer.new()
	grid.columns = 3
	action_panel.add_child(grid)
	for item: Dictionary in _shop_items():
		var quantity := int(model.player().bag.get(item.id, 0))
		if quantity <= 0: continue
		grid.add_child(ArkUI.button("%s (%d)" % [item.name, quantity], _battle_item.bind(item)))
	action_panel.add_child(ArkUI.button("Annulla", _build_actions))

func _battle_item(item: Dictionary) -> void:
	var effect: Dictionary = item.get("effect", {})
	var kind := String(effect.get("kind", ""))
	var prepared: Dictionary = model.battle_item(String(item.id), int(session.active.player))
	if not bool(prepared.get("ok", false)):
		_log(String(prepared.get("message", "Oggetto non disponibile."))); return
	var action: Dictionary = prepared.action
	action["item_id"] = item.id
	if kind == "revive":
		SiteBattle.prepare_overlay(self)
		for child in action_panel.get_children(): child.queue_free()
		for index in session.teams.player.size():
			var member: Dictionary = session.teams.player[index]
			if int(member.hp) == 0:
				var selected := action.duplicate(true)
				selected.target_index = index
				action_panel.add_child(ArkUI.button("Rianima " + String(member.name), _queue_action.bind(selected)))
		action_panel.add_child(ArkUI.button("Annulla", _build_actions))
	else:
		_queue_action(action)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_F11: _toggle_fullscreen()
	elif event.keycode == KEY_M: _toggle_sound()
	elif event.keycode == KEY_ESCAPE:
		if screen == "battle":
			if not busy: _build_actions()
		elif model.state.is_empty(): _show_title()
		elif screen != "world" and screen != "location": _return_to_campaign()
	elif screen == "battle" and not busy and not session.finished and session.needs_switch.is_empty():
		var moves: Array = rules.available_moves(session.active_creature(input_side))
		var index := int(event.keycode) - KEY_1
		if index >= 0 and index < moves.size(): _queue_action({"type": "attack", "move_id": int(moves[index].id)})

func _full_preview() -> void:
	testing = true
	model.new_game([1, 5])
	model.state.players[0].name = "Andrea"
	model.state.players[1].name = "Allenatore 2"
	_show_world()
	var args := OS.get_cmdline_user_args()
	var mode_index := args.find("--preview-screen")
	var mode := args[mode_index + 1] if mode_index >= 0 and mode_index + 1 < args.size() else "world"
	match mode:
		"title": _show_title()
		"names": starter_names_confirmed = false; _show_starters()
		"starters": starter_names_confirmed = true; _show_starters()
		"tools": _show_tools()
		"party": _show_party()
		"bag": _show_bag()
		"dex": _show_dex()
		"shop": _show_shop()
		"box": _show_box()
		"settings": _show_settings()
		"challenges": _show_challenges()
		"interactions": _show_interaction_editor()
		"analysis": _show_creature_details(model.player().party[0], _show_party)
		"league":
			model.player().location = "Roma"
			_show_league()
		"location": _show_location()
		"local":
			model.player().location = "Venezia"
			model.enter_location()
			_show_location()
		"battle": _start_session([rules.creature(28, 5), rules.creature(32, 5)], "npc")
	await get_tree().process_frame
	await get_tree().process_frame
	if "--animate-title" in args and mode == "title":
		await get_tree().create_timer(0.6).timeout
		print("TITLE_VIDEO_POSITION=", title_video.get_stream_position())
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var index := args.find("--screenshot")
	var path := args[index + 1] if index + 1 < args.size() else "user://full-preview.png"
	var error := image.save_png(path)
	for test_path: String in [save_path, save_path + ".bak", save_path + ".tmp"]:
		if test_path.begins_with("user://preview/") and FileAccess.file_exists(test_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))
	get_tree().quit(error)

func _show_party() -> void:
	_clear_page("party")
	SitePlayer.build_party(self)

func _choose_companion(index: int) -> void:
	var party: Array = model.player().party
	if index < 0 or index >= party.size() or int(party[index].hp) <= 0: return
	model.player().active = index
	_save()
	_show_party()

func _deposit(index: int) -> void:
	var result: Dictionary = model.deposit(index)
	_save()
	_show_party()
	_notify(String(result.get("message", "")), not bool(result.get("ok", false)))

func _evolve(index: int) -> void:
	var before := int(model.player().party[index].species_id)
	var result: Dictionary = model.evolve(index)
	_save()
	_show_party()
	_notify(String(result.get("message", "")), not bool(result.get("ok", false)))
	if bool(result.get("ok", false)) and before != int(model.player().party[index].species_id):
		_play("confirm")
		_show_evolution(before, int(model.player().party[index].species_id), _show_party)

func _show_evolution(before: int, after: int, back: Callable) -> void:
	_background("evolution")
	_clear_page("evolution")
	_heading("Un nuovo capitolo", "%s si è evoluto" % String(rules.species[after].nome), "Livello, PV e identità del tuo compagno sono conservati.")
	var stage := Control.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(stage)
	var previous := CreatureActor.new()
	var evolved := CreatureActor.new()
	for actor: CreatureActor in [previous, evolved]:
		actor.anchor_left = 0.25
		actor.anchor_right = 0.75
		actor.anchor_bottom = 1.0
		stage.add_child(actor)
	previous.setup(before, false, not reduced_motion)
	evolved.setup(after, false, not reduced_motion)
	evolved.modulate.a = 0.0
	var reveal := create_tween()
	reveal.tween_property(previous, "modulate:a", 0.0, 0.01 if reduced_motion else 1.2)
	reveal.parallel().tween_property(evolved, "modulate:a", 1.0, 0.01 if reduced_motion else 1.2)
	reveal.tween_callback(evolved.victory)
	_footer(back)

func _show_box() -> void:
	_clear_page("box")
	SitePlayer.build_box(self)

func _box_dialog(slot: String) -> void:
	var member: Dictionary = model.player().box.get(slot, {})
	if member.is_empty(): return
	_clear_page("box-detail")
	_heading("Deposito", String(member.name), "Livello %d · %s · PV %d/%d" % [int(member.level), member.type, int(member.hp), int(member.max_hp)])
	var actor := CreatureActor.new()
	actor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(actor)
	actor.setup(int(member.species_id), false, not reduced_motion)
	page.add_child(ArkUI.button("Ritira in squadra", func() -> void: var result: Dictionary = model.withdraw(slot); _save(); _show_box(); _notify(String(result.get("message", "")), not bool(result.get("ok", false))), true))
	var swaps := ArkUI.hbox()
	var swap_grid := GridContainer.new()
	swap_grid.columns = 3
	page.add_child(swaps)
	swaps.add_child(swap_grid)
	for index in model.player().party.size():
		var current: Dictionary = model.player().party[index]
		swap_grid.add_child(ArkUI.button("Scambia con " + String(current.name), _swap_box.bind(index, slot)))
	var extras := ArkUI.hbox()
	page.add_child(extras)
	extras.add_child(ArkUI.button("Analisi", _show_creature_details.bind(member.duplicate(true), _box_dialog.bind(slot))))
	var definition: Dictionary = rules.species[int(member.species_id)]
	if int(definition.get("evoluzioneId", 0)) > 0 and int(member.level) >= int(definition.get("livelloEvoluzione", 101)):
		extras.add_child(ArkUI.button("Evolvi nel deposito", func() -> void: var result: Dictionary = model.evolve(slot, "box"); _save(); _show_box(); _notify(String(result.get("message", "")), not bool(result.get("ok", false)))))
	for item: Dictionary in model.catalog:
		if item.effect != "masterball" and int(model.player().bag.get(item.id, 0)) > 0:
			extras.add_child(ArkUI.button(String(item.name), _use_box_item.bind(String(item.id), slot)))
	_footer(_show_box)

func _use_box_item(item_id: String, slot: String) -> void:
	var result: Dictionary = model.use_item(item_id, slot, "box")
	_save()
	_box_dialog(slot)
	_notify(String(result.get("message", "")), not bool(result.get("ok", false)))

func _swap_box(index: int, slot: String) -> void:
	var result: Dictionary = model.swap(index, slot)
	_save()
	_show_box()
	_notify(String(result.get("message", "")), not bool(result.get("ok", false)))

func _shop_items() -> Array:
	var result: Array = []
	for item: Dictionary in model.catalog:
		var copy := item.duplicate(true)
		if not copy.get("effect") is Dictionary:
			copy.effect = {"kind": item.get("effect", ""), "fraction": float(item.get("amount", 0)), "status": item.get("status", "")}
		result.append(copy)
	return result

func _show_shop() -> void:
	_clear_page("shop")
	SitePlayer.build_shop(self)

func _update_cart_total() -> void:
	var total: int = 0
	for item: Dictionary in _shop_items(): total += int(cart.get(item.id, 0)) * int(item.price)
	if is_instance_valid(snapshot_label): snapshot_label.text = "Totale: %d monete · Disponibili: %d" % [total, int(model.player().coins)]

func _purchase() -> void:
	var purchase: Dictionary = {}
	for id: String in cart:
		if int(cart[id]) > 0: purchase[id] = int(cart[id])
	var result: Dictionary = model.buy(purchase)
	if bool(result.get("ok", false)): cart.clear(); _save(); _play("confirm")
	_show_shop()
	_notify(String(result.get("message", "")), not bool(result.get("ok", false)))

func _show_bag() -> void:
	_clear_page("bag")
	SitePlayer.build_bag(self)

func _show_item_targets(item_id: String) -> void:
	chosen_item = item_id
	_clear_page("item-target")
	_heading("Borsa", "Scegli un compagno")
	var list := _scroll_column(page)
	for index in model.player().party.size():
		var member: Dictionary = model.player().party[index]
		list.add_child(ArkUI.button("%s · PV %d/%d" % [member.name, int(member.hp), int(member.max_hp)], _apply_item.bind(index)))
	_footer(_show_bag)

func _apply_item(index: int) -> void:
	var result: Dictionary = model.use_item(chosen_item, index)
	_save()
	_show_bag()
	_notify(String(result.get("message", "")), not bool(result.get("ok", false)))

func _show_dex() -> void:
	_clear_page("dex")
	SitePlayer.build_dex(self)

func _show_dex_entry(id: int) -> void:
	_show_creature_details(rules.creature(id, 5), _show_dex)

func _show_creature_details(member: Dictionary, back: Callable) -> void:
	_clear_page("analysis")
	SitePlayer.build_details(self, member, back)

func _show_tools() -> void:
	SiteScenes.tools(self)

func _show_archive() -> void:
	_clear_page("archive")
	_heading("Ultimi 20 scontri", "Registro delle battaglie")
	var list := _scroll_column(page)
	for entry: Dictionary in model.player().archive:
		var card := ArkUI.panel()
		list.add_child(card)
		var column := ArkUI.vbox(8)
		card.add_child(column)
		column.add_child(ArkUI.label(String(entry.get("title", "Battaglia")), 24, ArkUI.GOLD))
		column.add_child(ArkUI.label("%s · Turno %d · %s · %d monete" % [_place(String(entry.get("location", ""))), int(entry.get("turn", 1)), "Vittoria" if bool(entry.get("won", false)) else "Sconfitta", int(entry.get("coins", 0))], 18, ArkUI.MUTED))
		for event: Variant in entry.get("events", []):
			if event is Dictionary and not String(event.get("text", "")).is_empty(): column.add_child(ArkUI.paragraph(String(event.text), 18, ArkUI.TEXT))
	if model.player().archive.is_empty(): list.add_child(ArkUI.label("Nessuno scontro ancora registrato.", 22, ArkUI.MUTED))
	_footer(_show_tools)

func _backup_export() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.json ; Backup Arkamon"])
	dialog.current_file = "Arkamon-backup.json"
	dialog.file_selected.connect(func(path: String) -> void:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file: file.store_string(JSON.stringify({"arkamon_godot": 2, "state": model.state}, "\t")); file.close(); _notify("Backup esportato.")
		else: _notify("Impossibile scrivere il backup.", true)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.75)

func _backup_import() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.json ; Backup Arkamon"])
	dialog.file_selected.connect(func(path: String) -> void: _read_backup(path); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.75)

func _read_backup(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file or file.get_length() > SaveStore.MAX_BYTES:
		_notify("Backup non leggibile o troppo grande.", true); return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or not parsed.get("state") is Dictionary:
		_notify("Formato di backup non valido.", true); return
	var candidate := CampaignModel.new()
	candidate.configure(rules)
	var validation: Dictionary = candidate.load_state(parsed.state)
	if not bool(validation.get("ok", false)):
		_notify(String(validation.get("message", "Backup non valido.")), true); return
	var confirmation := ConfirmationDialog.new()
	confirmation.title = "Ripristinare la campagna?"
	confirmation.dialog_text = "Il backup contiene %s e %s, turno %d. Sostituirà la campagna corrente." % [candidate.state.players[0].name, candidate.state.players[1].name, int(candidate.state.turn)]
	confirmation.confirmed.connect(func() -> void: _restore_backup_model(candidate); confirmation.queue_free())
	confirmation.canceled.connect(confirmation.queue_free)
	add_child(confirmation)
	confirmation.popup_centered(Vector2i(650, 220))

func _restore_backup_model(candidate: CampaignModel) -> void:
	session = null
	challenge_descriptor.clear()
	model = candidate
	_save()
	_resume_loaded()

func _show_league() -> void:
	_clear_page("league")
	_heading("Roma · La Lega", "La strada verso il titolo", "Servono otto medaglie e una squadra in forze. I quattro incontri sono consecutivi: i PV restano quelli rimasti.")
	var info := _scroll_column(page)
	info.add_child(ArkUI.paragraph("Le squadre della Lega si configurano prima dell'ingresso, come nella versione originale. La configurazione fa parte del salvataggio.", 22))
	info.add_child(ArkUI.button("Configura gli avversari", _league_configuration))
	info.add_child(ArkUI.button("Entra nella Lega", _league_start, true))
	info.add_child(ArkUI.button("Prossimo incontro", _league_next))
	info.add_child(ArkUI.button("Squadra e borsa fra gli incontri", _show_party))
	var leave := ArkUI.button("Esci dalla Lega · Passa il turno", _league_leave)
	info.add_child(leave)
	_footer(_league_leave)

func _league_leave() -> void:
	if String(model.player().league.status) == "running":
		var confirmation := ConfirmationDialog.new()
		confirmation.title = "Interrompere il tentativo della Lega?"
		confirmation.dialog_text = "Il tentativo sarà registrato come interrotto. La prossima entrata seguirà la regola di ripresa configurata."
		confirmation.confirmed.connect(func() -> void: model.abandon_league(); _save(); _show_world(); confirmation.queue_free())
		confirmation.canceled.connect(confirmation.queue_free)
		add_child(confirmation)
		confirmation.popup_centered(Vector2i(620, 220))
	else:
		model.state.phase = "world"
		_end_turn()

func _league_configuration() -> void:
	_clear_page("league-config")
	_heading("Regia della Lega", "Scegli i quattro avversari", "Usa le squadre degli allenatori della regione come base della Lega.")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/allenatori.json"))
	var trainers: Array = raw if raw is Array else []
	var selections: Array[OptionButton] = []
	var list := _scroll_column(page)
	for stage in 4:
		list.add_child(ArkUI.label("Incontro %d" % (stage + 1), 22, ArkUI.GOLD))
		var picker := OptionButton.new()
		picker.custom_minimum_size.y = 50
		for trainer: Dictionary in trainers:
			picker.add_item(String(trainer.nome), int(trainer.id))
		picker.select(maxi(0, trainers.size() - 4 + stage))
		list.add_child(picker)
		selections.append(picker)
	var retry := CheckButton.new()
	retry.text = "Dopo una sconfitta riprendi dall'incontro raggiunto"
	list.add_child(retry)
	var items := CheckButton.new()
	items.text = "Consenti oggetti fra gli incontri"
	list.add_child(items)
	var champion_toggle := CheckButton.new()
	champion_toggle.text = "Aggiungi lo scontro con il Campione dopo i quattro incontri"
	list.add_child(champion_toggle)
	var champion_picker := OptionButton.new()
	for trainer: Dictionary in trainers: champion_picker.add_item(String(trainer.nome), int(trainer.id))
	champion_picker.select(maxi(0, trainers.size() - 1))
	list.add_child(champion_picker)
	page.add_child(ArkUI.button("Salva la configurazione", func() -> void:
		var opponents: Array = []
		for picker in selections:
			var entry: Dictionary = trainers[picker.selected]
			opponents.append({"name": entry.nome, "team": entry.squadra.duplicate(true)})
		var champion: Dictionary = trainers[champion_picker.selected]
		var result: Dictionary = model.configure_league({"opponents": opponents, "defeat": "retry-stage" if retry.button_pressed else "restart", "betweenBattleItems": items.button_pressed, "championEnabled": champion_toggle.button_pressed, "champion": {"name": champion.nome, "team": champion.squadra.duplicate(true)} if champion_toggle.button_pressed else null})
		_save(); _show_league(); _notify(String(result.get("message", "Configurazione salvata.")), not bool(result.get("ok", false))), true))
	_footer(_show_league)

func _league_start() -> void:
	var result: Dictionary = model.start_league()
	if bool(result.get("ok", false)) and result.has("enemy"): _begin_descriptor(result)
	elif bool(result.get("ok", false)): _league_next()
	else: _notify(String(result.get("message", "Lega non disponibile.")), true)

func _league_next() -> void:
	_begin_descriptor(model.next_league_battle())

func _return_to_campaign() -> void:
	view_player = -1
	if String(model.state.get("phase", "world")) == "league": _show_league()
	elif String(model.state.get("phase", "world")) == "location": _show_location()
	else: _show_world()

func _show_complete() -> void:
	_clear_page("complete")
	var winner: Dictionary = model.player(int(model.state.league.winner))
	_heading("Campione della regione", "%s ha conquistato la Lega" % winner.name, "La squadra e la storia del viaggio restano nel salvataggio della campagna.")
	var row := ArkUI.hbox()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(row)
	for member: Dictionary in winner.party:
		var column := ArkUI.vbox()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(column)
		var actor := CreatureActor.new()
		actor.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.add_child(actor)
		actor.setup(int(member.species_id), false, not reduced_motion)
		column.add_child(ArkUI.label("%s\nLv. %d" % [member.name, int(member.level)], 20, ArkUI.GOLD))
	page.add_child(ArkUI.button("Diario della vittoria", _show_tools))
	page.add_child(ArkUI.button("Titolo", _show_title, true))
	_focus_first()

func _show_help() -> void:
	_clear_page("help")
	_heading("Il viaggio di due allenatori", "Come si gioca")
	var list := _scroll_column(page)
	list.add_child(ArkUI.paragraph("LA CAMPAGNA\nI due giocatori scelgono starter diversi e si alternano. Ogni turno offre due azioni: due movimenti, oppure un movimento e un'interazione. Aprire un luogo è gratuito; esplorare, sfidare, curare e comprare completano le azioni del turno. Premi Passa il turno quando hai concluso.\n\nLE BATTAGLIE\nIl livello e la paralisi decidono l'iniziativa; a parità di livello si sorteggia. Le mosse tirano D6 e applicano i bonus e le affinità del tipo. La Suprema raddoppia il danno e costa metà dei PV massimi. Dopo un KO scegli un compagno in forze.\n\nSTATI E CURE\nParalisi, sonno e veleno cambiano l'esito dei turni. Le cure in città ripristinano la squadra. Gli oggetti hanno effetti specifici; una scelta senza effetto non consuma l'oggetto.\n\nSQUADRA E DEPOSITO\nLa squadra contiene fino a sei compagni, con differenza massima di cinque livelli. Le catture fuori fascia vanno nel deposito. Le evoluzioni si attivano quando viene raggiunto il livello richiesto.\n\nLA LEGA\nConquista le otto medaglie, raggiungi Roma e affronta gli incontri consecutivi della Lega. La configurazione degli avversari è accessibile dalla Lega.\n\nCOMANDI\nMouse oppure Tab/Invio. In battaglia 1–3 selezionano le mosse. F11 cambia lo schermo, M attiva o disattiva l'audio. I salvataggi sono locali; usa Diario e strumenti per esportare un backup completo.", 22, ArkUI.TEXT))
	_footer(_return_to_campaign)

func _interact_current() -> void:
	var result := InteractionRules.apply(model)
	if bool(result.get("ok", false)) and result.has("enemy"):
		_begin_descriptor(result)
	elif bool(result.get("open_shop", false)):
		_show_shop()
	else:
		_show_location()
		_notify(String(result.get("message", "")), not bool(result.get("ok", false)))
	_save()

func _show_interaction_editor() -> void:
	_clear_page("interactions")
	var editor := InteractionEditor.new()
	editor.setup(model)
	page.add_child(editor)
	editor.back_requested.connect(_show_tools)
	editor.saved.connect(func(result: Dictionary) -> void: if bool(result.get("ok", false)): _save())

func _migrate_demo() -> void:
	var previous := model.state.duplicate(true)
	var result: Dictionary = model.load_state(SaveStore.load_game(SAVE_PATH))
	if not bool(result.get("ok", false)):
		_notify(String(result.get("message", "Il viaggio della demo non è valido.")), true); return
	var candidate := model.state.duplicate(true)
	model.state = previous
	var confirmation := ConfirmationDialog.new()
	confirmation.title = "Importare il viaggio della demo?"
	confirmation.dialog_text = "Squadra e oggetti della prima demo diventeranno una nuova campagna per due. Il viaggio inizierà a Pordenone; la campagna attuale verrà sostituita."
	confirmation.confirmed.connect(func() -> void: model.state = candidate; _save(); _show_world(); confirmation.queue_free())
	confirmation.canceled.connect(confirmation.queue_free)
	add_child(confirmation)
	confirmation.popup_centered(Vector2i(650, 230))

func _show_challenges() -> void:
	_clear_page("challenges")
	challenge_menu = ChallengeMenu.new()
	challenge_menu.setup(rules)
	challenge_menu.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(challenge_menu)
	challenge_menu.back_requested.connect(_show_title)
	challenge_menu.battle_requested.connect(_start_challenge)

func _start_challenge(descriptor: Dictionary) -> void:
	if not bool(descriptor.get("ok", false)): return
	previous_campaign = model.state.duplicate(true)
	challenge_descriptor = descriptor.duplicate(true)
	model.new_game([1, 5], ["Sfida", "Avversario"])
	model.player().party = descriptor.team.duplicate(true)
	model.player().location = "Percorso_1"
	rng.seed = int(descriptor.rng_seed)
	battle_context = {"title": "Sfida · " + String(descriptor.seed), "kind": "npc"}
	_start_session(descriptor.enemy, "npc")

func _show_settings() -> void:
	_clear_page("settings")
	_heading("Strumenti della partita", "Impostazioni", "Personalizza audio, movimento e velocità della tua avventura.")
	var panel := ArkUI.panel()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(panel)
	var column := _scroll_column(panel)
	column.add_child(ArkUI.label("Audio degli effetti", 20))
	column.add_child(ArkUI.button("Attivo" if sound_enabled else "Disattivato", func() -> void: _toggle_sound(); _show_settings()))
	column.add_child(ArkUI.label("Movimento ridotto", 20))
	column.add_child(ArkUI.paragraph("Riduce oscillazioni e movimenti degli attacchi.", 14))
	column.add_child(ArkUI.button("Attivo" if reduced_motion else "Disattivato", func() -> void: reduced_motion = not reduced_motion; _save_preferences(); _show_settings()))
	column.add_child(ArkUI.button("Schermo intero / finestra · F11", _toggle_fullscreen))
	column.add_child(ArkUI.label("Velocità delle animazioni", 20))
	var picker := OptionButton.new()
	picker.add_item("Normale · Tutti i fotogrammi originali", 1)
	picker.add_item("Rapida · 2×", 2)
	picker.add_item("Molto rapida · 3×", 3)
	picker.select(clampi(int(animation_speed) - 1, 0, 2))
	picker.item_selected.connect(func(index: int) -> void: animation_speed = float(index + 1); _save_preferences())
	column.add_child(picker)
	_footer(_show_title if model.state.is_empty() else _return_to_campaign)

func _load_preferences() -> void:
	super._load_preferences()
	var config := ConfigFile.new()
	if config.load(preferences_path) == OK: animation_speed = clampf(float(config.get_value("preferences", "animation_speed", 1.0)), 1.0, 3.0)

func _save_preferences() -> void:
	super._save_preferences()
	if testing: return
	var config := ConfigFile.new()
	config.load(preferences_path)
	config.set_value("preferences", "animation_speed", animation_speed)
	config.save(preferences_path)

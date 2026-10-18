extends SceneTree
## Real two-player campaign scene: travel, capture, settlement and durable PvP.

const TEST_SAVE: String = "user://test-game/campaign.json"
const TEST_PREFS: String = "user://test-game/preferences.cfg"
var app: Variant
var checks: int = 0
var failures: int = 0
var finished: bool = false


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(60.0).timeout.connect(_timeout)
	_cleanup()
	await _open_app()
	check(app.save_path == TEST_SAVE, "La modalità test conserva il percorso isolato prima di qualsiasi scrittura")
	if app.save_path != TEST_SAVE:
		await _finish()
		return
	check(app.screen == "title", "La nuova scena si apre sul titolo")
	app._show_starters()
	app._new_game(1)
	check(app.screen == "starters" and app.starter_choices.size() == 1, "La prima scelta attende il secondo allenatore")
	app._new_game(1)
	check(app.starter_choices.size() == 1, "I giocatori non possono scegliere lo stesso starter")
	app._new_game(5)
	check(app.screen == "world" and app.model.state.players.size() == 2, "Due starter distinti avviano la campagna")
	check(int(app.model.state.rival_starter) == 9, "Lo starter rimasto viene assegnato al rivale")
	check(app.model.player().location == "Pordenone" and int(app.model.state.actions_left) == 2, "Il primo turno comincia a Pordenone con due azioni")
	var original_id: String = str(app.model.player().party[0].instance_id)
	app._travel("Roma")
	check(app.model.player().location == "Pordenone" and int(app.model.state.actions_left) == 2, "Un viaggio non adiacente viene rifiutato senza spesa")
	app._travel("Venezia")
	check(app.model.player().location == "Venezia" and int(app.model.state.actions_left) == 1, "Una strada adiacente consuma un solo movimento")
	app._enter_location()
	check(app.screen == "location" and int(app.model.state.actions_left) == 1, "Entrare nella città non consuma l'azione rimasta")
	await _check_pages()
	app._show_world()
	app._travel("Percorso_1")
	check(app.model.player().location == "Percorso_1" and int(app.model.state.actions_left) == 0, "Il secondo movimento esaurisce il budget condiviso")
	app._enter_location()
	app._wild_encounter("A")
	check(app.screen == "location" and app.session == null and app.model.state.pending.is_empty(), "Un turno senza azioni non può aprire un incontro")
	app._end_turn()
	check(int(app.model.state.active_player) == 1 and int(app.model.state.actions_left) == 2, "Passa il turno consegna due azioni al secondo giocatore")
	app._travel("Venezia")
	app._travel("Percorso_1")
	app._end_turn()
	check(int(app.model.state.active_player) == 0 and app.model.state.players[0].location == app.model.state.players[1].location, "I due allenatori possono raggiungere lo stesso percorso")
	app._enter_location()
	app.model.rng.seed = 42
	app._wild_encounter("A")
	check(app.screen == "battle" and app.session != null and app.session.kind == "wild", "Il cespuglio disponibile avvia lo scontro selvatico")
	if app.session == null:
		await _finish()
		return
	check(not app.model.state.pending.is_empty() and int(app.model.state.actions_left) == 0, "L'incontro impegna l'azione e crea un risultato atteso")
	check(app.model.state.has("battle_checkpoint"), "L'inizio dello scontro salva già un punto di ripresa")
	var masterballs: int = int(app.model.player().bag.get("masterball", 0))
	check(masterballs == 1, "La campagna fornisce la Masterball iniziale prevista")
	var wild_id: String = str(app.session.active_creature("enemy").instance_id)
	var masterball: Dictionary = _shop_item("masterball")
	await app._battle_item(masterball)
	while bool(app.busy):
		await process_frame
	check(app.session.finished and app.session.result.reason == "capture", "La Masterball conclude lo scontro con una cattura")
	check(int(app.model.player().bag.get("masterball", 0)) == masterballs - 1, "La borsa perde una sola Masterball dopo l'azione accettata")
	check(app.model.player().party.size() == 2 and app.model.state.pending.is_empty(), "Il settlement aggiunge la creatura e sblocca la campagna")
	if app.model.player().party.size() != 2 or not app.model.state.pending.is_empty():
		push_error("Dettaglio settlement: " + str(app.battle_message.text) + " | party=" + JSON.stringify(app.model.player().party) + " | captured=" + JSON.stringify(app.session.captured) + " | session_party=" + JSON.stringify(app.session.teams.player))
		await _finish()
		return
	check(str(app.model.player().party[0].instance_id) == original_id, "Il settlement conserva l'identità del compagno originale")
	check(str(app.model.player().party[1].instance_id) == wild_id, "La cattura conserva l'identità della creatura incontrata")
	check(app.model.team_within_cap(app.model.player().party), "La squadra catturata rispetta il cap di cinque livelli")
	check(int(app.model.player().captures) == 1 and app.model.player().archive.size() == 1, "Cattura e registro vengono aggiornati una sola volta")
	check(not app.model.state.has("battle_checkpoint"), "Il settlement rimuove il punto di ripresa già concluso")
	app._leave_battle()
	check(app.screen == "location", "Prosegui torna al luogo dell'incontro")
	app._end_turn()
	check(int(app.model.state.active_player) == 1, "La campagna prosegue con il secondo allenatore")
	await _check_pvp_resume()
	_test_model_validation()
	_test_full_storage()
	await _test_chosen_active()
	await _test_challenges()
	await _test_capture_capacity()
	await _test_league_defeat()
	await _test_league_ui()
	await _finish()


func _open_app() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	app = scene.instantiate()
	app.testing = true
	app.fast_mode = true
	app.reduced_motion = true
	app.sound_enabled = false
	app.save_path = TEST_SAVE
	app.preferences_path = TEST_PREFS
	root.add_child(app)
	await process_frame

func _test_capture_capacity() -> void:
	var previous: Dictionary = app.model.snapshot()
	app.model.new_game([1, 5])
	for index in 5:
		var reserve: Dictionary = app.rules.creature(13, 5)
		reserve.instance_id = "capacity-party-%d" % index
		app.model.player().party.append(reserve)
	for box_index in range(1, 31):
		for slot in range(1, 36):
			var member: Dictionary = app.rules.creature(13, 5)
			member.instance_id = "full-box-%d-%d" % [box_index, slot]
			app.model.player().box["%d:%d" % [box_index, slot]] = member
	app.model.player().location = "Percorso_1"
	app.model.enter_location()
	app._wild_encounter("A")
	check(app.session != null and not app.session.finished, "La capienza piena non impedisce di combattere")
	var orbs: int = int(app.model.player().bag.masterball)
	await app._queue_action({"type": "capture"})
	check(not app.session.finished and app.session.round_number == 0, "La cattura normale viene rifiutata prima di tirare senza spazio")
	await app._battle_item(_shop_item("masterball"))
	while bool(app.busy): await process_frame
	check(not app.session.finished and int(app.model.player().bag.masterball) == orbs, "La Masterball non è consumata se squadra e deposito sono pieni")
	check(not app.model.state.pending.is_empty() and app.screen == "battle", "Il rifiuto conserva lo scontro giocabile")
	app.session = null
	app.model.state = previous
	app._show_world()
	app._save()


func _check_pages() -> void:
	app._show_shop()
	check(app.screen == "shop" and _nodes("SpinBox") >= 7, "Arkastore mostra il catalogo e i sette selettori del carrello")
	app._show_bag()
	check(app.screen == "bag" and _nodes("Button") >= 8, "La borsa mostra gli oggetti del catalogo")
	app._show_party()
	check(app.screen == "party" and _nodes("TextureRect") >= 1, "La pagina squadra mostra il compagno reale")
	app._show_box()
	check(app.screen == "box" and _nodes("Button") >= 38, "Il deposito mostra trentacinque slot e i comandi di navigazione")
	app._show_dex()
	check(app.screen == "dex" and _nodes("TextureRect") >= 18, "L'Arkadex mostra una pagina di diciotto forme")
	app._show_tools()
	check(app.screen == "tools" and _nodes("Button") >= 4, "Il diario rende disponibili backup e registro")
	app._show_archive()
	check(app.screen == "archive", "Il registro vuoto si apre prima del primo incontro")
	app._show_league()
	check(app.screen == "league" and _nodes("Button") >= 4, "La pagina Lega espone configurazione e accesso")
	app._league_configuration()
	check(app.screen == "league-config" and _nodes("OptionButton") == 5, "La configurazione Lega permette di scegliere quattro squadre e il Campione opzionale")
	app._show_help()
	check(app.screen == "help", "La guida completa si apre dalla campagna")
	app._show_settings()
	check(app.screen == "settings", "Le impostazioni ereditate si aprono nella scena completa")
	await _test_interaction_editor()
	await process_frame


func _test_interaction_editor() -> void:
	var before: Dictionary = app.model.snapshot()
	app._show_interaction_editor()
	await process_frame
	var editors: Array[Node] = app.page.find_children("*", "InteractionEditor", true, false)
	check(app.screen == "interactions" and editors.size() == 1, "L'editor delle interazioni apre il modulo completo nella campagna")
	if editors.is_empty():
		return
	var editor: InteractionEditor = editors[0]
	var map_index: int = 0
	for index: int in range(editor.location.item_count):
		if str(editor.location.get_item_metadata(index)) == str(app.model.player().location):
			map_index = index
			break
	editor.location.select(map_index)
	editor.location.item_selected.emit(map_index)
	var point_index: int = 0
	for index: int in range(editor.point.item_count):
		if str(editor.point.get_item_metadata(index)) == str(app.model.player().local_node):
			point_index = index
			break
	editor.point.select(point_index)
	editor.point.item_selected.emit(point_index)
	editor.action.select(1)
	editor.dialogue.text = "Una ricompensa di verifica sul punto attuale."
	editor.coins.value = 25
	editor.once.button_pressed = true
	editor._save_entry()
	check(not app.model.state.get("interactions", {}).is_empty(), "Salva interazione collega l'attività al punto selezionato")
	app._show_location()
	var previous_coins: int = int(app.model.player().coins)
	app._interact_current()
	check(int(app.model.player().coins) == previous_coins + 25 and int(app.model.state.actions_left) == 0, "Interagire dal luogo applica il premio e consuma l'azione rimasta")
	app.model.state.actions_left = 1
	app._interact_current()
	check(int(app.model.player().coins) == previous_coins + 25 and int(app.model.state.actions_left) == 1, "Un premio una tantum non viene duplicato da un secondo comando")
	var restored: CampaignModel = CampaignModel.new()
	restored.configure(app.rules)
	check(bool(restored.load_state(JSON.parse_string(JSON.stringify(app.model.snapshot()))).ok), "L'interazione e il completamento sopravvivono al salvataggio JSON")
	var malformed: Dictionary = before.duplicate(true)
	malformed["interactions"] = []
	check(not bool(restored.load_state(malformed).ok), "Un backup con catalogo interazioni malformato viene rifiutato prima della UI")
	app.model.state = before
	app._show_location()
	app._save()


func _check_pvp_resume() -> void:
	# Fixture: make G2 stronger while keeping its actual campaign instance.
	var current: Dictionary = app.model.player().party[0]
	var g2_id: String = str(current.instance_id)
	current.merge(app.rules.creature(int(current.species_id), 10), true)
	check(str(current.instance_id) == g2_id, "La fixture cambia il livello senza sostituire l'istanza")
	var player_zero_ids: Array[String] = []
	for member: Dictionary in app.model.state.players[0].party:
		player_zero_ids.append(str(member.instance_id))
	app._start_pvp()
	check(app.screen == "battle" and app.session.kind == "pvp", "Due allenatori nello stesso luogo possono sfidarsi")
	check(int(app.battle_context.get("opponent_player", -1)) == 0 or int(app.model.state.pending.get("opponent_player", -1)) == 0, "Lo scontro conserva l'identità del secondo allenatore")
	for member: Dictionary in app.session.teams.enemy:
		member.hp = 1
	app._save()
	var stored: Dictionary = SaveStore.load_game(TEST_SAVE)
	check(stored.has("battle_checkpoint") and not stored.pending.is_empty(), "Il salvataggio contiene sessione e descrittore della sfida")
	var first_move: int = int(app.rules.available_moves(app.session.active_creature())[0].id)
	await app._queue_action({"type": "attack", "move_id": first_move})
	check(app.input_side == "enemy" and app.session.round_number == 0, "Il primo input PvP attende la scelta del secondo giocatore")
	var opponent_move: int = int(app.rules.available_moves(app.session.active_creature("enemy"))[0].id)
	await app._queue_action({"type": "attack", "move_id": opponent_move})
	check(not app.session.finished and app.session.needs_switch == ["enemy"], "Il primo KO PvP richiede la riserva del secondo giocatore")
	check(app.session.round_number == 1 and not app.busy, "Il round termina in un punto stabile per il salvataggio")
	var previous_snapshot: Dictionary = app.session.snapshot()
	var invalid_checkpoint: Dictionary = SaveStore.load_game(TEST_SAVE)
	var check_model: CampaignModel = CampaignModel.new()
	check_model.configure(app.rules)
	var corrupted: Dictionary = invalid_checkpoint.duplicate(true)
	corrupted.pending.player = 0
	check(not bool(check_model.load_state(corrupted).ok), "Un checkpoint non può cambiare il proprietario dello scontro")
	corrupted = invalid_checkpoint.duplicate(true)
	corrupted.battle_checkpoint.session.teams.player[0].instance_id = "unrelated-creature"
	check(not bool(check_model.load_state(corrupted).ok), "Il punto di ripresa deve appartenere alle stesse istanze della campagna")
	corrupted = invalid_checkpoint.duplicate(true)
	corrupted.battle_checkpoint.context.pending_id = "battle-999"
	check(not bool(check_model.load_state(corrupted).ok), "Il contesto non può riferirsi a uno scontro diverso")
	corrupted = invalid_checkpoint.duplicate(true)
	corrupted.erase("battle_checkpoint")
	check(not bool(check_model.load_state(corrupted).ok), "Un incontro sospeso richiede una sessione ripristinabile")
	app.queue_free()
	await process_frame
	await _open_app()
	app._continue_game()
	check(app.screen == "battle" and app.session != null, "Riprendi campagna riapre lo scontro invece della mappa")
	if app.session == null:
		check(false, "La sessione PvP viene ricostruita dal checkpoint")
		return
	check(app.session.round_number == 1 and app.session.needs_switch == ["enemy"], "Il checkpoint conserva il round e la sostituzione obbligatoria")
	check(str(app.session.active_creature().instance_id) == g2_id, "La ripresa mantiene la stessa istanza della campagna")
	check(str(app.session.snapshot().rng_state) == str(previous_snapshot.rng_state), "La ripresa non ritira iniziativa o dadi")
	var backup_model: CampaignModel = CampaignModel.new()
	backup_model.configure(app.rules)
	check(bool(backup_model.load_state(SaveStore.load_game(TEST_SAVE)).ok), "Il backup della battaglia sospesa supera la validazione")
	app._restore_backup_model(backup_model)
	check(app.screen == "battle" and app.session.needs_switch == ["enemy"], "Ripristinare un backup sospeso torna direttamente alla battaglia, senza una mappa bloccata")
	check(str(app.session.snapshot().rng_state) == str(previous_snapshot.rng_state), "Anche il ripristino esplicito del backup conserva lo stato dei dadi")
	app._switch_battle("enemy", 1, true)
	check(app.session.needs_switch.is_empty() and int(app.session.active.enemy) == 1, "La riserva può entrare tramite il comando della UI ripresa")
	first_move = int(app.rules.available_moves(app.session.active_creature())[0].id)
	opponent_move = int(app.rules.available_moves(app.session.active_creature("enemy"))[0].id)
	await app._queue_action({"type": "attack", "move_id": first_move})
	await app._queue_action({"type": "attack", "move_id": opponent_move})
	check(app.session.finished and app.session.result.winner == "player", "L'attacco reale della fixture conclude la sfida locale")
	check(app.model.state.pending.is_empty() and not app.model.state.has("battle_checkpoint"), "La conclusione persistita sblocca entrambi i giocatori")
	check(str(app.model.player().party[0].instance_id) == g2_id and int(app.model.player().party[0].level) == 12, "Il settlement PvP conserva l'istanza e non assegna una seconda volta i livelli")
	check(app.model.state.players[0].party.size() == player_zero_ids.size(), "Il secondo allenatore conserva tutti i membri dopo la sfida")
	for index: int in range(player_zero_ids.size()):
		check(str(app.model.state.players[0].party[index].instance_id) == player_zero_ids[index] and int(app.model.state.players[0].party[index].hp) == 0, "Il settlement conserva identità e KO della squadra avversaria")
	app._leave_battle()
	app._end_turn()
	check(int(app.model.state.active_player) == 0 and app.screen == "world", "Il turno può passare al giocatore sconfitto dopo il settlement")
	app._show_party()
	check(app.screen == "party", "La squadra esausta rimane consultabile dopo lo scontro")
	app._save()
	check(SaveStore.has_save(TEST_SAVE), "La campagna completa resta caricabile dopo i due settlement")
	var named_state: Dictionary = {"progress": &"loaded"}
	named_state.instance_id = "string-name-regression"
	check(SaveStore.save_game(named_state, "user://test-game/named_keys.json") == OK, "Il salvataggio accetta chiavi e valori StringName creati dai comandi nativi")
	var named_restored: Dictionary = SaveStore.load_game("user://test-game/named_keys.json")
	check(str(named_restored.get("instance_id", "")) == "string-name-regression" and str(named_restored.get("progress", "")) == "loaded", "Le chiavi native restano leggibili come stringhe dopo JSON")


func _test_model_validation() -> void:
	var candidate: CampaignModel = CampaignModel.new()
	candidate.configure(app.rules)
	candidate.new_game([1, 5])
	var original: Dictionary = candidate.snapshot()
	var invalid: Dictionary = original.duplicate(true)
	invalid.players[1].party[0].instance_id = invalid.players[0].party[0].instance_id
	check(not bool(candidate.load_state(invalid).ok) and candidate.state == original, "Le identità duplicate tra giocatori vengono rifiutate senza mutare la campagna")
	invalid = original.duplicate(true)
	invalid.players[0].box["1:1"] = invalid.players[0].party[0].duplicate(true)
	check(not bool(candidate.load_state(invalid).ok), "Un membro non può apparire contemporaneamente in squadra e deposito")
	invalid = original.duplicate(true)
	invalid.players[0].party[0].erase("instance_id")
	check(not bool(candidate.load_state(invalid).ok), "Un caricamento completo non inventa identità mancanti")
	invalid = original.duplicate(true)
	invalid.players[0].active = 4
	check(not bool(candidate.load_state(invalid).ok), "Un indice attivo fuori squadra viene rifiutato")
	invalid = original.duplicate(true)
	invalid.players[0].badges = [1]
	check(not bool(candidate.load_state(invalid).ok), "Una medaglia senza relativa palestra sconfitta è rifiutata")
	invalid = original.duplicate(true)
	invalid.players[0].defeated = [99999]
	check(not bool(candidate.load_state(invalid).ok), "Il registro non può inventare allenatori sconosciuti")
	invalid = original.duplicate(true)
	invalid.players[0].dex_seen.append(99999)
	check(not bool(candidate.load_state(invalid).ok), "L'Arkadex rifiuta specie fuori catalogo")
	var second: Dictionary = app.rules.creature(13, 5)
	second.instance_id = "chosen-reserve"
	candidate.player().party.append(second)
	candidate.player().active = 1
	var keeper: CampaignModel = CampaignModel.new()
	keeper.configure(app.rules)
	check(bool(keeper.load_state(JSON.parse_string(JSON.stringify(candidate.snapshot()))).ok) and int(keeper.player().active) == 1, "La scelta del compagno resta nel salvataggio JSON")
	keeper.travel("Venezia")
	keeper.travel("Percorso_1")
	keeper.end_turn()
	keeper.end_turn()
	var opening: Dictionary = keeper.encounter("A")
	check(bool(opening.ok), "La fixture di ripristino apre uno scontro valido")
	var party_after: Array = keeper.player().party.duplicate(true)
	party_after[0].status = {"type": "Avvelenato", "turns": -1, "elapsed": 2}
	party_after[1].status = {"type": "Paralizzato", "turns": -1}
	var settled: Dictionary = keeper.settle_battle({"winner": "player", "active_slots": {"player": 1}}, party_after)
	check(bool(settled.ok) and not keeper.player().party[0].has("status") and app.rules.status_name(keeper.player().party[1]) == "Paralizzato", "Il modello elimina gli stati temporanei e conserva la paralisi dopo lo scontro")
	check(int(keeper.player().active) == 1, "Il settlement conserva il compagno scelto dalla sessione")


func _test_full_storage() -> void:
	var full: CampaignModel = CampaignModel.new()
	full.configure(app.rules)
	full.new_game([1, 5])
	var sample: Dictionary = app.rules.creature(13, 5)
	for box_index: int in range(1, 31):
		for slot_index: int in range(1, 36):
			var member: Dictionary = sample.duplicate(true)
			member.instance_id = "capacity-%d-%d" % [box_index, slot_index]
			full.player().box["%d:%d" % [box_index, slot_index]] = member
	var capacity_path: String = "user://test-game/full_capacity.json"
	check(SaveStore.save_game(full.snapshot(), capacity_path) == OK, "Il salvataggio supporta tutti i millecinquanta posti del deposito")
	var loaded: Dictionary = SaveStore.load_game(capacity_path)
	var restored: CampaignModel = CampaignModel.new()
	restored.configure(app.rules)
	check(bool(restored.load_state(loaded).ok) and restored.player().box.size() == 1050, "Tutti i trenta box vengono ricaricati e validati")
	check(str(restored.player().box.get("30:35", {}).get("instance_id", "")) == "capacity-30-35", "Il posto finale del deposito conserva la propria identità")


func _test_chosen_active() -> void:
	var before: Dictionary = app.model.snapshot()
	app.model.new_game([1, 5])
	var first: Dictionary = app.rules.creature(13, 5)
	first.instance_id = "active-player-reserve"
	var second: Dictionary = app.rules.creature(28, 5)
	second.instance_id = "active-enemy-reserve"
	app.model.player(0).party.append(first)
	app.model.player(1).party.append(second)
	app._show_party()
	app._choose_companion(1)
	app.model.player(1).active = 1
	app._start_pvp()
	check(int(app.session.active.player) == 1 and int(app.session.active_creature().species_id) == 13, "La battaglia schiera il compagno scelto da G1")
	check(int(app.session.active.enemy) == 1 and int(app.session.active_creature("enemy").species_id) == 28, "Il PvP schiera il compagno scelto da G2")
	check(int(app.player_actor.get_meta("species", 0)) == 13 and int(app.enemy_actor.get_meta("species", 0)) == 28, "I due attori mostrano i compagni effettivamente schierati")
	app.session = null
	app.model.state = before
	app._show_world()
	app._save()
	var board: WorldBoard = WorldBoard.new()
	board.definition = app.world_data.main_map
	board.size = Vector2(1000, 600)
	var chosen: Array[String] = []
	board.selected.connect(func(id: String) -> void: chosen.append(id))
	root.add_child(board)
	await process_frame
	board.markers[0].pressed.emit()
	board.markers[1].pressed.emit()
	check(chosen.size() == 2 and chosen[0] == str(board.nodes[0].id) and chosen[1] == str(board.nodes[1].id), "I callback dei punti della mappa conservano destinazioni distinte")
	board.queue_free()
	await process_frame


func _test_challenges() -> void:
	var before: Dictionary = app.model.snapshot()
	var persisted_before: Dictionary = SaveStore.load_game(TEST_SAVE)
	app._show_challenges()
	check(app.screen == "challenges" and app.challenge_menu.slots.size() == 6, "La pagina Sfide mostra i sei posti del Fanta-Team")
	check(not app.challenge_menu.descriptor.is_empty() and not app.challenge_menu.start_button.disabled, "La sfida iniziale viene preparata con squadre complete")
	var imported: Dictionary = app.challenge_menu.model.create("UI-ALTRO-SEED", [], "challenge", 2)
	check(bool(imported.ok), "Il generatore prepara un secondo seed per la prova di importazione")
	app.challenge_menu.code_input.text = str(imported.code)
	app.challenge_menu._import_code()
	check(str(app.challenge_menu.descriptor.get("seed", "")) == "UI-ALTRO-SEED", "Importare un codice aggiorna seed e selettori senza perdere il descrittore")
	var descriptor: Dictionary = app.challenge_menu.descriptor.duplicate(true)
	app._start_challenge(descriptor)
	check(app.screen == "battle" and not app.challenge_descriptor.is_empty(), "La sfida a seed apre la stessa arena completa della campagna")
	check(app.session.teams.player.size() == 6 and app.session.teams.enemy.size() == 6, "La sfida schiera sei Arkamon per parte")
	for member: Dictionary in app.session.teams.enemy:
		member.hp = 1
	app.session.initial_side = "player"
	for index: int in range(6):
		var options: Array = app.rules.available_moves(app.session.active_creature())
		await app._queue_action({"type": "attack", "move_id": _offensive_move(options)})
		check(int(app.session.teams.enemy[index].hp) == 0, "La UI risolve il KO %d della sfida a seed" % (index + 1))
	check(app.session.finished and app.session.result.winner == "player", "La sfida si conclude dopo il sesto avversario")
	app._leave_battle()
	check(app.screen == "challenges" and app.model.state == before, "Prosegui ripristina integralmente la campagna precedente")
	check(SaveStore.load_game(TEST_SAVE) == persisted_before, "La sfida non sovrascrive il salvataggio della campagna")
	var scoreboard: ChallengeModel = ChallengeModel.new()
	scoreboard.configure(app.rules, "user://test-game/challenges.json")
	check(scoreboard.leaderboard(descriptor).size() == 1, "Il risultato della sfida viene scritto nel registro separato")
	app._show_world()


func _test_league_defeat() -> void:
	app.session = null
	app.model.new_game([1, 5])
	app.model.player().location = "Roma"
	app.model.player().visited.append("Roma")
	for trainer: Dictionary in app.model.trainers:
		if str(trainer.tipo) == "Capopalestra":
			app.model.player().defeated.append(int(trainer.id))
			app.model.player().badges.append(int(trainer.id))
	app.model.player().party[0].hp = 1
	var opponents: Array = []
	for index: int in range(4):
		opponents.append({"name": "Sfida di recupero %d" % index, "team": [{"pokemonId": 1, "livello": 10}]})
	var configured: Dictionary = app.model.configure_league({"opponents": opponents, "defeat": "retry-stage", "betweenBattleItems": false, "championEnabled": false, "champion": null})
	check(bool(configured.ok), "La verifica di recupero usa una configurazione valida della Lega")
	app._show_league()
	app._league_start()
	var options: Array = app.rules.available_moves(app.session.active_creature())
	await app._queue_action({"type": "attack", "move_id": _offensive_move(options)})
	check(app.session.finished and app.session.result.winner == "enemy" and int(app.model.player().party[0].hp) == 0, "Una sconfitta reale nella Lega conserva il KO del compagno")
	check(str(app.model.player().league.status) == "defeated" and app.model.state.pending.is_empty(), "La sconfitta conclude il tentativo e libera il descrittore")
	app._leave_battle()
	check(app.screen == "league", "Prosegui dalla sconfitta torna alla pagina della Lega")
	app._league_leave()
	check(app.screen == "world" and int(app.model.state.active_player) == 1, "Esci dalla Lega dopo la sconfitta passa il turno senza lasciare la UI bloccata")
	app._end_turn()
	check(int(app.model.state.active_player) == 0 and int(app.model.state.actions_left) == 2 and app.model.player().location == "Roma", "Il giocatore sconfitto riceve un nuovo turno nella città della Lega")
	app._enter_location()
	app._heal_party()
	check(app.screen == "location" and int(app.model.player().party[0].hp) == int(app.model.player().party[0].max_hp), "Il Centro di Roma permette di recuperare la squadra dopo la sconfitta")
	app._end_turn()
	app._end_turn()
	app._show_league()
	app._league_start()
	check(app.screen == "battle" and str(app.model.player().league.status) == "running", "Dopo il recupero il giocatore può iniziare un nuovo tentativo della Lega")
	# The next independent fixture starts a different campaign without saving this attempt.
	app.session = null


func _test_league_ui() -> void:
	app.session = null
	app.model.new_game([1, 5])
	app.model.player().location = "Roma"
	app.model.player().visited.append("Roma")
	for trainer: Dictionary in app.model.trainers:
		if str(trainer.tipo) == "Capopalestra":
			app.model.player().defeated.append(int(trainer.id))
			app.model.player().badges.append(int(trainer.id))
	var lead: Dictionary = app.model.player().party[0]
	var identifier: String = str(lead.instance_id)
	lead.merge(app.rules.creature(int(lead.species_id), 70), true)
	var opponents: Array = []
	for species_id: int in [1, 5, 9, 13]:
		opponents.append({"name": "Avversario di verifica %d" % species_id, "team": [{"pokemonId": species_id, "livello": 5}]})
	var configuration: Dictionary = {"opponents": opponents, "defeat": "restart", "betweenBattleItems": false, "championEnabled": false, "champion": null}
	check(bool(app.model.configure_league(configuration).ok), "La fixture della Lega usa una configurazione valida di quattro avversari")
	app._show_league()
	app._league_start()
	for stage: int in range(4):
		check(app.screen == "battle" and str(app.model.state.pending.kind) == "league", "Lo stadio %d della Lega parte dalla UI" % (stage + 1))
		var choices: Array = app.rules.available_moves(app.session.active_creature())
		await app._queue_action({"type": "attack", "move_id": _offensive_move(choices)})
		check(app.session.finished and app.model.state.pending.is_empty(), "La vittoria reale %d viene registrata e sblocca lo stadio seguente" % (stage + 1))
		check(str(app.model.player().party[0].instance_id) == identifier and int(app.model.player().party[0].level) == 71 + stage, "La Lega conserva l'istanza e assegna una sola volta il livello del KO")
		app._leave_battle()
		if stage < 3:
			check(app.screen == "league" and int(app.model.state.league.winner) == -1, "La UI non mostra il finale prima della quarta vittoria")
			app._league_next()
	check(app.screen == "complete" and int(app.model.state.league.winner) == 0, "Il quarto settlement mostra il finale del Campione")
	var restored: CampaignModel = CampaignModel.new()
	restored.configure(app.rules)
	check(bool(restored.load_state(SaveStore.load_game(TEST_SAVE)).ok) and int(restored.state.league.winner) == 0, "Il finale ottenuto attraverso la UI resta valido nel salvataggio")
	app._show_title()
	app._restore_backup_model(restored)
	check(app.screen == "complete" and app.model.state.pending.is_empty() and not app.model.state.has("battle_checkpoint"), "Ripristinare il backup del Campione torna al finale senza battaglie sospese")


func _offensive_move(options: Array) -> int:
	for entry: Dictionary in options:
		if not bool(entry.status_only) and str(entry.effect) not in ["CURA", "CURA_PCT", "SUPREMA"]:
			return int(entry.id)
	return int(options[0].id)


func _shop_item(item_id: String) -> Dictionary:
	for entry: Dictionary in app._shop_items():
		if str(entry.id) == item_id:
			return entry
	return {}


func _nodes(type_name: String) -> int:
	return app.page.find_children("*", type_name, true, false).size()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("Campagna UI: " + description)


func _cleanup() -> void:
	for path: String in [TEST_SAVE, TEST_SAVE + ".bak", TEST_SAVE + ".tmp", TEST_PREFS, "user://test-game/named_keys.json", "user://test-game/named_keys.json.bak", "user://test-game/named_keys.json.tmp", "user://test-game/full_capacity.json", "user://test-game/full_capacity.json.bak", "user://test-game/full_capacity.json.tmp", "user://test-game/challenges.json", "user://test-game/challenges.json.tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _timeout() -> void:
	if finished:
		return
	finished = true
	push_error("Campagna UI: timeout globale di sessanta secondi.")
	_cleanup()
	quit(1)


func _finish() -> void:
	finished = true
	if is_instance_valid(app):
		app.queue_free()
		await process_frame
	_cleanup()
	print("Campagna UI Arkamon: %d verifiche, %d errori." % [checks, failures])
	quit(0 if failures == 0 else 1)

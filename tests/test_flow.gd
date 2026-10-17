extends SceneTree
## Exercise the real scene and its asynchronous player actions with isolated saves.

const MAIN_SCENE: String = "res://scenes/prototype.tscn"
const TEST_SAVE: String = "user://test-flow/campaign.json"
const TEST_PREFERENCES: String = "user://test-flow/preferences.cfg"

var app: Variant
var checks: int = 0
var failures: int = 0
var finished: bool = false


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(60.0).timeout.connect(_on_timeout)
	_cleanup()
	await _open_app()
	check(app.screen == "title", "Il gioco si apre sul titolo")
	check(not SaveStore.has_save(TEST_SAVE), "Il test comincia senza una campagna precedente")
	app._show_starters()
	check(app.screen == "starters", "Dal titolo si raggiunge la scelta del compagno")
	app._new_game(5)
	check(app.screen == "world" and app.campaign.party.size() == 1, "La scelta dello starter apre il sentiero")
	check(int(app.campaign.starter) == 5 and int(app.campaign.checkpoint) == 0, "La nuova campagna conserva lo starter e comincia dal laboratorio")
	check(SaveStore.has_save(TEST_SAVE), "La nuova partita viene salvata automaticamente")
	app._select_stop(4)
	check(app.screen == "world" and int(app.campaign.checkpoint) == 0, "La sfida finale è bloccata prima di percorrere il sentiero")
	app._show_help()
	check(app.screen == "help", "La guida si apre durante una campagna")
	app._show_settings()
	check(app.screen == "settings", "Le impostazioni si aprono durante una campagna")
	app._show_party()
	app._choose_companion(99)
	check(app.screen == "party" and int(app.campaign.active) == 0, "Un compagno inesistente non cambia la selezione")
	app._show_world()
	app._select_stop(1)
	check(app.screen == "battle" and not app.battle_finished, "La prima tappa avvia un incontro reale")
	await _check_invalid_items()
	await _capture_first_companion()
	app._leave_battle()
	check(app.screen == "world", "Prosegui torna al sentiero dopo la cattura")
	var potions_before_rest: int = int(app.campaign.potions)
	var orbs_before_rest: int = int(app.campaign.orbs)
	app._select_stop(2)
	check(app.screen == "world" and int(app.campaign.checkpoint) == 2, "La sorgente fa avanzare il viaggio alla seconda tappa")
	check(_everyone_healed(), "Il riposo cura anche il compagno appena catturato")
	check(int(app.campaign.potions) == potions_before_rest and int(app.campaign.orbs) == orbs_before_rest, "Il riposo non consuma oggetti")
	await _win_at(3)
	check(int(app.campaign.checkpoint) == 3 and int(app.campaign.wins) == 2, "La seconda vittoria sblocca la radura")
	app._leave_battle()
	await _win_at(4)
	check(bool(app.campaign.completed) and int(app.campaign.checkpoint) == 4, "Vincere la sfida finale completa il viaggio")
	check(int(app.campaign.coins) == 45 and int(app.campaign.wins) == 3, "Cattura e due vittorie assegnano tre ricompense una sola volta")
	check(int(app.campaign.party[0].level) == 8, "Il compagno iniziale guadagna tre livelli nel percorso")
	app._leave_battle()
	check(app.screen == "complete", "Prosegui mostra il finale del viaggio")
	app._show_party()
	app._choose_companion(1)
	check(int(app.campaign.active) == 1, "La creatura catturata può diventare il compagno attivo")
	app._choose_companion(0)
	app._show_complete()
	check(app.screen == "complete", "Il riepilogo finale resta consultabile")
	app._save()
	var expected: Dictionary = app.campaign.duplicate(true)
	app._show_title()
	check(app.screen == "title", "Il titolo resta raggiungibile dopo il finale")
	app.queue_free()
	await process_frame
	await _open_app()
	app._continue_game()
	check(app.screen == "world", "Una nuova istanza riprende la campagna dal disco")
	check(bool(app.campaign.completed) and int(app.campaign.checkpoint) == int(expected.checkpoint), "Il caricamento conserva completamento e tappa")
	check(int(app.campaign.coins) == int(expected.coins) and int(app.campaign.wins) == int(expected.wins), "Il caricamento conserva ricompense e vittorie")
	check(int(app.campaign.captures) == 1 and app.campaign.party.size() == 2, "Il caricamento conserva cattura e squadra")
	check(int(app.campaign.potions) == int(expected.potions) and int(app.campaign.orbs) == int(expected.orbs), "Il caricamento conserva l'inventario")
	check(int(app.campaign.party[0].level) == int(expected.party[0].level) and int(app.campaign.party[0].hp) == int(expected.party[0].hp), "Il caricamento conserva livello e HP")
	check(not app.rules.available_moves(app._active()).is_empty(), "Le mosse funzionano dopo la ricostruzione dal salvataggio")
	await _check_ko_and_rest()
	await _check_valid_potion()
	await _finish()


func _open_app() -> void:
	var scene: PackedScene = load(MAIN_SCENE)
	app = scene.instantiate()
	app.testing = true
	app.fast_mode = true
	app.reduced_motion = true
	app.save_path = TEST_SAVE
	app.preferences_path = TEST_PREFERENCES
	root.add_child(app)
	await process_frame


func _check_invalid_items() -> void:
	var potions: int = int(app.campaign.potions)
	var orbs: int = int(app.campaign.orbs)
	var turn: int = int(app.turn_count)
	var enemy_hp: int = int(app.enemy.hp)
	await app._use_potion()
	check(int(app.campaign.potions) == potions and int(app.turn_count) == turn, "Una pozione a HP pieni non viene consumata e non passa il turno")
	check(int(app.enemy.hp) == enemy_hp, "Un oggetto non utilizzabile non altera il bersaglio")
	app.campaign.potions = 0
	app._active().hp = int(app._active().max_hp) - 1
	var injured_hp: int = int(app._active().hp)
	await app._use_potion()
	check(int(app.campaign.potions) == 0 and int(app._active().hp) == injured_hp and int(app.turn_count) == turn, "Con zero pozioni la richiesta lascia invariati HP e turno")
	app.campaign.potions = potions
	app._active().hp = int(app._active().max_hp)
	app.campaign.orbs = 0
	await app._try_capture()
	check(int(app.campaign.orbs) == 0 and app.campaign.party.size() == 1 and int(app.turn_count) == turn, "Con zero sfere la cattura non modifica squadra o turno")
	app.campaign.orbs = orbs
	while app.campaign.party.size() < 6:
		app.campaign.party.append(app.rules.creature(1))
	await app._try_capture()
	check(int(app.campaign.orbs) == orbs and app.campaign.party.size() == 6, "Una squadra piena impedisce la cattura senza consumare sfere")
	app.campaign.party.resize(1)


func _capture_first_companion() -> void:
	app.enemy.hp = 1
	var seed_for_capture: int = _capture_seed(app.enemy)
	check(seed_for_capture >= 0, "La fixture trova una cattura riuscita senza alterare i dati di gioco")
	if seed_for_capture < 0:
		return
	app.rng.seed = seed_for_capture
	var before: int = int(app.campaign.orbs)
	# Deliberately start once without awaiting, then attempt the same input again.
	app._try_capture()
	check(bool(app.busy), "L'azione asincrona blocca immediatamente i nuovi comandi")
	await app._try_capture()
	check(int(app.campaign.orbs) == before - 1, "Un doppio comando durante l'animazione consuma una sola sfera")
	while bool(app.busy):
		await process_frame
	check(app.battle_finished and app.campaign.party.size() == 2, "La cattura conclude lo scontro e aggiunge un compagno")
	check(int(app.campaign.captures) == 1 and int(app.campaign.wins) == 1, "La cattura conta una sola vittoria e una sola cattura")
	check(int(app.campaign.checkpoint) == 1 and int(app.campaign.coins) == 15, "La cattura sblocca la tappa successiva e assegna la ricompensa")


func _win_at(stop: int) -> void:
	app._select_stop(stop)
	check(app.screen == "battle" and int(app.battle_step) == stop, "La tappa %d apre il proprio incontro" % stop)
	app.enemy.hp = 1
	app.rng.seed = _initiative_seed(true)
	var hp_before: int = int(app._active().hp)
	var potions_before: int = int(app.campaign.potions)
	var orbs_before: int = int(app.campaign.orbs)
	var options: Array = app.rules.available_moves(app._active())
	if options.is_empty():
		check(false, "Il compagno ha una mossa per concludere lo scontro")
		return
	await app._choose_move(int(options[0].id))
	check(app.battle_finished and int(app.enemy.hp) == 0 and not app.busy, "La vittoria alla tappa %d termina senza bloccare i comandi" % stop)
	check(int(app._active().hp) >= hp_before, "Un nemico sconfitto prima di agire non attacca dopo il KO")
	check(int(app.campaign.potions) == potions_before and int(app.campaign.orbs) == orbs_before, "Attaccare non consuma pozioni o sfere")


func _check_ko_and_rest() -> void:
	app._select_stop(3)
	app._active().hp = 1
	app.rng.seed = _initiative_seed(false)
	var wins_before: int = int(app.campaign.wins)
	var coins_before: int = int(app.campaign.coins)
	var potions_before: int = int(app.campaign.potions)
	var orbs_before: int = int(app.campaign.orbs)
	var options: Array = app.rules.available_moves(app._active())
	await app._choose_move(int(options[0].id))
	check(app.battle_finished and int(app._active().hp) == 0, "L'attacco avversario può mandare KO il compagno")
	check(int(app.campaign.wins) == wins_before and int(app.campaign.coins) == coins_before, "Una sconfitta non assegna ricompense né vittorie")
	await app._use_potion()
	await app._try_capture()
	check(int(app.campaign.potions) == potions_before and int(app.campaign.orbs) == orbs_before, "Gli oggetti richiesti a scontro concluso non vengono consumati")
	app._leave_battle()
	app._select_stop(1)
	check(app.screen == "world", "Il compagno esausto non può iniziare un altro incontro")
	app._select_stop(0)
	check(app.screen == "world" and _everyone_healed(), "Il laboratorio rianima e cura la squadra dopo un KO")
	check(int(app.campaign.checkpoint) == 4 and bool(app.campaign.completed), "Un ritorno per curarsi conserva la progressione completata")
	check(int(app.campaign.potions) == potions_before and int(app.campaign.orbs) == orbs_before, "Il recupero dopo un KO è gratuito")


func _check_valid_potion() -> void:
	app._select_stop(3)
	app._active().hp = int(app._active().max_hp) - 1
	var potions_before: int = int(app.campaign.potions)
	var enemy_hp: int = int(app.enemy.hp)
	app.rng.seed = 42
	await app._use_potion()
	check(int(app.campaign.potions) == potions_before - 1, "Una pozione valida consuma esattamente una dose")
	check(int(app.turn_count) == 2 and int(app._active().hp) > 0, "Dopo la cura l'avversario agisce e comincia il turno seguente")
	check(int(app.enemy.hp) == enemy_hp, "La pozione non infligge danni all'avversario")
	app._flee()
	check(app.screen == "world", "La ritirata conclude l'incontro e torna al sentiero")
	var saved: Dictionary = SaveStore.load_game(TEST_SAVE)
	check(int(saved.get("potions", -1)) == potions_before - 1 and bool(saved.get("completed", false)), "La ritirata salva il consumo e conserva il viaggio completato")


func _everyone_healed() -> bool:
	for member: Dictionary in app.campaign.party:
		if int(member.hp) != int(member.max_hp):
			return false
	return true


func _capture_seed(target: Dictionary) -> int:
	var fixture_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	for candidate: int in range(1000):
		fixture_rng.seed = candidate
		var result: Dictionary = app.rules.capture(target, fixture_rng)
		if bool(result.success):
			return candidate
	return -1


func _initiative_seed(player_first: bool) -> int:
	var fixture_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	for candidate: int in range(1000):
		fixture_rng.seed = candidate
		var ours: int = fixture_rng.randi_range(1, 6)
		var theirs: int = fixture_rng.randi_range(1, 6)
		while ours == theirs:
			ours = fixture_rng.randi_range(1, 6)
			theirs = fixture_rng.randi_range(1, 6)
		if (ours > theirs) == player_first:
			return candidate
	return 0


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("Flusso: " + label)


func _on_timeout() -> void:
	if finished:
		return
	finished = true
	push_error("Flusso: timeout globale di 60 secondi; possibile azione bloccata.")
	_cleanup()
	quit(1)


func _cleanup() -> void:
	# Only these four isolated files belong to this test. Never touch campaign.json.
	for path: String in [TEST_SAVE, TEST_SAVE + ".bak", TEST_SAVE + ".tmp", TEST_PREFERENCES]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _finish() -> void:
	finished = true
	if is_instance_valid(app):
		app.queue_free()
		await process_frame
	_cleanup()
	print("Flusso Arkamon: %d verifiche, %d errori." % [checks, failures])
	quit(0 if failures == 0 else 1)

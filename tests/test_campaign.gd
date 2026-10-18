extends SceneTree

const Model = preload("res://scripts/core/campaign_model.gd")
var checks: int = 0
var failures: int = 0
var rules: BattleRules


func _initialize() -> void:
	rules = BattleRules.new()
	_check(rules.load_data(), "catalogo di battaglia")
	_test_world_and_turns()
	_test_atomic_shop_and_items()
	_test_capture_storage_evolution()
	_test_archive_and_loading()
	_test_complete_campaign()
	print("Campagna Arkamon: %d verifiche, %d errori." % [checks, failures])
	quit(1 if failures > 0 else 0)


func _model() -> CampaignModel:
	var model: CampaignModel = Model.new()
	_check(model.configure(rules), "catalogo campagna: " + model.load_error)
	_check(not model.new_game([1, 5], ["Andrea", "Luca"]).is_empty(), "nuova campagna locale")
	return model


func _test_world_and_turns() -> void:
	var model: CampaignModel = _model()
	_check(model.maps.size() >= 29 and model.trainers.size() >= 30 and model.local_maps.size() == 16, "tutti i dati originali")
	_check(model.player().name == "Andrea" and model.player(1).name == "Luca", "nomi distinti")
	_check(model.player().bag == {"masterball": 1} and model.player().coins == 0, "inventario originale senza oggetti regalati")
	_check(int(model.state.rival_starter) == 9, "il rivale riceve lo starter rimasto")
	var before: Dictionary = model.snapshot()
	_check(not model.travel("Roma").ok and model.state == before, "teletrasporto rifiutato atomicamente")
	_check(model.travel("Venezia").ok and model.state.actions_left == 1, "primo movimento")
	_check(model.enter_location().ok and model.state.actions_left == 1, "la vista locale non consuma un'azione")
	_check(model.travel("Percorso_1").ok and model.state.actions_left == 0, "secondo movimento")
	_check(not model.encounter("A").ok, "nessuna terza azione")
	_check(model.end_turn().ok and model.state.active_player == 1 and model.state.actions_left == 2, "passaggio al secondo giocatore")
	_check(model.player().location == "Pordenone" and model.player(0).location == "Percorso_1", "posizioni indipendenti")
	model.end_turn()
	model.enter_location()
	var local: Dictionary = model.local_maps.get("Percorso_1", {})
	var start: String = str(model.player().local_node)
	var destination: String = ""
	for edge: Dictionary in local.get("roads", []):
		if str(edge.get("from", "")) == start:
			destination = str(edge.get("to", ""))
		elif str(edge.get("to", "")) == start:
			destination = str(edge.get("from", ""))
	_check(not destination.is_empty(), "strade locali originali")
	_check(model.local_move(destination).ok and model.state.actions_left == 1, "movimento su nodo connesso")
	before = model.snapshot()
	_check(not model.local_move("nodo-inesistente").ok and model.state == before, "nodo sconnesso rifiutato")
	_check("A" in model.encounters_here(), "cespugli del percorso")
	var battle: Dictionary = model.encounter("A")
	_check(battle.ok and model.state.actions_left == 0 and battle.enemy.size() == 1, "movimento più interazione")
	_check(not model.end_turn().ok, "il turno resta al proprietario della battaglia")
	_check(int(battle.enemy[0].species_id) in model.player().dex_seen, "specie avvistata nel dex")
	_check(int(battle.enemy[0].species_id) not in model.player(1).dex_seen, "dex personale")
	_check(model.settle_battle({"won": false}, model.player().party).ok, "sconfitta selvatica")
	_renew(model)
	_check(not model.encounter("A").ok, "cespuglio consumato per giocatore")
	_check(model.player(1).consumed.is_empty(), "consumo individuale")


func _test_atomic_shop_and_items() -> void:
	var model: CampaignModel = _model()
	model.player().coins = 1000
	var before: Dictionary = model.snapshot()
	_check(not model.buy({"potion": 2, "unknown": 1}).ok and model.state == before, "acquisto misto sconosciuto non parziale")
	_check(not model.buy({"potion": -1}).ok and model.state == before, "quantità negativa rifiutata")
	_check(not model.buy({"potion": 1.5}).ok and model.state == before, "quantità frazionaria rifiutata")
	_check(not model.buy({"masterball": 1}).ok and model.state == before, "fondi insufficienti senza mutazioni")
	_check(model.buy({"potion": 2, "antidote": 1}).ok, "carrello reale valido")
	_check(model.player().coins == 720 and model.player().bag.potion == 2 and model.player().bag.antidote == 1, "prezzi100+80 e inventario atomici")
	_check(model.state.actions_left == 0, "negozio conclude l'interazione")
	_renew(model)
	var creature: Dictionary = model.player().party[0]
	creature.hp = 1
	creature.status = {"type": "Avvelenato", "turns": -1, "elapsed": 3}
	var expected: int = mini(int(creature.max_hp), 1 + int(ceil(float(creature.max_hp) * 0.25)))
	_check(model.use_item("potion", 0).ok and creature.hp == expected, "pozione recupera25percento arrotondato per eccesso")
	_check(creature.has("status") and model.player().bag.potion == 1, "curaHP preserva status e consuma una dose")
	_renew(model)
	_check(model.use_item("antidote", 0).ok and not creature.has("status"), "antidoto rimuove lo status esatto")
	_renew(model)
	model.player().bag.revive = 1
	creature.hp = 0
	creature.status = {"type": "Paralizzato", "turns": -1}
	_check(model.use_item("revive", 0).ok and creature.hp == int(ceil(float(creature.max_hp) * 0.5)), "rianimatore50percento")
	_check(creature.status.type == "Paralizzato", "rianimazione preserva status")
	_renew(model)
	before = model.snapshot()
	_check(not model.use_item("masterball", 0).ok and model.state == before, "masterball non usabile fuori battaglia")
	creature.hp = creature.max_hp
	before = model.snapshot()
	_check(not model.use_item("potion", 0).ok and model.state == before, "cura inutile non consuma oggetti o turno")
	_check(not model.deposit(0).ok, "ultimo compagno non depositabile")


func _test_capture_storage_evolution() -> void:
	var model: CampaignModel = _model()
	model.travel("Venezia")
	model.travel("Percorso_1")
	_renew(model)
	var high: Dictionary = rules.creature(1, 20)
	high.instance_id = "starter-0"
	model.player().party[0] = high
	var battle: Dictionary = model.encounter("A")
	var caught: Dictionary = battle.enemy[0].duplicate(true)
	var caught_id: int = int(caught.species_id)
	_check(model.settle_battle({"won": true, "captured": caught}, model.player().party).ok, "cattura valida")
	_check(model.player().party.size() == 1 and model.player().box.size() == 1, "cattura fuori fascia nel deposito")
	_check(caught_id in model.player().dex_obtained and caught_id in model.player().dex_seen, "dex ottenuto e avvistato")
	_check(model.player(1).dex_obtained == [5], "cattura non condivisa")
	_check(not model.withdraw("1:1").ok and model.player().box.size() == 1, "ritiro fuori fascia rifiutato")
	var low: Dictionary = rules.creature(1, 5)
	low.instance_id = "starter-0"
	model.player().party[0] = low
	_check(model.withdraw("1:1").ok and model.player().party.size() == 2 and model.player().box.is_empty(), "ritiro entro fascia conserva creature")
	_check(model.deposit(1, "2:35").ok and model.player().party.size() == 1 and model.player().box.has("2:35"), "deposito slot reale35")
	_check(model.swap(0, "2:35").ok, "scambio squadra deposito atomico")
	_check(model.player().party.size() + model.player().box.size() == 2, "scambi conservano il numero delle istanze")
	var evolved: Dictionary = rules.creature(1, 15)
	evolved.instance_id = "evolution-test"
	evolved.hp = 3
	evolved.status = {"type": "Avvelenato", "turns": -1, "elapsed": 1}
	model.player().party[0] = evolved
	_check(model.evolve(0).ok, "evoluzione alla soglia reale15")
	_check(model.player().party[0].species_id == 2 and model.player().party[0].hp == 3 and model.player().party[0].status.type == "Avvelenato", "evoluzione conservaHPstatus e identità")
	_check(not model.evolve(0).ok, "seconda evoluzione richiede il livello35")
	_check(model.player().party[0].xp == 0, "nessun accumuloEXP")
	var box_before: Dictionary = model.player().box.duplicate(true)
	for box_index: int in range(1, 31):
		for slot_index: int in range(1, 36):
			var box_creature: Dictionary = rules.creature(13, 5)
			box_creature.instance_id = "box-%d-%d" % [box_index, slot_index]
			model.player().box["%d:%d" % [box_index, slot_index]] = box_creature
	_check(model.player().box.size() == 1050, "30box da35slot")
	_check(not model._capture_destination(model.player().party, model.player().box, caught).ok, "deposito pieno non sovrascrive slot1")
	_check(model.player().box["1:1"].instance_id == "box-1-1", "primo slot conservato")
	model.player().box = box_before


func _test_archive_and_loading() -> void:
	var model: CampaignModel = _model()
	model.travel("Venezia")
	for index: int in range(23):
		model.state.actions_left = 2
		var result: Dictionary = model.start_pvp()
		_check(result.ok, "PvPlocale%d" % index)
		_check(model.settle_battle({"won": true, "events": [{"type": "winner", "value": index}], "enemy_party": model.player(1).party}, model.player().party).ok, "settlementPvP%d" % index)
	_check(model.player().archive.size() == 20 and model.player().archive[0].events[0].value == 3, "archivio conserva ultime20battaglie")
	var before: Dictionary = model.snapshot()
	_check(not model.settle_battle({"won": true}, model.player().party).ok and model.state == before, "settlement idempotente")
	var restored: CampaignModel = _model()
	_check(restored.load_state(before).ok, "snapshot completo ripristinabile")
	_check(restored.player().archive == model.player().archive and restored.player().bag == model.player().bag, "archivio e inventario conservati")
	var damaged: Dictionary = before.duplicate(true)
	damaged.players[0].party[0].hp = -1
	var restored_before: Dictionary = restored.snapshot()
	_check(not restored.load_state(damaged).ok and restored.state == restored_before, "caricamento fallito conserva stato precedente")
	damaged = before.duplicate(true)
	damaged.players[0].box = {"31:1": rules.creature(13, 5)}
	_check(not restored.load_state(damaged).ok and restored.state == restored_before, "slot fuori deposito rifiutato senza corruzione")
	var legacy: Dictionary = {"party": [rules.creature(9, 7)], "coins": 150, "potions": 3, "completed": true}
	_check(restored.load_state(legacy).ok, "migrazione prototipo")
	_check(restored.player().party[0].species_id == 9 and restored.player().coins == 150 and restored.player().bag.potion == 3, "migrazione conserva progressi posseduti")
	_check(restored.player().badges.is_empty() and restored.state.league.winner == -1, "migrazione non inventa medaglie o campione")
	var xp_save: Dictionary = restored.snapshot()
	xp_save.players[0].party[0].xp = 400
	_check(restored.load_state(xp_save).ok and restored.player().party[0].xp == 0, "EXPlegacy azzerata senza regalare livelli")


func _test_complete_campaign() -> void:
	var model: CampaignModel = _model()
	var gyms: Array = []
	for trainer: Dictionary in model.trainers:
		if str(trainer.tipo) == "Capopalestra":
			gyms.append(trainer)
	_check(gyms.size() == 8, "otto capipalestra originali")
	_check(not model.start_league().ok and not model.secret_unlocked(), "Lega e segreto bloccati inizialmente")
	for gym: Dictionary in gyms:
		_go_to(model, str(gym.luogo))
		if int(model.state.actions_left) == 0:
			_renew(model)
		var battle: Dictionary = model.trainer_battle(int(gym.id))
		_check(battle.ok and battle.enemy.size() == 6, "squadra completa di " + str(gym.nome))
		var before_level: int = int(model.player().party[0].level)
		_check(model.settle_battle({"won": true}, model.player().party).ok, "risultato palestra " + str(gym.id))
		_check(int(model.player().party[0].level) == before_level, "settlement non duplicaEXP della sessione")
	_check(model.player().badges.size() == 8 and model.player().coins == 8000, "medaglie e ricompense otto palestre")
	_check(model.secret_unlocked(), "passaggio segreto sbloccato")
	_check(model.state.league.winner == -1, "otto medaglie non equivalgono alla vittoria finale")
	_go_to(model, "Roma")
	if int(model.state.actions_left) == 0:
		_renew(model)
	_check(SECRET() in model.available_destinations(), "strada segreta daRoma")
	_check(model.travel(SECRET()).ok, "ingressoPercorso15")
	_check(model.local_maps.has(SECRET()) and model.enter_location().ok, "mappa segreta originale raggiungibile")
	_check(model.encounters_here().is_empty(), "nessun incontro segreto inventato: Beta non ne configura")
	if int(model.state.actions_left) == 0:
		_renew(model)
	_check(model.travel("Roma").ok, "ritornoRoma")
	if int(model.state.actions_left) == 0:
		_renew(model)
	var configuration: Dictionary = {"version": 1, "opponents": [], "defeat": "restart", "betweenBattleItems": true, "championEnabled": false, "champion": null}
	for index: int in range(4):
		configuration.opponents.append({"name": "Avversario configurato %d" % (index + 1), "team": [{"pokemonId": 13 + index, "livello": 5}]})
	_check(model.configure_league(configuration).ok, "configurazione4avversari reale richiesta comeBeta")
	var owner: int = int(model.state.active_player)
	var opening: Dictionary = model.start_league()
	_check(opening.ok and model.player().league.status == "running", "inizioLega")
	_check(not model.end_turn().ok and not model.travel("Civitavecchia").ok, "turno bloccato nellaLega")
	model.player().party[0].hp = maxi(1, int(model.player().party[0].max_hp) - 2)
	var hp: int = int(model.player().party[0].hp)
	for stage: int in range(4):
		if stage > 0:
			_check(model.next_league_battle().ok, "prossimo avversario%d" % stage)
		_check(model.settle_battle({"won": true}, model.player().party).ok, "Lega vinta%d" % stage)
		_check(model.state.active_player == owner and int(model.player().party[0].hp) == hp, "Lega conserva turnoHP%d" % stage)
		if stage < 3:
			_check(model.state.league.winner == -1, "nessun finale prematuro%d" % stage)
	_check(model.player().league.status == "completed" and model.state.league.winner == owner, "campione solo dopo tutte4sfide")
	_check(not model.next_league_battle().ok and not model.start_league().ok, "finale idempotente")
	var save: Dictionary = model.snapshot()
	var restored: CampaignModel = _model()
	_check(restored.load_state(save).ok and restored.state.league.winner == owner, "vittoria finale persistente")
	var corrupt: Dictionary = save.duplicate(true)
	corrupt.players[owner].league.stage = 3
	_check(not restored.load_state(corrupt).ok, "campione contraffatto rifiutato")


func SECRET() -> String:
	return "Percorso_15"


func _go_to(model: CampaignModel, destination: String) -> void:
	var start: String = str(model.player().location)
	var queue: Array = [start]
	var previous: Dictionary = {start: ""}
	while not queue.is_empty():
		var current: String = str(queue.pop_front())
		if current == destination:
			break
		for edge: Array in model.roads:
			var next: String = str(edge[1]) if str(edge[0]) == current else (str(edge[0]) if str(edge[1]) == current else "")
			if not next.is_empty() and not previous.has(next):
				previous[next] = current
				queue.append(next)
	_check(previous.has(destination), "percorso collegato a " + destination)
	var path: Array = []
	var cursor: String = destination
	while cursor != start and previous.has(cursor):
		path.push_front(cursor)
		cursor = str(previous[cursor])
	for step: String in path:
		if int(model.state.actions_left) == 0:
			_renew(model)
		_check(model.travel(step).ok, "viaggio reale verso " + step)


func _renew(model: CampaignModel) -> void:
	_check(model.end_turn().ok, "passaggio turno avversario")
	_check(model.end_turn().ok, "nuovo turno proprietario")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("CAMPAGNA: " + message)

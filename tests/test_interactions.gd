extends SceneTree
var checks: int = 0
var failures: int = 0

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var rules := BattleRules.new()
	check(rules.load_data(), "Catalogo disponibile")
	var model := CampaignModel.new()
	check(model.configure(rules), "Campagna configurata")
	model.new_game([1, 5])
	model.player().location = "Venezia"
	model.enter_location()
	var node := String(model.player().local_node)
	var entry := {"location": "Venezia", "node_id": node, "type": "reward", "text": "Il viaggiatore lascia una pozione.", "coins": 50, "item_id": "potion", "quantity": 1, "min_badges": 0, "once": true, "shared": false}
	check(InteractionRules.configure(entry, model).ok, "Ricompensa valida configurata sul punto reale")
	check(InteractionRules.current(model).text == entry.text, "La posizione seleziona l'interazione corretta")
	check(InteractionRules.apply(model).ok, "La prima visita consegna la ricompensa")
	check(int(model.player().coins) == 50 and int(model.player().bag.potion) == 1, "Premi trasferiti insieme")
	check(int(model.state.actions_left) == 0, "L'interazione esaurisce il turno")
	model.state.actions_left = 2
	check(not InteractionRules.apply(model).ok, "Non si può ripetere un premio singolo")
	check(int(model.player().coins) == 50, "Il rifiuto non duplica il premio")
	model.end_turn()
	model.player().location = "Venezia"
	model.enter_location()
	check(InteractionRules.apply(model).ok, "Il completamento individuale consente al secondo giocatore di interagire")
	check(int(model.player().coins) == 50, "I due inventari restano separati")
	entry.shared = true
	entry.node_id = String(model.local_maps.Venezia.nodes[0].id)
	entry.min_badges = 1
	model.player().local_node = entry.node_id
	model.state.actions_left = 2
	check(InteractionRules.configure(entry, model).ok, "Requisito medaglia configurabile")
	check(not InteractionRules.apply(model).ok and int(model.state.actions_left) == 2, "Il requisito blocca senza spendere l'azione")
	entry.min_badges = 0
	InteractionRules.configure(entry, model)
	check(InteractionRules.apply(model).ok, "Il completamento condiviso si registra")
	model.end_turn()
	model.player().local_node = entry.node_id
	check(not InteractionRules.apply(model).ok, "Una tappa condivisa non ripaga l'altro allenatore")
	var broken := entry.duplicate(true)
	broken.quantity = -3
	check(not InteractionRules.configure(broken, model).ok, "Quantità negativa rifiutata")
	broken = entry.duplicate(true)
	broken.node_id = "non-esiste"
	check(not InteractionRules.configure(broken, model).ok, "Il grafo non può ricevere punti inventati")
	var before := model.state.duplicate(true)
	check(not InteractionRules.apply(model).ok and model.state == before, "Un'interazione rifiutata non altera la campagna")
	var restored := CampaignModel.new()
	restored.configure(rules)
	var json: Dictionary = JSON.parse_string(JSON.stringify(model.state))
	check(restored.load_state(json).ok, "Le interazioni passano il salvataggio JSON")
	check(restored.state.interactions == json.interactions, "Configurazione conservata nella ripresa")
	_test_tampered_load(rules)
	_test_prerequisites(rules)
	_test_activity_lock_and_heal(rules)
	print("Interazioni Arkamon: %d verifiche, %d errori." % [checks, failures])
	quit(0 if failures == 0 else 1)


func _fresh(rules: BattleRules) -> CampaignModel:
	var model: CampaignModel = CampaignModel.new()
	model.configure(rules)
	model.new_game([1, 5])
	model.player().location = "Venezia"
	model.enter_location()
	return model


func _entry(model: CampaignModel, node: String, amount: int = 5) -> Dictionary:
	return {"location": "Venezia", "node_id": node, "type": "reward", "text": "Una tappa di prova.", "coins": amount, "quantity": 0, "min_badges": 0, "once": true, "shared": false, "prerequisite": ""}


func _test_tampered_load(rules: BattleRules) -> void:
	var model: CampaignModel = _fresh(rules)
	var node: String = str(model.player().local_node)
	check(bool(InteractionRules.configure(_entry(model, node), model).ok), "La fixture del caricamento ha un punto reale configurato")
	var valid: Dictionary = model.snapshot()
	var candidate: CampaignModel = _fresh(rules)
	var before: Dictionary = candidate.snapshot()
	var invalid: Dictionary = valid.duplicate(true)
	invalid.interactions = []
	check(not bool(candidate.load_state(invalid).ok) and candidate.state == before, "Un catalogo di tipo array viene rifiutato senza cambiare la campagna")
	invalid = valid.duplicate(true)
	invalid.interactions[InteractionRules.key("Venezia", node)] = "codice non strutturato"
	check(not bool(candidate.load_state(invalid).ok), "Il caricamento richiede record di interazione strutturati")
	invalid = valid.duplicate(true)
	invalid.interactions[InteractionRules.key("Venezia", node)].node_id = "punto-inventato"
	check(not bool(candidate.load_state(invalid).ok), "Un punto sconosciuto nel backup non entra nel grafo reale")
	invalid = valid.duplicate(true)
	invalid["interaction_completions"] = []
	check(not bool(candidate.load_state(invalid).ok), "Un completamento di tipo array viene rifiutato prima della UI")
	invalid = valid.duplicate(true)
	invalid["interaction_completions"] = {"Venezia:qualcosa:shared": {"value": true}}
	check(not bool(candidate.load_state(invalid).ok), "I completamenti richiedono valori booleani")
	var bad: Dictionary = _entry(model, node)
	bad.min_badges = 9
	check(not bool(InteractionRules.configure(bad, model).ok), "Un requisito superiore alle otto medaglie viene rifiutato")
	bad = _entry(model, node)
	bad.quantity = 1.5
	check(not bool(InteractionRules.configure(bad, model).ok), "Le quantità delle ricompense devono essere intere")
	bad = _entry(model, node)
	bad.item_id = "oggetto-non-esistente"
	check(not bool(InteractionRules.configure(bad, model).ok), "Un premio non può introdurre un oggetto fuori catalogo")
	bad = _entry(model, node)
	bad.type = "trainer"
	bad.trainer_id = 99999
	check(not bool(InteractionRules.configure(bad, model).ok), "La sfida richiede un allenatore presente nella mappa")


func _test_prerequisites(rules: BattleRules) -> void:
	var model: CampaignModel = _fresh(rules)
	var first: String = str(model.local_maps.Venezia.nodes[0].id)
	var second: String = str(model.local_maps.Venezia.nodes[1].id)
	var opening: Dictionary = _entry(model, first)
	var following: Dictionary = _entry(model, second, 7)
	following.prerequisite = InteractionRules.key("Venezia", first)
	check(bool(InteractionRules.configure(opening, model).ok) and bool(InteractionRules.configure(following, model).ok), "Due tappe possono essere collegate da un prerequisito")
	model.player().local_node = second
	var before: Dictionary = model.snapshot()
	check(not bool(InteractionRules.apply(model).ok) and model.state == before, "Il prerequisito assente blocca la ricompensa senza spendere azioni")
	model.player().local_node = first
	check(bool(InteractionRules.apply(model).ok), "La tappa iniziale registra il completamento individuale")
	model.state.actions_left = 2
	model.player().local_node = second
	check(bool(InteractionRules.apply(model).ok) and int(model.player().coins) == 12, "Il completamento iniziale sblocca la seconda ricompensa")
	model.end_turn()
	model.player().location = "Venezia"
	model.enter_location()
	model.player().local_node = second
	check(not bool(InteractionRules.apply(model).ok), "Il prerequisito individuale non viene ereditato dal secondo giocatore")
	model.player().local_node = first
	check(bool(InteractionRules.apply(model).ok), "Il secondo giocatore può completare la propria tappa iniziale")
	model.state.actions_left = 2
	model.player().local_node = second
	check(bool(InteractionRules.apply(model).ok) and int(model.player().coins) == 12, "Entrambe le ricompense individuali restano negli inventari distinti")
	var shared: CampaignModel = _fresh(rules)
	opening.shared = true
	InteractionRules.configure(opening, shared)
	InteractionRules.configure(following, shared)
	shared.player().local_node = first
	check(bool(InteractionRules.apply(shared).ok), "La tappa condivisa viene completata dal primo giocatore")
	shared.end_turn()
	shared.player().location = "Venezia"
	shared.enter_location()
	shared.player().local_node = second
	check(bool(InteractionRules.apply(shared).ok) and int(shared.player().coins) == 7, "Un prerequisito condiviso sblocca la tappa del secondo giocatore")
	shared.state.actions_left = 2
	shared.player().local_node = first
	before = shared.snapshot()
	check(not bool(InteractionRules.apply(shared).ok) and shared.state == before, "La tappa condivisa una tantum non assegna nuovamente il primo premio")


func _test_activity_lock_and_heal(rules: BattleRules) -> void:
	var model: CampaignModel = _fresh(rules)
	var node: String = str(model.player().local_node)
	InteractionRules.configure(_entry(model, node), model)
	model.player().league.status = "running"
	var before: Dictionary = model.snapshot()
	check(not bool(InteractionRules.apply(model).ok) and model.state == before, "Durante la Lega un'interazione non aggira il blocco delle attività")
	model.player().league.status = "idle"
	model.state.league.winner = 0
	before = model.snapshot()
	check(not bool(InteractionRules.apply(model).ok) and model.state == before, "La campagna conclusa non può ricevere premi tramite punti personalizzati")
	model.state.league.winner = -1
	model.state.pending = {"id": "test-lock"}
	before = model.snapshot()
	check(not bool(InteractionRules.apply(model).ok) and model.state == before, "Uno scontro sospeso impedisce premi esterni senza cambiare il checkpoint")
	check(not bool(InteractionRules.configure(_entry(model, node), model).ok), "L'editor non modifica un punto mentre è in corso una battaglia")
	model.state.pending = {}
	model.player().location = "Percorso_1"
	model.enter_location()
	var route_node: String = str(model.player().local_node)
	var healing: Dictionary = {"location": "Percorso_1", "node_id": route_node, "type": "heal", "text": "Una sorgente sul percorso."}
	check(bool(InteractionRules.configure(healing, model).ok), "Una sorgente può essere assegnata a un punto reale fuori città")
	model.player().party[0].hp = 0
	model.player().party[0].status = {"type": "Paralizzato", "turns": -1}
	check(bool(InteractionRules.apply(model).ok) and int(model.player().party[0].hp) == int(model.player().party[0].max_hp) and not model.player().party[0].has("status"), "La sorgente personalizzata rianima, cura e rimuove lo stato")
	check(int(model.state.actions_left) == 0, "La cura sul punto consuma il resto del turno")

func check(value: bool, name_value: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(name_value)

class_name CampaignModel
extends RefCounted
## Native campaign rules, ported from Arkamon-Beta commit 7ec91d1f.
## State is plain JSON data. Saving/rollback belongs to the caller/SaveStore.

const VERSION: int = 2
const TEAM_SIZE: int = 6
const BOX_COUNT: int = 30
const BOX_SLOTS: int = 35
const TEAM_GAP: int = 5
const STARTERS: Array[int] = [1, 5, 9]
const SECRET_LOCATION: String = "Percorso_15"
const STATUS_NAMES: Array[String] = ["Avvelenato", "Paralizzato", "Addormentato"]

var rules: BattleRules
var state: Dictionary = {}
var maps: Array = []
var trainers: Array = []
var encounters: Array = []
var roads: Array = []
var local_maps: Dictionary = {}
var load_error: String = ""
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var catalog: Array = [
	{"id": "potion", "name": "Pozione", "price": 100, "effect": "heal", "amount": 0.25},
	{"id": "super-potion", "name": "Superpozione", "price": 200, "effect": "heal", "amount": 0.5},
	{"id": "revive", "name": "Rianimatore", "price": 300, "effect": "revive", "amount": 0.5},
	{"id": "antidote", "name": "Antidoto", "price": 80, "effect": "cure", "status": "Avvelenato"},
	{"id": "paralysis-heal", "name": "Antiparalisi", "price": 80, "effect": "cure", "status": "Paralizzato"},
	{"id": "awakening", "name": "Sveglia", "price": 80, "effect": "cure", "status": "Addormentato"},
	{"id": "masterball", "name": "Masterball", "price": 1500, "effect": "masterball"},
]


func configure(battle_rules: BattleRules) -> bool:
	rules = battle_rules
	rng.randomize()
	load_error = ""
	var map_data: Variant = _read("res://data/mappe.json")
	var trainer_data: Variant = _read("res://data/allenatori.json")
	var encounter_data: Variant = _read("res://data/incontri.json")
	var road_data: Variant = _read("res://data/world/main_map_roads.json")
	var local_data: Variant = _read("res://data/world/local_maps.json")
	if rules == null or rules.species.is_empty() or not map_data is Array or not trainer_data is Array or not encounter_data is Array or not road_data is Dictionary:
		load_error = "Catalogo della campagna incompleto. Importa tutti i dati originali."
		return false
	maps = map_data.duplicate(true)
	trainers = trainer_data.duplicate(true)
	encounters = encounter_data.duplicate(true)
	_add_generated_encounters()
	roads = road_data.get("connections", []).duplicate(true)
	local_maps = local_data.get("maps", {}).duplicate(true) if local_data is Dictionary else {}
	return not maps.is_empty() and not roads.is_empty()


func new_game(starter_ids: Array = [1, 5], names: Array = []) -> Dictionary:
	if rules == null or starter_ids.size() != 2 or int(starter_ids[0]) == int(starter_ids[1]):
		return {}
	for id: Variant in starter_ids:
		if int(id) not in STARTERS:
			return {}
	state = {"version": VERSION, "players": [], "active_player": 0, "actions_left": 2,
		"turn": 1, "phase": "world", "pending": {}, "battle_serial": 0,
		"rival_starter": 0, "league": {"config": {}, "winner": -1}}
	for index: int in range(2):
		var name_value: String = str(names[index]).strip_edges().left(80) if index < names.size() else "Giocatore %d" % (index + 1)
		if name_value.is_empty():
			name_value = "Giocatore %d" % (index + 1)
		var p: Dictionary = _empty_player(index, name_value)
		p.party.append(_instance(int(starter_ids[index]), 5, "starter-%d" % index))
		_record_species(p, int(starter_ids[index]), true)
		state.players.append(p)
	for id: int in STARTERS:
		if id not in starter_ids:
			state.rival_starter = id
	return state


func player(index: int = -1) -> Dictionary:
	if state.is_empty():
		return {}
	var selected: int = int(state.active_player) if index < 0 else index
	if selected < 0 or selected >= state.players.size():
		return {}
	return state.players[selected]


func available_destinations() -> Array:
	var result: Array = []
	var current: String = str(player().get("location", ""))
	for edge: Variant in roads:
		if not edge is Array or edge.size() != 2:
			continue
		var destination: String = str(edge[1]) if str(edge[0]) == current else (str(edge[0]) if str(edge[1]) == current else "")
		if not destination.is_empty() and destination not in result:
			result.append(destination)
	if secret_unlocked() and current in ["Roma", SECRET_LOCATION]:
		result.append(SECRET_LOCATION if current == "Roma" else "Roma")
	return result


func travel(destination: String) -> Dictionary:
	if not _can_act() or destination not in available_destinations():
		return _fail("Scegli una strada collegata e un'azione disponibile.")
	var p: Dictionary = player()
	p.location = destination
	if destination not in p.visited:
		p.visited.append(destination)
	state.actions_left = int(state.actions_left) - 1
	state.phase = "world"
	_log("Viaggio", "Raggiunta " + destination)
	return _ok("Hai raggiunto " + destination + ".")


func enter_location() -> Dictionary:
	if _locked() or (str(player().get("location", "")) == SECRET_LOCATION and not secret_unlocked()):
		return _fail("Concludi prima l'attività in corso.")
	state.phase = "location"
	var location: String = str(player().location)
	if local_maps.has(location) and not player().local_positions.has(location):
		player().local_positions[location] = str(local_maps[location].get("startNode", ""))
	player().local_node = str(player().local_positions.get(location, ""))
	return _ok("Esplora " + location + ".")


func local_move(node_id: String) -> Dictionary:
	if not _can_act():
		return _fail("Non hai azioni disponibili.")
	var location: String = str(player().location)
	if not local_maps.has(location):
		return _fail("Questo luogo non ha una mappa locale.")
	var definition: Dictionary = local_maps[location]
	var current: String = str(player().local_positions.get(location, definition.get("startNode", "")))
	var connected: bool = false
	for road: Dictionary in definition.get("roads", []):
		if (str(road.get("from", "")) == current and str(road.get("to", "")) == node_id) or (str(road.get("to", "")) == current and str(road.get("from", "")) == node_id):
			connected = true
	if not connected:
		return _fail("Puoi raggiungere soltanto un punto collegato.")
	player().local_positions[location] = node_id
	player().local_node = node_id
	state.actions_left = int(state.actions_left) - 1
	_log("Esplorazione", "%s · %s" % [location, node_id])
	return _ok("Punto raggiunto.")


func end_turn() -> Dictionary:
	if _locked():
		return _fail("Concludi la battaglia o il tentativo della Lega prima di passare.")
	state.active_player = 1 - int(state.active_player)
	state.actions_left = 2
	state.turn = int(state.turn) + 1
	state.phase = "world"
	return _ok("Turno di " + str(player().name) + ".")


func trainers_here() -> Array:
	var result: Array = []
	for trainer: Dictionary in trainers:
		if str(trainer.get("luogo", "")) == str(player().get("location", "")):
			var entry: Dictionary = trainer.duplicate(true)
			entry.defeated = int(trainer.id) in player().get("defeated", [])
			result.append(entry)
	return result


func encounters_here() -> Array:
	var result: Array = []
	for entry: Dictionary in encounters:
		if str(entry.get("luogo", "")) == str(player().get("location", "")):
			var bush: String = str(entry.get("cespuglio", ""))
			if bush not in result:
				result.append(bush)
	return result


func encounter(bush: String = "A") -> Dictionary:
	if not _can_act() or not _battle_ready():
		return _fail("Serve un'azione e una squadra valida con almeno un Arkamon vivo.")
	var key: String = "%s:%s" % [player().location, bush]
	if key in player().consumed:
		return _fail("Hai già esplorato questo cespuglio.")
	var pool: Array = []
	var total: int = 0
	for entry: Dictionary in encounters:
		if str(entry.get("luogo", "")) == str(player().location) and str(entry.get("cespuglio", "")) == bush:
			pool.append(entry)
			total += int({"Comune": 60, "Medio": 30, "Difficile": 10}.get(str(entry.get("probabilita", "")), 0))
	if pool.is_empty() or total <= 0:
		return _fail("Nessun incontro configurato per questo cespuglio.")
	var roll: int = rng.randi_range(1, total)
	var selected: Dictionary = pool.back()
	for entry: Dictionary in pool:
		roll -= int({"Comune": 60, "Medio": 30, "Difficile": 10}.get(str(entry.get("probabilita", "")), 0))
		if roll <= 0:
			selected = entry
			break
	var minimum: int = int(selected.get("livelloMin", 5))
	var maximum: int = int(selected.get("livelloMax", minimum))
	var width: int = maximum - minimum + 1
	var level: int = minimum + ((rng.randi_range(1, 6) - 1) % width if width <= 6 else rng.randi_range(0, width - 1))
	var creature: Dictionary = _instance(int(selected.pokemonId), level)
	if creature.is_empty():
		return _fail("Specie dell'incontro non disponibile.")
	player().consumed.append(key)
	return _begin_battle("wild", [creature], "Incontro selvatico", {"bush": key})


func trainer_battle(trainer_id: int) -> Dictionary:
	if not _can_act() or not _battle_ready():
		return _fail("Serve un'azione e una squadra pronta.")
	var selected: Dictionary = {}
	for trainer: Dictionary in trainers_here():
		if int(trainer.id) == trainer_id:
			selected = trainer
	if selected.is_empty() or trainer_id in player().defeated:
		return _fail("L'allenatore non è disponibile in questo luogo o è già sconfitto.")
	var team: Array = []
	for index: int in range(selected.squadra.size()):
		var slot: Dictionary = selected.squadra[index]
		var species_id: int = int(state.rival_starter) if str(selected.tipo) == "PVP" and index == 0 else int(slot.pokemonId)
		var creature: Dictionary = _instance(species_id, int(slot.livello))
		if not creature.is_empty():
			team.append(creature)
	if team.is_empty():
		return _fail("La squadra dell'allenatore è incompleta.")
	return _begin_battle("npc", team, str(selected.nome), {"trainer_id": trainer_id, "trainer_type": str(selected.tipo)})


func start_pvp() -> Dictionary:
	if not _can_act() or not _battle_ready() or not _battle_ready(player(1 - int(state.active_player))):
		return _fail("Entrambi i giocatori devono avere una squadra pronta.")
	return _begin_battle("pvp", player(1 - int(state.active_player)).party.duplicate(true), "Sfida locale", {"opponent_player": 1 - int(state.active_player)})


func settle_battle(result: Dictionary, party_after: Array = []) -> Dictionary:
	if state.is_empty() or state.pending.is_empty():
		return _fail("Questo incontro è già stato concluso.")
	var pending: Dictionary = state.pending
	if int(pending.player) != int(state.active_player) or (result.has("pending_id") and str(result.pending_id) != str(pending.id)):
		return _fail("Il risultato non appartiene all'incontro corrente.")
	var updated_party: Array = party_after if not party_after.is_empty() else result.get("party", player().party)
	var normalized: Array = _normalize_team(updated_party)
	if normalized.size() != player().party.size() or not _same_instances(player().party, normalized) or not team_within_cap(normalized):
		return _fail("La squadra risultante non coincide con quella entrata nello scontro.")
	var won: bool = bool(result.get("won", str(result.get("winner", "")) in ["player", "A", "0"]))
	var captured: Variant = result.get("captured", result.get("caught", {}))
	var capture: Dictionary = captured if captured is Dictionary else {}
	if not capture.is_empty():
		if str(pending.kind) != "wild" or not won:
			return _fail("La cattura richiede un incontro selvatico concluso.")
		var catch_result: Dictionary = _capture_destination(normalized, player().box, capture)
		if not catch_result.ok:
			return catch_result
		capture = capture.duplicate(true)
		_clear_battle_status([capture])
	_clear_battle_status(normalized)
	player().party = normalized
	var active_slots: Dictionary = result.get("active_slots", {}) if result.get("active_slots", {}) is Dictionary else {}
	if _integer(active_slots.get("player", player().active), 0, normalized.size() - 1):
		player().active = int(active_slots.get("player", player().active))
	if not capture.is_empty():
		_store_captured(capture)
	var reward: int = 0
	if str(pending.kind) == "npc":
		var trainer_type: String = str(pending.get("trainer_type", "NPC"))
		if won:
			if int(pending.trainer_id) not in player().defeated:
				player().defeated.append(int(pending.trainer_id))
				reward = 1000 if trainer_type == "Capopalestra" else (200 if trainer_type == "NPC" else 0)
			if trainer_type == "Capopalestra" and int(pending.trainer_id) not in player().badges:
				player().badges.append(int(pending.trainer_id))
		else:
			reward = -200 if trainer_type in ["NPC", "Capopalestra"] else 0
	player().coins = maxi(0, int(player().coins) + reward)
	if won:
		player().wins = int(player().wins) + 1
	if str(pending.kind) == "pvp" and result.get("enemy_party", []) is Array:
		var other: Array = _normalize_team(result.get("enemy_party", []))
		var opponent: Dictionary = player(int(pending.opponent_player))
		if other.size() == opponent.party.size() and _same_instances(opponent.party, other) and team_within_cap(other):
			_clear_battle_status(other)
			opponent.party = other
			if _integer(active_slots.get("enemy", opponent.active), 0, other.size() - 1):
				opponent.active = int(active_slots.get("enemy", opponent.active))
	var archive: Dictionary = {"id": str(pending.id), "turn": int(state.turn), "location": str(player().location),
		"title": str(pending.title), "kind": str(pending.kind), "won": won, "coins": reward,
		"events": result.get("events", result.get("log", [])).duplicate(true), "team": player().party.duplicate(true)}
	player().archive.append(archive)
	while player().archive.size() > 20:
		player().archive.pop_front()
	_log("Vittoria" if won else "Sconfitta", str(pending.title))
	if str(pending.kind) == "league":
		var progress: Dictionary = player().league
		if won:
			progress.stage = int(progress.stage) + 1
			if int(progress.stage) >= _league_opponents().size():
				progress.status = "completed"
				state.league.winner = int(state.active_player)
				state.league.champion_team = player().party.duplicate(true)
				_log("Campione della regione", str(player().name) + " ha concluso la Lega.")
		else:
			progress.status = "defeated"
	state.pending = {}
	state.erase("battle_checkpoint")
	state.phase = "league" if str(pending.kind) == "league" else "location"
	return _ok("Risultato salvato.", {"won": won, "coins": reward, "captured": not capture.is_empty(), "completed": int(state.league.winner) >= 0})


func heal_party() -> Dictionary:
	if not _can_act() or not has_shop():
		return _fail("Raggiungi un centro in città con un'azione disponibile.")
	for creature: Dictionary in player().party:
		creature.hp = int(creature.max_hp)
		creature.erase("status")
		creature.erase("stato")
	state.actions_left = 0
	_log("Centro", "Squadra curata completamente.")
	return _ok("Tutta la squadra è stata curata.")


func has_shop() -> bool:
	var location: String = str(player().get("location", ""))
	return not location.is_empty() and not location.begins_with("Percorso_")


func buy(cart: Dictionary) -> Dictionary:
	if not _can_act() or not has_shop() or cart.is_empty():
		return _fail("Raggiungi un negozio con un'azione disponibile.")
	var cost: int = 0
	for id: Variant in cart:
		var item: Dictionary = item_definition(str(id))
		var quantity: Variant = cart[id]
		if item.is_empty() or not _integer(quantity, 1, 99) or int(player().bag.get(str(id), 0)) + int(quantity) > 999999:
			return _fail("Carrello non valido: scegli da 1 a 99 oggetti per voce.")
		cost += int(item.price) * int(quantity)
	if cost > int(player().coins):
		return _fail("Monete insufficienti: il carrello non è stato acquistato.")
	player().coins = int(player().coins) - cost
	for id: Variant in cart:
		player().bag[str(id)] = int(player().bag.get(str(id), 0)) + int(cart[id])
	state.actions_left = 0
	_log("ArkaStore", "Acquisto completato: %d monete." % cost)
	return _ok("Acquisto completato.", {"cost": cost})


func item_definition(item_id: String) -> Dictionary:
	for item: Dictionary in catalog:
		if str(item.id) == item_id:
			return item
	return {}


func use_item(item_id: String, index: Variant, storage: String = "party") -> Dictionary:
	if not state.pending.is_empty():
		return _fail("Durante uno scontro usa i comandi della battaglia.")
	var league_running: bool = str(player().league.status) == "running"
	if league_running and not bool(state.league.config.get("betweenBattleItems", false)):
		return _fail("Gli oggetti fra gli incontri della Lega non sono consentiti.")
	if not league_running and not _can_act():
		return _fail("Non hai un'azione disponibile.")
	var item: Dictionary = item_definition(item_id)
	var target: Dictionary = _stored_creature(index, storage)
	if item.is_empty() or target.is_empty() or int(player().bag.get(item_id, 0)) < 1:
		return _fail("Oggetto o Arkamon non disponibile.")
	var hp: int = int(target.hp)
	var maximum: int = int(target.max_hp)
	match str(item.effect):
		"heal":
			if hp <= 0 or hp >= maximum:
				return _fail("La cura richiede un Arkamon vivo e ferito.")
			target.hp = mini(maximum, hp + maxi(1, int(ceil(float(maximum) * float(item.amount)))))
		"revive":
			if hp != 0:
				return _fail("Il Rianimatore si usa solo su un Arkamon KO.")
			target.hp = maxi(1, int(ceil(float(maximum) * float(item.amount))))
		"cure":
			if hp <= 0 or _status(target) != str(item.status):
				return _fail("Questo Arkamon non ha lo status richiesto.")
			target.erase("status")
			target.erase("stato")
		_:
			return _fail("La Masterball si usa soltanto in una battaglia selvatica.")
	player().bag[item_id] = int(player().bag[item_id]) - 1
	if not league_running:
		state.actions_left = 0
	_log("Borsa", "%s usata su %s." % [item.name, target.name])
	return _ok("Oggetto usato.", {"recovered_hp": int(target.hp) - hp})


func battle_item(item_id: String, target_index: int = 0) -> Dictionary:
	var item: Dictionary = item_definition(item_id)
	if state.pending.is_empty() or item.is_empty() or int(player().bag.get(item_id, 0)) <= 0:
		return _fail("L'oggetto non è disponibile in questo incontro.")
	if str(item.effect) == "masterball" and str(state.pending.kind) != "wild":
		return _fail("La Masterball può catturare soltanto Arkamon selvatici.")
	if target_index < 0 or target_index >= player().party.size():
		return _fail("Scegli un Arkamon della squadra.")
	var action: Dictionary = {"type": "item", "effect": str(item.effect), "target_index": target_index}
	if item.has("amount"):
		action.amount = float(item.amount)
	if item.has("status"):
		action.status = str(item.status)
	return _ok("Oggetto pronto.", {"action": action, "item_id": item_id})


func consume_battle_item(item_id: String) -> bool:
	if state.pending.is_empty() or int(player().bag.get(item_id, 0)) <= 0:
		return false
	player().bag[item_id] = int(player().bag[item_id]) - 1
	return true


func deposit(index: int, slot: String = "") -> Dictionary:
	if _locked() or index < 0 or index >= player().party.size() or player().party.size() <= 1:
		return _fail("Conserva almeno un Arkamon in squadra.")
	var target: String = _free_box_slot(player().box) if slot.is_empty() else slot
	if not _valid_box_slot(target) or player().box.has(target):
		return _fail("Lo slot del deposito non è libero.")
	player().box[target] = player().party[index]
	player().party.remove_at(index)
	player().active = mini(int(player().active), player().party.size() - 1)
	return _ok("Arkamon depositato.", {"slot": target})


func withdraw(slot: String) -> Dictionary:
	if _locked() or not player().box.has(slot) or player().party.size() >= TEAM_SIZE:
		return _fail("Slot non disponibile o squadra piena.")
	var candidate: Array = player().party.duplicate(true)
	candidate.append(player().box[slot])
	if not team_within_cap(candidate):
		return _fail("La squadra può avere al massimo cinque livelli di differenza.")
	player().party.append(player().box[slot])
	player().box.erase(slot)
	return _ok("Arkamon aggiunto alla squadra.")


func swap(party_index: int, box_slot: String) -> Dictionary:
	if _locked() or party_index < 0 or party_index >= player().party.size() or not player().box.has(box_slot):
		return _fail("Scegli due slot pieni.")
	var candidate: Array = player().party.duplicate(true)
	candidate[party_index] = player().box[box_slot]
	if not team_within_cap(candidate):
		return _fail("Lo scambio supererebbe la fascia di cinque livelli.")
	var previous: Dictionary = player().party[party_index]
	player().party[party_index] = player().box[box_slot]
	player().box[box_slot] = previous
	return _ok("Scambio completato.")


func choose_active(index: int) -> Dictionary:
	if _locked() or index < 0 or index >= player().party.size() or int(player().party[index].hp) <= 0:
		return _fail("Scegli un compagno in grado di combattere.")
	player().active = index
	return _ok("Compagno scelto.")


func evolve(index: Variant, storage: String = "party") -> Dictionary:
	if not state.pending.is_empty():
		return _fail("Concludi lo scontro prima dell'evoluzione.")
	var old: Dictionary = _stored_creature(index, storage)
	if old.is_empty():
		return _fail("Arkamon non disponibile.")
	var definition: Dictionary = rules.species[int(old.species_id)]
	var evolved_id: int = int(definition.get("evoluzioneId", 0))
	if evolved_id <= 0 or not rules.species.has(evolved_id) or int(old.level) < int(definition.get("livelloEvoluzione", 101)):
		return _fail("Questo Arkamon non può ancora evolversi.")
	var evolved: Dictionary = _instance(evolved_id, int(old.level), str(old.get("instance_id", "")))
	evolved.hp = mini(int(old.hp), int(evolved.max_hp))
	if old.has("status"):
		evolved.status = old.status.duplicate(true) if old.status is Dictionary else old.status
	if old.has("stato"):
		evolved.stato = old.stato.duplicate(true)
	if storage == "party":
		player().party[int(index)] = evolved
	else:
		player().box[str(index)] = evolved
	_record_species(player(), evolved_id, true)
	_log("Evoluzione", "%s ha raggiunto la forma %d." % [old.name, evolved_id])
	return _ok("Evoluzione completata.", {"old_species": int(old.species_id), "new_species": evolved_id})


func team_within_cap(team: Array) -> bool:
	if team.is_empty() or team.size() > TEAM_SIZE:
		return false
	var minimum: int = 100
	var maximum: int = 5
	for creature: Dictionary in team:
		minimum = mini(minimum, int(creature.get("level", 0)))
		maximum = maxi(maximum, int(creature.get("level", 0)))
	return maximum - minimum <= TEAM_GAP


func secret_unlocked() -> bool:
	if player().is_empty():
		return false
	var gyms: Array = []
	for trainer: Dictionary in trainers:
		if str(trainer.get("tipo", "")) == "Capopalestra":
			gyms.append(int(trainer.id))
	if gyms.is_empty():
		return false
	for gym_id: int in gyms:
		if gym_id not in player().defeated:
			return false
	return true


func configure_league(configuration: Dictionary) -> Dictionary:
	if _locked() or int(state.league.winner) >= 0:
		return _fail("La configurazione non può cambiare durante una sfida.")
	for p: Dictionary in state.players:
		if int(p.league.attempt) > 0:
			return _fail("La Lega è già iniziata: conserva la configurazione della partita.")
	var normalized: Dictionary = _normalize_league_config(configuration)
	if normalized.is_empty():
		return _fail("Configura quattro avversari validi, la regola di sconfitta e l'eventuale Campione.")
	state.league.config = normalized
	return _ok("Lega configurata: quattro incontri consecutivi nello stesso turno.")


func start_league() -> Dictionary:
	if not _can_act() or str(player().location) != "Roma" or not secret_unlocked():
		return _fail("Raggiungi Roma con tutte le otto medaglie e un'azione disponibile.")
	if _normalize_league_config(state.league.config).is_empty() or not _battle_ready():
		return _fail("Configura i quattro avversari della Lega e prepara la squadra.")
	var progress: Dictionary = player().league
	if str(state.league.config.defeat) == "restart":
		progress.stage = 0
	progress.status = "running"
	progress.attempt = int(progress.attempt) + 1
	return next_league_battle()


func next_league_battle() -> Dictionary:
	if not state.pending.is_empty() or int(state.league.winner) >= 0 or str(player().league.status) != "running" or not _battle_ready():
		return _fail("Non c'è un prossimo incontro pronto o la squadra è esausta.")
	var opponents: Array = _league_opponents()
	var stage: int = int(player().league.stage)
	if stage < 0 or stage >= opponents.size():
		return _fail("Tutte le sfide sono già concluse.")
	var opponent: Dictionary = opponents[stage]
	var team: Array = []
	for slot: Dictionary in opponent.team:
		team.append(_instance(int(slot.pokemonId), int(slot.livello)))
	return _begin_battle("league", team, str(opponent.name), {"league_stage": stage})


func abandon_league() -> Dictionary:
	if not state.pending.is_empty() or str(player().league.status) != "running":
		return _fail("Concludi prima la battaglia corrente.")
	player().league.status = "defeated"
	return end_turn()


func snapshot() -> Dictionary:
	return state.duplicate(true)


func load_state(value: Dictionary) -> Dictionary:
	# Do all validation in a separate tree. Failure never damages the running game.
	if value.get("version", 0) != VERSION:
		return _migrate_prototype(value)
	if not value.get("players") is Array or value.players.size() != 2 or not _integer(value.get("active_player"), 0, 1) or not _integer(value.get("actions_left"), 0, 2):
		return _fail("Salvataggio campagna non valido.")
	var candidate: Dictionary = value.duplicate(true)
	for custom_field: String in ["interactions", "interaction_completions"]:
		if candidate.has(custom_field):
			if not candidate[custom_field] is Dictionary or candidate[custom_field].size() > 4096:
				return _fail("Interazioni salvate non valide.")
			for custom_key: Variant in candidate[custom_field]:
				if not (custom_key is String or custom_key is StringName): return _fail("Chiave di interazione non valida.")
				var entry: Variant = candidate[custom_field][custom_key]
				if custom_field == "interactions":
					if not entry is Dictionary or not InteractionRules.validate(entry, self).is_empty(): return _fail("Configurazione di interazione non valida.")
				elif not entry is bool: return _fail("Completamento di interazione non valido.")
	var owned_ids: Dictionary = {}
	for index: int in range(2):
		if not candidate.players[index] is Dictionary:
			return _fail("Dati giocatore non validi.")
		var raw: Dictionary = candidate.players[index]
		var normalized: Dictionary = _empty_player(index, str(raw.get("name", "Giocatore %d" % (index + 1))))
		var party: Array = _normalize_team(raw.get("party", []))
		if party.is_empty() or party.size() != raw.get("party", []).size() or not team_within_cap(party) or not _register_owned(raw.party, owned_ids):
			return _fail("Squadra salvata non valida.")
		normalized.party = party
		if not _integer(raw.get("active", 0), 0, party.size() - 1):
			return _fail("Compagno attivo non valido.")
		normalized.active = int(raw.get("active", 0))
		if not _integer(raw.get("coins", 0), 0, 999999999):
			return _fail("Monete salvate non valide.")
		normalized.coins = int(raw.get("coins", 0))
		var box: Variant = raw.get("box", {})
		if not box is Dictionary or box.size() > BOX_COUNT * BOX_SLOTS:
			return _fail("Deposito salvato non valido.")
		for slot: Variant in box:
			var restored: Dictionary = _restore_creature(box[slot])
			if not _valid_box_slot(str(slot)) or restored.is_empty() or not _register_owned([box[slot]], owned_ids):
				return _fail("Slot del deposito non valido.")
			normalized.box[str(slot)] = restored
		var bag: Variant = raw.get("bag", {})
		if not bag is Dictionary:
			return _fail("Borsa salvata non valida.")
		normalized.bag = {}
		for item_id: Variant in bag:
			if not item_definition(str(item_id)).is_empty() and _integer(bag[item_id], 0, 999999):
				normalized.bag[str(item_id)] = int(bag[item_id])
		var location: String = str(raw.get("location", "Pordenone"))
		if not _map_exists(location):
			return _fail("Luogo salvato non riconosciuto.")
		normalized.location = location
		for key: String in ["visited", "defeated", "badges", "consumed", "dex_seen", "dex_obtained", "journal", "archive"]:
			if not raw.get(key, []) is Array:
				return _fail("Progressi del giocatore non validi.")
			normalized[key] = raw.get(key, []).duplicate(true)
		if not _valid_progress(normalized):
			return _fail("Progressi, medaglie o Arkadex non validi.")
		while normalized.archive.size() > 20:
			normalized.archive.pop_front()
		while normalized.journal.size() > 200:
			normalized.journal.pop_front()
		if raw.get("local_positions", {}) is Dictionary:
			normalized.local_positions = raw.get("local_positions", {}).duplicate(true)
		normalized.local_node = str(raw.get("local_node", ""))
		normalized.wins = maxi(0, int(raw.get("wins", 0)))
		normalized.captures = maxi(0, int(raw.get("captures", 0)))
		var progress: Variant = raw.get("league", {})
		if progress is Dictionary and str(progress.get("status", "idle")) in ["idle", "running", "defeated", "completed"] and _integer(progress.get("stage", 0), 0, 5):
			normalized.league = {"status": str(progress.get("status", "idle")), "stage": int(progress.get("stage", 0)), "attempt": maxi(0, int(progress.get("attempt", 0)))}
		for creature: Dictionary in party:
			_record_species(normalized, int(creature.species_id), true)
		for creature: Dictionary in normalized.box.values():
			_record_species(normalized, int(creature.species_id), true)
		candidate.players[index] = normalized
	if not candidate.get("league", {}) is Dictionary:
		return _fail("Lega salvata non valida.")
	var league: Dictionary = candidate.get("league", {})
	var config: Dictionary = _normalize_league_config(league.get("config", {}))
	if not league.get("config", {}) is Dictionary or (not league.get("config", {}).is_empty() and config.is_empty()):
		return _fail("Configurazione della Lega salvata non valida.")
	candidate.league = {"config": config, "winner": int(league.get("winner", -1))}
	if candidate.league.winner < -1 or candidate.league.winner > 1:
		return _fail("Vincitore della Lega non valido.")
	if int(candidate.league.winner) >= 0:
		var winner: Dictionary = candidate.players[int(candidate.league.winner)]
		if config.is_empty() or str(winner.league.status) != "completed" or int(winner.league.stage) != (config.opponents.size() + (1 if bool(config.championEnabled) else 0)):
			return _fail("La vittoria della Lega non corrisponde a una serie completata.")
		candidate.league.champion_team = winner.party.duplicate(true)
	for p: Dictionary in candidate.players:
		if str(p.league.status) == "running" and config.is_empty():
			return _fail("Un tentativo della Lega richiede la configurazione originale.")
	# A pending battle descriptor is retained for durable resume by the UI.
	if not candidate.get("pending", {}) is Dictionary:
		return _fail("Incontro salvato non valido.")
	candidate.pending = candidate.get("pending", {}).duplicate(true)
	if not _integer(candidate.get("turn", 1), 1, 10000000) or not _integer(candidate.get("battle_serial", 0), 0, 1000000000):
		return _fail("Contatori della campagna non validi.")
	candidate.turn = int(candidate.get("turn", 1))
	candidate.battle_serial = int(candidate.get("battle_serial", 0))
	candidate.phase = str(candidate.get("phase", "world"))
	candidate.rival_starter = int(candidate.get("rival_starter", 9))
	if candidate.phase not in ["world", "location", "league", "battle"] or not _integer(candidate.get("rival_starter"), 1, 9) or int(candidate.rival_starter) not in STARTERS:
		return _fail("Fase o starter del rivale non validi.")
	if not _valid_pending_checkpoint(candidate):
		return _fail("Il punto di ripresa non corrisponde alla campagna salvata.")
	state = candidate
	return _ok("Campagna ripristinata.")


func _migrate_prototype(value: Dictionary) -> Dictionary:
	if not value.get("party") is Array or value.party.is_empty():
		return _fail("Formato del salvataggio non riconosciuto.")
	var team: Array = _normalize_team(value.party)
	if team.size() != value.party.size():
		return _fail("Il vecchio salvataggio contiene una squadra non valida.")
	var previous: Dictionary = state
	var species_id: int = int(team[0].species_id)
	var starter: int = species_id if species_id in STARTERS else 1
	new_game([starter, 5 if starter != 5 else 9])
	player().party = team
	player().coins = maxi(0, int(value.get("coins", 0)))
	player().bag["potion"] = clampi(int(value.get("potions", 0)), 0, 999999)
	for creature: Dictionary in team:
		_record_species(player(), int(creature.species_id), true)
	_log("Salvataggio importato", "Squadra e monete del prototipo conservate; la campagna inizia da Pordenone.")
	if state.is_empty():
		state = previous
		return _fail("Migrazione non riuscita.")
	return _ok("Salvataggio del prototipo importato.", {"migrated": true})


func _empty_player(index: int, player_name: String) -> Dictionary:
	return {"id": index + 1, "name": player_name, "party": [], "box": {}, "active": 0,
		"coins": 0, "bag": {"masterball": 1}, "location": "Pordenone", "local_node": "", "local_positions": {},
		"visited": ["Pordenone"], "defeated": [], "badges": [], "consumed": [],
		"dex_seen": [], "dex_obtained": [], "journal": [], "archive": [], "wins": 0, "captures": 0,
		"league": {"status": "idle", "stage": 0, "attempt": 0}}


func _begin_battle(kind: String, enemy_team: Array, title: String, extra: Dictionary = {}) -> Dictionary:
	state.battle_serial = int(state.battle_serial) + 1
	var pending: Dictionary = {"id": "battle-%d" % int(state.battle_serial), "player": int(state.active_player), "kind": kind,
		"title": title, "enemy": enemy_team.duplicate(true), "location": str(player().location)}
	pending.merge(extra, true)
	state.pending = pending
	state.actions_left = 0
	state.phase = "battle"
	for creature: Dictionary in enemy_team:
		_record_species(player(), int(creature.species_id), false)
	return _ok(title, {"kind": kind, "enemy": enemy_team, "title": title, "pending_id": str(pending.id), "trainer_id": int(pending.get("trainer_id", 0))})


func _battle_ready(p: Dictionary = {}) -> bool:
	var selected: Dictionary = player() if p.is_empty() else p
	if not team_within_cap(selected.get("party", [])):
		return false
	for creature: Dictionary in selected.party:
		if int(creature.hp) > 0:
			return true
	return false


func _locked() -> bool:
	if state.is_empty() or not state.get("pending", {}).is_empty() or int(state.get("league", {}).get("winner", -1)) >= 0:
		return true
	for p: Dictionary in state.players:
		if str(p.league.status) == "running":
			return true
	return false


func _can_act() -> bool:
	return not _locked() and int(state.get("actions_left", 0)) > 0


func _stored_creature(index: Variant, storage: String) -> Dictionary:
	if storage == "party":
		if not _integer(index, 0, TEAM_SIZE - 1) or int(index) >= player().party.size():
			return {}
		return player().party[int(index)]
	return player().box.get(str(index), {}) if storage == "box" else {}


func _capture_destination(team: Array, box: Dictionary, creature: Dictionary) -> Dictionary:
	var restored: Dictionary = _restore_creature(creature)
	if restored.is_empty() or int(restored.hp) <= 0:
		return _fail("La creatura catturata non è valida.")
	var combined: Array = team.duplicate(true)
	combined.append(restored)
	if combined.size() <= TEAM_SIZE and team_within_cap(combined):
		return _ok("Squadra.", {"storage": "party"})
	var slot: String = _free_box_slot(box)
	return _fail("Il deposito è pieno: nessun Arkamon è stato sovrascritto.") if slot.is_empty() else _ok("Deposito.", {"storage": "box", "slot": slot})


func _store_captured(creature: Dictionary) -> void:
	var restored: Dictionary = _restore_creature(creature)
	var destination: Dictionary = _capture_destination(player().party, player().box, restored)
	if str(destination.get("storage", "")) == "party":
		player().party.append(restored)
	else:
		player().box[str(destination.slot)] = restored
	player().captures = int(player().captures) + 1
	_record_species(player(), int(restored.species_id), true)


func _record_species(p: Dictionary, species_id: int, obtained: bool) -> void:
	if species_id not in p.dex_seen:
		p.dex_seen.append(species_id)
	if obtained and species_id not in p.dex_obtained:
		p.dex_obtained.append(species_id)


func _instance(species_id: int, level: int, identifier: String = "") -> Dictionary:
	var creature: Dictionary = rules.creature(species_id, level)
	if not creature.is_empty():
		creature.instance_id = identifier if not identifier.is_empty() else "%d-%d-%d" % [species_id, Time.get_ticks_usec(), rng.randi()]
		creature.xp = 0
	return creature


func _restore_creature(value: Variant) -> Dictionary:
	if not value is Dictionary or not _integer(value.get("species_id"), 1, 100000) or not _integer(value.get("level"), 5, 100):
		return {}
	var result: Dictionary = _instance(int(value.species_id), int(value.level), str(value.get("instance_id", "")))
	if result.is_empty() or not _integer(value.get("hp"), 0, int(result.max_hp)):
		return {}
	result.hp = int(value.hp)
	result.xp = 0
	for key: String in ["status", "stato", "pending_evolution"]:
		if value.has(key):
			result[key] = value[key].duplicate(true) if value[key] is Dictionary else value[key]
	if result.has("status"):
		var status_value: Variant = result.status
		if not status_value is Dictionary or not BattleRules.STATUS_DURATIONS.has(str(status_value.get("type", ""))) or not _integer(status_value.get("turns"), -1, 3):
			return {}
		var status_type: String = str(status_value.type)
		if status_type in ["Paralizzato", "Avvelenato"]:
			result.status.turns = -1
		elif int(status_value.turns) < 1 or int(status_value.turns) > int(BattleRules.STATUS_DURATIONS[status_type]):
			return {}
		if status_type == "Avvelenato" and not _integer(status_value.get("elapsed", 0), 0, 10000000):
			return {}
	return result


func _clear_battle_status(team: Array) -> void:
	for member: Dictionary in team:
		if rules.status_name(member) != "Paralizzato":
			rules.clear_status(member)
		member.erase("stato")


func _register_owned(team: Array, ids: Dictionary) -> bool:
	for member: Dictionary in team:
		var identifier: Variant = member.get("instance_id", "")
		if typeof(identifier) not in [TYPE_STRING, TYPE_STRING_NAME] or str(identifier).is_empty() or str(identifier).length() > 160 or ids.has(str(identifier)):
			return false
		ids[str(identifier)] = true
	return true


func _valid_progress(person: Dictionary) -> bool:
	var trainer_ids: Array[int] = []
	var gym_ids: Array[int] = []
	for entry: Dictionary in trainers:
		trainer_ids.append(int(entry.id))
		if str(entry.tipo) == "Capopalestra":
			gym_ids.append(int(entry.id))
	for key: String in ["defeated", "badges", "dex_seen", "dex_obtained"]:
		var seen: Array[int] = []
		for value: Variant in person[key]:
			if not _integer(value, 1, 100000) or int(value) in seen:
				return false
			var id: int = int(value)
			if key == "defeated" and id not in trainer_ids:
				return false
			if key == "badges" and (id not in gym_ids or id not in person.defeated):
				return false
			if key in ["dex_seen", "dex_obtained"] and not rules.species.has(id):
				return false
			seen.append(id)
		person[key] = seen
	for id: Variant in person.dex_obtained:
		if int(id) not in person.dex_seen:
			return false
	for location: Variant in person.visited:
		if typeof(location) not in [TYPE_STRING, TYPE_STRING_NAME] or not _map_exists(str(location)):
			return false
	return true


func _valid_pending_checkpoint(candidate: Dictionary) -> bool:
	var pending: Dictionary = candidate.pending
	if pending.is_empty():
		return not candidate.has("battle_checkpoint") and str(candidate.phase) != "battle"
	if not _integer(pending.get("player"), 0, 1) or int(pending.player) != int(candidate.active_player) or int(candidate.actions_left) != 0 or str(candidate.phase) != "battle":
		return false
	var owner: Dictionary = candidate.players[int(candidate.active_player)]
	var pending_kind: String = str(pending.get("kind", ""))
	if pending_kind not in ["wild", "npc", "pvp", "league"] or str(pending.get("location", "")) != str(owner.location):
		return false
	if str(pending.get("id", "")) != "battle-%d" % int(candidate.battle_serial) or int(candidate.battle_serial) < 1 or not pending.get("enemy") is Array:
		return false
	var enemy: Array = _normalize_team(pending.enemy)
	if enemy.is_empty() or enemy.size() != pending.enemy.size():
		return false
	if pending_kind == "wild" and enemy.size() != 1:
		return false
	if pending_kind == "wild":
		var bush_key: String = str(pending.get("bush", ""))
		var configured: bool = false
		for entry: Dictionary in encounters:
			if "%s:%s" % [entry.get("luogo", ""), entry.get("cespuglio", "")] == bush_key and str(entry.get("luogo", "")) == str(owner.location) and int(entry.get("pokemonId", 0)) == int(enemy[0].species_id) and int(enemy[0].level) >= int(entry.get("livelloMin", 5)) and int(enemy[0].level) <= int(entry.get("livelloMax", 5)):
				configured = true
		if not configured or bush_key not in owner.consumed:
			return false
	if pending_kind == "pvp":
		if not _integer(pending.get("opponent_player"), 0, 1) or int(pending.opponent_player) == int(candidate.active_player):
			return false
		var opponent: Dictionary = candidate.players[int(pending.opponent_player)]
		if str(opponent.location) != str(owner.location) or not _same_instances(opponent.party, enemy):
			return false
	if pending_kind == "npc":
		if not _integer(pending.get("trainer_id"), 1, 100000):
			return false
		var found: bool = false
		for trainer: Dictionary in trainers:
			if int(trainer.id) == int(pending.get("trainer_id", -1)) and str(trainer.luogo) == str(owner.location) and str(trainer.tipo) == str(pending.get("trainer_type", "")):
				found = trainer.squadra.size() == enemy.size() and int(trainer.id) not in owner.defeated
				if found:
					for index: int in range(enemy.size()):
						var expected_id: int = int(candidate.rival_starter) if str(trainer.tipo) == "PVP" and index == 0 else int(trainer.squadra[index].pokemonId)
						if int(enemy[index].species_id) != expected_id or int(enemy[index].level) != int(trainer.squadra[index].livello):
							found = false
		if not found:
			return false
	if pending_kind == "league" and (str(owner.league.status) != "running" or int(owner.league.stage) != int(pending.get("league_stage", -1))):
		return false
	var checkpoint_value: Variant = candidate.get("battle_checkpoint")
	if not checkpoint_value is Dictionary or not checkpoint_value.get("session") is Dictionary or not checkpoint_value.get("context") is Dictionary or not checkpoint_value.get("events", []) is Array:
		return false
	var checkpoint: Dictionary = checkpoint_value
	if str(checkpoint.context.get("pending_id", "")) != str(pending.id) or str(checkpoint.context.get("kind", "")) != pending_kind:
		return false
	var context_enemy: Array = _normalize_team(checkpoint.context.get("enemy", []))
	if context_enemy.is_empty() or not _same_instances(enemy, context_enemy):
		return false
	var session: BattleSession = BattleSession.new()
	session.rules = rules
	if not session.restore(checkpoint.session, RandomNumberGenerator.new()) or session.finished or session.kind != ("npc" if pending_kind == "league" else pending_kind):
		return false
	return _same_instances(owner.party, session.teams.player) and _same_instances(enemy, session.teams.enemy) and team_within_cap(session.teams.player)


func _normalize_team(value: Variant) -> Array:
	var result: Array = []
	if not value is Array or value.size() > TEAM_SIZE:
		return result
	var ids: Array = []
	for raw: Variant in value:
		var creature: Dictionary = _restore_creature(raw)
		if creature.is_empty() or str(creature.instance_id) in ids:
			return []
		ids.append(str(creature.instance_id))
		result.append(creature)
	return result


func _same_instances(before: Array, after: Array) -> bool:
	if before.size() != after.size():
		return false
	for index: int in range(before.size()):
		if str(before[index].get("instance_id", "")) != str(after[index].get("instance_id", "")) or int(before[index].species_id) != int(after[index].species_id):
			return false
	return true


func _free_box_slot(box: Dictionary) -> String:
	for box_index: int in range(1, BOX_COUNT + 1):
		for slot_index: int in range(1, BOX_SLOTS + 1):
			var key: String = "%d:%d" % [box_index, slot_index]
			if not box.has(key):
				return key
	return ""


func _valid_box_slot(key: String) -> bool:
	var parts: PackedStringArray = key.split(":")
	return parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int() and int(parts[0]) >= 1 and int(parts[0]) <= BOX_COUNT and int(parts[1]) >= 1 and int(parts[1]) <= BOX_SLOTS and key == "%d:%d" % [int(parts[0]), int(parts[1])]


func _status(creature: Dictionary) -> String:
	var value: Variant = creature.get("status", creature.get("stato", ""))
	return str(value.get("type", value.get("tipo", ""))) if value is Dictionary else str(value)


func _normalize_league_config(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.get("opponents") is Array or value.opponents.size() != 4 or str(value.get("defeat", "")) not in ["restart", "retry-stage"] or not value.get("championEnabled") is bool:
		return {}
	var result: Dictionary = {"version": 1, "opponents": [], "defeat": str(value.defeat), "betweenBattleItems": bool(value.get("betweenBattleItems", true)), "championEnabled": bool(value.championEnabled), "champion": null}
	var candidates: Array = value.opponents.duplicate(true)
	if result.championEnabled:
		candidates.append(value.get("champion"))
	for index: int in range(candidates.size()):
		var candidate: Variant = candidates[index]
		if not candidate is Dictionary or str(candidate.get("name", "")).strip_edges().is_empty() or not candidate.get("team") is Array or candidate.team.is_empty() or candidate.team.size() > 6:
			return {}
		var team: Array = []
		for slot: Variant in candidate.team:
			if not slot is Dictionary or not _integer(slot.get("pokemonId"), 1, 100000) or not rules.species.has(int(slot.pokemonId)) or not _integer(slot.get("livello"), 5, 100):
				return {}
			team.append({"pokemonId": int(slot.pokemonId), "livello": int(slot.livello)})
		var opponent: Dictionary = {"name": str(candidate.name).strip_edges().left(80), "team": team}
		if index < 4:
			result.opponents.append(opponent)
		else:
			result.champion = opponent
	return result


func _league_opponents() -> Array:
	var config: Dictionary = state.league.config
	var result: Array = config.get("opponents", []).duplicate(true)
	if bool(config.get("championEnabled", false)) and config.get("champion") is Dictionary:
		result.append(config.champion.duplicate(true))
	return result


func _map_exists(location: String) -> bool:
	if location == SECRET_LOCATION:
		return true
	for entry: Dictionary in maps:
		if str(entry.get("nome", "")) == location:
			return true
	return false


func _log(title: String, message: String) -> void:
	player().journal.append({"turn": int(state.turn), "title": title, "message": message, "location": str(player().location)})
	while player().journal.size() > 200:
		player().journal.pop_front()


func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _add_generated_encounters() -> void:
	# Exact runtime catalogue construction from Beta src/data/index.ts and
	# bilanciamento.ts. The raw incontri.json only contains routes 1--3.
	var routes: Array = ["Percorso_4", "Percorso_5", "Percorso_6", "Percorso_7", "Percorso_8", "Percorso_9", "Percorso_10", "Percorso_11", "Percorso_12", "Percorso_13", "Percorso_14"]
	var ranges: Array = [[17, 21], [18, 22], [19, 23], [30, 34], [36, 40], [40, 44], [41, 45], [42, 46], [43, 47], [47, 51], [51, 55]]
	var common: Array = [13, 16, 20, 21, 32, 34]
	var special: Array = [47, 26, 36, 52, 56, 60]
	var bushes: Array = ["A", "B", "C", "D", "E", "F"]
	for route_index: int in range(routes.size()):
		for bush_index: int in range(bushes.size()):
			var level: int = mini(int(ranges[route_index][1]) - 1, int(ranges[route_index][0]) + int(bush_index / 2))
			encounters.append({"luogo": routes[route_index], "cespuglio": bushes[bush_index], "pokemonId": common[bush_index], "probabilita": "Comune", "livelloMin": level, "livelloMax": level + 1})
			encounters.append({"luogo": routes[route_index], "cespuglio": bushes[bush_index], "pokemonId": special[(route_index + bush_index) % special.size()], "probabilita": "Difficile" if bush_index % 3 == 2 else "Medio", "livelloMin": level + 1, "livelloMax": level + 2})


func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= minimum and float(value) <= maximum


func _ok(message: String, extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"ok": true, "message": message}
	result.merge(extra, true)
	return result


func _fail(message: String) -> Dictionary:
	return {"ok": false, "message": message}

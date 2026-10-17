class_name BattleRules
extends RefCounted
## Small, deterministic port of the Beta's D6 battle rules.
## Source: Arkamon-Beta 7ec91d1f4e3e5252317044b1ee300b8b3e4d80a7.

const DATA_PATH: String = "res://data/"
const MIN_LEVEL: int = 5
const MAX_LEVEL: int = 100
const SUPPORTED_EFFECTS: Array[String] = ["", "CURA", "CURA_PCT", "SUPREMA", "VELENO", "SONNO", "CONFUSIONE", "PARALISI", "PARALIZZATO"]
const STATUS_EFFECTS: Dictionary = {"VELENO": "Avvelenato", "SONNO": "Addormentato", "CONFUSIONE": "Confuso", "PARALISI": "Paralizzato", "PARALIZZATO": "Paralizzato"}
const STATUS_DURATIONS: Dictionary = {"Avvelenato": -1, "Addormentato": 3, "Confuso": 2, "Paralizzato": -1}
# Exact sourceMoveId/name/element/owner mapping from the pinned statusMoves.ts catalogue.
const PARALYSIS_MOVES: Array = [
	[221, "Furia Ionica", "Normale", [3, 4]], [225, "Impatto Voltaico", "Elettro", [27]],
	[227, "Impatto Statico", "Elettro", [25]], [230, "Barriera elettrica", "Psico", [21]],
	[242, "Papille Paralizzanti", "Acqua", [70]], [253, "Folgorazione", "Erba", [48]],
	[256, "Stasi Elettrica", "Oscurità", [44]], [270, "Catene rigide", "Erba", [78]],
	[271, "Torpore Artico", "Oscurità", [55]],
]

var species: Dictionary = {}
var moves: Dictionary = {}
var type_chart: Dictionary = {}
var hp_growth: Dictionary = {}
var load_error: String = ""


func load_data() -> bool:
	species.clear()
	moves.clear()
	type_chart.clear()
	hp_growth.clear()
	load_error = ""
	var raw_species: Variant = _read_json(DATA_PATH + "pokemon.json")
	var raw_moves: Variant = _read_json(DATA_PATH + "mosse.json")
	var raw_types: Variant = _read_json(DATA_PATH + "tipi.json")
	var raw_growth: Variant = _read_json(DATA_PATH + "crescita_hp.json")
	if not raw_species is Array or not raw_moves is Array or not raw_types is Dictionary or not raw_growth is Dictionary:
		load_error = "I dati di gioco non sono disponibili o non sono validi."
		return false
	for value: Variant in raw_species:
		if value is Dictionary and int(value.get("id", 0)) > 0:
			species[int(value["id"])] = value.duplicate(true)
	for value: Variant in raw_moves:
		if value is Dictionary and int(value.get("id", 0)) > 0:
			moves[int(value["id"])] = value.duplicate(true)
	var chart_value: Variant = raw_types.get("efficacia", {})
	if chart_value is Dictionary:
		type_chart = chart_value.duplicate(true)
	hp_growth = raw_growth.duplicate(true)
	if species.is_empty() or moves.is_empty() or type_chart.is_empty() or hp_growth.is_empty():
		load_error = "Il catalogo di gioco è incompleto."
		return false
	_install_paralysis_moves()
	return true


func creature(id: int, level: int = 5) -> Dictionary:
	if not species.has(id):
		return {}
	var definition: Dictionary = species[id]
	var safe_level: int = clampi(level, MIN_LEVEL, MAX_LEVEL)
	var growth: float = float(hp_growth.get(str(definition.get("categoria", "")), 1.0))
	var maximum: int = maxi(1, int(definition.get("hpBase", 1)) + int(float(safe_level - MIN_LEVEL) * growth))
	var result: Dictionary = {
		"species_id": id,
		"name": str(definition.get("nome", "Arkamon")),
		"type": str(definition.get("tipo", "Normale")),
		"level": safe_level,
		"hp": maximum,
		"max_hp": maximum,
		"moves": [],
	}
	var move_list: Array = []
	var move_ids: Array = definition.get("mosse", [])
	for move_id: Variant in move_ids:
		if moves.has(int(move_id)):
			move_list.append(_move_for_level(moves[int(move_id)], safe_level))
	result["moves"] = move_list
	return result


func available_moves(fighter: Dictionary) -> Array:
	var result: Array = []
	var canonical: Dictionary = creature(int(fighter.get("species_id", 0)), int(fighter.get("level", MIN_LEVEL)))
	var entries: Array = canonical.get("moves", [])
	for entry: Dictionary in entries:
		if bool(entry.get("available", false)):
			result.append(entry)
	return result


func attack(attacker: Dictionary, defender: Dictionary, move_id: int, rng: RandomNumberGenerator, options: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {
		"ok": false, "dice": [], "damage": 0, "actual_damage": 0,
		"text": "L'azione non è disponibile.", "effect": "", "multiplier": 1.0,
		"heal": 0, "recoil": 0,
	}
	if rng == null or not _valid_fighter(attacker) or not _valid_fighter(defender):
		return result
	if int(attacker["hp"]) <= 0 or int(defender["hp"]) <= 0:
		result["text"] = "Un Arkamon fuori combattimento non può agire o essere attaccato."
		return result
	var selected: Dictionary = {}
	for candidate: Dictionary in available_moves(attacker):
		if int(candidate["id"]) == move_id:
			selected = candidate
			break
	if selected.is_empty():
		result["text"] = "Questa mossa non è disponibile a questo livello o in questa prova."
		return result
	var effect: String = str(selected["effect"])
	var messages: Array[String] = ["%s usa %s!" % [attacker["name"], selected["name"]]]
	result["ok"] = true
	result["effect"] = effect
	result["status_applied"] = ""
	result["status_cured"] = ""
	if effect == "CURA" or effect == "CURA_PCT":
		var amount: int = maxi(1, int(selected["value"]))
		if effect == "CURA_PCT":
			amount = maxi(1, int(float(attacker["max_hp"]) * float(selected["value"]) / 100.0))
		var before: int = int(attacker["hp"])
		attacker["hp"] = mini(int(attacker["max_hp"]), before + amount)
		var restored: int = int(attacker["hp"]) - before
		result["heal"] = restored
		if status_name(attacker) in ["Avvelenato", "Paralizzato"]:
			result["status_cured"] = status_name(attacker)
			clear_status(attacker)
			messages.append("Guarisce da %s." % str(result["status_cured"]))
		messages.append("Recupera %d HP." % restored if restored > 0 else "Ha già tutti gli HP.")
		result["text"] = " ".join(messages)
		return result
	var dice: Array = []
	var total: int = 0
	for _index: int in range(0 if bool(selected.get("status_only", false)) else int(selected["dice"])):
		var die: int = rng.randi_range(1, 6)
		dice.append(die)
		total += die
	var status_only: bool = bool(selected.get("status_only", false))
	var row: Dictionary = type_chart.get(str(selected["type"]), {})
	var multiplier: float = 1.0 if status_only else float(row.get(str(defender["type"]), 1.0))
	# Beta calls effectiveness > 1 STAB; it does not add a same-type bonus.
	var supreme: bool = bool(options.get("supreme", effect == "SUPREMA")) and not status_only
	var damage: int = 0 if status_only else maxi(1, int(floor(float(total + int(selected["bonus"])) * multiplier + 0.5)))
	if supreme:
		damage *= 2
		var cost: int = maxi(1, int(float(attacker["max_hp"]) * 0.5))
		result["recoil"] = cost
	var previous_hp: int = int(defender["hp"])
	defender["hp"] = maxi(0, previous_hp - damage)
	if int(defender["hp"]) > 0 and STATUS_EFFECTS.has(effect):
		var applied: Dictionary = apply_status(defender, str(STATUS_EFFECTS[effect]))
		if bool(applied.applied):
			result["status_applied"] = str(STATUS_EFFECTS[effect])
			messages.append("%s è %s." % [defender["name"], STATUS_EFFECTS[effect]])
		else:
			messages.append("Ma non ha funzionato: è già presente uno stato alterato.")
	if supreme and not bool(options.get("defer_recoil", false)):
		attacker["hp"] = maxi(0, int(attacker["hp"]) - int(result["recoil"]))
	result["dice"] = dice
	result["damage"] = damage
	result["actual_damage"] = previous_hp - int(defender["hp"])
	result["multiplier"] = multiplier
	result["supreme"] = supreme
	if multiplier > 1.0:
		messages.append("È superefficace!")
	elif multiplier < 1.0:
		messages.append("Non è molto efficace.")
	if not status_only:
		messages.append("%s perde %d HP." % [defender["name"], damage])
	if supreme and not bool(options.get("defer_recoil", false)):
		messages.append("La Suprema costa %d HP a chi attacca." % int(result["recoil"]))
	if int(defender["hp"]) <= 0:
		messages.append("%s è fuori combattimento!" % defender["name"])
	result["text"] = " ".join(messages)
	return result


func heal(fighter: Dictionary) -> int:
	if not _valid_fighter(fighter):
		return 0
	var missing: int = int(fighter["max_hp"]) - int(fighter["hp"])
	fighter["hp"] = int(fighter["max_hp"])
	clear_status(fighter)
	return missing


func capture(target: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var result: Dictionary = {"success": false, "dice": [], "roll": 0, "threshold": 0.0, "text": "Non puoi catturare questo Arkamon."}
	if rng == null or not _valid_fighter(target) or int(target["hp"]) <= 0:
		return result
	var definition: Dictionary = species[int(target["species_id"])]
	var threshold: float = float(maxi(1, int(definition.get("tassoCattura", 1)))) * (3.0 - float(target["hp"]) / float(target["max_hp"]))
	var dice: Array = []
	var total: int = 0
	for _index: int in range(3):
		var die: int = rng.randi_range(1, 6)
		dice.append(die)
		total += die
	var success: bool = float(total) <= threshold
	result["success"] = success
	result["dice"] = dice
	result["roll"] = total
	result["threshold"] = threshold
	result["text"] = "%s è stato catturato!" % target["name"] if success else "%s si è liberato!" % target["name"]
	return result


func _move_for_level(definition: Dictionary, level: int) -> Dictionary:
	var dice_table: Dictionary = definition.get("dadiPerLivello", {})
	var bonus_table: Dictionary = definition.get("incrementoPerLivello", {})
	var dice_count: int = 0
	var bonus: int = 0
	for candidate_level: int in range(level, MIN_LEVEL - 1, -1):
		var key: String = str(candidate_level)
		if dice_table.has(key):
			dice_count = clampi(int(dice_table[key]), 0, 100)
			break
	for candidate_level: int in range(level, MIN_LEVEL - 1, -1):
		var key: String = str(candidate_level)
		if bonus_table.has(key):
			bonus = clampi(int(bonus_table[key]), 0, 1000)
			break
	var raw_effect: Variant = definition.get("effetto", "")
	var effect: String = "" if raw_effect == null else str(raw_effect)
	var raw_value: Variant = definition.get("valoreEffetto", 0)
	return {
		"id": int(definition.get("id", 0)), "name": str(definition.get("nome", "Mossa")),
		"type": str(definition.get("tipo", "Normale")), "dice": dice_count,
		"bonus": bonus, "effect": effect, "value": 0 if raw_value == null else int(raw_value),
		"status_only": bool(definition.get("soloStato", false)),
		"available": effect in SUPPORTED_EFFECTS,
		"effect_supported": effect in SUPPORTED_EFFECTS,
	}


func move_info(fighter: Dictionary, move_id: int) -> Dictionary:
	for entry: Dictionary in available_moves(fighter):
		if int(entry.id) == move_id:
			return entry
	return {}


func status_name(fighter: Dictionary) -> String:
	var value: Variant = fighter.get("status", {})
	return str(value.get("type", "")) if value is Dictionary else ""


func clear_status(fighter: Dictionary) -> void:
	fighter.erase("status")


func apply_status(fighter: Dictionary, kind: String) -> Dictionary:
	if not STATUS_DURATIONS.has(kind) or int(fighter.get("hp", 0)) <= 0 or not status_name(fighter).is_empty():
		return {"applied": false}
	var state: Dictionary = {"type": kind, "turns": int(STATUS_DURATIONS[kind])}
	if kind == "Avvelenato":
		state["elapsed"] = 0
	fighter["status"] = state
	return {"applied": true, "status": state.duplicate(true)}


func process_status(fighter: Dictionary, rng: RandomNumberGenerator, offensive: bool = true) -> Dictionary:
	var result: Dictionary = {"can_act": int(fighter.get("hp", 0)) > 0, "damage": 0, "dice": [], "text": "", "cleared": false}
	var kind: String = status_name(fighter)
	if kind.is_empty() or int(fighter.get("hp", 0)) <= 0:
		return result
	var state: Dictionary = fighter.status
	var messages: Array[String] = []
	var damage: int = 0
	match kind:
		"Paralizzato":
			state["turns"] = -1
			if offensive:
				var die: int = rng.randi_range(1, 6)
				result.dice = [die]
				result.can_act = die >= 3
				messages.append("Paralisi: dado %d, %s." % [die, "può agire" if die >= 3 else "perde l'attacco"])
		"Avvelenato":
			var elapsed: int = maxi(0, int(state.get("elapsed", 0))) + 1
			state["elapsed"] = elapsed
			state["turns"] = -1
			damage = maxi(1, int(float(fighter.max_hp) * float(elapsed) / 10.0))
			messages.append("Veleno: %d danni (%d%% degli HP massimi)." % [damage, elapsed * 10])
		"Addormentato":
			var remaining: int = int(state.get("turns", 3))
			if remaining >= 3:
				state["turns"] = 2
				result.can_act = false
				messages.append("Primo turno di sonno: riposa senza tiro di risveglio.")
			else:
				var die: int = rng.randi_range(1, 6)
				result.dice = [die]
				if die >= 4:
					clear_status(fighter)
					messages.append("Dado %d: si sveglia e può agire!" % die)
				else:
					result.can_act = false
					state["turns"] = remaining - 1
					messages.append("Dado %d: il sonno impedisce l'azione." % die)
					if remaining <= 1:
						clear_status(fighter)
						messages.append("Si sveglierà per il prossimo turno.")
		"Confuso":
			state["turns"] = int(state.get("turns", 2)) - 1
			if rng.randf() < 0.5:
				damage = rng.randi_range(1, 6)
				result.dice = [damage]
				result.can_act = false
				messages.append("La confusione causa %d danni a chi agisce." % damage)
			else:
				messages.append("È confuso, ma riesce ad agire.")
			if int(state.turns) <= 0:
				clear_status(fighter)
				messages.append("La confusione termina.")
	fighter["hp"] = maxi(0, int(fighter.hp) - damage)
	result.damage = damage
	result.can_act = bool(result.can_act) and int(fighter.hp) > 0
	result.cleared = status_name(fighter).is_empty()
	result.text = " ".join(messages)
	return result


func choose_ai(attacker: Dictionary, defender: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var best: Dictionary = {}
	var score_max: float = -INF
	var ratio: float = float(attacker.hp) / float(attacker.max_hp)
	for entry: Dictionary in available_moves(attacker):
		var row: Dictionary = type_chart.get(str(entry.type), {})
		var score: float = (float(entry.dice) * 3.5 + float(entry.bonus)) * float(row.get(str(defender.type), 1.0))
		if bool(entry.status_only):
			var useful: bool = status_name(attacker) == "Paralizzato" or int(defender.level) > int(attacker.level)
			score = -INF if not status_name(defender).is_empty() else (float(defender.hp) if useful and int(defender.hp) > 1 else -1.0)
		if str(entry.effect) in ["CURA", "CURA_PCT"]:
			score = INF if status_name(attacker) == "Paralizzato" else (100.0 if ratio <= 0.3 else -1.0)
		if str(entry.effect) == "SUPREMA":
			score = score * 2.0 if ratio > 0.55 else -1.0
		if best.is_empty() or score > score_max or (is_equal_approx(score, score_max) and rng.randf() < 0.5):
			best = entry
			score_max = score
	if best.is_empty():
		return {"type": "wait"}
	return {"type": "supreme" if str(best.effect) == "SUPREMA" else "attack", "move_id": int(best.id)}


func _install_paralysis_moves() -> void:
	for entry: Array in PARALYSIS_MOVES:
		var move_id: int = int(entry[0])
		moves[move_id] = {"id": move_id, "nome": entry[1], "tipo": entry[2], "effetto": "PARALISI", "soloStato": true, "dadiPerLivello": {"5": 0}, "incrementoPerLivello": {"5": 0}}
		for owner: Variant in entry[3]:
			if not species.has(int(owner)):
				continue
			var definition: Dictionary = species[int(owner)]
			var slots: Array = definition.get("mosse", [])
			var empty_slot: int = -1
			var already_assigned: bool = false
			for index: int in range(slots.size()):
				if int(slots[index]) == 0 and empty_slot < 0:
					empty_slot = index
				if int(slots[index]) == move_id:
					already_assigned = true
			if empty_slot >= 0 and not already_assigned:
				slots[empty_slot] = move_id


func _valid_fighter(fighter: Dictionary) -> bool:
	if not species.has(int(fighter.get("species_id", 0))):
		return false
	for key: String in ["name", "type", "hp", "max_hp", "level"]:
		if not fighter.has(key):
			return false
	return int(fighter["max_hp"]) > 0 and int(fighter["hp"]) >= 0 and int(fighter["hp"]) <= int(fighter["max_hp"]) and int(fighter["level"]) >= MIN_LEVEL and int(fighter["level"]) <= MAX_LEVEL


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parser: JSON = JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return null
	return parser.data

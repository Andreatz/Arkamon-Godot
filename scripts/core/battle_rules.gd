class_name BattleRules
extends RefCounted
## Small, deterministic port of the Beta's D6 battle rules.
## Source: Arkamon-Beta 7ec91d1f4e3e5252317044b1ee300b8b3e4d80a7.

const DATA_PATH: String = "res://data/"
const MIN_LEVEL: int = 5
const MAX_LEVEL: int = 100
const SUPPORTED_EFFECTS: Array[String] = ["", "CURA", "CURA_PCT", "SUPREMA"]

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


func attack(attacker: Dictionary, defender: Dictionary, move_id: int, rng: RandomNumberGenerator) -> Dictionary:
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
	if effect == "CURA" or effect == "CURA_PCT":
		var amount: int = maxi(1, int(selected["value"]))
		if effect == "CURA_PCT":
			amount = maxi(1, int(float(attacker["max_hp"]) * float(selected["value"]) / 100.0))
		var before: int = int(attacker["hp"])
		attacker["hp"] = mini(int(attacker["max_hp"]), before + amount)
		var restored: int = int(attacker["hp"]) - before
		result["heal"] = restored
		messages.append("Recupera %d HP." % restored if restored > 0 else "Ha già tutti gli HP.")
		result["text"] = " ".join(messages)
		return result
	var dice: Array = []
	var total: int = 0
	for _index: int in range(int(selected["dice"])):
		var die: int = rng.randi_range(1, 6)
		dice.append(die)
		total += die
	var row: Dictionary = type_chart.get(str(selected["type"]), {})
	var multiplier: float = float(row.get(str(defender["type"]), 1.0))
	# Beta calls effectiveness > 1 STAB; it does not add a same-type bonus.
	var damage: int = maxi(1, int(floor(float(total + int(selected["bonus"])) * multiplier + 0.5)))
	if effect == "SUPREMA":
		damage *= 2
		var cost: int = maxi(1, int(float(attacker["max_hp"]) * 0.5))
		result["recoil"] = cost
		attacker["hp"] = maxi(0, int(attacker["hp"]) - cost)
	var previous_hp: int = int(defender["hp"])
	defender["hp"] = maxi(0, previous_hp - damage)
	result["dice"] = dice
	result["damage"] = damage
	result["actual_damage"] = previous_hp - int(defender["hp"])
	result["multiplier"] = multiplier
	if multiplier > 1.0:
		messages.append("È superefficace!")
	elif multiplier < 1.0:
		messages.append("Non è molto efficace.")
	messages.append("%s perde %d HP." % [defender["name"], damage])
	if effect == "SUPREMA":
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
		"available": dice_count > 0 and effect in SUPPORTED_EFFECTS,
		"effect_supported": effect in SUPPORTED_EFFECTS,
	}


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

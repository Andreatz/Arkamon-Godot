class_name ChallengeModel
extends RefCounted
## Seed/Fanta rules ported from Beta 7ec91d1f: rules versions 1 and 2,
## FNV-1a UTF-16 hashing, arkamon-counter-v1 and configuration-only codes.

const LEVEL: int = 20
const TEAM_SIZE: int = 6
const BUDGET: int = 100
const RULES_VERSION: int = 2
const MAX_RESULTS: int = 30
const MAX_CODE_LENGTH: int = 8192
const MAX_CURSOR: int = 1000000000

class CounterRandom extends RefCounted:
	var seed_text: String = ""
	var cursor: int = 0
	func _init(text: String = "ARKAMON-2026", offset: int = 0) -> void:
		seed_text = text
		cursor = offset
	func randf() -> float:
		assert(cursor >= 0 and cursor < 1000000000, "Limite dei tiri della sfida raggiunto.")
		var value: int = (ChallengeModel.hash_text(seed_text) + ChallengeModel.multiply32(cursor + 1, 0x9e3779b9)) & 0xffffffff
		value = ChallengeModel.multiply32(value ^ (value >> 16), 0x21f0aaad)
		value = ChallengeModel.multiply32(value ^ (value >> 15), 0x735a2d97)
		value = (value ^ (value >> 15)) & 0xffffffff
		cursor += 1
		return float(value) / 4294967296.0
	func randi_range(from: int, to: int) -> int:
		return from + int(floor(randf() * float(to - from + 1)))
	func randf_range(from: float, to: float) -> float:
		return from + randf() * (to - from)
	func randi() -> int:
		return int(floor(randf() * 4294967296.0))
	func snapshot() -> Dictionary:
		return {"algorithm": "arkamon-counter-v1", "seed": seed_text, "cursor": cursor}
	func restore(value: Dictionary) -> bool:
		if str(value.get("algorithm", "")) != "arkamon-counter-v1" or not value.get("seed") is String or not ChallengeModel.whole(value.get("cursor"), 0, 1000000000):
			return false
		seed_text = str(value.seed)
		cursor = int(value.cursor)
		return true

var rules: BattleRules
var storage_path: String = "user://challenges.json"
var results: Array = []
var storage_warning: String = ""
var classic: Dictionary = {}
var nfc: Dictionary = {}
var _costs: Dictionary = {}
var _seed_team_cache: Dictionary = {}


func configure(battle_rules: BattleRules, path: String = "user://challenges.json") -> bool:
	rules = battle_rules
	storage_path = path
	if rules == null or rules.species.is_empty():
		return false
	var raw: Variant = _read("res://data/challenges/classic_catalog_v1.json")
	var unicode_data: Variant = _read("res://data/challenges/unicode_nfc.json")
	if not raw is Dictionary or not raw.get("species") is Array or not unicode_data is Dictionary:
		return false
	classic.clear()
	_costs.clear()
	_seed_team_cache.clear()
	for species: Dictionary in raw.species:
		classic[int(species.id)] = species
	nfc = unicode_data
	load_results()
	return classic.size() == 110


func species_cost(species_id: int, version: int = RULES_VERSION) -> int:
	if version not in [1, 2] or not rules.species.has(species_id):
		return -1
	if version == 1:
		return int(classic.get(species_id, {}).get("cost", -1))
	if _costs.has(species_id):
		return int(_costs[species_id])
	var species: Dictionary = rules.species[species_id]
	var category_cost: int = int({"Lenta": 2, "Media": 4, "Veloce": 7, "Leggendaria": 14}.get(str(species.get("categoria", "")), 4))
	var previous: Dictionary = {}
	for entry: Dictionary in rules.species.values():
		if int(entry.get("evoluzioneId", 0)) > 0:
			previous[int(entry.evoluzioneId)] = int(entry.id)
	var stage: int = 0
	var cursor: int = species_id
	var visited: Array = [cursor]
	while previous.has(cursor) and int(previous[cursor]) not in visited:
		cursor = int(previous[cursor])
		visited.append(cursor)
		stage += 1
	var expected_damage: float = 0.0
	for move: Dictionary in rules.creature(species_id, LEVEL).moves:
		if bool(move.get("status_only", false)) or str(move.get("effect", "")) in ["CURA", "CURA_PCT"]:
			continue
		expected_damage = maxf(expected_damage, float(move.dice) * 3.5 + float(move.bonus))
	var cost: int = 8 + category_cost + stage * 3 + int(ceil(expected_damage / 5.0))
	_costs[species_id] = cost
	return cost


func team_cost(ids: Array, version: int = RULES_VERSION) -> int:
	var total: int = 0
	for id: Variant in ids:
		if not whole(id, 1, 100000) or species_cost(int(id), version) < 0:
			return -1
		total += species_cost(int(id), version)
	return total


func validate_team(ids: Variant, complete: bool = true, version: int = RULES_VERSION) -> Dictionary:
	if version not in [1, 2]:
		return _fail("Versione delle regole non supportata.")
	if not ids is Array or ids.size() > TEAM_SIZE or (complete and ids.size() != TEAM_SIZE):
		return _fail("Scegli sei Arkamon per la squadra.")
	var seen: Array = []
	for id: Variant in ids:
		if not whole(id, 1, 100000) or not rules.species.has(int(id)) or (version == 1 and not classic.has(int(id))):
			return _fail("La squadra contiene una specie sconosciuta.")
		if int(id) in seen:
			return _fail("Ogni specie può essere scelta una sola volta.")
		seen.append(int(id))
	if team_cost(ids, version) > BUDGET:
		return _fail("La squadra supera il budget di cento crediti.")
	return {"ok": true, "cost": team_cost(ids, version), "message": "Squadra valida."}


func create(seed: String, team_ids: Array = [], mode: String = "challenge", version: int = RULES_VERSION) -> Dictionary:
	if rules == null or version not in [1, 2] or mode not in ["challenge", "fantateam", "seed", "fanta"]:
		return _fail("Versione o modalità della sfida non supportata.")
	var checked_seed: Dictionary = validate_seed(seed)
	if not checked_seed.ok:
		return checked_seed
	var text: String = checked_seed.seed
	var beta_mode: String = "seed" if mode in ["challenge", "seed"] else "fanta"
	var ids: Array = generate_seed_team(text, "player", version) if beta_mode == "seed" else team_ids.duplicate()
	var checked: Dictionary = validate_team(ids, true, version)
	if not checked.ok:
		return checked
	for index: int in range(ids.size()):
		ids[index] = int(ids[index])
	var enemy_ids: Array = generate_seed_team(text, "opponent", version)
	if enemy_ids.size() != TEAM_SIZE:
		return _fail("Il catalogo non consente di completare la squadra avversaria.")
	var identifier: String = "challenge-v%d-%08x" % [version, hash_text(JSON.stringify([beta_mode, text, ids]))]
	var team: Array = _make_team(ids, identifier + "-A")
	var enemy: Array = _make_team(enemy_ids, identifier + "-B")
	var code: String = JSON.stringify({"format": "arkamon-challenge", "version": version, "rulesVersion": version,
		"mode": beta_mode, "seed": text, "speciesIds": ids if beta_mode == "fanta" else []})
	return {"ok": true, "message": "Sfida pronta.", "id": identifier,
		"attempt_id": identifier + "-%d-%d" % [Time.get_unix_time_from_system() * 1000.0, Time.get_ticks_usec()],
		"version": version, "rulesVersion": version, "kind": "challenge" if beta_mode == "seed" else "fantateam",
		"mode": beta_mode, "seed": text, "rng_seed": hash_text(text),
		"rng": {"algorithm": "arkamon-counter-v1", "seed": text, "cursor": 0},
		"team": team, "enemy": enemy, "enemyTeam": enemy, "team_ids": ids,
		"enemy_ids": enemy_ids, "code": code, "cost": team_cost(ids, version), "level": LEVEL, "budget": BUDGET,
		"title": "Sfida a seed" if beta_mode == "seed" else "Fanta-Team"}


func decode(code: String) -> Dictionary:
	if code.length() > MAX_CODE_LENGTH:
		return _fail("Il codice della sfida è troppo grande.")
	var parser: JSON = JSON.new()
	if parser.parse(code) != OK:
		return _fail("Il codice della sfida non è un JSON valido.")
	var value: Variant = parser.data
	if not value is Dictionary or str(value.get("format", "")) != "arkamon-challenge" or not whole(value.get("version"), 1, 2) or value.get("rulesVersion") != value.get("version") or str(value.get("mode", "")) not in ["seed", "fanta"] or not value.get("seed") is String or not value.get("speciesIds") is Array:
		return _fail("Formato o versione della sfida non supportato.")
	var version: int = int(value.version)
	var check: Dictionary = validate_team(value.speciesIds, str(value.mode) == "fanta", version)
	if not check.ok:
		return check
	if str(value.mode) == "seed" and not value.speciesIds.is_empty():
		return _fail("Le squadre della sfida a seed sono generate dalle regole.")
	# Rebuild every HP/move/RNG field. Shared payloads never define runtime stats.
	return create(str(value.seed), value.speciesIds, str(value.mode), version)


func generate_seed_team(seed: String, stream_name: String, version: int = RULES_VERSION) -> Array:
	if version not in [1, 2] or stream_name not in ["player", "opponent"]:
		return []
	var check: Dictionary = validate_seed(seed)
	if not check.ok:
		return []
	var cache_key: String = JSON.stringify([version, check.seed, stream_name])
	if _seed_team_cache.has(cache_key):
		return _seed_team_cache[cache_key].duplicate()
	var random: CounterRandom = CounterRandom.new(stream_name + ":%x" % hash_text(str(check.seed)))
	var candidates: Array = []
	var ids: Array = classic.keys() if version == 1 else rules.species.keys()
	# Catalogue insertion order is the original ascending species ID order.
	ids.sort()
	for id: int in ids:
		candidates.append({"id": id, "type": str(classic[id].type) if version == 1 else str(rules.species[id].tipo), "cost": species_cost(id, version), "tie": random.randf()})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.tie) < float(b.tie) if a.tie != b.tie else int(a.id) < int(b.id))
	var selected: Array = []
	var types: Array = []
	var spent: int = 0
	for slot: int in range(TEAM_SIZE):
		# The minimum completion reserve depends only on the remaining costs.
		# Sort it once per slot instead of for every candidate; the original
		# tie order and type diversity selection are retained exactly.
		var available_costs: Array = []
		for other: Dictionary in candidates:
			if int(other.id) not in selected:
				available_costs.append({"id": int(other.id), "cost": int(other.cost)})
		available_costs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.cost) < int(b.cost))
		var affordable: Array = []
		for candidate: Dictionary in candidates:
			if int(candidate.id) in selected:
				continue
			var reserve: int = 0
			var reserve_count: int = 0
			for other: Dictionary in available_costs:
				if reserve_count >= TEAM_SIZE - slot - 1:
					break
				if int(other.id) != int(candidate.id):
					reserve += int(other.cost)
					reserve_count += 1
			if spent + int(candidate.cost) + reserve <= BUDGET:
				affordable.append(candidate)
		if affordable.is_empty():
			return []
		var pick: Dictionary = affordable[0]
		for candidate: Dictionary in affordable:
			if str(candidate.type) not in types:
				pick = candidate
				break
		selected.append(int(pick.id))
		spent += int(pick.cost)
		types.append(str(pick.type))
	if _seed_team_cache.size() > 256:
		_seed_team_cache.clear()
	_seed_team_cache[cache_key] = selected.duplicate()
	return selected


func make_rng(seed: String, cursor: int = 0) -> CounterRandom:
	var checked: Dictionary = validate_seed(seed)
	return CounterRandom.new(str(checked.get("seed", "ARKAMON-2026")), clampi(cursor, 0, MAX_CURSOR))


func validate_seed(value: String) -> Dictionary:
	var text: String = normalize_nfc(_trim_seed(value))
	var units: int = 0
	for index: int in range(text.length()):
		var codepoint: int = text.unicode_at(index)
		units += 2 if codepoint > 65535 else 1
		if codepoint < 32 or codepoint == 127:
			return _fail("Il seed deve contenere da 1 a 64 caratteri, senza caratteri di controllo.")
	if units < 1 or units > 64:
		return _fail("Il seed deve contenere da 1 a 64 caratteri, senza caratteri di controllo.")
	return {"ok": true, "seed": text, "message": "Seed valido."}


func canonical(descriptor: Dictionary) -> Dictionary:
	if not descriptor.get("code") is String:
		return _fail("Configurazione della sfida non valida.")
	var rebuilt: Dictionary = decode(str(descriptor.code))
	if not rebuilt.ok or str(descriptor.get("id", "")) != str(rebuilt.id):
		return _fail("La configurazione non coincide con il codice condiviso.")
	if descriptor.has("attempt_id") and descriptor.attempt_id is String and not str(descriptor.attempt_id).is_empty() and str(descriptor.attempt_id).length() <= 160:
		rebuilt.attempt_id = str(descriptor.attempt_id)
	return rebuilt


func record_result(descriptor: Dictionary, won: bool, turns: int, remaining_hp: int = 0) -> Dictionary:
	var restored: Dictionary = canonical(descriptor)
	if not restored.ok or not whole(turns, 0, 100000) or not whole(remaining_hp, 0, 1000000):
		return _fail("Risultato della sfida non valido.")
	var entry: Dictionary = {"id": str(restored.attempt_id), "sessionId": str(restored.id), "rulesVersion": int(restored.version),
		"mode": str(restored.mode), "seed": str(restored.seed), "outcome": "vittoria" if won else "sconfitta",
		"turns": turns, "remainingHp": remaining_hp, "completedAt": Time.get_datetime_string_from_system(true) + "Z", "team": restored.team_ids.duplicate()}
	var candidate: Array = results.duplicate(true)
	var present: bool = false
	for result: Dictionary in candidate:
		if str(result.id) == str(entry.id):
			present = true
	if not present:
		candidate.push_front(entry)
	while candidate.size() > MAX_RESULTS:
		candidate.pop_back()
	var written: Dictionary = _write_results(candidate)
	if not written.ok:
		return written
	results = candidate
	return {"ok": true, "message": "Risultato registrato nella classifica locale.", "entry": entry}


func leaderboard(descriptor: Variant) -> Array:
	var identifier: String = str(descriptor.get("id", "")) if descriptor is Dictionary else str(descriptor)
	var version: int = 2 if identifier.begins_with("challenge-v2-") else 1
	var selected: Array = []
	for entry: Dictionary in results:
		if str(entry.sessionId) == identifier and int(entry.rulesVersion) == version:
			if descriptor is Dictionary and (str(entry.seed) != str(descriptor.get("seed", "")) or str(entry.mode) != str(descriptor.get("mode", "")) or entry.team != descriptor.get("team_ids", [])):
				continue
			selected.append(entry.duplicate(true))
	selected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.outcome != b.outcome:
			return str(a.outcome) == "vittoria"
		if a.turns != b.turns:
			return int(a.turns) < int(b.turns)
		if a.remainingHp != b.remainingHp:
			return int(a.remainingHp) > int(b.remainingHp)
		return str(a.completedAt) < str(b.completedAt))
	return selected


func load_results() -> bool:
	results = []
	storage_warning = ""
	if not FileAccess.file_exists(storage_path):
		return true
	var value: Variant = _read(storage_path)
	if not value is Dictionary or int(value.get("version", 0)) != 1 or not value.get("results") is Array:
		storage_warning = "Il registro delle sfide non è leggibile; il file originale è conservato."
		return false
	var seen: Array = []
	for candidate: Variant in value.results:
		if results.size() >= MAX_RESULTS:
			break
		if not candidate is Dictionary:
			continue
		var entry: Dictionary = _normalize_result(candidate)
		if not entry.is_empty() and str(entry.id) not in seen:
			seen.append(str(entry.id))
			results.append(entry)
	return true


func _normalize_result(value: Dictionary) -> Dictionary:
	if not value.get("id") is String or str(value.id).is_empty() or str(value.id).length() > 160 or not value.get("sessionId") is String or not value.get("seed") is String or str(value.get("outcome", "")) not in ["vittoria", "sconfitta"] or not whole(value.get("turns"), 0, 100000) or not whole(value.get("remainingHp"), 0, 1000000) or not value.get("team") is Array or not value.get("completedAt") is String:
		return {}
	var version: int = int(value.get("rulesVersion", 1))
	var check: Dictionary = validate_team(value.team, true, version)
	var seed: Dictionary = validate_seed(str(value.seed))
	if not check.ok or not seed.ok or str(value.get("mode", "")) not in ["seed", "fanta"]:
		return {}
	var descriptor: Dictionary = create(str(seed.seed), value.team, str(value.mode), version)
	var ids: Array = []
	for id: Variant in value.team:
		ids.append(int(id))
	if not descriptor.ok or str(descriptor.id) != str(value.sessionId) or descriptor.team_ids != ids:
		return {}
	var result: Dictionary = value.duplicate(true)
	result.rulesVersion = version
	result.seed = str(seed.seed)
	result.turns = int(value.turns)
	result.remainingHp = int(value.remainingHp)
	result.team = ids
	return result


func _write_results(candidate: Array) -> Dictionary:
	# Atomic replacement on the same filesystem; campaign data is never opened.
	var temporary: String = storage_path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		storage_warning = "Non posso salvare il risultato. Libera spazio e riprova."
		return _fail(storage_warning)
	file.store_string(JSON.stringify({"version": 1, "results": candidate}))
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK:
		return _fail("Scrittura della classifica non riuscita.")
	error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(storage_path))
	if error != OK:
		return _fail("Non posso sostituire il registro delle sfide: riprova.")
	storage_warning = ""
	return {"ok": true, "message": "Classifica salvata."}


func _make_team(ids: Array, prefix: String) -> Array:
	var team: Array = []
	for index: int in range(ids.size()):
		var creature: Dictionary = rules.creature(int(ids[index]), LEVEL)
		creature.instance_id = "%s-%d-%d" % [prefix, index, int(ids[index])]
		creature.xp = 0
		team.append(creature)
	return team


static func multiply32(a: int, b: int) -> int:
	var low: int = (a & 0xffff) * (b & 0xffff)
	var high: int = ((a >> 16) * (b & 0xffff) + (a & 0xffff) * (b >> 16)) & 0xffff
	return (low + (high << 16)) & 0xffffffff


static func hash_text(text: String) -> int:
	var hash_value: int = 2166136261
	for index: int in range(text.length()):
		var cp: int = text.unicode_at(index)
		if cp > 0xffff:
			cp -= 0x10000
			hash_value = multiply32(hash_value ^ (0xd800 + (cp >> 10)), 16777619)
			hash_value = multiply32(hash_value ^ (0xdc00 + (cp & 0x3ff)), 16777619)
		else:
			hash_value = multiply32(hash_value ^ cp, 16777619)
	return hash_value & 0xffffffff


func normalize_nfc(text: String) -> String:
	# Canonical normalization preserves Beta's JS String.normalize('NFC').
	# Tables are generated from the Unicode Character Database, not transliteration.
	var decomposed: Array = []
	for index: int in range(text.length()):
		_decompose(text.unicode_at(index), decomposed)
	for index: int in range(1, decomposed.size()):
		var position: int = index
		var cc: int = _combining(int(decomposed[position]))
		while cc > 0 and position > 0 and _combining(int(decomposed[position - 1])) > cc:
			var prior: int = int(decomposed[position - 1])
			decomposed[position - 1] = decomposed[position]
			decomposed[position] = prior
			position -= 1
	var composed: Array = []
	var starter_position: int = -1
	var starter: int = 0
	var last_cc: int = 0
	for raw: int in decomposed:
		var cc: int = _combining(raw)
		var compound: int = _compose(starter, raw) if starter_position >= 0 else -1
		if compound >= 0 and (last_cc == 0 or last_cc < cc):
			composed[starter_position] = compound
			starter = compound
		else:
			if cc == 0:
				starter_position = composed.size()
				starter = raw
			composed.append(raw)
			last_cc = cc
	var result: String = ""
	for cp: int in composed:
		result += String.chr(cp)
	return result


func _trim_seed(value: String) -> String:
	# ECMAScript trim includes Unicode separator spaces and the BOM.
	var whitespace: Array = [9, 10, 11, 12, 13, 32, 160, 5760, 8192, 8193, 8194, 8195, 8196, 8197, 8198, 8199, 8200, 8201, 8202, 8232, 8233, 8239, 8287, 12288, 65279]
	var first: int = 0
	var last: int = value.length()
	while first < last and value.unicode_at(first) in whitespace:
		first += 1
	while last > first and value.unicode_at(last - 1) in whitespace:
		last -= 1
	return value.substr(first, last - first)


func _decompose(cp: int, output: Array) -> void:
	if cp >= 0xac00 and cp < 0xd7a4:
		var offset: int = cp - 0xac00
		output.append(0x1100 + int(offset / 588))
		output.append(0x1161 + int((offset % 588) / 28))
		if offset % 28 > 0:
			output.append(0x11a7 + offset % 28)
	elif nfc.get("decomposition", {}).has(str(cp)):
		for component: Variant in nfc.decomposition[str(cp)]:
			_decompose(int(component), output)
	else:
		output.append(cp)


func _combining(cp: int) -> int:
	return int(nfc.get("combining", {}).get(str(cp), 0))


func _compose(first: int, second: int) -> int:
	if first >= 0x1100 and first < 0x1113 and second >= 0x1161 and second < 0x1176:
		return 0xac00 + ((first - 0x1100) * 21 + second - 0x1161) * 28
	if first >= 0xac00 and first < 0xd7a4 and (first - 0xac00) % 28 == 0 and second > 0x11a7 and second < 0x11c3:
		return first + second - 0x11a7
	return int(nfc.get("composition", {}).get("%d:%d" % [first, second], -1))


static func whole(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and floor(float(value)) == float(value) and float(value) >= minimum and float(value) <= maximum


func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var parser: JSON = JSON.new()
	return parser.data if parser.parse(FileAccess.get_file_as_string(path)) == OK else null


func _fail(message: String) -> Dictionary:
	return {"ok": false, "message": message}

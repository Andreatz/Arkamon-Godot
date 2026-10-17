extends SceneTree

const Rules = preload("res://scripts/core/battle_rules.gd")
const Saves = preload("res://scripts/core/save_store.gd")
const TEST_PATH: String = "user://tests/core_roundtrip.json"

var failures: int = 0
var checks: int = 0


func _init() -> void:
	var rules: Rules = Rules.new()
	_expect(rules.load_data(), "Il catalogo originale si carica")
	_expect(rules.species.size() == 110, "Sono disponibili le 110 specie originali")
	_expect(rules.moves.size() >= 220, "Il catalogo delle mosse è completo")
	if rules.species.is_empty():
		finish()
		return
	_test_battle(rules)
	_test_capture(rules)
	_test_saves(rules)
	finish()


func _test_battle(rules: Rules) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261017
	var hero: Dictionary = rules.creature(1)
	var enemy: Dictionary = rules.creature(5)
	_expect(hero["max_hp"] == 12, "HP base originali al livello cinque")
	var grown: Dictionary = rules.creature(1, 10)
	_expect(grown["max_hp"] == 19, "Crescita HP Media troncata come in Beta")
	_expect(rules.creature(99999).is_empty(), "Una specie sconosciuta è rifiutata")
	var available: Array = rules.available_moves(hero)
	_expect(not available.is_empty(), "Lo starter ha una mossa utilizzabile")
	var result: Dictionary = rules.attack(hero, enemy, 1, rng)
	var dice: Array = result["dice"]
	_expect(bool(result["ok"]) and dice.size() == 1, "Soffio al livello cinque tira un D6")
	if dice.size() == 1:
		_expect(int(dice[0]) >= 1 and int(dice[0]) <= 6, "Il D6 resta nell'intervallo uno-sei")
		_expect(int(result["damage"]) == int(dice[0]) + 1, "Il danno neutro è D6 più incremento, senza bonus aggiunti")
	_expect(int(enemy["hp"]) == 12 - int(result["damage"]), "L'attacco aggiorna gli HP del bersaglio")
	var recovered: int = rules.heal(enemy)
	_expect(recovered == int(result["damage"]) and enemy["hp"] == enemy["max_hp"], "La cura ripristina gli HP esatti")
	_expect(rules.heal(enemy) == 0, "La cura a HP pieni è innocua")
	var previous_hp: int = int(enemy["hp"])
	var invalid: Dictionary = rules.attack(hero, enemy, 99999, rng)
	_expect(not bool(invalid["ok"]) and int(enemy["hp"]) == previous_hp, "Una mossa non posseduta non infligge danni")
	enemy["hp"] = 1
	rules.attack(hero, enemy, 1, rng)
	_expect(enemy["hp"] == 0, "Il KO limita gli HP a zero")
	var invalid_ko: Dictionary = rules.attack(enemy, hero, 28, rng)
	_expect(not bool(invalid_ko["ok"]), "Un Arkamon KO non può attaccare")
	var fire: Dictionary = rules.creature(32, 5)
	var grass: Dictionary = rules.creature(28, 5)
	var fire_moves: Array = rules.available_moves(fire)
	_expect(not fire_moves.is_empty(), "Blazion ha un attacco disponibile")
	if not fire_moves.is_empty():
		var fire_move: Dictionary = fire_moves[0]
		var effective: Dictionary = rules.attack(fire, grass, int(fire_move["id"]), rng)
		var total: int = int(fire_move["bonus"])
		for value: Variant in effective["dice"]:
			total += int(value)
		_expect(float(effective["multiplier"]) == 1.5, "Fuoco contro Erba usa la tabella originale")
		_expect(int(effective["damage"]) == int(floor(float(total) * 1.5 + 0.5)), "Il moltiplicatore arrotonda metà verso l'alto")


func _test_capture(rules: Rules) -> void:
	var full: Dictionary = rules.creature(1)
	var weakened: Dictionary = full.duplicate(true)
	weakened["hp"] = 1
	var first_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var second_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	first_rng.seed = 42
	second_rng.seed = 42
	var full_result: Dictionary = rules.capture(full, first_rng)
	var weak_result: Dictionary = rules.capture(weakened, second_rng)
	_expect(full_result["dice"] == weak_result["dice"], "Un seed rende riproducibile la cattura")
	_expect(full_result["dice"].size() == 3, "La cattura usa tre D6")
	_expect(int(full_result["roll"]) >= 3 and int(full_result["roll"]) <= 18, "La somma di cattura resta fra tre e diciotto")
	_expect(is_equal_approx(float(full_result["threshold"]), 10.0), "Soglia originale a HP pieni: tasso per due")
	_expect(float(weak_result["threshold"]) > float(full_result["threshold"]), "Indebolire il bersaglio facilita la cattura")
	_expect(bool(weak_result["success"]) == (float(weak_result["roll"]) <= float(weak_result["threshold"])), "La riuscita segue la soglia dei dadi")
	weakened["hp"] = 0
	var ko_result: Dictionary = rules.capture(weakened, second_rng)
	_expect(not bool(ko_result["success"]) and ko_result["dice"].is_empty(), "Un bersaglio KO non consuma tiri di cattura")


func _test_saves(rules: Rules) -> void:
	_cleanup()
	var state: Dictionary = {"team": [rules.creature(1, 10)], "box": [], "money": 50, "location": "Milano", "started": true}
	_expect(Saves.save_game(state, TEST_PATH) == OK, "Il salvataggio scrive un file valido")
	var restored: Dictionary = Saves.load_game(TEST_PATH)
	_expect(str(restored.get("location", "")) == "Milano", "Il roundtrip conserva il luogo")
	var restored_team: Array = restored.get("team", [])
	_expect(restored_team.size() == 1 and int(restored_team[0]["hp"]) == 19, "Il roundtrip conserva specie e HP")
	_expect(Saves.has_save(TEST_PATH), "Il salvataggio viene rilevato")
	state["money"] = 75
	_expect(Saves.save_game(state, TEST_PATH) == OK, "Una seconda scrittura mantiene una copia precedente")
	_write_text(TEST_PATH, "{salvataggio interrotto")
	var recovered: Dictionary = Saves.load_game(TEST_PATH)
	_expect(int(recovered.get("money", -1)) == 50, "Un JSON corrotto recupera la copia precedente")
	_expect(Saves.save_game(state, TEST_PATH) == OK, "Si può salvare dopo il recupero senza perdere la copia valida")
	var invalid: Dictionary = state.duplicate(true)
	invalid["team"][0]["hp"] = -1
	_expect(Saves.save_game(invalid, TEST_PATH) == ERR_INVALID_DATA, "HP negativi vengono rifiutati prima della scrittura")
	_expect(int(Saves.load_game(TEST_PATH).get("money", -1)) == 75, "Una richiesta invalida conserva il salvataggio valido")
	invalid = state.duplicate(true)
	invalid["team"][0]["level"] = 999
	_expect(Saves.save_game(invalid, TEST_PATH) == ERR_INVALID_DATA, "Livelli fuori intervallo vengono rifiutati")
	invalid = state.duplicate(true)
	invalid["money"] = -10
	_expect(Saves.save_game(invalid, TEST_PATH) == ERR_INVALID_DATA, "Le risorse non possono essere negative")
	_write_text(TEST_PATH, JSON.stringify({"version": 99, "state": state}))
	_write_text(TEST_PATH + ".bak", "[]")
	_expect(Saves.load_game(TEST_PATH).is_empty(), "Versioni future e backup invalidi vengono rifiutati")
	_cleanup()
	_expect(not Saves.has_save(TEST_PATH), "I test rimuovono soltanto i propri file isolati")


func _write_text(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()


func _cleanup() -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		var path: String = TEST_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)


func finish() -> void:
	print("Core Arkamon: %d verifiche, %d errori." % [checks, failures])
	quit(0 if failures == 0 else 1)

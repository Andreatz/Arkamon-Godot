extends SceneTree

const Model = preload("res://scripts/core/challenge_model.gd")
const Menu = preload("res://scripts/challenge_menu.gd")
const TEST_PATH: String = "user://test_challenges_results.json"
var checks: int = 0
var failures: int = 0
var rules: BattleRules
var model: ChallengeModel
var launches: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_remove_test_files()
	rules = BattleRules.new()
	_check(rules.load_data(), "catalogo battaglia")
	model = Model.new()
	_check(model.configure(rules, TEST_PATH), "modello sfide configurato")
	print("Sfide: compatibilità con le fixture Beta.")
	_test_reference_compatibility()
	print("Sfide: validazione codici.")
	_test_inputs_codes()
	print("Sfide: registro locale.")
	_test_results()
	print("Sfide: menu e segnali.")
	await _test_menu()
	_remove_test_files()
	print("Sfide Arkamon: %d verifiche, %d errori." % [checks, failures])
	quit(1 if failures > 0 else 0)


func _test_reference_compatibility() -> void:
	var classic: Dictionary = _read("res://data/challenges/classic_sessions_v1.json")
	for fixture: Dictionary in classic.sessions:
		var descriptor: Dictionary = model.create(str(fixture.seed), [], "challenge", 1)
		_check(descriptor.ok, "fixturev1 " + str(fixture.seed))
		_check(descriptor.team_ids == _ints(fixture.team), "squadra classica esatta " + str(fixture.seed))
		_check(descriptor.enemy_ids == _ints(fixture.enemy), "nemici classici esatti " + str(fixture.seed))
		_check(str(descriptor.id) == str(fixture.id), "hash configurazionev1 " + str(fixture.seed))
	var reference: Dictionary = _read("res://data/challenges/reference_v2.json")
	for fixture: Dictionary in reference.costs:
		_check(model.species_cost(int(fixture.id)) == int(fixture.cost), "costo offensivo originale specie%d" % int(fixture.id))
	for fixture: Dictionary in reference.sessions:
		var descriptor: Dictionary = model.create(str(fixture.seed))
		_check(descriptor.ok and descriptor.team_ids == _ints(fixture.team), "generazionev2 esatta " + str(fixture.seed))
		_check(descriptor.enemy_ids == _ints(fixture.enemy), "generazioneavversariv2 " + str(fixture.seed))
		_check(descriptor.id == fixture.id, "hash UTF16 configurazionev2 " + str(fixture.seed))
		_check(model.validate_team(descriptor.team_ids).ok and model.validate_team(descriptor.enemy_ids).ok, "entrambe squadre entro budget")
		for creature: Dictionary in descriptor.team:
			_check(int(creature.level) == 20 and int(creature.hp) == int(creature.max_hp), "tutti al livello20 conHPcanonici")
	for fixture: Dictionary in reference.randoms:
		_check(Model.hash_text(str(fixture.seed)) == int(fixture.hash), "FNV1aJavaScript " + str(fixture.seed))
		var random: ChallengeModel.CounterRandom = model.make_rng(str(fixture.seed))
		for expected: Variant in fixture.samples:
			_check(is_equal_approx(random.randf(), float(expected)), "counter PRNG originale esatto")
		var checkpoint: Dictionary = random.snapshot()
		var expected: float = random.randf()
		var restored: ChallengeModel.CounterRandom = model.make_rng(str(fixture.seed))
		_check(restored.restore(checkpoint) and restored.randf() == expected, "cursor PRNG ripristinabile")
	_check(model.create("Caffe\u0300").id == model.create("Caffè").id, "normalizzazioneNFCseed accenti")
	_check(model.normalize_nfc("\u1100\u1161\u11a8") == "각", "composizioneHangulNFC")
	var first: Dictionary = model.create("Same-seed")
	var second: Dictionary = model.create("Same-seed")
	_check(first.team == second.team and first.enemy == second.enemy and first.id == second.id, "ripetibilità squadre statistiche identità")
	_check(first.attempt_id != second.attempt_id, "tentativi distinti della stessa configurazione")
	_check(model.create("Other-seed").team_ids != first.team_ids, "seed diverso cambia squadra")


func _test_inputs_codes() -> void:
	_check(not model.create("").ok and not model.create("\n \t").ok, "seedvuoto rifiutato")
	_check(not model.create("A\u0001B").ok, "controlliASCIIrifiutati")
	_check(not model.create("A".repeat(65)).ok and model.create("A".repeat(64)).ok, "seedlimiteUTF1664")
	_check(not model.create("🚀".repeat(33)).ok and model.create("🚀".repeat(32)).ok, "surrogateUTF16contanodue")
	_check(model.create("\ufeff\u00a0Italia\u3000").id == model.create("Italia").id, "trimUnicodecompatibileJavaScript")
	_check(not model.validate_team([1, 1, 5, 9, 13, 16]).ok, "vietate specie ripetute")
	_check(not model.validate_team([1, 5, 9, 13, 16, 999]).ok, "specie inesistente")
	_check(not model.validate_team([1, 5, 9, 13, 16]).ok, "servonoesattamente6")
	_check(not model.validate_team([1.2, 5, 9, 13, 16, 20]).ok, "specieintere")
	var expensive: Array = rules.species.keys()
	expensive.sort_custom(func(a: int, b: int) -> bool: return model.species_cost(a) > model.species_cost(b))
	_check(not model.validate_team(expensive.slice(0, 6)).ok, "budget100nonaggirabile")
	var seed: Dictionary = model.create("Codice-JS")
	var fanta: Dictionary = model.create("Codice-JS", seed.team_ids, "fantateam")
	_check(fanta.ok and fanta.team_ids == seed.team_ids, "FantaTeam usa selezione manuale")
	_check(fanta.enemy_ids == seed.enemy_ids and fanta.id != seed.id, "nemici stessoseed e classifica separata permodalità")
	var imported: Dictionary = model.decode(str(fanta.code))
	_check(imported.ok and imported.id == fanta.id and imported.team == fanta.team and imported.enemy == fanta.enemy, "code roundtripFanta")
	_check(model.decode(str(seed.code)).id == seed.id, "code roundtripseeds")
	var attack: Dictionary = JSON.parse_string(str(fanta.code))
	attack.team = [{"hp": 999999, "level": 100}]
	attack.enemy = []
	attack.rng = {"cursor": 999}
	imported = model.decode(JSON.stringify(attack))
	_check(imported.ok and imported.team == fanta.team and imported.rng.cursor == 0, "payloadnonpuòiniettareHPmosseRNG")
	attack.speciesIds[1] = attack.speciesIds[0]
	_check(not model.decode(JSON.stringify(attack)).ok, "codicemanomessoduplicati rifiutato")
	attack = JSON.parse_string(str(seed.code))
	attack.speciesIds = seed.team_ids
	_check(not model.decode(JSON.stringify(attack)).ok, "codiceseednonpuòsovrascriveresquadra")
	attack = JSON.parse_string(str(seed.code))
	attack.rulesVersion = 1
	_check(not model.decode(JSON.stringify(attack)).ok, "versionidiscordantirifiutate")
	_check(not model.decode("{").ok and not model.decode("{}").ok and not model.decode("A".repeat(8193)).ok, "JSONnonvalidoeoversize")
	var classic: Dictionary = model.create("Roma", [], "challenge", 1)
	_check(model.decode(str(classic.code)).id == classic.id, "codiciv1classiciriconosciuti")


func _test_results() -> void:
	var descriptor: Dictionary = model.create("CLASSIFICA")
	var campaign: CampaignModel = CampaignModel.new()
	_check(campaign.configure(rules), "campagna disponibile isolamentotest")
	campaign.new_game([1, 5])
	var campaign_before: Dictionary = campaign.snapshot()
	_check(model.record_result(descriptor, false, 3, 0).ok, "sconfittaregistrata")
	_check(model.record_result(descriptor, true, 1, 900).ok and model.results.size() == 1, "retryidempotentenontrasformasconfittainvittoria")
	_check(model.results[0].outcome == "sconfitta", "ilrisultatooriginaleresta")
	var next: Dictionary = model.decode(str(descriptor.code))
	_check(model.record_result(next, true, 8, 21).ok, "vittoriaregistrata")
	next = model.decode(str(descriptor.code))
	_check(model.record_result(next, true, 8, 40).ok, "secondavittoriaregistrata")
	next = model.decode(str(descriptor.code))
	_check(model.record_result(next, true, 6, 1).ok, "vittoria6turni")
	var board: Array = model.leaderboard(descriptor)
	_check(board.size() == 4 and board[0].turns == 6 and board[1].remainingHp == 40 and board[3].outcome == "sconfitta", "ordinamentovittoria-turni-HP")
	_check(model.leaderboard(model.create("ALTROSEED")).is_empty(), "seeddiverso/classificaseparata")
	_check(model.leaderboard(model.create("CLASSIFICA", descriptor.team_ids, "fantateam")).is_empty(), "Fanta/classificaseparata")
	_check(model.leaderboard(model.create("CLASSIFICA", [], "challenge", 1)).is_empty(), "v1v2classificheseparate")
	var tampered: Dictionary = descriptor.duplicate(true)
	tampered.id = "fake"
	var before: Array = model.results.duplicate(true)
	_check(not model.record_result(tampered, true, 1).ok and model.results == before, "risultatoconfigurazionealteratarifiutato")
	_check(not model.record_result(descriptor, true, -1).ok and model.results == before, "turninegativirifiutati")
	var saved: ChallengeModel = Model.new()
	_check(saved.configure(rules, TEST_PATH) and saved.results == model.results, "classificapersistedfileindipendente")
	_check(campaign.state == campaign_before, "sfidenonmodificanocampagna")
	for index: int in range(32):
		var entry: Dictionary = model.create("ROTATION-%d" % index)
		_check(model.record_result(entry, true, index, 1).ok, "rotazioneclassificapersistente")
	_check(model.results.size() == 30 and model.results[0].seed == "ROTATION-31", "massimoultimi30risultati")
	var payload: Dictionary = _read(TEST_PATH)
	payload.results.push_front({"id": "bad", "sessionId": "fake", "turns": -5})
	var file: FileAccess = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload))
	file.close()
	_check(model.load_results() and model.results.size() == 30, "classificacorrotto-recordrifiutato")
	var failed: ChallengeModel = Model.new()
	_check(failed.configure(rules, "user://directory_inesistente_challenge/results.json"), "modelperfallimentosalvataggio")
	_check(not failed.record_result(descriptor, true, 3).ok and failed.results.is_empty(), "salvataggiofallitononpubblicarisultato")


func _test_menu() -> void:
	var menu: ChallengeMenu = Menu.new()
	menu.setup(rules)
	menu.model.storage_path = TEST_PATH
	root.add_child(menu)
	await process_frame
	await process_frame
	_check(menu.slots.size() == 6 and menu.slots[0].item_count == 110, "UIsei selettoritutticatalogo")
	_check(not menu.descriptor.is_empty() and not menu.start_button.disabled, "UIsfidaseedgiàpronta")
	menu.battle_requested.connect(func(value: Dictionary) -> void:
		launches += 1
		_check(value.team.size() == 6 and value.enemy.size() == 6 and value.has("rng_seed"), "segnalebattagliacompleta"))
	menu._launch()
	_check(launches == 1, "pulsanteavviobattaglia")
	menu.mode_picker.select(1)
	menu._selection_changed()
	menu._prepare()
	_check(menu.descriptor.mode == "fanta", "UIFantaTeamfunziona")
	var code: String = str(menu.descriptor.code)
	menu.code_input.text = code
	menu._import_code()
	_check(menu.descriptor.code == code, "UIimportcodice")
	var different: Dictionary = model.create("Seeddiverso-import", model.generate_seed_team("Seeddiverso-import", "player", 1), "fantateam", 1)
	menu.code_input.text = str(different.code)
	menu._import_code()
	_check(menu.descriptor.id == different.id and menu.descriptor.seed == "Seeddiverso-import", "UIimportseeddiversopreservadescriptor")
	_check(menu.descriptor.mode == "fanta" and int(menu.descriptor.version) == 1 and menu._ids() == different.team_ids, "UIimportversionemodalitàesquadra")
	_check(menu.slots[0].get_item_text(menu.slots[0].selected).contains("%d crediti" % model.species_cost(int(different.team_ids[0]), 1)), "UIprezziallineatiaregolev1importate")
	menu.queue_free()
	await process_frame


func _read(path: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}


func _ints(value: Array) -> Array:
	var result: Array = []
	for id: Variant in value:
		result.append(int(id))
	return result


func _remove_test_files() -> void:
	for suffix: String in ["", ".tmp"]:
		var path: String = TEST_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("SFIDE: " + message)

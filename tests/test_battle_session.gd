extends SceneTree

const Rules = preload("res://scripts/core/battle_rules.gd")
const Session = preload("res://scripts/core/battle_session.gd")
var rules: Rules = Rules.new()
var failures: int = 0
var checks: int = 0


func _init() -> void:
	check(rules.load_data(), "I dati si caricano")
	_test_setup_and_pvp()
	_test_six_vs_six()
	_test_forced_switch_and_status()
	_test_supreme()
	_test_capture_and_items()
	_test_snapshot_restore()
	print("Sessione Arkamon: %d verifiche, %d errori." % [checks, failures])
	quit(0 if failures == 0 else 1)


func _session(player: Array, enemy: Array, kind: String = "npc") -> Session:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 42
	var session: Session = Session.new()
	check(session.setup(player, enemy, kind, random), "La sessione %s si inizializza" % kind)
	return session


func _test_setup_and_pvp() -> void:
	var hero: Dictionary = rules.creature(1, 10)
	var enemy: Dictionary = rules.creature(5, 5)
	var session: Session = _session([hero], [enemy], "pvp")
	check(session.initial_side == "player", "L'iniziativa premia il livello maggiore")
	var before_rng: int = session.rng.state
	var rejected: Dictionary = session.play_turn({"type": "attack", "move_id": 1})
	check(not bool(rejected.ok) and session.rng.state == before_rng and session.round_number == 0, "Il PvP attende entrambe le scelte senza tirare dadi")
	var played: Dictionary = session.play_turn({"type": "attack", "move_id": 1}, {"type": "attack", "move_id": 28})
	check(bool(played.ok) and bool(played.accepted), "Due scelte locali risolvono il round PvP")
	check(_count(played.events, "attack") >= 1, "Il round produce eventi di attacco")
	check(int(hero.hp) == int(hero.max_hp) and int(enemy.hp) == int(enemy.max_hp), "La sessione non modifica le squadre fornite dal modello")
	var snapshot: Dictionary = played.events[0].snapshot.player
	var original_hp: int = int(snapshot.hp)
	session.active_creature().hp = 1
	check(int(snapshot.hp) == original_hp, "Gli snapshot per le animazioni non cambiano con il modello")
	var invalid: Session = Session.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	check(not invalid.setup([], [enemy], "npc", rng), "Una squadra vuota viene rifiutata")
	check(not invalid.setup([hero], [enemy, enemy], "wild", rng), "Un incontro selvatico ha un solo bersaglio")
	var oversized: Array = []
	for _index: int in range(7):
		oversized.append(hero)
	check(not invalid.setup(oversized, [enemy], "npc", rng), "La sessione limita le squadre a sei membri")
	var weak: Dictionary = rules.creature(5)
	weak.hp = 1
	var pvp_switch: Session = _session([rules.creature(1, 10)], [weak, rules.creature(9)], "pvp")
	pvp_switch.play_turn({"type": "attack", "move_id": 1}, {"type": "wait"})
	check(pvp_switch.needs_switch == ["enemy"] and int(pvp_switch.active.enemy) == 0, "In PvP il secondo giocatore sceglie la propria riserva")
	var enemy_switch: Dictionary = pvp_switch.switch_active("enemy", 1)
	check(bool(enemy_switch.ok) and int(pvp_switch.active.enemy) == 1, "La sostituzione locale del secondo giocatore è applicata")
	var voluntary: Session = _session([rules.creature(1, 10), rules.creature(5, 10)], [rules.creature(9, 5)], "pvp")
	var changed: Dictionary = voluntary.play_turn({"type": "switch", "index": 1}, {"type": "attack", "move_id": 55})
	check(bool(changed.accepted) and int(voluntary.active.player) == 1 and int(voluntary.active_creature().hp) < int(voluntary.active_creature().max_hp), "Il cambio volontario occupa l'azione e la riserva può ricevere l'attacco avversario")


func _test_six_vs_six() -> void:
	var allies: Array = []
	var foes: Array = []
	for _index: int in range(6):
		allies.append(rules.creature(1, 20))
		var foe: Dictionary = rules.creature(5, 5)
		foe.hp = 1
		foes.append(foe)
	var session: Session = _session(allies, foes)
	for index: int in range(6):
		var played: Dictionary = session.play_turn({"type": "attack", "move_id": 1})
		check(bool(played.ok), "Il turno contro il membro %d è valido" % (index + 1))
		check(int(session.teams.enemy[index].hp) == 0, "Il membro %d viene sconfitto" % (index + 1))
		if index < 5:
			check(not session.finished and int(session.active.enemy) == index + 1, "L'NPC manda in campo la riserva successiva")
			check(_count(played.events, "switch") == 1 and _count(played.events, "attack") == 1, "La nuova riserva non attacca nel round del cambio forzato")
	check(session.finished and session.result.winner == "player", "La vittoria avviene soltanto dopo il sesto KO")
	check(int(session.active_creature().level) == 25, "L'EXP al cap minimo più cinque non si accumula")
	check(int(session.active_creature().hp) == int(allies[0].hp), "Salire di livello dopo un KO non cura gli HP")
	var last: Dictionary = session.play_turn({"type": "attack", "move_id": 1})
	check(not bool(last.ok), "Uno scontro concluso non assegna altri turni o premi")


func _test_forced_switch_and_status() -> void:
	var lead: Dictionary = rules.creature(1, 5)
	lead.hp = 1
	var session: Session = _session([lead, rules.creature(5, 5)], [rules.creature(32, 10)])
	var played: Dictionary = session.play_turn({"type": "attack", "move_id": 1})
	check(not session.finished and session.needs_switch == ["player"], "Un KO con riserva richiede una scelta del giocatore")
	check(_count(played.events, "attack") == 1, "Il membro KO non esegue l'azione già scelta")
	var blocked: Dictionary = session.play_turn({"type": "attack", "move_id": 1})
	check(not bool(blocked.ok), "Nessun round parte prima della sostituzione obbligatoria")
	var invalid: Dictionary = session.switch_active("player", 0)
	check(not bool(invalid.ok), "Un membro esausto non può sostituire sé stesso")
	var switched: Dictionary = session.switch_active("player", 1)
	check(bool(switched.ok) and session.needs_switch.is_empty() and int(session.active.player) == 1, "La riserva sana entra senza consumare un round")
	var voluntary: Dictionary = session.play_turn({"type": "switch", "index": 0})
	check(not bool(voluntary.ok), "Un cambio volontario verso un membro KO è rifiutato")
	var paralyzed: Dictionary = rules.creature(1, 50)
	rules.apply_status(paralyzed, "Paralizzato")
	var priority: Session = _session([paralyzed], [rules.creature(5, 5)])
	check(priority.initial_side == "enemy", "La paralisi perde la priorità anche con livello maggiore")
	var sleeper: Dictionary = rules.creature(1, 10)
	rules.apply_status(sleeper, "Addormentato")
	var sleep_session: Session = _session([sleeper], [rules.creature(5, 5)], "pvp")
	var asleep: Dictionary = sleep_session.play_turn({"type": "attack", "move_id": 1}, {"type": "wait"})
	check(not bool(asleep.accepted) and _count(asleep.events, "attack") == 0, "Il sonno blocca l'attacco prima dei dadi offensivi")
	var poisoned: Dictionary = rules.creature(1, 10)
	poisoned.hp = 1
	rules.apply_status(poisoned, "Avvelenato")
	var poison_session: Session = _session([poisoned], [rules.creature(5, 5)], "pvp")
	var poisoned_turn: Dictionary = poison_session.play_turn({"type": "attack", "move_id": 1}, {"type": "wait"})
	check(poison_session.finished and poison_session.result.winner == "enemy", "Il veleno può decidere lo scontro prima dell'attacco")
	check(_count(poisoned_turn.events, "attack") == 0 and int(poison_session.active_creature("enemy").level) == 6, "Il KO da veleno premia una sola volta l'avversario superstite")


func _test_supreme() -> void:
	var hero: Dictionary = rules.creature(1, 6)
	hero.hp = 6
	var enemy: Dictionary = rules.creature(13, 5)
	enemy.hp = 1
	var session: Session = _session([hero], [enemy], "pvp")
	var played: Dictionary = session.play_turn({"type": "supreme", "move_id": 1}, {"type": "wait"})
	check(session.finished and session.result.winner == "player" and session.result.reason == "double_ko", "Nel doppio ultimo KO vince chi ha attaccato")
	check(int(session.active_creature().level) == 7 and int(session.active_creature().hp) == 0, "Il livello sale prima del contraccolpo senza curare")
	var recoil: Dictionary = _event(played.events, "recoil")
	check(int(recoil.amount) == 7, "Il contraccolpo usa metà del nuovo massimo, arrotondata per difetto")
	check(_event_index(played.events, "ko") < _event_index(played.events, "xp") and _event_index(played.events, "xp") < _event_index(played.events, "recoil"), "Gli eventi ordinano KO, livello e contraccolpo per l'animazione")
	var with_reserve: Session = _session([hero], [enemy, rules.creature(5)], "pvp")
	with_reserve.play_turn({"type": "supreme", "move_id": 1}, {"type": "wait"})
	check(with_reserve.finished and with_reserve.result.winner == "enemy", "Il contraccolpo perde contro una squadra con riserve sane")
	var sleeper: Dictionary = rules.creature(1)
	var healer: Session = _session([rules.creature(95)], [sleeper], "pvp")
	var invalid: Dictionary = healer.play_turn({"type": "supreme", "move_id": 59}, {"type": "wait"})
	check(not bool(invalid.ok), "Una cura non può essere potenziata in Suprema")
	var status_only: Session = _session([rules.creature(21)], [sleeper], "pvp")
	invalid = status_only.play_turn({"type": "supreme", "move_id": 230}, {"type": "wait"})
	check(not bool(invalid.ok), "La Suprema non trasforma uno stato puro in danno")
	var normal_meta: Session = _session([rules.creature(107, 10)], [rules.creature(1, 50)], "pvp")
	var before: int = int(normal_meta.active_creature().hp)
	var ordinary: Dictionary = normal_meta.play_turn({"type": "attack", "move_id": 107}, {"type": "wait"})
	check(bool(ordinary.ok) and _count(ordinary.events, "recoil") == 0 and int(normal_meta.active_creature().hp) == before, "L'attacco normale ignora la classificazione legacy Suprema")
	var opponent: Dictionary = rules.creature(1, 6)
	opponent.hp = 6
	var player_target: Dictionary = rules.creature(13, 5)
	player_target.hp = 1
	var symmetric: Session = _session([player_target], [opponent], "pvp")
	symmetric.play_turn({"type": "wait"}, {"type": "supreme", "move_id": 1})
	check(symmetric.finished and symmetric.result.winner == "enemy" and symmetric.result.reason == "double_ko", "Anche l'attaccante del secondo giocatore vince il doppio ultimo KO")
	var evolving: Dictionary = rules.creature(1, 14)
	evolving.hp = 13
	var evolution: Session = _session([evolving], [enemy], "pvp")
	evolution.play_turn({"type": "supreme", "move_id": 1}, {"type": "wait"})
	check(int(evolution.active_creature().get("pending_evolution", 0)) == 2 and int(evolution.active_creature().hp) == 0, "La soglia evolutiva viene segnalata anche se il contraccolpo manda KO")


func _test_capture_and_items() -> void:
	var session: Session = _session([rules.creature(1, 10)], [rules.creature(5, 5)], "npc")
	var denied: Dictionary = session.play_turn({"type": "capture"})
	check(not bool(denied.ok) and not bool(denied.accepted), "La cattura contro un allenatore è rifiutata prima del turno")
	var wild: Session = _session([rules.creature(1, 10)], [rules.creature(5)], "wild")
	var caught: Dictionary = wild.play_turn({"type": "item", "effect": "masterball"})
	check(bool(caught.accepted) and wild.finished and wild.result.reason == "capture", "La Masterball cattura un bersaglio selvatico senza controattacco")
	check(int(wild.captured.species_id) == 5 and wild.teams.player.size() == 1, "La creatura catturata è restituita al modello per squadra o deposito")
	var hero: Dictionary = rules.creature(1, 10)
	hero.hp = 2
	var fainted: Dictionary = rules.creature(5, 5)
	fainted.hp = 0
	rules.apply_status(hero, "Paralizzato")
	var items: Session = _session([hero, fainted], [rules.creature(1, 5)], "pvp")
	var healed: Dictionary = items.play_turn({"type": "item", "effect": "heal", "target_index": 0, "amount": 0.25}, {"type": "wait"})
	check(bool(healed.accepted) and int(items.active_creature().hp) == 6, "La pozione recupera il venticinque percento degli HP massimi")
	check(items.rules.status_name(items.active_creature()) == "Paralizzato", "Una pozione non rimuove la paralisi né tira per il suo blocco")
	var revived: Dictionary = items.play_turn({"type": "item", "effect": "revive", "target_index": 1, "amount": 0.5}, {"type": "wait"})
	check(bool(revived.accepted) and int(items.teams.player[1].hp) == 6, "Il rianimatore agisce sulla riserva KO al cinquanta percento")
	var cured: Dictionary = items.play_turn({"type": "item", "effect": "cure", "target_index": 0, "status": "Paralizzato"}, {"type": "wait"})
	check(bool(cured.accepted) and items.rules.status_name(items.active_creature()).is_empty(), "L'Antiparalisi rimuove solo il proprio stato bersaglio")
	var invalid: Dictionary = items.play_turn({"type": "item", "effect": "cure", "target_index": 0, "status": "Avvelenato"}, {"type": "wait"})
	check(not bool(invalid.ok) and not bool(invalid.accepted), "Una cura senza effetto non autorizza il consumo dell'inventario")
	var sleepy: Dictionary = rules.creature(1, 10)
	sleepy.hp = 1
	rules.apply_status(sleepy, "Addormentato")
	var blocked: Session = _session([sleepy], [rules.creature(5)], "pvp")
	var blocked_item: Dictionary = blocked.play_turn({"type": "item", "effect": "heal", "amount": 0.25}, {"type": "wait"})
	check(bool(blocked_item.ok) and not bool(blocked_item.accepted), "Il sonno perde l'azione, ma non autorizza il consumo di un oggetto non applicato")
	check(_count(blocked_item.events, "item") == 0, "Gli eventi non simulano una cura bloccata dallo stato")
	var ordinary: Session = _session([rules.creature(1, 10)], [rules.creature(5)], "wild")
	ordinary.rng.seed = _capture_seed(ordinary, true)
	var caught_normal: Dictionary = ordinary.play_turn({"type": "capture"}, {"type": "wait"})
	check(bool(caught_normal.accepted) and ordinary.finished and ordinary.result.reason == "capture", "La cattura ordinaria riuscita conclude lo scontro")
	check(_event(caught_normal.events, "capture").dice.size() == 3, "La cattura ordinaria presenta i tre D6 negli eventi")
	var escaped: Session = _session([rules.creature(1, 10)], [rules.creature(5)], "wild")
	escaped.rng.seed = _capture_seed(escaped, false)
	var failed_capture: Dictionary = escaped.play_turn({"type": "capture"}, {"type": "wait"})
	check(bool(failed_capture.accepted) and not escaped.finished and escaped.round_number == 1, "Una cattura fallita consuma l'azione e lascia proseguire lo scontro")
	var paralyzer: Dictionary = rules.creature(21)
	var choice_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var choice: Dictionary = rules.choose_ai(paralyzer, rules.creature(1, 50), choice_rng)
	check(int(choice.move_id) == 230, "L'IA usa la paralisi pura quando toglie la priorità a un avversario forte")


func _capture_seed(session: Session, succeeds: bool) -> int:
	var fixture: RandomNumberGenerator = RandomNumberGenerator.new()
	for candidate: int in range(10000):
		fixture.seed = candidate
		var attempt: Dictionary = session.rules.capture(session.active_creature("enemy"), fixture)
		if bool(attempt.success) == succeeds:
			return candidate
	return 0


func _test_snapshot_restore() -> void:
	var lead: Dictionary = rules.creature(1, 20)
	lead["instance_id"] = "campaign-member-0001"
	rules.apply_status(lead, "Avvelenato")
	var original: Session = _session([lead, rules.creature(5, 20)], [rules.creature(9, 20), rules.creature(13, 20)], "pvp")
	original.play_turn({"type": "wait"}, {"type": "wait"})
	var saved: Dictionary = original.snapshot()
	check(saved.rng_seed is String and saved.rng_state is String, "Lo snapshot serializza il generatore 64 bit come stringhe")
	var encoded: String = JSON.stringify(saved)
	var decoded: Dictionary = JSON.parse_string(encoded)
	var restored: Session = Session.new()
	check(restored.restore(decoded, RandomNumberGenerator.new()), "Uno snapshot passa attraverso JSON e viene ripristinato")
	check(restored.rng.state == original.rng.state and restored.rng.seed == original.rng.seed, "Il generatore torna esattamente nello stato precedente")
	check(restored.round_number == 1 and restored.initial_side == original.initial_side, "Il ripristino conserva round e priorità senza ritirarli")
	check(str(restored.active_creature().instance_id) == "campaign-member-0001", "L'identità del membro resta quella della campagna")
	check(int(restored.active_creature().status.elapsed) == 1, "Il ripristino conserva il contatore del veleno")
	var next_original: Dictionary = original.play_turn({"type": "attack", "move_id": 1}, {"type": "attack", "move_id": 55})
	var next_restored: Dictionary = restored.play_turn({"type": "attack", "move_id": 1}, {"type": "attack", "move_id": 55})
	check(_canonical_json(next_original) == _canonical_json(next_restored), "Il round dopo la ricarica produce gli stessi dadi, eventi e risultati")
	check(_canonical_json(original.snapshot()) == _canonical_json(restored.snapshot()), "Gli stati completi restano identici dopo il round ripreso")
	var broken: Dictionary = decoded.duplicate(true)
	broken.active.player = 99
	check(not restored.restore(broken, RandomNumberGenerator.new()), "Un indice attivo inesistente viene rifiutato")
	broken = decoded.duplicate(true)
	broken.rng_state = "9223372036854775808"
	check(not restored.restore(broken, RandomNumberGenerator.new()), "Un generatore fuori dall'intervallo 64 bit viene rifiutato")
	broken = decoded.duplicate(true)
	broken.finished = true
	broken.result = {"winner": "player", "reason": "victory"}
	check(not restored.restore(broken, RandomNumberGenerator.new()), "Una vittoria con squadra avversaria ancora viva viene rifiutata")
	broken = decoded.duplicate(true)
	broken.teams.player[0].status.turns = 1.5
	check(not restored.restore(broken, RandomNumberGenerator.new()), "Uno stato con durata frazionaria viene rifiutato")
	var doomed: Dictionary = rules.creature(1, 5)
	doomed.hp = 1
	var switching: Session = _session([doomed, rules.creature(5)], [rules.creature(32, 10)])
	switching.play_turn({"type": "attack", "move_id": 1})
	var switch_restore: Session = Session.new()
	check(switch_restore.restore(JSON.parse_string(JSON.stringify(switching.snapshot())), RandomNumberGenerator.new()), "Un salvataggio in attesa di sostituzione si riprende")
	check(switch_restore.needs_switch == ["player"] and switch_restore.awaiting_switch == "player", "La sostituzione obbligatoria resta tale dopo la ripresa")
	var changed: Dictionary = switch_restore.switch_active("player", 1)
	check(bool(changed.ok), "La riserva può entrare dopo il ripristino")
	var wild: Session = _session([rules.creature(1)], [rules.creature(5)], "wild")
	wild.play_turn({"type": "item", "effect": "masterball"}, {"type": "wait"})
	var capture_restore: Session = Session.new()
	check(capture_restore.restore(JSON.parse_string(JSON.stringify(wild.snapshot())), RandomNumberGenerator.new()) and capture_restore.finished and int(capture_restore.captured.species_id) == 5, "Un esito cattura conserva la creatura per il settlement dopo la ripresa")


func _canonical_json(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))


func _count(events: Array, type: String) -> int:
	var count: int = 0
	for entry: Dictionary in events:
		if str(entry.type) == type:
			count += 1
	return count


func _event(events: Array, type: String) -> Dictionary:
	for entry: Dictionary in events:
		if str(entry.type) == type:
			return entry
	return {}


func _event_index(events: Array, type: String) -> int:
	for index: int in range(events.size()):
		if str(events[index].type) == type:
			return index
	return 99999


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

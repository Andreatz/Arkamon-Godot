class_name BattleSession
extends RefCounted
## Resolves complete rounds. Presentation replays immutable event snapshots.
## Inventory ownership and campaign rewards belong to CampaignModel.

var rules: BattleRules = BattleRules.new()
var teams: Dictionary = {"player": [], "enemy": []}
var active: Dictionary = {"player": 0, "enemy": 0}
var kind: String = "wild"
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var finished: bool = false
var result: Dictionary = {}
var needs_switch: Array[String] = []
var awaiting_switch: String = ""
var round_number: int = 0
var initial_side: String = "player"
var captured: Dictionary = {}
var _events: Array = []
var _accepted: bool = false


func setup(player_team: Array, enemy_team: Array, battle_kind: String, random: RandomNumberGenerator) -> bool:
	if battle_kind not in ["wild", "npc", "pvp"] or random == null:
		return false
	if rules.species.is_empty() and not rules.load_data():
		return false
	var player: Array = _normalize_team(player_team)
	var enemy: Array = _normalize_team(enemy_team)
	if player.is_empty() or enemy.is_empty() or (battle_kind == "wild" and enemy.size() != 1):
		return false
	teams = {"player": player, "enemy": enemy}
	active = {"player": _first_alive("player"), "enemy": _first_alive("enemy")}
	# Keep an addressable creature even for an already exhausted input team.
	active.player = maxi(0, int(active.player))
	active.enemy = maxi(0, int(active.enemy))
	kind = battle_kind
	rng = random
	finished = false
	result = {}
	captured = {}
	needs_switch.clear()
	awaiting_switch = ""
	round_number = 0
	_events = []
	initial_side = _initial_priority()
	_evaluate_end("")
	return true


func active_creature(side: String = "player") -> Dictionary:
	if not teams.has(side) or teams[side].is_empty():
		return {}
	return teams[side][int(active[side])]


func play_turn(player_action: Dictionary, enemy_action: Dictionary = {}) -> Dictionary:
	_events = []
	_accepted = false
	if finished:
		return _response(false, "Lo scontro è già concluso.")
	if not needs_switch.is_empty():
		return _response(false, "Scegli un compagno per sostituire quello esausto.")
	var player_error: String = _validate_action("player", player_action)
	if not player_error.is_empty():
		return _response(false, player_error)
	if kind == "pvp" and enemy_action.is_empty():
		return _response(false, "Il secondo giocatore deve scegliere la propria azione.")
	var selected_enemy: Dictionary = enemy_action
	if selected_enemy.is_empty():
		selected_enemy = rules.choose_ai(active_creature("enemy"), active_creature("player"), rng)
	var enemy_error: String = _validate_action("enemy", selected_enemy)
	if not enemy_error.is_empty():
		return _response(false, enemy_error)
	round_number += 1
	var first: String = _round_priority()
	var second: String = _other(first)
	_emit("initiative", first, "%s agisce per primo." % active_creature(first).name, {"round": round_number})
	var actions: Dictionary = {"player": player_action, "enemy": selected_enemy}
	for side: String in [first, second]:
		if finished or not needs_switch.is_empty():
			break
		var slots_before: Dictionary = active.duplicate()
		_execute(side, actions[side])
		if finished or not needs_switch.is_empty() or (slots_before != active and str(actions[side].type) != "switch"):
			break
	return _response(true)


func switch_active(side: String, index: int) -> Dictionary:
	_events = []
	_accepted = false
	if finished or not side in needs_switch or not _can_switch(side, index):
		return _response(false, "La sostituzione non è disponibile.")
	active[side] = index
	_accepted = true
	needs_switch.erase(side)
	_update_awaiting()
	_emit("switch", side, "%s entra in campo!" % active_creature(side).name, {"index": index, "forced": true})
	return _response(true)


func snapshot() -> Dictionary:
	return {"schema_version": 1, "kind": kind, "teams": teams.duplicate(true), "active": active.duplicate(),
		"round_number": round_number, "initial_side": initial_side, "needs_switch": needs_switch.duplicate(),
		"finished": finished, "result": result.duplicate(true), "captured": captured.duplicate(true),
		"rng_seed": str(rng.seed), "rng_state": str(rng.state)}


func restore(saved: Dictionary, random: RandomNumberGenerator) -> bool:
	if random == null or int(saved.get("schema_version", -1)) != 1:
		return false
	if not saved.get("teams") is Dictionary or not saved.get("active") is Dictionary or not saved.get("needs_switch") is Array or not saved.get("result") is Dictionary or not saved.get("captured") is Dictionary:
		return false
	if typeof(saved.get("finished")) != TYPE_BOOL or str(saved.get("initial_side", "")) not in ["player", "enemy"]:
		return false
	var seed_text: String = str(saved.get("rng_seed", ""))
	var state_text: String = str(saved.get("rng_state", ""))
	if not saved.get("rng_seed") is String or not saved.get("rng_state") is String or not seed_text.is_valid_int() or not state_text.is_valid_int():
		return false
	if str(int(seed_text)) != seed_text or str(int(state_text)) != state_text:
		return false
	if not _whole_number(saved.get("round_number")) or int(saved.round_number) < 0 or int(saved.round_number) > 10000000:
		return false
	var saved_teams: Dictionary = saved.teams
	if not saved_teams.get("player") is Array or not saved_teams.get("enemy") is Array:
		return false
	var candidate: BattleSession = BattleSession.new()
	candidate.rules = rules
	if not candidate.setup(saved_teams.player, saved_teams.enemy, str(saved.get("kind", "")), RandomNumberGenerator.new()):
		return false
	for side: String in ["player", "enemy"]:
		if not _whole_number(saved.active.get(side)):
			return false
		var index: int = int(saved.active[side])
		if index < 0 or index >= candidate.teams[side].size():
			return false
		candidate.active[side] = index
	candidate.needs_switch.clear()
	for side: Variant in saved.needs_switch:
		if not side is String or str(side) not in ["player", "enemy"] or str(side) in candidate.needs_switch:
			return false
		candidate.needs_switch.append(str(side))
	candidate.finished = bool(saved.finished)
	candidate.result = saved.result.duplicate(true)
	if not saved.captured.is_empty():
		var normalized_capture: Array = candidate._normalize_team([saved.captured])
		if normalized_capture.is_empty():
			return false
		candidate.captured = normalized_capture[0]
	else:
		candidate.captured = {}
	var player_alive: bool = candidate._first_alive("player") >= 0
	var enemy_alive: bool = candidate._first_alive("enemy") >= 0
	if candidate.finished:
		var winner: String = str(candidate.result.get("winner", ""))
		var reason: String = str(candidate.result.get("reason", ""))
		if winner not in ["player", "enemy"] or reason not in ["victory", "defeat", "double_ko", "capture", "fled"] or not candidate.needs_switch.is_empty():
			return false
		if reason == "victory" and (not player_alive or enemy_alive or winner != "player"):
			return false
		if reason == "defeat" and (player_alive or not enemy_alive or winner != "enemy"):
			return false
		if reason == "double_ko" and (player_alive or enemy_alive):
			return false
		if reason in ["capture", "fled"] and candidate.kind != "wild":
			return false
		if reason == "capture" and (candidate.captured.is_empty() or winner != "player"):
			return false
	else:
		if not player_alive or not enemy_alive or not candidate.result.is_empty() or not candidate.captured.is_empty():
			return false
		for side: String in ["player", "enemy"]:
			if (int(candidate.active_creature(side).hp) <= 0) != (side in candidate.needs_switch):
				return false
		if candidate.kind != "pvp" and "enemy" in candidate.needs_switch:
			return false
	teams = candidate.teams
	active = candidate.active
	kind = candidate.kind
	needs_switch.assign(candidate.needs_switch)
	finished = candidate.finished
	result = candidate.result
	captured = candidate.captured
	initial_side = str(saved.initial_side)
	round_number = int(saved.round_number)
	rng = random
	rng.seed = int(seed_text)
	rng.state = int(state_text)
	_events = []
	_accepted = false
	_update_awaiting()
	return true


func _execute(side: String, action: Dictionary) -> void:
	var action_type: String = str(action.get("type", ""))
	if action_type == "switch":
		active[side] = int(action.index)
		_emit("switch", side, "%s entra in campo!" % active_creature(side).name, {"index": int(action.index), "forced": false})
		if side == "player":
			_accepted = true
		return
	if action_type == "flee":
		if side == "player":
			_accepted = true
		_finish(_other(side), "fled")
		return
	var fighter: Dictionary = active_creature(side)
	var offensive: bool = action_type in ["attack", "supreme"]
	if offensive:
		var move: Dictionary = rules.move_info(fighter, int(action.get("move_id", 0)))
		offensive = str(move.get("effect", "")) not in ["CURA", "CURA_PCT"]
	var status_result: Dictionary = rules.process_status(fighter, rng, offensive)
	if not str(status_result.text).is_empty():
		_emit("status", side, str(status_result.text), {"dice": status_result.dice, "damage": int(status_result.damage), "can_act": bool(status_result.can_act)})
	if int(fighter.hp) <= 0:
		_emit("ko", side, "%s è fuori combattimento!" % fighter.name)
		_reward_ko(_other(side))
		_evaluate_end("")
		if not finished:
			_request_switches()
		return
	if not bool(status_result.can_act):
		return
	if action_type in ["capture", "item"]:
		if action_type == "capture" or str(action.get("effect", "")) == "masterball":
			var caught: Dictionary = rules.capture(active_creature(_other(side)), rng) if action_type == "capture" else {"success": true, "dice": [], "text": "La Masterball cattura l'Arkamon selvatico!"}
			_emit("capture", side, str(caught.text), {"dice": caught.dice, "success": bool(caught.success), "applied": true})
			if side == "player":
				_accepted = true
			if bool(caught.success):
				captured = active_creature(_other(side)).duplicate(true)
				_finish(side, "capture")
		else:
			_apply_item(side, action)
		return
	if action_type == "wait":
		_emit("wait", side, "%s attende." % fighter.name)
		return
	var target_side: String = _other(side)
	var target: Dictionary = active_creature(target_side)
	_emit("attack", side, "%s prepara la mossa." % fighter.name, {"move_id": int(action.move_id), "supreme": action_type == "supreme"})
	var impact: Dictionary = rules.attack(fighter, target, int(action.move_id), rng, {"supreme": action_type == "supreme", "defer_recoil": true})
	if not bool(impact.ok):
		_emit("error", side, str(impact.text))
		return
	if side == "player":
		_accepted = true
	_emit("dice", side, "Dadi della mossa.", {"dice": impact.dice, "move_id": int(action.move_id)})
	if int(impact.heal) > 0 or not str(impact.get("status_cured", "")).is_empty():
		_emit("heal", side, str(impact.text), {"amount": int(impact.heal), "status_cured": impact.get("status_cured", "")})
	else:
		_emit("damage", target_side, str(impact.text), {"amount": int(impact.damage), "actual_damage": int(impact.actual_damage), "attacker": side, "multiplier": impact.multiplier})
	if not str(impact.get("status_applied", "")).is_empty():
		_emit("status", target_side, "%s è %s." % [target.name, impact.status_applied], {"status": impact.status_applied})
	var direct_ko: bool = int(target.hp) <= 0
	if direct_ko:
		_emit("ko", target_side, "%s è fuori combattimento!" % target.name)
		_reward_ko(side)
	# KO reward raises the maximum HP first, without healing; recoil uses that maximum.
	if action_type == "supreme":
		var cost: int = maxi(1, int(float(fighter.max_hp) * 0.5))
		fighter.hp = maxi(0, int(fighter.hp) - cost)
		_emit("recoil", side, "La Suprema costa %d HP a %s." % [cost, fighter.name], {"amount": cost})
		if int(fighter.hp) <= 0:
			_emit("ko", side, "%s è fuori combattimento!" % fighter.name)
			if not direct_ko:
				_reward_ko(target_side)
	_evaluate_end(side if direct_ko else "")
	if not finished:
		_request_switches()


func _validate_action(side: String, action: Dictionary) -> String:
	var action_type: String = str(action.get("type", ""))
	var fighter: Dictionary = active_creature(side)
	match action_type:
		"attack", "supreme":
			var info: Dictionary = rules.move_info(fighter, int(action.get("move_id", 0)))
			if info.is_empty():
				return "La mossa selezionata non appartiene al compagno attivo."
			if action_type == "supreme" and (bool(info.status_only) or str(info.effect) in ["CURA", "CURA_PCT"]):
				return "Una cura o uno stato puro non può diventare Suprema."
		"switch":
			if not _can_switch(side, int(action.get("index", -1))):
				return "Il compagno selezionato non può entrare in campo."
		"capture":
			if kind != "wild" or side != "player":
				return "Puoi catturare solo Arkamon selvatici."
		"item":
			return _validate_item(side, action)
		"flee":
			if kind != "wild" or side != "player":
				return "La ritirata è disponibile soltanto negli incontri selvatici."
		"wait":
			pass
		_:
			return "Azione sconosciuta."
	return ""


func _validate_item(side: String, action: Dictionary) -> String:
	var effect: String = str(action.get("effect", ""))
	if effect == "masterball":
		return "" if kind == "wild" and side == "player" else "La Masterball può catturare solo Arkamon selvatici."
	var index: int = int(action.get("target_index", active[side]))
	if index < 0 or index >= teams[side].size():
		return "Bersaglio dell'oggetto non valido."
	var target: Dictionary = teams[side][index]
	var fraction: float = float(action.get("amount", 0.0))
	match effect:
		"heal":
			if int(target.hp) <= 0 or int(target.hp) >= int(target.max_hp) or not is_finite(fraction) or fraction <= 0.0 or fraction > 1.0:
				return "La pozione non avrebbe effetto."
		"revive":
			if int(target.hp) > 0 or not is_finite(fraction) or fraction <= 0.0 or fraction > 1.0:
				return "Il rianimatore richiede un compagno esausto."
		"cure":
			var cured_status: String = str(action.get("status", ""))
			if int(target.hp) <= 0 or cured_status not in ["Avvelenato", "Paralizzato", "Addormentato"] or rules.status_name(target) != cured_status:
				return "La cura di stato non avrebbe effetto."
		_:
			return "Effetto dell'oggetto sconosciuto."
	return ""


func _apply_item(side: String, action: Dictionary) -> void:
	# Status ticks can change the target after preflight validation.
	if not _validate_item(side, action).is_empty():
		_emit("item", side, "L'oggetto non ha più un bersaglio valido.", {"applied": false})
		return
	var index: int = int(action.get("target_index", active[side]))
	var target: Dictionary = teams[side][index]
	var effect: String = str(action.effect)
	var before: int = int(target.hp)
	if effect == "cure":
		rules.clear_status(target)
	else:
		var amount: int = maxi(1, int(float(target.max_hp) * float(action.amount)))
		target.hp = mini(int(target.max_hp), int(target.hp) + amount)
	_emit("item", side, "Oggetto usato su %s." % target.name, {"applied": true, "effect": effect, "target_index": index, "amount": int(target.hp) - before})
	if side == "player":
		_accepted = true


func _reward_ko(side: String) -> void:
	var fighter: Dictionary = active_creature(side)
	if int(fighter.hp) <= 0:
		return
	var limit: int = 100
	for index: int in range(teams[side].size()):
		if index != int(active[side]):
			limit = mini(limit, int(teams[side][index].level) + 5)
	var levels: int = 0
	if int(fighter.level) < limit and int(fighter.level) < 100:
		var raised: Dictionary = rules.creature(int(fighter.species_id), int(fighter.level) + 1)
		fighter.level = raised.level
		fighter.max_hp = raised.max_hp
		fighter.moves = raised.moves
		levels = 1
	var definition: Dictionary = rules.species[int(fighter.species_id)]
	var evolution: int = int(definition.get("evoluzioneId", 0)) if int(definition.get("livelloEvoluzione", 0)) > 0 and int(fighter.level) >= int(definition.get("livelloEvoluzione", 0)) else 0
	fighter["xp"] = 0
	if evolution > 0:
		fighter["pending_evolution"] = evolution
	_emit("xp", side, "%s sale al livello %d." % [fighter.name, int(fighter.level)] if levels > 0 else "Il cap della squadra impedisce di accumulare EXP.", {"index": int(active[side]), "levels": levels, "xp_discarded": 1 - levels, "pending_evolution": evolution})


func _evaluate_end(double_ko_winner: String) -> void:
	var player_alive: bool = _first_alive("player") >= 0
	var enemy_alive: bool = _first_alive("enemy") >= 0
	if not player_alive and not enemy_alive:
		_finish(double_ko_winner if not double_ko_winner.is_empty() else "enemy", "double_ko")
	elif not player_alive:
		_finish("enemy", "defeat")
	elif not enemy_alive:
		_finish("player", "victory")


func _request_switches() -> void:
	needs_switch.clear()
	for side: String in ["player", "enemy"]:
		if int(active_creature(side).hp) > 0:
			continue
		var index: int = _first_alive(side)
		if index < 0:
			continue
		if side == "enemy" and kind != "pvp":
			active[side] = index
			_emit("switch", side, "%s entra in campo!" % active_creature(side).name, {"index": index, "forced": true})
		else:
			needs_switch.append(side)
	_update_awaiting()


func _finish(winner: String, reason: String) -> void:
	finished = true
	result = {"winner": winner, "reason": reason}
	needs_switch.clear()
	_update_awaiting()
	_emit("end", winner, "Lo scontro è concluso.", result)


func _initial_priority() -> String:
	var player: Dictionary = active_creature("player")
	var enemy: Dictionary = active_creature("enemy")
	var player_paralyzed: bool = rules.status_name(player) == "Paralizzato"
	var enemy_paralyzed: bool = rules.status_name(enemy) == "Paralizzato"
	if player_paralyzed != enemy_paralyzed:
		return "enemy" if player_paralyzed else "player"
	if int(player.level) != int(enemy.level):
		return "player" if int(player.level) > int(enemy.level) else "enemy"
	return "player" if rng.randf() < 0.5 else "enemy"


func _round_priority() -> String:
	var player_paralyzed: bool = rules.status_name(active_creature("player")) == "Paralizzato"
	var enemy_paralyzed: bool = rules.status_name(active_creature("enemy")) == "Paralizzato"
	return ("enemy" if player_paralyzed else "player") if player_paralyzed != enemy_paralyzed else initial_side


func _can_switch(side: String, index: int) -> bool:
	return teams.has(side) and index >= 0 and index < teams[side].size() and index != int(active[side]) and int(teams[side][index].hp) > 0


func _first_alive(side: String) -> int:
	for index: int in range(teams[side].size()):
		if int(teams[side][index].hp) > 0:
			return index
	return -1


func _other(side: String) -> String:
	return "enemy" if side == "player" else "player"


func _update_awaiting() -> void:
	awaiting_switch = "both" if needs_switch.size() == 2 else (needs_switch[0] if not needs_switch.is_empty() else "")


func _emit(event_type: String, side: String, text: String, extra: Dictionary = {}) -> void:
	var entry: Dictionary = {"type": event_type, "side": side, "text": text,
		"snapshot": {"player": active_creature("player").duplicate(true), "enemy": active_creature("enemy").duplicate(true), "active": active.duplicate()}}
	entry.merge(extra, true)
	_events.append(entry)


func _response(ok: bool, error: String = "") -> Dictionary:
	return {"ok": ok, "accepted": _accepted, "events": _events.duplicate(true), "finished": finished, "winner": str(result.get("winner", "")), "reason": str(result.get("reason", "")), "needs_switch": needs_switch.duplicate(), "error": error}


func _normalize_team(raw_team: Array) -> Array:
	if raw_team.is_empty() or raw_team.size() > 6:
		return []
	var normalized: Array = []
	for value: Variant in raw_team:
		if not value is Dictionary:
			return []
		var member: Dictionary = value
		if not _whole_number(member.get("level")) or not _whole_number(member.get("species_id")) or not _whole_number(member.get("hp")):
			return []
		var level: int = int(member.get("level", 0))
		if level < 5 or level > 100:
			return []
		var rebuilt: Dictionary = rules.creature(int(member.get("species_id", 0)), level)
		if rebuilt.is_empty() or int(member.get("hp", -1)) < 0 or int(member.get("hp", -1)) > int(rebuilt.max_hp):
			return []
		rebuilt.hp = int(member.hp)
		for key: String in ["instance_id", "pending_evolution", "status"]:
			if member.has(key):
				rebuilt[key] = member[key].duplicate(true) if member[key] is Dictionary else member[key]
		if rebuilt.has("status"):
			if not rebuilt.status is Dictionary or not BattleRules.STATUS_DURATIONS.has(rules.status_name(rebuilt)) or not _whole_number(rebuilt.status.get("turns")):
				return []
			var status_type: String = rules.status_name(rebuilt)
			var turns: int = int(rebuilt.status.turns)
			if status_type in ["Paralizzato", "Avvelenato"]:
				rebuilt.status.turns = -1
			elif turns < 1 or turns > int(BattleRules.STATUS_DURATIONS[status_type]):
				return []
			if status_type == "Avvelenato" and (not _whole_number(rebuilt.status.get("elapsed", 0)) or int(rebuilt.status.get("elapsed", 0)) < 0 or int(rebuilt.status.get("elapsed", 0)) > 10000000):
				return []
		normalized.append(rebuilt)
	return normalized


func _whole_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floor(float(value))

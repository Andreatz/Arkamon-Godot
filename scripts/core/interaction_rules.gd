class_name InteractionRules
extends RefCounted
## Optional authoring data, stored in the campaign rather than executable scripts.

const TYPES: Array[String] = ["dialogue", "reward", "heal", "wild", "trainer", "shop"]

static func key(location: String, node: String) -> String:
	return location + ":" + node

static func validate(entry: Dictionary, model: CampaignModel) -> String:
	if String(entry.get("type", "")) not in TYPES: return "Scegli un tipo di interazione."
	var location := String(entry.get("location", ""))
	var node := String(entry.get("node_id", ""))
	if not model.local_maps.has(location): return "Scegli una mappa locale disponibile."
	var found: bool = false
	for point: Dictionary in model.local_maps[location].nodes:
		if String(point.id) == node: found = true
	if not found: return "Il punto non appartiene alla mappa."
	if String(entry.get("text", "")).length() > 2000: return "Il dialogo può contenere al massimo 2000 caratteri."
	for field: String in ["coins", "quantity", "min_badges"]:
		var amount: Variant = entry.get(field, 0)
		if not (amount is float or amount is int) or float(amount) != floorf(float(amount)) or int(amount) < 0 or int(amount) > (8 if field == "min_badges" else 99999): return "Ricompensa o requisito non valido."
	if not String(entry.get("item_id", "")).is_empty() and model.item_definition(String(entry.item_id)).is_empty(): return "Oggetto non riconosciuto."
	if String(entry.type) == "trainer":
		var trainer_found: bool = false
		for trainer: Dictionary in model.trainers:
			if int(trainer.id) == int(entry.get("trainer_id", 0)) and String(trainer.luogo) == location: trainer_found = true
		if not trainer_found: return "Scegli un allenatore presente nel luogo."
	return ""

static func configure(entry: Dictionary, model: CampaignModel) -> Dictionary:
	var problem := validate(entry, model)
	if not problem.is_empty(): return {"ok": false, "message": problem}
	if not model.state.get("pending", {}).is_empty(): return {"ok": false, "message": "Concludi lo scontro prima di modificare le interazioni."}
	if not model.state.get("interactions") is Dictionary: model.state["interactions"] = {}
	model.state.interactions[key(String(entry.location), String(entry.node_id))] = entry.duplicate(true)
	return {"ok": true, "message": "Interazione salvata nella campagna."}

static func current(model: CampaignModel) -> Dictionary:
	var catalogue: Dictionary = model.state.get("interactions", {})
	return catalogue.get(key(String(model.player().location), String(model.player().local_node)), {})

static func apply(model: CampaignModel) -> Dictionary:
	var entry: Dictionary = current(model)
	if entry.is_empty(): return {"ok": false, "message": "Questo punto non ha ancora un'interazione assegnata."}
	var problem := validate(entry, model)
	if not problem.is_empty(): return {"ok": false, "message": problem}
	if not model.state.pending.is_empty() or int(model.state.actions_left) <= 0 or int(model.state.league.winner) >= 0 or String(model.player().league.status) == "running": return {"ok": false, "message": "Non hai un'azione disponibile durante l'attività corrente."}
	var p: Dictionary = model.player()
	if p.badges.size() < int(entry.get("min_badges", 0)): return {"ok": false, "message": "Servono almeno %d medaglie." % int(entry.min_badges)}
	var identifier := key(String(entry.location), String(entry.node_id))
	var completion: Dictionary = model.state.get("interaction_completions", {})
	var completion_key := identifier + (":shared" if bool(entry.get("shared", false)) else ":%d" % int(model.state.active_player))
	if bool(entry.get("once", false)) and completion.has(completion_key): return {"ok": false, "message": "Questa interazione è già stata completata."}
	var previous := String(entry.get("prerequisite", ""))
	if not previous.is_empty() and not completion.has(previous + ":shared") and not completion.has(previous + ":%d" % int(model.state.active_player)):
		return {"ok": false, "message": "Completa prima l'interazione richiesta."}
	var result: Dictionary = {"ok": true, "message": String(entry.get("text", ""))}
	match String(entry.type):
		"wild": result = model.encounter(String(entry.get("bush", "A")))
		"trainer": result = model.trainer_battle(int(entry.get("trainer_id", 0)))
		"heal":
			for member: Dictionary in p.party:
				member.hp = int(member.max_hp)
				model.rules.clear_status(member)
			model.state.actions_left = 0
			result.message = "La squadra è stata curata."
		"shop":
			if not model.has_shop(): return {"ok": false, "message": "Il negozio deve trovarsi in città."}
			result["open_shop"] = true
		_:
			var item_id := String(entry.get("item_id", ""))
			var quantity := int(entry.get("quantity", 0))
			if not item_id.is_empty() and int(p.bag.get(item_id, 0)) + quantity > 999999: return {"ok": false, "message": "La borsa non può contenere la ricompensa."}
			p.coins = mini(999999999, int(p.coins) + int(entry.get("coins", 0)))
			if not item_id.is_empty(): p.bag[item_id] = int(p.bag.get(item_id, 0)) + quantity
			model.state.actions_left = 0
	if bool(result.get("ok", false)):
		completion[completion_key] = true
		model.state["interaction_completions"] = completion
		p.journal.append({"title": "Interazione", "message": String(entry.get("text", result.get("message", ""))), "location": p.location})
		while p.journal.size() > 200: p.journal.pop_front()
	return result

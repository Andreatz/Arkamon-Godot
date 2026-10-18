extends SceneTree
## Headless regression of the production UI through real button callbacks.
## Run without --smoke-test/--screenshot; those modes exit the application early.

const TEST_SAVE: String = "user://test-site-ui/campaign.json"
const TEST_PREFS: String = "user://test-site-ui/preferences.cfg"
const VIEW_SIZE: Vector2 = Vector2(1440, 810)
const PROTECTED_PATHS: Array[String] = [
	"user://campaign.json", "user://campaign.json.bak", "user://campaign.json.tmp",
	"user://full_campaign.json", "user://full_campaign.json.bak", "user://full_campaign.json.tmp",
	"user://preferences.cfg",
]

var app: Variant
var checks: int = 0
var failures: int = 0
var finished: bool = false
var protected_before: Dictionary = {}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(60.0).timeout.connect(_timeout)
	protected_before = _protected_fingerprints()
	_cleanup()
	root.size = Vector2i(1440, 810)
	root.content_scale_size = Vector2i(1440, 810)
	var scene: PackedScene = load("res://scenes/main.tscn")
	app = scene.instantiate()
	app.testing = true
	app.fast_mode = true
	app.reduced_motion = true
	app.sound_enabled = false
	app.save_path = TEST_SAVE
	app.preferences_path = TEST_PREFS
	root.add_child(app)
	await _frames()
	check(String(app.save_path) == TEST_SAVE and String(app.preferences_path) == TEST_PREFS, "Ready conserva entrambi i percorsi isolati impostati prima dell'albero")
	if String(app.save_path) != TEST_SAVE or String(app.preferences_path) != TEST_PREFS:
		await _finish()
		return
	check(root.get_visible_rect().size.is_equal_approx(VIEW_SIZE), "Il test usa il viewport logico 1440×810")
	check(String(app.screen) == "title", "L'applicazione parte dal titolo")
	check(_button_with_text("Nuova Partita") != null and _button_with_text("Continua") == null, "Senza salvataggio isolato il titolo propone soltanto la nuova partita")
	await _audio_preserves_state("title")
	if not await _click_by_text("Partita"):
		await _finish()
		return
	check(String(app.screen) == "tools" and _button_with_text("Importa partita della demo") != null, "Gli strumenti e l'importazione della demo restano raggiungibili prima di iniziare")
	if not await _click_by_text("Riprendi il Viaggio"):
		await _finish()
		return
	check(String(app.screen) == "title" and app.model.state.is_empty(), "Il footer degli strumenti prima della campagna torna al titolo")
	if not await _new_game_from_buttons():
		await _finish()
		return
	await _audio_preserves_state("world")
	if not await _continue_from_button():
		await _finish()
		return
	if not await _tools_and_management():
		await _finish()
		return
	if not await _travel_and_pvp():
		await _finish()
		return
	await _audio_preserves_state("battle")
	_check_battle_geometry()
	check(String(app.save_path) == TEST_SAVE and String(app.preferences_path) == TEST_PREFS, "Navigazione, audio e battaglia non cambiano i percorsi di test")
	check(FileAccess.file_exists(TEST_SAVE), "Il flusso reale ha prodotto il salvataggio nel percorso isolato")
	check(not FileAccess.file_exists(TEST_PREFS), "Le preferenze in modalità test non scrivono file")
	await _finish()


func _new_game_from_buttons() -> bool:
	if not await _click_by_text("Nuova Partita"):
		return false
	check(String(app.screen) == "starters" and app.name_inputs.size() == 2, "Nuova Partita apre il modulo con due nomi")
	if app.name_inputs.size() != 2:
		return false
	for index: int in range(2):
		var edit: LineEdit = app.name_inputs[index]
		var name_value: String = "Ada" if index == 0 else "Bruno"
		edit.text = name_value
		edit.text_changed.emit(name_value)
	if not await _click_by_text("Continua"):
		return false
	var starter_names: Array[String] = []
	for id: int in [1, 5, 9]:
		var name_value: String = String(app.rules.creature(id, 5).name)
		starter_names.append(name_value)
		var card: Button = _button_with_text(name_value)
		check(card != null and not card.disabled, "La scheda starter %s è presente e selezionabile" % name_value)
	if not await _click_by_text(starter_names[0]):
		return false
	check(String(app.screen) == "starters" and app.starter_choices == [1], "La prima scheda seleziona il compagno del primo allenatore")
	var chosen: Button = _button_with_text(starter_names[0])
	check(chosen != null and chosen.disabled, "Il primo starter resta visibile ma non può essere scelto di nuovo")
	if not await _click_by_text(starter_names[1]):
		return false
	check(String(app.screen) == "world" and app.model.state.players.size() == 2, "Due schede distinte avviano la campagna dalla UI")
	if app.model.state.players.size() != 2:
		return false
	check(String(app.model.player(0).name) == "Ada" and String(app.model.player(1).name) == "Bruno", "I nomi digitati sono assegnati ai giocatori corretti")
	check(int(app.model.player(0).party[0].species_id) == 1 and int(app.model.player(1).party[0].species_id) == 5 and int(app.model.state.rival_starter) == 9, "Le scelte dei tre starter distinguono i due giocatori e il rivale")
	check(int(app.model.state.actions_left) == 2 and app.session == null, "Il nuovo viaggio offre due azioni e nessuno scontro sospeso")
	return true


func _continue_from_button() -> bool:
	# Compare the complete JSON document, which is the persistence contract.
	# JSON parses numbers as floats: load_state retains that representation for
	# version/active_player/actions_left and restores other numeric fields as ints.
	# Serializing both trees preserves every key/value while normalizing numbers.
	var expected: Dictionary = JSON.parse_string(JSON.stringify(app.model.snapshot()))
	if not await _click_by_text("Titolo"):
		return false
	check(String(app.screen) == "title" and _button_with_text("Continua") != null, "Il titolo offre Continua dopo il primo salvataggio")
	# Clear only the in-memory fixture: the button must actually reload the file.
	app.model.state = {}
	if not await _click_by_text("Continua"):
		return false
	var actual: Dictionary = JSON.parse_string(JSON.stringify(app.model.snapshot()))
	check(String(app.screen) == "world" and actual == expected, "Continua ricostruisce l'intero documento salvato, inclusi giocatori, identità e turno")
	return not app.model.state.is_empty()


func _tools_and_management() -> bool:
	if not await _click_by_text("Partita"):
		return false
	check(String(app.screen) == "tools", "Il comando Partita apre gli strumenti dalla mappa")
	if not await _click_by_text("Impostazioni"):
		return false
	check(String(app.screen) == "settings", "La tessera Impostazioni richiama la pagina completa")
	await _audio_preserves_state("settings")
	if not await _click_by_text("Riprendi il Viaggio"):
		return false
	check(String(app.screen) == "world", "Il footer delle impostazioni torna alla mappa del viaggio")
	if not await _click_by_text("Partita"):
		return false
	if not await _click_by_text("Editor delle interazioni"):
		return false
	check(String(app.screen) == "interactions" and _button_with_text("Salva interazione") != null, "L'editor è raggiungibile da un pulsante e mostra il modulo reale")
	if not await _click_by_text("← Torna al diario"):
		return false
	check(String(app.screen) == "tools", "Il ritorno dell'editor riapre gli strumenti")
	if not await _click_by_text("Come si gioca"):
		return false
	check(String(app.screen) == "help", "La guida è raggiungibile dagli strumenti")
	if not await _click_by_text("Riprendi il Viaggio"):
		return false
	check(String(app.screen) == "world", "Il footer della guida ripristina la campagna")
	if not await _click_by_text("Partita"):
		return false
	if not await _click_by_text("Squadra"):
		return false
	check(String(app.screen) == "party", "La navigazione apre la squadra")
	var roster: Array[Button] = []
	for node: Node in app.page.find_children("*", "Button", true, false):
		var button: Button = node as Button
		if button.text.is_empty() and not button.find_children("*", "Label", true, false).is_empty():
			roster.append(button)
	check(roster.size() == 6, "La squadra mostra sei posti, compresi quelli liberi")
	var empty_slots: int = 0
	for button: Button in roster:
		if button.disabled:
			empty_slots += 1
	check(empty_slots == 5, "I cinque posti liberi non avviano azioni sul compagno")
	if not await _click_by_text("Deposito"):
		return false
	check(String(app.screen) == "box", "Deposito è raggiungibile dalla navigazione")
	var box_slots: int = 0
	for node: Node in app.page.find_children("*", "Button", true, false):
		var button: Button = node as Button
		if button.tooltip_text.begins_with("Posto "):
			box_slots += 1
			_check_inside_view(button, "Il posto del box %d resta nel viewport" % box_slots)
	check(box_slots == 35, "Il deposito conserva trentacinque posti distinti")
	if not await _click_by_text("Borsa"):
		return false
	check(String(app.screen) == "bag", "La borsa si apre dalla navigazione")
	var icons: int = 0
	for node: Node in app.page.find_children("*", "TextureRect", true, false):
		var art: TextureRect = node as TextureRect
		if art.texture != null and art.texture.resource_path.contains("/player-kit/") and (art.texture.resource_path.contains("/item-") or art.texture.resource_path.contains("/type-")):
			icons += 1
	check(icons >= 7, "Tutti gli articoli della borsa hanno un'icona caricata")
	for item: Dictionary in app.model.catalog:
		check(_button_with_text(String(item.name)) != null, "L'oggetto %s dispone di una scheda selezionabile" % item.name)
	if not await _click_by_text("Riprendi il viaggio"):
		return false
	check(String(app.screen) == "world", "Il footer della borsa conserva l'ambito della mappa")
	return true


func _travel_and_pvp() -> bool:
	if not await _click_by_text("Venezia"):
		return false
	check(String(app.model.player().location) == "Venezia" and int(app.model.state.actions_left) == 1, "Il nodo adiacente della mappa esegue il viaggio e spende un'azione")
	if not await _click_by_text("Entra in Venezia"):
		return false
	check(String(app.screen) == "location" and int(app.model.state.actions_left) == 1, "L'ingresso nel luogo è gratuito anche dalla nuova UI")
	if not await _click_by_text("Partita"):
		return false
	if not await _click_by_text("Riprendi il Viaggio"):
		return false
	check(String(app.screen) == "location" and String(app.model.player().location) == "Venezia", "Il footer degli strumenti conserva l'ambito del luogo quando aperto da una città")
	var current: String = String(app.model.player().local_node)
	var definition: Dictionary = app.model.local_maps.get("Venezia", {})
	var destination: String = ""
	for road: Dictionary in definition.get("roads", []):
		if String(road.get("from", "")) == current:
			destination = String(road.get("to", ""))
			break
		if String(road.get("to", "")) == current:
			destination = String(road.get("from", ""))
			break
	var marker_text: String = ""
	for point: Dictionary in definition.get("nodes", []):
		if String(point.get("id", "")) == destination:
			marker_text = String(point.get("label", destination)).replace("_", " ")
			break
	check(not destination.is_empty() and not marker_text.is_empty(), "La mappa locale presenta un punto collegato alla partenza")
	if marker_text.is_empty() or not await _click_by_text(marker_text):
		return false
	check(String(app.model.player().local_node) == destination and int(app.model.state.actions_left) == 0, "Il pulsante del punto locale chiama il movimento e rispetta il budget")
	if not await _click_by_text("Attività del luogo"):
		return false
	check(_button_with_text("Centro cure") != null and _button_with_text("Arkastore") != null, "La finestra attività offre i servizi reali del luogo")
	check(_button_with_text("Sfida Bruno") == null, "Il luogo non propone PvP contro un giocatore altrove")
	if not await _click_by_text("Chiudi  ×"):
		return false
	check(_button_with_text("Centro cure") == null, "Chiudi rimuove la finestra attività")
	if not await _click_by_text("Passa il turno"):
		return false
	check(String(app.screen) == "world" and int(app.model.state.active_player) == 1, "Passa turno consegna i comandi al secondo allenatore")
	if not await _click_by_text("Venezia"):
		return false
	if not await _click_by_text("Entra in Venezia"):
		return false
	if not await _click_by_text("Attività del luogo"):
		return false
	if not await _click_by_text("Sfida Ada"):
		return false
	check(String(app.screen) == "battle" and app.session != null, "Il pulsante PvP delle attività apre uno scontro")
	if app.session == null:
		return false
	check(String(app.session.kind) == "pvp" and String(app.model.state.pending.kind) == "pvp", "La battaglia aperta dal pulsante è registrata come PvP locale")
	check(int(app.session.active_creature("player").species_id) == 5 and int(app.session.active_creature("enemy").species_id) == 1, "Il secondo allenatore e il primo rivale conservano le squadre corrette")
	return true


func _audio_preserves_state(expected_screen: String) -> void:
	var state_before: Dictionary = app.model.snapshot()
	var session_before: BattleSession = app.session
	var battle_before: Dictionary = session_before.snapshot() if session_before != null else {}
	var audio_before: bool = bool(app.sound_enabled)
	for index: int in range(2):
		var text: String = ("Attivo" if app.sound_enabled else "Disattivato") if expected_screen == "settings" else ("Audio ON" if app.sound_enabled else "Audio OFF")
		if not await _click_by_text(text):
			return
		check(bool(app.sound_enabled) != audio_before if index == 0 else bool(app.sound_enabled) == audio_before, "Audio %s cambia lo stato al click %d" % [expected_screen, index + 1])
		check(String(app.screen) == expected_screen, "Audio %s conserva la pagina" % expected_screen)
		check(app.model.snapshot() == state_before, "Audio %s non altera campagna, HP o turno" % expected_screen)
		check(app.session == session_before, "Audio %s conserva l'istanza di battaglia" % expected_screen)
		if session_before != null:
			check(app.session.snapshot() == battle_before, "Audio in battaglia conserva round, HP, squadre e RNG")
		check(String(app.save_path) == TEST_SAVE, "Audio %s mantiene il salvataggio isolato" % expected_screen)


func _check_battle_geometry() -> void:
	var arena_rect: Rect2 = app.arena.get_global_rect()
	check(arena_rect.size.is_equal_approx(VIEW_SIZE), "L'arena occupa l'intero palco 1440×810")
	_check_inside_view(app.player_actor, "Lo sprite del giocatore resta nel palco")
	_check_inside_view(app.enemy_actor, "Lo sprite avversario resta nel palco")
	_check_inside_view(app.player_hp, "Gli HP del giocatore restano nel palco")
	_check_inside_view(app.enemy_hp, "Gli HP avversari restano nel palco")
	_check_inside_view(app.player_health, "Il contatore HP del giocatore resta visibile")
	_check_inside_view(app.enemy_health, "Il contatore HP avversario resta visibile")
	var player_rect: Rect2 = app.player_hp.get_global_rect()
	var enemy_rect: Rect2 = app.enemy_hp.get_global_rect()
	check(not player_rect.intersects(enemy_rect) and player_rect.position.y > enemy_rect.end.y, "Le barre HP occupano i lati opposti senza sovrapporsi")
	var visible_actions: int = 0
	for candidate: Variant in app.action_buttons:
		if not is_instance_valid(candidate) or not candidate.is_visible_in_tree():
			continue
		var button: Button = candidate as Button
		visible_actions += 1
		_check_inside_view(button, "Il comando di battaglia %d è dentro il viewport" % visible_actions)
		var bounds: Rect2 = button.get_global_rect()
		check(bounds.size.x >= 35 and bounds.size.y >= 30, "Il comando di battaglia %d ha una superficie utilizzabile" % visible_actions)
		check(not bounds.intersects(player_rect) and not bounds.intersects(enemy_rect), "Il comando di battaglia %d non copre gli HP" % visible_actions)
	check(visible_actions >= 5, "L'arena espone mosse e comandi di gestione")
	check(_button_with_text("Cattura") == null, "La UI PvP non propone la cattura dell'avversario")
	var bag: Button = _button_with_text("Borsa")
	check(bag != null and bag.disabled, "Gli oggetti non sono selezionabili nel PvP locale")


func _click_by_text(text: String, scope: Node = null) -> bool:
	var button: Button = _button_with_text(text, scope)
	check(button != null, "Il pulsante '%s' esiste nella pagina corrente" % text)
	if button == null:
		return false
	var ancestor: Node = button.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			(ancestor as ScrollContainer).ensure_control_visible(button)
		ancestor = ancestor.get_parent()
	await _frames()
	check(is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled, "Il pulsante '%s' è visibile e abilitato prima del click" % text)
	if not is_instance_valid(button) or not button.is_visible_in_tree() or button.disabled:
		return false
	button.pressed.emit()
	await _frames()
	return true


func _button_with_text(text: String, scope: Node = null) -> Button:
	var container: Node = app if scope == null else scope
	var expected: String = text.strip_edges().to_lower()
	for node: Node in container.find_children("*", "Button", true, false):
		var button: Button = node as Button
		if button.is_queued_for_deletion() or not button.is_visible_in_tree():
			continue
		if button.text.strip_edges().to_lower() == expected or button.tooltip_text.strip_edges().to_lower() == expected:
			return button
		if button.text.is_empty():
			for child: Node in button.find_children("*", "Label", true, false):
				if String((child as Label).text).strip_edges().to_lower() == expected:
					return button
	return null


func _check_inside_view(control: Control, description: String) -> void:
	var bounds: Rect2 = control.get_global_rect()
	check(control.is_visible_in_tree() and bounds.size.x > 0 and bounds.size.y > 0 and Rect2(Vector2(-1, -1), VIEW_SIZE + Vector2(2, 2)).encloses(bounds), description)


func _frames() -> void:
	await process_frame
	await process_frame
	await process_frame


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("Site UI: " + description)


func _protected_fingerprints() -> Dictionary:
	var result: Dictionary = {}
	for path: String in PROTECTED_PATHS:
		result[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
	return result


func _cleanup() -> void:
	for path: String in [TEST_SAVE, TEST_SAVE + ".bak", TEST_SAVE + ".tmp", TEST_PREFS]:
		if path.begins_with("user://test-site-ui/") and FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _timeout() -> void:
	if finished:
		return
	finished = true
	push_error("Site UI: timeout globale di sessanta secondi.")
	_cleanup()
	quit(1)


func _finish() -> void:
	finished = true
	if is_instance_valid(app):
		app.queue_free()
		await process_frame
	check(_protected_fingerprints() == protected_before, "I salvataggi e le preferenze reali conservano le impronte originali")
	_cleanup()
	print("Site UI Arkamon: %d verifiche, %d errori." % [checks, failures])
	quit(0 if failures == 0 else 1)

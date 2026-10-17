class_name InteractionEditor
extends VBoxContainer

signal back_requested
signal saved(result: Dictionary)
var model: CampaignModel
var location: OptionButton
var point: OptionButton
var action: OptionButton
var dialogue: TextEdit
var coins: SpinBox
var item: OptionButton
var quantity: SpinBox
var badges: SpinBox
var once: CheckButton
var shared: CheckButton
var trainer: OptionButton
var prerequisite: LineEdit
var message: Label
const ACTION_NAMES := ["Dialogo", "Ricompensa", "Cura", "Incontro selvatico", "Allenatore", "Negozio"]

func setup(value: CampaignModel) -> void:
	model = value

func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(ArkUI.label("Editor delle interazioni", 30, ArkUI.GOLD))
	add_child(ArkUI.paragraph("Assegna dialoghi e attività ai punti delle mappe locali. Le modifiche sono salvate con la campagna.", 19))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var form := ArkUI.vbox(8)
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(form)
	location = OptionButton.new()
	for id: String in model.local_maps: location.add_item(id.replace("_", " ")); location.set_item_metadata(location.item_count - 1, id)
	form.add_child(ArkUI.label("Mappa e punto", 18))
	form.add_child(location)
	point = OptionButton.new()
	form.add_child(point)
	action = OptionButton.new()
	for name_value: String in ACTION_NAMES: action.add_item(name_value)
	form.add_child(ArkUI.label("Attività", 18))
	form.add_child(action)
	dialogue = TextEdit.new()
	dialogue.custom_minimum_size.y = 110
	dialogue.placeholder_text = "Dialogo o descrizione dell'interazione"
	form.add_child(dialogue)
	var numbers := ArkUI.hbox()
	form.add_child(numbers)
	coins = _number(numbers, "Monete premio", 99999)
	quantity = _number(numbers, "Quantità oggetto", 99999)
	badges = _number(numbers, "Medaglie richieste", 8)
	item = OptionButton.new()
	item.add_item("Nessun oggetto")
	item.set_item_metadata(0, "")
	for definition: Dictionary in model.catalog:
		item.add_item(String(definition.name)); item.set_item_metadata(item.item_count - 1, String(definition.id))
	form.add_child(item)
	trainer = OptionButton.new()
	form.add_child(ArkUI.label("Allenatore del luogo (per una sfida)", 18))
	form.add_child(trainer)
	once = CheckButton.new()
	once.text = "Completamento una sola volta"
	form.add_child(once)
	shared = CheckButton.new()
	shared.text = "Completamento condiviso dai due giocatori"
	form.add_child(shared)
	prerequisite = LineEdit.new()
	prerequisite.placeholder_text = "Tappa precedente facoltativa: Mappa:id_punto"
	form.add_child(prerequisite)
	message = ArkUI.label("", 18, ArkUI.MINT)
	add_child(message)
	add_child(ArkUI.button("Salva interazione", _save_entry, true))
	add_child(ArkUI.button("← Torna al diario", func() -> void: back_requested.emit()))
	location.item_selected.connect(func(_index: int) -> void: _update_points())
	point.item_selected.connect(func(_index: int) -> void: _load_entry())
	_update_points()

func _number(parent: Control, title: String, maximum: int) -> SpinBox:
	var column := ArkUI.vbox(4)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	column.add_child(ArkUI.label(title, 16))
	var spinner := SpinBox.new()
	spinner.max_value = maximum
	column.add_child(spinner)
	return spinner

func _update_points() -> void:
	point.clear()
	trainer.clear()
	var id := String(location.get_selected_metadata())
	for entry: Dictionary in model.local_maps[id].nodes:
		point.add_item(String(entry.get("label", entry.id)) + " · " + String(entry.id))
		point.set_item_metadata(point.item_count - 1, entry.id)
	for entry: Dictionary in model.trainers:
		if String(entry.luogo) == id: trainer.add_item(String(entry.nome), int(entry.id))
	_load_entry()

func _load_entry() -> void:
	var key_value := InteractionRules.key(String(location.get_selected_metadata()), String(point.get_selected_metadata()))
	var entry: Dictionary = model.state.get("interactions", {}).get(key_value, {})
	action.select(maxi(0, InteractionRules.TYPES.find(String(entry.get("type", "dialogue")))))
	dialogue.text = String(entry.get("text", ""))
	coins.value = int(entry.get("coins", 0))
	quantity.value = int(entry.get("quantity", 0))
	badges.value = int(entry.get("min_badges", 0))
	once.button_pressed = bool(entry.get("once", false))
	shared.button_pressed = bool(entry.get("shared", false))
	prerequisite.text = String(entry.get("prerequisite", ""))
	item.select(0)
	for index in item.item_count:
		if String(item.get_item_metadata(index)) == String(entry.get("item_id", "")): item.select(index)
	for index in trainer.item_count:
		if trainer.get_item_id(index) == int(entry.get("trainer_id", 0)): trainer.select(index)

func _save_entry() -> void:
	var entry := {"location": String(location.get_selected_metadata()), "node_id": String(point.get_selected_metadata()), "type": InteractionRules.TYPES[action.selected], "text": dialogue.text,
		"coins": int(coins.value), "quantity": int(quantity.value), "min_badges": int(badges.value), "item_id": String(item.get_selected_metadata()),
		"once": once.button_pressed, "shared": shared.button_pressed, "prerequisite": prerequisite.text.strip_edges(), "trainer_id": trainer.get_selected_id(), "bush": "A"}
	var result := InteractionRules.configure(entry, model)
	message.text = String(result.message)
	message.add_theme_color_override("font_color", ArkUI.MINT if bool(result.ok) else ArkUI.RED)
	saved.emit(result)

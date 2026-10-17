class_name SaveStore
extends RefCounted
## Portable, versioned JSON saves. Only JSON data is accepted; no objects execute.

const VERSION: int = 1
const DEFAULT_PATH: String = "user://campaign.json"
const MAX_BYTES: int = 2 * 1024 * 1024
const MAX_DEPTH: int = 20


static func save_game(state: Dictionary, path: String = DEFAULT_PATH) -> Error:
	if not _valid_path(path) or state.is_empty() or not _valid_value(state, 0):
		return ERR_INVALID_DATA
	var envelope: Dictionary = {"version": VERSION, "saved_at": int(Time.get_unix_time_from_system()), "state": state}
	var text: String = JSON.stringify(envelope, "\t")
	if text.to_utf8_buffer().size() > MAX_BYTES:
		return ERR_INVALID_DATA
	var absolute: String = ProjectSettings.globalize_path(path)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if directory_error != OK:
		return directory_error
	var temporary: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		return write_error
	if _read_state(temporary).is_empty():
		return ERR_FILE_CORRUPT
	# Keep the last valid campaign, even when the primary file was damaged.
	var backup_source: String = path if not _read_state(path).is_empty() else temporary
	if backup_source == path or _read_state(path + ".bak").is_empty():
		var copy_error: Error = DirAccess.copy_absolute(ProjectSettings.globalize_path(backup_source), absolute + ".bak")
		if copy_error != OK:
			return copy_error
	if FileAccess.file_exists(path):
		var remove_error: Error = DirAccess.remove_absolute(absolute)
		if remove_error != OK:
			return remove_error
	var rename_error: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), absolute)
	if rename_error != OK:
		# The verified backup remains readable if replacement fails.
		return rename_error
	return OK


static func load_game(path: String = DEFAULT_PATH) -> Dictionary:
	if not _valid_path(path):
		return {}
	for candidate: String in [path, path + ".bak", path + ".tmp"]:
		var state: Dictionary = _read_state(candidate)
		if not state.is_empty():
			return state
	return {}


static func has_save(path: String = DEFAULT_PATH) -> bool:
	return not load_game(path).is_empty()


static func _read_state(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		return {}
	var parser: JSON = JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {}
	var envelope: Dictionary = parser.data
	if typeof(envelope.get("version")) not in [TYPE_INT, TYPE_FLOAT] or float(envelope["version"]) != float(VERSION):
		return {}
	var raw_state: Variant = envelope.get("state")
	if not raw_state is Dictionary or raw_state.is_empty() or not _valid_value(raw_state, 0):
		return {}
	return raw_state.duplicate(true)


static func _valid_path(path: String) -> bool:
	return path.begins_with("user://") and path.length() <= 512 and not ".." in path and not path.ends_with("/")


static func _valid_value(value: Variant, depth: int) -> bool:
	if depth > MAX_DEPTH:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL:
			return true
		TYPE_INT:
			return true
		TYPE_FLOAT:
			return is_finite(float(value))
		TYPE_STRING:
			return str(value).length() <= 4096
		TYPE_ARRAY:
			var list: Array = value
			if list.size() > 512:
				return false
			for entry: Variant in list:
				if not _valid_value(entry, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			var record: Dictionary = value
			if record.size() > 512 or not _valid_record(record):
				return false
			for key: Variant in record:
				if not key is String or str(key).length() > 256 or not _valid_value(record[key], depth + 1):
					return false
			return true
	return false


static func _valid_record(record: Dictionary) -> bool:
	if record.has("species_id"):
		for key: String in ["species_id", "level", "hp", "max_hp"]:
			if not _whole_number(record.get(key)):
				return false
		if int(record["species_id"]) < 1 or int(record["species_id"]) > 10000:
			return false
		if int(record["level"]) < 5 or int(record["level"]) > 100:
			return false
		if int(record["max_hp"]) < 1 or int(record["max_hp"]) > 100000:
			return false
		if int(record["hp"]) < 0 or int(record["hp"]) > int(record["max_hp"]):
			return false
	for key: String in ["party", "team", "squadra"]:
		if record.has(key) and (not record[key] is Array or record[key].size() > 6):
			return false
	for key: String in ["box", "storage", "deposito"]:
		if record.has(key) and (not record[key] is Array or record[key].size() > 200):
			return false
	for key: String in ["money", "coins", "potions", "capture_balls", "orbs", "captures", "wins", "losses"]:
		if record.has(key) and (not _whole_number(record[key]) or int(record[key]) < 0 or int(record[key]) > 100000000):
			return false
	return true


static func _whole_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floor(float(value))

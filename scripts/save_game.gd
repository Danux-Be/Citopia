class_name SaveGame
extends RefCounted

## Save slots under user://saves/. A save is JSON: metadata + the full map
## state (see IsoMap.to_dict / restore_from).

const DIR := "user://saves"


static func save(slot: String, iso_map: IsoMap, meta: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	var data := {
		"version": 1,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"map": iso_map.to_dict(),
	}
	data.merge(meta, true)
	var file := FileAccess.open(DIR + "/" + slot + ".json", FileAccess.WRITE)
	if file == null:
		push_warning("cannot write save %s" % slot)
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true


static func load_data(slot: String) -> Dictionary:
	var file := FileAccess.open(DIR + "/" + slot + ".json", FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


static func exists(slot: String) -> bool:
	return FileAccess.file_exists(DIR + "/" + slot + ".json")


static func remove(slot: String) -> void:
	if exists(slot):
		DirAccess.remove_absolute(DIR + "/" + slot + ".json")


## Slots with their metadata, newest first.
static func list_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	DirAccess.make_dir_recursive_absolute(DIR)
	for file in DirAccess.get_files_at(DIR):
		if not file.ends_with(".json"):
			continue
		var slot := file.trim_suffix(".json")
		var data := load_data(slot)
		out.append({
			"slot": slot,
			"saved_at": str(data.get("saved_at", "?")),
			"pop": int(data.get("pop", 0)),
			"day": int(float(data.get("day", 0.0))),
		})
	out.sort_custom(func(a, b): return a.saved_at > b.saved_at)
	return out

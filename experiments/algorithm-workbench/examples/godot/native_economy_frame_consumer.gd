extends Node
## Display bridge only. Original WorldState remains the sole economy owner.
signal personal_observed(personal: Dictionary, minute: int)
signal record_changed(observation: Dictionary)
var last_revision: int = -1
var seen: Dictionary = {}

func reset_replay() -> void:
	last_revision = -1
	seen.clear()

func consume(frame: Dictionary) -> bool:
	if frame.get("schemaVersion") != "wwo-native-economy/frame/v1": return false
	var revision := int(frame.get("revision", -1))
	if revision < last_revision or not frame.get("personal") is Dictionary: return false
	personal_observed.emit(frame["personal"].duplicate(true), int(frame["minute"]))
	for observation: Dictionary in frame.get("changes", []):
		if not seen.has(observation["id"]):
			seen[observation["id"]] = true
			record_changed.emit(observation.duplicate(true))
	last_revision = revision
	return true

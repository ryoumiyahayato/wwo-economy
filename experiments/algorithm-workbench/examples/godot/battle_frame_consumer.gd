extends Node3D
## Minimal display consumer, Godot 4. No simulation, damage or command authority.
## Map your EXISTING display nodes by the exact source entity ID. Units are km;
## Godot map below uses metres on XZ, positive source y -> negative Godot Z.
signal source_event(record: Dictionary)
signal frame_committed(tick: int)
@export var frame_path: String = ""
var display_nodes: Dictionary = {}
var last_tick: int = -1
var seen: Dictionary = {}

func reset_replay() -> void:
	last_tick = -1
	seen.clear()

func consume(frame: Dictionary) -> bool:
	if frame.get("schemaVersion") != "wwo-battle/frame/v1" or frame.get("view") != "DEBUG_TRUTH":
		return false
	if int(frame.get("tick", -1)) < last_tick:
		return false # Call reset_replay before a backward seek or a new run.
	for entity: Dictionary in frame.get("entities", []):
		if display_nodes.has(entity.id):
			display_nodes[entity.id].position = Vector3(float(entity.x) * 1000.0, 0.0, -float(entity.y) * 1000.0)
	for event: Dictionary in frame.get("events", []):
		if not seen.has(event.id):
			seen[event.id] = true
			source_event.emit(event.duplicate(true))
	last_tick = int(frame.tick)
	frame_committed.emit(last_tick)
	return true

func _ready() -> void:
	if frame_path.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(frame_path))
	if parsed is Dictionary:
		consume(parsed)

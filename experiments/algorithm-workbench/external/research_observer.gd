extends SceneTree
## Sandbox-owned transport/observation only. Original Session owns all decisions,
## clocks, movement, fire and damage. Never feed DEBUG_TRUTH into player Context.
const Session = preload("res://experiments/war_resolver/attachment_continuity/session.gd")
var session = Session.new()

func research(after: String) -> Dictionary:
	if session.world.env.state.public_pending():
		return {"pending": true}
	var env: Dictionary = session.world.env
	var units: Dictionary = {}
	for id: String in env.state.units:
		var unit: Dictionary = env.state.units[id]
		units[id] = {"raw": unit.duplicate(true), "xy": env.space.xy(unit)}
	var people: Dictionary = {}
	for id: String in env.gameplay.participants._units:
		people[id] = env.gameplay.participants.view(id)
	var observation = session.world.observation
	# Resume by native event identity: observation.dropped counts both buffers,
	# so it must not be mistaken for a debug-only array offset.
	var start: int = 0
	var found: bool = after.is_empty()
	if not after.is_empty():
		for index: int in range(observation.debug_records.size() - 1, -1, -1):
			if str(observation.debug_records[index].event_id) == after:
				start = index + 1
				found = true
				break
	var stop: int = mini(start + 128, observation.debug_records.size())
	var page: Array = observation.debug_records.slice(start, stop).duplicate(true)
	var cursor: String = str(page[-1].event_id) if not page.is_empty() else after
	page.sort_custom(observation.before)
	var event_page: Dictionary = {"records": page, "dropped": observation.dropped, "cursor": cursor, "more": stop < observation.debug_records.size(), "cursor_lost": not found}
	return {"schemaVersion": "wwo-battle/source/v1", "view": "DEBUG_TRUTH", "time": env.state.time,
		"units": units, "people": people, "events": event_page,
		"nodes": env.space._nodes.duplicate(true), "totals": env.state.totals.duplicate(true),
		"randomState": env.state.random_state.duplicate(true),
		"scope": "original materialized units and named bodies; sparse groups not expanded"}

func _initialize() -> void:
	var options: Dictionary = JSON.parse_string(OS.get_cmdline_user_args()[0])
	if not session.configure("A3", int(options.seed), "squad", "sandbox_session", int(options.quota), {"diagnostic": true}):
		quit(2)
		return
	# Existing diagnostic switches add records only. Equivalence is tested against
	# the uninstrumented original server, including physical state and RNG.
	session.world.env.gameplay.participants.debug_calculations = true
	session.world.env.lod.physical_event_sink = session.world.observation.physical
	print("PERSON_BOUND=" + JSON.stringify({"ok": true, "started": true, "program": session._program()}))
	while not session.closed:
		var frame: PackedByteArray = OS.read_buffer_from_stdin(Session.FRAME)
		if frame.is_empty():
			break
		var parser = JSON.new()
		var response: Dictionary = {"ok": false, "error": "invalid_frame"}
		if frame.size() == Session.FRAME and parser.parse(frame.get_string_from_utf8().strip_edges()) == OK and parser.data is Dictionary:
			var packet: Dictionary = parser.data
			# Preserve original sequence validation. Research is an explicit read-only
			# extension of look; its payload never enters Session.request or decisions.
			var observing: bool = packet.get("op") == "research" and packet.get("args") is Dictionary and packet.args.size() == 1 and packet.args.get("after") is String and packet.args.after.length() <= 256
			var after: String = str(packet.args.after) if observing else ""
			if observing:
				packet.op = "look"
				packet.args = {}
			response = session.handle(packet)
			if observing and response.get("ok", false):
				response.research = research(after)
		print("PERSON_BOUND=" + JSON.stringify(response))
	session.dispose()
	quit(0)

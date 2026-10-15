extends SceneTree
## Transport only. All state, permission checks and settlement remain in WWO.
var built: WorldBuildResult
var request_minutes: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _integers(value: Variant) -> Variant:
	if value is float and value == floor(value): return int(value)
	if value is Dictionary:
		for key: Variant in value: value[key] = _integers(value[key])
	elif value is Array:
		for i in value.size(): value[i] = _integers(value[i])
	return value

func _snapshot() -> Dictionary:
	var w := built.world
	var person := w.player_state.player_id()
	var personal := LivelihoodAction.query(w, person)
	var consumption: Dictionary = {}
	for good: String in personal.get("inventory", {}):
		if int(personal["inventory"][good]) > 0:
			consumption[good] = w.economy_r1.personal_consumption_quote(person, "native:"+good, 1)
	return {"minute": w.game_clock.total_minutes(), "playerId": person,
		"personal": personal, "native": w.economy_r1.snapshot(), "destinations": w.person_travel.destinations(person), "consumptionQuotes": consumption,
		"ledger": w.ledger_state.snapshot(), "living": w.personal_economy_state.living_records(person, 100)}

func _run() -> void:
	var setup: Dictionary = JSON.parse_string(OS.get_cmdline_user_args()[0])
	var configuration := EconomyDevelopmentConfig.formal_liquidity_request() if setup.get("configuration") == "EconomyDevelopmentConfig.formal_liquidity_request" else EconomyDevelopmentConfig.formal_limited()
	built = WorldBootstrap.new().build(null, [], [], FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT, true, configuration)
	if not built.success or built.world.economy_r1 == null:
		print("WWO_NATIVE ", JSON.stringify({"error": built.error + " " + built.world.native_economy_error}))
		quit(1)
		return
	print("WWO_NATIVE ", JSON.stringify({"state": _snapshot()}))
	while true:
		var line := OS.read_string_from_stdin()
		if line.is_empty(): break
		var request: Variant = _integers(JSON.parse_string(line))
		if not request is Dictionary: break
		if request.get("op") == "close": break
		var result: Dictionary = {}
		match request.get("op"):
			"step": result = built.simulation_step.advance_minutes(int(request.get("minutes", 720)))
			"command":
				var c: Dictionary = request.get("request", {})
				var p: Dictionary = c.get("parameters", {})
				if c.get("op") != "livelihood" or p.get("kind") not in ["apply", "work", "travel", "buy", "consume", "collect"]:
					result = {"accepted": false, "reason": "UNSUPPORTED_SANDBOX_ACTION"}
				else:
					var id: String = c.get("id", "")
					if not request_minutes.has(id): request_minutes[id] = built.world.game_clock.total_minutes()
					result = LivelihoodAction.execute(built.world, built.world.player_state.player_id(), {"action_id": id, "minute": request_minutes[id], "kind": p.get("kind"), "payload": p.get("payload", {})})
			_:
				print("WWO_NATIVE ", JSON.stringify({"error": "UNKNOWN_OPERATION"}))
				continue
		if result.get("success", true) == false:
			print("WWO_NATIVE ", JSON.stringify({"error": str(result)}))
		else:
			print("WWO_NATIVE ", JSON.stringify({"state": _snapshot(), "result": result}))
	quit()

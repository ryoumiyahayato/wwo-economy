extends "res://merchant/qa_household_timing.gd"
## Current dot pre-risk-policy versus future candidate, not Comparison A.
## Original capacity-manager commands cause/release a real transport blockage.
## Old goods remain reserved and eventually deliver/pay. Observe effective
## consumption, later stock and finite extra spending, not order count alone.
var failed: bool = false
var report: Dictionary = {}
var output: String = ""

func save() -> void:
	var f := FileAccess.open(output, FileAccess.WRITE)
	if f == null: push_error("Cannot write absolute unknown-arrival QA output"); quit(2); return
	f.store_string(JSON.stringify(report, "\t")); f.close()

func require(ok: bool, label: String, detail: Variant = {}) -> bool:
	if ok: return true
	failed = true
	report["status"] = label
	report["failure_detail"] = detail
	save(); print("QA_UNKNOWN_ARRIVAL ", label); quit(1)
	return false

func capacity(e: EconomyR1Slice, amount: int, id: String) -> Dictionary:
	var command: Dictionary = e._auto_command(SELLER, "set_edge_capacity", {"edge_id": SLOW, "capacity": amount}, id)
	return {"command": command, "result": e.submit_internal(SELLER, command)}

func own_local(e: EconomyR1Slice) -> Array:
	var rows: Array = []
	for o: Dictionary in e._orders.values():
		if o["buyer"] == ACTOR and o["seller_site"] == LOCAL and o["good"] == "bread": rows.append(o.duplicate(true))
	return rows

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or not args[0].is_absolute_path() or args[1] not in ["baseline", "candidate"]:
		push_error("Usage: -- /absolute/report.json baseline|candidate"); quit(2); return
	output = args[0]
	var baseline: bool = args[1] == "baseline"
	var cfg: Dictionary = configuration("TIMELY_LOCAL")
	cfg["case_id"] = "QA_UNKNOWN_ARRIVAL_REAL_CLOSURE_THEN_REOPEN"
	var original_capacity: int = 0
	for firm: Dictionary in cfg["firms"]:
		for site: Dictionary in firm["sites"]:
			if site["id"] == LOCAL: site["stock"]["bread"] = 20
	for route: Dictionary in cfg["routes"]:
		if route["id"] == SLOW:
			route["capacity_manager"] = SELLER
			original_capacity = route["capacity"]
	report = {"origin": "dot", "mode": args[1], "status": "RUNNING_NOT_VERIFIED", "initial_configuration": cfg, "rows": [], "bounded_policy_under_test": "If an original known closure leaves no ETA, allow at most one extra daily meal2 while retaining old4 liability. Do not repeat a new emergency amount every day of the same unresolved episode. Reopening is new actual route progress and permits a different known-late decision.", "limits": ["LEGAL_CONFIGURATION_VARIANT_NOT_NATURAL_PRODUCT_SAVE", "REAL_ORIGINAL_CAPACITY_MANAGER_ACTIONS", "NO_SOURCE_OR_SIGNED_ORDER_EDIT_AFTER_BOOTSTRAP", "14_DAYS_NOT_INFINITE_STABILITY", "NO_SUPPLIER_FAULT_INFERRED_FROM_CARRIER_BLOCK", "PARENT_CONTRACT_DEADLINE_IS_NOT_TESTED_HERE"]}
	save()
	if not require(EconomySliceConfig.valid(cfg), "INVALID_INITIAL_CONFIGURATION"): return
	var b: WorldBuildResult = WorldBootstrap.new().build(null, [], [], FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT, true, {"format": "HOST_REGION_SELECTION", "person_ids": [], "select_people_at_sites": false, "configuration": cfg})
	if not require(b.success, "BOOTSTRAP_FAILED", b.error): return
	if not require(b.simulation_step.advance_minutes(1).get("success", true), "CLOCK_FAILED"): return
	var e: EconomyR1Slice = b.world.economy_r1
	var offer: Dictionary = e._offer(ACTOR, SELLER, "bread", SLOW, REMOTE)
	var payload := {"quote_id": offer["quote_id"], "seller": SELLER, "seller_site": REMOTE, "good": "bread", "quantity": 4, "denomination": offer["denomination"], "max_price": 8, "path_id": SLOW, "purpose": "HOLDING", "need_by_day": 7}
	var old_command: Dictionary = e._auto_command(ACTOR, "buy", payload, "QA_ORIGINAL_FAR_HOLDING")
	var accepted: Dictionary = e.submit_internal(ACTOR, old_command)
	if not require(accepted.get("accepted", false) and accepted.get("quantity") == 4, "ORIGINAL_ORDER_NOT_ACCEPTED", accepted): return
	var old_id: String = accepted["order_id"]
	var old_terms: Dictionary = e._orders[old_id].duplicate(true)
	var closed: Dictionary = capacity(e, 0, "QA_REAL_ROUTE_CLOSURE")
	if not require(closed["result"].get("accepted", false), "ORIGINAL_CAPACITY_AUTHORITY_REFUSED", closed): return
	report["original_order"] = old_terms
	report["closure"] = closed
	var closed_local_total: int = 0
	var closed_consumption: int = 0
	for date: int in range(1, 15):
		if not require(b.simulation_step.advance_minutes(date * 1440 - b.world.game_clock.total_minutes()).get("success", true), "CLOCK_OR_DOMAIN_FAILED"): return
		var local: Array = own_local(e)
		var incoming: Dictionary = e._input_incoming_observation(ACTOR, "bread", date + 1)
		report["rows"].append({"day": date, "minute": b.world.game_clock.total_minutes(), "incoming": incoming, "position": e._household_position(ACTOR, true), "need": e._needs[ACTOR].duplicate(true), "stock": e._stocks[ACTOR].duplicate(true), "local_orders": local, "old_order": e._orders[old_id].duplicate(true), "cash_available": b.world.ledger_state.available_balance(e._account(ACTOR)), "cash_reserved": b.world.ledger_state.reserved_balance(e._account(ACTOR))})
		if date <= 6: closed_consumption += int(e._needs[ACTOR]["categories"]["food"]["satisfied"])
		if date == 6:
			for o: Dictionary in local: closed_local_total += int(o["quantity"])
			if not require(incoming["unknown_arrival"] >= 4 and e._orders[old_id]["pending"] == 4 and e._orders[old_id]["delivered"] == 0, "KNOWN_BLOCK_NOT_RETAINED_AS_UNKNOWN_OPEN_RESPONSIBILITY", incoming): return
			var reopened: Dictionary = capacity(e, original_capacity, "QA_REAL_ROUTE_REOPEN")
			if not require(reopened["result"].get("accepted", false), "ORIGINAL_REOPEN_REFUSED", reopened): return
			report["reopen"] = reopened
	var old_final: Dictionary = e._orders[old_id]
	for key: String in old_terms:
		if key in ["pending", "transit", "delivered", "cancelled"]: continue
		if not require(old_final[key] == old_terms[key], "OLD_SIGNED_TERMS_CHANGED", key): return
	if not require(old_final["delivered"] == 4 and old_final["cancelled"] == 0, "OLD_RESPONSIBILITY_NOT_FULFILLED", old_final): return
	var payments: Array = []
	var goods_paid: int = 0
	var freight_paid: int = 0
	for tx: Dictionary in b.world.ledger_state.transactions():
		if tx["reference_id"] != old_id: continue
		payments.append(tx.duplicate(true))
		if tx["kind"] == "goods": goods_paid += int(tx["amount"])
		elif tx["kind"] == "freight": freight_paid += int(tx["amount"])
	if not require(goods_paid == 32 and freight_paid == 4, "OLD_PAYMENT_NOT_EXACTLY_ONCE", payments): return
	report["closed_episode_local_quantity"] = closed_local_total
	report["closed_episode_effective_food"] = closed_consumption
	report["old_payments"] = payments
	if baseline:
		if not require(closed_local_total == 0 and closed_consumption == 0, "EXPECTED_CURRENT_UNKNOWN_WAIT_BOUNDARY_NOT_REPRODUCED"): return
		report["status"] = "BASELINE_REPRODUCED_SIX_DAY_UNKNOWN_WAIT_WITH_REAL_LOCAL_ALTERNATIVE"
	else:
		if not require(closed_local_total == 2 and closed_consumption == 2, "BOUNDED_EXTRA_MEAL_OR_NO_REPEAT_POLICY_NOT_ADOPTED"): return
		report["status"] = "CANDIDATE_FINITE_UNKNOWN_RISK_MEAL_AND_OLD_DELIVERY_VERIFIED"
	save(); print("QA_UNKNOWN_ARRIVAL ", report["status"]); quit()

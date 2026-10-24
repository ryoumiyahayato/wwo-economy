extends SceneTree
## One native world, one noon flow arrangement, original commands and clock only.
## This is a baseline audit plus an explicit manual future-replenishment witness.
## No successful result is claimed until this script actually reaches its final label.
const PERSON := WorldBootstrap.DEFAULT_FORMAL_PERSON_ID
const ITEM := "native:bread"
const SELLER := "firm:development_workshop"
const LOCAL := "site:development_workshop:paris"
const REMOTE := "site:development_workshop:lyon"
const SLOW := "edge:development_lyon_paris"
const FIRST_DUE := 2160
const SECOND_DUE := 3600
const LOCAL_ARRIVAL := 4320
const THIRD_DUE := 5040
var output_path: String = ""
var started_usec: int = 0
var report: Dictionary = {"case": "PERSONAL_NOON_FLOW2_LATE4", "status": "NOT_RUN", "records": [], "limits": ["EXPLICIT_LEGAL_NEW_WORLD_VARIANT_NOT_PLAYER_SAVE", "ONE_FLOW_COMMODITY_ONLY", "NATIVE_INTEGER_GOODS_QUANTITY_SCALE_1_NOT_MILLI_OR_SERVICE_BALANCE", "MANUAL_WITNESS_DOES_NOT_CLAIM_AUTOMATIC_FIX", "BASELINE_REPRODUCTION_REQUIRES_FINAL_SUCCESS_LABEL", "NO_RESTORE_OR_LONG_RUN_CLAIM"]}

func _initialize() -> void:
	call_deferred("run")

func configuration() -> Dictionary:
	# Reuse the existing formal opt-in: real player, original opening cash,
	# original Paris presence, personal storage permission and native binding.
	var cfg: Dictionary = EconomyDevelopmentConfig.formal_limited()
	# Retain its case_id: WorldBootstrap uses it for host-place preparation.
	cfg["production_enabled"] = false
	for firm: Dictionary in cfg["firms"]:
		for site: Dictionary in firm["sites"]:
			site["production_enabled"] = false
			site["targets"] = EconomySliceConfig.zero_stock(EconomySliceConfig.good_ids(cfg))
			if site["id"] == LOCAL: site["stock"]["bread"] = 2
			if site["id"] == REMOTE: site["stock"]["bread"] = 4
	for actor: Dictionary in cfg["actors"]:
		if actor["id"] == PERSON:
			# Only initial scenario data; no live holdings, need or clock rewrites.
			actor["stock"] = EconomySliceConfig.zero_stock(EconomySliceConfig.good_ids(cfg))
			actor["needs"] = {"food": 2, "clothing": 0, "household": 0}
			actor["daily_need"] = 2
		else:
			actor["stock"]["bread"] = 100
			actor["stock"]["clothes"] = 100
			actor["stock"]["soap"] = 100
	for route: Dictionary in cfg["routes"]:
		if route["id"] == SLOW: route["delay"] = 6
	cfg["information"].append({"actor": PERSON, "kind": "supplier", "candidate": SELLER + "|bread|" + REMOTE, "delivery_day": 0})
	return cfg

func save_report() -> void:
	report["elapsed_seconds"] = float(Time.get_ticks_usec() - started_usec) / 1000000.0
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write absolute QA output: " + output_path)
		quit(2)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()

func check(ok: bool, label: String, detail: Variant = {}) -> bool:
	if ok: return true
	report["status"] = label
	report["failure_detail"] = detail
	save_report()
	print("QA_PERSONAL_ARRANGEMENT_TIMING ", label)
	quit(1)
	return false

func advance_to(b: WorldBuildResult, minute: int) -> bool:
	var result: Dictionary = b.simulation_step.advance_minutes(minute - b.world.game_clock.total_minutes())
	return check(result.get("success", true) and b.world.game_clock.total_minutes() == minute, "CLOCK_OR_DOMAIN_STEP_BLOCKED", result)

func orders_for(e: EconomyR1Slice) -> Array:
	var rows: Array = []
	for order: Dictionary in e._orders.values():
		if order["buyer"] == PERSON and order["good"] == "bread": rows.append(order.duplicate(true))
	return rows

func capture(b: WorldBuildResult, label: String) -> void:
	var e: EconomyR1Slice = b.world.economy_r1
	var p: FormalPersonalEconomyState = b.world.personal_economy_state
	report["records"].append({"label": label, "minute": b.world.game_clock.total_minutes(), "place": b.world.person_overlay.current_place(PERSON), "arrangement": p.arrangement(PERSON, ITEM), "holding": p.holding(PERSON, ITEM), "incoming_goods": e.personal_incoming(PERSON, ITEM), "need": e._needs.get(PERSON, {}).duplicate(true), "orders": orders_for(e), "available_cash": b.world.ledger_state.available_balance(p.account_id_for_person(PERSON)), "reserved_cash": b.world.ledger_state.reserved_balance(p.account_id_for_person(PERSON))})

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or not args[0].is_absolute_path():
		push_error("Usage: -- /absolute/output.json (one baseline case; no production edits)")
		quit(2)
		return
	output_path = args[0]
	started_usec = Time.get_ticks_usec()
	report["status"] = "RUNNING_NOT_YET_REPRODUCED"
	save_report()
	var cfg := configuration()
	if not check(EconomySliceConfig.valid(cfg), "FIXTURE_BLOCKED_INVALID_INITIAL_CONFIGURATION"): return
	var b: WorldBuildResult = WorldBootstrap.new().build(null, [], [], FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT, false, cfg)
	if not check(b.success and b.world.economy_r1 != null, "FIXTURE_BLOCKED_NATIVE_WORLD", {"build_error": b.error, "native_error": b.world.native_economy_error}): return
	var e: EconomyR1Slice = b.world.economy_r1
	var p: FormalPersonalEconomyState = b.world.personal_economy_state
	if not check(b.world.player_state.player_id() == PERSON and p.manages_native(PERSON) and e.personal_authorized(PERSON) and b.world.person_overlay.is_at_place(PERSON, "place:paris"), "FIXTURE_BLOCKED_NATIVE_PERSON_OR_AUTHORITY"): return
	if not advance_to(b, 720): return
	var plan_result := p.set_daily_consumption(PERSON, ITEM, 2, true, true)
	if not check(plan_result.get("success", false), "FIXTURE_BLOCKED_ORIGINAL_ARRANGEMENT_COMMAND", plan_result): return
	var plan := p.arrangement(PERSON, ITEM)
	if not check(plan.get("quantity_scale") == 1 and plan.get("quantity") == 2 and plan.get("mode") == "flow" and plan.get("next_due_minute") == FIRST_DUE, "FIXTURE_BLOCKED_NONMIDNIGHT_FLOW_PLAN", plan): return
	var far_quote := p.purchase_quote(PERSON, REMOTE, ITEM, 4)
	if not check(far_quote.get("success", false) and far_quote.get("offered_quantity", 0) >= 4 and far_quote.get("route_id") == SLOW, "FIXTURE_BLOCKED_LAWFUL_LATE_SOURCE", far_quote): return
	var far := p.purchase(PERSON, REMOTE, ITEM, 4, -1, far_quote)
	if not check(far.get("success", false), "FIXTURE_BLOCKED_ORIGINAL_LATE_PURCHASE_COMMAND", far): return
	var old_id: String = far["source"]["order_id"]
	report["old_order_id"] = old_id
	report["old_locked_commitment"] = int(far_quote["amount"])
	if not check(e._orders[old_id]["quantity"] == 4 and e._orders[old_id]["need_category"] == "" and e._earliest_dispatch(e._orders[old_id]) == 1, "FIXTURE_BLOCKED_LATE_RESPONSIBILITY_SHAPE", e._orders[old_id]): return
	capture(b, "INITIAL_NOON_PLAN_AND_LEGAL_LATE4_HOLDING")
	if not advance_to(b, FIRST_DUE - 1): return
	capture(b, "BEFORE_FIRST_DUE")
	if not check(p.holding(PERSON, ITEM)["quantity"] == 0 and e.personal_incoming(PERSON, ITEM) == 4 and e._daily_need(PERSON, "food") == 2, "FIXTURE_BLOCKED_NEED_OR_STOCK_CHANGED"): return
	if not advance_to(b, FIRST_DUE): return
	capture(b, "FIRST_DUE_CLOSED_BEFORE_WITNESS")
	if not check(orders_for(e).size() == 1 and e._needs[PERSON]["categories"]["food"]["unmet"] == 2 and p.arrangement(PERSON, ITEM)["next_due_minute"] == SECOND_DUE, "BASELINE_BEHAVIOR_NOT_REPRODUCED", orders_for(e)): return
	report["baseline_observation"] = "LATE4_TOTAL_SUPPRESSED_AUTO_BUY_AT_FIRST_NOON_DUE"
	report["original_first_failure_records"] = p.living_records(PERSON, 40)
	# Explicit authorised-owner witness, after the first due has already closed.
	# Ordinary local one-day transport CANNOT save the immediate next noon due.
	var local_quote := p.purchase_quote(PERSON, LOCAL, ITEM, 2)
	if not check(local_quote.get("success", false) and local_quote.get("offered_quantity", 0) >= 2 and local_quote.get("route_id") == "edge:r2_paris_local" and local_quote.get("earliest_arrival_day") == 3, "TIMELY_FUTURE_WITNESS_NOT_ESTABLISHED", local_quote): return
	var local := p.purchase(PERSON, LOCAL, ITEM, 2, -1, local_quote)
	if not check(local.get("success", false), "TIMELY_FUTURE_WITNESS_PURCHASE_REJECTED", local): return
	var local_id: String = local["source"]["order_id"]
	report["manual_witness_order_id"] = local_id
	report["witness_timing"] = {"accepted_after_closed_due": FIRST_DUE, "earliest_dispatch_minute": e._earliest_dispatch(e._orders[local_id]) * 1440, "next_due_cannot_be_saved": SECOND_DUE, "expected_arrival_minute": LOCAL_ARRIVAL, "future_due_can_be_saved": THIRD_DUE}
	if not check(e._earliest_dispatch(e._orders[local_id]) == 2 and e._orders[local_id]["quantity"] == 2, "TIMELY_FUTURE_WITNESS_DISPATCH_MISMATCH"): return
	if not advance_to(b, SECOND_DUE): return
	capture(b, "SECOND_DUE_ALSO_CLOSED_BEFORE_LOCAL_ARRIVAL")
	if not check(p.holding(PERSON, ITEM)["quantity"] == 0 and e._needs[PERSON]["categories"]["food"]["unmet"] == 2, "INCORRECT_RETROACTIVE_OR_EARLY_COVERAGE"): return
	if not advance_to(b, LOCAL_ARRIVAL): return
	capture(b, "SAME_DAY_MIDNIGHT_ARRIVAL_BEFORE_NOON_DUE")
	if not check(e._orders[local_id]["delivered"] == 2 and p.holding(PERSON, ITEM)["quantity"] == 2 and p.holding(PERSON, ITEM)["consumed"] == 0, "TIMELY_FUTURE_WITNESS_NOT_ACTUALLY_RECEIVED"): return
	if not advance_to(b, THIRD_DUE - 1): return
	if not check(p.holding(PERSON, ITEM)["quantity"] == 2 and p.arrangement(PERSON, ITEM)["next_due_minute"] == THIRD_DUE, "ARRANGEMENT_CONSUMED_BEFORE_ITS_EXACT_DUE"): return
	if not advance_to(b, THIRD_DUE): return
	capture(b, "ORIGINAL_NOON_CONSUMPTION_SAVED_ONLY_FUTURE_DUE")
	if not check(p.holding(PERSON, ITEM)["quantity"] == 0 and p.holding(PERSON, ITEM)["consumed"] == 2 and e._needs[PERSON]["categories"]["food"]["satisfied"] == 2 and orders_for(e).size() == 2, "FUTURE_DUE_NOT_SAVED_BY_ACTUAL_ITEMS"): return
	var failures: Array = []
	var consumption: Array = []
	for record: Dictionary in p.living_records(PERSON, 100):
		if record.get("commodity_id") != ITEM: continue
		if record.get("kind") == "native_failed" and record.get("source") == "daily": failures.append(int(record["effective_minute"]))
		if record.get("kind") == "native_consume": consumption.append(record)
	failures.sort()
	if not check(failures == [FIRST_DUE, SECOND_DUE] and consumption.size() == 1 and consumption[0]["effective_minute"] == THIRD_DUE and consumption[0]["quantity"] == 2, "ORIGINAL_FAILURE_OR_CONSUMPTION_HISTORY_MISMATCH", {"failures": failures, "consumption": consumption}): return
	var receipts: Array = []
	for receipt: Dictionary in e._delivery_receipts.values():
		if receipt["order_id"] == local_id: receipts.append(receipt.duplicate(true))
	if not check(receipts.size() == 1 and receipts[0]["delivered_minute"] == LOCAL_ARRIVAL and e._orders[old_id]["delivered"] == 0 and e._orders[old_id]["cancelled"] == 0 and int(e._orders[old_id]["pending"]) + int(e._orders[old_id]["transit"]) == 4, "ORIGINAL_LATE_RESPONSIBILITY_OR_LOCAL_RECEIPT_CHANGED", receipts): return
	if not check(b.world.ledger_state.reserved_balance(p.account_id_for_person(PERSON)) == int(far_quote["amount"]), "ORIGINAL_LATE_CASH_RESERVATION_CHANGED"): return
	var local_paid := 0
	var payments: Array = []
	for tx: Dictionary in b.world.ledger_state.transactions():
		if tx.get("reference_id") not in [old_id, local_id]: continue
		payments.append(tx.duplicate(true))
		if tx.get("reference_id") == local_id and tx.get("kind") == "goods": local_paid += int(tx["amount"])
	if not check(local_paid == int(local_quote["amount"]), "LOCAL_WITNESS_PAYMENT_NOT_EXACTLY_ONCE", payments): return
	report["original_ledger_payments"] = payments
	report["local_receipts"] = receipts
	report["daily_failure_minutes_preserved"] = failures
	report["actual_consumption"] = consumption
	report["old_order_still_live"] = e._orders[old_id].duplicate(true)
	report["status"] = "BASELINE_FAIL_REPRODUCED_LATE4_SUPPRESSES_FUTURE_LOCAL2_WITH_EXACT_DUE_WITNESS"
	report["limits"].erase("BASELINE_REPRODUCTION_REQUIRES_FINAL_SUCCESS_LABEL")
	save_report()
	print("QA_PERSONAL_ARRANGEMENT_TIMING ", report["status"])
	quit()

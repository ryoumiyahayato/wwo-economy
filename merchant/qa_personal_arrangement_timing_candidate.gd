extends SceneTree
## Candidate-only regression. No engine run is claimed by writing this script.
## One legal native opening, original arrangement/purchase commands and clock.
## The only explicit purchase is the initial late four. Local two must be bought
## by the original clock's arrangement settlement, never by this QA script.
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
const REMOTE_ARRIVAL := 10080
const SEVENTH_DUE := 10800
const EIGHTH_DUE := 12240
var output_path: String = ""
var started_usec: int = 0
var original_contract: Dictionary = {}
var first_failure: Dictionary = {}
var report: Dictionary = {
	"case": "PERSONAL_NOON_FLOW2_AUTOMATIC_LOCAL2_WITH_LATE4",
	"status": "NOT_RUN",
	"initialization_control": "ORIGINAL_BOOTSTRAP_INITIALIZE_LAND_ADMINISTRATION_TRUE",
	"records": [],
	"replay_checks": [],
	"limits": [
		"EXPLICIT_LEGAL_NEW_WORLD_VARIANT_NOT_PLAYER_SAVE",
		"ONE_NATIVE_FLOW_COMMODITY_AND_ONE_PERSON_ONLY",
		"NATIVE_INTEGER_GOODS_QUANTITY_SCALE_1_NOT_MILLI_OR_SERVICE_BALANCE",
		"FINITE_THROUGH_DAY8_NOON_NOT_UNBOUNDED_STABILITY",
		"NO_MANUAL_REPLENISHMENT_OR_REAL_WORLD_SNAPSHOT_MUTATION",
		"CANDIDATE_REQUIRES_ACTUAL_ENGINE_RUN_AND_FINAL_SUCCESS_LABEL"
	]
}

func _initialize() -> void:
	call_deferred("run")

func configuration() -> Dictionary:
	# Same economic opening as the unchanged baseline. The new normalized old-rule
	# control and this candidate both enable the original normal bootstrap administration.
	# Retain formal_limited case_id for the original host-place preparation.
	var cfg: Dictionary = EconomyDevelopmentConfig.formal_limited()
	cfg["production_enabled"] = false
	for firm: Dictionary in cfg["firms"]:
		for site: Dictionary in firm["sites"]:
			site["production_enabled"] = false
			site["targets"] = EconomySliceConfig.zero_stock(EconomySliceConfig.good_ids(cfg))
			if site["id"] == LOCAL: site["stock"]["bread"] = 2
			if site["id"] == REMOTE: site["stock"]["bread"] = 4
	for actor: Dictionary in cfg["actors"]:
		if actor["id"] == PERSON:
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
	print("QA_PERSONAL_ARRANGEMENT_TIMING_CANDIDATE ", label)
	quit(1)
	return false

# Bounded failure evidence only. Never writes a full saved world or relaxes
# equality. JSON-pointer-like paths identify original before/after leaf values.
func diff_value(value: Variant) -> Variant:
	if value is Dictionary: return {"summary_type": "Dictionary", "size": value.size()}
	if value is Array: return {"summary_type": "Array", "size": value.size()}
	if value is String: return value if value.length() <= 256 else value.substr(0, 256) + "...[truncated]"
	if typeof(value) in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT]: return value
	return {"summary_type": type_string(typeof(value)), "value": str(value).substr(0, 256)}

func collect_diff(before: Variant, after: Variant, path: String, depth: int, result: Dictionary) -> void:
	if result["entries"].size() >= 32 or int(result["visited"]) >= 20000:
		result["truncated"] = true
		return
	result["visited"] += 1
	if typeof(before) == typeof(after) and before == after: return
	if depth >= 24 or typeof(before) != typeof(after):
		result["entries"].append({"path": path, "before_type": type_string(typeof(before)), "after_type": type_string(typeof(after)), "before": diff_value(before), "after": diff_value(after), "depth_limit": depth >= 24})
		return
	if before is Dictionary and after is Dictionary:
		var keys: Array = before.keys()
		for key: Variant in after:
			if not before.has(key): keys.append(key)
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
		for key: Variant in keys:
			if result["entries"].size() >= 32 or int(result["visited"]) >= 20000:
				result["truncated"] = true
				break
			var child: String = path + "/" + str(key).replace("~", "~0").replace("/", "~1")
			if not before.has(key) or not after.has(key):
				result["entries"].append({"path": child, "before_present": before.has(key), "after_present": after.has(key), "before": diff_value(before.get(key)), "after": diff_value(after.get(key))})
			else: collect_diff(before[key], after[key], child, depth + 1, result)
	elif before is Array and after is Array:
		if before.size() != after.size(): result["entries"].append({"path": path + "/@size", "before": before.size(), "after": after.size()})
		for index: int in maxi(before.size(), after.size()):
			if result["entries"].size() >= 32 or int(result["visited"]) >= 20000:
				result["truncated"] = true
				break
			var child: String = path + "/" + str(index)
			if index >= before.size() or index >= after.size():
				result["entries"].append({"path": child, "before_present": index < before.size(), "after_present": index < after.size(), "before": diff_value(before[index]) if index < before.size() else null, "after": diff_value(after[index]) if index < after.size() else null})
			else: collect_diff(before[index], after[index], child, depth + 1, result)
	else:
		result["entries"].append({"path": path, "before": diff_value(before), "after": diff_value(after)})

func snapshot_diff(before: Dictionary, after: Dictionary) -> Dictionary:
	var result := {"equal": before == after, "entries": [], "visited": 0, "truncated": false, "entry_limit": 32, "depth_limit": 24, "visit_limit": 20000, "unequal_top_level_fields": []}
	var keys: Array = before.keys()
	for key: Variant in after:
		if not before.has(key): keys.append(key)
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
	for key: Variant in keys:
		if not before.has(key) or not after.has(key) or before[key] != after[key]: result["unequal_top_level_fields"].append(str(key))
	collect_diff(before, after, "", 0, result)
	return result


func advance_to(b: WorldBuildResult, minute: int) -> bool:
	if not check(minute >= b.world.game_clock.total_minutes(), "QA_CLOCK_TARGET_WENT_BACKWARD"): return false
	var result: Dictionary = b.simulation_step.advance_minutes(minute - b.world.game_clock.total_minutes())
	return check(result.get("success", true) and b.world.game_clock.total_minutes() == minute, "CLOCK_OR_DOMAIN_STEP_BLOCKED", result)

func orders_for(e: EconomyR1Slice) -> Array:
	var rows: Array = []
	for order: Dictionary in e._orders.values():
		if order["buyer"] == PERSON and order["good"] == "bread": rows.append(order.duplicate(true))
	return rows

func daily_failures(p: FormalPersonalEconomyState) -> Array:
	var rows: Array = []
	for record: Dictionary in p.living_records(PERSON, 1000):
		if record.get("commodity_id") == ITEM and record.get("kind") == "native_failed" and record.get("source") == "daily": rows.append(record.duplicate(true))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["effective_minute"]) < int(b["effective_minute"]))
	return rows

func consumptions(p: FormalPersonalEconomyState) -> Array:
	var rows: Array = []
	for record: Dictionary in p.living_records(PERSON, 1000):
		if record.get("commodity_id") == ITEM and record.get("kind") == "native_consume": rows.append(record.duplicate(true))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["effective_minute"]) < int(b["effective_minute"]))
	return rows

func receipts_for(e: EconomyR1Slice, order_id: String) -> Array:
	var rows: Array = []
	for receipt: Dictionary in e._delivery_receipts.values():
		if receipt["order_id"] == order_id: rows.append(receipt.duplicate(true))
	return rows

func payments_for(b: WorldBuildResult, order_id: String) -> Dictionary:
	var result := {"goods": 0, "freight": 0, "goods_count": 0, "freight_count": 0, "transactions": []}
	for tx: Dictionary in b.world.ledger_state.transactions():
		if tx.get("reference_id") != order_id: continue
		result["transactions"].append(tx.duplicate(true))
		if tx.get("kind") in ["goods", "freight"]:
			var kind: String = tx["kind"]
			result[kind] = int(result[kind]) + int(tx["amount"])
			result[kind + "_count"] = int(result[kind + "_count"]) + 1
	return result

func capture(b: WorldBuildResult, label: String) -> void:
	var e: EconomyR1Slice = b.world.economy_r1
	var p: FormalPersonalEconomyState = b.world.personal_economy_state
	report["records"].append({"label": label, "minute": b.world.game_clock.total_minutes(), "place": b.world.person_overlay.current_place(PERSON), "arrangement": p.arrangement(PERSON, ITEM), "holding": p.holding(PERSON, ITEM), "incoming_goods": e.personal_incoming(PERSON, ITEM), "need": e._needs.get(PERSON, {}).duplicate(true), "orders": orders_for(e), "available_cash": b.world.ledger_state.available_balance(p.account_id_for_person(PERSON)), "reserved_cash": b.world.ledger_state.reserved_balance(p.account_id_for_person(PERSON))})

func check_old_responsibility(e: EconomyR1Slice, old_id: String) -> bool:
	if not check(e._orders.has(old_id), "ORIGINAL_ORDER_DISAPPEARED"): return false
	var current: Dictionary = e._orders[old_id]
	# The physical progress fields may advance; the original contract may not.
	for field: String in original_contract:
		if field in ["pending", "transit", "delivered", "cancelled"]: continue
		if not check(current.get(field) == original_contract[field], "ORIGINAL_LOCKED_CONTRACT_CHANGED", {"field": field, "before": original_contract[field], "after": current.get(field)}): return false
	return check(current["quantity"] == 4 and current["cancelled"] == 0 and int(current["pending"]) + int(current["transit"]) + int(current["delivered"]) == 4, "ORIGINAL_RESPONSIBILITY_LOST_OR_CANCELLED", current)

func check_same_minute(b: WorldBuildResult, label: String) -> bool:
	# Replaying the public settlement at an already closed due must be a no-op.
	var before: Dictionary = b.persistence.snapshot()
	var settled: Dictionary = b.world.personal_economy_state.settle_due_consumption()
	if not check(settled.get("completed", -1) == 0 and settled.get("failed", -1) == 0 and before == b.persistence.snapshot(), "SAME_MINUTE_SETTLEMENT_REPEATED_WORK", {"label": label, "result": settled}): return false
	var e: EconomyR1Slice = b.world.economy_r1
	var preview: Dictionary = {}
	# Optional diagnostic API; observation of the real automatic order is the
	# mandatory test. No call here submits or manually triggers replenishment.
	if e.has_method("personal_arrangement_purchase_quote"):
		preview = e.call("personal_arrangement_purchase_quote", PERSON, ITEM)
		var repeated: Dictionary = e.call("personal_arrangement_purchase_quote", PERSON, ITEM)
		if not check(preview == repeated and before == b.persistence.snapshot(), "ARRANGEMENT_PREVIEW_MUTATED_WORLD_OR_IS_UNSTABLE", {"label": label, "preview": preview, "repeated": repeated}): return false
		var no_purchase: bool = typeof(preview.get("quantity")) == TYPE_INT and int(preview["quantity"]) == 0 if preview.get("success", false) else not str(preview.get("reason", preview.get("error", ""))).is_empty()
		if not check(no_purchase, "EXHAUSTED_SUPPLY_PREVIEW_OFFERS_NEW_ORDER", {"label": label, "preview": preview}): return false
	report["replay_checks"].append({"label": label, "minute": b.world.game_clock.total_minutes(), "settlement": settled, "preview_available": e.has_method("personal_arrangement_purchase_quote"), "preview": preview, "full_snapshot_unchanged": true})
	return true

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or not args[0].is_absolute_path():
		push_error("Usage: -- /absolute/output.json (candidate only; no manual replenishment)")
		quit(2)
		return
	output_path = args[0]
	started_usec = Time.get_ticks_usec()
	report["status"] = "RUNNING_NOT_YET_VERIFIED"
	save_report()
	var cfg := configuration()
	if not check(EconomySliceConfig.valid(cfg), "FIXTURE_BLOCKED_INVALID_INITIAL_CONFIGURATION"): return
	var b: WorldBuildResult = WorldBootstrap.new().build(null, [], [], FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT, true, cfg)
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
	if not check(far_quote.get("success", false) and far_quote.get("offered_quantity", 0) >= 4 and far_quote.get("route_id") == SLOW and far_quote.get("amount") == 36, "FIXTURE_BLOCKED_LAWFUL_LATE_SOURCE", far_quote): return
	# The sole explicit purchase in the test. This is the baseline late holding.
	var far := p.purchase(PERSON, REMOTE, ITEM, 4, -1, far_quote)
	if not check(far.get("success", false), "FIXTURE_BLOCKED_ORIGINAL_LATE_PURCHASE_COMMAND", far): return
	var old_id: String = far["source"]["order_id"]
	original_contract = e._orders[old_id].duplicate(true)
	report["old_order_id"] = old_id
	report["old_locked_commitment"] = int(far_quote["amount"])
	if not check(original_contract["quantity"] == 4 and original_contract["need_category"] == "" and e._earliest_dispatch(original_contract) == 1, "FIXTURE_BLOCKED_LATE_RESPONSIBILITY_SHAPE", original_contract): return
	capture(b, "INITIAL_NOON_PLAN_AND_LEGAL_LATE4_HOLDING")
	if not advance_to(b, FIRST_DUE - 1): return
	capture(b, "BEFORE_FIRST_DUE_NO_REPLENISHMENT_YET")
	if not check(orders_for(e).size() == 1 and p.holding(PERSON, ITEM)["quantity"] == 0 and e.personal_incoming(PERSON, ITEM) == 4 and e._daily_need(PERSON, "food") == 2, "FIXTURE_BLOCKED_NEED_STOCK_OR_ORDER_CHANGED_BEFORE_DUE"): return
	if not advance_to(b, FIRST_DUE): return
	capture(b, "FIRST_DUE_FAILED_AND_CLOCK_AUTOMATICALLY_BOUGHT_LOCAL2")
	var all_orders := orders_for(e)
	var local_orders: Array = []
	for order: Dictionary in all_orders:
		if order["seller_site"] == LOCAL: local_orders.append(order)
	if not check(all_orders.size() == 2 and local_orders.size() == 1, "AUTOMATIC_LOCAL_REPLENISHMENT_NOT_OBSERVED", all_orders): return
	var local_order: Dictionary = local_orders[0]
	var local_id: String = local_order["id"]
	report["automatic_local_order_id"] = local_id
	if not check(local_order["quantity"] == 2 and local_order["accepted_minute"] == FIRST_DUE and local_order["accepted_day"] == 1 and local_order["route_id"] == "edge:r2_paris_local" and e._earliest_dispatch(local_order) == 2 and local_order["delivered"] == 0 and local_order["cancelled"] == 0 and local_order["price"] == 7, "AUTOMATIC_ORDER_HAS_WRONG_QUANTITY_TIME_OR_ROUTE", local_order): return
	var failed_at_first := daily_failures(p)
	if not check(failed_at_first.size() == 1 and failed_at_first[0]["effective_minute"] == FIRST_DUE and failed_at_first[0]["quantity"] == 2 and e._needs[PERSON]["categories"]["food"]["unmet"] == 2 and p.holding(PERSON, ITEM)["consumed"] == 0 and p.arrangement(PERSON, ITEM)["next_due_minute"] == SECOND_DUE, "FIRST_DUE_FAILURE_REWRITTEN_OR_PREMATURELY_SATISFIED", failed_at_first): return
	first_failure = failed_at_first[0].duplicate(true)
	report["first_failure_record"] = first_failure.duplicate(true)
	if not check_old_responsibility(e, old_id): return
	if not check(b.world.ledger_state.reserved_balance(p.account_id_for_person(PERSON)) == 50 and payments_for(b, old_id)["transactions"].is_empty() and payments_for(b, local_id)["transactions"].is_empty(), "AUTOMATIC_RESERVATION_OR_PREDELIVERY_PAYMENT_WRONG"): return
	if not check_same_minute(b, "FIRST_DUE_ALREADY_CLOSED"): return
	if not advance_to(b, SECOND_DUE): return
	capture(b, "SECOND_DUE_CANNOT_BE_SAVED_BY_DAY3_ARRIVAL")
	if not check(p.holding(PERSON, ITEM)["quantity"] == 0 and p.holding(PERSON, ITEM)["consumed"] == 0 and e._needs[PERSON]["categories"]["food"]["unmet"] == 2 and daily_failures(p).size() == 2 and orders_for(e).size() == 2, "INCORRECT_RETROACTIVE_EARLY_OR_DUPLICATE_REPLENISHMENT"): return
	if not check_same_minute(b, "SECOND_DUE_ALREADY_CLOSED"): return
	if not advance_to(b, LOCAL_ARRIVAL): return
	capture(b, "LOCAL2_ACTUALLY_ARRIVED_AT_DAY3_MIDNIGHT")
	var local_receipts := receipts_for(e, local_id)
	if not check(e._orders[local_id]["delivered"] == 2 and p.holding(PERSON, ITEM)["quantity"] == 2 and p.holding(PERSON, ITEM)["consumed"] == 0 and local_receipts.size() == 1 and local_receipts[0]["delivered_minute"] == LOCAL_ARRIVAL and local_receipts[0]["quantity"] == 2, "LOCAL2_NOT_ACTUALLY_RECEIVED_AT_EXPECTED_TIME", local_receipts): return
	var local_payment := payments_for(b, local_id)
	if not check(local_payment["goods"] == 14 and local_payment["goods_count"] == 1 and local_payment["freight"] == 0 and local_payment["freight_count"] == 0 and b.world.ledger_state.reserved_balance(p.account_id_for_person(PERSON)) == 36, "LOCAL_PAYMENT_OR_REMAINING_OLD_RESERVATION_WRONG", local_payment): return
	if not advance_to(b, THIRD_DUE - 1): return
	if not check(p.holding(PERSON, ITEM)["quantity"] == 2 and p.arrangement(PERSON, ITEM)["next_due_minute"] == THIRD_DUE, "ARRANGEMENT_CONSUMED_BEFORE_ITS_EXACT_DUE"): return
	if not advance_to(b, THIRD_DUE): return
	capture(b, "LOCAL2_ACTUALLY_CONSUMED_AT_DAY3_NOON")
	var used_at_third := consumptions(p)
	if not check(p.holding(PERSON, ITEM)["quantity"] == 0 and p.holding(PERSON, ITEM)["consumed"] == 2 and e._needs[PERSON]["categories"]["food"]["satisfied"] == 2 and used_at_third.size() == 1 and used_at_third[0]["effective_minute"] == THIRD_DUE and used_at_third[0]["quantity"] == 2 and orders_for(e).size() == 2, "AUTOMATIC_LOCAL2_DID_NOT_SAVE_REAL_FUTURE_CONSUMPTION", used_at_third): return
	if not check(daily_failures(p)[0] == first_failure and daily_failures(p)[1]["effective_minute"] == SECOND_DUE and e._orders[old_id]["delivered"] == 0, "ORIGINAL_FAILURE_OR_LATE_DELIVERY_REWRITTEN"): return
	if not check_old_responsibility(e, old_id): return
	if not check_same_minute(b, "THIRD_DUE_ALREADY_CLOSED"): return
	# Restore a complete, unmodified authoritative snapshot, then continue the
	# restored world through the original late delivery and both later meals.
	var snapshot: Dictionary = b.persistence.snapshot()
	var restored: WorldBuildResult = FormalPersistence.new().restore_candidate(snapshot)
	if not check(restored.success, "FULL_SNAPSHOT_RESTORE_REJECTED", {"error": restored.error}): return
	var restored_snapshot: Dictionary = restored.persistence.snapshot()
	var live_after_restore: Dictionary = b.persistence.snapshot()
	if restored_snapshot != snapshot or live_after_restore != snapshot:
		report["restore_difference_evidence"] = {"restored_vs_saved": snapshot_diff(snapshot, restored_snapshot), "original_world_vs_saved": snapshot_diff(snapshot, live_after_restore)}
	if not check(restored_snapshot == snapshot and live_after_restore == snapshot, "FULL_SNAPSHOT_RESTORE_CHANGED_AUTHORITATIVE_STATE", report.get("restore_difference_evidence", {})): return
	report["full_restore"] = {"minute": THIRD_DUE, "success": true, "all_snapshot_fields_equal": true}
	if not check_same_minute(restored, "RESTORED_THIRD_DUE_ALREADY_CLOSED"): return
	b = restored
	e = b.world.economy_r1
	p = b.world.personal_economy_state
	for due: int in [6480, 7920, 9360]:
		if not advance_to(b, due): return
		capture(b, "NO_SUPPLY_AT_NOON_" + str(due))
		if not check(orders_for(e).size() == 2 and p.holding(PERSON, ITEM)["quantity"] == 0 and p.holding(PERSON, ITEM)["consumed"] == 2 and e._needs[PERSON]["categories"]["food"]["unmet"] == 2, "EXHAUSTED_STOCK_CREATED_NEW_ORDER_OR_FAKE_CONSUMPTION"): return
		if not check_old_responsibility(e, old_id): return
		if not check_same_minute(b, "NO_SUPPLY_CLOSED_DUE_" + str(due)): return
	if not advance_to(b, REMOTE_ARRIVAL): return
	capture(b, "ORIGINAL_REMOTE4_DELIVERED_AND_PAID_DAY7_MIDNIGHT")
	var far_receipts := receipts_for(e, old_id)
	var far_payment := payments_for(b, old_id)
	if not check(e._orders[old_id]["delivered"] == 4 and p.holding(PERSON, ITEM)["quantity"] == 4 and p.holding(PERSON, ITEM)["consumed"] == 2 and e.personal_incoming(PERSON, ITEM) == 0 and far_receipts.size() == 1 and far_receipts[0]["quantity"] == 4 and far_receipts[0]["delivered_minute"] == REMOTE_ARRIVAL, "ORIGINAL_REMOTE4_NOT_PHYSICALLY_DELIVERED", far_receipts): return
	if not check(far_payment["goods"] == 32 and far_payment["freight"] == 4 and far_payment["goods_count"] == 1 and far_payment["freight_count"] == 1 and b.world.ledger_state.reserved_balance(p.account_id_for_person(PERSON)) == 0, "ORIGINAL_REMOTE_GOODS_OR_FREIGHT_NOT_PAID_ONCE", far_payment): return
	if not check_old_responsibility(e, old_id): return
	if not advance_to(b, SEVENTH_DUE - 1): return
	if not check(p.holding(PERSON, ITEM)["quantity"] == 4 and p.holding(PERSON, ITEM)["consumed"] == 2, "REMOTE_GOODS_CONSUMED_BEFORE_DAY7_NOON"): return
	if not advance_to(b, SEVENTH_DUE): return
	capture(b, "ORIGINAL_REMOTE_GOODS_FIRST2_CONSUMED_DAY7_NOON")
	if not check(p.holding(PERSON, ITEM)["quantity"] == 2 and p.holding(PERSON, ITEM)["consumed"] == 4 and e._needs[PERSON]["categories"]["food"]["satisfied"] == 2, "REMOTE_GOODS_DID_NOT_FEED_DAY7_NOON"): return
	if not check_same_minute(b, "DAY7_NOON_ALREADY_CLOSED"): return
	if not advance_to(b, EIGHTH_DUE - 1): return
	if not check(p.holding(PERSON, ITEM)["quantity"] == 2 and p.holding(PERSON, ITEM)["consumed"] == 4, "REMOTE_GOODS_CONSUMED_BEFORE_DAY8_NOON"): return
	if not advance_to(b, EIGHTH_DUE): return
	capture(b, "ORIGINAL_REMOTE_GOODS_LAST2_CONSUMED_DAY8_NOON")
	var final_failures := daily_failures(p)
	var failure_minutes: Array = []
	for record: Dictionary in final_failures: failure_minutes.append(int(record["effective_minute"]))
	var final_uses := consumptions(p)
	var consumption_minutes: Array = []
	for record: Dictionary in final_uses:
		consumption_minutes.append(int(record["effective_minute"]))
		if not check(record["quantity"] == 2 and record.get("source") == "daily", "FINAL_CONSUMPTION_QUANTITY_OR_SOURCE_WRONG", record): return
	if not check(failure_minutes == [FIRST_DUE, SECOND_DUE, 6480, 7920, 9360] and final_failures[0] == first_failure and consumption_minutes == [THIRD_DUE, SEVENTH_DUE, EIGHTH_DUE] and p.holding(PERSON, ITEM)["quantity"] == 0 and p.holding(PERSON, ITEM)["consumed"] == 6 and e._needs[PERSON]["categories"]["food"]["satisfied"] == 2 and orders_for(e).size() == 2, "FINAL_FAILURE_CONSUMPTION_OR_ORDER_HISTORY_WRONG", {"failures": final_failures, "consumption": final_uses}): return
	if not check_old_responsibility(e, old_id): return
	if not check(payments_for(b, old_id) == far_payment and payments_for(b, local_id) == local_payment and receipts_for(e, old_id) == far_receipts and receipts_for(e, local_id) == local_receipts and b.world.ledger_state.reserved_balance(p.account_id_for_person(PERSON)) == 0, "PAYMENT_OR_RECEIPT_DUPLICATED_AFTER_DELIVERY"): return
	if not check_same_minute(b, "DAY8_NOON_ALREADY_CLOSED"): return
	# Corrupt only a deep copy supplied to a separate restore candidate. The live
	# world remains unchanged. Reuse the already proven-valid day3 snapshot so
	# rejection cannot be mistaken for an unrelated day8 restore failure.
	var final_snapshot: Dictionary = b.persistence.snapshot()
	var invalid_snapshot: Dictionary = snapshot.duplicate(true)
	invalid_snapshot["personal_economy"]["arrangements"][PERSON][ITEM]["next_due_minute"] = THIRD_DUE
	var rejected: WorldBuildResult = FormalPersistence.new().restore_candidate(invalid_snapshot)
	if not check(not rejected.success and rejected.error.contains("Invalid native arrangement unit, purpose or date"), "CORRUPT_CLOSED_DUE_SNAPSHOT_NOT_REJECTED_FOR_ARRANGEMENT", {"error": rejected.error}): return
	if not check(b.persistence.snapshot() == final_snapshot, "CORRUPT_CANDIDATE_CHANGED_LIVE_WORLD"): return
	report["invalid_restore"] = {"mutated_copy_field": "personal_economy.arrangements[PERSON][ITEM].next_due_minute", "known_valid_snapshot_minute": THIRD_DUE, "invalid_value": THIRD_DUE, "rejected": true, "reason": rejected.error, "live_full_snapshot_unchanged": true}
	report["daily_failure_minutes_preserved"] = failure_minutes
	report["actual_consumption"] = final_uses
	report["local_receipts"] = local_receipts
	report["remote_receipts"] = far_receipts
	report["local_payment"] = local_payment
	report["remote_payment"] = far_payment
	report["old_order_fully_fulfilled"] = e._orders[old_id].duplicate(true)
	report["status"] = "CANDIDATE_PASS_AUTOMATIC_LOCAL2_EXACT_NOON_DUES_REMOTE4_PAID_ONCE_RESTORE_REPLAY_AND_BAD_CANDIDATE_REJECTED"
	report["limits"].erase("CANDIDATE_REQUIRES_ACTUAL_ENGINE_RUN_AND_FINAL_SUCCESS_LABEL")
	save_report()
	print("QA_PERSONAL_ARRANGEMENT_TIMING_CANDIDATE ", report["status"])
	quit()

extends SceneTree
## Legal opening variations only. Runs through original commands, days, cargo,
## StockLots and Ledger. This file does not alter an already loaded world.
const ACTOR := "cohort:regional:paris_food"
const SELLER := "firm:regional_food"
const LOCAL := "site:regional_food:paris"
const REMOTE := "site:regional_food:lyon"
const SLOW := "edge:regional:lyon:paris"

func _initialize() -> void:
	call_deferred("run")

func configuration(kind: String) -> Dictionary:
	var cfg: Dictionary = EconomyDevelopmentConfig.regional_template()
	cfg["case_id"] = "QA_HOUSEHOLD_DAILY2_WINDOW4_LATE4_" + kind
	cfg["production_enabled"] = false
	for firm: Dictionary in cfg["firms"]:
		for site: Dictionary in firm["sites"]:
			site["production_enabled"] = false
			site["targets"] = EconomySliceConfig.zero_stock(EconomySliceConfig.good_ids(cfg))
			if site["id"] == LOCAL: site["stock"]["bread"] = 0 if kind == "NO_TIMELY_STOCK" else 2
			if site["id"] == REMOTE: site["stock"]["bread"] = 4
	for actor: Dictionary in cfg["actors"]:
		# Other original cohorts have a finite initial endowment, keeping this
		# timing fixture free of same-day demand competition, never live grants.
		actor["stock"]["bread"] = 100
		actor["stock"]["clothes"] = 100
		actor["stock"]["soap"] = 100
		if actor["id"] == ACTOR:
			assert(actor["members"] == 2)
			actor["daily_need"] = 1
			actor["needs"] = {"food": 1, "clothing": 0, "household": 0}
			actor["stock"] = EconomySliceConfig.zero_stock(EconomySliceConfig.good_ids(cfg))
			actor["cash"] = 36 if kind == "NO_REMAINING_CASH" else 200
	var information: Array = []
	for row: Dictionary in cfg["information"]:
		if row["actor"] != ACTOR: information.append(row)
	information.append({"actor": ACTOR, "kind": "supplier", "candidate": SELLER + "|bread|" + REMOTE, "delivery_day": 0})
	information.append({"actor": ACTOR, "kind": "supplier", "candidate": SELLER + "|bread|" + LOCAL, "delivery_day": 1})
	cfg["information"] = information
	for route: Dictionary in cfg["routes"]:
		if route["id"] == SLOW: route["delay"] = 6
	return cfg

func run_case(kind: String, baseline: bool) -> Dictionary:
	var cfg := configuration(kind)
	assert(EconomySliceConfig.valid(cfg), "Opening configuration must be legal")
	var b: WorldBuildResult = WorldBootstrap.new().build(null, [], [], FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT, false, {"format": "HOST_REGION_SELECTION", "person_ids": [], "select_people_at_sites": false, "configuration": cfg})
	assert(b.success, "Legal host initial world must build")
	assert(b.simulation_step.advance_minutes(1).get("success", true))
	var e: EconomyR1Slice = b.world.economy_r1
	assert(e._daily_need(ACTOR, "food") == 2)
	assert(e._household_position(ACTOR, true)["food"]["target"] == 4)
	var offer: Dictionary = e._offer(ACTOR, SELLER, "bread", SLOW, REMOTE)
	assert(offer["quantity"] >= 4 and offer["price"] == 8 and offer["freight_per_unit"] == 1)
	var payload := {"quote_id": offer["quote_id"], "seller": SELLER, "seller_site": REMOTE, "good": "bread", "quantity": 4, "denomination": offer["denomination"], "max_price": 8, "path_id": SLOW, "purpose": "HOLDING", "need_by_day": 7}
	# Explicit legal opening holding decision, identical for baseline/candidate.
	# This is not claimed to be a natural NPC choice to buy known-late food.
	var command: Dictionary = e._auto_command(ACTOR, "buy", payload, "QA_EXPLICIT_LEGAL_INITIAL_FAR_HOLDING")
	var accepted: Dictionary = e._accept(ACTOR, command, true)
	assert(accepted.get("accepted", false) and accepted["quantity"] == 4)
	var old_id: String = accepted["order_id"]
	var before: Dictionary = b.persistence.snapshot()
	assert(e._accept(ACTOR, command, true) == accepted)
	assert(before == b.persistence.snapshot(), "Exact command replay cannot reserve/pay twice")
	var initial: Dictionary = e._household_position(ACTOR, true)
	assert(before == b.persistence.snapshot(), "Household query must remain read-only")
	var records: Array = []
	var first_local: Array = []
	for date: int in range(1, 9):
		for hour: int in range(24): assert(b.simulation_step.advance_minutes(60).get("success", true))
		var local_orders: Array = []
		for order: Dictionary in e._orders.values():
			if order["buyer"] == ACTOR and order["seller_site"] == LOCAL and order["good"] == "bread": local_orders.append(order.duplicate(true))
		if date == 1: first_local = local_orders.duplicate(true)
		records.append({"day": e.day, "minute": b.world.game_clock.total_minutes(), "position": e._household_position(ACTOR, true), "actual_consumption": e._needs[ACTOR].duplicate(true), "stock": e._stocks[ACTOR].duplicate(true), "old_order": e._orders[old_id].duplicate(true), "local_orders": local_orders, "available_cash": b.world.ledger_state.available_balance(e._account(ACTOR))})
	assert(e._orders[old_id]["quantity"] == 4 and e._orders[old_id]["delivered"] == 4 and e._orders[old_id]["cancelled"] == 0, "Original late four remain a real fulfilled responsibility")
	var goods_paid := 0
	var freight_paid := 0
	for tx: Dictionary in b.world.ledger_state.transactions():
		if tx.get("reference_id") != old_id: continue
		if tx.get("kind") == "goods": goods_paid += int(tx["amount"])
		if tx.get("kind") == "freight": freight_paid += int(tx["amount"])
	assert(goods_paid == 32, "Original late order is paid once through Ledger")
	var status := "BASELINE_RECORDED_NOT_FIXED" if baseline else "CANDIDATE_ASSERTED"
	if kind == "TIMELY_LOCAL":
		if baseline:
			assert(first_local.is_empty(), "Baseline must reproduce late-total suppression")
			assert(records[1]["actual_consumption"]["categories"]["food"]["unmet"] == 2)
			status = "BASELINE_FAIL_REPRODUCED_LATE4_BLOCKS_TIMELY_LOCAL2"
		else:
			assert(first_local.size() == 1 and first_local[0]["quantity"] == 2, "Only day2 can still be rescued by real one-day local transport")
			assert(first_local[0]["accepted_day"] == 1 and first_local[0]["route_id"] == "edge:regional_local:paris")
			assert(records[0]["actual_consumption"]["categories"]["food"]["unmet"] == 2, "No day1 backfill after consumption")
			assert(records[1]["actual_consumption"]["categories"]["food"]["satisfied"] == 2)
			assert(records[1]["local_orders"].size() == 1, "No duplicate rescue of the same boundary")
	else:
		assert(first_local.is_empty(), "No timely stock or no remaining cash must wait")
	var restored: WorldBuildResult = FormalPersistence.new().restore_candidate(b.persistence.snapshot())
	assert(restored.success, "Full candidate restore must preserve original authorities")
	return {"kind": kind, "status": status, "initial_position_with_late4": initial, "old_order_id": old_id, "first_day_local": first_local, "records": records, "old_goods_paid": goods_paid, "old_freight_paid": freight_paid, "limits": ["LEGAL_INITIAL_VARIANT_NOT_NATURAL_PLAYER_SAVE", "ORIGINAL_LOCAL_ONE_DAY_ROUTE_NOT_ONSITE_OR_INSTANT_FREE_TRANSPORT", "FINITE_8_DAYS", "PERSONAL_SCHEDULE_AND_DINING_NOT_EXERCISED"]}

func run() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() >= 1, "Usage: -- output.json [baseline|candidate] [TIMELY_LOCAL|NO_TIMELY_STOCK|NO_REMAINING_CASH]")
	var baseline: bool = args.size() > 1 and args[1] == "baseline"
	var results: Array = []
	var kinds: Array = [args[2]] if args.size() > 2 else ["TIMELY_LOCAL", "NO_TIMELY_STOCK", "NO_REMAINING_CASH"]
	for kind: String in kinds:
		assert(kind in ["TIMELY_LOCAL", "NO_TIMELY_STOCK", "NO_REMAINING_CASH"])
		results.append(run_case(kind, baseline))
	var output := {"case": "HOUSEHOLD_DAILY2_WINDOW4_LATE4", "baseline": baseline, "results": results}
	var file := FileAccess.open(args[0], FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	print("QA_HOUSEHOLD_TIMING_RECORDED ", "BASELINE" if baseline else "CANDIDATE")
	quit()

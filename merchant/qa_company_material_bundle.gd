extends "res://merchant/qa_company_procurement_priority.gd"
## Legal initial two-input variant; source stock, recipe and prices are not edited
## after bootstrap. This is a separate bounded baseline/candidate policy probe.
## -- /absolute/report.json baseline|candidate complete_pair|missing_second

func run() -> void:
	started = Time.get_ticks_msec()
	var args := OS.get_cmdline_user_args()
	if args.size() != 3 or not args[0].is_absolute_path() or args[1] not in ["baseline", "candidate"] or args[2] not in ["complete_pair", "missing_second"]:
		push_error("Usage: -- /absolute/report.json baseline|candidate complete_pair|missing_second")
		quit(2)
		return
	output_path = args[0]
	baseline = args[1] == "baseline"
	case_name = args[2]
	var cfg: Dictionary = configuration("priority_input_first")
	cfg["case_id"] = "QA_COMPLETE_ORIGINAL_TWO_MATERIAL_BATCH"
	site_row(cfg, "site:regional_textile:z_optional")["targets"]["bread"] = 0
	var weave: Dictionary = site_row(cfg, WEAVE)
	weave["activities"][0]["materials"]["fiber"] = 1
	weave["activities"][0]["materials"]["oil"] = 1
	var supplier: String = UPSTREAM + "|oil|" + FARM
	weave["suppliers"].append(supplier)
	cfg["information"].append({"actor": WEAVE, "kind": "supplier", "candidate": supplier, "delivery_day": 0})
	site_row(cfg, FARM)["stock"]["oil"] = 0 if case_name == "missing_second" else 12
	site_row(cfg, FARM)["prices"]["oil"] = 4
	evidence = {"case": case_name, "configuration_sha256": JSON.stringify(cfg).sha256_text(), "initial_configuration": cfg, "scope": "Same company cash9: fiber1 plus oil1 costs8, one accepted future hourly labor term costs1 if actually worked. No wage debt exists initially. A whole batch is conditional on original labor and capacity, never a promise."}
	write_report("FIXTURE_DECLARED_BEFORE_BOOTSTRAP")
	if not check(EconomySliceConfig.valid(cfg), "Original two-input initial configuration validates"):
		write_report("INVALID_FIXTURE"); quit(1); return
	var b: WorldBuildResult = WorldBootstrap.new().build(null, [], [], FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT, true, {"format": "HOST_REGION_SELECTION", "person_ids": [], "select_people_at_sites": false, "configuration": cfg})
	if not check(b.success, "Original WorldBootstrap accepts two-input fixture: " + str(b.error)):
		write_report("BOOTSTRAP_FAILED"); quit(1); return
	check(b.simulation_step.advance_minutes(1).get("success", true), "Original clock delivers both supplier messages")
	var e: EconomyR1Slice = b.world.economy_r1
	accept_original_employment(e)
	var first: Dictionary = e._offer(TEXTILE, UPSTREAM, "fiber", "edge:regional_local:lyon", FARM, WEAVE)
	var second: Dictionary = e._offer(TEXTILE, UPSTREAM, "oil", "edge:regional_local:lyon", FARM, WEAVE)
	check(first.get("price") == 4 and first.get("transport_quantity", 0) >= 2, "First material is known and can absorb scarce cash in excess of one batch")
	check(second.get("price") == 4 and second.get("transport_quantity", -1) == (0 if case_name == "missing_second" else 12), "Second material availability is an actual source and route fact")
	check(e._activity(WEAVE, "activity:regional_clothes")["materials"]["fiber"] == 1 and e._activity(WEAVE, "activity:regional_clothes")["materials"]["oil"] == 1, "Real recipe consumes one of each material")
	evidence["before"] = {"first_offer": first, "second_offer": second, "cash": b.world.ledger_state.available_balance(e._account(TEXTILE)), "labor_contract": e._contract_for(WORKER, JOB), "wages": company_wages(e), "capacity": e._capital.capacity(WEAVE, 1440, "activity:regional_clothes")}
	write_report("FIXTURE_READY_BEFORE_ORIGINAL_DAY")
	if advance_first_day(b):
		if e.has_method("_production_bundle_position"):
			var snapshot_before: Dictionary = b.persistence.snapshot()
			var group: Dictionary = e.call("_production_bundle_position", WEAVE)
			check(group == e.call("_production_bundle_position", WEAVE) and b.persistence.snapshot() == snapshot_before, "Minimum batch query is deterministic and leaves the complete world unchanged")
			evidence["minimum_batch_query_after_decision"] = group
		var first_orders: Array = matching_orders(e, WEAVE, "fiber")
		var second_orders: Array = matching_orders(e, WEAVE, "oil")
		var want: int = 0 if case_name == "missing_second" else 1
		check(quantity(first_orders) == want and quantity(second_orders) == want, "Finite scarce-cash policy buys one complete pair or waits when second input is unavailable", true)
		check(b.world.ledger_state.available_balance(e._account(TEXTILE)) == (9 if want == 0 else 1), "No excess first input strands cash needed by the missing second input", true)
		check(e._stocks[WEAVE]["fiber"] == 0 and e._stocks[WEAVE]["oil"] == 0 and e._stocks[WEAVE]["clothes"] == 0, "Accepted future inputs are not physical inventory or instant production")
		verify_order_replay(e, b, first_orders + second_orders)
		evidence["outcome"] = {"first_orders": first_orders, "second_orders": second_orders, "cash_available": b.world.ledger_state.available_balance(e._account(TEXTILE)), "cash_reserved": b.world.ledger_state.reserved_balance(e._account(TEXTILE)), "plan": e._plans[WEAVE].duplicate(true), "physical": e._physical_totals[WEAVE].duplicate(true), "wages": company_wages(e), "work_queue": e._work_queue.duplicate(true)}
	if not baseline and failures == 0:
		var continuation: Array = []
		for date: int in [2, 3]:
			if not check(b.simulation_step.advance_minutes(date * 1440 - b.world.game_clock.total_minutes()).get("success", true), "Original clock continues actual arrivals, work, production and wages"): break
			continuation.append({"day": e.day, "first_orders": matching_orders(e, WEAVE, "fiber"), "second_orders": matching_orders(e, WEAVE, "oil"), "physical": e._physical_totals[WEAVE].duplicate(true), "stocks": e._stocks[WEAVE].duplicate(true), "wages": company_wages(e), "cash_available": b.world.ledger_state.available_balance(e._account(TEXTILE))})
		evidence["actual_continuation_through_day3"] = continuation
		check(int(e._physical_totals[WEAVE]["produced"]["clothes"]) == (0 if case_name == "missing_second" else 1), "Obtainable complete inputs actually become one original production batch; missing second input never does")
		if case_name == "complete_pair":
			check(int(e._physical_totals[WEAVE]["used"]["fiber"]) == 1 and int(e._physical_totals[WEAVE]["used"]["oil"]) == 1, "Original production consumes one actual delivered unit of each material exactly once")
			var goods_paid: int = 0
			for tx: Dictionary in b.world.ledger_state.transactions():
				if tx["kind"] == "goods" and tx["from_account_id"] == e._account(TEXTILE): goods_paid += int(tx["amount"])
			check(goods_paid == 8, "Original Ledger pays actual material deliveries8 once without creating revenue")
		verify_normalized_complete_restore(b)
	write_report("FINISHED")
	print("QA_COMPANY_MATERIAL_BUNDLE ", case_name, " failures=", failures)
	quit(1 if failures > 0 else 0)

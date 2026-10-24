extends "res://merchant/qa_company_procurement_priority.gd"
## Existing funded bilateral-credit domain, not a new bank or invented liability.
## -- /absolute/report.json baseline|candidate due_only|due_and_reserved
## No wage claim is fabricated: a separate original-work case is still required.

func run() -> void:
	started = Time.get_ticks_msec()
	var args := OS.get_cmdline_user_args()
	if args.size() != 3 or not args[0].is_absolute_path() or args[1] not in ["baseline", "candidate"] or args[2] not in ["due_only", "due_and_reserved"]:
		push_error("Usage: -- /absolute/report.json baseline|candidate due_only|due_and_reserved"); quit(2); return
	output_path = args[0]; baseline = args[1] == "baseline"; case_name = args[2]
	var reserved_case: bool = case_name == "due_and_reserved"
	var cfg: Dictionary = configuration("priority_input_first")
	cfg["case_id"] = "QA_ORIGINAL_DUE_CREDIT_AND_REAL_ORDER_RESERVE"
	firm_row(cfg, TEXTILE)["cash"] = 9 if reserved_case else 0
	site_row(cfg, WEAVE)["targets"]["clothes"] = 0
	site_row(cfg, WEAVE)["production_enabled"] = false
	for route: Dictionary in cfg["routes"]:
		if route["id"] == "edge:regional_local:lyon": route["delay"] = 6
	cfg["credit_offers"] = [{"lender": UPSTREAM, "borrower": TEXTILE, "principal_limit": 10, "denomination": FormalLedgerState.DENOMINATION, "interest": 0, "duration_days": 1, "valid_days": 30, "requires_job": false}]
	evidence = {"initial_configuration": cfg, "configuration_sha256": JSON.stringify(cfg).sha256_text(), "scope": "One actual loan10 is funded by an existing upstream firm's existing account. Initial cash0 or9, plus original loan10, optional bread1 costs9. Reserved variant makes one original fiber2 purchase at8 with original six-day freight. At day1 loan10 is due; available is already net of the still-real reservation. No NPC auto-borrow or auto-repay policy is added.", "wage_limit": "NO_REAL_WAGE_ARREARS_IN_THIS_FIXTURE"}
	write_report("FIXTURE_DECLARED_BEFORE_BOOTSTRAP")
	if not check(EconomySliceConfig.valid(cfg), "Existing domains validate the finite credit fixture"): write_report("INVALID_FIXTURE"); quit(1); return
	var b: WorldBuildResult = WorldBootstrap.new().build(null, [], [], FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT, true, {"format": "HOST_REGION_SELECTION", "person_ids": [], "select_people_at_sites": false, "configuration": cfg})
	if not check(b.success, "Original bootstrap accepts configuration: " + str(b.error)): write_report("BOOTSTRAP_FAILED"); quit(1); return
	if not check(b.simulation_step.advance_minutes(1).get("success", true), "Original clock delivers supplier knowledge"): write_report("CLOCK_FAILED"); quit(1); return
	var e: EconomyR1Slice = b.world.economy_r1
	var quotes: Array = e._credit.visible(TEXTILE, e._known_credit_lenders(TEXTILE), 1, true)["offers"]
	if not check(quotes.size() == 1 and quotes[0]["available_quantity"] == 10, "Original existing lender actually funds its one known offer"): write_report("OFFER_FAILED"); quit(1); return
	var borrow: Dictionary = e._auto_command(TEXTILE, "accept_credit", {"offer_id": quotes[0]["id"], "amount": 10}, "qa_existing_due_credit")
	var accepted: Dictionary = e.submit_internal(TEXTILE, borrow)
	if not check(accepted.get("accepted", false), "Original accept_credit creates and funds the real obligation"): evidence["loan_failure"] = accepted; write_report("LOAN_FAILED"); quit(1); return
	var loan_id: String = accepted["loan_id"]
	var old_order_id: String = ""
	if reserved_case:
		var offer: Dictionary = e._offer(TEXTILE, UPSTREAM, "fiber", "edge:regional_local:lyon", FARM, WEAVE)
		var buy: Dictionary = e._auto_command(TEXTILE, "buy", {"quote_id": offer["quote_id"], "seller": UPSTREAM, "seller_site": FARM, "buyer_site": WEAVE, "good": "fiber", "quantity": 2, "denomination": offer["denomination"], "max_price": 4, "path_id": offer["route_id"], "need_by_day": 7}, "qa_real_prior_reserved_material")
		var held: Dictionary = e.submit_internal(TEXTILE, buy)
		if not check(held.get("accepted", false) and held.get("quantity") == 2, "Original prior material purchase creates a genuine reservation8"): evidence["order_failure"] = held; write_report("RESERVE_FAILED"); quit(1); return
		old_order_id = held["order_id"]
	check(e._due_credit_amount(TEXTILE, FormalLedgerState.DENOMINATION) == 0, "Loan is not misclassified as due on its issue day")
	check(b.world.ledger_state.available_balance(e._account(TEXTILE)) == (11 if reserved_case else 10), "Initial available balance already excludes the actual reservation once")
	evidence["before"] = {"minute": 1, "loan": e._credit._loans[loan_id].duplicate(true), "loan_command": borrow, "old_order_id": old_order_id, "ledger": b.world.ledger_state.snapshot()}
	write_report("FIXTURE_READY_BEFORE_ORIGINAL_DAY")
	if advance_first_day(b):
		var optional: Array = matching_orders(e, "site:regional_textile:z_optional", "bread")
		var due: int = e._due_credit_amount(TEXTILE, FormalLedgerState.DENOMINATION)
		check(due == 10, "Original due_day has actually arrived and the original loan remains unpaid")
		check(quantity(optional) == 0, "Finite procurement preserves current unreserved debt before optional resale", true)
		check(b.world.ledger_state.available_balance(e._account(TEXTILE)) == (11 if reserved_case else 10), "No optional purchase spends the cash required by the existing due loan", true)
		if reserved_case:
			check(e._orders[old_order_id]["delivered"] == 0 and e._orders[old_order_id]["pending"] + e._orders[old_order_id]["transit"] == 2, "Prior fiber2 remains a real future obligation rather than free inventory")
			check(b.world.ledger_state._reservations.get(old_order_id, {}).get("amount") == 8, "Existing order reservation8 remains in its original Ledger family")
		if e.has_method("_procurement_cash_position"):
			var before: Dictionary = b.persistence.snapshot()
			var position: Dictionary = e.call("_procurement_cash_position", TEXTILE, FormalLedgerState.DENOMINATION)
			check(position == e.call("_procurement_cash_position", TEXTILE, FormalLedgerState.DENOMINATION) and b.persistence.snapshot() == before, "Current due query is pure and deterministic without touching saved historical distribution proofs")
			check(position.get("due_unreserved") == 10 and position.get("available") == (11 if reserved_case else 10), "Current due protection distinguishes original reserve from unreserved due amount")
			evidence["cash_position"] = position
		verify_order_replay(e, b, optional)
		evidence["outcome"] = {"minute": b.world.game_clock.total_minutes(), "loan": e._credit.visible(TEXTILE, [], b.world.game_clock.total_minutes(), true), "optional_orders": optional, "old_order": e._orders.get(old_order_id, {}).duplicate(true), "ledger": b.world.ledger_state.snapshot(), "due_credit": due, "cash_available": b.world.ledger_state.available_balance(e._account(TEXTILE)), "cash_reserved": b.world.ledger_state.reserved_balance(e._account(TEXTILE))}
	write_report("FINISHED")
	print("QA_COMPANY_DUE_CASH ", case_name, " failures=", failures)
	quit(1 if failures > 0 else 0)

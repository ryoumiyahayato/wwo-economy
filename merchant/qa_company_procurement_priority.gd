extends SceneTree
## Static preparation only: parent owns the engine window and runs one case/process.
## Usage: -- /absolute/output.json baseline|candidate CASE
## CASE: priority_optional_first | priority_input_first | budget_actual_two
## Priority pair differs only in one initial branch identifier. Compare both JSONs.
## baseline here means the current timing-fixed, pre-priority candidate snapshot.
## It is NOT runnable on the older sales-control project (new helper APIs are required).
## budget_actual_two is an expected PASS regression in the current timing build:
## original _input_candidate_need already caps wanted by offer.transport_quantity
## before _fund_procurement. A direct gross10 rejection is not a proven NPC bug.
const TEXTILE = "firm:regional_textile"
const WEAVE = "site:regional_textile:lyon"
const BRANCH = "site:regional_textile:marseille"
const FARM = "site:regional_upstream:lyon"
const UPSTREAM = "firm:regional_upstream"
const BAKERY = "site:regional_food:paris"
const FOOD = "firm:regional_food"
const WORKER = "cohort:regional:lyon_textile"
const JOB = "job:regional_textile:lyon"
const BUDGET = "budget:qa_company:fiber_two"
var baseline: bool = false
var failures: int = 0
var checks: Array = []
var evidence: Dictionary = {}
var output_path: String = ""
var case_name: String = ""
var started: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String, pending_policy: bool = false) -> bool:
	var status: String = "PASS" if ok else "BASELINE_GAP" if baseline and pending_policy else "FAIL"
	checks.append({"label": label, "ok": ok, "status": status})
	print(status, " ", label)
	if not ok and not (baseline and pending_policy): failures += 1
	return ok

func write_report(stage: String) -> void:
	var f: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
	if f == null:
		push_error("Cannot write QA evidence to " + output_path)
		failures += 1
		return
	f.store_string(JSON.stringify({"suite": "QA_COMPANY_PROCUREMENT_PRIORITY", "stage": stage, "case": case_name, "mode": "baseline" if baseline else "candidate", "baseline_definition": "TIMING_FIXED_PRE_COMPANY_PRIORITY_CANDIDATE_NOT_OLD_SALES_CONTROL", "failures": failures, "checks": checks, "evidence": evidence, "elapsed_msec": Time.get_ticks_msec() - started, "limits": ["LEGAL_INITIAL_VARIANT_NOT_NATURAL_PRODUCT_SAVE", "ORIGINAL_FIRST_DAY_CLOCK_AUTOMATION_NOT_GUI", "ONE_WORLD_PER_PROCESS_NO_ENGINE_RUN_BY_AUTHOR", "PRIORITY_IS_EXPLICIT_OPERATING_POLICY_NOT_A_UNIVERSAL_ECONOMIC_LAW", "NO_LIVE_CASH_STOCK_RECIPE_OR_SIGNED_ORDER_MUTATION", "NO_INVENTED_REVENUE_AUTOMATIC_BORROWING_OR_SECOND_LEDGER", "BUDGET_IS_EXISTING_EXPLICIT_DEVELOPMENT_APPROPRIATION_NOT_HOST_DELEGATED_AUTHORITY_PROOF", "ONE_REAL_DAY_NO_SECOND_DAY_DELIVERY_PRODUCTION_OR_RESTORE_PROOF", "A_PLUS_B_COMPLETENESS_AND_RESERVED_VERSUS_UNRESERVED_WAGES_REQUIRE_SEPARATE_CASES", "SECTION_SIX_DIRECT_COST_AND_DEMAND_DECAY_REQUIRE_SEPARATE_CASES"]}, "\t"))
	f.close()

func site_row(cfg: Dictionary, id: String) -> Dictionary:
	for firm: Dictionary in cfg["firms"]:
		for site: Dictionary in firm["sites"]:
			if site["id"] == id: return site
	return {}

func firm_row(cfg: Dictionary, id: String) -> Dictionary:
	for firm: Dictionary in cfg["firms"]:
		if firm["id"] == id: return firm
	return {}

func replace_identifier(value: Variant, before: String, after: String) -> Variant:
	# Initial configuration only. Preserve integer/bool types and every reference.
	if value is String: return value.replace(before, after)
	if value is Array:
		var result: Array = []
		for item: Variant in value: result.append(replace_identifier(item, before, after))
		return result
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value:
			result[replace_identifier(key, before, after)] = replace_identifier(value[key], before, after)
		return result
	return value

func configuration(kind: String) -> Dictionary:
	var cfg: Dictionary = EconomyDevelopmentConfig.regional_template()
	cfg["case_id"] = "QA_COMPANY_PROCUREMENT_PRIORITY_LEGAL_INITIAL_VARIANT"
	for firm: Dictionary in cfg["firms"]:
		for site: Dictionary in firm["sites"]:
			site["targets"] = EconomySliceConfig.zero_stock(EconomySliceConfig.good_ids(cfg))
			if site["id"] != WEAVE: site["production_enabled"] = false
			# Avoid an unrelated same-owner internal surplus satisfying the target.
			if firm["id"] == TEXTILE: site["stock"] = EconomySliceConfig.zero_stock(EconomySliceConfig.good_ids(cfg))
	var weave: Dictionary = site_row(cfg, WEAVE)
	weave["targets"]["clothes"] = 4
	# Real recipe remains fiber2 -> clothes1, with one hour and existing capacity.
	# Four planned batches provide actual still-future recipe needs at minute1.
	site_row(cfg, FARM)["stock"]["fiber"] = 2 if kind == "budget_actual_two" else 12
	site_row(cfg, FARM)["prices"]["fiber"] = 4
	for operation: Dictionary in cfg["firm_operations"]:
		if operation["firm"] == TEXTILE: operation["manage_jobs"] = false
	for job: Dictionary in cfg["jobs"]:
		if job["id"] == JOB:
			job["wage_per_hour"] = 1
			job["hours"] = 1
			job["positions"] = 1
	# Finite initial household endowments isolate firm competition for one day.
	# They are never inserted into an already running world.
	for actor: Dictionary in cfg["actors"]:
		actor["stock"]["bread"] = 100
		actor["stock"]["clothes"] = 100
		actor["stock"]["soap"] = 100
	firm_row(cfg, TEXTILE)["cash"] = 80 if kind == "budget_actual_two" else 9
	if kind == "budget_actual_two":
		weave["targets"]["fiber"] = 10
		cfg["procurement_budgets"] = [{"id": BUDGET, "subject": TEXTILE, "root_authority": "development:qa_company:fiber_authority", "denomination": FormalLedgerState.DENOMINATION, "category": "goods:fiber", "start_minute": 0, "end_minute": 30 * 1440, "limit": 8, "carryover": "RETAIN_ORIGINAL_WINDOW", "priority": "EXISTING_ACTION_ORDER", "basis": "EXPLICIT_DEVELOPMENT_PROCUREMENT_AUTHORITY"}]
	else:
		var branch: Dictionary = site_row(cfg, BRANCH)
		branch["targets"]["bread"] = 1
		branch["prices"]["bread"] = 10
		site_row(cfg, BAKERY)["stock"]["bread"] = 10
		site_row(cfg, BAKERY)["prices"]["bread"] = 7
		var new_id: String = "site:regional_textile:a_optional" if kind == "priority_optional_first" else "site:regional_textile:z_optional"
		cfg = replace_identifier(cfg, BRANCH, new_id)
	return cfg

func source_messages(cfg: Dictionary, branch: String) -> Array:
	var result: Array = []
	for row: Dictionary in cfg["information"]:
		if row["actor"] in [WEAVE, branch, WORKER]: result.append(row.duplicate(true))
	return result

func matching_orders(e: EconomyR1Slice, destination: String, good: String) -> Array:
	var result: Array = []
	for order: Dictionary in e._orders.values():
		if order["buyer"] == TEXTILE and order["buyer_site"] == destination and order["good"] == good:
			result.append(order.duplicate(true))
	return result

func quantity(orders: Array) -> int:
	var result: int = 0
	for order: Dictionary in orders: result += int(order["quantity"]) - int(order["cancelled"])
	return result

func money_goods(e: EconomyR1Slice, b: WorldBuildResult) -> Dictionary:
	return {"ledger": b.world.ledger_state.snapshot(), "lots": e._lots.snapshot(), "orders": e._orders.duplicate(true), "budgets": e._budgets.snapshot()}

func accept_original_employment(e: EconomyR1Slice) -> void:
	var command: Dictionary = e._auto_command(WORKER, "apply", {"job_id": JOB}, "qa_company_known_recipe_labor")
	var result: Dictionary = e.submit_internal(WORKER, command)
	evidence["original_employment_action"] = {"command": command, "result": result}
	check(result.get("accepted", false), "Known original worker applies through the real employment entrypoint")
	evidence["original_employment_terms"] = e._contract_for(WORKER, JOB).duplicate(true)
	# No work is claimed and no wage paid before it is actually performed.
	# Future use of the contracted worker still needs normal scheduling/settlement.

func actual_commands(e: EconomyR1Slice, orders: Array) -> Array:
	var result: Array = []
	for order: Dictionary in orders:
		result.append(e._commands[order["action_id"]].duplicate(true))
	return result

func advance_first_day(b: WorldBuildResult) -> bool:
	# Original phase ordering creates plans, settles real work, then procures.
	# Stop exactly at the first midnight; no fabricated day-zero plan is saved.
	while b.world.game_clock.total_minutes() < 1440:
		var minutes: int = mini(60, 1440 - b.world.game_clock.total_minutes())
		if not check(b.simulation_step.advance_minutes(minutes).get("success", true), "Original clock advances toward first daily boundary"): return false
	return check(b.world.economy_r1.day == 1, "First real daily boundary completed")

func company_wages(e: EconomyR1Slice) -> Array:
	var rows: Array = []
	for wage: Dictionary in e._wages.values():
		if wage["employer"] == TEXTILE: rows.append(wage.duplicate(true))
	return rows

func verify_order_replay(e: EconomyR1Slice, b: WorldBuildResult, orders: Array) -> void:
	for order: Dictionary in orders:
		var source: Dictionary = e._commands[order["action_id"]]
		var command: Dictionary = source["envelope"]["command"].duplicate(true)
		var original: Dictionary = source["result"].duplicate(true)
		var before: Dictionary = money_goods(e, b)
		check(e.submit_internal(TEXTILE, command) == original and money_goods(e, b) == before, "Exact original order replay is idempotent without re-running a test-made procurement phase")


func verify_finite_intent_query(e: EconomyR1Slice, b: WorldBuildResult) -> void:
	if not e.has_method("_procurement_intents"): return
	var before: Dictionary = b.persistence.snapshot()
	var rows: Array = e.call("_procurement_intents")
	check(rows == e.call("_procurement_intents") and b.persistence.snapshot() == before, "Finite company intent query is deterministic and leaves the complete world unchanged")
	var original_slots: Array = []
	for site: String in e._site_ids():
		if not e._site_accepting(site) or e._firm_winding_down(e._owner(site)): continue
		for good: String in e._goods:
			if e._input_good(site, good): original_slots.append(e._owner(site))
	var actual_slots: Array = []
	var last: Dictionary = {}
	var ordered: bool = true
	for row: Dictionary in rows:
		actual_slots.append(row["firm"])
		if last.has(row["firm"]) and int(row["priority"]) < int(last[row["firm"]]): ordered = false
		last[row["firm"]] = int(row["priority"])
	check(actual_slots == original_slots, "Company reordering does not replace another enterprise's original world-turn slot")
	check(ordered, "Within each company existing responsibilities precede future recipe inputs and optional inventory")
	evidence["finite_intent_query"] = rows

func priority_case(e: EconomyR1Slice, b: WorldBuildResult, branch: String) -> void:
	accept_original_employment(e)
	var input_offer: Dictionary = e._offer(TEXTILE, UPSTREAM, "fiber", "edge:regional_local:lyon", FARM, WEAVE)
	var optional_offer: Dictionary = e._offer(TEXTILE, FOOD, "bread", "path:regional:paris:marseille", BAKERY, branch)
	var recipe: Dictionary = e._activity(WEAVE, "activity:regional_clothes")
	check(int(recipe["materials"]["fiber"]) == 2 and int(recipe["hours"]) == 1, "Real one-clothes batch requires fiber2 and one worked hour")
	check(int(input_offer["price"]) == 4 and int(input_offer["freight_per_unit"]) == 0 and int(input_offer["transport_quantity"]) >= 2, "Actual known local fiber2 costs8 and has available logistics")
	check(int(optional_offer["price"]) + int(optional_offer["freight_per_unit"]) == 9 and int(optional_offer["transport_quantity"]) >= 1, "Actual optional bread1 costs9 including both original freight legs")
	check(b.world.ledger_state.available_balance(e._account(TEXTILE)) == 9, "One original company account can fund only one alternative")
	check(company_wages(e).is_empty() and b.world.ledger_state.reserved_balance(e._account(TEXTILE)) == 0, "Initial fixture has no hidden incurred wage claim or existing reservation")
	var optional_need: Dictionary = e._input_need(branch, "bread")
	var optional_purpose: Dictionary = e._resale_replenishment_observation(branch, "bread", optional_offer, 1, optional_need)
	check(int(optional_purpose["optional_quantity"]) == 1 and optional_purpose["optional_eligible"], "Optional branch replenishment is otherwise legally and economically eligible")
	var ids: Array = e._site_ids()
	check((ids.find(branch) < ids.find(WEAVE)) == (case_name == "priority_optional_first"), "Fixture proves selected branch identifier ordering before any procurement")
	evidence["before_original_day"] = {"minute": b.world.game_clock.total_minutes(), "day": e.day, "site_order": ids, "account": e._account(TEXTILE), "cash": 9, "initial_targets": e._spec["sites"][WEAVE]["targets"].duplicate(true), "optional_need": optional_need, "input_offer": input_offer, "optional_offer": optional_offer, "optional_purpose": optional_purpose, "recipe": recipe, "wages": company_wages(e), "work_queue": e._work_queue.duplicate(true), "phase_rule": "No _plan_firms or _procure_inputs calls from QA. The first original daily boundary creates and consumes its own plan.", "policy_under_test": "Prioritize one obtainable complete recipe input batch over discretionary branch resale. Cash9 can pay fiber2 at8 and one actually worked contracted hour at1. This is an explicit business policy, not a universal profitability claim.", "wage_terms": "One worker slot, one hour, wage1, original delay1. Apply is a real contract; no QA work claim is inserted. Record any original scheduler work and debt below."}
	write_report("FIXTURE_READY_BEFORE_ORIGINAL_DAY")
	if not advance_first_day(b): return
	verify_finite_intent_query(e, b)
	var inputs: Array = matching_orders(e, WEAVE, "fiber")
	var optional: Array = matching_orders(e, branch, "bread")
	var actual_need: Dictionary = e._input_need(WEAVE, "fiber")
	evidence["outcome"] = {"minute": b.world.game_clock.total_minutes(), "day": e.day, "input_orders": inputs, "optional_orders": optional, "input_commands": actual_commands(e, inputs), "optional_commands": actual_commands(e, optional), "available_cash": b.world.ledger_state.available_balance(e._account(TEXTILE)), "reserved_cash": b.world.ledger_state.reserved_balance(e._account(TEXTILE)), "real_day_plan": e._plans[WEAVE].duplicate(true), "actual_input_need": actual_need, "realized_production": e._physical_totals[WEAVE].duplicate(true), "work_records": e._work_records.duplicate(true), "wages": company_wages(e), "next_work_queue": e._work_queue.duplicate(true)}
	check(int(actual_need["timing_projection"]["uncovered_future_quantity"]) + int(actual_need["accepted_responsibility"]) >= 2, "Original day created a real still-future recipe need")
	check(quantity(inputs) == 2 and quantity(optional) == 0, "Original daily procurement chooses actual fiber2 and defers optional bread independent of site ID", true)
	check(b.world.ledger_state.available_balance(e._account(TEXTILE)) == 1, "Choice preserves the remaining one unit for contracted actual labor", true)
	check(int(e._stocks[WEAVE]["fiber"]) == 0, "Accepted material is incoming responsibility, never free instantaneous stock")
	verify_order_replay(e, b, inputs + optional)
	evidence["interpretation"] = "Run both priority cases separately. Normalize only a_optional/z_optional identifiers when comparing. A baseline order difference establishes an ID-order sensitivity; it is not evidence of bankruptcy, delivered production, or net profit. Plans and claims now come from the completed original first day."

func budget_case(e: EconomyR1Slice, b: WorldBuildResult) -> void:
	var need: Dictionary = e._input_need(WEAVE, "fiber")
	var offer: Dictionary = e._offer(TEXTILE, UPSTREAM, "fiber", "edge:regional_local:lyon", FARM, WEAVE)
	var choice: Dictionary = e._input_candidate_need(need, e._input_offer_arrival(offer), int(offer["transport_quantity"]), e._input_offer_batch_size(offer))
	var gross_components: Array[Dictionary] = e._budget_plan(TEXTILE, offer["denomination"], "fiber", offer["route_legs"], 10, true, int(offer["price"]))
	var executable_components: Array[Dictionary] = e._budget_plan(TEXTILE, offer["denomination"], "fiber", offer["route_legs"], 2, true, int(offer["price"]))
	check(int(need["regular_quantity"]) == 10, "Actual planned stock need is ten, not a fabricated query-only quantity")
	check(int(offer["transport_quantity"]) == 2 and int(e._stocks[FARM]["fiber"]) == 2, "Real source owns only two uncommitted fiber units")
	check(int(choice["quantity"]) == 2, "Current original timing decision already truncates desired10 to actual2 before funding")
	check(not e._budget_ready(gross_components) and e._budget_ready(executable_components), "Original appropriation rejects gross40 and permits the actual8 commitment")
	var before_query: Dictionary = money_goods(e, b)
	check(e._fund_procurement(TEXTILE, offer, int(choice["quantity"])) == 2, "Original bounded funding call permits quantity2")
	check(money_goods(e, b) == before_query, "Budget readiness check does not create commitments or money")
	evidence["before_original_day"] = {"minute": b.world.game_clock.total_minutes(), "day": e.day, "initial_stock_target_need": need, "offer": offer, "choice": choice, "gross_ten_components_diagnostic_only": gross_components, "actual_two_components": executable_components, "rule": e._budgets.rule(BUDGET), "funding_order": "The first normal day runs _plan_firms -> _procure_inputs -> _input_candidate_need(capacity=offer.transport_quantity) -> per-good limit -> _fund_procurement -> _accept -> _admit -> original budget commit"}
	write_report("FIXTURE_READY_BEFORE_ORIGINAL_DAY")
	if not advance_first_day(b): return
	var orders: Array = matching_orders(e, WEAVE, "fiber")
	check(orders.size() == 1 and quantity(orders) == 2, "Original NPC procurement actually accepts the legally executable two units")
	var claims: Array = []
	for order: Dictionary in orders:
		var command: Dictionary = e._commands[order["action_id"]]["envelope"]["command"]
		check(int(command["payload"]["quantity"]) == 2, "Recorded real buy command requests2 rather than impossible10")
		for claim: Dictionary in e._budgets.claims.get(order["id"], []):
			if claim["rule_id"] == BUDGET: claims.append(claim.duplicate(true))
	check(claims.size() == 1 and int(claims[0]["total"]) == 8 and int(claims[0]["spent"]) == 0, "Original cumulative budget claims exactly8 and invents no delivered spending")
	check(not e._budget_ready(e._budget_plan(TEXTILE, offer["denomination"], "fiber", offer["route_legs"], 1, true, 4)), "Committed8 exhausts the original budget window for another unit")
	check(b.world.ledger_state.reserved_balance(e._account(TEXTILE)) == 8 and int(e._stocks[WEAVE]["fiber"]) == 0, "Original Ledger reserves8 while materials remain undelivered")
	verify_order_replay(e, b, orders)
	evidence["outcome"] = {"minute": b.world.game_clock.total_minutes(), "day": e.day, "orders": orders, "commands": actual_commands(e, orders), "claims": claims, "budget_snapshot": e._budgets.snapshot(), "reserved_cash": b.world.ledger_state.reserved_balance(e._account(TEXTILE)), "physical_fiber": e._stocks[WEAVE]["fiber"], "real_day_plan": e._plans[WEAVE].duplicate(true), "wages": company_wages(e)}
	evidence["interpretation"] = "EXPECTED_CURRENT_PASS_REGRESSION. _fund_procurement still checks its supplied quantity in full, but the current operating-input caller supplies actual2. Rejecting a deliberately direct gross10 call is not evidence that this NPC path remains broken."

func verify_normalized_complete_restore(b: WorldBuildResult) -> void:
	var original: Dictionary = b.persistence.snapshot()
	var restored: WorldBuildResult = FormalPersistence.new().restore_candidate(original)
	check(restored.success, "Complete original world restores with normal initial administrative state: " + str(restored.error))
	if restored.success:
		check(restored.persistence.snapshot() == original, "All restored snapshot fields equal the original without geographical or financial exemptions")
	check(b.persistence.snapshot() == original, "Detached candidate restoration never changes the live original world")

func run() -> void:
	started = Time.get_ticks_msec()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 3 or not args[0].is_absolute_path() or args[1] not in ["baseline", "candidate"] or args[2] not in ["priority_optional_first", "priority_input_first", "budget_actual_two"]:
		push_error("Usage: -- /absolute/output.json baseline|candidate priority_optional_first|priority_input_first|budget_actual_two")
		quit(2)
		return
	output_path = args[0]
	baseline = args[1] == "baseline"
	case_name = args[2]
	var branch: String = "site:regional_textile:a_optional" if case_name == "priority_optional_first" else "site:regional_textile:z_optional" if case_name == "priority_input_first" else BRANCH
	var cfg: Dictionary = configuration(case_name)
	evidence = {"fixture_design_date_utc": "2026-10-19", "run_started_at_utc": Time.get_datetime_string_from_system(true), "fixture_clock": "Start day0 minute1 with configured delivery_day0 supplier/job receipts, then run original clock exactly to day1 minute1440. No direct planning or procurement phase calls.", "source_hashes": {"economy_r1_slice.gd": FileAccess.get_sha256("res://scripts/world/economy_r1_slice.gd"), "economy_procurement_budget.gd": FileAccess.get_sha256("res://scripts/world/economy_procurement_budget.gd"), "qa_script": FileAccess.get_sha256("res://merchant/qa_company_procurement_priority.gd")}, "source_interfaces": ["_offer: transport_quantity=min(real seller stock, current route availability)", "_input_candidate_need: returned quantity<=capacity", "_procure_inputs: bounded choice precedes _fund_procurement", "_fund_procurement: original budget and permission checks remain authoritative"], "configuration_sha256": JSON.stringify(cfg).sha256_text(), "initial_configuration": cfg, "initial_supplier_and_job_messages": source_messages(cfg, branch), "branch_identifier": branch}
	print("QA_COMPANY_FIXTURE_BEFORE_BOOTSTRAP ", JSON.stringify({"date": evidence["fixture_design_date_utc"], "case": case_name, "configuration_sha256": evidence["configuration_sha256"], "messages": evidence["initial_supplier_and_job_messages"]}))
	write_report("FIXTURE_DECLARED_BEFORE_BOOTSTRAP")
	if not check(EconomySliceConfig.valid(cfg), "Declared finite initial configuration is valid"):
		write_report("INVALID_FIXTURE")
		quit(1)
		return
	var built: WorldBuildResult = WorldBootstrap.new().build(null, [], [], FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT, false, {"format": "HOST_REGION_SELECTION", "person_ids": [], "select_people_at_sites": false, "configuration": cfg})
	if not check(built.success, "Original WorldBootstrap accepts fixture: " + str(built.error)):
		write_report("BOOTSTRAP_FAILED")
		quit(1)
		return
	check(built.simulation_step.advance_minutes(1).get("success", true), "Original clock activates known day-zero information")
	var e: EconomyR1Slice = built.world.economy_r1
	if case_name == "budget_actual_two": budget_case(e, built)
	else: priority_case(e, built, branch)
	write_report("FINISHED")
	print("QA_COMPANY_PROCUREMENT_PRIORITY ", case_name, " failures=", failures, " elapsed_msec=", Time.get_ticks_msec() - started)
	quit(1 if failures > 0 else 0)

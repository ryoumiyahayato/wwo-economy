extends SceneTree
## First feedback batch: one labelled, finite legal opening per process.
## Usage: -- baseline|candidate LABEL OUTPUT.json
## LABEL: admit_logistics | admit_stock | admit_cash | admit_multiple |
##        purpose_bread | purpose_fiber | purpose_split
## No live stock/cash injection, modified signed contracts, or virtual delivery.
## The parent runs each label serially with an external 60-second timeout.
const Opening = preload("res://merchant/merchant_opening.gd")
const UPSTREAM = "firm:regional_upstream"
const FARM = "site:regional_upstream:lyon"
const TEXTILE = "firm:regional_textile"
const WEAVE = "site:regional_textile:lyon"
const FOOD = "firm:regional_food"
const BAKERY = "site:regional_food:paris"
const FOOD_STORE = "site:regional_food:lyon"
const ADMIT_ROUTE = "edge:regional:lyon:paris"
const BREAD_ROUTE = "edge:regional:paris:lyon"
var baseline: bool = false
var failures: int = 0
var observations: Dictionary = {}
var checks: Array = []
var started_msec: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String, policy: bool = false) -> bool:
	var status: String = "PASS" if ok else "BASELINE_GAP" if baseline and policy else "FAIL"
	checks.append({"label": label, "ok": ok, "status": status})
	print(status, " ", label)
	if not ok and not (baseline and policy): failures += 1
	return ok

func site_row(cfg: Dictionary, id: String) -> Dictionary:
	for firm: Dictionary in cfg["firms"]:
		for site: Dictionary in firm["sites"]:
			if site["id"] == id: return site
	return {}

func firm_row(cfg: Dictionary, id: String) -> Dictionary:
	for firm: Dictionary in cfg["firms"]:
		if firm["id"] == id: return firm
	return {}

func configured_world(cfg: Dictionary) -> WorldBuildResult:
	var built: WorldBuildResult = WorldBootstrap.new().build(null, [], [], FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT, false, {"format": "HOST_REGION_SELECTION", "person_ids": [], "select_people_at_sites": true, "configuration": cfg})
	if not check(built.success, "Legal original WorldBootstrap opening: " + str(built.error)): return built
	check(built.simulation_step.advance_minutes(1).get("success", true), "Original GameClock activates opening and delivered day-zero knowledge")
	return built

func command_for(e: EconomyR1Slice, buyer: String, buyer_site: String, seller: String, seller_site: String, good: String, quantity: int, route: String, suffix: String) -> Dictionary:
	var offer: Dictionary = e._offer(buyer, seller, good, route, seller_site, buyer_site)
	observations["quote_" + suffix] = offer.duplicate(true)
	return e._auto_command(buyer, "buy", {"quote_id": offer["quote_id"], "seller": seller, "seller_site": seller_site, "buyer_site": buyer_site, "good": good, "quantity": quantity, "denomination": offer["denomination"], "max_price": int(offer["price"]), "path_id": route, "need_by_day": e.day + 4}, "batch_one:" + suffix)

func request_record(e: EconomyR1Slice, seller_site: String, good: String, action_id: String) -> Dictionary:
	for row: Dictionary in e._request_window.get(seller_site + "|" + good, []):
		if row.get("action_id") == action_id: return row.duplicate(true)
	return {}

func canonical_money_goods(e: EconomyR1Slice, built: WorldBuildResult) -> Dictionary:
	return {"ledger": built.world.ledger_state.snapshot(), "lots": e._lots.snapshot(), "orders": e._orders.duplicate(true), "stocks": e._stocks.duplicate(true), "transport": e._transport.duplicate(true)}

func verify_restore(built: WorldBuildResult) -> void:
	var snapshot: Dictionary = built.persistence.snapshot()
	var restored: WorldBuildResult = FormalPersistence.new().restore_candidate(snapshot)
	check(restored.success,"Full candidate restore accepts original money/goods and sourced request observations: "+str(restored.error))
	if restored.success:
		var again: Dictionary = restored.persistence.snapshot()
		for key: String in ["economy_native","ledger","total_minutes"]: check(snapshot[key]==again[key],"Restore preserves authority section "+key)
	if baseline: return
	var bad := snapshot.duplicate(true)
	var corrupted := false
	for rows: Array in bad["economy_native"]["request_window"].values():
		for row: Dictionary in rows:
			if row.has("limit_observation"):
				row["limit_observation"]["unmet_quantity"] += 1
				corrupted=true;break
		if corrupted: break
	if corrupted:
		var rejected: WorldBuildResult = FormalPersistence.new().restore_candidate(bad)
		check(not rejected.success,"Malformed classified quantity cannot restore into a candidate")
		check(snapshot==built.persistence.snapshot(),"Rejected restore never replaces the live authority")


func admit_case(label: String) -> void:
	var cfg: Dictionary = Opening.regional_configuration()
	cfg["case_id"] = "QA_ECONOMY_BATCH_ONE_" + label.to_upper()
	firm_row(cfg, Opening.FIRM)["cash"] = 0 if label == "admit_cash" else 400
	site_row(cfg, FARM)["stock"]["grain"] = 0 if label in ["admit_stock", "admit_multiple"] else 10
	site_row(cfg, FARM)["stock"]["fiber"] = 10
	for route: Dictionary in cfg["routes"]:
		if route["id"] == ADMIT_ROUTE: route["capacity"] = 5
	observations["initial_configuration"] = {"seller_grain": site_row(cfg, FARM)["stock"]["grain"], "buyer_cash": firm_row(cfg, Opening.FIRM)["cash"], "route_capacity": 5, "requested": 5, "route_zero_basis": "REAL_ACCEPTED_FIBER_ORDER_CONSUMES_FIRST_EDGE_CAPACITY" if label in ["admit_logistics", "admit_multiple"] else "UNUSED_LEGAL_ROUTE"}
	var built: WorldBuildResult = configured_world(cfg)
	if not built.success: return
	var e: EconomyR1Slice = built.world.economy_r1
	if label in ["admit_logistics", "admit_multiple"]:
		var blocker: Dictionary = command_for(e, Opening.FIRM, Opening.SITE, UPSTREAM, FARM, "fiber", 5, ADMIT_ROUTE, "occupy_route")
		var occupied: Dictionary = e.submit_internal(Opening.FIRM, blocker)
		observations["capacity_reserving_order"] = occupied
		if not check(occupied.get("accepted", false) and int(occupied.get("quantity", 0)) == 5, "Real separate fiber purchase legally occupies all five route units"): return
	var route: Dictionary = e._route_for(Opening.FIRM, UPSTREAM, ADMIT_ROUTE, Opening.SITE, FARM)
	var available: int = e._route_available(route)
	var expected_route: int = 0 if label in ["admit_logistics", "admit_multiple"] else 5
	if not check(available == expected_route, "Target request sees exact current route availability"): return
	var request: Dictionary = command_for(e, Opening.FIRM, Opening.SITE, UPSTREAM, FARM, "grain", 5, ADMIT_ROUTE, label)
	var before: Dictionary = canonical_money_goods(e, built)
	var outcome: Dictionary = e.submit_internal(Opening.FIRM, request)
	var record: Dictionary = request_record(e, FARM, "grain", request["action_id"])
	observations.merge({"outcome": outcome, "request_record": record, "seller_free_stock": int(e._stocks[FARM]["grain"]) - e._committed(FARM, "grain"), "route_available": available, "production_pressure": e._received_pressure(FARM, "grain")})
	check(not outcome.get("accepted", false), "Target five-unit purchase does not transact")
	check(before == canonical_money_goods(e, built), "Rejected target changes no money, lots, orders, physical stocks, or transport")
	check(not record.is_empty() and int(record.get("quantity", 0)) == 5, "Original buy entry records the effective five-unit request")
	var limit: Dictionary = record.get("limit_observation", {})
	var caps: Dictionary = limit.get("caps", {})
	var refused: Dictionary = limit.get("refused", {})
	check(not limit.is_empty(), "Request retains sourced limiting dimensions", true)
	check(int(limit.get("accepted_quantity", -1)) == 0 and int(limit.get("unmet_quantity", -1)) == 5, "Accepted and unmet quantities form the bounded original request", true)
	var refused_total: int = 0
	for quantity: Variant in refused.values():
		if typeof(quantity) == TYPE_INT: refused_total += int(quantity)
	check(refused_total <= 5, "Mutually exclusive refusal quantities never exceed requested five", true)
	if label == "admit_logistics":
		check(int(record.get("physical_unmet", -1)) == 0 and e._received_pressure(FARM, "grain") == 0, "Pure logistics refusal contributes no seller-stock production pressure", true)
		check(int(caps.get("seller_stock", -1)) >= 5 and int(caps.get("logistics", -1)) == 0 and int(refused.get("logistics", -1)) == 5, "Stock10 route0 is specifically a five-unit logistics limitation", true)
	elif label == "admit_stock":
		check(int(record.get("physical_unmet", -1)) == 5 and int(record.get("cash_refused", -1)) == 0 and e._received_pressure(FARM, "grain") == 5, "Stock0 with transport and purchasing power is genuine supplier shortage", true)
		check(int(caps.get("seller_stock", -1)) == 0 and int(caps.get("logistics", -1)) >= 5, "Supplier shortage preserves distinct adequate logistics cap", true)
	elif label == "admit_cash":
		check(int(record.get("physical_unmet", -1)) == 0 and int(record.get("cash_refused", -1)) == 5 and e._received_pressure(FARM, "grain") == 0, "Cash0 is known purchasing-power rejection with no seller shortage", true)
		check(int(caps.get("cash", -1)) == 0 and int(caps.get("seller_stock", -1)) >= 5 and int(caps.get("logistics", -1)) >= 5, "Cash limitation is a quantity cap rather than a disclosed private balance", true)
	else:
		check(int(caps.get("seller_stock", -1)) == 0 and int(caps.get("logistics", -1)) == 0, "Simultaneous stock and transport constraints both retain their source", true)
		check(e._received_pressure(FARM, "grain") <= 5, "Simultaneous constraints do not multiply production pressure", true)
	var replay_before: Dictionary = e.snapshot()
	check(e.submit_internal(Opening.FIRM, request) == outcome and replay_before == e.snapshot(), "Exact action replay is idempotent including request observations")
	var retry: Dictionary = request.duplicate(true)
	retry["action_id"] = str(request["action_id"]) + ":retry_same_need"
	e.submit_internal(Opening.FIRM, retry)
	var rows: Array = e._request_window.get(FARM + "|grain", [])
	var same_need_rows: int = 0
	var pressure: int = 0
	for row: Dictionary in rows:
		if row.get("buyer") == Opening.SITE and int(row.get("need_by_day", -1)) == e.day + 4:
			same_need_rows += 1
			pressure += int(row.get("physical_unmet", 0))
	check(same_need_rows == 1 and pressure <= 5, "New action retry of this same buyer and need does not duplicate demand")
	check(before == canonical_money_goods(e, built), "Repeated rejection cannot mint revenue or change goods")
	observations["after_retry_records"] = rows.duplicate(true)
	if label=="admit_multiple": verify_restore(built)

func add_initial_supplier(cfg: Dictionary, site: String, supplier: String) -> void:
	var row: Dictionary = site_row(cfg, site)
	if supplier not in row["suppliers"]: row["suppliers"].append(supplier)
	for notice: Dictionary in cfg["information"]:
		if notice["actor"] == site and notice["kind"] == "supplier" and notice["candidate"] == supplier:
			notice["delivery_day"] = 0
			return
	cfg["information"].append({"actor": site, "kind": "supplier", "candidate": supplier, "delivery_day": 0})

func purpose_observation(e: EconomyR1Slice, good: String, offer: Dictionary, requested: int, need: Dictionary) -> Dictionary:
	# Baseline has exactly three arguments. Candidate adds requested and need.
	# Keep this adaptation in one place, without fabricating any result fields.
	var args: Array = [WEAVE, good, offer]
	for method: Dictionary in e.get_method_list():
		if method["name"] != "_resale_replenishment_observation": continue
		var count: int = method.get("args", []).size()
		if count >= 4: args.append(requested)
		if count >= 5: args.append(need)
		break
	return e.callv("_resale_replenishment_observation", args)

func orders_for(e: EconomyR1Slice, buyer_site: String, good: String) -> Array:
	var found: Array = []
	for order: Dictionary in e._orders.values():
		if order["buyer_site"] == buyer_site and order["good"] == good:
			found.append(order.duplicate(true))
	return found

func ordered_quantity(orders: Array) -> int:
	var total: int = 0
	for order: Dictionary in orders: total += int(order["quantity"]) - int(order["cancelled"])
	return total

func partial_retry_case() -> void:
	var cfg: Dictionary = Opening.regional_configuration()
	cfg["case_id"]="QA_CLASSIFIED_PARTIAL_RETRY"
	site_row(cfg,FARM)["stock"]["grain"]=2
	firm_row(cfg,Opening.FIRM)["cash"]=400
	for route: Dictionary in cfg["routes"]:
		if route["id"]==ADMIT_ROUTE: route["capacity"]=5
	var built := configured_world(cfg)
	if not built.success: return
	var e: EconomyR1Slice=built.world.economy_r1
	var first := command_for(e,Opening.FIRM,Opening.SITE,UPSTREAM,FARM,"grain",5,ADMIT_ROUTE,"partial_first")
	var accepted: Dictionary=e.submit_internal(Opening.FIRM,first)
	if not check(accepted.get("accepted",false) and accepted.get("quantity")==2,"Original admission actually accepts two of five"): return
	var after_first:=canonical_money_goods(e,built)
	var second:=command_for(e,Opening.FIRM,Opening.SITE,UPSTREAM,FARM,"grain",3,ADMIT_ROUTE,"partial_retry")
	var refused: Dictionary=e.submit_internal(Opening.FIRM,second)
	check(not refused.get("accepted",false),"Retry of remaining three has no new source stock")
	check(e._received_pressure(FARM,"grain")==3,"Latest same-need remainder is three, never first3 plus retry3",true)
	check(after_first==canonical_money_goods(e,built),"Rejected remainder does not change accepted order or funds")
	var raw: Array=e._request_window.get(FARM+"|grain",[])
	check(raw.size()==2,"Actual accepted order history and latest unresolved request both survive",true)
	var view: Dictionary=e._site_operating_view(FARM)
	for row: Dictionary in view["received_requests"]["grain"]:
		check(not row.get("limit_observation",{}).get("caps",{}).has("cash"),"Supplier view does not disclose an unused private affordability cap",true)
	var distinct:=command_for(e,Opening.FIRM,Opening.SITE,UPSTREAM,FARM,"grain",2,ADMIT_ROUTE,"different_need_boundary")
	distinct["payload"]["need_by_day"]=e.day+5
	e.submit_internal(Opening.FIRM,distinct)
	check(e._received_pressure(FARM,"grain")==5,"Distinct real need boundaries remain independent",true)
	observations={"first":accepted,"retry":refused,"raw_request_records":raw.duplicate(true),"seller_view":view["received_requests"]["grain"],"pressure_after_distinct":e._received_pressure(FARM,"grain")}
	verify_restore(built)


func purpose_case(label: String) -> void:
	var cfg: Dictionary = Opening.regional_configuration()
	cfg["case_id"] = "QA_ECONOMY_BATCH_ONE_" + label.to_upper()
	# Legal finite opening isolates this procurement decision. Existing recipes,
	# real transport, upstream prices, account owners and original inputs remain.
	for firm: Dictionary in cfg["firms"]:
		for site: Dictionary in firm["sites"]:
			for good: String in site["targets"]: site["targets"][good] = 0
			if site["id"] != WEAVE: site["production_enabled"] = false
			if firm["id"]==TEXTILE and site["id"]!=WEAVE: site["stock"]["bread"]=0 # No cheaper real internal alternative in this explicit opening.
	firm_row(cfg, TEXTILE)["cash"] = 500
	var weave: Dictionary = site_row(cfg, WEAVE)
	weave["stock"]["bread"] = 0
	weave["stock"]["clothes"] = 0
	weave["stock"]["fiber"] = 0 if label == "purpose_fiber" else 100
	weave["targets"]["bread"] = 4
	weave["targets"]["clothes"] = 5
	weave["prices"]["bread"] = 8
	site_row(cfg, BAKERY)["stock"]["bread"] = 10
	site_row(cfg, BAKERY)["prices"]["bread"] = 9
	add_initial_supplier(cfg, WEAVE, FOOD + "|bread|" + BAKERY)
	var contract_id: String = "supply:qa_batch_one:bread_one"
	if label == "purpose_split":
		site_row(cfg,FOOD_STORE)["stock"]["bread"]=0
		site_row(cfg,FOOD_STORE)["targets"]["bread"]=1 # Real buyer need permits the finite one-unit contract.
		# Genuine one-unit future responsibility with a four-unit optional buffer.
		# This is a configured offer; it is accepted through the original command.
		cfg["supply_contracts"] = {"id": contract_id, "buyer": FOOD, "buyer_site": FOOD_STORE, "supplier": TEXTILE, "supplier_site": WEAVE, "good": "bread", "quantity": 1, "days": 10, "premium": 1, "competitor": Opening.FIRM, "competitor_site": Opening.SITE, "competitor_target": 1, "competitor_batch": 1, "basis": "EXPLICIT_DEVELOPMENT_CITY_SUPPLY"}
		add_initial_supplier(cfg, FOOD_STORE, TEXTILE + "|bread|" + WEAVE)
	observations["initial_configuration"] = {"mixed_site": WEAVE, "activity": "activity:regional_clothes", "recipe_fiber_per_batch": 2, "recipe_bread_per_batch": 0, "own_bread_price": 8, "source_bread_price": 9, "original_cross_city_freight": 1, "bread_opening_stock": 0, "optional_buffer_target": 4, "accepted_responsibility": 1 if label == "purpose_split" else 0, "other_sites": "INITIAL_TARGETS_ZERO_PRODUCTION_DISABLED;OWN_OTHER_BREAD_ZERO;CONTRACT_BUYER_TARGET1_STOCK0_FOR_SPLIT"}
	var built: WorldBuildResult = configured_world(cfg)
	if not built.success: return
	var e: EconomyR1Slice = built.world.economy_r1
	var original_contract: Dictionary = {}
	if label == "purpose_split":
		var offered: Dictionary = e._supply.offer(contract_id)
		observations["real_supply_offer"] = offered.duplicate(true)
		if not check(offered.get("ready", false), "Configured real one-bread supplier responsibility is funded and open"): return
		var accept: Dictionary = e._auto_command(TEXTILE, "accept_supply_contract", {"contract_id": contract_id, "price": offered["price"]}, "batch_one:real_supply_acceptance")
		var accepted: Dictionary = e.submit_internal(TEXTILE, accept)
		observations["real_supply_acceptance"] = accepted.duplicate(true)
		if not check(accepted.get("accepted", false), "Original supplier command accepts one real bread obligation"): return
		original_contract = e._supply.records[contract_id].duplicate(true)
		check(int(original_contract["quantity"]) == 1 and int(original_contract["allocated"]) == 0, "One accepted unit has not been fabricated as a child delivery")
	e._plan_firms()
	var good: String = "fiber" if label == "purpose_fiber" else "bread"
	var requested: int = 2 if label == "purpose_fiber" else 5 if label == "purpose_split" else 4
	var seller: String = UPSTREAM if good == "fiber" else FOOD
	var seller_site: String = FARM if good == "fiber" else BAKERY
	var route: String = "edge:regional_local:lyon" if good == "fiber" else BREAD_ROUTE
	var offer: Dictionary = e._offer(TEXTILE, seller, good, route, seller_site, WEAVE)
	if not check(typeof(offer.get("price")) == TYPE_INT and int(offer.get("transport_quantity", 0)) > 0, "Real known source has stock and legal transport"): return
	var recipe: Dictionary = e._activity(WEAVE, "activity:regional_clothes")
	check(int(recipe["materials"]["fiber"]) == 2 and int(recipe["materials"]["bread"]) == 0, "The same active clothes recipe consumes fiber and never bread")
	if good == "bread":
		check(int(offer["price"]) + int(offer["freight_per_unit"]) == 10 and e._price(WEAVE, "bread") == 8, "Actual known bread landed10 is above own resale8")
	var need: Dictionary = e._input_need(WEAVE, good)
	var read_before: Dictionary = e.snapshot()
	var observation: Dictionary = purpose_observation(e, good, offer, requested, need)
	var candidate_args: Array = [WEAVE,good,int(need["need_by_day"]),requested]
	for method: Dictionary in e.get_method_list():
		if method["name"]=="_input_offers" and method.get("args",[]).size()>=5: candidate_args.append(need); break
	var candidates: Array = e.callv("_input_offers",candidate_args)
	check(read_before == e.snapshot(), "Purpose and candidate queries are read-only")
	var matching: Array = []
	for candidate: Dictionary in candidates:
		if candidate["seller_site"] == seller_site and candidate["route_id"] == route: matching.append(candidate.duplicate(true))
	observations.merge({"offer": offer, "need_before": need, "input_good_before": e._input_good(WEAVE, good), "purpose_observation": observation, "matching_input_candidates": matching, "recipe": recipe.duplicate(true)})
	if label == "purpose_bread":
		check(observation.get("applicable", false) and not observation.get("eligible", true), "Mixed production site rejects optional loss-making bread by this good's use", true)
		check(matching.is_empty(), "Original input-offer consumer excludes rejected optional bread", true)
		observations["baseline_caution"] = "Old mixed-site _input_good(bread) is false: this fixture proves an observation/filter gap, not a previously executed natural wrong purchase."
	elif label == "purpose_fiber":
		check(observation.get("eligible", false), "Real fiber recipe input remains eligible under its own purpose", true)
		check(not matching.is_empty(), "Original input-offer consumer retains the executable recipe input", true)
	else:
		check(int(observation.get("protected_quantity", -1)) == 1 and int(observation.get("optional_quantity", -1)) == 4, "Requested five units split into actual responsibility1 and optional4", true)
		check(int(observation.get("quantity_limit", -1)) == 1 and observation.get("eligible", false) and not observation.get("optional_eligible", true), "Protected responsibility1 survives while costly optional4 is refused", true)
		check(not matching.is_empty(), "Original procurement retains a bounded source for actual responsibility", true)
	# Use the original planning and procurement entry points, never a test-made
	# acceptance to pretend the new strategy adopted its observation.
	e._procure_inputs()
	var actual_orders: Array = orders_for(e, WEAVE, good)
	observations["actual_procurement_orders"] = actual_orders.duplicate(true)
	observations["need_after"] = e._input_need(WEAVE, good)
	if label == "purpose_bread":
		check(actual_orders.is_empty(), "Original procurement places no optional overpriced bread order")
	elif label == "purpose_fiber":
		check(ordered_quantity(actual_orders) > 0, "Original procurement actually reserves and orders required fiber", true)
	else:
		check(ordered_quantity(actual_orders) == 1, "Original procurement actually orders only the protected one bread", true)
		check(e._supply.records[contract_id] == original_contract, "Procurement does not rewrite accepted supply terms or fake fulfilment")
		var before_repeat: Array = actual_orders.duplicate(true)
		e._procure_inputs()
		check(orders_for(e, WEAVE, good) == before_repeat, "Accepted incoming coverage prevents a second same-need bread purchase", true)
		check(e._supply.records[contract_id] == original_contract, "Repeat decision preserves old contract deadline price and funds source")
		# The narrow observer test above calls the original planner at opening
		# day zero. Such a procedural fixture is not a saveable native phase:
		# the real daily loop has not planned any sites yet. Advance the actual
		# clock to complete its first authoritative daily plan before restore.
		check(built.simulation_step.advance_minutes(1440).get("success",true),"Original next-day lifecycle replaces the procedural day-zero plan")
		check(ordered_quantity(orders_for(e,WEAVE,good))==1,"Normal daily procurement retains only the actual protected bread responsibility")
		observations["restore_boundary"]={"day":e.day,"minute":built.world.game_clock.total_minutes(),"basis":"ORIGINAL_CLOCK_AFTER_FIRST_DAILY_PLANNING"}
		verify_restore(built)
		observations["original_supply_contract"] = original_contract
		observations["supply_contract_after"] = e._supply.records[contract_id].duplicate(true)
	observations["final_goods_money"] = {"cash": built.world.ledger_state.balance(e._account(TEXTILE)), "available_cash": built.world.ledger_state.available_balance(e._account(TEXTILE)), "physical_stock": e._stocks[WEAVE].duplicate(true), "accepted_incoming": e._input_incoming_observation(WEAVE, good, e.day + 4)}

func run() -> void:
	started_msec = Time.get_ticks_msec()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 3 or args[0] not in ["baseline", "candidate"]:
		push_error("Usage: -- baseline|candidate LABEL OUTPUT.json")
		quit(2)
		return
	baseline = args[0] == "baseline"
	var label: String = args[1]
	if label in ["admit_logistics", "admit_stock", "admit_cash", "admit_multiple"]:
		admit_case(label)
	elif label in ["purpose_bread", "purpose_fiber", "purpose_split"]:
		purpose_case(label)
	elif label=="partial_retry":
		partial_retry_case()
	else:
		check(false, "Unknown QA label: " + label)
	var report: Dictionary = {"suite": "QA_ECONOMY_BATCH_ONE", "mode": args[0], "label": label, "failures": failures, "checks": checks, "observations": observations, "elapsed_msec": Time.get_ticks_msec() - started_msec, "limits": ["LEGAL_INITIAL_QA_VARIANT_NOT_NATURAL_PRODUCT_SAVE", "DOMAIN_AUTOMATION_NOT_GUI", "ONE_WORLD_PER_LABEL_WITH_LABELLED_RESTORE_CHECKS", "NO_LIVE_CASH_STOCK_OR_SIGNED_CONTRACT_MUTATION", "OUT_OF_SCOPE_HOUSEHOLD_TIMING_AND_SPLIT_SHIPMENTS_REQUIRE_SEPARATE_TIME_AWARE_QA", "BUYER_STORAGE_BUDGET_AUTHORITY_PRICE_LIMIT_AND_UNKNOWN_QUOTE_LIMITS_NOT_YET_TARGETED", "DIFFERENT_REAL_NEED_WINDOWS_TARGETED_ONLY_BY_PARTIAL_RETRY_LABEL", "EXISTING_BUYBACK_DELIVERY_LOCKED_PRICE_PAYMENT_RESTORE_USE_SEPARATE_SALES_QA"]}
	var file: FileAccess = FileAccess.open(args[2], FileAccess.WRITE)
	if file == null:
		check(false, "Cannot open report output")
	else:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("QA_ECONOMY_BATCH_ONE ", args[0], " ", label, " failures=", failures, " elapsed_msec=", Time.get_ticks_msec() - started_msec)
	quit(1 if failures > 0 else 0)

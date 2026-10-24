extends "res://merchant/qa_commercial_terms.gd"
const Consumer=preload("res://merchant/consumer_access_opening.gd")
func paid_publication() -> Dictionary:
	# The pre-existing paid fixture gives Lyon upstream knowledge of a Paris
	# publisher. It does not give that firm lawful Paris premises.
	var cfg: Dictionary=EconomyDevelopmentConfig.commercial_information_regional_template()
	var b: WorldBuildResult=build(cfg);var e: EconomyR1Slice=b.world.economy_r1
	var client: String="firm:regional_upstream";var site: String="site:regional_upstream:lyon"
	var actor: String=e.firm_manager_at(client,0)
	var payload: Dictionary={"firm":client,"payer":client,"offer_id":"service_offer:paris_local_publication","max_amount":3,"announcement":{"site_id":site,"kind":"GOODS","item":"grain","channel_id":"channel:development:paris_paid","valid_days":8}}
	var refused: Dictionary=e.submit(actor,e._auto_command(actor,"request_service",payload,"paid_nonlocal_source"))
	assert(not refused.accepted and refused.reason=="PUBLICATION_REQUIRES_LEGAL_LOCAL_OPERATING_SITE",str(refused))
	# Controlled local variant of that same service: existing Lyon provider,
	# existing worker, same fee, purchasing authority and budget. No grant.
	for facility: Dictionary in cfg.service_market.facilities:
		if facility.id=="facility:service:paris_publication":facility.site_id="site:regional_textile:lyon"
	for offer: Dictionary in cfg.service_market.offers:
		if offer.id==payload.offer_id:offer.job_ids=["job:regional_textile:lyon","job:regional_textile:lyon:support"]
	for channel: Dictionary in cfg.commercial_information.channels:
		if channel.id==payload.announcement.channel_id:
			channel.place_id="place:lyon";channel.recipients=["site:regional_food:lyon","cohort:stratified:lyon_skilled"];channel.recipient_limit=2
	b=build(cfg);e=b.world.economy_r1;actor=e.firm_manager_at(client,0)
	var stocks: Dictionary=e._stocks[site].duplicate()
	var before: int=b.world.ledger_state.available_balance(e._account(client))
	var accepted: Dictionary=e.submit(actor,e._auto_command(actor,"request_service",payload,"paid_local_original_service"))
	assert(accepted.get("accepted",false),str(accepted))
	assert(before-b.world.ledger_state.available_balance(e._account(client))==3)
	assert(e._stocks[site]==stocks,"Announcement moved sale goods")
	var c: Dictionary=e._service_market.contracts[accepted.service_id]
	var a: Dictionary=e._commercial.publications[c.announcement_id]
	assert(a.quote==accepted.observed_goods_quote and c.total==3 and a.released_minute==-1)
	exact_restore(b)
	for date: int in range(1,16):
		until(b,date*1440)
		if c.status=="COMPLETED":break
	assert(c.status=="COMPLETED" and c.paid==3 and c.earned==3 and not c.work.is_empty(),str(c))
	until(b,b.world.game_clock.total_minutes()+2*1440)
	var receipts: Array=[]
	for receipt: Dictionary in e._receipts.values():
		if receipt.get("announcement_id")==a.id:receipts.append(receipt.duplicate(true))
	assert(not receipts.is_empty(),"Paid publication never delivered its real message")
	exact_restore(b)
	var snapshot: Dictionary=b.persistence.snapshot();var forged: Dictionary=snapshot.duplicate(true)
	forged.economy_native.commercial_information.publications[a.id].quote.price+=1
	var bad: WorldBuildResult=FormalPersistence.new().restore_candidate(forged)
	assert(not bad.success and "original adopted price observation" in bad.error,bad.error)
	assert(b.persistence.snapshot()==snapshot)
	return {"scope":"CONTROLLED_LOCAL_SERVICE_CONFIGURATION_EXISTING_STOCK_CASH_LABOR_NOT_DEFAULT_F5","original_nonlocal_rejection":refused,"accepted":accepted,"publication":a.duplicate(true),"contract":c.duplicate(true),"receipts":receipts,"price_forgery_rejection":bad.error,"original_ledger_payments":b.world.ledger_state.own_transactions(client),"restored_exact":true}

func capital_case(window: bool) -> Dictionary:
	var cfg: Dictionary=Consumer.configuration("consumer_company_budget" if window else "consumer_reference")
	# Cash stress: larger finite trial at two already listed goods. Reintroduce
	# an explicit opening supplier address; no stock, money or need is added.
	cfg.operating_inventory.trial_units=10
	var food: Dictionary=Multi.site(cfg,"site:regional_food:lyon")
	food.targets.clothes=2;food.targets.soap=4
	var supplier: String="firm:regional_textile|clothes|site:regional_textile:lyon"
	food.suppliers.append(supplier)
	cfg.information.append({"actor":food.id,"kind":"supplier","candidate":supplier,"delivery_day":0})
	var b: WorldBuildResult=build(cfg);assert(Consumer.apply_condition(b.world,"consumer_company_budget" if window else "consumer_reference").accepted)
	var e: EconomyR1Slice=b.world.economy_r1
	until(b,7*1440)
	var days: Dictionary={}
	var ids: Array=e._orders_by_buyer.get("firm:regional_food",[]).duplicate()
	ids.sort_custom(func(a: String,z: String):return int(a.trim_prefix("order:"))<int(z.trim_prefix("order:")))
	for id: String in ids:
		var order: Dictionary=e._orders[id]
		var dec: Dictionary=e._commands[order.action_id].result.get("decision",{})
		var resale: Dictionary=dec.get("replenishment",{})
		if order.kind!="SALE" or not resale.has("optional_cash_budget"):continue
		var amount: int=maxi(0,int(order.quantity)-int(resale.protected_quantity))*(int(order.price)+e._freight(order.route_legs))
		var date: String=str(order.accepted_day)
		if not days.has(date):days[date]={"first_ceiling":dec.get("company_cash_window",{}).get("ceiling",resale.optional_cash_budget),"committed_optional_cost":0,"orders":[]}
		days[date].committed_optional_cost+=amount;days[date].orders.append({"order":id,"good":order.good,"buyer_site":order.buyer_site,"quantity":order.quantity,"cost":amount,"decision":dec})
	var exceeded: bool=false
	for row: Dictionary in days.values():
		exceeded=exceeded or int(row.committed_optional_cost)>int(row.first_ceiling)
		if window:assert(int(row.committed_optional_cost)<=int(row.first_ceiling),str(row))
	exact_restore(b)
	return {"window":window,"days":days,"exceeded_first_optional_ceiling":exceeded,"restored_exact":true}
func funded_case(extra_attempt: bool,response: String="") -> Dictionary:
	var cfg: Dictionary=Consumer.configuration("consumer_enquiries")
	if not response.is_empty():
		cfg.operating_inventory["enquiry_response"]=response
		cfg.operating_inventory["enquiry_response_goods"]=["soap"]
	var b: WorldBuildResult=build(cfg)
	assert(Consumer.apply_condition(b.world,"consumer_enquiries").accepted)
	until(b,1)
	var e: EconomyR1Slice=b.world.economy_r1
	var actor: String="cohort:regional:lyon_upstream"
	var offer: Dictionary=e._offer(actor,"firm:regional_food","soap","edge:regional_local:lyon","site:regional_food:lyon")
	var cash: int=b.world.ledger_state.available_balance(e._account(actor))
	var probe: Dictionary={}
	if extra_attempt:
		assert(offer.reason=="NO_UNCOMMITTED_STOCK" and cash>=int(offer.price)+int(offer.freight_per_unit),str(offer))
		var limited: Dictionary=offer.duplicate(true);limited.transport_quantity=1
		var useful: Dictionary=e.HouseholdTiming.candidate_need(e,actor,"household",limited,1)
		assert(useful.quantity==1,str(useful))
		var cmd: Dictionary=e._auto_command(actor,"buy",{"quote_id":offer.quote_id,"seller":offer.seller,"seller_site":offer.seller_site,"good":"soap","quantity":1,"denomination":offer.denomination,"max_price":offer.price,"path_id":offer.route_id,"need_category":"household","need_by_day":useful.need_by_day},"CONTROLLED_FUNDED_KNOWN_STOCK_ENQUIRY")
		probe=e._accept(actor,cmd,true)
		assert(not probe.accepted and probe.reason=="NO_STOCK",str(probe))
		assert(b.world.ledger_state.available_balance(e._account(actor))==cash)
	var daily: Array=[]
	for date: int in range(1,9):
		until(b,date*1440)
		daily.append({"market_time_responses":e._procurement_observations.filter(func(row: Dictionary):return row.get("kind")=="MARKET_TIME_RESPONSE" and row.site=="site:regional_food:lyon" and row.good=="soap").duplicate(true),"day":date,"received_requests":e._request_pressure_records("site:regional_food:lyon","soap").duplicate(true),"inventory_decision":e.OperatingInventory.observe(e,"site:regional_food:lyon","soap"),"seller_cash":b.world.ledger_state.available_balance(e._account("firm:regional_food")),"stock":e._stocks["site:regional_food:lyon"].duplicate(true),"consumer_inventory":e._stocks["cohort:regional:lyon_textile"].duplicate(true),"consumer_totals":e._totals["cohort:regional:lyon_textile"].duplicate(true)})
	exact_restore(b)
	return {"scope":"CONTROLLED_ONE_ORIGINAL_FUNDED_ATTEMPT_EXISTING_ACTOR_NO_GRANT_NOT_NATURAL_CHOICE","extra_attempt":extra_attempt,"initial_offer":offer,"initial_available_cash":cash,"original_result":probe,"daily":daily,"orders":e._orders.duplicate(true),"commands":e._commands.duplicate(true),"shipments":e._shipments.duplicate(true),"receipts":e._delivery_receipts.duplicate(true),"ledger":b.world.ledger_state.transactions(),"restored_exact":true}

func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var result: Dictionary
	if args.size()>1 and args[1]=="funded_time":result={"legacy_funded":funded_case(true),"deadline":funded_case(true,"deadline"),"bounded":funded_case(true,"bounded")}
	else:result={"control":funded_case(false),"funded_attempt":funded_case(true)} if args.size()>1 and args[1]=="funded" else paid_publication() if args.size()>1 and args[1]=="paid" else {"per_attempt":capital_case(false),"company_window":capital_case(true)}
	if result.is_empty() or (result.has("per_attempt") and (result.per_attempt.is_empty() or result.company_window.is_empty())):push_error("Targeted consumer policy run incomplete");quit(1);return
	var f: FileAccess=FileAccess.open(args[0],FileAccess.WRITE);f.store_string(JSON.stringify(result,"\t"));f.close()
	completed=true;print("CONSUMER_POLICY_FINISHED ",args);quit()


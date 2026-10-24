extends RefCounted
## Developer diagnosis only. Called inside the research Runtime; pure values
## leave the worker. This is never supplier knowledge or a purchasing action.
static func household(e: RefCounted,actor: String) -> Dictionary:
	var cash: int=e._world.ledger_state.balance(e._account(actor))
	var reserved: int=e._world.ledger_state.reserved_balance(e._account(actor))
	var matured: int=0
	for id: String in e._wages_by_worker.get(actor,[]):
		var wage: Dictionary=e._wages[id]
		if int(wage.due_day)<=e.day:matured+=int(wage.remaining)
	var position: Dictionary=e._household_position(actor,true)
	var rows: Array=[]
	for original: Dictionary in e._offers(actor):
		var good: String=original.good
		var categories: Array=e._actor_categories(actor).filter(func(c: String):return e._service(good,c)>0)
		if categories.is_empty():continue
		var category: String=categories[0]
		var offer: Dictionary=original.duplicate(true)
		var requested: int=maxi(1,int(position.get(category,{}).get("uncovered",0)))
		var probe: Dictionary=offer.duplicate(true);probe.transport_quantity=requested
		var eligible: int=int(e.HouseholdTiming.candidate_need(e,actor,category,probe,requested).quantity)
		var site: String=offer.seller_site
		var available_cash: int=e._world.ledger_state.available_balance(e._account(actor,offer.denomination))
		var unit_cost: int=int(offer.get("price",0))+int(offer.get("freight_per_unit",0)) if offer.get("price") is int else 0
		var stock: int=int(e._stocks[site][good]);var committed: int=e._committed(site,good)
		var path: Dictionary=e._route_for(actor,offer.seller,offer.route_id,"",site)
		var onsite: bool=str(offer.route_id).begins_with("onsite:")
		var transport: int=e._retail.limit(site) if onsite else e._route_available(path) if not path.is_empty() else 0
		var caps: Dictionary=e._request_limits(requested,maxi(0,stock-committed),transport,1000000,maxi(0,available_cash)/unit_cost if unit_cost>0 else 0)
		var introduced: Array=[]
		var candidate: String=str(offer.seller)+"|"+good+"|"+site
		var opening: Dictionary=e._receipts.get("message:"+actor+":supplier:"+candidate,{})
		if not opening.is_empty():introduced.append(opening.duplicate(true))
		for id: String in e._commercial._received.get(actor,[]):
			var receipt: Dictionary=e._receipts[id]
			if receipt.kind=="supplier" and receipt.candidate==candidate:introduced.append(receipt.duplicate(true))
		rows.append({"good":good,"seller_site":site,"seller":offer.seller,"price":offer.get("price"),"freight":offer.get("freight_per_unit"),"offer_reason":offer.reason,"executable_quantity":offer.quantity,"stock":stock,"committed":committed,"free":maxi(0,stock-committed),"site_selling":e._site_selling(site),"sales_role":"sales" in e._spec.sites[site].roles,"storefront":e._retail.has_site(site),"route_id":offer.route_id,"transport_cap":transport,"known_quote_reason":e._local_quotes.reason(actor,site,good),"known_sources":introduced,"need_eligible_quantity":eligible,"request_caps":caps,"arrival_lower_bound":offer.get("earliest_arrival_day"),"eta_guaranteed":offer.get("eta_guaranteed",false)})
	var choices: Array=[]
	var attempts: Array=[]
	for id: String in e._recent_buy_commands.get(actor,[]):
		var entry: Dictionary=e._commands[id]
		var cmd: Dictionary=entry.envelope.command
		if entry.envelope.actor==actor and cmd.kind=="buy" and entry.result.get("decision",{}).has("household_choice"):choices.append({"minute":cmd.minute,"good":cmd.payload.good,"quantity":cmd.payload.quantity,"result":entry.result.duplicate(true)})
		if entry.envelope.actor==actor and cmd.kind=="buy" and cmd.payload.get("need_category")=="food":attempts.append({"minute":cmd.minute,"payload":cmd.payload.duplicate(true),"result":entry.result.duplicate(true)})
	choices.sort_custom(func(a: Dictionary,b: Dictionary):return int(a.minute)>int(b.minute))
	attempts.sort_custom(func(a: Dictionary,b: Dictionary):return int(a.minute)>int(b.minute))
	return {"known_consumption_offers":rows,"recent_cross_category_choices":choices.slice(0,5),"choice_observation":e._household_choice_observations.get(actor,{}).duplicate(true),"actor":actor,"place_id":e._place(actor),"cash":cash,"reserved":reserved,"available":cash-reserved,"income":e._income_by_actor.get(actor,{}).duplicate(),"wage_matured_unpaid":matured,"consumer_inventory":e._stocks[actor].duplicate(true),"category_totals":e._totals.get(actor,{}).get("categories",{}).duplicate(true),"category_today":e._needs.get(actor,{}).get("categories",{}).duplicate(true),"food_today":e._needs.get(actor,{}).get("categories",{}).get("food",{}).duplicate(true),"food_total":e._totals.get(actor,{}).get("categories",{}).get("food",{}).duplicate(true),"planning_food":position.get("food",{}),"known_food_offers":rows.filter(func(o: Dictionary):return e._service(o.good,"food")>0),"recent_real_attempts":attempts.slice(0,3),"scope":"DEVELOPER_PRIVATE_DIAGNOSIS_NOT_MARKET_KNOWLEDGE"}
static func project(e: RefCounted) -> Dictionary:
	var places: Dictionary={}
	for actor: String in e._actor_ids():
		if e._actors[actor].control!="automatic":continue
		var row: Dictionary=household(e,actor)
		if not places.has(row.place_id):places[row.place_id]=[]
		places[row.place_id].append(row)
	var responses: Array=[];var purchases: Array=[]
	for original: Dictionary in e._procurement_observations:
		if original.get("kind") not in ["MARKET_TIME_RESPONSE","CAPITAL_RESPONSE"]:continue
		var row: Dictionary=original.duplicate(true);row["place_id"]=e._place(row.site);responses.append(row)
	for firm: String in e._firm_ids():
		for id: String in e._orders_by_buyer.get(firm,[]).slice(-16):
			var order: Dictionary=e._orders[id]
			if not e._spec.sites.has(order.buyer_site):continue
			var replenishment: Dictionary=e._commands[order.action_id].result.get("decision",{}).get("replenishment",{})
			var decision: Dictionary=replenishment.get("market_time_response",{})
			if decision.is_empty() and not replenishment.has("turnover_response"):continue
			purchases.append({"order_id":order.id,"place_id":order.to_place_id,"site":order.buyer_site,"good":order.good,"accepted_day":order.accepted_day,"quantity":order.quantity,"pending":order.pending,"transit":order.transit,"delivered":order.delivered,"cancelled":order.cancelled,"decision":decision.duplicate(true),"turnover":replenishment.get("turnover_response",{}).duplicate(true)})
	purchases.sort_custom(func(a: Dictionary,b: Dictionary):return int(a.accepted_day)>int(b.accepted_day))
	return {"market_responses":responses,"recent_replenishment":purchases.slice(0,12),"schema":"developer_consumer_access_v1","minute":e._world.game_clock.total_minutes(),"places":places}

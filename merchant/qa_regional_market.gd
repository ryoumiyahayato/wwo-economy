extends SceneTree
## Three conditions, same restored world. Full facts stay in this diagnosis file.
const Reaction=preload("res://merchant/regional_reaction_opening.gd")
const Multi=preload("res://merchant/multisource_opening.gd")
const Opening=preload("res://merchant/merchant_opening.gd")
const Contacts=preload("res://merchant/merchant_market_contacts.gd")
const Runtime=preload("res://merchant/merchant_runtime.gd")
var completed: bool=false
var started: int=Time.get_ticks_msec()
func _initialize() -> void:call_deferred("run")
func _process(_delta: float) -> bool:
	if not completed and Time.get_ticks_msec()-started>300000:push_error("Regional market incomplete");quit(1)
	return false

func cash_totals(b: WorldBuildResult) -> Dictionary:
	var sums: Dictionary={}
	for id: String in b.world.ledger_state.account_ids():
		var a: Dictionary=b.world.ledger_state.account(id)
		sums[a.denomination]=int(sums.get(a.denomination,0))+int(a.balance)
	return sums

func record(b: WorldBuildResult) -> Dictionary:
	var e: EconomyR1Slice=b.world.economy_r1
	var sites: Dictionary={};var firms: Dictionary={}
	for site: String in e._site_ids():
		var needs: Dictionary={}
		for good: String in ["grain","bread","oil","soap"]:
			needs[good]=e._input_need(site,good)
		sites[site]={"inventory":e._stocks[site].duplicate(),"physical":e._physical_totals[site].duplicate(true),"plan":e._plans.get(site,{}).duplicate(true),"needs":needs,"offers":e._offers(e._owner(site),site),"knowledge":e._firm_knowledge[site].duplicate()}
	for firm: String in e._firm_ids():
		var own: Dictionary=e.visible_internal(firm)
		firms[firm]={"cash":b.world.ledger_state.balance(e._account(firm)),"available":b.world.ledger_state.available_balance(e._account(firm)),"reserved":b.world.ledger_state.reserved_balance(e._account(firm)),"contacts":Contacts.project(own,[],b.world.game_clock.total_minutes())}
	return {"minute":b.world.game_clock.total_minutes(),"sites":sites,"firms":firms,"transport":e._transport.duplicate(true),"orders":e._orders.values().duplicate(true),"original_request_observations":e._request_window.duplicate(true),"quotes":e._local_quotes.snapshot(),"quote_notices":e._receipts.values().filter(func(row: Dictionary):return row.get("kind")=="goods_quote")}

func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if "--capacity-competition" in args:competition(args[0]);return
	var base: WorldBuildResult=Reaction.build()
	assert(base.success and base.world.economy_r1!=null,base.error+" "+str(base.world.native_economy_error))
	var initial: Dictionary=base.persistence.snapshot();base=null
	var normalized: WorldBuildResult=FormalPersistence.new().restore_candidate(initial)
	assert(normalized.success,normalized.error)
	for key: String in ["economy_native","ledger","total_minutes"]:assert(normalized.persistence.snapshot()[key]==initial[key],"First restore changed economic facts")
	initial=normalized.persistence.snapshot();normalized=null
	var output: Dictionary={"scope":"EXPLICIT_DEVELOPMENT_REGIONAL_DIAGNOSIS","close_minute":Reaction.CLOSE_MINUTE,"reopen_minute":Reaction.REOPEN_MINUTE,"bypass_basis":"SYNTHETIC_TWO_UNITS_FIVE_DAYS_THREE_FREIGHT_NOT_A_HISTORICAL_MAP_LINK","conditions":{}}
	for condition: String in Reaction.CONDITIONS:
		var b: WorldBuildResult=FormalPersistence.new().restore_candidate(initial)
		assert(b.success and b.persistence.snapshot()==initial,b.error)
		assert(Reaction.apply_condition(b.world,condition).get("accepted",false))
		var cash: Dictionary=cash_totals(b)
		var records: Array=[record(b)]
		var e: EconomyR1Slice=b.world.economy_r1
		for day: int in range(1,41):
			while b.world.game_clock.total_minutes()<day*1440:
				var minutes: int=mini(60,mini(day*1440-b.world.game_clock.total_minutes(),Reaction.minutes_to_boundary(b.world.game_clock.total_minutes())))
				assert(b.simulation_step.advance_minutes(minutes).get("success",true))
				assert(Reaction.apply_condition(b.world,condition).get("accepted",false))
			assert(cash_totals(b)==cash,"Currency created or destroyed")
			records.append(record(b))
			if day in [5,6,10,15,21,28,40]:print("REGIONAL_MARKET ",condition," day=",day," grain=",e._stocks[Opening.SITE].grain," food_grain=",e._stocks["site:regional_food:paris"].grain," orders=",e._orders.size()," main=",e._transport.edges[Multi.EDGE].capacity," bypass=",e._transport.edges[Reaction.BYPASS].capacity)
		for id: String in e._lots.sources:
			var quantity: int=0
			for portion: Dictionary in e._lots.portions.values():
				if portion.source_id==id:quantity+=int(portion.remaining)+int(portion.consumed)+int(portion.lost)
			assert(quantity==int(e._lots.sources[id].quantity),"Physical source not conserved")
		for order: Dictionary in e._orders.values():
			assert(int(order.quantity)==int(order.pending)+int(order.transit)+int(order.delivered)+int(order.cancelled))
			if order.kind=="SALE" and not e._local_quotes.rule(order.seller_site,order.good).is_empty():assert(e._local_quotes.valid_locked_price(order),"Order price or information receipt changed")
		var snapshot: Dictionary=b.persistence.snapshot()
		var restored: WorldBuildResult=FormalPersistence.new().restore_candidate(snapshot)
		assert(restored.success,restored.error)
		for key: String in ["economy_native","ledger","total_minutes"]:assert(restored.persistence.snapshot()[key]==snapshot[key])
		# Measure real value-view work before deciding whether to optimize it.
		var runtime: RefCounted=Runtime.new();runtime._slot=0;runtime._network_experiment=true;runtime._multisource_condition=condition
		var observation_us: Array=[]
		for subject: String in ["","firm:regional_food"]:
			runtime._research_subject=subject
			var begin: int=Time.get_ticks_usec();var view: Dictionary=runtime._view(b)
			observation_us.append({"subject":subject,"elapsed_us":Time.get_ticks_usec()-begin,"nodes":view.market_network.nodes.size(),"edges":view.market_network.edges.size()})
		assert(b.persistence.snapshot()==snapshot,"Research view changed the world")
		output.conditions[condition]={"records":records,"final_lots":e._lots.snapshot(),"final_ledger":b.world.ledger_state.transactions(),"work_records":e._work_records.duplicate(true),"wages":e._wages.duplicate(true),"commands":e._commands.duplicate(true),"restore_exact":true,"cash_conserved":true,"source_quantities_conserved":true,"observation_us":observation_us}
		if args.size()>1:
			var save: FileAccess=FileAccess.open(args[1]+"_"+condition+".json",FileAccess.WRITE);save.store_string(JSON.stringify(snapshot));save.close()
		restored=null;b=null
	var file: FileAccess=FileAccess.open(args[0],FileAccess.WRITE);file.store_string(JSON.stringify(output,"\t"));file.close();completed=true;print("REGIONAL_MARKET_FINISHED");quit()

func competition(path: String) -> void:
	print("REGIONAL_USER_DATA_DIR ",OS.get_user_data_dir())
	var cfg: Dictionary=Multi.configuration("normal")
	var original: Dictionary=Multi.totals(cfg)
	# Controlled capacity fixture: move the food firm's finite opening grain
	# back to its real upstream source, giving both buyers an actual need.
	var food: Dictionary=Multi.site(cfg,"site:regional_food:paris")
	Multi.site(cfg,Multi.LYON).stock.grain+=int(food.stock.grain);food.stock.grain=0
	assert(Multi.totals(cfg)==original)
	var b: WorldBuildResult=WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,false,{"format":"HOST_REGION_SELECTION","person_ids":[],"select_people_at_sites":true,"configuration":cfg})
	assert(b.success and b.world.economy_r1!=null,b.error)
	var e: EconomyR1Slice=b.world.economy_r1
	assert(e.submit_internal(Opening.FIRM,e._auto_command(Opening.FIRM,"set_edge_capacity",{"edge_id":Multi.EDGE,"capacity":1},"research_capacity_competition")).accepted)
	assert(b.simulation_step.advance_minutes(1).get("success",true))
	var seeds: Array=[];var capacity_refused: bool=false
	for buyer: Array in [[Opening.FIRM,Opening.SITE],["firm:regional_food","site:regional_food:paris"]]:
		var offer: Dictionary=e._offer(buyer[0],"firm:regional_upstream","grain",Multi.EDGE,Multi.LYON,buyer[1])
		var payload: Dictionary={"quote_id":offer.quote_id,"seller":offer.seller,"seller_site":Multi.LYON,"buyer_site":buyer[1],"good":"grain","quantity":1,"denomination":offer.denomination,"max_price":offer.price,"path_id":offer.route_id,"need_by_day":7}
		var result: Dictionary=e.submit_internal(buyer[0],e._auto_command(buyer[0],"buy",payload,"EXPLICIT_TWO_BUYER_CAPACITY_REQUEST"))
		if buyer[0]==Opening.FIRM:assert(result.get("accepted",false),str(result))
		else:
			assert(not result.get("accepted",false) and offer.transport_quantity==0 and offer.reason=="TRANSPORT_LIMIT_OR_CLOSED",str(offer)+str(result))
			assert(b.world.ledger_state.available_balance(e._account(buyer[0]))>=4)
			capacity_refused=true
		seeds.append({"buyer":buyer[0],"offer":offer,"result":result})
	var cash: Dictionary=cash_totals(b)
	var records: Array=[];var buyers: Dictionary={};var waited: bool=false
	for day: int in range(1,13):
		while b.world.game_clock.total_minutes()<day*1440:assert(b.simulation_step.advance_minutes(mini(60,day*1440-b.world.game_clock.total_minutes())).get("success",true))
		var edge: Dictionary=e._transport.edges[Multi.EDGE]
		assert(int(edge.dispatched)<=1 and cash_totals(b)==cash)
		var relevant: Array=[]
		for order: Dictionary in e._orders.values():
			if not order.route_legs.any(func(leg: Dictionary):return leg.edge_id==Multi.EDGE):continue
			relevant.append(order.duplicate(true))
			if order.transit>0 or order.delivered>0:buyers[order.buyer]=true
			if order.pending>0 and int(edge.dispatched)==1:waited=true
		for order: Dictionary in e._orders.values():
			if order.kind=="SALE" and not e._local_quotes.rule(order.seller_site,order.good).is_empty():assert(e._local_quotes.valid_locked_price(order))
		records.append({"day":day,"edge":edge.duplicate(true),"orders":relevant,"shipments":e._shipments.values().duplicate(true),"delivery_receipts":e._delivery_receipts.values().duplicate(true)})
	assert(capacity_refused and not buyers.is_empty(),"No actual competing admission or transport")
	var restored: WorldBuildResult=FormalPersistence.new().restore_candidate(b.persistence.snapshot())
	assert(restored.success,restored.error)
	for key: String in ["economy_native","ledger","total_minutes"]:assert(restored.persistence.snapshot()[key]==b.persistence.snapshot()[key])
	b=null;restored=null
	var prices: WorldBuildResult=Reaction.build()
	assert(prices.success and prices.world.economy_r1!=null)
	assert(Reaction.apply_condition(prices.world,"regional_normal").accepted)
	var price_records: Array=[]
	for day: int in range(1,7):
		while prices.world.game_clock.total_minutes()<day*1440:assert(prices.simulation_step.advance_minutes(mini(60,day*1440-prices.world.game_clock.total_minutes())).get("success",true))
		var pe: EconomyR1Slice=prices.world.economy_r1
		var current: Dictionary=pe._local_quotes.current(Multi.LYON,"grain")
		var known: Dictionary=pe._local_quotes.known("site:regional_food:paris",Multi.LYON,"grain")
		var reason: String=pe._local_quotes.reason("site:regional_food:paris",Multi.LYON,"grain")
		if day==4:assert(current.version==1 and known.version==0 and reason=="GOODS_QUOTE_SUPERSEDED")
		if day==5:assert(known.version==1)
		price_records.append({"day":day,"current":current,"known":known,"reason":reason})
	var output: Dictionary={"basis":"EXPLICIT_DEVELOPMENT_MAIN_CAPACITY_ONE_NOT_HISTORICAL","seed_basis":"TWO_EXPLICIT_FORMAL_PURCHASE_REQUESTS_NOT_NPC_DECISIONS","seeds":seeds,"buyers_with_actual_transport":buyers.keys(),"records":records,"pending_queue_seen":waited,"capacity_admission_competition":capacity_refused,"delayed_quote_observation":true,"price_records":price_records,"locked_prices_preserved":true,"restore_exact":true,"cash_conserved":true}
	var file: FileAccess=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(output,"\t"));file.close();completed=true;print("REGIONAL_COMPETITION_FINISHED buyers=",buyers.keys());quit()

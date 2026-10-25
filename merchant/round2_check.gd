extends SceneTree
## Round2 finite developer worlds. No user save paths or archived worlds are read.
const Base = preload("res://merchant/qa_company_procurement_priority.gd")
const Reference = preload("res://scripts/world/global_commodity_reference.gd")
const Opening = preload("res://merchant/merchant_opening.gd")
const Runtime = preload("res://merchant/merchant_runtime.gd")
var output_path: String

func _initialize() -> void:
	run.call_deferred()

func emit_result(value: Dictionary) -> void:
	value["status"] = "PASS"
	value["basis"] = "EXPLICIT_FINITE_DEVELOPMENT_SCENARIO_NOT_1900_STATISTICS"
	var file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value,"\t")); file.close()
	print("ROUND2_PASS ",JSON.stringify(value))
	quit(0)

func fresh(cfg: Dictionary, select_people: bool=false) -> WorldBuildResult:
	assert(EconomySliceConfig.valid(cfg),"Invalid finite development configuration")
	var built: WorldBuildResult = WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,false,{"format":"HOST_REGION_SELECTION","person_ids":[],"select_people_at_sites":select_people,"configuration":cfg})
	assert(built.success,built.error)
	return built

func advance(b: WorldBuildResult, minutes: int) -> void:
	# Existing exact clock/step; hourly intervals preserve real phase ordering.
	var target: int = b.world.game_clock.total_minutes()+minutes
	while b.world.game_clock.total_minutes()<target:
		assert(b.simulation_step.advance_minutes(mini(60,target-b.world.game_clock.total_minutes())).get("success",true))

func restore_exact(b: WorldBuildResult) -> bool:
	var snapshot: Dictionary=b.persistence.snapshot()
	var restored: WorldBuildResult=FormalPersistence.new().restore_candidate(snapshot)
	assert(restored.success,restored.error)
	for key: String in ["total_minutes","economy_native","ledger","economy"]:
		assert(restored.persistence.snapshot()[key]==snapshot[key],key)
	return true

func site_row(cfg: Dictionary, id: String) -> Dictionary:
	for firm: Dictionary in cfg.firms:
		for site: Dictionary in firm.sites:
			if site.id==id:return site
	return {}

func industry_config(condition: String) -> Dictionary:
	var cfg: Dictionary=EconomyDevelopmentConfig.regional_template()
	cfg["case_id"]="ROUND2_FINITE_COAL_IRON_STEEL_V1"
	for good: String in ["coal","iron_ore","steel"]:
		cfg.goods.append({"id":good,"needs":{},"unit_id":"round2_material_unit","unit_name_zh":"有限开发材料单位"})
	var goods: Array[String]=EconomySliceConfig.good_ids(cfg)
	for actor: Dictionary in cfg.actors:
		for good: String in goods:
			if not actor.stock.has(good):actor.stock[good]=0
	for firm: Dictionary in cfg.firms:
		for site: Dictionary in firm.sites:
			for good: String in goods:
				if not site.stock.has(good):site.stock[good]=0
				if not site.targets.has(good):site.targets[good]=0
			for activity: Dictionary in site.activities:
				for good: String in goods:
					if not activity.materials.has(good):activity.materials[good]=0
			site.targets=EconomySliceConfig.zero_stock(goods)
			site.production_enabled=site.id==Base.WEAVE
	var plant: Dictionary=site_row(cfg,Base.WEAVE)
	plant.stock=EconomySliceConfig.zero_stock(goods)
	plant.stock.coal=0 if condition=="coal_shortage" else 6
	plant.stock.iron_ore=0 if condition=="iron_shortage" else 6
	plant.targets.steel=3
	plant.prices.steel=12
	plant.activities[0].materials=EconomySliceConfig.zero_stock(goods)
	plant.activities[0].materials.coal=2;plant.activities[0].materials.iron_ore=1
	plant.activities[0].outputs={"steel":1}
	# Existing equipment, skill, employment, wages and capacity remain binding.
	return cfg

func industry() -> void:
	var results: Array=[]
	for condition: String in ["sufficient","coal_shortage","iron_shortage"]:
		var cfg: Dictionary=industry_config(condition)
		var initial: Dictionary=site_row(cfg,Base.WEAVE).stock.duplicate(true)
		var b: WorldBuildResult=fresh(cfg)
		var e: EconomyR1Slice=b.world.economy_r1
		var cash_before: int=b.world.ledger_state.balance(e._account(Base.TEXTILE))
		advance(b,3*1440)
		var totals: Dictionary=e._physical_totals[Base.WEAVE].duplicate(true)
		var made: int=int(totals.produced.steel)
		assert(made>0 if condition=="sufficient" else made==0,"Material scarcity must bind actual production")
		assert(int(totals.used.coal)==made*2 and int(totals.used.iron_ore)==made)
		assert(int(e._stocks[Base.WEAVE].coal)+int(totals.used.coal)==int(initial.coal))
		assert(int(e._stocks[Base.WEAVE].iron_ore)+int(totals.used.iron_ore)==int(initial.iron_ore))
		var lots: Array=[]
		for portion: Dictionary in e._lots.snapshot().portions.values():
			if portion.good in ["coal","iron_ore","steel"]:lots.append(portion)
		results.append({"condition":condition,"minute":b.world.game_clock.total_minutes(),"initial_inputs":initial,"physical":totals,"final_stock":e._stocks[Base.WEAVE].duplicate(true),"cash_before":cash_before,"cash_after":b.world.ledger_state.balance(e._account(Base.TEXTILE)),"quote":e._price(Base.WEAVE,"steel"),"lots":lots,"restore_exact":restore_exact(b)})
	emit_result({"suite":"finite_steel","recipe":{"coal":2,"iron_ore":1,"steel_output":1},"cases":results,"feedback_boundary":"ACTUAL_INPUT_LOTS_TO_STEEL; NO_ASSUMED_MACRO_STOCK_OR_FORCED_PRICE_CHANGE"})

func coupled() -> void:
	var opening: WorldBuildResult=fresh(EconomyDevelopmentConfig.regional_template(),true)
	advance(opening,24*1440)
	var initial: Dictionary=opening.persistence.snapshot()
	var source_hash: String=var_to_bytes(initial).hex_encode().sha256_text()
	var rows: Array=[]
	for enabled: bool in [false,true]:
		var b: WorldBuildResult=FormalPersistence.new().restore_candidate(initial)
		assert(b.success,b.error)
		var e: EconomyR1Slice=b.world.economy_r1
		var begin: Dictionary={"cash":b.world.ledger_state.balance(e._account(Base.FOOD)),"stock":e._stocks[Base.BAKERY].duplicate(true),"production":e._physical_totals[Base.BAKERY].duplicate(true)}
		if enabled:assert(b.world.economy_state.enable_reference_market("shocks"))
		var started: int=Time.get_ticks_usec()
		advance(b,30*1440)
		var orders: Array=[];var decisions: Array=[]
		for order: Dictionary in e._orders.values():
			if order.buyer==Base.FOOD and order.good=="grain" and int(order.accepted_minute)>=24*1440:orders.append(order.duplicate(true))
		for entry: Dictionary in e._commands.values():
			if entry.result.get("decision",{}).has("public_reference_bulletin"):decisions.append(entry.result.decision)
		rows.append({"enabled":enabled,"begin":begin,"end":{"cash":b.world.ledger_state.balance(e._account(Base.FOOD)),"stock":e._stocks[Base.BAKERY].duplicate(true),"production":e._physical_totals[Base.BAKERY].duplicate(true)},"grain_orders":orders,"reference_decisions":decisions,"reference_local":b.world.economy_state.reference_market.data.local if enabled else {},"simulation_us":Time.get_ticks_usec()-started,"restore_exact":restore_exact(b)})
	assert(var_to_bytes(initial).hex_encode().sha256_text()==source_hash)
	emit_result({"suite":"fresh_same_start_formal_30_days","start_minute":24*1440,"source_hash":source_hash,"conditions":rows,"old_baseline":{"cash":[125,103],"bread_cumulative":96,"grain_orders_each":12,"index_evaluations":9,"index_price_changes":0},"comparability":"NEW_REGIONAL_DAY24_FIXTURE_NOT_ARCHIVED_PLAYER_TRIAL; DIFFERENT_INITIAL_CONDITIONS_EXPLICIT"})

func trade() -> void:
	var catalog: VNextSpatialCatalog=VNextSpatialCatalog.new()
	assert(catalog.load_legacy_world_map())
	var link: Dictionary={}
	for candidate: Dictionary in catalog.links():
		if candidate.link_type=="shipping" and [candidate.from_place_id,candidate.to_place_id].has("place:port_london") and [candidate.from_place_id,candidate.to_place_id].has("place:port_le_havre"):link=candidate;break
	assert(not link.is_empty(),"No actual London port-Le Havre host shipping link")
	var cfg: Dictionary=EconomyDevelopmentConfig.regional_template()
	cfg.case_id="ROUND2_CHANNEL_FINITE_GRAIN_V1"
	var goods: Array[String]=EconomySliceConfig.good_ids(cfg)
	var seller: String="firm:round2_london";var buyer: String="firm:round2_havre"
	var ss: String="site:round2_london:port";var bs: String="site:round2_havre:port"
	var template: Dictionary=cfg.firms[0].sites[0].duplicate(true)
	for side: Dictionary in [{"id":seller,"site":ss,"place":"place:port_london","cash":40,"stock":12},{"id":buyer,"site":bs,"place":"place:port_le_havre","cash":100,"stock":0}]:
		var site: Dictionary=template.duplicate(true)
		site.id=side.site;site.place_id=side.place;site.stock=EconomySliceConfig.zero_stock(goods);site.stock.grain=side.stock
		site.targets=EconomySliceConfig.zero_stock(goods);site.prices={"grain":4};site.capacity=0;site.activities=[];site.roles=["storage","sales"];site.suppliers=[];site.production_enabled=false
		if side.id==buyer:site.suppliers=[seller+"|grain|"+ss]
		cfg.firms.append({"id":side.id,"place_id":side.place,"account_id":"account:"+str(side.id).trim_prefix("firm:"),"cash":side.cash,"sites":[site]})
	cfg.carriers.append({"id":"carrier:round2_channel","place_id":"place:port_london","account_id":"account:round2_channel","cash":10})
	cfg.routes.append({"id":"edge:round2_channel","from_place_id":"place:port_london","to_place_id":"place:port_le_havre","capacity":2,"delay":2,"carrier":"carrier:round2_channel","freight_per_unit":1,"known_to":[seller,buyer],"basis":"HOST_LINK","source_link_id":link.link_id})
	cfg.transport_nodes.append({"place_id":"place:port_london","capacity":2});cfg.transport_nodes.append({"place_id":"place:port_le_havre","capacity":2})
	cfg.information.append({"actor":bs,"kind":"supplier","candidate":seller+"|grain|"+ss,"delivery_day":0})
	var b: WorldBuildResult=fresh(cfg)
	var e: EconomyR1Slice=b.world.economy_r1
	advance(b,1)
	var before: Dictionary={"buyer_cash":b.world.ledger_state.balance(e._account(buyer)),"seller_cash":b.world.ledger_state.balance(e._account(seller)),"carrier_cash":b.world.ledger_state.balance("account:round2_channel"),"seller_stock":e._stocks[ss].grain,"buyer_stock":e._stocks[bs].grain}
	var offer: Dictionary=e._offer(buyer,seller,"grain","edge:round2_channel",ss,bs)
	assert(int(offer.transport_quantity)==2,str(offer))
	var payload: Dictionary={"quote_id":offer.quote_id,"seller":seller,"seller_site":ss,"buyer_site":bs,"good":"grain","quantity":2,"max_price":offer.price,"denomination":offer.denomination,"path_id":offer.route_id}
	var command: Dictionary=e._auto_command(buyer,"buy",payload,"ROUND2_CHANNEL")
	var accepted: Dictionary=e.submit_internal(buyer,command)
	assert(accepted.get("accepted",false),str(accepted))
	var accepted_state: Dictionary=e.snapshot()
	assert(e.submit_internal(buyer,command)==accepted and e.snapshot()==accepted_state,"Order replay must be idempotent")
	var reserved: int=b.world.ledger_state.reserved_balance(e._account(buyer))
	var stages: Array=[]
	for hour: int in 96:
		advance(b,60)
		for shipment: Dictionary in e._shipments.values():
			if e._orders[shipment.order_id].buyer==buyer and (stages.is_empty() or stages[-1].get("stage")!=shipment.stage):stages.append({"minute":b.world.game_clock.total_minutes(),"id":shipment.id,"stage":shipment.stage})
		if int(e._stocks[bs].grain)==2:break
	var orders: Array=[];var transactions: Array=[];var lots: Array=[]
	for order: Dictionary in e._orders.values():
		if order.buyer==buyer:orders.append(order)
	for tx: Dictionary in b.world.ledger_state.transactions():
		if tx.from_account_id==e._account(buyer):transactions.append(tx)
	for lot: Dictionary in e._lots.snapshot().portions.values():
		if lot.owner in [seller,buyer]:lots.append(lot)
	assert(int(e._stocks[bs].grain)==2 and int(e._stocks[ss].grain)==10,"Actual finite cargo must arrive")
	assert(b.world.ledger_state.balance(e._account(buyer))==90 and b.world.ledger_state.balance(e._account(seller))==48 and b.world.ledger_state.balance("account:round2_channel")==12,"Goods8 plus freight2 must settle once")
	emit_result({"suite":"real_channel_order","host_link":link,"from":catalog.get_place("place:port_london"),"to":catalog.get_place("place:port_le_havre"),"london_city_is_not_port":catalog.get_place("place:london").place_id!=catalog.get_place("place:port_london").place_id,"currency_terms":"BOTH_DEVELOPMENT_FIRMS_CONTRACT_IN_EXISTING_FORMAL_DENOMINATION; NO_FX_REQUIRED; NOT_HISTORICAL_GBP_CLAIM","before":before,"accepted":accepted,"reserved_cash":reserved,"offer":offer,"orders":orders,"stages":stages,"transactions":transactions,"lots":lots,"after":{"buyer_stock":e._stocks[bs].grain,"seller_stock":e._stocks[ss].grain,"buyer_cash":b.world.ledger_state.balance(e._account(buyer))},"restore_exact":restore_exact(b),"feedback_boundary":"CROSS_BORDER_REAL_STOCK_ORDER_CAPACITY_CARGO_LEDGER; GLOBAL_ESTIMATED_FLOWS_ARE_SEPARATE"})

func ui() -> void:
	var global_scene: Node=load("res://merchant/global_market.tscn").instantiate()
	root.add_child(global_scene)
	await process_frame
	assert(global_scene.runtime==null,"Scene load must not open archived research save")
	var sizes: Array=[]
	for size: Vector2i in [Vector2i(1440,900),Vector2i(390,844)]:
		root.size=size
		await process_frame
		sizes.append({"viewport":str(size),"mode_button":global_scene.map_view.mode_button.text,"estimated_and_physical_separate":true,"side_panel":str(global_scene.map_view.side.size)})
	global_scene.queue_free();await process_frame
	var cfg: Dictionary=Opening.regional_configuration()
	var b: WorldBuildResult=fresh(cfg,true)
	assert(Opening.grant_regional_authority(b.world))
	var merchant: Node=load("res://merchant/main.tscn").instantiate()
	merchant.external_host_context=Runtime.host_context(b.persistence.snapshot(),b.world.player_state.player_id(),Opening.FIRM,Opening.SITE,{},Opening.REGIONAL_AUTHORITY)
	merchant.guide_opened=true
	root.add_child(merchant)
	var deadline: int=Time.get_ticks_msec()+60000
	while not merchant.world_ready:
		assert(Time.get_ticks_msec()<deadline,"Merchant fresh-host startup timeout")
		await process_frame
	assert(merchant.snapshot.minute==0,"UI alone must not advance the test world")
	merchant.runtime.shutdown_and_join();merchant.runtime=null;merchant.queue_free();await process_frame
	emit_result({"suite":"original_scenes_headless","global_scene_loaded":true,"merchant_original_host_ready":true,"minute":0,"layouts":sizes,"scope":"HEADLESS_LAYOUT_AND_HOST_NOT_GPU_FPS_OR_HUMAN_GUI"})

func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	output_path=args[1]
	create_timer(180).timeout.connect(func():push_error("ROUND2_STAGE_TIMEOUT");quit(124))
	match args[0]:
		"industry":industry()
		"trade":trade()
		"coupled-fresh":coupled()
		"ui":await ui()
		_:quit(2)

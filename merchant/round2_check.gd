extends SceneTree
## Round2 finite developer worlds. No user save paths or archived worlds are read.
const Base = preload("res://merchant/qa_company_procurement_priority.gd")
const Reference = preload("res://scripts/world/global_commodity_reference.gd")
const Opening = preload("res://merchant/merchant_opening.gd")
const Runtime = preload("res://merchant/merchant_runtime.gd")
const Consumer = preload("res://merchant/consumer_access_opening.gd")
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
	# The original SimulationStep visits native day, wage, travel and transport
	# boundaries itself. Use its existing bounded daily API, as run_global_market.
	var target: int = b.world.game_clock.total_minutes()+minutes
	while b.world.game_clock.total_minutes()<target:
		assert(b.simulation_step.advance_minutes(mini(1440,target-b.world.game_clock.total_minutes())).get("success",true))

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
	var buyer_site: Dictionary=site_row(cfg,"site:regional_food:lyon")
	buyer_site.targets.steel=1
	# Existing optional resale admission requires the buyer's own legal quote.
	# Same-place landed cost is12; quote12 is a zero-spread developer term,
	# common to all three arms, not a forced price increase or promised sale.
	buyer_site.prices.steel=12
	var introduction: String=Base.TEXTILE+"|steel|"+Base.WEAVE
	buyer_site.suppliers.append(introduction)
	cfg.information.append({"actor":buyer_site.id,"kind":"supplier","candidate":introduction,"delivery_day":0})
	cfg["cost_accounting"]={"freight_treatment":"BUYER_ACQUISITION","joint_allocations":[],"npc_policies":[],"basis":"EXPLICIT_DEVELOPMENT_COST_POLICY"}
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
		advance(b,7*1440)
		var totals: Dictionary=e._physical_totals[Base.WEAVE].duplicate(true)
		var made: int=int(totals.produced.steel)
		assert(made>0 if condition=="sufficient" else made==0,"Material scarcity must bind actual production")
		assert(int(totals.used.coal)==made*2 and int(totals.used.iron_ore)==made)
		assert(int(e._stocks[Base.WEAVE].coal)+int(totals.used.coal)==int(initial.coal))
		assert(int(e._stocks[Base.WEAVE].iron_ore)+int(totals.used.iron_ore)==int(initial.iron_ore))
		var lots: Array=[]
		for portion: Dictionary in e._lots.snapshot().portions.values():
			if portion.good in ["coal","iron_ore","steel"]:lots.append(portion)
		var steel_orders: Array=[];var steel_payments: Array=[]
		for order: Dictionary in e._orders.values():
			if order.good=="steel":steel_orders.append(order)
		for tx: Dictionary in b.world.ledger_state.transactions():
			if steel_orders.any(func(order: Dictionary)->bool:return order.id==tx.reference_id):steel_payments.append(tx)
		var delivered: int=int(e._stocks["site:regional_food:lyon"].steel)
		assert(delivered>0 if condition=="sufficient" else delivered==0,"Input limitation must propagate through actual downstream orders and delivery")
		results.append({"condition":condition,"minute":b.world.game_clock.total_minutes(),"initial_inputs":initial,"physical":totals,"final_stock":e._stocks[Base.WEAVE].duplicate(true),"cash_before":cash_before,"cash_after":b.world.ledger_state.balance(e._account(Base.TEXTILE)),"quote":e._price(Base.WEAVE,"steel"),"downstream_steel":delivered,"orders":steel_orders,"payments":steel_payments,"lots":lots,"restore_exact":restore_exact(b)})
	emit_result({"suite":"finite_steel","recipe":{"coal":2,"iron_ore":1,"steel_output":1},"cases":results,"feedback_boundary":"ACTUAL_INPUT_LOTS_TO_STEEL; NO_ASSUMED_MACRO_STOCK_OR_FORCED_PRICE_CHANGE"})

func coupled(legacy_only: bool=false) -> void:
	var cfg: Dictionary=Consumer.configuration("consumer_combined")
	cfg["cost_accounting"]={"freight_treatment":"BUYER_ACQUISITION","joint_allocations":[],"npc_policies":[],"basis":"EXPLICIT_DEVELOPMENT_COST_POLICY"}
	var opening: WorldBuildResult=fresh(cfg,true)
	assert(opening.success,opening.error)
	assert(Consumer.apply_condition(opening.world,"consumer_combined").get("accepted",false))
	opening.world.economy_r1._dated_input_procurement_enabled=true
	advance(opening,24*1440)
	var initial: Dictionary=opening.persistence.snapshot()
	var source_bytes: PackedByteArray=var_to_bytes(initial)
	var rows: Array=[]
	for enabled: bool in ([true] if legacy_only else [false,true]):
		var b: WorldBuildResult=FormalPersistence.new().restore_candidate(initial)
		assert(b.success,b.error)
		var e: EconomyR1Slice=b.world.economy_r1
		e._dated_input_procurement_enabled=true
		var begin: Dictionary={"cash":b.world.ledger_state.balance(e._account(Base.FOOD)),"stock":e._stocks[Base.BAKERY].duplicate(true),"production":e._physical_totals[Base.BAKERY].duplicate(true),"costs":e._costs.view(Base.FOOD,30)}
		if enabled:assert(b.world.economy_state.enable_reference_market("shocks"))
		var started: int=Time.get_ticks_usec()
		advance(b,30*1440)
		var orders: Array=[];var decisions: Array=[]
		for order: Dictionary in e._orders.values():
			if order.buyer==Base.FOOD and order.good=="grain" and int(order.accepted_minute)>=24*1440:orders.append(order.duplicate(true))
		for entry: Dictionary in e._commands.values():
			if entry.result.get("decision",{}).has("public_reference_bulletin"):decisions.append({"minute":entry.envelope.command.minute,"action_id":entry.envelope.command.action_id,"result":entry.result})
		rows.append({"enabled":enabled,"begin":begin,"end":{"cash":b.world.ledger_state.balance(e._account(Base.FOOD)),"stock":e._stocks[Base.BAKERY].duplicate(true),"production":e._physical_totals[Base.BAKERY].duplicate(true),"costs":e._costs.view(Base.FOOD,30)},"grain_orders":orders,"reference_decisions":decisions,"reference_local":b.world.economy_state.reference_market.data.local if enabled else {},"simulation_us":Time.get_ticks_usec()-started,"restore_exact":restore_exact(b)})
	assert(var_to_bytes(initial)==source_bytes)
	emit_result({"suite":"fresh_same_start_formal_30_days","start_minute":24*1440,"same_initial_snapshot":true,"conditions":rows,"old_baseline":{"cash":[125,103],"bread_cumulative":96,"grain_orders_each":12,"index_evaluations":9,"index_price_changes":0},"comparability":"NEW_REGIONAL_DAY24_FIXTURE_NOT_ARCHIVED_PLAYER_TRIAL; DIFFERENT_INITIAL_CONDITIONS_EXPLICIT"})

func add_channel(cfg: Dictionary, link: Dictionary) -> Dictionary:
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
	return cfg

func trade() -> void:
	var catalog: VNextSpatialCatalog=VNextSpatialCatalog.new()
	assert(catalog.load_legacy_world_map())
	var link: Dictionary={}
	for candidate: Dictionary in catalog.links():
		if candidate.link_type=="shipping" and [candidate.from_place_id,candidate.to_place_id].has("place:port_london") and [candidate.from_place_id,candidate.to_place_id].has("place:port_le_havre"):link=candidate;break
	assert(not link.is_empty(),"No actual London port-Le Havre host shipping link")
	var cfg: Dictionary=add_channel(EconomyDevelopmentConfig.regional_template(),link)
	var seller: String="firm:round2_london";var buyer: String="firm:round2_havre"
	var ss: String="site:round2_london:port";var bs: String="site:round2_havre:port"
	var b: WorldBuildResult=fresh(cfg)
	var e: EconomyR1Slice=b.world.economy_r1
	assert(b.world.economy_state.enable_reference_market("baseline"))
	var domestic_opening: int=0
	for point: String in e._stocks:
		if b.world.spatial_catalog.get_place(e._place(point)).get("parent_country_id")=="country_fra":domestic_opening+=int(e._stocks[point].get("grain",0))
	assert(int(b.world.economy_state.reference_market.data.local.regions.country_fra.stock_native)==domestic_opening,"UK grain must not be counted as French stock")
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
	emit_result({"suite":"real_channel_order","host_link":link,"from":catalog.get_place("place:port_london"),"to":catalog.get_place("place:port_le_havre"),"london_city_is_not_port":catalog.get_place("place:london").place_id!=catalog.get_place("place:port_london").place_id,"currency_terms":"BOTH_DEVELOPMENT_FIRMS_CONTRACT_IN_EXISTING_FORMAL_DENOMINATION; NO_FX_REQUIRED; NOT_HISTORICAL_GBP_CLAIM","before":before,"accepted":accepted,"reserved_cash":reserved,"offer":offer,"orders":orders,"stages":stages,"transactions":transactions,"lots":lots,"after":{"buyer_stock":e._stocks[bs].grain,"seller_stock":e._stocks[ss].grain,"buyer_cash":b.world.ledger_state.balance(e._account(buyer))},"domestic_opening_stock":domestic_opening,"reference_local":b.world.economy_state.reference_market.data.local,"restore_exact":restore_exact(b),"feedback_boundary":"CROSS_BORDER_REAL_STOCK_ORDER_CAPACITY_CARGO_LEDGER; DOMESTIC_SAMPLE_EXCLUDES_FOREIGN_STOCK; GLOBAL_ESTIMATED_FLOWS_ARE_SEPARATE"})

func grain_decisions(e: EconomyR1Slice, after: int) -> Array:
	var result: Array=[]
	for entry: Dictionary in e._commands.values():
		var cmd: Dictionary=entry.envelope.command
		if int(cmd.minute)>=after and entry.result.get("decision",{}).has("reference_evaluation"):
			result.append({"minute":cmd.minute,"action_id":cmd.action_id,"result":entry.result})
	return result

func grain_followup() -> void:
	var catalog: VNextSpatialCatalog=VNextSpatialCatalog.new()
	assert(catalog.load_legacy_world_map())
	var link: Dictionary={}
	for candidate: Dictionary in catalog.links():
		if candidate.link_type=="shipping" and [candidate.from_place_id,candidate.to_place_id].has("place:port_london") and [candidate.from_place_id,candidate.to_place_id].has("place:port_le_havre"):link=candidate;break
	assert(not link.is_empty())
	var cfg: Dictionary=add_channel(Consumer.configuration("consumer_combined"),link)
	cfg["cost_accounting"]={"freight_treatment":"BUYER_ACQUISITION","joint_allocations":[],"npc_policies":[],"basis":"EXPLICIT_DEVELOPMENT_COST_POLICY"}
	var opening: WorldBuildResult=fresh(cfg,true)
	assert(Consumer.apply_condition(opening.world,"consumer_combined").get("accepted",false))
	opening.world.economy_r1._dated_input_procurement_enabled=true
	advance(opening,24*1440)
	assert(opening.world.economy_state.enable_reference_market("shocks"))
	var e0: EconomyR1Slice=opening.world.economy_r1
	var buyer: String="firm:round2_havre";var seller: String="firm:round2_london"
	var ss: String="site:round2_london:port";var bs: String="site:round2_havre:port"
	var offer: Dictionary=e0._offer(buyer,seller,"grain","edge:round2_channel",ss,bs)
	var cmd: Dictionary=e0._auto_command(buyer,"buy",{"quote_id":offer.quote_id,"seller":seller,"seller_site":ss,"buyer_site":bs,"good":"grain","quantity":2,"max_price":offer.price,"denomination":offer.denomination,"path_id":offer.route_id},"GRAIN_FOLLOWUP_CHANNEL")
	var accepted: Dictionary=e0.submit_internal(buyer,cmd)
	assert(accepted.get("accepted",false),str(accepted))
	var initial: Dictionary=opening.persistence.snapshot()
	var initial_bytes: PackedByteArray=var_to_bytes(initial)
	var target_firm: String="firm:regional_upstream"
	var cases: Array=[]
	for condition: String in ["adopt","ignore_native_flows","ignore_target_signal"]:
		var b: WorldBuildResult=FormalPersistence.new().restore_candidate(initial)
		assert(b.success,b.error)
		assert(b.persistence.snapshot().economy_native==initial.economy_native and b.persistence.snapshot().ledger==initial.ledger)
		var e: EconomyR1Slice=b.world.economy_r1
		e._dated_input_procurement_enabled=true
		var reference: RefCounted=b.world.economy_state.reference_market
		reference.data.local.adopt_flows=condition!="ignore_native_flows"
		e._local_quotes.ignored_reference_firm=target_firm if condition=="ignore_target_signal" else ""
		var before_zero: Dictionary=b.persistence.snapshot()
		b.simulation_step.advance_minutes(0)
		assert(b.persistence.snapshot()==before_zero,"Zero time cannot accumulate flows, notices or payments")
		assert(e.submit_internal(buyer,cmd)==accepted and b.persistence.snapshot()==before_zero,"Duplicate accepted cargo command cannot create a second order")
		var marks: Array=[];var deliveries: Array=[];var restore_checked: bool=false
		var all_locked: Dictionary={}
		for order: Dictionary in e._orders.values():all_locked[order.id]=order.price
		for elapsed: int in 30:
			advance(b,1440)
			var local: Dictionary=reference.data.local.duplicate(true)
			var native_before: Dictionary=e.snapshot()
			var ref_before: Dictionary=reference.data.duplicate(true)
			reference._observe_native(e);reference.settle(e.day,e)
			assert(reference.data==ref_before and e.snapshot()==native_before,"Same boundary adoption must be idempotent")
			for order: Dictionary in e._orders.values():
				if all_locked.has(order.id):assert(order.price==all_locked[order.id],"New notices must not reprice existing contracts")
				all_locked[order.id]=order.price
			deliveries.append_array(local.deliveries)
			marks.append({"day":e.day,"cell":reference.data.cells["country_fra|wheat"].duplicate(true),"sample":local.regions.duplicate(true),"channel_buyer_stock":e._stocks[bs].grain})
			# Compare one uninterrupted next day with a restored next day. The same
			# finite research treatment is reapplied; no receipts are injected.
			if elapsed==5:
				var snap: Dictionary=b.persistence.snapshot()
				var restored: WorldBuildResult=FormalPersistence.new().restore_candidate(snap)
				assert(restored.success,restored.error)
				assert(restored.persistence.snapshot().economy==snap.economy)
				restored.world.economy_r1._dated_input_procurement_enabled=true
				restored.world.economy_r1._local_quotes.ignored_reference_firm=e._local_quotes.ignored_reference_firm
				advance(restored,1440)
				var next_snap: Dictionary=restored.persistence.snapshot()
				# Retain comparison until the normal branch reaches that day.
				before_zero=next_snap
			elif elapsed==6:
				for key: String in ["economy","economy_native","ledger","total_minutes","organization_responsibilities"]:assert(b.persistence.snapshot()[key]==before_zero[key],key)
				restore_checked=true
		var orders: Array=[];var payments: Array=[];var received_quotes: Array=[];var refusals: Array=[]
		for order: Dictionary in e._orders.values():
			if order.good=="grain" and int(order.accepted_minute)>=24*1440:orders.append(order.duplicate(true))
		for tx: Dictionary in b.world.ledger_state.transactions():
			if orders.any(func(o: Dictionary)->bool:return o.id==tx.reference_id):payments.append(tx)
		for receipt: Dictionary in e._receipts.values():
			if receipt.kind=="goods_quote" and e._local_quotes.quotes[receipt.candidate].good=="grain" and int(receipt.delivery_day)>=24:received_quotes.append(receipt)
		for entry: Dictionary in e._commands.values():
			if entry.envelope.command.kind=="buy" and entry.envelope.command.payload.get("good")=="grain" and int(entry.envelope.command.minute)>=24*1440 and not entry.result.get("accepted",false):refusals.append(entry)
		var source_rows: Array=[];var portion_rows: Array=[]
		for source: Dictionary in e._lots.sources.values():
			if source.good=="grain" and int(source.formed_minute)>=24*1440:source_rows.append(source)
		for portion: Dictionary in e._lots.portions.values():
			if portion.good=="grain" and (portion.acquisition_id==accepted.order_id or str(portion.location).contains("round2")):portion_rows.append(portion)
		assert(int(e._stocks[bs].grain)==2)
		cases.append({"condition":condition,"marks":marks,"decisions":grain_decisions(e,24*1440),"grain_orders":orders,"grain_payments":payments,"grain_quote_receipts":received_quotes,"grain_refusals":refusals,"observed_deliveries":deliveries,"grain_sources":source_rows,"channel_portions":portion_rows,"zero_time_unchanged":true,"repeat_adoption_unchanged":true,"restore_continuation_equal":restore_checked,"restore_exact":restore_exact(b)})
	assert(var_to_bytes(initial)==initial_bytes)
	# Legacy snapshots retain exactly their legacy sampling boundary. No V2
	# production block or historical native receipt is attached during restore.
	var legacy: Dictionary=initial.duplicate(true)
	legacy.economy.reference_market.local={"basis":"DEVELOPMENT_GRAIN_WHEAT_SAMPLE_1_NATIVE_UNIT_1_KG_NOT_ALL_FRANCE","produced_total":0,"used_total":0,"produced_tonnes":0.0,"used_tonnes":0.0,"baseline_produced":0.0,"baseline_used":0.0,"grain_stock_native":0,"delivered_all_goods_native_today":0}
	var old: WorldBuildResult=FormalPersistence.new().restore_candidate(legacy)
	assert(old.success,old.error)
	var old_sample: Dictionary=old.world.economy_state.reference_market.data.local.duplicate(true)
	advance(old,1440)
	assert(old.world.economy_state.reference_market.data.local==old_sample,"Old snapshots must not gain new sample contributions")
	emit_result({"suite":"grain_wheat_finite_followup","start_minute":24*1440,"days":30,"same_initial_snapshot":true,"target_firm":target_firm,"channel_order":accepted,"host_link":link,"opening_sample":initial.economy.reference_market.local,"wheat_definition":opening.world.economy_state.commodity_definition("wheat"),"place_mapping":{"london_city":catalog.get_place("place:london"),"london_port":catalog.get_place("place:port_london"),"le_havre_port":catalog.get_place("place:port_le_havre"),"british_statistical_node":initial.economy.reference_market.nodes.british_isles_1900},"cases":cases,"legacy_no_backfill":true,"trade_import_adoption":"UNVERIFIED_NO_IDENTIFIED_MACRO_FLOW_COVERAGE","macro_units":"DEVELOPMENT_TONNES_PER_DAY; BASE_TONNES_PER_DAY; COVER_BASE_DAYS; INDEX_DIMENSIONLESS"})

func grain_quotations() -> void:
	var cfg: Dictionary=Consumer.configuration("consumer_combined")
	var farm: String="site:regional_upstream:lyon"
	var seller: String="firm:regional_upstream"
	var bakery: String="site:regional_food:paris"
	var original_buffer: int=int(site_row(cfg,farm).targets.grain)
	var original_assets: Dictionary=Consumer.Multi.totals(cfg)
	# One predeclared operating scenario: produce against observed orders without
	# the eight-unit finished-grain buffer. No opening asset or recipe is removed.
	site_row(cfg,farm).targets.grain=0
	assert(Consumer.Multi.totals(cfg)==original_assets)
	cfg["cost_accounting"]={"freight_treatment":"BUYER_ACQUISITION","joint_allocations":[],"npc_policies":[],"basis":"EXPLICIT_DEVELOPMENT_COST_POLICY"}
	var opening: WorldBuildResult=fresh(cfg,true)
	assert(Consumer.apply_condition(opening.world,"consumer_combined").get("accepted",false))
	opening.world.economy_r1._dated_input_procurement_enabled=true
	advance(opening,24*1440)
	assert(opening.world.economy_state.enable_reference_market("shocks"))
	var initial: Dictionary=opening.persistence.snapshot()
	var initial_bytes: PackedByteArray=var_to_bytes(initial)
	var rule: Dictionary=opening.world.economy_r1._local_quotes.rule(farm,"grain")
	# Reuse prior actual records, not a rerun of the old blocked world. The same
	# function used by NPCs calculates all detached historical attributions.
	var arguments: PackedStringArray=OS.get_cmdline_user_args()
	var history: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(arguments[2]))
	var historical: Array=[]
	for row: Dictionary in history.grain_followup_20261025.historical_reconstruction.decisions:
		var v: Dictionary=opening.world.economy_r1._local_quotes.quotation_step(rule,int(row.opening_price),int(row.current_price),int(row.free_stock),int(row.recent_delivered),int(row.cash_refused),true,float(row.index))
		var n: Dictionary=opening.world.economy_r1._local_quotes.quotation_step(rule,int(row.opening_price),int(row.current_price),int(row.free_stock),int(row.recent_delivered),int(row.cash_refused),true,100.0)
		historical.append({"decision_day":row.decision_day,"received_index":row.index,"free_stock":row.free_stock,"delivered":row.recent_delivered,"cash_refused":row.cash_refused,"current_price":row.current_price,"actual_value":v,"neutral_100":n})
	var old_orders: Array=[]
	for order: Dictionary in initial.economy_native.orders.values():
		if order.seller==seller and order.good=="grain":old_orders.append(order)
	var cases: Array=[]
	for adopt: bool in [true,false]:
		var b: WorldBuildResult=FormalPersistence.new().restore_candidate(initial)
		assert(b.success,b.error)
		assert(b.persistence.snapshot().economy_native==initial.economy_native and b.persistence.snapshot().ledger==initial.ledger)
		var e: EconomyR1Slice=b.world.economy_r1
		e._dated_input_procurement_enabled=true
		e._local_quotes.ignored_reference_firm="" if adopt else seller
		var reference: RefCounted=b.world.economy_state.reference_market
		var baseline: Dictionary=b.persistence.snapshot()
		b.simulation_step.advance_minutes(0)
		assert(b.persistence.snapshot()==baseline)
		var marks: Array=[];var order_adoptions: Dictionary={};var locked: Dictionary={}
		var continuation: Dictionary={};var restored_equal: bool=false
		for order: Dictionary in e._orders.values():locked[order.id]=order.price
		for elapsed: int in 30:
			advance(b,1440)
			for order: Dictionary in e._orders.values():
				if locked.has(order.id):assert(order.price==locked[order.id],"A later quote cannot reprice accepted orders")
				locked[order.id]=order.price
				if order.seller!=seller or order.good!="grain" or int(order.accepted_minute)<=24*1440 or order_adoptions.has(order.id):continue
				var q: Dictionary=e._local_quotes.current(farm,"grain",int(order.accepted_minute))
				var known: Dictionary=e._local_quotes.known(e._inventory_key(order.buyer,order.buyer_site),farm,"grain",int(order.accepted_minute))
				assert(q.id==known.id and int(q.price)==int(order.price) and int(q.effective_day)*1440<=int(order.accepted_minute))
				var reservation: Dictionary=b.world.ledger_state._reservations.get(order.id,{}).duplicate(true)
				var reserved_lots: Array=[]
				for portion: Dictionary in e._lots.portions.values():
					if portion.reserved_for==order.id:reserved_lots.append(portion.duplicate(true))
				order_adoptions[order.id]={"order_at_observation":order.duplicate(true),"quote":q.duplicate(true),"known_quote":known.duplicate(true),"reservation":reservation,"site_reserved_quantity":e._committed(farm,"grain"),"physical_reservation_portions":reserved_lots,"command":e._commands[order.action_id].duplicate(true)}
				var unchanged: Dictionary=b.persistence.snapshot()
				var command: Dictionary=e._commands[order.action_id].envelope.command
				assert(e.submit_internal(order.buyer,command)==e._commands[order.action_id].result)
				assert(b.persistence.snapshot()==unchanged,"Replaying the accepted buy cannot duplicate reservation or settlement")
			var offers: Array=[]
			for offer: Dictionary in e._offers("firm:regional_food",bakery,"grain"):
				offers.append({"seller":offer.seller,"site":offer.seller_site,"price":offer.price,"quantity":offer.quantity,"reason":offer.reason,"published_quote_id":offer.get("published_quote_id","")})
			var bulletin: Dictionary=reference.received_bulletin(seller,"wheat",e.day)
			marks.append({"day":e.day,"reference_price":reference.data.cells["country_fra|wheat"].price,"received_bulletin":bulletin,"stock":e._stocks[farm].grain,"committed":e._committed(farm,"grain"),"produced_total":e._physical_totals[farm].produced.grain,"observed_daily_orders":e._observed_daily_orders(farm,"grain"),"grain_plan":e._plans[farm].activities.get("activity:regional_grain",{}).duplicate(true),"buyer_grain_stock":e._stocks[bakery].grain,"buyer_grain_used_total":e._physical_totals[bakery].used.grain,"buyer_bread_produced_total":e._physical_totals[bakery].produced.bread,"buyer_offers":offers})
			var same: Dictionary=b.persistence.snapshot()
			reference.settle(e.day,e);e.advance_time();b.simulation_step.advance_minutes(0)
			assert(b.persistence.snapshot()==same,"Repeated boundaries cannot redeliver or pay again")
			if elapsed==5:
				var rebuilt: WorldBuildResult=FormalPersistence.new().restore_candidate(same)
				assert(rebuilt.success,rebuilt.error)
				rebuilt.world.economy_r1._dated_input_procurement_enabled=true
				rebuilt.world.economy_r1._local_quotes.ignored_reference_firm=e._local_quotes.ignored_reference_firm
				advance(rebuilt,1440)
				continuation=rebuilt.persistence.snapshot()
			elif elapsed==6:
				for key: String in ["total_minutes","economy","economy_native","ledger","organization_responsibilities"]:assert(b.persistence.snapshot()[key]==continuation[key],key)
				restored_equal=true
		var orders: Array=[];var payments: Array=[];var quote_rows: Array=[];var receipts: Array=[];var deliveries: Array=[];var refused: Array=[]
		for order: Dictionary in e._orders.values():
			if order.seller==seller and order.good=="grain" and int(order.accepted_minute)>24*1440:orders.append(order.duplicate(true))
		for tx: Dictionary in b.world.ledger_state.transactions():
			if not orders.any(func(o: Dictionary)->bool:return o.id==tx.reference_id):continue
			payments.append(tx)
			var unchanged: Dictionary=b.world.ledger_state.snapshot()
			assert(b.world.ledger_state.transfer(tx.transaction_id,tx.from_account_id,tx.to_account_id,tx.amount,tx.effective_minute,tx.kind,tx.reference_id))
			assert(b.world.ledger_state.snapshot()==unchanged,"Original payment ID must not pay twice")
		for q: Dictionary in e._local_quotes.quotes.values():
			if q.site==farm and q.good=="grain":quote_rows.append(q)
		for r: Dictionary in e._receipts.values():
			if r.kind=="goods_quote" and quote_rows.any(func(q: Dictionary)->bool:return q.id==r.candidate):receipts.append(r)
		for r: Dictionary in e._delivery_receipts.values():
			if orders.any(func(o: Dictionary)->bool:return o.id==r.order_id):deliveries.append(r)
		for entry: Dictionary in e._commands.values():
			var command: Dictionary=entry.envelope.command
			if command.kind=="buy" and command.payload.get("seller")==seller and command.payload.get("good")=="grain" and int(command.minute)>24*1440 and not entry.result.get("accepted",false):refused.append(entry)
		var decisions: Array=[]
		for row: Dictionary in grain_decisions(e,24*1440+1):
			if row.result.decision.reference_evaluation.firm==seller:decisions.append(row)
		cases.append({"condition":"adopt_received_index" if adopt else "ignore_target_signal","marks":marks,"decisions":decisions,"quotes":quote_rows,"quote_receipts":receipts,"grain_orders":orders,"order_adoptions":order_adoptions,"grain_payments":payments,"deliveries":deliveries,"grain_refusals":refused,"opening_old_orders":old_orders,"old_prices_unchanged":true,"zero_time_unchanged":true,"repeat_adoption_unchanged":true,"repeat_payment_unchanged":true,"restore_continuation_equal":restored_equal,"restore_exact":restore_exact(b)})
	assert(var_to_bytes(initial)==initial_bytes)
	emit_result({"suite":"grain_quotation_causality_30_days","start_minute":24*1440,"days":30,"same_initial_snapshot":true,"scenario":{"basis":"ONE_PREDECLARED_MAKE_TO_ORDER_GRAIN_BUFFER_VARIANT_NOT_HISTORICAL_OR_RETUNED","original_buffer":original_buffer,"grain_buffer":0,"opening_farm_grain":site_row(cfg,farm).stock.grain,"opening_farm_price":site_row(cfg,farm).prices.grain,"asset_totals_unchanged":true,"runtime_actions":"COMMON_EXISTING_TRANSPORT_SETUP_THEN_AUTONOMOUS_NATIVE_FIRMS; NO_SCRIPT_BUY_OR_PRICE_COMMANDS"},"historical_same_input_attribution":historical,"cases":cases,"scope":"ADOPTION_AND_DETACHED_NUMERIC_ATTRIBUTION_SEPARATE; NEUTRAL_100_IS_NOT_NEWS_OR_A_TRADING_WORLD; UNKNOWN_IMPORT_COVERAGE_UNCHANGED"})

func ui() -> void:
	var probe: WorldBuildResult=fresh(EconomyDevelopmentConfig.regional_template(),true)
	assert(probe.world.economy_state.enable_reference_market("shocks"))
	advance(probe,3*1440)
	var reference: RefCounted=probe.world.economy_state.reference_market
	var public: Dictionary=reference.observe_public()
	assert(public.day==reference.data.day-2 and public.flows.is_empty() and public.local.is_empty())
	assert(not public.cells["country_fra|wheat"].has("supply"),"Public index must not leak research supply or accounts")
	var global_scene: Node=load("res://merchant/global_market.tscn").instantiate()
	root.add_child(global_scene)
	await process_frame
	assert(global_scene.runtime==null,"Scene load must not open archived research save")
	global_scene.map_view.update_snapshot({"global_market":reference.observe(),"minute":probe.world.game_clock.total_minutes()})
	var map_deadline: int=Time.get_ticks_msec()+30000
	while not global_scene.map_view.map_base.loaded:
		assert(Time.get_ticks_msec()<map_deadline,"Original globe did not load")
		await process_frame
	var sizes: Array=[]
	for size: Vector2i in [Vector2i(1440,900),Vector2i(390,844)]:
		root.size=size
		await process_frame
		var labels: Array[String]=global_scene.map_view.important_label_ids()
		assert(labels.size()<=5)
		sizes.append({"viewport":str(size),"mode_button":global_scene.map_view.mode_button.text,"estimated_and_physical_separate":true,"label_ids":labels,"side_panel":str(global_scene.map_view.side.size)})
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
	emit_result({"suite":"original_scenes_headless","global_scene_loaded":true,"merchant_original_host_ready":true,"minute":0,"public_index_delay_days":2,"public_has_no_private_supply_or_flows":true,"layouts":sizes,"scope":"HEADLESS_LAYOUT_AND_HOST_NOT_GPU_FPS_OR_HUMAN_GUI"})

func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	output_path=args[1]
	create_timer(180).timeout.connect(func():push_error("ROUND2_STAGE_TIMEOUT");quit(124))
	match args[0]:
		"industry":industry()
		"trade":trade()
		"coupled-fresh":coupled()
		"coupled-reasons":coupled(true)
		"grain-followup":grain_quotations()
		"grain-flows-history":grain_followup()
		"ui":await ui()
		_:quit(2)

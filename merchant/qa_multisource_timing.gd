extends SceneTree
const Opening=preload("res://merchant/merchant_opening.gd")
const BUYER="firm:regional_food"
const SITE="site:regional_food:paris"
const LOCAL="site:merchant_prototype:paris"
const REMOTE="site:regional_upstream:lyon"
const Allocation=preload("res://merchant/multisource_opening.gd")
var started: int=Time.get_ticks_msec()
var completed: bool=false
func _process(_delta: float) -> bool:
	if not completed and Time.get_ticks_msec()-started>60000:push_error("Timing experiment did not finish within60s");quit(1)
	return false
func _initialize() -> void:call_deferred("run")

func configuration() -> Dictionary:
	var cfg: Dictionary=Opening.regional_configuration()
	var original: Dictionary=Allocation.totals(cfg)
	cfg.case_id="MULTISOURCE_TIMING_LEGAL_INITIAL_REALLOCATION"
	if "npc_manager" in OS.get_cmdline_user_args():
		cfg.firm_management_permissions=[] # No automatic person-only succession permit for a collective manager.
		for firm: Dictionary in cfg.firms:
			if firm.id==BUYER:firm.manager="cohort:regional:paris_food"
	for firm: Dictionary in cfg.firms:
		for site: Dictionary in firm.sites:
			# Reallocate existing initial grain, never insert goods in a live world.
			if site.id==LOCAL:site.stock.grain=4
			if site.id==REMOTE:site.stock.grain+=2 # +6 from bakery, -4 local stock
			if site.id==SITE:site.stock.grain=0
	if "narrow_capacity" in OS.get_cmdline_user_args():cfg.route.capacity=1
	for route: Dictionary in cfg.routes:
		if route.id=="edge:regional:lyon:paris":
			route.delay=6
			if "unknown_arrival" in OS.get_cmdline_user_args():route.capacity_manager=BUYER
	if "no_timely_stock" in OS.get_cmdline_user_args():
		Allocation.site(cfg,LOCAL).stock.grain-=4;Allocation.site(cfg,REMOTE).stock.grain+=4
	if "no_cash" in OS.get_cmdline_user_args():
		for firm: Dictionary in cfg.firms:
			if firm.id==BUYER:firm.cash-=138
			if firm.id=="firm:regional_upstream":firm.cash+=138
	if "human_manager" in OS.get_cmdline_user_args():
		cfg.firms.sort_custom(func(a: Dictionary,b: Dictionary):return a.id==BUYER and b.id!=BUYER)
	assert(Allocation.totals(cfg)==original)
	return cfg

func record(built: WorldBuildResult) -> Dictionary:
	var e: EconomyR1Slice=built.world.economy_r1
	var before: Dictionary=built.persistence.snapshot()
	var need: Dictionary=e._input_need(SITE,"grain")
	var offers: Array=e._input_offers(SITE,"grain",int(need.need_by_day),maxi(int(need.regular_quantity),int(need.timing_projection.uncovered_future_quantity)),need)
	assert(before==built.persistence.snapshot(),"Diagnosis changed formal state")
	var orders: Array=[]
	for row: Dictionary in e._orders.values():
		if row.buyer==BUYER and row.good=="grain":orders.append(row.duplicate(true))
	return {"minute":built.world.game_clock.total_minutes(),"manager":e.firm_manager_at(BUYER,built.world.game_clock.total_minutes()),"need":need,"ranked":offers,"orders":orders,"buyer_stock":e._stocks[SITE].duplicate(),"buyer_physical_totals":e._physical_totals[SITE].duplicate(true),"buyer_cash":built.world.ledger_state.balance(e._account(BUYER)),"buyer_reserved":built.world.ledger_state.reserved_balance(e._account(BUYER)),"buyer_available":built.world.ledger_state.available_balance(e._account(BUYER)),"seller_local_stock":e._stocks[LOCAL].duplicate()}

func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var cfg: Dictionary=configuration()
	assert(EconomySliceConfig.valid(cfg))
	var built: WorldBuildResult=WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,false,{"format":"HOST_REGION_SELECTION","person_ids":[],"select_people_at_sites":true,"configuration":cfg})
	assert(built.success,built.error)
	if built.world.economy_r1==null:
		push_error("Native economy unavailable: "+built.world.native_economy_error);quit(1);return
	assert(built.simulation_step.advance_minutes(1).get("success",true))
	var e: EconomyR1Slice=built.world.economy_r1
	e._dated_input_procurement_enabled="--dated-inputs" in args
	if "narrow_capacity" in args:assert(int(e._edge("edge:regional_local:paris").capacity)==1,"Finite first-edge fixture was not installed")
	var offer: Dictionary=e._offer(BUYER,"firm:regional_upstream","grain","edge:regional:lyon:paris",REMOTE,SITE)
	var command: Dictionary=e._auto_command(BUYER,"buy",{"quote_id":offer.quote_id,"seller":offer.seller,"seller_site":REMOTE,"buyer_site":SITE,"good":"grain","quantity":8,"denomination":offer.denomination,"max_price":offer.price,"path_id":offer.route_id,"need_by_day":7},"EXPLICIT_INITIAL_LATE_CONTRACT")
	var accepted: Dictionary=e.submit_internal(BUYER,command)
	assert(accepted.get("accepted",false),str(accepted))
	var unchanged: Dictionary=built.persistence.snapshot()
	assert(e.submit_internal(BUYER,command)==accepted and built.persistence.snapshot()==unchanged,"Command replay duplicated responsibility")
	if "unknown_arrival" in args:
		var closed: Dictionary=e.submit_internal(BUYER,e._auto_command(BUYER,"set_edge_capacity",{"edge_id":"edge:regional:lyon:paris","capacity":0},"EXPLICIT_PENDING_ROUTE_CLOSURE"))
		assert(closed.get("accepted",false),str(closed))
	var records: Array=[record(built)]
	for boundary: int in range(1,9):
		while built.world.game_clock.total_minutes()<boundary*1440:
			assert(built.simulation_step.advance_minutes(mini(60,boundary*1440-built.world.game_clock.total_minutes())).get("success",true))
		var row: Dictionary=record(built);records.append(row)
		print("TIMING_NATIVE day=",e.day," legacy=",row.need.quantity," regular=",row.need.regular_quantity," uncovered=",row.need.timing_projection.uncovered_future_quantity," adoption=",row.need.npc_timing_adoption," orders=",row.orders.size()," local_stock=",row.seller_local_stock.grain)
	if "expect_fixed" in args:
		var local_orders: Array=[]
		for order: Dictionary in e._orders.values():
			if order.buyer==BUYER and order.good=="grain" and order.seller_site==LOCAL:local_orders.append(order)
		var waiting: bool="no_timely_stock" in args or "unknown_arrival" in args or "human_manager" in args
		if waiting:assert(local_orders.is_empty(),"Invented timely purchase despite missing stock/cash/authority or unknown risk hold")
		elif "narrow_capacity" in args:
			var accepted_by_day: Dictionary={}
			for order: Dictionary in e._orders.values():
				if order.route_legs.is_empty() or order.route_legs[0].edge_id!="edge:regional_local:paris":continue
				accepted_by_day[order.accepted_day]=int(accepted_by_day.get(order.accepted_day,0))+int(order.quantity)
			for total: int in accepted_by_day.values():assert(total<=1,"Shared first-edge admission was booked twice")
		else:
			assert(local_orders.size()==1 and local_orders[0].quantity==4 and local_orders[0].accepted_day==2 and local_orders[0].delivered==4,"NPC did not make the finite original timely alternative purchase")
		var old: Dictionary=e._orders[accepted.order_id]
		assert(old.quantity==8 and old.cancelled==0)
		if "unknown_arrival" in args:assert(old.pending==8 and e._lots.reserved_quantity(old.id)==8)
		else:
			assert(old.delivered==8)
			var paid: int=0
			for tx: Dictionary in built.world.ledger_state.transactions():
				if tx.get("reference_id")==old.id:paid+=int(tx.amount)
			assert(paid==32,"Old late order did not pay original goods24+freight8 exactly once")
		if "human_manager" in args:assert(not records[2].need.npc_timing_adoption)
		if "no_cash" in args:assert(records[0].buyer_available==0 and records[0].buyer_reserved==32,"Initial cash constraint was not real")
		var restored: WorldBuildResult=FormalPersistence.new().restore_candidate(built.persistence.snapshot())
		assert(restored.success,restored.error)
		for key: String in ["economy_native","ledger","total_minutes"]:assert(restored.persistence.snapshot()[key]==built.persistence.snapshot()[key])
	var file: FileAccess=FileAccess.open(args[0],FileAccess.WRITE)
	var money: Array=[]
	for tx: Dictionary in built.world.ledger_state.transactions():
		if tx.get("from_account_id")==e._account(BUYER) or tx.get("to_account_id")==e._account(BUYER):money.append(tx)
	file.store_string(JSON.stringify({"seed_command":command,"seed_result":accepted,"records":records,"buyer_ledger":money},"\t"));file.close();completed=true;print("TIMING_CASE_FINISHED");quit()

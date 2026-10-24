extends SceneTree
## Run the same absolute script under either baseline or candidate --path.
## Arguments: original GUI day12 checkpoint, output JSON, optional run label.
## Uses only pre-existing R1 actions/observations. No forced NPC buyer or supply.
const Save=preload("res://merchant/merchant_save.gd")
const Opening=preload("res://merchant/merchant_opening.gd")
const FOOD="firm:regional_food"
const LYON="site:regional_food:lyon"
const PARIS="site:regional_food:paris"
const WINDOW_DAYS: int=12
const MAX_PURCHASES: int=3
func _initialize() -> void:call_deferred("run")
func slim(row: Dictionary,keys: Array) -> Dictionary:
	var result: Dictionary={}
	for key: String in keys:
		if row.has(key):result[key]=row[key]
	return result
func relevant(order: Dictionary) -> bool:
	return order["good"]=="bread" and (order["buyer"]==Opening.FIRM or order["seller"]==Opening.FIRM or order["buyer_site"]==LYON or order["seller_site"]==LYON)
func outstanding(e: EconomyR1Slice) -> int:
	var quantity: int=0
	for order: Dictionary in e._orders.values():
		if order["good"]=="bread" and (order["buyer"]==Opening.FIRM or order["seller"]==Opening.FIRM):quantity+=int(order["pending"])+int(order["transit"])
	return quantity
func record(built: WorldBuildResult) -> Dictionary:
	var e: EconomyR1Slice=built.world.economy_r1
	var sites: Dictionary={}
	for site: String in [LYON,PARIS,Opening.SITE]:
		var need: Dictionary=e._input_need(site,"bread")
		sites[site]={"on_hand":e._stocks[site]["bread"],"committed":e._committed(site,"bread"),"free":maxi(0,int(e._stocks[site]["bread"])-e._committed(site,"bread")),"incoming":e._exposure(site,"bread")-int(e._stocks[site]["bread"]),"need":slim(need,["quantity","target","need_by_day","conditional_shortfall_day","confirmed_arrivals"]),"reported_surplus":e._reported_surplus(site,"bread")}
	var held: Array=[]
	for portion: Dictionary in e._lots.portions.values():
		if portion["good"]=="bread" and int(portion["remaining"])>0 and (portion["owner"]==Opening.FIRM or portion["location"]=="SITE|"+LYON):held.append(slim(portion,["id","parent_portion_id","source_id","remaining","owner","location","acquisition_id","reserved_for"]))
	return {"minute":built.world.game_clock.total_minutes(),"merchant_cash":built.world.ledger_state.balance(e._account(Opening.FIRM)),"merchant_reserved":built.world.ledger_state.reserved_balance(e._account(Opening.FIRM)),"food_cash":built.world.ledger_state.balance(e._account(FOOD)),"sites":sites,"held_relevant_portions":held,"merchant_outstanding_bread":outstanding(e)}
func lyon_offer(built: WorldBuildResult,quantity: int) -> Dictionary:
	var e: EconomyR1Slice=built.world.economy_r1
	var offset: int=0
	while true:
		var business: Dictionary=e.business_view(built.world.player_state.player_id(),Opening.FIRM,Opening.SITE,quantity,offset,16)
		for offer: Dictionary in business.get("offers",[]):
			if offer["good"]=="bread" and offer["seller_site"]==LYON:return offer
		offset+=16
		if offset>=int(business.get("offer_total",0)):break
	return {}
func attempt_purchase(built: WorldBuildResult) -> Dictionary:
	var e: EconomyR1Slice=built.world.economy_r1
	if int(e._stocks[Opening.SITE]["bread"])>0 or outstanding(e)>0:return {"decision":"WAIT_OWN_STOCK_OR_EXISTING_RESPONSIBILITY"}
	var selected: Dictionary=lyon_offer(built,2)
	if selected.is_empty():return {"decision":"WAIT_NO_KNOWN_LYON_SOURCE"}
	if not selected.get("can_order",false) and int(selected.get("quantity",0))==1:selected=lyon_offer(built,1)
	if not selected.get("can_order",false):return {"decision":"WAIT_NO_EXECUTABLE_LYON_SOURCE","offer":slim(selected,["price","quantity","freight_per_unit","earliest_arrival_day","reason","can_order"])}
	var result: Dictionary=LivelihoodAction.execute_current(built.world,"buy",selected["request"])
	return {"decision":"BUY_AT_MOST_TWO_AFTER_PREVIOUS_EXPOSURE_CLEARS","offer":slim(selected,["seller","seller_site","price","quantity","freight_per_unit","earliest_arrival_day","reason"]),"result":result}
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var raw: Dictionary=Save._read(args[0],5);assert(raw.get("error","").is_empty())
	var built: WorldBuildResult=FormalPersistence.new().restore_candidate(raw["core"]);assert(built.success)
	var e: EconomyR1Slice=built.world.economy_r1
	assert(built.world.game_clock.total_minutes()==15841)
	var start_order: int=e.next_order
	var start_minute: int=built.world.game_clock.total_minutes()
	var records: Array=[record(built)];var decisions: Array=[];var purchases: int=0
	for elapsed: int in range(WINDOW_DAYS):
		if purchases<MAX_PURCHASES:
			var decision: Dictionary=attempt_purchase(built)
			decision["minute"]=built.world.game_clock.total_minutes();decisions.append(decision)
			if decision.get("result",{}).get("accepted",false):purchases+=1
		for hour: int in range(24):assert(built.simulation_step.advance_minutes(60).get("success",true))
		records.append(record(built))
	var orders: Array=[];var order_ids: Dictionary={};var shipments: Array=[];var receipts: Array=[];var transactions: Array=[];var terminal: Array=[];var sources: Dictionary={}
	for order: Dictionary in e._orders.values():
		if not relevant(order) or int(str(order["id"]).trim_prefix("order:"))<start_order:continue
		orders.append(order.duplicate(true));order_ids[order["id"]]=true
	for shipment: Dictionary in e._shipments.values():
		if order_ids.has(shipment["order_id"]):shipments.append(shipment.duplicate(true))
	for receipt: Dictionary in e._delivery_receipts.values():
		if order_ids.has(receipt["order_id"]):receipts.append(receipt.duplicate(true))
	for payment: Dictionary in built.world.ledger_state.transactions():
		if order_ids.has(payment["reference_id"]):transactions.append(payment.duplicate(true))
	for portion: Dictionary in e._lots.portions.values():
		if portion["good"]!="bread" or int(portion["opened_minute"])<start_minute:continue
		if portion["source_id"]=="opening:"+LYON+":bread":
			sources[portion["id"]]=slim(portion,["id","parent_portion_id","source_id","quantity","remaining","consumed","owner","location","acquisition_id","reserved_for","opened_minute","closed_minute"])
		if int(portion["consumed"])>0 and str(portion["source_id"])=="opening:"+LYON+":bread":terminal.append(slim(portion,["id","source_id","owner","consumed","acquisition_id","opened_minute"]))
	var review: Dictionary=e.managed_trade_review(built.world.player_state.player_id(),Opening.FIRM)
	var output: Dictionary={"label":args[2] if args.size()>2 else "unspecified","same_start_sha256":FileAccess.get_sha256(args[0]),"window_days":WINDOW_DAYS,"maximum_purchases":MAX_PURCHASES,"actual_purchases":purchases,"strategy":"Buy up to2 from current legal Lyon source only when own bread stock and related open responsibility both zero; otherwise wait. NPC decisions remain natural.","records":records,"decisions":decisions,"new_relevant_orders":orders,"active_shipments":shipments,"delivery_receipts":receipts,"ledger_transactions":transactions,"tracked_origin_new_portions":sources,"tracked_origin_actual_consumption":terminal,"final_cash_review":review,"limits":["Domain automation, not GUI.","Finite12-day observation cannot prove indefinite absence of cycles.","No added cash, goods, routes, budgets, price changes or forced buyers.","Policy comparison includes actual candidate NPC changes; it is not proof of a player single-choice effect.","Unfinished cargo and unsold goods retained; no synthetic settlement."]}
	var file=FileAccess.open(args[1],FileAccess.WRITE);assert(file!=null);file.store_string(JSON.stringify(output,"\t"));file.close()
	print("QA_SALES_CYCLES_COMPLETE ",args[1]," purchases=",purchases," minute=",built.world.game_clock.total_minutes()," cash=",records[-1]["merchant_cash"]," inventory=",e._stocks[Opening.SITE]["bread"]," outstanding=",outstanding(e))
	quit()

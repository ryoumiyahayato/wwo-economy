extends SceneTree
const Opening=preload("res://merchant/merchant_opening.gd")
const SITE="site:regional_food:paris"
const FIRM="firm:regional_food"
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var args := OS.get_cmdline_user_args()
	var cfg: Dictionary=Opening.feedback_configuration()
	cfg["case_id"]="TIME_AWARE_LEGAL_INITIAL_VARIANT"
	# Finite explicit opening only. No live-world injection or signed order edit.
	for firm: Dictionary in cfg["firms"]:
		for site: Dictionary in firm["sites"]:
			if site["id"]==Opening.SITE: site["stock"]["grain"]=8
			if site["id"]==SITE: site["stock"]["grain"]=0
			if site["id"]=="site:regional_food:lyon":site["stock"]["grain"]=8
	for route: Dictionary in cfg["routes"]:
		if route["id"]=="edge:regional:lyon:paris":route["delay"]=6
	var b: WorldBuildResult=WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,false,{"format":"HOST_REGION_SELECTION","person_ids":[],"select_people_at_sites":true,"configuration":cfg})
	assert(b.success and Opening.grant_regional_authority(b.world))
	assert(b.simulation_step.advance_minutes(1).get("success",true))
	var e: EconomyR1Slice=b.world.economy_r1
	# Quote notices remain real: day0 upstream quote is not yet received.
	# Let the normal first day accept its own slower supply, rather than
	# fabricating a legal quote or forcing a purchase before information arrives.
	for h: int in range(24):assert(b.simulation_step.advance_minutes(60).get("success",true))
	var old: Dictionary={}
	for order: Dictionary in e._orders.values():
		if order["buyer_site"]==SITE and order["good"]=="grain" and int(order["pending"])+int(order["transit"])>0:
			old={"accepted":true,"order_id":order["id"],"quantity":order["quantity"],"order":order.duplicate(true)};break
	print("INITIAL_NORMAL_NPC_SLOW ",JSON.stringify(old))
	assert(not old.is_empty())
	var envelope: Dictionary=e._commands[old["order"]["action_id"]]["envelope"]
	var command: Dictionary=envelope["command"].duplicate(true)
	var original_result: Dictionary=e._commands[old["order"]["action_id"]]["result"].duplicate(true)
	var before: Dictionary=b.persistence.snapshot()
	assert(e._accept(envelope["actor"],command,true)==original_result and before==b.persistence.snapshot())
	var records: Array=[];var rescue_ids: Array=[];var first_day_orders: Array=[]
	for elapsed: int in range(10):
		for h: int in range(24): assert(b.simulation_step.advance_minutes(60).get("success",true))
		var orders: Array=[]
		for order: Dictionary in e._orders.values():
			if order["buyer_site"]==SITE and order["good"]=="grain":
				orders.append(order.duplicate(true))
				if order["seller"]==Opening.FIRM and int(order["accepted_day"])>1 and int(order["accepted_day"])<7 and order["id"] not in rescue_ids:rescue_ids.append(order["id"])
		if elapsed==0:first_day_orders=orders.duplicate(true)
		records.append({"day":e.day,"minute":b.world.game_clock.total_minutes(),"need":e._input_need(SITE,"grain"),"orders":orders,"cash":b.world.ledger_state.balance(e._account(FIRM)),"stock":e._stocks[SITE]["grain"],"production":e._plans[SITE].duplicate(true),"physical_totals":e._physical_totals[SITE].duplicate(true)})
		if elapsed in [0,1,6,9]:
			var snap: Dictionary=b.persistence.snapshot();var restore: WorldBuildResult=FormalPersistence.new().restore_candidate(snap);assert(restore.success)
			for key: String in ["economy_native","ledger","total_minutes"]:assert(snap[key]==restore.persistence.snapshot()[key])
			restore=null
	var payments: Array=[]
	for tx: Dictionary in b.world.ledger_state.transactions():
		if tx.get("reference_id")==old["order_id"] or tx.get("reference_id") in rescue_ids:payments.append(tx)
	var out := {"case":"LEGAL_INITIAL_QA_VARIANT_NOT_NATURAL_PRODUCT_SAVE","config_changes":["Merchant opening grain8","Food Paris opening grain0","Food Lyon opening grain8 offers real internal surplus","Lyon to Paris route delay6 before world creation"],"old_order":old,"first_day_orders":first_day_orders,"rescues":rescue_ids,"records":records,"payments":payments,"limits":["DOMAIN_AUTOMATION_NOT_GUI","Finite10days","No live cash/goods/capacity injection","Both initial slow order and rescue must be normal NPC strategy after genuine quotation receipt"]}
	var f=FileAccess.open(args[1],FileAccess.WRITE);f.store_string(JSON.stringify(out,"\t"));f.close()
	if args.size()<3 or args[2]!="adoption_baseline":assert(not rescue_ids.is_empty())
	for id: String in rescue_ids:assert(e._orders[id]["delivered"]>0)
	if args.size()<3 or args[2]!="adoption_baseline":
		for order: Dictionary in first_day_orders:
			if order["accepted_day"]==2:assert(order["kind"]!="TRANSFER")
	assert(e._orders[old["order_id"]]["delivered"]==old["quantity"])
	print("QA_TIME_AWARE_ADOPTION_PASS rescues=",rescue_ids," old=",old["order_id"]);quit()

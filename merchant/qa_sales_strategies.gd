extends SceneTree
const Save=preload("res://merchant/merchant_save.gd")
const Opening=preload("res://merchant/merchant_opening.gd")
func _initialize() -> void:call_deferred("run")
func change(b: WorldBuildResult,paused: bool) -> Dictionary:
	var p: String=b.world.player_state.player_id()
	return LivelihoodAction.execute_current(b.world,"set_managed_goods_sales",{"firm":Opening.FIRM,"site":Opening.SITE,"good":"bread","paused":paused,"authorization_context":OrganizationState.acting_context(p,Opening.ORGANIZATION,Opening.ORGANIZATION,Opening.REGIONAL_AUTHORITY,"opening_operator")})
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args();var raw: Dictionary=Save._read(args[0],5);var out: Dictionary={}
	for strategy: String in ["A_local_buy_keep9","B_local_hold_then_quote8_resume"]:
		var built: WorldBuildResult=FormalPersistence.new().restore_candidate(raw["core"]);assert(built.success)
		var e: EconomyR1Slice=built.world.economy_r1;var p: String=built.world.player_state.player_id();var start_order: int=e.next_order
		var actions: Array=[];var records: Array=[];var resumed := strategy=="A_local_buy_keep9";var decided_wait := false
		if not resumed:
			var pause: Dictionary=change(built,true);assert(pause["accepted"]);actions.append({"kind":"pause","result":pause})
		var selected: Dictionary={};var known: Array=[]
		for q: Dictionary in e.business_view(p,Opening.FIRM,Opening.SITE,2,0,16).get("offers",[]):
			if q.get("good")!="bread":continue
			known.append(q["comparison"])
			if q.get("seller_site")=="site:regional_food:paris":selected=q
		assert(selected.get("can_order",false));var purchase: Dictionary=LivelihoodAction.execute_current(built.world,"buy",selected["request"]);assert(purchase["accepted"])
		actions.append({"kind":"buy","known_sources":known,"comparison":selected["comparison"],"result":purchase})
		if not resumed:
			var quote: Dictionary=LivelihoodAction.execute_current(built.world,"post_managed_goods_quote",{"firm":Opening.FIRM,"site":Opening.SITE,"good":"bread","price":8,"authorization_context":OrganizationState.acting_context(p,Opening.ORGANIZATION,Opening.ORGANIZATION,Opening.REGIONAL_AUTHORITY,"opening_operator")});assert(quote["accepted"]);actions.append({"kind":"future_quote8","result":quote})
		for day: int in range(12):
			for hour: int in range(24):assert(built.simulation_step.advance_minutes(60).get("success",true))
			var listing: Dictionary=e._managed_listing_view(Opening.SITE,"bread")
			if not resumed and int(listing["stock_quantity"])>0 and listing["price"]==8:
				var opened: Dictionary=change(built,false);assert(opened["accepted"]);resumed=true;actions.append({"kind":"resume_after_actual_stock_arrival_and_quote_effective","minute":built.world.game_clock.total_minutes(),"listing_before":listing,"result":opened})
			var review: Dictionary=e.managed_trade_review(p,Opening.FIRM)
			if not decided_wait and (review["sales_received"].get(FormalLedgerState.DENOMINATION,0)>34 or day>=4):
				decided_wait=true;actions.append({"kind":"wait_no_next_purchase","minute":built.world.game_clock.total_minutes(),"reason":"Review real sales or held inventory and cash before tying up additional money.","current_inventory":review["current_inventory"],"actual_sales_received":review["sales_received"],"cash":built.world.ledger_state.balance(e._account(Opening.FIRM))})
			records.append({"minute":built.world.game_clock.total_minutes(),"cash":built.world.ledger_state.balance(e._account(Opening.FIRM)),"stock":e._stocks[Opening.SITE]["bread"],"sales_paused":e._local_quotes.sales_paused(Opening.SITE,"bread")})
		var trades: Array=[]
		for order: Dictionary in e._orders.values():
			if int(str(order["id"]).trim_prefix("order:"))>=start_order and (order["buyer"]==Opening.FIRM or order["seller"]==Opening.FIRM):trades.append(order.duplicate(true))
		var snap: Dictionary=built.persistence.snapshot();var candidate: WorldBuildResult=FormalPersistence.new().restore_candidate(snap);assert(candidate.success)
		for key: String in ["economy_native","ledger","total_minutes"]:assert(candidate.persistence.snapshot()[key]==snap[key])
		out[strategy]={"same_start_sha256":FileAccess.get_sha256(args[0]),"window_days":12,"actions":actions,"daily":records,"orders":trades,"final_trade_review":e.managed_trade_review(p,Opening.FIRM),"restore_native_ledger_clock_exact":true,"causality":"Overall strategy comparison: listing price and pause timing differ together. Neither is guaranteed future income."}
		built=null;candidate=null
	var file=FileAccess.open(args[1],FileAccess.WRITE);file.store_string(JSON.stringify(out,"\t"));file.close();print("QA_SALES_STRATEGIES_PASS same start two actual legal decisions each natural NPC12days");quit()

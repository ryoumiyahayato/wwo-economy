extends SceneTree
const Save=preload("res://merchant/merchant_save.gd")
const Opening=preload("res://merchant/merchant_opening.gd")
const Runtime=preload("res://merchant/merchant_runtime.gd")
var checks: Array[String]=[]
var failure: bool=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool, label: String) -> bool:
	if not ok:push_error(label);failure=true;quit(1);return false
	checks.append(label);return true
func control_payload(built: WorldBuildResult, paused: bool, good: String="bread", site: String=Opening.SITE) -> Dictionary:
	return {"firm":Opening.FIRM,"site":site,"good":good,"paused":paused,"authorization_context":OrganizationState.acting_context(built.world.player_state.player_id(),Opening.ORGANIZATION,Opening.ORGANIZATION,Opening.REGIONAL_AUTHORITY,"opening_operator")}
func act(built: WorldBuildResult, paused: bool) -> Dictionary:
	return LivelihoodAction.execute_current(built.world,"set_managed_goods_sales",control_payload(built,paused))
func advance_day(built: WorldBuildResult) -> bool:
	for hour: int in range(24):
		if not check(built.simulation_step.advance_minutes(60).get("success",true),"Original clock advances"):return false
	return true
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var decoded: Dictionary=Save._read(args[0],5)
	var built: WorldBuildResult=FormalPersistence.new().restore_candidate(decoded["core"])
	if not check(built.success,"Legacy day12 candidate restores without optional sales controls"):return
	var e: EconomyR1Slice=built.world.economy_r1
	var person: String=built.world.player_state.player_id()
	var original: Dictionary=built.persistence.snapshot()
	if not check(original["economy_native"]==decoded["core"]["economy_native"],"Missing controls preserve exact native old state"):return
	var ledger: Dictionary=built.world.ledger_state.snapshot()
	var lots: Dictionary=e._lots.snapshot()
	var cmd: Dictionary={"action_id":e.next_person_action_id(),"minute":built.world.game_clock.total_minutes(),"kind":"set_managed_goods_sales","payload":control_payload(built,true)}
	var paused: Dictionary=LivelihoodAction.execute(built.world,person,cmd)
	if not check(paused.get("accepted",false),"Formal authorized bread pause accepted"):return
	if not check(built.world.ledger_state.snapshot()==ledger and e._lots.snapshot()==lots,"Pause does not alter cash or physical lots"):return
	if not check(e._managed_listing_view(Opening.SITE,"bread")["sales_paused"] and not e._managed_listing_view(Opening.SITE,"bread")["active"] and e._managed_listing_view(Opening.SITE,"grain")["active"],"Only selected good stops new spot sales"):return
	var state: Dictionary=built.persistence.snapshot()
	if not check(LivelihoodAction.execute(built.world,person,cmd)==paused and state==built.persistence.snapshot(),"Same-ID replay has no duplicated change"):return
	var conflict: Dictionary=cmd.duplicate(true);conflict["payload"]["paused"]=false
	if not check(LivelihoodAction.execute(built.world,person,conflict).get("reason")=="ACTION_ID_CONFLICT","Same ID changed parameters rejected"):return
	var wrong: Dictionary=control_payload(built,false,"bread","site:regional_food:paris")
	if not check(not LivelihoodAction.execute_current(built.world,"set_managed_goods_sales",wrong).get("accepted",false),"Foreign site request rejected"):return
	wrong=control_payload(built,false);wrong["authorization_context"]["person_id"]="person:unknown"
	if not check(not LivelihoodAction.execute_current(built.world,"set_managed_goods_sales",wrong).get("accepted",false),"Wrong acting person rejected"):return
	if not check(built.world.ledger_state.snapshot()==ledger and e._lots.snapshot()==lots,"Rejected control has no money or stock effects"):return
	var offer: Dictionary={}
	for q: Dictionary in e.business_view(person,Opening.FIRM,Opening.SITE,2,0,16)["offers"]:
		if q.get("good")=="bread" and q.get("seller_site")=="site:regional_food:paris":offer=q
	if not check(offer.get("can_order",false),"Day12 genuine local source is executable"):return
	var buy: Dictionary=LivelihoodAction.execute_current(built.world,"buy",offer["request"])
	if not check(buy.get("accepted",false),"Procurement continues while own sales paused"):return
	var qpayload: Dictionary=control_payload(built,true);qpayload.erase("paused");qpayload["price"]=8
	if not check(LivelihoodAction.execute_current(built.world,"post_managed_goods_quote",qpayload).get("accepted",false),"Future price accepted while sales paused"):return
	if not advance_day(built):return
	if not check(e._managed_listing_view(Opening.SITE,"bread")["sales_paused"] and e._managed_listing_view(Opening.SITE,"bread")["price"]==8,"Effective future price does not resume sales"):return
	var recovered: WorldBuildResult=FormalPersistence.new().restore_candidate(built.persistence.snapshot())
	if not check(recovered.success,"Paused goods and in-transit/arrival candidate restores"):return
	if not check(recovered.persistence.snapshot()==built.persistence.snapshot(),"Paused restore exact across native ledger clock"):return
	recovered=null
	var before_resume: Dictionary=built.persistence.snapshot()
	var result: Dictionary=act(built,false)
	if not check(result.get("accepted",false),"Resume uses current valid quote with original authority"):return
	if not check(not e._managed_listing_view(Opening.SITE,"bread")["sales_paused"],"Resume permits new legitimate buyers"):return
	# Preserve a genuine stale public offer, then pause at the same clock minute.
	var buyer: String="firm:regional_food";var buyer_site: String="site:regional_food:lyon"
	var stale: Dictionary=e._offer(buyer,Opening.FIRM,"bread","edge:regional:paris:lyon",Opening.SITE,buyer_site)
	if not check(act(built,true).get("accepted",false),"Same-minute re-pause adopted before buyer recheck"):return
	ledger=built.world.ledger_state.snapshot();lots=e._lots.snapshot()
	var buycmd: Dictionary={"action_id":"auto:"+buyer+":qa_stale_paused","minute":built.world.game_clock.total_minutes(),"kind":"buy","payload":{"quote_id":stale["quote_id"],"seller":Opening.FIRM,"seller_site":Opening.SITE,"buyer_site":buyer_site,"good":"bread","quantity":1,"path_id":"edge:regional:paris:lyon","denomination":FormalLedgerState.DENOMINATION,"max_price":8}}
	var denied: Dictionary=e._accept(buyer,buycmd,true)
	if not check(denied.get("reason")=="GOODS_NEW_SALES_PAUSED" and ledger==built.world.ledger_state.snapshot() and lots==e._lots.snapshot(),"Old quote rechecked in R1 without cash or lot reservation"):return
	if not check(act(built,false).get("accepted",false),"Second resume remains explicit"):return
	# Expiry is a labelled rejection-only fixture; restore the original immutable
	# quote immediately and never save this altered fixture.
	var current_quote: Dictionary=e._local_quotes.current(Opening.SITE,"bread")
	var original_expiry: int=current_quote["expires_day"]
	current_quote["expires_day"]=e.day
	ledger=built.world.ledger_state.snapshot();lots=e._lots.snapshot()
	var expired: Dictionary=act(built,false)
	current_quote["expires_day"]=original_expiry
	if not check(expired.get("reason")=="GOODS_QUOTE_EXPIRED" and ledger==built.world.ledger_state.snapshot() and lots==e._lots.snapshot(),"Expired quote fixture rejects resume without renewal or effects"):return
	var sales_before: int=e.next_order
	var old_order: String=""
	for hour: int in range(120):
		if not check(built.simulation_step.advance_minutes(60).get("success",true),"Natural NPC clock advances"):return
		for order: Dictionary in e._orders.values():
			if order["seller"]==Opening.FIRM and order["good"]=="bread" and int(str(order["id"]).trim_prefix("order:"))>=sales_before:
				old_order=order["id"];break
		if not old_order.is_empty():break
	if not check(not old_order.is_empty(),"Independent natural buyer accepts resumed legal stock"):return
	var accepted_old: Dictionary=e._orders[old_order].duplicate(true)
	if not check(act(built,true).get("accepted",false),"Pause after genuine accepted sale retains that obligation"):return
	var snap_after_pause: Dictionary=built.persistence.snapshot()
	recovered=FormalPersistence.new().restore_candidate(snap_after_pause)
	if not check(recovered.success and recovered.persistence.snapshot()==snap_after_pause,"Same-minute accepted-old-sale then pause restores"):return
	recovered=null
	for d: int in range(3):
		if not advance_day(built):return
	var fulfilled: Dictionary=e._orders[old_order]
	if not check(fulfilled["price"]==accepted_old["price"] and int(fulfilled["delivered"])==int(fulfilled["quantity"]),"Pre-pause accepted sale keeps locked price and completes delivery"):return
	var actual_paid := 0
	for tx: Dictionary in built.world.ledger_state.transactions():
		if tx.get("reference_id")==old_order and tx.get("kind")=="goods": actual_paid+=int(tx["amount"])
	if not check(actual_paid==int(fulfilled["quantity"])*int(fulfilled["price"]),"Pre-pause accepted sale actually paid via original Ledger"):return

	var runtime=Runtime.new();runtime._slot=5
	var view: Dictionary=runtime._view(built)
	var current: Dictionary=built.persistence.snapshot()
	recovered=FormalPersistence.new().restore_candidate(current)
	if not check(recovered.success and recovered.persistence.snapshot()==current,"Resumed and actual settlement candidate restores exactly"):return
	var bad: Dictionary=current.duplicate(true);bad["economy_native"]["local_quotations"]["sales_controls"][Opening.SITE+"|bread"]["paused"]=not bool(bad["economy_native"]["local_quotations"]["sales_controls"][Opening.SITE+"|bread"]["paused"])
	var rejected: WorldBuildResult=FormalPersistence.new().restore_candidate(bad)
	if not check(not rejected.success and current==built.persistence.snapshot(),"Tampered candidate rejected without replacing live world"):return
	var file=FileAccess.open(args[1],FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"pause_action":paused,"resume_action":result,"purchase":buy,"new_orders_after_resume":e.next_order-sales_before,"accepted_then_paused_order":old_order,"accepted_then_paused_actual_paid":actual_paid,"final_minute":view["minute"],"cash":view["firm"]["cash"],"inventory":view["firm"]["inventory"],"trade_review":view["trade_review"],"limitations":["DOMAIN_AUTOMATION_NOT_GUI","EXPIRY_REJECTION_USES_LABELLED_IN_MEMORY_FIXTURE","EXISTING_SUPPLY_REGRESSION_SEPARATE"]},"\t"));file.close()
	print("QA_SALES_CONTROL_PASS checks=",checks.size()," cash=",view["firm"]["cash"])
	quit()

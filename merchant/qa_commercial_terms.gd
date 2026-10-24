extends SceneTree
## Targeted quotation continuity and N3 publication restoration, using original actions.
const Commercial=preload("res://merchant/commercial_adaptation_opening.gd")
const Multi=preload("res://merchant/multisource_opening.gd")
const Opening=preload("res://merchant/merchant_opening.gd")
var completed: bool=false
var started: int=Time.get_ticks_msec()
func _initialize() -> void:call_deferred("run")
func _process(_delta: float) -> bool:
	if not completed and Time.get_ticks_msec()-started>180000:push_error("Commercial terms check incomplete");quit(1)
	return false
func build(cfg: Dictionary) -> WorldBuildResult:
	var b: WorldBuildResult=WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,false,{"format":"HOST_REGION_SELECTION","person_ids":[],"select_people_at_sites":true,"configuration":cfg})
	assert(b.success,b.error);return b
func until(b: WorldBuildResult,minute: int) -> void:
	while b.world.game_clock.total_minutes()<minute:assert(b.simulation_step.advance_minutes(mini(60,minute-b.world.game_clock.total_minutes())).get("success",true))
func exact_restore(b: WorldBuildResult) -> void:
	var snapshot: Dictionary=b.persistence.snapshot()
	var recovered: WorldBuildResult=FormalPersistence.new().restore_candidate(snapshot)
	assert(recovered.success,recovered.error)
	for key: String in ["economy_native","ledger","total_minutes"]:assert(snapshot[key]==recovered.persistence.snapshot()[key],key)
func quote_lifecycle(renew: bool) -> Dictionary:
	var cfg: Dictionary=Commercial.configuration("commercial_quotes" if renew else "commercial_reference")
	cfg.case_id="QA_SAME_TERMS_LIFECYCLE"
	cfg.local_quotation_experiment.npc_enabled=false # Explicit fixed-terms fixture only.
	var b: WorldBuildResult=build(cfg);var e: EconomyR1Slice=b.world.economy_r1
	var gaps: Array=[];var seen: Array=[]
	for d: int in range(1,36):
		until(b,d*1440)
		var why: String=e._local_quotes.reason("site:regional_food:paris",Multi.LYON,"grain")
		if d>=2 and not why.is_empty():gaps.append({"day":d,"reason":why})
		var q: Dictionary=e._local_quotes.current(Multi.LYON,"grain")
		if q.id not in seen:seen.append(q.id)
	assert((gaps.is_empty() if renew else not gaps.is_empty()),str(gaps))
	exact_restore(b)
	var result: Dictionary={"same_terms":true,"renew":renew,"days":35,"gaps":gaps,"versions_seen":seen,"restored_exact":true}
	if renew:
		until(b,35*1440+1)
		var old: Dictionary=e._local_quotes.current(Multi.LYON,"grain").duplicate(true)
		var changed: Dictionary=e.submit_internal("firm:regional_upstream",e._auto_command("firm:regional_upstream","post_goods_quote",{"site":Multi.LYON,"good":"grain","price":int(old.price)+1},"qa_actual_price_change"))
		assert(changed.get("accepted",false),str(changed))
		until(b,36*1440)
		assert(e._local_quotes.reason("site:regional_food:paris",Multi.LYON,"grain")=="GOODS_QUOTE_SUPERSEDED")
		assert(e._local_quotes.known("site:regional_food:paris",Multi.LYON,"grain").price==old.price)
		exact_restore(b)
		until(b,37*1440)
		assert(e._local_quotes.reason("site:regional_food:paris",Multi.LYON,"grain").is_empty())
		assert(e._local_quotes.known("site:regional_food:paris",Multi.LYON,"grain").price==int(old.price)+1)
		result["real_price_change_retains_two_day_notice"]=true
		result["changed_price"]=changed
	return result
func n3_publication() -> Dictionary:
	var cfg: Dictionary=Commercial.configuration("commercial_reference")
	cfg.case_id="QA_MOVING_N3_ANNOUNCEMENT_PRICE"
	var site: String="site:regional_textile:lyon";var firm: String="firm:regional_textile"
	Multi.site(cfg,site).prices.clothes=60 # Labelled N3 price fixture; no cash, stock or demand grant.
	cfg.price_policies.append({"firm":firm,"site_id":site,"good":"clothes","mode":"N3","tick":1,"window_days":3,"minimum":25,"maximum":120})
	var b: WorldBuildResult=build(cfg);var e: EconomyR1Slice=b.world.economy_r1
	var ad: Dictionary={}
	for date: int in range(1,21):
		until(b,date*1440)
		for row: Dictionary in e._commercial.publications.values():
			if row.site_id==site and row.item=="clothes":ad=row.duplicate(true);break
		if not ad.is_empty():break
		if e._commercial._staff(site).is_empty():continue
		var publication: Dictionary=e.submit_internal(firm,e._auto_command(firm,"publish_notice",{"firm":firm,"site_id":site,"kind":"GOODS","item":"clothes","channel_id":"channel:adaptive:local:"+site,"valid_days":4},"qa_original_n3_publication"))
		assert(publication.get("accepted",false),str(publication))
		ad=e._commercial.publications[publication.announcement_id].duplicate(true);break
	assert(not ad.is_empty(),"No actual staffed N3 publication in twenty original days")
	assert(ad.quote.price>=50)
	until(b,b.world.game_clock.total_minutes()+1440)
	# Controlled instruction to an existing NPC after it actually receives the
	# announcement. Its original cash funds the original buy; this is no claim
	# that its autonomous resale policy would choose an unprofitable purchase.
	var q: Dictionary=e._offer("firm:regional_food",firm,"clothes","edge:regional_local:lyon",site,"site:regional_food:lyon")
	var purchased: Dictionary=e.submit_internal("firm:regional_food",e._auto_command("firm:regional_food","buy",{"seller":firm,"seller_site":site,"buyer_site":"site:regional_food:lyon","good":"clothes","quantity":1,"quote_id":q.quote_id,"path_id":q.route_id,"denomination":q.denomination,"max_price":q.price},"qa_controlled_n3_purchase"))
	assert(purchased.get("accepted",false),str(purchased)+" "+str(q))
	until(b,b.world.game_clock.total_minutes()+6*1440)
	assert(e._price(site,"clothes")!=ad.quote.price,"Fixture did not produce an actual N3 price change")
	exact_restore(b)
	var original: Dictionary=b.persistence.snapshot();var forged: Dictionary=original.duplicate(true)
	var forged_price: int=int(ad.quote.price)+1
	forged.economy_native.commercial_information.publications[ad.id].quote.price=forged_price # Still inside 25..120, tick1.
	var rejected: WorldBuildResult=FormalPersistence.new().restore_candidate(forged)
	assert(not rejected.success and "original adopted price observation" in rejected.error,rejected.error)
	assert(b.persistence.snapshot()==original)
	return {"scope":"CONTROLLED_N3_INITIAL60_AND_EXPLICIT_NPC_BUY_EXISTING_GOODS_CASH_ACTORS_NOT_AUTONOMOUS_PREFERENCE","purchase":purchased,"published_day":int(ad.published_minute)/1440,"actual_published_price":ad.quote.price,"final_day":e.day,"final_price":e._price(site,"clothes"),"recorded_source":e._commands[ad.action_id].result.observed_goods_quote,"same_range_tick_forgery":forged_price,"rejection":rejected.error,"restored_past_price_after_actual_change":true,"rejected_without_replacing_live_world":true}
func protected_contract() -> Dictionary:
	var cfg: Dictionary=Commercial.configuration("commercial_inventory")
	cfg.case_id="QA_OPTIONAL_BUFFER_WITH_ACCEPTED_NPC_SUPPLY"
	cfg["supply_contracts"]={"id":"supply:qa_existing_clothes","buyer":Opening.FIRM,"buyer_site":Opening.LYON_SITE,"supplier":"firm:regional_food","supplier_site":"site:regional_food:lyon","good":"clothes","quantity":2,"days":30,"premium":4,"competitor":"firm:regional_textile","competitor_site":"site:regional_textile:lyon","competitor_target":2,"competitor_batch":1,"basis":"EXPLICIT_DEVELOPMENT_CITY_SUPPLY"}
	var b: WorldBuildResult=build(cfg);var e: EconomyR1Slice=b.world.economy_r1
	until(b,1)
	var offered: Dictionary=e._supply.offer()
	assert(offered.ready,str(offered))
	var accept: Dictionary=e.submit_internal("firm:regional_food",e._auto_command("firm:regional_food","accept_supply_contract",{"contract_id":offered.id,"price":offered.price},"qa_actual_npc_supply"))
	assert(accept.get("accepted",false),str(accept))
	until(b,7*1440)
	var purchases: Array=[]
	for order: Dictionary in e._orders.values():
		if order.buyer_site=="site:regional_food:lyon" and order.good=="clothes":purchases.append(order.duplicate(true))
	assert(not purchases.is_empty())
	var quantity: int=0
	for order: Dictionary in purchases:quantity+=int(order.quantity)
	assert(quantity>=2,"Optional trial must not displace a funded accepted contract")
	var inventory: Dictionary=e.OperatingInventory.observe(e,"site:regional_food:lyon","clothes")
	assert(inventory.optional_buffer_target==1)
	var batch: Dictionary=e.submit_internal("firm:regional_food",e._auto_command("firm:regional_food","submit_supply_batch",{"contract_id":offered.id,"quantity":2},"qa_real_clothes_supply_batch"))
	assert(batch.get("accepted",false),str(batch))
	until(b,10*1440)
	var delivered: Dictionary=e._orders[batch.order_id]
	assert(delivered.delivered==2 and delivered.price==offered.price)
	var paid: int=0
	for tx: Dictionary in b.world.ledger_state.transactions():
		if tx.get("reference_id")==batch.order_id and tx.get("kind")=="goods":paid+=int(tx.amount)
	assert(paid==2*int(offered.price))
	exact_restore(b)
	return {"scope":"CONTROLLED_EXISTING_NPC_ACCEPTS_FUNDED_CONTRACT_NO_CASH_OR_STOCK_GRANT","optional_target":1,"accepted_contract":accept,"real_procurements":purchases,"delivered_order":delivered.duplicate(true),"actual_goods_paid":paid,"restored_exact":true}
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var n3_only: bool=args.size()>1 and args[1]=="n3"
	var result: Dictionary={"scope":"TARGETED_DOMAIN_AUTOMATION_NOT_GUI","n3":n3_publication()} if n3_only else {"scope":"TARGETED_DOMAIN_AUTOMATION_NOT_GUI","unchanged_old_policy":quote_lifecycle(false),"same_terms_policy":quote_lifecycle(true),"n3":n3_publication(),"protected_contract":protected_contract()}
	for key: String in (["n3"] if n3_only else ["unchanged_old_policy","same_terms_policy","n3","protected_contract"]):
		if result[key].is_empty():completed=true;push_error("Incomplete scoped check: "+key);quit(1);return
	var file: FileAccess=FileAccess.open(args[0],FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close();completed=true
	print("COMMERCIAL_TERMS_FINISHED ",JSON.stringify(result));quit()

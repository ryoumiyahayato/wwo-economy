extends SceneTree
## Isolated QA: no forced NPC actions, no stock/cash patches, no production save writes.
## Run with --script res://merchant/qa09_feedback.gd -- [report.json] [legacy_slot4.json].
const Opening=preload("res://merchant/merchant_opening.gd")
const Save=preload("res://merchant/merchant_save.gd")
const BUYER_SITE="site:regional_food:paris"
const LEGACY="/workspace/shared/economy_08_opportunities/verified_manual/day6_slot4.json"
var failures: int=0
var report: Dictionary={"assumptions":"Unmodified finite opportunities_configuration opening; identical exact snapshot forks. B never submits player business commands. A buys 8 grain and accepts only the smallest visible grain procurement during 8-day comparison. Subsequent 30 days use bounded condition-driven player orders. NPCs only advance through simulation_step.","checks":[],"actions":[],"comparison":[],"continuation":[],"causal_links":[],"untriggered":[]}
var accepted_ids: Array[String]=[]
var player_purchases: int=0
var selected_contract: String=""
var unseen_tested: bool=false

func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> bool:
	report["checks"].append({"ok":ok,"label":label})
	if not ok:failures+=1;push_error("QA09_FAIL "+label)
	return ok
func actor(b: WorldBuildResult) -> String:return b.world.player_state.player_id()
func emit(label: String,value: Variant) -> void:print("QA09_",label," ",JSON.stringify(value))
func exact_restore(b: WorldBuildResult,label: String) -> void:
	var snap: Dictionary=b.persistence.snapshot()
	var restored: WorldBuildResult=FormalPersistence.new().restore_candidate(snap)
	if check(restored.success,"restore "+label+": "+restored.error):
		var after: Dictionary=restored.persistence.snapshot()
		check(after["economy_native"]==snap["economy_native"],"exact economy "+label)
		check(after["ledger"]==snap["ledger"],"exact ledger "+label)
		check(after["total_minutes"]==snap["total_minutes"],"exact clock "+label)
		check(restored.world.economy_r1._supply.competition_observation()==b.world.economy_r1._supply.competition_observation(),"derived observation rebuild "+label)
	check(b.persistence.snapshot()==snap,"candidate restore leaves live world "+label)
	check(b.world.economy_r1._orders.size()==snap["economy_native"]["orders"].size(),"restore does not generate NPC orders "+label)
	emit("RESTORE",label)
func query_check(b: WorldBuildResult,label: String) -> void:
	var before: Dictionary=b.persistence.snapshot()
	var e: EconomyR1Slice=b.world.economy_r1
	var feedback: Dictionary=e.managed_market_feedback(actor(b),Opening.FIRM)
	check(not feedback.is_empty(),"authorized feedback "+label)
	check(e._delivery_minute({"delivered_day":3})==4320,"legacy receipt day-only minute helper "+label)
	known_notice_history_check(e,feedback,label)
	check(e.managed_market_feedback("unknown",Opening.FIRM).is_empty(),"unknown actor feedback denied "+label)
	check(e.managed_market_feedback(actor(b),Opening.COMPETITOR).is_empty(),"foreign firm feedback denied "+label)
	e._supply.competition_observation()
	check(before==b.persistence.snapshot(),"feedback and history observation pure "+label)
	feedback.clear()
	check(before==b.persistence.snapshot(),"feedback return is detached "+label)
func known_notice_history_check(e: EconomyR1Slice,feedback: Dictionary,label: String) -> void:
	var events: Array=feedback.get("events",[])
	var cutoff: int=2147483647
	for event: Dictionary in events:cutoff=mini(cutoff,int(event["minute"]))
	var checked: int=0;var tie_or_older: int=0
	# Source is received immutable notices, deliberately not live views/need/cash.
	for notice: Dictionary in e._supply.notices.values():
		var terms: Dictionary=notice["terms"]
		if terms["supplier"]!=Opening.FIRM or not e._supply.known_notice(notice["id"]):continue
		var minute: int=e._received_market_minute(str(terms["supplier_site"]),"supply_opportunity",str(notice["id"]))
		var matching: Array=events.filter(func(event: Dictionary)->bool:return str(notice["id"]) in event.get("refs",[]))
		# A tied twelfth event may be trimmed legitimately; do not assume sort stability.
		if events.size()<12 or minute>cutoff:
			check(not matching.is_empty(),"received notice remains visible independent of current acceptability "+label+" "+str(notice["id"]))
			checked+=1
		else:tie_or_older+=1
		for event: Dictionary in matching:
			check(int(event["minute"])==minute,"notice event uses receipt date "+label)
			check(str(event["text"]).contains("%d单位"%int(terms["quantity"])) and str(event["text"]).contains("单价%d"%int(notice["price"])),"notice event preserves published quantity and price "+label)
	report["checks"].append({"ok":true,"label":"received notice history coverage "+label,"required_in_top12":checked,"tie_or_older_not_required":tie_or_older})
func command(b: WorldBuildResult,kind: String,payload: Dictionary) -> Dictionary:
	var e: EconomyR1Slice=b.world.economy_r1
	var envelope: Dictionary={"action_id":e.next_person_action_id(),"minute":b.world.game_clock.total_minutes(),"kind":kind,"payload":payload}
	var result: Dictionary=LivelihoodAction.execute(b.world,actor(b),envelope)
	var after: Dictionary=b.persistence.snapshot()
	check(LivelihoodAction.execute(b.world,actor(b),envelope)==result,"same action result "+kind)
	check(b.persistence.snapshot()==after,"replay no duplicate order or payment "+kind)
	var entry: Dictionary={"day":e.day,"command":envelope,"result":result}
	report["actions"].append(entry);emit("ACTION",entry)
	return result
func buy_grain(b: WorldBuildResult,quantity: int) -> bool:
	var e: EconomyR1Slice=b.world.economy_r1
	var book: Dictionary=e.business_view(actor(b),Opening.FIRM,Opening.SITE,quantity,0,16)
	for q: Dictionary in book.get("offers",[]):
		if q.get("good")=="grain" and q.get("seller")=="firm:regional_upstream" and q.get("can_order",false):
			var result: Dictionary=command(b,"buy",q["request"])
			if result.get("accepted",false):player_purchases+=1;exact_restore(b,"purchase_"+str(player_purchases));return true
	return false
func smallest_grain(b: WorldBuildResult) -> Dictionary:
	var choices: Array[Dictionary]=[]
	for c: Dictionary in b.world.economy_r1.supply_business_view(actor(b)):
		if str(c["id"]).begins_with("procurement:grain") and c.get("status")=="RECRUITING" and c.get("ready",false):choices.append(c)
	choices.sort_custom(func(a: Dictionary,z: Dictionary)->bool:return int(a["quantity"])<int(z["quantity"]))
	return {} if choices.is_empty() else choices[0]
func accept_one(b: WorldBuildResult) -> void:
	var c: Dictionary=smallest_grain(b)
	if c.is_empty():return
	var before: Array=b.world.ledger_state.own_accounts(Opening.FIRM)
	var r: Dictionary=command(b,"accept_supply_contract",{"contract_id":c["id"],"price":c["price"]})
	if r.get("accepted",false):
		accepted_ids.append(c["id"])
		if selected_contract.is_empty():selected_contract=c["id"]
		check(before==b.world.ledger_state.own_accounts(Opening.FIRM),"acceptance creates no merchant income")
		exact_restore(b,"accept_"+str(c["id"]))
func deliver(b: WorldBuildResult) -> void:
	for c: Dictionary in b.world.economy_r1.supply_business_view(actor(b)):
		if c["id"] not in accepted_ids or c.get("status") not in ["ACCEPTED","PARTIAL"]:continue
		var quantity: int=mini(int(c.get("free_stock",0)),int(c.get("unallocated",0)))
		if quantity>0:
			command(b,"submit_supply_batch",{"contract_id":c["id"],"quantity":quantity})
			exact_restore(b,"batch_"+str(c["id"]))
func unseen_notice_check(b: WorldBuildResult) -> void:
	if unseen_tested:return
	var e: EconomyR1Slice=b.world.economy_r1
	for id: String in e._supply.notices:
		if e._supply.known_notice(id):continue
		var n: Dictionary=e._supply.notices[id]
		check(not e.supply_business_view(actor(b)).any(func(c: Dictionary)->bool:return c["id"]==id),"undelivered procurement hidden")
		var r: Dictionary=command(b,"accept_supply_contract",{"contract_id":id,"price":n["price"]})
		check(not r.get("accepted",false),"undelivered procurement acceptance rejected")
		unseen_tested=true
		return
func observe(b: WorldBuildResult) -> Dictionary:
	var e: EconomyR1Slice=b.world.economy_r1
	var player_orders: Array[Dictionary]=[];var buyer_orders: Array[Dictionary]=[];var npc_orders: Array[Dictionary]=[]
	for o: Dictionary in e._orders.values():
		if o["buyer"]==Opening.FIRM or o["seller"]==Opening.FIRM:player_orders.append(o.duplicate(true))
		if o["buyer_site"]==BUYER_SITE and o["good"]=="grain":buyer_orders.append(o.duplicate(true))
		if o["buyer"]==Opening.COMPETITOR or o["seller"]==Opening.COMPETITOR:npc_orders.append(o.duplicate(true))
	var receipts: Array[Dictionary]=[]
	for r: Dictionary in e._delivery_receipts.values():
		var o: Dictionary=e._orders[r["order_id"]]
		if o["buyer"] in [Opening.FIRM,Opening.COMPETITOR,"firm:regional_food"] or o["seller"] in [Opening.FIRM,Opening.COMPETITOR]:receipts.append(r.duplicate(true))
	var sources: Array[Dictionary]=[]
	for s: Dictionary in e._lots.sources.values():
		if str(s["id"]).begins_with("production:") and BUYER_SITE in str(s["id"]):sources.append(s.duplicate(true))
	var decisions: Array[Dictionary]=[]
	for entry: Dictionary in e._commands.values():
		if entry.get("envelope",{}).get("actor") in [Opening.COMPETITOR,"firm:regional_food"] and entry.get("result",{}).has("decision"):decisions.append(entry.duplicate(true))
	var observation: Dictionary=e._supply.competition_observation()
	var sold: int=0;var received: int=0
	for receipt: Dictionary in e._delivery_receipts.values():
		if int(receipt["delivered_day"])<=e.day-4:continue
		var order: Dictionary=e._orders[receipt["order_id"]]
		if order["kind"]!="SALE" or order["good"]!="grain":continue
		if order["seller"]==Opening.COMPETITOR and order["seller_site"]==Opening.COMPETITOR_SITE:sold+=int(receipt["quantity"])
		if order["buyer"]==Opening.COMPETITOR and order["buyer_site"]==Opening.COMPETITOR_SITE:received+=int(receipt["quantity"])
	check(sold==int(observation.get("recent_sold",-1)) and received==int(observation.get("recent_received",-1)),"NPC sales observation equals original receipts day "+str(e.day))
	check(observation.get("window_days")==4 and observation.get("cooldown_days")==2,"bounded NPC history window day "+str(e.day))
	check(int(observation.get("target",0))>=3 and int(observation.get("target",99))<=12,"bounded NPC target day "+str(e.day))
	return {"day":e.day,"minute":b.world.game_clock.total_minutes(),"buyer_stock":e._stocks[BUYER_SITE].duplicate(true),"buyer_input_need":e._input_need(BUYER_SITE,"grain"),"buyer_plan":e._plans.get(BUYER_SITE,{}).duplicate(true),"merchant_stock":e._stocks[Opening.SITE].duplicate(true),"merchant_cash":b.world.ledger_state.own_accounts(Opening.FIRM),"contracts":e.supply_business_view(actor(b)),"player_visible_offers":e.business_view(actor(b),Opening.FIRM,Opening.SITE,1,0,32).get("offers",[]),"npc_known_offers":e._offers(Opening.COMPETITOR,Opening.COMPETITOR_SITE,"grain"),"npc_observation":observation,"npc_orders":npc_orders,"npc_decisions":decisions,"buyer_orders":buyer_orders,"player_orders":player_orders,"receipts":receipts,"shipments":e._shipments.duplicate(true),"production_sources":sources,"feedback":e.managed_market_feedback(actor(b),Opening.FIRM)}
func causal_links(b: WorldBuildResult) -> Array[Dictionary]:
	var e: EconomyR1Slice=b.world.economy_r1
	var links: Array[Dictionary]=[]
	for receipt: Dictionary in e._delivery_receipts.values():
		var order: Dictionary=e._orders[receipt["order_id"]]
		if order["seller"]!=Opening.FIRM or order["buyer_site"]!=BUYER_SITE or order["good"]!="grain":continue
		var portions: Array[Dictionary]=[];var used: Array[Dictionary]=[];var ids: Array[String]=[]
		for portion: Dictionary in e._lots.portions.values():
			if portion.get("acquisition_id")==receipt["id"]:
				portions.append(portion.duplicate(true));ids.append(portion["id"])
		for source: Dictionary in e._lots.sources.values():
			if not str(source["id"]).begins_with("production:"):continue
			for input: Dictionary in source["inputs"]:
				if input.get("portion_id") in ids:used.append({"production_source":source.duplicate(true),"matched_input":input.duplicate(true)})
		var transactions: Array[Dictionary]=[]
		for tx: Dictionary in b.world.ledger_state.own_transactions(Opening.FIRM,0,b.world.game_clock.total_minutes()+1):
			if str(tx.get("transaction_id",tx.get("id",""))).ends_with(str(receipt["id"])):transactions.append(tx.duplicate(true))
		links.append({"order":order.duplicate(true),"delivery_receipt":receipt.duplicate(true),"acquired_portions":portions,"exact_production_inputs":used,"ledger_transactions":transactions,"production_causality":"Exact input portion references only; same-day coincidence is not evidence."})
	return links
func invalid_and_legacy(b: WorldBuildResult,legacy: String) -> void:
	var before: Dictionary=b.persistence.snapshot()
	var bad: Dictionary=before.duplicate(true);bad["economy_native"]["receipts"]="invalid"
	var rejected: WorldBuildResult=FormalPersistence.new().restore_candidate(bad)
	check(not rejected.success,"malformed candidate rejected")
	check(before==b.persistence.snapshot(),"rejected candidate leaves live world exact")
	var raw: Dictionary=Save._read(legacy,4)
	if not check(raw.get("error","").is_empty(),"real 08 slot4 read: "+str(raw.get("error",""))):return
	var old: WorldBuildResult=FormalPersistence.new().restore_candidate(raw["core"])
	if check(old.success,"real 08 slot4 restore: "+old.error):
		var restored: Dictionary=old.persistence.snapshot()
		check(restored["economy_native"]==raw["core"]["economy_native"],"08 economy remains exact without new observation state")
		check(restored["ledger"]==raw["core"]["ledger"],"08 ledger remains exact")
		report["legacy"]={"path":legacy,"minute":restored["total_minutes"],"cash":old.world.ledger_state.own_accounts(Opening.FIRM),"stock":old.world.economy_r1._stocks[Opening.SITE]}
		query_check(old,"legacy")
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var output: String=args[0] if args.size()>0 else "/tmp/qa09_feedback_report.json"
	var legacy: String=args[1] if args.size()>1 else LEGACY
	var initial: WorldBuildResult=WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,false,{"format":"HOST_REGION_SELECTION","person_ids":[],"select_people_at_sites":true,"configuration":Opening.opportunities_configuration()})
	if not check(initial.success,"initial build "+initial.error):quit(1);return
	check(Opening.grant_regional_authority(initial.world),"regional player quote authority")
	check(initial.simulation_step.advance_minutes(1).get("success",true),"initial minute")
	var seed: Dictionary=initial.persistence.snapshot()
	var a: WorldBuildResult=FormalPersistence.new().restore_candidate(seed)
	var b: WorldBuildResult=FormalPersistence.new().restore_candidate(seed)
	if not check(a.success and b.success,"both exact forks restore"):quit(1);return
	check(a.persistence.snapshot()==b.persistence.snapshot(),"A/B identical legal start")
	initial=null
	query_check(a,"opening")
	check(buy_grain(a,8),"A legal initial eight grain purchase")
	for d: int in range(1,9):
		for world: WorldBuildResult in [a,b]:check(world.simulation_step.advance_minutes(1440).get("success",true),"A/B day advance "+str(d))
		unseen_notice_check(a)
		if selected_contract.is_empty():accept_one(a)
		deliver(a)
		var aa: Dictionary=observe(a);var bb: Dictionary=observe(b)
		report["comparison"].append({"day":d,"A":aa,"B":bb,"different_input_need":aa["buyer_input_need"]!=bb["buyer_input_need"],"different_npc_observation":aa["npc_observation"]!=bb["npc_observation"]})
		emit("AB",{"day":d,"A_need":aa["buyer_input_need"],"B_need":bb["buyer_input_need"],"A_npc":aa["npc_observation"],"B_npc":bb["npc_observation"],"A_cash":aa["merchant_cash"],"B_cash":bb["merchant_cash"]})
		if d in [1,2,3,6,8]:exact_restore(a,"A_day_"+str(d));exact_restore(b,"B_day_"+str(d))
	check(not selected_contract.is_empty(),"A accepts visible smallest grain procurement")
	report["ab_causal_links"]=causal_links(a)
	check(not report["ab_causal_links"].is_empty(),"A actual grain delivery before end of A/B")
	b=null
	for elapsed: int in range(1,31):
		var started: int=Time.get_ticks_msec()
		var advance_result: Dictionary=a.simulation_step.advance_minutes(1440)
		var advance_only_ms: int=Time.get_ticks_msec()-started
		check(advance_result.get("success",true),"continuation day "+str(elapsed))
		var e: EconomyR1Slice=a.world.economy_r1
		var free: int=maxi(0,int(e._stocks[Opening.SITE]["grain"])-e._committed(Opening.SITE,"grain"))
		var incoming: int=maxi(0,e._exposure(Opening.SITE,"grain")-int(e._stocks[Opening.SITE]["grain"]))
		# At most four extra player purchases, contingent on stock, responsibility and real cash.
		if free<3 and incoming==0 and player_purchases<5 and a.world.ledger_state.available_balance(e._account(Opening.FIRM))>=30:buy_grain(a,4)
		if accepted_ids.size()<4 and not smallest_grain(a).is_empty():accept_one(a)
		deliver(a)
		var advance_and_player_ms: int=Time.get_ticks_msec()-started
		var sample: Dictionary=observe(a)
		sample["advance_only_ms"]=advance_only_ms
		sample["advance_and_player_ms"]=advance_and_player_ms
		report["continuation"].append(sample)
		emit("LONG_DAY",{"elapsed":elapsed,"day":e.day,"stock":sample["merchant_stock"],"cash":sample["merchant_cash"],"npc":sample["npc_observation"],"advance_only_ms":sample["advance_only_ms"],"advance_and_player_ms":sample["advance_and_player_ms"]})
		if elapsed%5==0:exact_restore(a,"continuation_"+str(elapsed));query_check(a,"continuation_"+str(elapsed))
	report["causal_links"]=causal_links(a)
	var used: int=0
	for link: Dictionary in report["causal_links"]:used+=link["exact_production_inputs"].size()
	if used==0:report["untriggered"].append("No production input portion directly traced to player delivery; inspect real buyer plans and other material/labor/capacity constraints. Do not claim all buyer output was caused by player.")
	if player_purchases<2:report["untriggered"].append("Repeated player purchases did not meet stock/incoming/cash conditions.")
	if not unseen_tested:report["untriggered"].append("No still-undelivered notice available at daily boundaries; original QA08 information tests remain required.")
	invalid_and_legacy(a,legacy)
	report["summary"]={"failures":failures,"player_purchase_count":player_purchases,"accepted_contract_ids":accepted_ids,"comparison_days":8,"continuation_days":30,"final_day":a.world.economy_r1.day,"direct_production_input_links":used}
	var file: FileAccess=FileAccess.open(output,FileAccess.WRITE)
	if check(file!=null,"open QA report output"):
		file.store_string(JSON.stringify(report,"\t"));file.close()
	emit("RESULT",report["summary"]);print("QA09_REPORT ",output)
	a=null;quit(0 if failures==0 else 1)

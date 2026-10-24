extends "res://merchant/qa_regional_market.gd"
## Scoped long-run diagnosis. Uses original simulation and exact persistence.
const Adaptive=preload("res://merchant/adaptive_contacts_opening.gd")
const Consumer=preload("res://merchant/consumer_access_opening.gd")
const Commercial=preload("res://merchant/commercial_adaptation_opening.gd")
var known_at_order: Dictionary={}
var publicity_actions: Array=[]
var publicity_chain: Array=[]

func publication_action(b: WorldBuildResult,condition: String) -> bool:
	if condition!="regional_publicity_work":return true
	var e: EconomyR1Slice=b.world.economy_r1
	var minute: int=b.world.game_clock.total_minutes()
	var actions: Array=[]
	if minute==4*1440:actions=[{"kind":"apply","payload":{"job_id":Consumer.PUBLICITY_JOB}},{"kind":"work","payload":{"hours":1}}]
	if minute==5*1440:actions=[{"kind":"publish_notice","payload":{"firm":Opening.FIRM,"site_id":Opening.SITE,"kind":"GOODS","item":"grain","channel_id":Consumer.PUBLICITY_CHANNEL,"valid_days":3}}]
	for action: Dictionary in actions:
		var result: Dictionary=LivelihoodAction.execute_current(b.world,action.kind,action.payload)
		publicity_actions.append({"minute":minute,"kind":action.kind,"payload":action.payload,"result":result})
		if not result.get("accepted",false):push_error(str(result));return false
	return true

func publication_probe(b: WorldBuildResult) -> Dictionary:
	var e: EconomyR1Slice=b.world.economy_r1
	var buyer: String="site:regional_food:paris"
	var candidate: String=Opening.FIRM+"|grain|"+Opening.SITE
	var known: bool=candidate in e._firm_knowledge[buyer]
	var notices: Array=[];var pending: Array=[];var received: Array=[]
	for a: Dictionary in e._commercial.publications.values():
		if a.firm!=Opening.FIRM or a.item!="grain":continue
		notices.append(a.duplicate(true))
		for m: Dictionary in e._messages:
			if m.get("announcement_id")==a.id:pending.append(m.duplicate(true))
		for m: Dictionary in e._receipts.values():
			if m.get("announcement_id")==a.id:received.append(m.duplicate(true))
	var need: Dictionary=e._input_need(buyer,"grain")
	var ranked: Array=e._input_offers(buyer,"grain",int(need.need_by_day),maxi(1,int(need.quantity)),need)
	var work: Array=[]
	for row: Dictionary in e._work_records.values():
		if row.job==Consumer.PUBLICITY_JOB:work.append(row.duplicate(true))
	return {"minute":b.world.game_clock.total_minutes(),"notices":notices,"pending_messages":pending,"received_messages":received,"buyer_received_grain_introduction":known,"buyer_need":need,"buyer_cash":e._procurement_cash_position("firm:regional_food",FormalLedgerState.DENOMINATION),"buyer_ranked_offers":ranked,"actual_buyer_grain_decisions":e._procurement_observations.filter(func(row: Dictionary):return row.get("intent",{}).get("site")==buyer and row.get("intent",{}).get("good")=="grain").duplicate(true),"own_actual_work":work,"scope":"DEVELOPER_ONLY_ORIGINAL_COMMANDS_AND_RECEIPTS"}

func cash_totals(b: WorldBuildResult) -> Dictionary:
	var result: Dictionary=super.cash_totals(b)
	for id: String in b.world.ledger_state.account_ids():
		var account: Dictionary=b.world.ledger_state.account(id)
		if account.role=="opening_source":result["unspent_opening_source:"+str(account.denomination)]=account.balance
	return result

func _process(_delta: float) -> bool:
	if not completed and Time.get_ticks_msec()-started>600000:push_error("Adaptive contact diagnosis incomplete");quit(1)
	return false

func summary_day(b: WorldBuildResult) -> Dictionary:
	var e: EconomyR1Slice=b.world.economy_r1
	var sites: Dictionary={};var firms: Dictionary={};var actors: Dictionary={}
	for site: String in e._site_ids():
		sites[site]={"stock":e._stocks[site].duplicate(),"physical":e._physical_totals[site].duplicate(true),"state":e._site_state[site].duplicate(true),"operating_inventory":{},"plan":e._plans.get(site,{}).duplicate(true),"introductions":e._supplier_introduction_view(site)}
	for site: String in sites:
		for good: String in e._goods:
			var stock_policy: Dictionary=e.OperatingInventory.observe(e,site,good)
			if not stock_policy.is_empty():sites[site].operating_inventory[good]=stock_policy
	for firm: String in e._firm_ids():
		firms[firm]={"cash":b.world.ledger_state.balance(e._account(firm)),"available":b.world.ledger_state.available_balance(e._account(firm)),"reserved":b.world.ledger_state.reserved_balance(e._account(firm)),"wages":e._mature_wage_position(firm,FormalLedgerState.DENOMINATION)}
		if e._costs.enabled:firms[firm]["native_costs"]=e._costs.view(firm,14)
	for actor: String in e._actor_ids():
		actors[actor]={"cash":b.world.ledger_state.balance(e._account(actor)),"available":b.world.ledger_state.available_balance(e._account(actor)),"reserved":b.world.ledger_state.reserved_balance(e._account(actor)),"income":e._income_by_actor.get(actor,{}).duplicate(),"totals":e._totals[actor].duplicate(true),"need":e._needs.get(actor,{}).duplicate(true),"employment":e._contracts.get(actor,{}).duplicate(true),"inventory":e._inventory_view(actor)}
	return {"household_oil_procurement":e._procurement_observations.filter(func(row: Dictionary):return row.get("intent",{}).get("site")=="site:regional_household:marseille" and row.get("intent",{}).get("good")=="oil").duplicate(true),"food_procurement":e._procurement_observations.filter(func(row: Dictionary):return row.get("intent",{}).get("site")=="site:regional_food:paris" and row.get("intent",{}).get("good")=="grain").duplicate(true),"market_time_responses":e._procurement_observations.filter(func(row: Dictionary):return row.get("kind")=="MARKET_TIME_RESPONSE").duplicate(true),"day":e.day,"minute":b.world.game_clock.total_minutes(),"sites":sites,"firms":firms,"actors":actors,"consumer_access":preload("res://merchant/consumer_access_projection.gd").project(e),"clothes_procurement":e._procurement_observations.filter(func(row: Dictionary):return row.get("intent",{}).get("site")=="site:regional_food:lyon" and row.get("intent",{}).get("good")=="clothes").duplicate(true),"decision_counts":e._decision_counts.duplicate(),"main":e._transport.edges[Multi.EDGE].duplicate(true),"bypass":e._transport.edges.get(Reaction.BYPASS,{}).duplicate(true)}

func check_introductions(e: EconomyR1Slice) -> void:
	for site: String in e._site_ids():
		for fact: Dictionary in e._supplier_introduction_view(site):
			assert(fact.knowledge_source!="UNKNOWN_RETAINED_INTRODUCTION",str(fact))
			assert(e._receipts.has(fact.message_id),"Knowledge has no adopted receipt")
			var receipt: Dictionary=e._receipts[fact.message_id]
			assert(receipt.actor==site and receipt.kind=="supplier" and int(receipt.delivery_day)<=e.day)
	for order: Dictionary in e._orders.values():
		if known_at_order.has(order.id) or order.kind!="SALE" or not e._spec.sites.has(order.get("buyer_site","")):continue
		var candidate: String=str(order.seller)+"|"+str(order.good)+"|"+str(order.seller_site)
		var found: bool=false
		for receipt: Dictionary in e._receipts.values():
			if receipt.actor==order.buyer_site and receipt.kind=="supplier" and receipt.candidate==candidate and int(receipt.delivery_day)<=int(order.accepted_day):found=true;break
		assert(found,"Accepted business order lacked received supplier knowledge: "+str(order.id))
		known_at_order[order.id]=true

func contact_sample(b: WorldBuildResult) -> Dictionary:
	var e: EconomyR1Slice=b.world.economy_r1
	var rows: Dictionary={}
	for firm: String in e._firm_ids():
		var own: Dictionary=e.visible_internal(firm)
		var offers: Array[Dictionary]=e.managed_network_contacts(firm,firm)
		rows[firm]=Contacts.project(own,offers,b.world.game_clock.total_minutes())
	return rows

func observation_profile(b: WorldBuildResult,condition: String) -> Dictionary:
	var runtime: RefCounted=Runtime.new();runtime._network_experiment=true;runtime._multisource_condition=condition
	var samples: Array=[]
	for subject: String in ["","firm:regional_food"]:
		runtime._research_subject=subject
		var timings: Array=[];var orders: int=0
		for iteration: int in 4:
			var begin: int=Time.get_ticks_usec();var view: Dictionary=runtime._view(b)
			timings.append(Time.get_ticks_usec()-begin);orders=view.market_network.edges.size()
		samples.append({"subject":subject,"elapsed_us":timings,"orders":orders})
	var e: EconomyR1Slice=b.world.economy_r1
	return {"view_samples":samples,"request_window_bytes":JSON.stringify(e._request_window).to_utf8_buffer().size(),"request_keys":e._request_window.size(),"buy_diagnostic_ids":e._recent_buy_commands.values().reduce(func(sum: int,ids: Array):return sum+ids.size(),0),"total_original_commands":e._commands.size(),"original_orders":e._orders.size(),"basis":"SERIAL_NATIVE_SINGLE_DESKTOP_OBSERVATION_NOT_PERFORMANCE_GUARANTEE"}

func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	assert(args.size()>=4,"output condition days checkpoint_prefix")
	var condition: String=args[1];var days: int=int(args[2])
	if args.size()>4 and args[4]=="--observe-saved":
		var decoded: Dictionary=FormalWorldPersistenceDocument.decode(JSON.parse_string(FileAccess.get_file_as_string(args[3])))
		assert(decoded.success,str(decoded))
		var b: WorldBuildResult=FormalPersistence.new().restore_candidate(decoded.snapshot)
		assert(b.success,b.error)
		var snapshot: Dictionary=b.persistence.snapshot();var result: Dictionary=observation_profile(b,condition)
		assert(b.persistence.snapshot()==snapshot,"Observation changed saved economy")
		var file: FileAccess=FileAccess.open(args[0],FileAccess.WRITE);file.store_string(JSON.stringify(result));file.close()
		completed=true;print("ADAPTIVE_SAVED_OBSERVATION_FINISHED ",result);quit();return
	var legacy: bool=condition.begins_with("legacy_")
	assert(condition in Commercial.CONDITIONS+Consumer.CONDITIONS or condition in Adaptive.CONDITIONS or condition in ["legacy_normal","legacy_blocked"])
	print("ADAPTIVE_USER_DATA_DIR ",OS.get_user_data_dir())
	var initial: Dictionary={}
	var resume_index: int=args.find("--resume-from")
	if resume_index>=0:
		var source: Dictionary=FormalWorldPersistenceDocument.decode(JSON.parse_string(FileAccess.get_file_as_string(args[resume_index+1])))
		assert(source.success,str(source))
		initial=source.snapshot
	else:
		var base: WorldBuildResult=Consumer.build(condition) if condition in Consumer.CONDITIONS else Commercial.build(condition) if condition in Commercial.CONDITIONS else Multi.build("normal" if condition=="legacy_normal" else "blocked") if legacy else Adaptive.build()
		assert(base.success and base.world.economy_r1!=null,base.error+" "+str(base.world.native_economy_error))
		initial=base.persistence.snapshot()
	var b: WorldBuildResult=FormalPersistence.new().restore_candidate(initial)
	assert(b.success,b.error)
	for key: String in ["economy_native","ledger","total_minutes"]:assert(b.persistence.snapshot()[key]==initial[key],"Canonical first restore changed economic facts")
	initial=b.persistence.snapshot();b=null
	b=FormalPersistence.new().restore_candidate(initial)
	assert(b.success and b.persistence.snapshot()==initial,b.error)
	if condition=="legacy_blocked":assert(Multi.capacity(b.world,0).get("accepted",false))
	if not legacy:assert((Consumer.apply_condition(b.world,condition) if condition in Consumer.CONDITIONS else Commercial.apply_condition(b.world,condition) if condition in Commercial.CONDITIONS else Adaptive.apply_condition(b.world,condition)).get("accepted",false))
	var e: EconomyR1Slice=b.world.economy_r1
	e._dated_input_procurement_enabled="--dated-inputs" in args
	e._procurement_diagnostics_enabled=condition in Commercial.CONDITIONS+Consumer.CONDITIONS
	var first_day: int=e.day
	var last_day: int=first_day+days
	var cash: Dictionary=cash_totals(b)
	var daily: Array=[summary_day(b)];var samples: Dictionary={first_day:contact_sample(b)}
	if condition in Consumer.PUBLICITY_CHOICES:publicity_chain.append(publication_probe(b))
	var compute_ms: Array=[]
	for day_number: int in range(first_day+1,last_day+1):
		var begin: int=Time.get_ticks_msec()
		while b.world.game_clock.total_minutes()<day_number*1440:
			var minute: int=b.world.game_clock.total_minutes()
			var minutes: int=mini(60,day_number*1440-minute)
			if not legacy and condition not in Commercial.CONDITIONS+Consumer.CONDITIONS:minutes=mini(minutes,Adaptive.minutes_to_boundary(minute))
			assert(b.simulation_step.advance_minutes(minutes).get("success",true),"Formal advance failed")
			if not legacy:assert((Consumer.apply_condition(b.world,condition) if condition in Consumer.CONDITIONS else Commercial.apply_condition(b.world,condition) if condition in Commercial.CONDITIONS else Adaptive.apply_condition(b.world,condition)).get("accepted",false))
			if not publication_action(b,condition):completed=true;quit(1);return
		compute_ms.append(Time.get_ticks_msec()-begin)
		assert(cash_totals(b)==cash,"Currency changed")
		check_introductions(e)
		daily.append(summary_day(b))
		if condition in Consumer.PUBLICITY_CHOICES and day_number in [4,5,6,7,8,15,30,60]:publicity_chain.append(publication_probe(b))
		if day_number in [1,3,7,12,18,25,35,42,60,90,120] or day_number==last_day:samples[day_number]=contact_sample(b)
		if day_number in [3,7,12,18,25,35,42,60,90,120] or day_number==last_day:print("ADAPTIVE_DAY ",condition," day=",day_number," orders=",e._orders.size()," food_cash=",b.world.ledger_state.balance(e._account("firm:regional_food"))," food_wages=",e._mature_wage_position("firm:regional_food",FormalLedgerState.DENOMINATION)," publications=",e._commercial.publications.size())
	var source_quantities: Dictionary={}
	for portion: Dictionary in e._lots.portions.values():source_quantities[portion.source_id]=int(source_quantities.get(portion.source_id,0))+int(portion.remaining)+int(portion.consumed)+int(portion.lost)
	for id: String in e._lots.sources:assert(int(source_quantities.get(id,0))==int(e._lots.sources[id].quantity),"Source quantity changed")
	for order: Dictionary in e._orders.values():
		assert(int(order.quantity)==int(order.pending)+int(order.transit)+int(order.delivered)+int(order.cancelled))
		if order.kind=="SALE" and not e._local_quotes.rule(order.seller_site,order.good).is_empty():assert(e._local_quotes.valid_locked_price(order),"Locked quote changed")
	var snapshot: Dictionary=b.persistence.snapshot()
	var encode_begin: int=Time.get_ticks_usec()
	var document: Dictionary=FormalWorldPersistenceDocument.encode(snapshot)
	var encoded: String=JSON.stringify(document)
	var encode_us: int=Time.get_ticks_usec()-encode_begin
	var checkpoint: FileAccess=FileAccess.open(args[3]+"_"+condition+".json",FileAccess.WRITE);checkpoint.store_string(encoded);checkpoint.close()
	var decoded: Dictionary=FormalWorldPersistenceDocument.decode(JSON.parse_string(FileAccess.get_file_as_string(args[3]+"_"+condition+".json")))
	assert(decoded.success and decoded.snapshot==snapshot,"Exact persisted value changed")
	var restore_begin: int=Time.get_ticks_usec()
	var restored: WorldBuildResult=FormalPersistence.new().restore_candidate(decoded.snapshot)
	var restore_us: int=Time.get_ticks_usec()-restore_begin
	assert(restored.success,restored.error)
	assert(restored.world.economy_r1._recent_buy_commands==e._recent_buy_commands,"Recent command access changed on restore")
	for key: String in ["economy_native","ledger","total_minutes"]:assert(restored.persistence.snapshot()[key]==snapshot[key],"Restoration changed economy")
	assert(contact_sample(restored)==samples[last_day],"Restoration changed contacts or their provenance")
	var runtime: RefCounted=Runtime.new();runtime._network_experiment=true;runtime._multisource_condition=condition
	var query_us: Array=[]
	for subject: String in ([""] if legacy else ["","firm:regional_food"]):
		runtime._research_subject=subject
		var begin: int=Time.get_ticks_usec();var view: Dictionary=runtime._view(b)
		query_us.append({"subject":subject,"elapsed_us":Time.get_ticks_usec()-begin,"orders":view.market_network.edges.size()})
	assert(b.persistence.snapshot()==snapshot,"Observation mutated the world")
	var profile: Dictionary=observation_profile(b,condition)
	assert(b.persistence.snapshot()==snapshot,"Repeated observation mutated the world")
	var output: Dictionary={"scope":"EXPLICIT_DEVELOPMENT_LONG_RUN_NOT_GUI","condition":condition,"days":days,"opening_totals":Multi.totals(initial.economy_native.config),"ledger_and_unspent_source_totals":cash,"daily":daily,"contacts":samples,"orders":e._orders.duplicate(true),"shipments":e._shipments.duplicate(true),"delivery_receipts":e._delivery_receipts.duplicate(true),"messages_received":e._receipts.duplicate(true),"commands":e._commands.duplicate(true),"publications":e._commercial.publications.duplicate(true),"work_records":e._work_records.duplicate(true),"wages":e._wages.duplicate(true),"employment_ends":e._employment_ends.duplicate(true),"enterprise_changes":e._enterprise_changes.duplicate(true),"ledger":b.world.ledger_state.transactions(),"quotes":e._local_quotes.snapshot(),"day_compute_ms":compute_ms,"query_us":query_us,"cash_conserved":true,"no_later_opening_source_payment":true,"physical_sources_conserved":true,"order_responsibilities_conserved":true,"accepted_business_orders_had_received_supplier":true,"locked_quotes_preserved":true,"exact_persisted_types":true,"restored_economy_exact":true,"restored_contacts_exact":true,"observation_unchanged":true}
	output["final_lots"]=e._lots.snapshot()
	output["first_day"]=first_day;output["last_day"]=last_day;output["dated_input_procurement"]=e._dated_input_procurement_enabled
	output["observation_profile"]=profile
	if condition in Consumer.PUBLICITY_CHOICES:output["publicity_actions"]=publicity_actions;output["publicity_chain"]=publicity_chain
	output["persistence_cost"]={"typed_document_bytes":encoded.to_utf8_buffer().size(),"encode_and_stringify_us":encode_us,"formal_restore_us":restore_us}
	var file: FileAccess=FileAccess.open(args[0],FileAccess.WRITE);file.store_string(JSON.stringify(output));file.close()
	completed=true;print("ADAPTIVE_FINISHED ",condition," elapsed_ms=",Time.get_ticks_msec()-started," query_us=",query_us);quit()

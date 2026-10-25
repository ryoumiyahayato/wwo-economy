extends SceneTree
const Opening=preload("res://scripts/content/production_network_opening.gd")
const Process=preload("res://scripts/world/economy_production_process.gd")
var output_path: String
var condition: String

func _initialize() -> void: run.call_deferred()

func cash_total(ledger: FormalLedgerState) -> int:
	var sum: int=0
	for a: Dictionary in ledger.snapshot().accounts.values():sum+=int(a.balance)
	return sum

func check_physical(e: EconomyR1Slice) -> void:
	for good: String in e._goods:
		var made: int=0;var terminal: int=0
		for source: Dictionary in e._lots.sources.values():
			if source.good==good:made+=int(source.quantity)
		for p: Dictionary in e._lots.portions.values():
			if p.good==good:terminal+=int(p.remaining)+int(p.consumed)+int(p.lost)
		assert(made==terminal,"Source conservation: "+good)
	for site: String in e._site_ids():
		for good: String in e._goods:assert(int(e._stocks[site][good])>=0)

func summary(e: EconomyR1Slice) -> Dictionary:
	var firms: Array=[];var made: Dictionary=Opening.stock();var used: Dictionary=Opening.stock();var work: int=0;var paid: int=0;var incurred: int=0;var unpaid: int=0;var overdue: int=0
	for f: String in e._firm_ids():
		var site: String=e._primary_site(f);var ownmade: Dictionary=e._physical_totals[site].produced
		var hours: int=0;var owed: int=0;var wages: int=0
		for w: Dictionary in e._wages.values():
			if w.employer!=f:continue
			hours+=int(w.hours);wages+=int(w.amount);owed+=int(w.remaining)
			if int(w.due_day)<=e.day:overdue+=int(w.remaining)
		work+=hours;incurred+=wages;unpaid+=owed;paid+=wages-owed
		for good: String in e._goods:
			made[good]=int(made[good])+int(ownmade[good]);used[good]=int(used[good])+int(e._physical_totals[site].used[good])
		var dc: Dictionary=e._costs.view(f,30)
		firms.append({"id":f,"site":site,"place":e._place(site),"account":e._account(f),"cash":e._world.ledger_state.balance(e._account(f)),"cash_reserved":e._world.ledger_state.reserved_balance(e._account(f)),"stock":e._stocks[site].duplicate(true),"produced":ownmade.duplicate(true),"used":e._physical_totals[site].used.duplicate(true),"worked_hours":hours,"wage_incurred":wages,"wage_unpaid":owed,"known_sales_revenue":dc.sales_revenue,"known_contribution":dc.contribution,"unknown_sales":dc.unknown_sales,"inventory_cost":dc.inventory})
	var consumed: Dictionary=Opening.stock();var satisfied: int=0;var unmet: int=0
	for a: String in e._actor_ids():
		for row: Dictionary in e._totals[a].categories.values():
			satisfied+=int(row.satisfied);unmet+=int(row.unmet)
			for good: String in e._goods:consumed[good]=int(consumed[good])+int(row.used_items[good])
	var delivered: int=0;var pending: int=0;var reject: Dictionary={}
	for o: Dictionary in e._orders.values():
		delivered+=int(o.delivered);pending+=int(o.quantity)-int(o.delivered)-int(o.cancelled)
	for c: Dictionary in e._commands.values():
		if not c.result.get("accepted",false):reject[c.result.reason]=int(reject.get(c.result.reason,0))+1
	return {"firms":firms,"made":made,"used":used,"consumed_items":consumed,"satisfied_need_units":satisfied,"unmet_need_units":unmet,"worked_person_hours":work,"wages_incurred":incurred,"wages_paid":paid,"wages_unpaid":unpaid,"wages_overdue":overdue,"orders":e._orders.size(),"delivered_quantity":delivered,"pending_quantity":pending,"rejected_commands":reject,"decisions":e._decision_counts.duplicate(true)}

func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args();output_path=args[0];condition=args[1]
	var cfg: Dictionary=Opening.configuration(condition)
	assert(EconomySliceConfig.valid(cfg),"Invalid development configuration "+condition)
	# Negative contract checks use the real configuration validator.
	var invalid: Dictionary=cfg.duplicate(true)
	invalid.firms[4].sites[0].activities[0].process.gross_outputs.flour=0
	assert(not EconomySliceConfig.valid(invalid),"Gross/reject mismatch must be rejected")
	var built: WorldBuildResult=WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,false,cfg)
	assert(built.success,built.error)
	assert(built.world.economy_r1!=null,built.world.native_economy_error)
	var e: EconomyR1Slice=built.world.economy_r1
	var cash_before: int=cash_total(built.world.ledger_state)
	var initial: Dictionary=e._stocks.duplicate(true)
	var days: int=2 if condition.begins_with("fixed_") else 21
	var elapsed: Array=[];var marks: Array=[];var closure: Dictionary={};var sample: Dictionary={}
	for day_index: int in days:
		if condition=="transport" and day_index==2:
			closure=e.submit_internal("firm:network:mill1",{"action_id":"network:close","kind":"set_edge_capacity","payload":{"edge_id":"edge:network:lyon:paris","capacity":0}})
			assert(closure.accepted)
		var began: int=Time.get_ticks_usec()
		var step: Dictionary=built.simulation_step.advance_minutes(1440)
		assert(step.get("success",true),str(step))
		elapsed.append(Time.get_ticks_usec()-began)
		check_physical(e);assert(cash_total(built.world.ledger_state)==cash_before,"Cash conservation")
		if e.day in [2,7,14,21]:
			var mark: Dictionary=summary(e)
			mark.erase("firms");mark.day=e.day;marks.append(mark)
		if condition in ["normal","materials","cash"] and day_index==6:
			var before: Dictionary=e.snapshot()
			sample=e.economy_read_view("firm:network:mill1","firm:network:mill1","site:network:mill1")
			assert(not sample.is_empty())
			assert(e.economy_read_view(WorldBootstrap.DEFAULT_FORMAL_PERSON_ID,"firm:network:mill1","site:network:mill1").is_empty(),"Player cannot read another manager's private business")
			assert(before==e.snapshot(),"Read projection must not change authoritative state")
	var final: Dictionary=summary(e)
	var snap: Dictionary=built.persistence.snapshot()
	var restored: WorldBuildResult=FormalPersistence.new().restore_candidate(snap)
	assert(restored.success,restored.error)
	assert(restored.persistence.snapshot().economy_native==snap.economy_native,"Production contracts survive Formal restore")
	assert(restored.persistence.snapshot().ledger==snap.ledger,"Ledger restore")
	if condition=="normal":
		assert(e._firm_ids().size()==20)
		assert(int(final.made.bread)>0 and final.wages_paid>0 and final.delivered_quantity>0 and int(final.consumed_items.bread)>0,"Real production, wage, delivery and consumption chain")
	if condition in ["materials","technology_no_materials","unavailable"]:assert(int(e._physical_totals["site:network:mill1"].produced.flour)==0)
	if condition=="process_cycle":assert(e._site_state["site:network:mill1"].activities["activity:network:mill1"].batches<=2)
	var active_production: int=0
	for plan: Dictionary in e._plans.values():
		for a: Dictionary in plan.activities.values():
			if int(a.schedule[0].quantity)>0:active_production+=1
	var state_bytes: int=var_to_bytes(e.snapshot()).size()+var_to_bytes(built.world.ledger_state.snapshot()).size()
	elapsed.sort();var sum_us: int=0
	for us: int in elapsed:sum_us+=us
	var result: Dictionary={"condition":condition,"status":"PASS","firm_count":e._firm_ids().size(),"days":days,"initial_stock":initial,"result":final,"marks":marks,"transport_closure":closure,"daily_settlement_us":{"mean":float(sum_us)/days,"median":elapsed[elapsed.size()/2],"max":elapsed.back()},"counts":{"active_production_tasks":active_production,"effective_orders":e._orders.size(),"active_orders":e._active_orders.size(),"lot_sources":e._lots.sources.size(),"lot_portions":e._lots.portions.size(),"transport_tasks":e._shipments.size(),"moving_transport_tasks":e._moving_shipments.size()},"native_ledger_serialized_bytes":state_bytes,"whole_formal_serialized_bytes":var_to_bytes(snap).size(),"formal_restore":true,"readonly_sample":sample,"scope":"DEVELOPMENT_PARAMETERS; NO_MAP_TEXTURE_TERRAIN_GPU; NO_INFINITE_CASH_OR_STOCK"}
	# Small exact evidence, with original IDs, of each formal authority.
	result["evidence"]={"production":e._costs.productions.values().slice(0,2),"wages":e._wages.values().slice(0,2),"orders":e._orders.values().slice(0,2),"deliveries":e._delivery_receipts.values().slice(0,2),"payments":built.world.ledger_state.transactions().filter(func(tx: Dictionary)->bool:return int(tx.effective_minute)>0).slice(0,4)}
	var file: FileAccess=FileAccess.open(output_path,FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("NETWORK_PASS ",condition)
	quit(0)

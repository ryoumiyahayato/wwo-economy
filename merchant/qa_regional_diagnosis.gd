extends SceneTree
## Full-world developer diagnosis only. Never consumed by the player map.
const Multi=preload("res://merchant/multisource_opening.gd")
const Opening=preload("res://merchant/merchant_opening.gd")
const SITES=["site:regional_upstream:lyon","site:regional_food:paris","site:regional_food:lyon","site:regional_textile:paris","site:regional_household:marseille",Opening.SITE]
var completed: bool=false
var started: int=Time.get_ticks_msec()
func _initialize() -> void:call_deferred("run")
func _process(_delta: float) -> bool:
	if not completed and Time.get_ticks_msec()-started>240000:push_error("Regional diagnosis incomplete");quit(1)
	return false

func observe(b: WorldBuildResult) -> Dictionary:
	var e: EconomyR1Slice=b.world.economy_r1
	var result: Dictionary={"minute":b.world.game_clock.total_minutes(),"day":e.day,"phase":e.phase,"sites":{},"original_request_observations":e._request_window.duplicate(true)}
	for site: String in SITES:
		var firm: String=e._owner(site)
		var need: Dictionary=e._input_need(site,"grain")
		var offers: Array=e._input_offers(site,"grain",int(need.need_by_day),maxi(int(need.regular_quantity),int(need.timing_projection.uncovered_future_quantity)),need)
		result.sites[site]={"inventory":e._stocks[site].duplicate(true),"grain_need":need,"ranked_grain":offers,"received_offers":e._offers(firm,site),"plan":e._plans.get(site,{}).duplicate(true),"physical":e._physical_totals[site].duplicate(true),"cash":b.world.ledger_state.balance(e._account(firm)),"available":b.world.ledger_state.available_balance(e._account(firm)),"reserved":b.world.ledger_state.reserved_balance(e._account(firm)),"known_suppliers":e._firm_knowledge[site].duplicate(),"manager":e.firm_manager_at(firm,b.world.game_clock.total_minutes())}
	return result

func benchmark(b: WorldBuildResult) -> Dictionary:
	var before: Dictionary=b.persistence.snapshot()
	var e: EconomyR1Slice=b.world.economy_r1
	var person: String=b.world.player_state.player_id()
	var times: Array=[];var rows: Array=[]
	for repeat: int in 3:
		var begin: int=Time.get_ticks_usec()
		rows=e.managed_network_contacts(person,Opening.FIRM)
		times.append(Time.get_ticks_usec()-begin)
	assert(before==b.persistence.snapshot(),"Contact query changed formal state")
	return {"contacts_us":times,"rows":rows}

func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var canonical: WorldBuildResult=Multi.build("normal")
	assert(canonical.success and canonical.world.economy_r1!=null,canonical.error)
	var initial: Dictionary=canonical.persistence.snapshot();canonical=null
	if "--restore-difference" in args:
		var restored_probe: WorldBuildResult=FormalPersistence.new().restore_candidate(initial)
		assert(restored_probe.success,restored_probe.error)
		var diagnostic: FileAccess=FileAccess.open(args[0],FileAccess.WRITE)
		diagnostic.store_string(JSON.stringify({"fresh":initial,"restored":restored_probe.persistence.snapshot()}));diagnostic.close();completed=true;print("RESTORE_DIFFERENCE_CAPTURED");quit();return
	# The original first restore reconciles spatial/territory metadata. Establish
	# the shared restored start only after exact economic equality is checked.
	var normalized: WorldBuildResult=FormalPersistence.new().restore_candidate(initial)
	assert(normalized.success,normalized.error)
	for key: String in ["economy_native","ledger","total_minutes"]:assert(normalized.persistence.snapshot()[key]==initial[key],"First restore changed economic facts")
	initial=normalized.persistence.snapshot();normalized=null
	var output: Dictionary={"scope":"DEVELOPER_FULL_WORLD_DIAGNOSIS_NOT_PLAYER_KNOWLEDGE","starting_basis":"COMMON_FORMAL_RESTORED_STATE_ECONOMY_LEDGER_CLOCK_UNCHANGED","branches":{}}
	for condition: String in ["normal","blocked"]:
		var b: WorldBuildResult=FormalPersistence.new().restore_candidate(initial)
		assert(b.success,b.error)
		assert(b.persistence.snapshot()==initial)
		assert(Multi.capacity(b.world,0 if condition=="blocked" else 10).get("accepted",false))
		var e: EconomyR1Slice=b.world.economy_r1
		e._procurement_diagnostics_enabled=not "--baseline-only" in args
		var records: Array=[];var orders_seen: Dictionary={};var commands_seen: Dictionary={};var sources_seen: Dictionary={};var wages_seen: Dictionary={}
		var ledger_cursor: int=b.world.ledger_state.transactions().size()
		for boundary: int in range(1,41):
			while b.world.game_clock.total_minutes()<boundary*1440-1:
				assert(b.simulation_step.advance_minutes(mini(60,boundary*1440-1-b.world.game_clock.total_minutes())).get("success",true))
			var before: Dictionary=observe(b)
			assert(b.simulation_step.advance_minutes(1).get("success",true))
			var after: Dictionary=observe(b)
			var orders: Array=[];var commands: Array=[];var sources: Array=[];var wages: Array=[]
			for id: String in e._orders:
				if not orders_seen.has(id) or orders_seen[id]!=e._orders[id]:orders.append(e._orders[id].duplicate(true));orders_seen[id]=e._orders[id].duplicate(true)
			for id: String in e._commands:
				if commands_seen.has(id):continue
				commands_seen[id]=true
				var row: Dictionary=e._commands[id]
				if row.envelope.command.kind in ["buy","post_goods_quote","post_managed_goods_quote"]:commands.append(row.duplicate(true))
			for id: String in e._lots.sources:
				if sources_seen.has(id):continue
				sources_seen[id]=true
				if id.begins_with("production:"):sources.append(e._lots.sources[id].duplicate(true))
			for id: String in e._wages:
				if not wages_seen.has(id) or wages_seen[id]!=e._wages[id]:wages.append(e._wages[id].duplicate(true));wages_seen[id]=e._wages[id].duplicate(true)
			var all_cash: Array[Dictionary]=b.world.ledger_state.transactions()
			var cash: Array=all_cash.slice(ledger_cursor);ledger_cursor=all_cash.size()
			records.append({"before_boundary":before,"after_boundary":after,"procurement_decisions":e._procurement_observations.duplicate(true),"changed_orders":orders,"new_commands":commands,"new_production_sources":sources,"changed_wages":wages,"ledger":cash,"transport":e._transport.duplicate(true)})
			if boundary in [1,5,6,9,14,28,40]:print("REGIONAL_DIAG ",condition," day=",boundary," food_grain=",e._stocks["site:regional_food:paris"].grain," food_cash=",b.world.ledger_state.balance("account:regional_food")," orders=",e._orders.size())
			if boundary==14:
				if condition=="normal" and args.size()>2 and args[2]!="--baseline-only":
					var decoded: Dictionary=FormalWorldPersistenceDocument.decode(JSON.parse_string(FileAccess.get_file_as_string(args[2])))
					assert(decoded.success,decoded.error)
					for key: String in ["economy_native","ledger","total_minutes"]:assert(decoded.snapshot[key]==b.persistence.snapshot()[key],"Diagnostic capture changed economic outcomes")
				output[condition+"_query_baseline"]=benchmark(b)
				if condition=="normal":
					var checkpoint: FileAccess=FileAccess.open(args[1],FileAccess.WRITE);checkpoint.store_string(JSON.stringify(FormalWorldPersistenceDocument.encode(b.persistence.snapshot())));checkpoint.close()
					if "--baseline-only" in args:completed=true;print("REGIONAL_DIAG_BASELINE_FINISHED trace_disabled=true");quit();return
		var restored: WorldBuildResult=FormalPersistence.new().restore_candidate(b.persistence.snapshot())
		assert(restored.success,restored.error)
		for key: String in ["economy_native","ledger","total_minutes"]:assert(restored.persistence.snapshot()[key]==b.persistence.snapshot()[key])
		output.branches[condition]={"records":records,"final_lots":e._lots.snapshot(),"restore_exact":true}
	var file: FileAccess=FileAccess.open(args[0],FileAccess.WRITE);file.store_string(JSON.stringify(output,"\t"));file.close()
	completed=true;print("REGIONAL_DIAG_FINISHED");quit()

extends SceneTree
## Requested controlled scenarios / scale measurement, not a second world owner.
const Reference=preload("res://scripts/world/global_commodity_reference.gd")
const Save=preload("res://merchant/merchant_save.gd")
const Runtime=preload("res://merchant/merchant_runtime.gd")
var args: PackedStringArray

func _initialize() -> void:call_deferred("run")

func run() -> void:
	args=OS.get_cmdline_user_args()
	if args.is_empty():push_error("Use benchmark or coupled, then an output filename");quit(2);return
	var result: Dictionary={}
	if args[0]=="benchmark":result=_benchmark()
	elif args[0]=="benchmark50":result=_benchmark([1])
	elif args[0]=="coupled":result=_coupled()
	else:quit(2);return
	if args.size()>1:
		var f:=FileAccess.open(args[1],FileAccess.WRITE);f.store_string(JSON.stringify(result,"\t"));f.close()
	print("GLOBAL_MARKET_FINISHED ",JSON.stringify(result.get("summary",{})));quit()

func _benchmark(scales: Array=[1,10]) -> Dictionary:
	var b: WorldBuildResult=WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,false)
	assert(b.success,b.error)
	var rows: Array=[]
	for copies: int in scales:
		var scenarios: Array=["baseline","supply","demand","transport","shocks"] if copies==1 else ["baseline"]
		for scenario: String in scenarios:
			# No native actors are advanced in this timing. Each independent run uses
			# the existing formal GameClock; only indicator cost is being measured.
			assert(b.world.game_clock.restore({"total_minutes":0,"minute_remainder":0}))
			var memory_before: int=OS.get_static_memory_usage();var setup_begin: int=Time.get_ticks_usec()
			var r: RefCounted=Reference.new();r.bind(b.world.economy_state);r.initialize(0,scenario,copies)
			var setup_us: int=Time.get_ticks_usec()-setup_begin
			var begin: int=Time.get_ticks_usec();var marks: Array=[]
			for day: int in range(1,366):
				b.world.game_clock.advance_minutes(1440)
				r.settle(b.world.game_clock.total_minutes()/1440)
				if day in [1,14,16,30,45,60,75,90,120,180,270,365]:marks.append(_mark(r))
			var elapsed: int=Time.get_ticks_usec()-begin
			var state_memory_end: int=OS.get_static_memory_usage()
			var compact_bytes: int=var_to_bytes(r.data).size();var json_bytes: int=JSON.stringify(r.data).to_utf8_buffer().size()
			var valid: bool=true
			if copies==1:
				var restored: RefCounted=Reference.new();restored.bind(b.world.economy_state)
				valid=restored.restore(bytes_to_var(var_to_bytes(r.data)),365)
				assert(valid and restored.data==r.data)
			var stats: Dictionary={"regions":r.data.nodes.size(),"goods":Reference.GOODS.size(),"edges":r.data.edges.size(),"scenario":scenario,"years":1,"setup_us":setup_us,"simulation_us":elapsed,"memory_delta_bytes":state_memory_end-memory_before,"memory_scope":"GODOT_STATIC_ALLOCATOR_DELTA_NOT_PROCESS_RSS","typed_state_bytes":compact_bytes,"compact_json_bytes":json_bytes,"history_limit_days":Reference.HISTORY,"restore_reference":valid if copies==1 else "TEN_DISJOINT_STRESS_REPLICAS_NOT_NEW_GEOGRAPHIC_MARKETS","marks":marks}
			rows.append(stats);print("GLOBAL_MARKET_BENCHMARK ",JSON.stringify(stats))
	return {"summary":{"scope":"INDICATOR_ALGORITHM_ONLY_NOT_FULL_R1_YEAR","runs":rows.size()},"runs":rows}

func _mark(r: RefCounted) -> Dictionary:
	var values: Dictionary={}
	for id: String in ["united_states_1900","british_isles_1900","country_fra","german_empire","argentina_1900","qing_empire","empire_of_japan","brazil_1900","congo_free_state"]:
		values[id]={}
		for good: String in ["wheat","coal","iron_ore","steel","coffee","natural_rubber"]:
			var c: Dictionary=r.data.cells[id+"|"+good]
			values[id][good]={"price":c.price,"supply":c.supply,"demand":c.demand,"cover":c.cover,"imports":c.imports,"exports":c.exports,"unmet":c.unmet}
	var flows: Array=[]
	for flow: Dictionary in r.data.flows:
		if flow.good in ["wheat","coal"]:flows.append(flow.duplicate(true))
	flows.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return float(a.estimated_units)>float(b.estimated_units))
	if flows.size()>12:flows.resize(12)
	return {"day":r.data.day,"values":values,"flow_count":r.data.flows.size(),"largest_wheat_coal_flows":flows}

func _coupled() -> Dictionary:
	var source: PackedByteArray=FileAccess.get_file_as_bytes(Save.path(6))
	var results: Array=[]
	for enabled: bool in [false,true]:
		var store: RefCounted=Save.new();var b: WorldBuildResult=store.load_slot(6);assert(b.success,b.error)
		b.world.economy_r1._dated_input_procurement_enabled=true
		var e: EconomyR1Slice=b.world.economy_r1
		var begin_cash: int=b.world.ledger_state.balance(e._account("firm:regional_food"))
		if enabled:assert(b.world.economy_state.enable_reference_market("shocks"))
		var started: int=Time.get_ticks_usec();var timeline: Array=[]
		for i: int in 30:
			assert(b.simulation_step.advance_minutes(1440).get("success",true))
			if enabled and i in [0,7,14,29]:timeline.append(_mark(b.world.economy_state.reference_market))
		var elapsed: int=Time.get_ticks_usec()-started
		var influenced: Array=[];var evaluated: Array=[];var grain_orders: Array=[]
		for entry: Dictionary in e._commands.values():
			if entry.result.get("decision",{}).get("reason")=="DELAYED_PUBLIC_INDEX_AND_OWN_SALES":influenced.append(entry.duplicate(true))
			if entry.result.get("decision",{}).has("public_reference_bulletin"):evaluated.append(entry.duplicate(true))
		for o: Dictionary in e._orders.values():
			if o.good=="grain" and int(o.accepted_minute)>=33120:grain_orders.append(o.duplicate(true))
		var snapshot: Dictionary=b.persistence.snapshot()
		var restore_start: int=Time.get_ticks_usec();var restored: WorldBuildResult=b.persistence.restore_candidate(snapshot)
		assert(restored.success,restored.error)
		for field: String in ["total_minutes","economy_native","ledger","economy"]:assert(restored.persistence.snapshot()[field]==snapshot[field],field)
		var restore_us: int=Time.get_ticks_usec()-restore_start
		if enabled:
			var corrupted: Dictionary=snapshot.duplicate(true);corrupted.economy.reference_market.cells["country_fra|wheat"].price=-1.0
			assert(not FormalPersistence.new().restore_candidate(corrupted).success,"Invalid price must fail restore")
			if not Save.has_slot(7):assert(store.save(b,7,store.plans).success)
		var row: Dictionary={"global_enabled":enabled,"minute":b.world.game_clock.total_minutes(),"simulation_us":elapsed,"restore_us":restore_us,"food_cash_begin":begin_cash,"food_cash_end":b.world.ledger_state.balance(e._account("firm:regional_food")),"food_production":e._physical_totals.get("site:regional_food:paris",{}),"grain_orders":grain_orders,"price_signal_decisions":influenced,"price_signal_evaluations":evaluated,"timeline":timeline,"reference_local":b.world.economy_state.reference_market.data.local if enabled else {},"signal_receipts":b.world.economy_state.reference_market.data.policy_receipts if enabled else {},"formal_typed_bytes":var_to_bytes(snapshot).size(),"restore_exact":true}
		results.append(row);print("GLOBAL_MARKET_COUPLED ",JSON.stringify(row))
	assert(source==FileAccess.get_file_as_bytes(Save.path(6)),"Input trial overwritten")
	return {"summary":{"scope":"SAME_DAY24_TRIAL_30_FORMAL_DAYS","conditions":2,"source_unchanged":true},"runs":results}

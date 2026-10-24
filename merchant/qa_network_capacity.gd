extends SceneTree
const Experiment=preload("res://merchant/network_experiment_opening.gd")
const Runtime=preload("res://merchant/merchant_runtime.gd")
const Opening=preload("res://merchant/merchant_opening.gd")
const Contacts=preload("res://merchant/merchant_market_contacts.gd")
var failure: String=""

func _initialize() -> void:call_deferred("run")

func require(ok: bool, message: String) -> bool:
	if not ok:failure=message;push_error(message)
	return ok

func capture(built: WorldBuildResult, runtime: RefCounted) -> Dictionary:
	var before: Dictionary=built.persistence.snapshot()
	var started: int=Time.get_ticks_usec()
	var view: Dictionary=runtime._view(built)
	var elapsed: int=Time.get_ticks_usec()-started
	require(before==built.persistence.snapshot(),"Observation mutated formal state")
	var orders: Array=[]
	for order: Dictionary in built.world.economy_r1._orders.values():
		if order.buyer==Opening.FIRM and order.good=="grain":orders.append(order.duplicate(true))
	return {"minute":view.minute,"view_us":elapsed,"orders":orders,"map_snapshot":view,"lots_quantity":built.world.economy_r1._lots.quantity_at("SITE|"+Opening.SITE,"grain")}

func run() -> void:
	var built: WorldBuildResult=Experiment.build()
	if not require(built.success,built.error):quit(1);return
	var initial: Dictionary=built.persistence.snapshot()
	built=null
	built=FormalPersistence.new().restore_candidate(initial)
	if not require(built.success,built.error):quit(1);return
	initial=built.persistence.snapshot() # Both branches use the formal restored continuation.
	var initial_stock: Dictionary=built.world.economy_r1._lots.snapshot()
	var outputs: Dictionary={}
	for condition: String in ["open","blocked"]:
		if condition=="blocked":
			built=null
			built=FormalPersistence.new().restore_candidate(initial)
			if not require(built.success,built.error):quit(1);return
			if not require(built.persistence.snapshot()==initial,"A/B did not restore exact same starting state"):quit(1);return
		var runtime: RefCounted=Runtime.new();runtime._slot=0;runtime._network_experiment=true
		var before_stock: Dictionary=built.world.economy_r1._lots.snapshot()
		var action: Dictionary=Experiment.capacity(built.world,10 if condition=="open" else 0)
		if not require(action.get("accepted",false),str(action)):quit(1);return
		if not require(before_stock==initial_stock and before_stock==built.world.economy_r1._lots.snapshot(),"Capacity action altered physical goods"):quit(1);return
		var records: Array=[capture(built,runtime)]
		for hour: int in 120:
			var result: Dictionary=built.simulation_step.advance_minutes(60)
			if not require(result.get("success",true),str(result)):quit(1);return
			if built.world.game_clock.total_minutes()%1440==0:records.append(capture(built,runtime))
		var last: Dictionary=records.back()
		if condition=="open":
			require(not last.orders.is_empty(),"Open route did not produce an automatic merchant grain order")
			var delivered: int=0
			for order: Dictionary in last.orders:
				require(str(order.action_id).begins_with("auto:"+Opening.FIRM+":"),"Purchase bypassed original autonomous procurement")
				delivered+=int(order.delivered)
			require(delivered>0,"Open route did not physically deliver grain")
			var activity: Dictionary=last.map_snapshot.market_contacts.nodes["place:lyon"].goods.grain
			require(activity.sent==delivered and activity.received==0,"Observed commodity activity differs from actual delivery receipts")
			var aged: Dictionary=Contacts.project(last.map_snapshot.firm,[],int(last.minute)+7*1440)
			require(aged.nodes["place:lyon"].goods.is_empty(),"Old deliveries remain a current centre forever")
			var receipts: Array=[]
			for order: Dictionary in last.orders:
				var paid: int=0
				for tx: Dictionary in built.world.ledger_state.transactions():
					if tx.get("reference_id")==order.id:
						paid+=int(tx.amount);receipts.append(tx)
				require(paid==int(order.quantity)*(int(order.price)+built.world.economy_r1._freight(order.route_legs)),"Delivery goods/freight payment mismatch")
			outputs["open_receipts"]=receipts
		else:require(last.orders.is_empty(),"Closed only known grain corridor still created a merchant grain order")
		var restored: WorldBuildResult=FormalPersistence.new().restore_candidate(built.persistence.snapshot())
		require(restored.success,restored.error)
		if restored.success:
			for key: String in ["economy_native","ledger","total_minutes"]:require(restored.persistence.snapshot()[key]==built.persistence.snapshot()[key],"Restore changed "+key)
		for source_id: String in built.world.economy_r1._lots.sources:
			var total: int=0
			for portion: Dictionary in built.world.economy_r1._lots.portions.values():
				if portion.source_id==source_id:total+=int(portion.remaining)+int(portion.consumed)+int(portion.lost)
			require(total==int(built.world.economy_r1._lots.sources[source_id].quantity),"StockLots source conservation: "+source_id)
		require(built.world.economy_r1.managed_network_contacts("unrelated",Opening.FIRM).is_empty(),"Unauthorized contacts exposed")
		outputs[condition]={"capacity_action":action,"records":records,"restore_exact":restored.success}
		print("NETWORK_CONDITION ",condition," orders=",last.orders.size()," own_grain=",last.lots_quantity)
	# Continue the actual blocked branch. Reopening changes a formal action,
	# not inventory, knowledge, budget or the procurement algorithm.
	var recovery_runtime: RefCounted=Runtime.new();recovery_runtime._slot=0;recovery_runtime._network_experiment=true
	var reopening: Dictionary=Experiment.capacity(built.world,10)
	require(reopening.get("accepted",false),str(reopening))
	var recovery: Array=[capture(built,recovery_runtime)]
	for hour: int in 72:
		require(built.simulation_step.advance_minutes(60).get("success",true),"Recovery clock failure")
		if built.world.game_clock.total_minutes()%1440==0:recovery.append(capture(built,recovery_runtime))
	var recovered: Dictionary=recovery.back()
	require(not recovered.orders.is_empty() and recovered.lots_quantity>0,"Original autonomous procurement did not resume after reopening")
	outputs["reopened"]={"capacity_action":reopening,"records":recovery}
	print("NETWORK_CONDITION reopened orders=",recovered.orders.size()," own_grain=",recovered.lots_quantity)
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var output: FileAccess=FileAccess.open(args[0],FileAccess.WRITE)
	output.store_string(JSON.stringify({"status":"PASS" if failure.is_empty() else "FAIL","failure":failure,"case":Experiment.CASE,"conditions":outputs},"\t"));output.close()
	quit(0 if failure.is_empty() else 1)

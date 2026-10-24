extends SceneTree
const Opening=preload("res://merchant/merchant_opening.gd")
const Multi=preload("res://merchant/multisource_opening.gd")
const Runtime=preload("res://merchant/merchant_runtime.gd")
var started: int=Time.get_ticks_msec()
var completed: bool=false
func _process(_delta: float) -> bool:
	if not completed and Time.get_ticks_msec()-started>120000:push_error("Multisource experiment did not complete within120s");quit(1)
	return false
func _initialize() -> void:call_deferred("run")

func record(b: WorldBuildResult,runtime: RefCounted) -> Dictionary:
	var state: Dictionary=b.persistence.snapshot()
	var view: Dictionary=runtime._view(b)
	assert(state==b.persistence.snapshot(),"Observation changed economy")
	var purchases: Array=[];var sales: Array=[];var receipts: Array=[];var other_orders: Array=[]
	for o: Dictionary in b.world.economy_r1._orders.values():
		if o.good!="grain":
			if o.buyer==Opening.FIRM or o.seller==Opening.FIRM:other_orders.append(o.duplicate(true))
			continue
		if o.buyer==Opening.FIRM:purchases.append(o.duplicate(true))
		if o.seller==Opening.FIRM:sales.append(o.duplicate(true))
	for tx: Dictionary in b.world.ledger_state.transactions():
		if tx.get("from_account_id")=="account:merchant_prototype" or tx.get("to_account_id")=="account:merchant_prototype":receipts.append(tx)
	return {"minute":view.minute,"contacts":view.market_contacts,"network":view.market_network,"inventory":view.firm.inventory,"cash":view.firm.cash,"reserved":view.firm.reserved,"purchases":purchases,"sales":sales,"other_orders":other_orders,"ledger":receipts}

func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var b: WorldBuildResult=Multi.build()
	assert(b.success and b.world.economy_r1!=null,b.world.native_economy_error)
	var initial: Dictionary=b.persistence.snapshot();b=null
	b=FormalPersistence.new().restore_candidate(initial);assert(b.success,b.error)
	initial=b.persistence.snapshot()
	var results: Dictionary={}
	for condition: String in Multi.CONDITIONS:
		if condition=="blocked":
			b=null;b=FormalPersistence.new().restore_candidate(initial)
			assert(b.success and b.persistence.snapshot()==initial)
		elif condition not in ["normal","blocked"]:
			b=null;b=Multi.build(condition)
			assert(b.success and b.world.economy_r1!=null,b.world.native_economy_error)
		var runtime: RefCounted=Runtime.new();runtime._slot=0;runtime._network_experiment=true
		var action: Dictionary=Multi.capacity(b.world,0 if condition=="blocked" else 10)
		assert(action.get("accepted",false),str(action))
		var records: Array=[record(b,runtime)]
		for boundary: int in range(1,15):
			while b.world.game_clock.total_minutes()<boundary*1440:
				assert(b.simulation_step.advance_minutes(mini(60,boundary*1440-b.world.game_clock.total_minutes())).get("success",true))
			records.append(record(b,runtime))
		var last: Dictionary=records.back()
		assert(last.purchases.size()==1)
		var first: Dictionary=last.purchases[0]
		assert(first.seller_site==(Multi.PARIS if condition=="blocked" else Multi.LYON))
		assert(first.quantity==(4 if condition=="blocked" else 5 if condition=="cash_limited" else 6))
		assert(first.delivered==first.quantity and first.pending==0 and first.transit==0)
		if condition=="blocked":assert(last.sales.size()>0 and last.inventory.grain==0 and last.cash==84)
		else:assert(last.sales.is_empty() and last.inventory.grain==first.quantity)
		var incoming_cash: int=0;var outgoing_cash: int=0
		for tx: Dictionary in last.ledger:
			if tx in records[0].ledger:continue # Opening allocation is already in initial cash.
			if tx.get("to_account_id")=="account:merchant_prototype":incoming_cash+=int(tx.amount)
			if tx.get("from_account_id")=="account:merchant_prototype":outgoing_cash+=int(tx.amount)
		assert(int(last.cash)==(20 if condition=="cash_limited" else 80)+incoming_cash-outgoing_cash)
		assert(last.reserved==0)
		if condition=="notice_delayed":
			assert(not records[1].contacts.contacts.any(func(row: Dictionary):return row.seller_site==Multi.COAST and row.good=="grain"))
			assert(records[3].contacts.contacts.any(func(row: Dictionary):return row.seller_site==Multi.COAST and row.good=="grain"))
		if condition=="two_goods":
			var soap: Array=last.other_orders.filter(func(o: Dictionary):return o.buyer==Opening.FIRM and o.good=="soap")
			assert(not soap.is_empty() and soap[0].from_place_id=="place:marseille" and first.from_place_id=="place:lyon","Different goods did not use their actual different sources")
		print("MULTISOURCE ",condition," purchases=",last.purchases.size()," sales=",last.sales.size()," cash=",last.cash," stock=",last.inventory.grain)
		for order: Dictionary in last.purchases:print("BUY ",order.id," ",order.seller_site," q=",order.quantity," delivered=",order.delivered," day=",order.accepted_day)
		var restored: WorldBuildResult=FormalPersistence.new().restore_candidate(b.persistence.snapshot())
		assert(restored.success,restored.error)
		for key: String in ["economy_native","ledger","total_minutes"]:assert(restored.persistence.snapshot()[key]==b.persistence.snapshot()[key])
		for id: String in b.world.economy_r1._lots.sources:
			var quantity: int=0
			for portion: Dictionary in b.world.economy_r1._lots.portions.values():
				if portion.source_id==id:quantity+=int(portion.remaining)+int(portion.consumed)+int(portion.lost)
			assert(quantity==b.world.economy_r1._lots.sources[id].quantity)
		var receipts: Dictionary={};var descendants: Dictionary={};var trace: Array=[]
		var economy: EconomyR1Slice=b.world.economy_r1
		for receipt: Dictionary in economy._delivery_receipts.values():
			if receipt.order_id==first.id:receipts[receipt.id]=true
		var portion_ids: Array=economy._lots.portions.keys()
		portion_ids.sort_custom(func(a: String,b_id: String):return int(a.trim_prefix("portion:"))<int(b_id.trim_prefix("portion:")))
		var consumed: int=0;var remaining: int=0;var lost: int=0
		for id: String in portion_ids:
			var portion: Dictionary=economy._lots.portions[id]
			if not receipts.has(portion.acquisition_id) and not descendants.has(portion.parent_portion_id):continue
			descendants[id]=true;trace.append(portion.duplicate(true))
			consumed+=int(portion.consumed);remaining+=int(portion.remaining);lost+=int(portion.lost)
		assert(consumed+remaining+lost==first.delivered,"Purchased portions disappeared or duplicated downstream")
		print("DOWNSTREAM ",condition," consumed=",consumed," remaining=",remaining," cash_in=",incoming_cash," cash_out=",outgoing_cash)
		results[condition]={"capacity_action":action,"opening_totals":Multi.totals(Multi.configuration(condition)),"records":records,"restore_exact":true,"lots_conservation":true,"cash_received_after_opening":incoming_cash,"cash_paid_after_opening":outgoing_cash,"purchased_portion_trace":trace,"purchased_quantity_consumed":consumed,"purchased_quantity_remaining":remaining}
	var file: FileAccess=FileAccess.open(args[0],FileAccess.WRITE);file.store_string(JSON.stringify(results,"\t"));file.close();completed=true;print("MULTISOURCE_ALL_FINISHED");quit()

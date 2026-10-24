extends SceneTree
const Save=preload("res://merchant/merchant_save.gd")
const Runtime=preload("res://merchant/merchant_runtime.gd")
const Opening=preload("res://merchant/merchant_opening.gd")
var tracked_sources: Dictionary={}
func _initialize() -> void:call_deferred("run")
func record(built: WorldBuildResult,runtime: RefCounted,id: String) -> Dictionary:
	var e: EconomyR1Slice=built.world.economy_r1
	var o: Dictionary=e._orders[id]
	var host: Dictionary=runtime._view(built)
	var net: Dictionary=host.market_network
	assert(net.issues.is_empty(),str(net.issues))
	var actual_ids: Array=[]
	for sid: String in e._shipments_by_order.get(id,{}):actual_ids.append(sid)
	var projected_ids: Array=[]
	var cargo: int=0
	for sid: String in net.cargo:
		var c: Dictionary=net.cargo[sid]
		if c.order_id!=id:continue
		projected_ids.append(sid)
		assert(c.physical_quantity==e._lots.quantity_at("CARGO|"+sid,o.good))
		assert(str(c.place_id).is_empty() or net.nodes.has(c.place_id))
		cargo+=int(c.physical_quantity)
	actual_ids.sort();projected_ids.sort();assert(actual_ids==projected_ids,"Missing or duplicated physical cargo projection")
	for source: String in tracked_sources:
		var accounted: int=0
		for portion: Dictionary in e._lots.portions.values():
			if portion.source_id==source:accounted+=int(portion.remaining)+int(portion.consumed)+int(portion.lost)
		assert(accounted==int(e._lots.sources[source].quantity),"Source conservation failed")
	assert(net.edges.has(id))
	assert(int(o.pending)+int(o.transit)+int(o.delivered)+int(o.cancelled)==int(o.quantity))
	return {"minute":built.world.game_clock.total_minutes(),"order":o.duplicate(true),"reserved_physical":e._lots.reserved_quantity(id),"cargo_physical":cargo,"buyer_cash":built.world.ledger_state.balance(o.buyer_account),"buyer_cash_reserved":built.world.ledger_state.reserved_balance(o.buyer_account),"seller_stock":e._lots.quantity_at("SITE|"+o.seller_site,o.good),"buyer_stock":e._lots.quantity_at("SITE|"+o.buyer_site,o.good),"network":net}
func run() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var source_bytes: PackedByteArray=FileAccess.get_file_as_bytes(args[0])
	var decoded: Dictionary=Save._read(args[0],5);assert(decoded.get("error","").is_empty())
	var built: WorldBuildResult=FormalPersistence.new().restore_candidate(decoded.core);assert(built.success)
	var runtime: RefCounted=Runtime.new();runtime._slot=5
	var business: Dictionary=built.world.economy_r1.business_view(built.world.player_state.player_id(),Opening.FIRM,Opening.SITE,2,0,16)
	var selected: Dictionary={}
	for offer: Dictionary in business.offers:
		if offer.get("good")=="bread" and offer.get("seller_site")=="site:regional_food:lyon" and offer.get("can_order",false):selected=offer;break
	assert(not selected.is_empty(),"No actual legal Lyon bread offer: "+str(business.offers))
	var purchase: Dictionary=LivelihoodAction.execute_current(built.world,"buy",selected.request)
	assert(purchase.get("accepted",false),str(purchase))
	var id: String=purchase.order_id
	for part: Dictionary in built.world.economy_r1._lots.reserved_selection(id,int(purchase.quantity)):tracked_sources[part.source_id]=true
	assert(not tracked_sources.is_empty())
	var first: Dictionary=record(built,runtime,id)
	assert(first.reserved_physical==purchase.quantity and first.order.pending==purchase.quantity)
	var records: Array=[first]
	var saw_cargo: bool=false
	var previous: String=""
	for hour: int in range(144):
		assert(built.simulation_step.advance_minutes(60).get("success",true))
		var r: Dictionary=record(built,runtime,id)
		var stage: String=str([r.order.pending,r.order.transit,r.order.delivered,r.cargo_physical])
		if stage!=previous:records.append(r);print("LIVE_ORDER_PHASE ",r.minute," ",stage);previous=stage
		if r.cargo_physical>0:saw_cargo=true
		if r.order.delivered==purchase.quantity:break
	var last: Dictionary=record(built,runtime,id)
	assert(saw_cargo,"No observed actual cargo")
	assert(last.order.delivered==purchase.quantity and last.order.transit==0 and last.order.pending==0)
	assert(last.reserved_physical==0 and last.cargo_physical==0)
	var receipts: Array=[]
	for tx: Dictionary in built.world.ledger_state.transactions():
		if str(tx.get("reference_id",""))==id:receipts.append(tx)
	assert(receipts.size()==2,"Expected exact goods and freight receipts")
	var goods_paid: int=0
	var freight_paid: int=0
	for tx: Dictionary in receipts:
		assert(tx.from_account_id==last.order.buyer_account)
		if tx.kind=="goods":
			assert(tx.to_account_id==last.order.seller_account);goods_paid+=int(tx.amount)
		elif tx.kind=="freight":freight_paid+=int(tx.amount)
	assert(goods_paid==int(purchase.quantity)*int(purchase.price))
	assert(goods_paid+freight_paid==first.buyer_cash_reserved)
	assert(first.buyer_cash-last.buyer_cash==goods_paid+freight_paid and last.buyer_cash_reserved==0)
	assert(last.buyer_stock==first.buyer_stock+int(purchase.quantity))
	var save: RefCounted=Save.new();assert(save.save(built,5,decoded.plans).success)
	var restored: WorldBuildResult=save.load_slot(5);assert(restored.success)
	for key: String in ["economy_native","ledger","total_minutes"]:assert(built.persistence.snapshot()[key]==restored.persistence.snapshot()[key])
	assert(source_bytes==FileAccess.get_file_as_bytes(args[0]),"Original save changed")
	var output: Dictionary={"status":"PASS","scope":"ORIGINAL_GAME_BUY_ENTRY_NATURAL_NPC_TIME_NOT_GUI","purchase":purchase,"offer":selected,"records":records,"final":last,"ledger_receipts":receipts,"save_restore_exact":true,"original_save_unchanged":true,"source_conservation":true,"exact_cargo_id_set":true,"exact_order_receipts":true}
	var f: FileAccess=FileAccess.open(args[1],FileAccess.WRITE);assert(f!=null);f.store_string(JSON.stringify(output,"\t"));f.close()
	print("QA_MARKET_NETWORK_LIVE_ORDER_PASS ",id);quit()

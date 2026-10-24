extends SceneTree
## Detached projection fixtures only. No world, GUI, save, payment or order action.
## Written for the parent's serialized test window; writing this file is not a pass.
const Timing=preload("res://merchant/merchant_decision_projection.gd")
const Supply=preload("res://merchant/merchant_supply_projection.gd")
const DEADLINE: int=10*1440+12*60
const BEFORE: int=10*1440+10*60

func _cargo(id: String, quantity: int, earliest: Variant, stage: String="TRANSIT") -> Dictionary:
	return {"id":id,"quantity":quantity,"physical_quantity":quantity,"stage":stage,"earliest_arrival_day":earliest}

func _single_order(cargo: Dictionary) -> Dictionary:
	return {"id":"one-order","quantity":cargo["quantity"],"pending":0,"transit":cargo["quantity"],"delivered":0,"shipments":[cargo],"deliveries":[]}

func _classified(timing: Dictionary) -> int:
	var total: int=0
	for key: String in ["possible","late","unknown","unbound","expired"]:total+=int(timing[key])
	return total

func _initialize() -> void:
	# One accepted order has multiple actual shipments, not one ETA for all units.
	var early: Dictionary=_cargo("early",3,10)
	early["arrival_minute"]=10*1440+11*60
	var order: Dictionary={"id":"mixed","good":"grain","buyer_site":"buyer","quantity":16,"pending":2,"transit":9,"delivered":5,"earliest_arrival_day":11,"shipments":[_cargo("late",4,11),early,_cargo("unknown",2,null,"WAITING")],"deliveries":[{"id":"receipt-first","quantity":2,"delivered_day":9,"delivered_minute":9*1440+720},{"id":"receipt-second","quantity":3,"delivered_day":10,"delivered_minute":10*1440+1}]}
	var contract: Dictionary={"id":"own-supply","accept_action":"accepted","quantity":16,"ontime":5,"late":0,"in_transit":11,"batches":["mixed"],"status":"PARTIAL","price":5,"paid":25,"deadline":DEADLINE,"unallocated":0,"free_stock":0,"secured_unallocated":0}
	var original: Dictionary=order.duplicate(true)
	var original_contract: Dictionary=contract.duplicate(true)
	var timing: Dictionary=Timing.order_timing(order,DEADLINE,BEFORE)
	assert(timing["possible"]==3 and timing["late"]==4 and timing["unknown"]==4,"Mixed shipment quantities must remain separately timed; pending is unknown")
	assert(timing["unbound"]==0 and timing["expired"]==0 and timing["received"]==5,"Actual receipts must not be added to delivered total twice")
	assert(_classified(timing)==11 and _classified(timing)+int(timing["received"])==16,"Every unit belongs to one timing category or actual receipt")
	assert(timing["rows"].size()==6,"Three shipments, two receipts and one pending responsibility produce six rows")
	var prior: int=-1
	var reached_unknown: bool=false
	for row: Dictionary in timing["rows"]:
		if row["minute"]==null:reached_unknown=true;continue
		assert(not reached_unknown and int(row["minute"])>=prior,"Known event times precede unknown times and are ordered")
		prior=int(row["minute"])
	var text: String=Timing.order_timing_text(order,contract,BEFORE)
	for expected: String in ["预计可能及时3","最早也迟到4","时间未知4","有货但未到","已实际收到 ×2","已实际收到 ×3","第11天 11:00","第11天 12:00","不是保证"]:
		assert(text.contains(expected),"Missing truthful timing text: "+expected)
	assert(order==original and contract==original_contract,"Presentation must not mutate its detached source")
	assert(timing==Timing.order_timing(order,DEADLINE,BEFORE) and text==Timing.order_timing_text(order,contract,BEFORE),"Repeated queries must be deterministic")

	# The same own order in purchase/sale views is one responsibility, not two.
	var firm: Dictionary={"orders":[order.duplicate(true)],"sales_orders":[order.duplicate(true)]}
	var original_firm: Dictionary=firm.duplicate(true)
	var supply: Dictionary=Supply.project(contract,firm,BEFORE)
	assert(supply["known_batches"]==1 and supply["pending"]==2 and supply["transit"]==9,"Deduplicate an order present in both authorized lists")
	assert(supply["possible_quantity"]==3 and supply["late_quantity"]==4 and supply["unknown_quantity"]==4,"Supply summary must use shipment quantities")
	assert(supply["late_risk"].size()==1 and supply["late_risk"][0]["quantity"]==4,"Only the actually minimum-late batch is a late risk")
	assert(supply==Supply.project(contract,firm,BEFORE) and firm==original_firm and contract==original_contract,"Supply query must also be pure and repeatable")
	var second: Dictionary=_single_order(_cargo("second-cargo",1,10))
	second["id"]="second-order"
	firm["orders"].append(second);firm["sales_orders"].append(second.duplicate(true))
	contract["batches"].append("second-order");contract["quantity"]=17;contract["in_transit"]=12
	supply=Supply.project(contract,firm,BEFORE)
	assert(supply["known_batches"]==2 and supply["possible_quantity"]==4 and supply["late_quantity"]==4 and supply["unknown_quantity"]==4,"Separate child orders count once each, without applying the parent quantity again")

	# A timed arrival one minute after noon must not become midnight and pass.
	var timed_order: Dictionary={"id":"minute-boundary","quantity":3,"pending":0,"transit":3,"delivered":0,"shipments":[],"deliveries":[]}
	for offset: int in [-1,0,1]:
		var cargo: Dictionary=_cargo("minute-"+str(offset),1,10)
		cargo["arrival_minute"]=DEADLINE+offset
		timed_order["shipments"].append(cargo)
	timing=Timing.order_timing(timed_order,DEADLINE,BEFORE)
	assert(timing["possible"]==2 and timing["late"]==1,"Minute comparison must preserve deadline equality and reject one-minute lateness")
	text=Timing.order_timing_text(timed_order,original_contract,BEFORE)
	assert(text.contains("第11天 11:59") and text.contains("第11天 12:00") and text.contains("第11天 12:01"),"Display known timed bounds without flooring them to midnight")
	timing=Timing.order_timing(timed_order,DEADLINE,DEADLINE+1)
	assert(timing["possible"]==0 and timing["expired"]==2 and timing["late"]==1,"A past lower bound cannot keep an undelivered batch timely after the deadline")

	# A leg arrival is not unload completion, collection or stock handover.
	for stage: String in ["WAITING_UNLOAD","UNLOADING","AWAITING_RECIPIENT"]:
		var cargo: Dictionary=_cargo("node-"+stage,2,null,stage)
		cargo["arrival_minute"]=DEADLINE-1
		cargo["unloading_end_minute"]=DEADLINE+60
		var waiting: Dictionary=_single_order(cargo)
		timing=Timing.order_timing(waiting,DEADLINE,BEFORE)
		assert(timing["unknown"]==2 and timing["possible"]==0 and timing["late"]==0,"Null final ETA must remain unknown during "+stage)
		text=Timing.order_timing_text(waiting,original_contract,BEFORE)
		assert(text.contains("到仓时间未知") and text.contains("已知本段抵达下限"),"Show a known leg time separately from unknown final receipt")
	var bound_node: Dictionary=_cargo("bound-node",2,10)
	bound_node["arrival_minute"]=DEADLINE-1;bound_node["node_resources"]={"awaiting_unload":true}
	timing=Timing.order_timing(_single_order(bound_node),DEADLINE,BEFORE)
	assert(timing["unknown"]==2 and timing["possible"]==0,"Exposed node resources do not prove unload completion even before the node-wait stage")
	var null_eta: Dictionary=_cargo("null-final-eta",1,null)
	null_eta["arrival_minute"]=DEADLINE-1
	assert(Timing.order_timing(_single_order(null_eta),DEADLINE,BEFORE)["unknown"]==1,"An arrival_minute alone cannot replace a null final bound")
	var missing_physical: Dictionary=_cargo("partly-lost",3,10)
	missing_physical["physical_quantity"]=1
	timing=Timing.order_timing(_single_order(missing_physical),DEADLINE,BEFORE)
	assert(timing["possible"]==1 and timing["unknown"]==2,"Missing physical goods are not possible timely stock")

	# An unaccepted notice or undisclosed production date is not a player deadline.
	var unbound: Dictionary=_single_order(_cargo("unbound",2,11))
	unbound["need_by_day"]=0;unbound["npc_production_minute"]=1
	timing=Timing.order_timing(unbound,null,BEFORE)
	assert(timing["unbound"]==2 and timing["possible"]==0 and timing["late"]==0,"No accepted deadline means no timely/late verdict")
	var no_contract_text: String=Timing.order_timing_text(unbound,{},BEFORE)
	assert(no_contract_text.contains("未关联已接受供货合同截止") and not no_contract_text.contains("预计可能及时") and not no_contract_text.contains("最早也迟到"),"No-contract text must not adopt an NPC production date")
	unbound["need_by_day"]=999;unbound["npc_production_minute"]=999999
	assert(no_contract_text==Timing.order_timing_text(unbound,{},BEFORE),"Unrelated private date fields must not affect presentation")
	var recruiting: Dictionary=original_contract.duplicate(true)
	recruiting.erase("accept_action");recruiting["status"]="RECRUITING"
	assert(no_contract_text==Timing.order_timing_text(unbound,recruiting,BEFORE),"An unaccepted notice is not an accepted supply responsibility")

	# Actual receipts retain precise minute verdicts; old day-only records do not invent hours.
	var received: Dictionary={"id":"receipt-boundary","pending":0,"transit":0,"delivered":5,"shipments":[],"deliveries":[{"id":"at-deadline","quantity":2,"delivered_day":10,"delivered_minute":DEADLINE},{"id":"after-deadline","quantity":3,"delivered_day":10,"delivered_minute":DEADLINE+1}]}
	timing=Timing.order_timing(received,DEADLINE,DEADLINE+2)
	assert(timing["received"]==5 and _classified(timing)==0 and timing["rows"].size()==2,"Received quantity is counted only from actual delivery rows")
	text=Timing.order_timing_text(received,original_contract,DEADLINE+2)
	assert(text.contains("已实际收到 ×2 · 第11天 12:00；按时验收") and text.contains("已实际收到 ×3 · 第11天 12:01；迟到验收"),"Actual receipt at deadline is on time; one minute later is late")
	var legacy: Dictionary={"id":"legacy","pending":0,"transit":0,"delivered":4,"shipments":[],"deliveries":[{"id":"day-only","quantity":2,"delivered_day":9}]}
	timing=Timing.order_timing(legacy,DEADLINE,BEFORE)
	assert(timing["received"]==4 and timing["rows"].size()==2,"A legacy receipt and missing-detail remainder count once each")
	text=Timing.order_timing_text(legacy,original_contract,BEFORE)
	assert(text.contains("第10天（旧记录无时分）") and text.contains("实收时间未知（原订单累计）"),"Legacy history preserves unknown time precision")
	assert(not text.contains("00:00") and not text.contains("按时验收"),"Do not manufacture minute precision or receipt verdicts for legacy unknown times")
	var pending_only: Dictionary={"id":"pending-only","pending":3,"transit":0,"delivered":0,"earliest_arrival_day":11}
	timing=Timing.order_timing(pending_only,DEADLINE,BEFORE)
	assert(timing["unknown"]==3 and timing["late"]==0,"The whole-order ETA cannot time unallocated pending quantities")
	assert(order==original and original_contract=={"id":"own-supply","accept_action":"accepted","quantity":16,"ontime":5,"late":0,"in_transit":11,"batches":["mixed"],"status":"PARTIAL","price":5,"paid":25,"deadline":DEADLINE,"unallocated":0,"free_stock":0,"secured_unallocated":0},"All projection calls leave original data intact")
	print("QA_TIME_AWARE_UI_PASS fixture_only mixed_batches actual_receipts deduplicated_orders minute_deadline node_unknown no_private_deadline pure_repeat legacy_unknown")
	quit()

extends SceneTree
const P=preload("res://merchant/merchant_supply_projection.gd")
func _initialize() -> void:
	var c: Dictionary={"quantity":80,"ontime":77,"late":0,"in_transit":3,"batches":["last"],"status":"OVERDUE","price":5,"paid":385,"deadline":14400,"unallocated":0,"free_stock":0,"secured_unallocated":0}
	var f: Dictionary={"orders":[],"sales_orders":[{"id":"last","pending":3,"transit":0,"earliest_arrival_day":11}]}
	var before: Dictionary=c.duplicate(true)
	var a: Dictionary=P.project(c,f,14401)
	assert(a["pending"]==3 and a["transit"]==0 and a["not_received"]==3 and a["late_risk"].is_empty() and a["unknown_quantity"]==3)
	assert(c==before and a==P.project(c,f,14401))
	f["orders"]=f["sales_orders"].duplicate(true)
	assert(P.project(c,f,14401)["pending"]==3)
	c["late"]=3;c["in_transit"]=0;f["sales_orders"][0]["pending"]=0;f["orders"]=[]
	a=P.project(c,f,16000);assert(a["not_received"]==0 and a["not_on_time"]==3)
	assert(not P.project(c,{},16000)["complete_order_visibility"])
	assert(P.project({},f,0).is_empty())
	assert(a["possible_quantity"]==0 and a["late_quantity"]==0 and a["unknown_quantity"]==0)
	assert("合同已结束" in a["action_reason"])
	var waiting: Dictionary={"quantity":80,"status":"ACCEPTED","supplier_site":"own","good":"grain","deadline":14400,"unallocated":80,"free_stock":0,"batches":[]}
	var inbound: Dictionary={"orders":[{"id":"purchase","buyer_site":"own","good":"grain","pending":2,"transit":1}]}
	assert(P.project(waiting,inbound,4321)["incoming_purchase"]==3)
	assert(P.project(waiting,inbound,4321)["next_tab"]==2)
	waiting["free_stock"]=1;waiting["new_batch_earliest_day"]=11
	var late: Dictionary=P.project(waiting,{},12961)
	assert(late["new_batch_late"] and "第12天" in late["risk"] and "第11天" in late["risk"])
	waiting["new_batch_earliest_day"]=null
	assert(not P.project(waiting,{},12961)["new_batch_late"])
	print("PROJECTION_PASS pending_vs_transit deduplicate late_vs_remaining pure_repeat missing_unknown")
	quit()

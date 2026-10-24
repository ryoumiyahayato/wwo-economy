extends RefCounted
## Presentation only. Input is the manager-gated supply view plus authorized own orders.
## Never receives WorldState, private NPC accounts, or mutable economic objects.
const Timing=preload("res://merchant/merchant_decision_projection.gd")
static func project(contract: Dictionary, firm: Dictionary, minute: int) -> Dictionary:
	if contract.is_empty():return {}
	var result: Dictionary={"pending":0,"transit":0,"known_batches":0,"missing_batches":[],"late_risk":[],"possible_quantity":0,"late_quantity":0,"unknown_quantity":0,"expired_quantity":0,"next_tab":6,"next_action":"查看供货公告","risk":"到达日是下限，不是保证。","acceptance_queue":"原业务到货即验收，无独立待验收队列"}
	var arrival_days: Array[int]=[]
	var orders: Dictionary={}
	for order: Dictionary in firm.get("orders",[])+firm.get("sales_orders",[]):orders[str(order.get("id",""))]=order
	var incoming_purchase: int=0
	for order: Dictionary in orders.values():
		if contract.has("supplier_site") and contract.has("good") and order.get("buyer_site")==contract.get("supplier_site") and order.get("good")==contract.get("good"):
			incoming_purchase+=int(order.get("pending",0))+int(order.get("transit",0))
	result["incoming_purchase"]=incoming_purchase
	for id: String in contract.get("batches",[]):
		if not orders.has(id):result["missing_batches"].append(id);continue
		var order: Dictionary=orders[id]
		result["known_batches"]+=1
		result["pending"]+=int(order.get("pending",0));result["transit"]+=int(order.get("transit",0))
		var timing: Dictionary=Timing.order_timing(order,contract.get("deadline"),minute)
		for field: String in ["possible","late","unknown","expired"]:result[field+"_quantity"]+=int(timing[field])
		result["unknown_quantity"]+=int(timing["unbound"])
		for date: int in timing["arrival_days"]:arrival_days.append(date)
		for cargo: Dictionary in timing["rows"]:
			if cargo.get("state")=="late" and int(cargo.get("physical",0))>0:result["late_risk"].append({"id":id,"earliest_day":cargo["earliest"],"quantity":cargo["physical"]})
	result["complete_order_visibility"]=result["missing_batches"].is_empty()
	result["not_received"]=maxi(0,int(contract.get("quantity",0))-int(contract.get("ontime",0))-int(contract.get("late",0)))
	result["not_on_time"]=maxi(0,int(contract.get("quantity",0))-int(contract.get("ontime",0)))
	result["unallocated_cash_security"]=contract.get("secured_unallocated",null)
	result["batch_unpaid_amount"]=int(contract.get("in_transit",0))*int(contract.get("price",0))
	var status: String=str(contract.get("status",""))
	if status in ["COMPLETED","OVERDUE","TERMINATED"]:
		result["next_tab"]=2;result["next_action"]="查看旧批次履约与账款"
	elif status in ["ACCEPTED","PARTIAL"]:
		if int(contract.get("free_stock",0))>0 and int(contract.get("unallocated",0))>0:
			result["next_action"]="核对可交现货，预览分批供货"
		elif incoming_purchase>0:
			result["next_tab"]=2;result["next_action"]="查看已受理采购，等待真实到仓"
		elif int(contract.get("unallocated",0))>0:
			result["next_tab"]=0;result["next_action"]="查看已知采购机会和待入库"
		else:
			result["next_tab"]=2;result["next_action"]="查看已安排货运，等待正式到货"
	if not result["late_risk"].is_empty():result["risk"]="已有货批%s件最早也迟到；其余数量分批判断，旧运输继续。"%result["late_quantity"]
	elif minute>int(contract.get("deadline",0)):result["risk"]="截止已过；历史收款保留，旧运输继续。"
	elif int(result["unknown_quantity"])>0:result["risk"]="未到货中%s件时间未知；不能推定及时，也不据此重复采购。"%result["unknown_quantity"]
	elif int(contract.get("deadline",0))-minute<=2880:result["risk"]="临近截止：现货仍须本地货运；不能把提交当验收。"
	if not result["complete_order_visibility"]:result["risk"]="部分批次查询缺失；分阶段数量未知，不能推定已交付。"
	var remaining: int=maxi(0,int(contract.get("deadline",0))-minute)
	result["arrival_summary"]="分批未到：预计可能及时%s / 最早也迟到%s / 时间未知%s；下限非保证。"%[result["possible_quantity"],result["late_quantity"],result["unknown_quantity"]]
	if int(result["expired_quantity"])>0:result["arrival_summary"]+="截止已过仍未收到%s件。"%result["expired_quantity"]
	if not arrival_days.is_empty():result["arrival_summary"]+="已知货批下限第%d–%d天；逐批见货站。"%[arrival_days.min()+1,arrival_days.max()+1]
	if not result["complete_order_visibility"]:result["arrival_summary"]+="另有批次资料缺失，数量与时间未知。"
	result["action_reason"]="余%d日%d时；可交%s，待到仓%s，未安排%s。现货仍须货运。"%[remaining/1440,(remaining/60)%24,contract.get("free_stock",0),incoming_purchase,contract.get("unallocated",0)]
	if status in ["COMPLETED","OVERDUE","TERMINATED"]:result["action_reason"]="合同已结束，核对旧批次与实际到账%s；不再提交新货。"%contract.get("paid",0)
	result["new_batch_late"]=false
	if status in ["ACCEPTED","PARTIAL"] and int(contract.get("free_stock",0))>0 and int(contract.get("unallocated",0))>0 and contract.get("new_batch_earliest_day")!=null:
		var earliest: int=int(contract["new_batch_earliest_day"])
		result["new_batch_late"]=earliest*1440>int(contract.get("deadline",0))
		result["new_batch_hint"]="现在提交，单件无排队到达下限第%d天；非保证。"%(earliest+1)
		if result["new_batch_late"]:
			result["risk"]="警告：现货现在提交，最早第%d天也晚于第%d天截止，无法计为按时。"%[earliest+1,int(contract.get("deadline",0))/1440+1]
			result["next_action"]="现货最早也迟到，核对后再提交"
			result["action_reason"]=result["risk"]
	else:result["new_batch_hint"]="新提交批次到达下限未知；受理后检查货站。"
	result["short_risk"]=str(result["risk"])+(" 还需采购或等待到仓。" if int(contract.get("free_stock",0))<int(contract.get("unallocated",contract.get("quantity",0))) else "")
	if status in ["COMPLETED","OVERDUE","TERMINATED"]:
		result["short_risk"]="合同%s；已按时交付%s，迟到%s，实际到账%s。旧批次如仍在途继续履约，不再安排新货。"%[{"COMPLETED":"已完成","OVERDUE":"已逾期","TERMINATED":"已终止"}[status],contract.get("ontime",0),contract.get("late",0),contract.get("paid",0)]
	elif status!="RECRUITING" and not contract.has("accept_action"):
		result["short_risk"]="这项机会当前不能接受；查看其他已知机会或等待更新。"
		result["next_tab"]=0;result["next_action"]="查看其他已知贸易机会"
	return result

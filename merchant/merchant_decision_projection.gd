extends RefCounted
## Presentation only. Inputs are detached authorized Formal projections.
## Unknown values stay unknown; no orders, money or listings are created here.
const GOODS={"grain":"粮食","beans":"豆类","fiber":"纤维","oil":"油料","bread":"面包","clothes":"衣物","soap":"肥皂"}

static func known(value: Variant) -> String:
	return "未知" if value==null else str(value)

static func day_text(minute: Variant) -> String:
	return "未知" if minute==null or int(minute)<0 else "第%d天 %02d:%02d"%[int(minute)/1440+1,(int(minute)/60)%24,int(minute)%60]

static func sales_state_text(listing: Dictionary) -> String:
	if not listing.get("sales_control_supported",false):return "新销售状态资料不足"
	return "已暂停该商品新销售" if listing.get("sales_paused",false) else "该商品新销售开放（仍须有效报价及权限）"

static func listing_text(listing: Dictionary) -> String:
	if listing.is_empty():return "本仓挂牌资料不足，不能把其他商号售价当作自己的销售收入。"
	var text: String=sales_state_text(listing)
	if listing.get("sales_paused",false):text+="；库存仍在，旧订单、原供货责任继续。"
	text+="\n本仓当前报价：单价%s；%s；有效至%s。"%[known(listing.get("price")),"可接受新销售" if listing.get("active",false) else "当前不可接受新销售",day_text(listing.get("expires_minute"))]
	var future: Array=listing.get("future_quotes",[])
	if future.is_empty():text+="\n尚无已提交的未来报价。"
	else:
		for quote: Dictionary in future:text+="\n已提交未来价%s，%s生效；调价不自动恢复新销售。"%[known(quote.get("price")),day_text(quote.get("effective_minute"))]
	text+="\n实际在库%s / 自由库存%s / 正式订单已占用%s。"%[known(listing.get("stock_quantity")),known(listing.get("free_quantity")),known(listing.get("reserved_quantity"))]
	var locked: Array=listing.get("locked_sales",[])
	text+="\n旧销售/供货责任：%s条已关联记录；原锁价、运输与付款继续。"%locked.size() if listing.has("locked_sales") else "\n旧销售合同沿原规则履约；详细责任见货站与买方。"
	for contract: Dictionary in locked.slice(0,3):text+="\n旧合同锁价%s / 未结%s件（仅原责任）。"%[known(contract.get("price")),known(contract.get("remaining",contract.get("remaining_quantity")))]
	text+="\n开放后自由货可能被真实NPC按有效报价采购；挂牌不保证成交。"
	text+="\n补货委托只管未来补货，关闭委托不暂停新销售。调价次日生效、同仓商品每天最多一次，原合同锁价不变。"
	return text

static func purchase_summary_text(offer: Dictionary, destination_name: String, supplier_name: String) -> String:
	var c: Dictionary=offer.get("comparison",{})
	var listing: Dictionary=c.get("own_listing",{})
	var lines: Array[String]=["%s · 来源%s → %s"%[GOODS.get(offer.get("good"),str(offer.get("good","商品"))),supplier_name,destination_name]]
	lines.append("申请%s件 / 当前可受理%s件（提交时复核）"%[known(c.get("requested_quantity",offer.get("request",{}).get("quantity"))),known(c.get("acceptable_quantity"))])
	lines.append("最高现金承诺%s = 货款%s + 入库运费%s"%[known(c.get("maximum_cash_commitment")),known(c.get("goods_commitment")),known(c.get("inbound_freight_commitment"))])
	lines.append("每件货价%s + 运费%s；报价有效至%s"%[known(c.get("supplier_price",offer.get("price"))),known(offer.get("freight_per_unit")),day_text(offer.get("expires_minute",offer.get("quote_expires_minute")))])
	lines.append("到仓下限%s（非保证）；%s"%[("第%d天"%(int(offer["earliest_arrival_day"])+1)) if offer.get("earliest_arrival_day")!=null else "未知",sales_state_text(listing)])
	var scenario: Dictionary=c.get("scenario",{})
	var risk: String="没有真实买方承诺，不保证售出；库存会占用现金。"
	if listing.get("sales_paused",false):risk="这批货到仓后仍暂停新销售；原合同若已承诺仍须履行。"
	elif scenario.get("known",false) and int(scenario.get("known_cash_difference",0))<0:risk="即使按当前价售出，已知收支差额%s，仍覆盖不了采购与入库运费。"%known(scenario.get("known_cash_difference"))
	elif c.get("maximum_cash_commitment")==null:risk="采购或入库费用未完全可知，不能核定总成本。"
	lines.append("关键风险："+risk)
	var onward: Dictionary=c.get("onward_delivery",{})
	lines.append("后续配送费用："+(known(onward.get("amount"))+"（仅对应已知责任）" if onward.get("known",false) else "未知，未计入；无新货保底回款。"))
	return "\n".join(lines)

static func purchase_text(offer: Dictionary, destination_name: String, supplier_name: String) -> String:
	var c: Dictionary=offer.get("comparison",{})
	var good: String=GOODS.get(offer.get("good"),str(offer.get("good","商品")))
	var lines: Array[String]=["%s · 从%s采购 → %s"%[good,supplier_name,destination_name]]
	lines.append("申请%s件；当前该来源可受理%s件（以正式提交复核为准）。"%[known(c.get("requested_quantity",offer.get("request",{}).get("quantity"))),known(c.get("acceptable_quantity"))])
	lines.append("供应商采购单价%s；入库运费每件%s。"%[known(c.get("supplier_price",offer.get("price"))),known(offer.get("freight_per_unit"))])
	lines.append("本次商品价款%s + 已知入库运费%s = 当前最高现金承诺%s。"%[known(c.get("goods_commitment")),known(c.get("inbound_freight_commitment")),known(c.get("maximum_cash_commitment"))])
	lines.append("当前路径到仓下限%s（非保证）；实际接续、容量与收货仍以货运记录为准。"%arrival_day_text(offer.get("earliest_arrival_day")))
	var scenario: Dictionary=c.get("scenario",{})
	if scenario.get("known",false):
		lines.append("按当前条件的收支估算：若确实按当前自家挂牌售出，销售款%s − 已知采购及入库运费%s = %s。"%[known(scenario.get("sales_amount")),known(c.get("maximum_cash_commitment")),known(scenario.get("known_cash_difference"))])
		if int(scenario.get("known_cash_difference",0))<0:lines.append("警告：这种售价连已知采购与入库运费也不能覆盖。仍可自愿承担，不强制禁止。")
	else:lines.append("销售金额或费用口径不足，收支估算未知。")
	lines.append("仅此货源与路径，未把少量低价货扩算成全部需求；实际受理可能随资金、库存、运力变化。")
	lines.append(listing_text(c.get("own_listing",{})))
	var contracts: Array=c.get("locked_sales_contracts",[])
	if contracts.is_empty():lines.append("没有已接受买方合同为这次新货保证锁价收购。")
	else:
		lines.append("已存在销售锁价合同（只覆盖原合同责任，不自动承诺新采购）：")
		for contract: Dictionary in contracts:lines.append("锁价%s，未结%s件；合同%s。"%[known(contract.get("price")),known(contract.get("remaining",contract.get("remaining_quantity",contract.get("quantity")))),contract.get("order_id",contract.get("id","已知合同"))])
	var onward: Dictionary=c.get("onward_delivery",{})
	lines.append("后续配送费用："+(known(onward.get("amount"))+"（仅对应已知责任）" if onward.get("known",false) else "未知，未计入收支估算；未受理销售也不保证买方路线与费用条件。"))
	lines.append("这不是成交预测或完整净利润。可以取消不买、减少数量、选另一条页面中真实可用的来源，或等待；可去仓库依法调整未来挂牌。")
	return "\n".join(lines)

static func order_receipts_text(order_id: String, review: Dictionary) -> String:
	for row: Dictionary in review.get("order_rows",[]):
		if row.get("order_id")!=order_id:continue
		var lines: Array[String]=["原Ledger实际收支（本订单，不套用全部历史）："]
		for field: String in ["goods_paid","freight_paid","sales_received"]:
			var amounts: Dictionary=row.get(field,{})
			var parts: Array[String]=[]
			for currency: String in amounts:parts.append(str(amounts[currency])+" "+currency.replace("denomination:formal_simulation_minor_v1","记账单位"))
			lines.append({"goods_paid":"实际采购货款","freight_paid":"实际运费","sales_received":"实际销售到账"}[field]+"："+(" / ".join(parts) if not parts.is_empty() else "无已关联付款"))
		lines.append("收据："+str(row.get("receipt_ids",[])))
		lines.append("付款引用："+str(row.get("payment_ids",[])))
		lines.append("混合来源或库存成本未准确分配，不据此伪造逐件利润。")
		return "\n".join(lines)
	return "本订单尚无可核验到账记录。"

static func arrival_day_text(day: Variant) -> String:
	return "时间未知" if day==null or int(day)<0 else "第%d天"%(int(day)+1)

static func _arrival_status(earliest_minute: Variant, deadline: Variant, minute: int) -> String:
	if earliest_minute==null or int(earliest_minute)<0:return "unknown"
	if deadline==null:return "unbound"
	if int(earliest_minute)>int(deadline):return "late"
	# A lower bound in the past cannot prove an undelivered batch can still meet a past deadline.
	if minute>int(deadline):return "expired"
	return "possible"

static func order_timing(order: Dictionary, deadline: Variant=null, minute: int=-1) -> Dictionary:
	# Read only each shipment's lower bound. Never apply the whole-order maximum ETA
	# to all units, and never borrow an NPC's undisclosed production boundary.
	var result: Dictionary={"rows":[],"possible":0,"late":0,"unknown":0,"unbound":0,"expired":0,"received":0,"arrival_days":[],"deadline":deadline}
	var traced_transit: int=0
	for cargo: Dictionary in order.get("shipments",[]):
		if cargo.get("stage")=="DELIVERED":continue # Actual receipts/own delivered total below are the single source.
		var q: int=maxi(0,int(cargo.get("quantity",0)))
		if q==0:continue
		traced_transit+=q
		var physical: int=clampi(int(cargo.get("physical_quantity",q)),0,q)
		var earliest: Variant=cargo.get("earliest_arrival_day")
		var leg_arrival: Variant=cargo.get("arrival_minute")
		var lower_minute: Variant=int(earliest)*1440 if earliest!=null and int(earliest)>=0 else null
		# Timed entry at noon is not midnight. A known leg arrival is still not
		# unloading completion: preserve null and node-wait stages as unknown.
		if cargo.get("stage") in ["WAITING_UNLOAD","UNLOADING","AWAITING_RECIPIENT"] or cargo.has("node_resources"):lower_minute=null
		elif lower_minute!=null and leg_arrival!=null and int(leg_arrival)>=0:lower_minute=maxi(int(lower_minute),int(leg_arrival))
		var state: String=_arrival_status(lower_minute,deadline,minute)
		result[state]+=physical;result["unknown"]+=q-physical
		if lower_minute!=null and physical>0:result["arrival_days"].append(int(lower_minute)/1440)
		var waiting_reason: String=str(cargo.get("arrival_blocked_reason",""))
		if waiting_reason.is_empty():waiting_reason=str(cargo.get("waiting_reason",""))
		result["rows"].append({"kind":"shipment","quantity":q,"physical":physical,"stage":cargo.get("stage",""),"earliest":int(lower_minute)/1440 if lower_minute!=null else null,"state":state,"waiting_reason":waiting_reason,"minute":lower_minute,"leg_arrival_minute":leg_arrival,"bound_has_time":leg_arrival!=null and lower_minute!=null and int(leg_arrival)==int(lower_minute)})
	var pending: int=maxi(0,int(order.get("pending",0)))
	if pending>0:
		result["unknown"]+=pending
		result["rows"].append({"kind":"pending","quantity":pending,"minute":null})
	var untraced: int=maxi(0,int(order.get("transit",0))-traced_transit)
	if untraced>0:
		result["unknown"]+=untraced
		result["rows"].append({"kind":"untraced","quantity":untraced,"minute":null})
	for receipt: Dictionary in order.get("deliveries",[]):
		var q: int=maxi(0,int(receipt.get("quantity",0)))
		if q==0:continue
		var actual: Variant=receipt.get("delivered_minute")
		var date: Variant=receipt.get("delivered_day")
		if actual==null and date!=null:actual=int(date)*1440
		result["received"]+=q
		result["rows"].append({"kind":"received","quantity":q,"minute":actual,"day_only":not receipt.has("delivered_minute")})
	var untraced_received: int=maxi(0,int(order.get("delivered",0))-int(result["received"]))
	if untraced_received>0:
		result["received"]+=untraced_received
		result["rows"].append({"kind":"received","quantity":untraced_received,"minute":null,"day_only":true})
	result["rows"].sort_custom(func(a: Dictionary,b: Dictionary)->bool:
		if a.get("minute")==null:return false
		if b.get("minute")==null:return true
		return int(a["minute"])<int(b["minute"]))
	return result

static func order_timing_text(order: Dictionary, contract: Dictionary={}, minute: int=-1) -> String:
	var deadline: Variant=contract.get("deadline") if contract.has("accept_action") else null
	var timing: Dictionary=order_timing(order,deadline,minute)
	var lines: Array[String]=["分批时序 · 到达下限不是保证，实际收到才计入到仓"]
	lines.append("关联供货合同截止："+day_text(deadline) if deadline!=null else "未关联已接受供货合同截止；不以买方内部生产日判断及时性。")
	lines.append("原订单累计已实际收到%s件；当前待发%s / 在途%s。"%[timing["received"],order.get("pending",0),order.get("transit",0)])
	if deadline!=null:
		lines.append("尚未收到：预计可能及时%s / 最早也迟到%s / 时间未知%s%s"%[timing["possible"],timing["late"],timing["unknown"]," / 截止已过%s"%timing["expired"] if int(timing["expired"])>0 else ""])
	var rows: Array=timing["rows"]
	for i: int in range(mini(rows.size(),8)):
		var row: Dictionary=rows[i]
		var q: int=int(row["quantity"])
		if row["kind"]=="received":
			var when: String="实收时间未知（原订单累计）" if row["minute"]==null else arrival_day_text(int(row["minute"])/1440)+"（旧记录无时分）" if row["day_only"] else day_text(row["minute"])
			var verdict: String=""
			if deadline!=null and row["minute"]!=null and not row["day_only"]:verdict="；按时验收" if int(row["minute"])<=int(deadline) else "；迟到验收"
			lines.append("已实际收到 ×%s · %s%s"%[q,when,verdict]);continue
		if row["kind"]=="pending":lines.append("待发责任 ×%s · 尚未实际收到；时间未知（尚无逐批日期）"%q);continue
		if row["kind"]=="untraced":lines.append("在途责任 ×%s · 时间未知（逐批资料不足）"%q);continue
		var stage: String={"TRANSIT":"运输中","WAITING":"等待接续","LOADING":"装货中","WAITING_UNLOAD":"等待卸货","UNLOADING":"卸货中","AWAITING_RECIPIENT":"等待收货人领取"}.get(str(row["stage"]),"货运处理中")
		var state: String={"possible":"预计可能及时（非保证）","late":"最早也迟到","unknown":"时间未知","unbound":"未绑定截止","expired":"截止已过，尚未收到"}[row["state"]]
		var cargo_text: String="有货但未到" if int(row["physical"])>0 else "实货缺失待处理"
		var arrival: String="到仓时间未知" if row["minute"]==null else "最早"+day_text(row["minute"]) if row.get("bound_has_time",false) else "最早"+arrival_day_text(row["earliest"])
		lines.append("货批 ×%s · %s / %s · %s；%s%s"%[q,cargo_text,stage,arrival,state,"；其中实货缺失%s，不能算作可到货"%(q-int(row["physical"])) if int(row["physical"])<q else ""])
		if row.get("leg_arrival_minute")!=null and not row.get("bound_has_time",false):lines.append("  已知本段抵达下限"+day_text(row["leg_arrival_minute"])+"；卸货、接续与最终实收须另核对。")
		var wait_text: String={"EXPLICIT_OWNER_COLLECTION_REQUIRED":"需收货人按原规则领取","HOST_CONNECTION_UNAVAILABLE":"运输连接当前不可用","FUTURE_HOST_ENTRY_ALLOCATION_REQUIRED":"等待实际运输窗口分配","WAITING_EXPLICIT_HOST_ENTRY_WINDOW":"等待实际运输窗口","EDGE_CLOSED":"线路当前关闭","BATCH_EXCEEDS_ACTIVE_CAPACITY":"该批超过当前线路运力","EDGE_CAPACITY":"等待线路运力","NODE_CAPACITY":"等待货站处理能力","NOT_READY":"尚未到约定发运日"}.get(str(row.get("waiting_reason","")),"")
		if not wait_text.is_empty():lines.append("  "+wait_text+"；旧责任保留。")
	if rows.size()>8:lines.append("另有%s条批次记录；完整原记录见技术详情。"%(rows.size()-8))
	if rows.is_empty():lines.append("当前没有待发、在途或已收到的货物记录。")
	lines.append("阶段仅示意；等待、排队或新阻塞仍可推迟到货。撤销只影响合法未发部分。")
	return "\n".join(lines)

extends RefCounted
## Player instructions select future orders; all rights, stock and settlement stay in R1.
const Opening=preload("res://merchant/merchant_opening.gd")
var state: Dictionary={"version":1,"plans":{},"sequence":0,"journal":[]}

func edit(world: WorldState, payload: Dictionary) -> Dictionary:
	if not FormalLedgerState.exact_fields(payload,["site","good","target","batch","ceiling","floor","enabled"]):return {"accepted":false,"reason":"INVALID_PLAN"}
	if not payload["enabled"] is bool or not payload["site"] is String or payload.get("good") not in Opening.TRADE_GOODS:return {"accepted":false,"reason":"INVALID_PLAN"}
	for key: String in ["target","batch","ceiling","floor"]:
		if not FormalLedgerState.valid_amount(payload[key]) or int(payload[key])>99999:return {"accepted":false,"reason":"INVALID_PLAN_LIMIT"}
	if int(payload["batch"])<1 or int(payload["target"])<1 or int(payload["ceiling"])<1:return {"accepted":false,"reason":"INVALID_PLAN_LIMIT"}
	var business: Dictionary=world.economy_r1.business_view(world.player_state.player_id(),Opening.FIRM,payload["site"],1,0,1)
	if business.is_empty():return {"accepted":false,"reason":"NO_FIRM_AUTHORITY"}
	var key: String=payload["site"]+"|"+payload["good"]
	var old: Dictionary=state["plans"].get(key,{})
	var plan: Dictionary=payload.duplicate(true)
	plan["next_day"]=maxi(int(old.get("next_day",0)),world.economy_r1.day+1)
	plan["last_action"]=old.get("last_action","");plan["last_minute"]=old.get("last_minute",-1)
	plan["status"]="从下一日开始复核" if plan["enabled"] else "已暂停；既有合同照常履行"
	state["plans"][key]=plan
	return {"accepted":true,"reason":"PLAN_SAVED","next_day":plan["next_day"]}

func review(world: WorldState) -> bool:
	var changed: bool=false
	for key: String in state["plans"]:
		var p: Dictionary=state["plans"][key]
		if not p["enabled"] or world.economy_r1.day<int(p["next_day"]):continue
		changed=true;p["next_day"]=world.economy_r1.day+1
		var person: String=world.player_state.player_id()
		var business: Dictionary=world.economy_r1.business_view(person,Opening.FIRM,p["site"],1,0,16)
		if business.is_empty():p["status"]="无当前经营权限";continue
		var site: Dictionary=business["site"]
		var cover: int=int(site.get("free_inventory",{}).get(p["good"],0))+int(site.get("incoming",{}).get(p["good"],0))
		var need: int=mini(int(p["batch"]),maxi(0,int(p["target"])-cover))
		if need==0:p["status"]="自由库存＋已承诺入库已达目标";continue
		var offers: Array[Dictionary]=[]
		var total: int=int(business.get("offer_total",0))
		# Finite known candidate pages only; never inspect unknown market orders.
		for offset: int in range(0,total,16):
			var page: Dictionary=business if offset==0 else world.economy_r1.business_view(person,Opening.FIRM,p["site"],1,offset,16)
			for offer: Dictionary in page.get("offers",[]):
				if offer.get("good")!=p["good"] or not offer.get("can_order",false) or offer.get("denomination")!=FormalLedgerState.DENOMINATION:continue
				var landed: int=int(offer["price"])+int(offer["freight_per_unit"])
				if landed>int(p["ceiling"]):continue
				offers.append(offer)
		offers.sort_custom(func(a: Dictionary,b: Dictionary)->bool:
			var ca: int=int(a["price"])+int(a["freight_per_unit"]);var cb: int=int(b["price"])+int(b["freight_per_unit"])
			return ca<cb if ca!=cb else str(a["quote_id"])<str(b["quote_id"]))
		p["status"]="没有预算内的已知可执行报价"
		for offer: Dictionary in offers:
			var finance: Dictionary=business["finance"]
			var cash: Dictionary=finance.get("account_cash",{}).get(FormalLedgerState.DENOMINATION,{})
			var position: Dictionary=finance.get("procurement_cash",{}).get(FormalLedgerState.DENOMINATION,{})
			# Use the original due query. available already excludes reservations;
			# stock costs, future rent and future sales are not today's payment.
			var protection: int=maxi(int(p["floor"]),int(position.get("protected",0)))
			var available: int=maxi(0,int(cash.get("available",0))-protection)
			var landed: int=int(offer["price"])+int(offer["freight_per_unit"])
			var quantity: int=mini(need,int(offer["quantity"]))
			if landed>0:quantity=mini(quantity,available/landed)
			if quantity<1:p["status"]="扣除预留与留存现金后不足";continue
			var payload: Dictionary=offer["request"].duplicate(true);payload["quantity"]=quantity
			var action: String=world.economy_r1.next_person_action_id()
			var minute: int=world.game_clock.total_minutes()
			var result: Dictionary=LivelihoodAction.execute(world,person,{"action_id":action,"minute":minute,"kind":"buy","payload":payload})
			if not world.economy_r1._commands.has(action):
				p["status"]="正式行动未入账："+str(result.get("reason",""));break
			state["sequence"]=int(state["sequence"])+1
			p["last_action"]=action;p["last_minute"]=minute
			p["status"]=("已提交采购：" if result.get("accepted",false) else "采购被正式系统拒绝：")+str(result.get("reason",""))
			state["journal"].append({"sequence":state["sequence"],"plan":key,"action":action,"minute":minute,"accepted":result.get("accepted",false)})
			while state["journal"].size()>32:state["journal"].pop_front()
			break # One attempt per plan/day, including rejected formal commands.
	return changed

static func validate(value: Variant, snapshot: Dictionary) -> String:
	if not value is Dictionary or not FormalLedgerState.exact_fields(value,["version","plans","sequence","journal"]) or value.get("version")!=1 or not value.get("plans") is Dictionary or not value.get("journal") is Array:return "委托格式无效"
	if value["plans"].size()>14 or value["journal"].size()>32 or not FormalLedgerState.valid_amount(value["sequence"]):return "委托数量或序号无效"
	if not snapshot.get("economy_native") is Dictionary or not snapshot.get("player") is Dictionary or not FormalLedgerState.valid_amount(snapshot.get("total_minutes")):return "核心封套缺少委托引用字段"
	var native: Dictionary=snapshot["economy_native"]
	if not native.get("commands") is Dictionary or not native.get("config") is Dictionary or not FormalLedgerState.valid_amount(native.get("day")):return "核心行动或配置字段无效"
	if not native["config"].get("firms") is Array:return "核心企业列表无效"
	for entry: Variant in native["commands"].values():
		if not entry is Dictionary or not entry.get("envelope") is Dictionary or not entry.get("result") is Dictionary:return "核心行动封套字段无效"
		if not entry["envelope"].get("command") is Dictionary or not entry["envelope"]["command"].get("payload") is Dictionary:return "核心行动载荷字段无效"
	var commands: Dictionary=native.get("commands",{})
	var sites: Dictionary={}
	for firm: Variant in native["config"]["firms"]:
		if not firm is Dictionary or not firm.get("id") is String or not firm.get("sites") is Array:return "核心企业结构无效"
		if firm["id"]==Opening.FIRM:
			for site: Variant in firm["sites"]:
				if not site is Dictionary or not site.get("id") is String:return "核心地点结构无效"
				sites[site["id"]]=true
	for key: Variant in value["plans"]:
		var p: Variant=value["plans"][key]
		if not p is Dictionary or not FormalLedgerState.exact_fields(p,["site","good","target","batch","ceiling","floor","enabled","next_day","last_action","last_minute","status"]):return "委托字段无效"
		if not sites.has(p["site"]) or p["good"] not in Opening.TRADE_GOODS or key!=str(p["site"])+"|"+str(p["good"]) or not p["enabled"] is bool or not p["status"] is String:return "委托身份无效"
		for n: String in ["target","batch","ceiling","floor","next_day"]:
			if not FormalLedgerState.valid_amount(p[n]):return "委托数值无效"
		if p["target"]<1 or p["batch"]<1 or p["ceiling"]<1 or p["target"]>99999 or p["batch"]>99999 or p["ceiling"]>99999 or p["floor"]>99999 or not p["last_action"] is String or typeof(p["last_minute"])!=TYPE_INT:return "委托限制无效"
		if p["enabled"] and int(p["next_day"])<=int(native.get("day",0)):return "委托复核游标落后于世界"
		if int(p["last_minute"])>int(snapshot["total_minutes"]):return "委托提交时间晚于世界"
		if not str(p["last_action"]).is_empty():
			var envelope: Dictionary=commands.get(p["last_action"],{}).get("envelope",{})
			var cmd: Dictionary=envelope.get("command",{})
			if envelope.get("actor")!=snapshot.get("player",{}).get("player_id") or cmd.get("payload",{}).get("firm")!=Opening.FIRM or int(p["next_day"])<=int(p["last_minute"])/1440:return "委托行动主体或游标无效"
			if cmd.get("kind")!="buy" or cmd.get("minute")!=p["last_minute"] or cmd.get("payload",{}).get("buyer_site")!=p["site"] or cmd.get("payload",{}).get("good")!=p["good"]:return "委托与正式行动不一致"
	var previous: int=0
	var actions: Dictionary={}
	var latest: Dictionary={}
	for row: Variant in value["journal"]:
		if not row is Dictionary or not FormalLedgerState.exact_fields(row,["sequence","plan","action","minute","accepted"]):return "委托日志格式无效"
		if not value["plans"].has(row["plan"]) or int(row["sequence"])<=previous or int(row["sequence"])>int(value["sequence"]):return "委托日志次序无效"
		if not row["action"] is String or not row["accepted"] is bool or not FormalLedgerState.valid_amount(row["minute"]) or not FormalLedgerState.valid_amount(row["sequence"]) or actions.has(row["action"]):return "委托日志字段或重复行动无效"
		actions[row["action"]]=true
		var entry: Dictionary=commands.get(row["action"],{})
		var envelope: Dictionary=entry.get("envelope",{})
		var cmd: Dictionary=envelope.get("command",{})
		var p: Dictionary=value["plans"][row["plan"]]
		if envelope.get("actor")!=snapshot.get("player",{}).get("player_id") or cmd.get("kind")!="buy" or cmd.get("payload",{}).get("firm")!=Opening.FIRM or cmd.get("payload",{}).get("buyer_site")!=p["site"] or cmd.get("payload",{}).get("good")!=p["good"]:return "委托日志行动身份不符"
		if entry.get("envelope",{}).get("command",{}).get("minute")!=row["minute"] or entry.get("result",{}).get("accepted")!=row["accepted"]:return "委托日志无正式行动依据"
		latest[row["plan"]]=row
		previous=int(row["sequence"])
	for key: String in latest:
		if value["plans"][key]["last_action"]!=latest[key]["action"] or value["plans"][key]["last_minute"]!=latest[key]["minute"]:return "委托最新行动引用不一致"
	return ""

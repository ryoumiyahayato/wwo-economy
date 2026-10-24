extends RefCounted
## Development access to existing public listings; no money, stock or actors added.
const Base=preload("res://merchant/regional_reaction_opening.gd")
const Multi=preload("res://merchant/multisource_opening.gd")
const Opening=preload("res://merchant/merchant_opening.gd")
const CASE="MERCHANT_ADAPTIVE_CONTACTS"
const CONDITIONS=["adaptive_open","adaptive_disruption","adaptive_bypass","adaptive_no_publicity"]
const CLOSE_MINUTE=12*1440
const REOPEN_MINUTE=35*1440

static func configuration() -> Dictionary:
	var cfg: Dictionary=Base.configuration()
	var original: Dictionary=Multi.totals(cfg)
	cfg.case_id=CASE
	var sites: Dictionary={}
	for firm: Dictionary in cfg.firms:
		for site: Dictionary in firm.sites:sites[site.id]={"owner":firm.id,"site":site}
	# One opening introduction per good. Two existing business needs start
	# without their previous address, allowing the original information path
	# to be observed. Household living introductions remain intact.
	for id: String in sites:
		var site: Dictionary=sites[id].site
		var kept: Array=[];var seen: Dictionary={}
		for candidate: String in site.suppliers:
			var good: String=candidate.split("|")[1]
			if (id=="site:regional_food:lyon" and good=="clothes") or (id=="site:regional_textile:lyon" and good=="bread"):continue
			if not seen.has(good):kept.append(candidate);seen[good]=true
		site.suppliers=kept
	var information: Array=[]
	for row: Dictionary in cfg.information:
		if row.kind=="supplier" and sites.has(row.actor) and row.candidate not in sites[row.actor].site.suppliers:continue
		information.append(row)
	cfg.information=information
	# An explicitly public inter-city directory grants search access, not
	# received knowledge, quantities, cash or an executable quote. Audience
	# follows existing places and own business desks, not hand-written pairs.
	cfg.supplier_directory=[];cfg.supplier_search=[]
	for id: String in sites:
		var seller: Dictionary=sites[id]
		var audience: Array=[]
		for buyer: String in sites:
			if sites[buyer].owner!=seller.owner and sites[buyer].site.place_id!=seller.site.place_id:audience.append(buyer)
		for good: String in seller.site.prices:
			if audience.is_empty():continue
			cfg.supplier_directory.append({"seller":seller.owner,"site_id":id,"good":good,"zone":"development_public_intercity_directory","known_to":audience.duplicate(),"available_day":1})
		cfg.supplier_search.append({"firm":seller.owner,"site_id":id,"local_zones":[],"regional_zones":[],"scope_basis":"HOST_SPACE","allow_wide":true,"delay_days":{"LOCAL":1,"REGIONAL":2,"WIDE":3},"result_limit":1,"max_known":4,"cooldown_days":3})
	cfg.commercial_information={"basis":"EXPLICIT_DEVELOPMENT_COMMERCIAL_INFORMATION","channels":[],"npc_policies":[]}
	# Existing staffed producers may publicize their actual unsold goods.
	for terms: Array in [["firm:regional_textile","site:regional_textile:lyon","clothes"],["firm:regional_food","site:regional_food:paris","bread"]]:
		var seller: Dictionary=sites[terms[1]]
		var audience: Array=[]
		for buyer: String in sites:
			if sites[buyer].owner!=seller.owner and sites[buyer].site.place_id==seller.site.place_id:audience.append(buyer)
		var channel: String="channel:adaptive:local:"+str(terms[1])
		cfg.commercial_information.channels.append({"id":channel,"kind":"SITE_BOARD","place_id":seller.site.place_id,"service_offer":"","recipients":audience,"recipient_limit":audience.size(),"delay_days":1,"cooldown_days":4,"window_days":7,"window_limit":2,"basis":"EXPLICIT_DEVELOPMENT_PUBLICATION_CHANNEL","audience_basis":"LOCAL_NAMED_PERSON_OR_POOLED_PURCHASING_DESK_NOT_MEMBER_KNOWLEDGE"})
		cfg.commercial_information.npc_policies.append({"id":"publicity:adaptive:"+str(terms[1])+":"+str(terms[2]),"firm":terms[0],"site_id":terms[1],"kind":"GOODS","item":terms[2],"channel_id":channel,"valid_days":4,"minimum_stock":1,"sales_window":7,"sales_at_most":2,"max_fee":0,"cash_floor":5,"basis":"EXPLICIT_DEVELOPMENT_OWN_SALES_PUBLICITY_POLICY"})
	# Adopt existing bounded cash/labor responses, without credit or grants.
	cfg.liquidity_policies=[];cfg.labor_response_policies=[]
	for firm: Dictionary in cfg.firms:
		if firm.id==Opening.FIRM:continue
		cfg.liquidity_policies.append({"firm":firm.id,"currency":FormalLedgerState.DENOMINATION,"cash_floor":5,"protect_due_wages":true,"finance_due_wages":false,"pause_after_days":3,"recover_cash":12,"wind_down_after_days":0,"pause_investment":true,"basis":"EXPLICIT_DEVELOPMENT_LIQUIDITY_POLICY"})
	for actor: Dictionary in cfg.actors:
		if actor.control=="automatic":cfg.labor_response_policies.append({"actor":actor.id,"arrears_days":3,"basis":"EXPLICIT_DEVELOPMENT_LABOR_RESPONSE"})
	assert(Multi.totals(cfg)==original,"Contact opening changed money/goods")
	return cfg

static func build() -> WorldBuildResult:
	return WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,false,{"format":"HOST_REGION_SELECTION","person_ids":[],"select_people_at_sites":true,"configuration":configuration()})

static func apply_condition(world: WorldState,condition: String) -> Dictionary:
	if world.economy_r1==null or world.economy_r1.config.get("case_id")!=CASE or condition not in CONDITIONS:return {"accepted":false,"reason":"NOT_ADAPTIVE_CONTACTS"}
	var e: EconomyR1Slice=world.economy_r1
	var minute: int=world.game_clock.total_minutes()
	var closed: bool=condition!="adaptive_open" and minute>=CLOSE_MINUTE and minute<REOPEN_MINUTE
	for terms: Array in [[Multi.EDGE,0 if closed else 10],[Base.BYPASS,2 if closed and condition=="adaptive_bypass" else 0]]:
		if int(e._transport.edges[terms[0]].capacity)==int(terms[1]):continue
		var result: Dictionary=e.submit_internal(Opening.FIRM,e._auto_command(Opening.FIRM,"set_edge_capacity",{"edge_id":terms[0],"capacity":terms[1]},"adaptive_schedule:"+str(terms[0])))
		if not result.get("accepted",false):return result
	if condition=="adaptive_no_publicity" and minute==0:
		for policy: Dictionary in e._commercial.policies():
			if not e._commercial._policy_enabled[policy.id]:continue
			var result: Dictionary=e.submit_internal(policy.firm,e._auto_command(policy.firm,"set_publicity_policy",{"policy_id":policy.id,"enabled":false},"explicit_publicity_counterfactual:"+str(policy.id)))
			if not result.get("accepted",false):return result
	return {"accepted":true,"reason":"ADAPTIVE_DEVELOPMENT_CONDITION"}

static func minutes_to_boundary(minute: int) -> int:
	for boundary: int in [CLOSE_MINUTE,REOPEN_MINUTE]:
		if minute<boundary:return boundary-minute
	return 60

static func subjects(world: WorldState) -> Array[Dictionary]:
	if world.economy_r1==null or world.economy_r1.config.get("case_id")!=CASE:return []
	var rows: Array[Dictionary]=[{"id":"","label":"本商号合法视图"}]
	var names: Dictionary={"firm:regional_food":"食品厂","firm:regional_upstream":"里昂上游","firm:regional_textile":"纺织企业","firm:regional_household":"马赛日用品厂"}
	for firm: Dictionary in world.economy_r1.config.firms:
		if firm.id!=Opening.FIRM:rows.append({"id":firm.id,"label":"研究观察："+str(names.get(firm.id,firm.id))})
	return rows
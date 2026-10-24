extends RefCounted
const Base=preload("res://merchant/adaptive_contacts_opening.gd")
const Multi=preload("res://merchant/multisource_opening.gd")
const Opening=preload("res://merchant/merchant_opening.gd")
const Reaction=preload("res://merchant/regional_reaction_opening.gd")
const CASE="MERCHANT_COMMERCIAL_ADAPTATION"
const CONDITIONS=["commercial_reference","commercial_inventory","commercial_quotes","commercial_combined"]
static func configuration(condition: String) -> Dictionary:
	assert(condition in CONDITIONS)
	var cfg: Dictionary=Base.configuration()
	var original: Dictionary=Multi.totals(cfg)
	cfg.case_id=CASE
	cfg["operating_inventory"]={"enabled":condition in ["commercial_inventory","commercial_combined"],"window_days":14,"idle_days":14,"trial_units":1,"sales_cover_days":7,"cash_share_percent":25,"basis":"DEVELOPMENT_OWN_SALES_INVENTORY_POLICY"}
	cfg.local_quotation_experiment["renew_same_terms"]=condition in ["commercial_quotes","commercial_combined"]
	assert(Multi.totals(cfg)==original)
	return cfg
static func build(condition: String) -> WorldBuildResult:
	return WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,false,{"format":"HOST_REGION_SELECTION","person_ids":[],"select_people_at_sites":true,"configuration":configuration(condition)})
static func apply_condition(world: WorldState,condition: String) -> Dictionary:
	if condition not in CONDITIONS or world.economy_r1==null or world.economy_r1.config.get("case_id")!=CASE:return {"accepted":false,"reason":"NOT_COMMERCIAL_ADAPTATION"}
	var e: EconomyR1Slice=world.economy_r1
	for terms: Array in [[Multi.EDGE,10],[Reaction.BYPASS,0]]:
		if int(e._transport.edges[terms[0]].capacity)==int(terms[1]):continue
		var result: Dictionary=e.submit_internal(Opening.FIRM,e._auto_command(Opening.FIRM,"set_edge_capacity",{"edge_id":terms[0],"capacity":terms[1]},"commercial_same_transport:"+str(terms[0])))
		if not result.get("accepted",false):return result
	return {"accepted":true,"reason":"SAME_OPEN_TRANSPORT_FOR_RULE_COMPARISON"}
static func subjects(world: WorldState) -> Array[Dictionary]:
	if world.economy_r1==null or world.economy_r1.config.get("case_id")!=CASE:return []
	var rows: Array[Dictionary]=[{"id":"","label":"本商号合法视图"}]
	var names: Dictionary={"firm:regional_food":"食品厂","firm:regional_upstream":"里昂上游","firm:regional_textile":"纺织企业","firm:regional_household":"马赛日用品厂"}
	for firm: Dictionary in world.economy_r1.config.firms:
		if firm.id!=Opening.FIRM:rows.append({"id":firm.id,"label":"研究观察："+str(names.get(firm.id,firm.id))})
	return rows

extends RefCounted
## Explicit development assumptions over existing firms, recipes and accounts.
const Multi=preload("res://merchant/multisource_opening.gd")
const Opening=preload("res://merchant/merchant_opening.gd")
const CASE="MERCHANT_REGIONAL_REACTION"
const CONDITIONS=["regional_normal","regional_disruption","regional_bypass"]
const BYPASS="edge:research:marseille:paris"
const CLOSE_MINUTE=6*1440
const REOPEN_MINUTE=15*1440

static func configuration() -> Dictionary:
	var cfg: Dictionary=Multi.configuration("normal")
	var initial: Dictionary=Multi.totals(cfg)
	cfg.case_id=CASE
	# Independent only in this experiment. Not a catalog railway/road/shipping link.
	var known: Array=[]
	for firm: Dictionary in cfg.firms:known.append(firm.id)
	cfg.routes.append({"id":BYPASS,"from_place_id":"place:marseille","to_place_id":"place:paris","capacity":2,"delay":5,"carrier":"carrier:regional_development","freight_per_unit":3,"known_to":known,"capacity_manager":Opening.FIRM,"basis":"SYNTHETIC"})
	# Original bounded quotation mechanism: own stock/sales evidence, delayed notices.
	cfg.local_quotation_experiment.npc_enabled=true
	for terms: Array in [["firm:regional_upstream",Multi.LYON,"grain"],["firm:regional_food","site:regional_food:paris","bread"],["firm:regional_household",Multi.COAST,"soap"]]:
		cfg.local_quotation_experiment.rules.append({"firm":terms[0],"site":terms[1],"good":terms[2],"period":3,"window":3,"tick":1,"tight":2,"volume":6,"idle_cover":2,"notice_days":2,"valid_days":30,"authority_basis":"DEVELOPMENT_FIRM_SALES_MANDATE"})
	assert(Multi.totals(cfg)==initial,"Reaction opening created goods or cash")
	return cfg

static func build() -> WorldBuildResult:
	return WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,false,{"format":"HOST_REGION_SELECTION","person_ids":[],"select_people_at_sites":true,"configuration":configuration()})

static func apply_condition(world: WorldState,condition: String) -> Dictionary:
	if condition not in CONDITIONS or world.economy_r1==null or world.economy_r1.config.get("case_id")!=CASE:return {"accepted":false,"reason":"NOT_REGIONAL_REACTION"}
	var minute: int=world.game_clock.total_minutes()
	var limited: bool=condition!="regional_normal" and minute>=CLOSE_MINUTE and minute<REOPEN_MINUTE
	var changes: Array=[]
	for terms: Array in [[Multi.EDGE,0 if limited else 10],[BYPASS,2 if limited and condition=="regional_bypass" else 0]]:
		if int(world.economy_r1._transport.edges[terms[0]].capacity)==int(terms[1]):continue
		var action: Dictionary=world.economy_r1.submit_internal(Opening.FIRM,world.economy_r1._auto_command(Opening.FIRM,"set_edge_capacity",{"edge_id":terms[0],"capacity":terms[1]},"regional_reaction:"+str(terms[0])))
		if not action.get("accepted",false):return action
		changes.append(action)
	return {"accepted":true,"reason":"DEVELOPMENT_SCHEDULE_APPLIED","changes":changes,"main_capacity":0 if limited else 10,"bypass_capacity":2 if limited and condition=="regional_bypass" else 0}

static func minutes_to_boundary(minute: int) -> int:
	for boundary: int in [CLOSE_MINUTE,REOPEN_MINUTE]:
		if minute<boundary:return boundary-minute
	return 60

static func subjects(world: WorldState) -> Array[Dictionary]:
	var rows: Array[Dictionary]=[{"id":"","label":"本商号合法视图"}]
	if world.economy_r1==null or world.economy_r1.config.get("case_id")!=CASE:return []
	var names: Dictionary={"firm:regional_food":"食品厂","firm:regional_upstream":"里昂上游","firm:regional_textile":"纺织企业","firm:regional_household":"马赛日用品厂"}
	for firm: Dictionary in world.economy_r1.config.firms:
		if firm.id!=Opening.FIRM:rows.append({"id":firm.id,"label":"研究观察："+str(names.get(firm.id,firm.id))})
	return rows

extends RefCounted
## Finite initial allocation, not a migration or a live grant.
const Opening=preload("res://merchant/merchant_opening.gd")
const EDGE="edge:regional:lyon:paris"
const CASE="MERCHANT_FINITE_MULTISOURCE"
const PARIS="site:regional_textile:paris"
const LYON="site:regional_upstream:lyon"
const COAST="site:regional_household:marseille"
const CONDITIONS=["normal","blocked","cash_limited","notice_delayed","two_goods"]

static func site(cfg: Dictionary,id: String) -> Dictionary:
	for firm: Dictionary in cfg.firms:
		for row: Dictionary in firm.sites:
			if row.id==id:return row
	return {}

static func totals(cfg: Dictionary) -> Dictionary:
	var goods: Dictionary={};var cash: int=0
	for firm: Dictionary in cfg.firms:
		cash+=int(firm.cash)
		for row: Dictionary in firm.sites:
			for good: String in row.stock:goods[good]=int(goods.get(good,0))+int(row.stock[good])
	for actor: Dictionary in cfg.actors:
		cash+=int(actor.cash)
		for good: String in actor.stock:goods[good]=int(goods.get(good,0))+int(actor.stock[good])
	for carrier: Dictionary in cfg.get("carriers",[]):cash+=int(carrier.cash)
	return {"cash":cash,"goods":goods}

static func configuration(condition: String="normal") -> Dictionary:
	var cfg: Dictionary=Opening.regional_configuration()
	var original: Dictionary=totals(cfg)
	cfg.case_id=CASE
	# Existing Lyon18 becomes Lyon8, Marseille6 and Paris4. No new quantity.
	site(cfg,LYON).stock.grain-=10
	site(cfg,COAST).stock.grain=6;site(cfg,COAST).prices.grain=2
	site(cfg,PARIS).stock.grain=4;site(cfg,PARIS).prices.grain=6
	site(cfg,Opening.SITE).targets.grain=6;site(cfg,Opening.SITE).prices.grain=7
	if condition=="two_goods":site(cfg,Opening.SITE).targets.soap=2 # Existing listed good, original price/recipe/sources.
	# Explicit introductions only, including the existing real production buyer.
	for terms: Array in [["firm:regional_textile",PARIS],["firm:regional_household",COAST]]:
		var candidate: String=terms[0]+"|grain|"+terms[1]
		for buyer: String in [Opening.SITE,Opening.LYON_SITE,"site:regional_food:paris"]:
			site(cfg,buyer).suppliers.append(candidate)
			cfg.information.append({"actor":buyer,"kind":"supplier","candidate":candidate,"delivery_day":3 if condition=="notice_delayed" and terms[1]==COAST else 0})
	for route: Dictionary in cfg.routes:
		if route.id==EDGE:route.capacity_manager=Opening.FIRM
	if condition=="cash_limited":
		# Same finite total capital; sixty units are allocated to the upstream firm.
		for firm: Dictionary in cfg.firms:
			if firm.id==Opening.FIRM:firm.cash-=60
			if firm.id=="firm:regional_upstream":firm.cash+=60
	assert(totals(cfg)==original,"Initial allocation changed total goods/cash")
	return cfg

static func build(condition: String="normal") -> WorldBuildResult:
	var failed:=WorldBuildResult.new()
	if condition not in CONDITIONS:failed.error="UNKNOWN_MULTISOURCE_CONDITION";return failed
	return WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,false,{"format":"HOST_REGION_SELECTION","person_ids":[],"select_people_at_sites":true,"configuration":configuration(condition)})

static func capacity(world: WorldState,amount: int) -> Dictionary:
	if world.economy_r1==null or world.economy_r1.config.get("case_id")!=CASE:return {"accepted":false,"reason":"NOT_MULTISOURCE_EXPERIMENT"}
	return world.economy_r1.submit_internal(Opening.FIRM,world.economy_r1._auto_command(Opening.FIRM,"set_edge_capacity",{"edge_id":EDGE,"capacity":amount},"multisource_condition"))

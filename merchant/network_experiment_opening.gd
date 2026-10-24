extends RefCounted
## Explicit initial assumption only: existing merchant keeps six grain for resale.
## Existing firms, opening cash, goods, recipes and transport are unchanged.
const Opening=preload("res://merchant/merchant_opening.gd")
const EDGE: String="edge:regional:lyon:paris"
const CASE: String="MERCHANT_NETWORK_CAPACITY_EXPERIMENT"

static func configuration() -> Dictionary:
	var cfg: Dictionary=Opening.regional_configuration()
	cfg.case_id=CASE
	for firm: Dictionary in cfg.firms:
		if firm.id==Opening.FIRM:
			for site: Dictionary in firm.sites:
				if site.id==Opening.SITE:site.targets.grain=6
	# Development mandate for this experiment. It confers no player permission
	# in a loaded save. The original submit_internal journal enforces the manager.
	for route: Dictionary in cfg.routes:
		if route.id==EDGE:route.capacity_manager=Opening.FIRM
	return cfg

static func build() -> WorldBuildResult:
	return WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,false,{"format":"HOST_REGION_SELECTION","person_ids":[],"select_people_at_sites":true,"configuration":configuration()})

static func capacity(world: WorldState, amount: int) -> Dictionary:
	if world.economy_r1.config.get("case_id")!=CASE:return {"accepted":false,"reason":"NOT_ISOLATED_NETWORK_EXPERIMENT"}
	var economy: EconomyR1Slice=world.economy_r1
	return economy.submit_internal(Opening.FIRM,economy._auto_command(Opening.FIRM,"set_edge_capacity",{"edge_id":EDGE,"capacity":amount},"network_experiment"))

extends RefCounted
## Independent, explicit development scenario. No production save is read.
const FIRM: String = "firm:merchant_prototype"
const SITE: String = "site:merchant_prototype:paris"
const ORGANIZATION: String = "organization:development_merchant_prototype"
const AUTHORITY: String = "authority:merchant_prototype:grain_quote"

static func configuration() -> Dictionary:
	var cfg: Dictionary = EconomyDevelopmentConfig.regional_template()
	var zero: Dictionary = EconomySliceConfig.zero_stock(EconomySliceConfig.good_ids(cfg))
	var site: Dictionary = {"id":SITE,"place_id":"place:paris","roles":["storage","sales"],"stock":zero.duplicate(),"targets":zero.duplicate(),"prices":{"grain":5},"capacity":0,"activities":[],"suppliers":["firm:regional_upstream|grain|site:regional_upstream:lyon"],"enabled":true,"production_enabled":false,"accepting_business":true,"basis":"DEVELOPMENT_CONFIGURATION","coordination_delay":1}
	# Finite host opening endowment, not a second personal wallet or earned profit.
	cfg["firms"].push_front({"id":FIRM,"place_id":"place:paris","account_id":"account:merchant_prototype","cash":80,"sites":[site],"host_organization_id":ORGANIZATION})
	cfg["development_organizations"]=[{"organization_id":ORGANIZATION,"firm_id":FIRM,"basis":"EXPLICIT_DEVELOPMENT_COMMERCIAL_ORGANIZATION"}]
	cfg["firm_operations"].append({"firm":FIRM,"planning_horizon":4,"buffer_days":1,"demand_window":3,"manage_jobs":false})
	cfg["information"].append({"actor":SITE,"kind":"supplier","candidate":"firm:regional_upstream|grain|site:regional_upstream:lyon","delivery_day":0})
	for firm: Dictionary in cfg["firms"]:
		for buyer_site: Dictionary in firm["sites"]:
			if buyer_site["id"]=="site:regional_food:paris": buyer_site["suppliers"].append(FIRM+"|grain|"+SITE)
	cfg["information"].append({"actor":"site:regional_food:paris","kind":"supplier","candidate":FIRM+"|grain|"+SITE,"delivery_day":1})
	for route: Dictionary in cfg["routes"]:
		if route["from_place_id"] in ["place:paris","place:lyon"] and route["to_place_id"] in ["place:paris","place:lyon"]:
			route["known_to"].append(FIRM)
	cfg["local_quotation_experiment"]={"basis":"GENERATED_SIMULATION_ASSUMPTION_LOCAL_QUOTATIONS","npc_enabled":false,"rules":[{"firm":FIRM,"site":SITE,"good":"grain","period":3,"window":3,"tick":1,"tight":2,"volume":6,"idle_cover":2,"notice_days":1,"valid_days":30,"authority_basis":"DEVELOPMENT_FIRM_SALES_MANDATE"}]}
	return cfg

static func grant_quote_authority(world: WorldState) -> bool:
	var person: String = world.player_state.player_id()
	if world.economy_r1.firm_manager_at(FIRM,world.game_clock.total_minutes())!=person: return false
	return world.organization_state.add_authority_grant({"authority_id":AUTHORITY,"holder":{"kind":"position","organization_id":ORGANIZATION,"local_id":"economic_operator","person_id":""},"represented_entity":ORGANIZATION,"operation":"economy.goods.quote","target_scope":[FIRM],"spatial_scope":["place:paris"],"subject_scope":["goods:grain"],"amount_or_quantity_limit":12.0,"valid_from":world.game_clock.current_hour(),"valid_until":world.game_clock.current_hour()+720,"basis":{"kind":"generated_simulation_assumption","id":"merchant:opening:grain_sales"},"revocable":true,"delegable":false,"exclusive_or_concurrent":"concurrent","additional_constraints":{"allowed_stages":["domain_execution"],"required_procedure_id":"","notes":"Only grain quotes for this merchant and Paris premises. Unit-price cap 12; no capital, credit or distribution permission."},"accountability":{"organization_id":ORGANIZATION,"relation_id":""},"revoked_at":-1})

static func quote_context(world: WorldState) -> Dictionary:
	return OrganizationState.acting_context(world.player_state.player_id(),ORGANIZATION,ORGANIZATION,AUTHORITY,"opening_operator")

const LYON_SITE: String="site:merchant_prototype:lyon"
const REGIONAL_AUTHORITY: String="authority:merchant_prototype:regional_quotes"
const TRADE_GOODS: Array[String]=["grain","beans","fiber","oil","bread","clothes","soap"]

static func regional_configuration() -> Dictionary:
	# Explicit separate opening. Never merged into a loaded legacy world.
	var cfg: Dictionary=configuration()
	cfg["case_id"]="MERCHANT_REGIONAL_03"
	var merchant: Dictionary=cfg["firms"][0]
	var paris: Dictionary=merchant["sites"][0]
	paris["prices"]={"grain":5,"beans":6,"fiber":5,"oil":5,"bread":8,"clothes":45,"soap":10}
	var lyon: Dictionary=paris.duplicate(true)
	lyon["id"]=LYON_SITE;lyon["place_id"]="place:lyon";lyon["prices"]={};lyon["roles"]=["storage"]
	merchant["sites"].append(lyon)
	var sources: Array[String]=[]
	for firm: Dictionary in cfg["firms"]:
		if firm["id"]==FIRM:continue
		for site: Dictionary in firm["sites"]:
			for good: String in site["prices"]:
				if good in TRADE_GOODS:sources.append(firm["id"]+"|"+good+"|"+site["id"])
	for site: Dictionary in merchant["sites"]:
		site["suppliers"]=sources.duplicate()
		for candidate: String in sources:
			if not cfg["information"].any(func(row: Dictionary)->bool:return row["actor"]==site["id"] and row.get("candidate")==candidate):
				cfg["information"].append({"actor":site["id"],"kind":"supplier","candidate":candidate,"delivery_day":0})
	# Existing NPC firms receive explicit introductions only for goods they use.
	for firm: Dictionary in cfg["firms"]:
		if firm["id"]==FIRM:continue
		for site: Dictionary in firm["sites"]:
			var needed: Array[String]=[]
			for activity: Dictionary in site["activities"]:
				for good: String in activity["materials"]:
					if int(activity["materials"][good])>0 and good not in needed:needed.append(good)
			for good: String in site["targets"]:
				if int(site["targets"][good])>0 and good not in needed:needed.append(good)
			for own: Dictionary in merchant["sites"]:
				for good: String in needed:
					if good not in own["prices"]:continue
					var candidate: String=FIRM+"|"+good+"|"+own["id"]
					if candidate in site["suppliers"]:continue
					site["suppliers"].append(candidate)
					cfg["information"].append({"actor":site["id"],"kind":"supplier","candidate":candidate,"delivery_day":1})
	for actor: Dictionary in cfg["actors"]:
		for own: Dictionary in merchant["sites"]:
			if actor["place_id"]!=own["place_id"] or own["prices"].is_empty():continue
			for good: String in ["beans","bread","clothes","soap"]:
				cfg["information"].append({"actor":actor["id"],"kind":"supplier","candidate":FIRM+"|"+good+"|"+own["id"],"delivery_day":1})
	for route: Dictionary in cfg["routes"]:
		if FIRM not in route["known_to"]:route["known_to"].append(FIRM)
	for path: Dictionary in cfg["transport_paths"]:
		if FIRM not in path["known_to"]:path["known_to"].append(FIRM)
	var rules: Array[Dictionary]=[]
	for site: Dictionary in merchant["sites"]:
		for good: String in site["prices"]:
			rules.append({"firm":FIRM,"site":site["id"],"good":good,"period":30,"window":3,"tick":1,"tight":2,"volume":6,"idle_cover":2,"notice_days":1,"valid_days":90,"authority_basis":"DEVELOPMENT_FIRM_SALES_MANDATE"})
	cfg["local_quotation_experiment"]["rules"]=rules
	return cfg

static func grant_regional_authority(world: WorldState) -> bool:
	var person: String=world.player_state.player_id()
	if world.economy_r1.firm_manager_at(FIRM,world.game_clock.total_minutes())!=person:return false
	var subjects: Array[String]=[]
	for good: String in TRADE_GOODS:subjects.append("goods:"+good)
	return world.organization_state.add_authority_grant({"authority_id":REGIONAL_AUTHORITY,"holder":{"kind":"position","organization_id":ORGANIZATION,"local_id":"economic_operator","person_id":""},"represented_entity":ORGANIZATION,"operation":"economy.goods.quote","target_scope":[FIRM],"spatial_scope":["place:paris"],"subject_scope":subjects,"amount_or_quantity_limit":120.0,"valid_from":world.game_clock.current_hour(),"valid_until":world.game_clock.current_hour()+2160,"basis":{"kind":"generated_simulation_assumption","id":"merchant:regional03:sales"},"revocable":true,"delegable":false,"exclusive_or_concurrent":"concurrent","additional_constraints":{"allowed_stages":["domain_execution"],"required_procedure_id":"","notes":"Explicit new regional opening; seven goods, Paris sales premises, price cap 120, ninety days; no capital or credit authority."},"accountability":{"organization_id":ORGANIZATION,"relation_id":""},"revoked_at":-1})

const COMPETITOR: String="firm:city_competitor"
const COMPETITOR_SITE: String="site:city_competitor:paris"
static func supply_configuration() -> Dictionary:
	# Explicit third opening. These are finite scenario endowments, never a migration.
	var cfg: Dictionary=regional_configuration()
	cfg["case_id"]="MERCHANT_CITY_SUPPLY_05"
	for firm: Dictionary in cfg["firms"]:
		if firm["id"]==FIRM:firm["cash"]=320
		if firm["id"]=="firm:regional_food":firm["cash"]=600
		if firm["id"]=="firm:regional_upstream":
			firm["sites"][0]["targets"]["grain"]=24
			firm["sites"][0]["stock"]["grain"]=100
	for node: Dictionary in cfg["transport_nodes"]:
		if node["place_id"]=="place:lyon":node["capacity"]=32
	for job: Dictionary in cfg["jobs"]:
		if job["employer"]=="firm:regional_upstream":job["hours"]=4
	for route: Dictionary in cfg["routes"]:
		if route["from_place_id"] in ["place:lyon","place:paris"] and route["to_place_id"] in ["place:lyon","place:paris"] and route["from_place_id"]!=route["to_place_id"]:route["capacity"]=16
		if COMPETITOR not in route["known_to"]:route["known_to"].append(COMPETITOR)
	for path: Dictionary in cfg["transport_paths"]:path["known_to"].append(COMPETITOR)
	var zero: Dictionary=EconomySliceConfig.zero_stock(EconomySliceConfig.good_ids(cfg))
	var source: String="firm:regional_upstream|grain|site:regional_upstream:lyon"
	var site: Dictionary={"id":COMPETITOR_SITE,"place_id":"place:paris","roles":["storage","sales"],"stock":zero.duplicate(),"targets":zero.duplicate(),"prices":{"grain":5},"capacity":0,"activities":[],"suppliers":[source],"enabled":true,"production_enabled":false,"accepting_business":true,"basis":"DEVELOPMENT_CONFIGURATION","coordination_delay":1}
	cfg["firms"].append({"id":COMPETITOR,"place_id":"place:paris","account_id":"account:city_competitor","cash":80,"sites":[site]})
	cfg["firm_operations"].append({"firm":COMPETITOR,"planning_horizon":4,"buffer_days":1,"demand_window":3,"manage_jobs":false})
	cfg["information"].append({"actor":COMPETITOR_SITE,"kind":"supplier","candidate":source,"delivery_day":0})
	var competitor_offer: String=COMPETITOR+"|grain|"+COMPETITOR_SITE
	for firm: Dictionary in cfg["firms"]:
		for stock_site: Dictionary in firm["sites"]:
			if stock_site["id"] in [SITE,LYON_SITE,"site:regional_food:paris"]:
				stock_site["suppliers"].append(competitor_offer)
				cfg["information"].append({"actor":stock_site["id"],"kind":"supplier","candidate":competitor_offer,"delivery_day":0})
	cfg["supply_contracts"]={"id":"supply:paris:grain:1","buyer":"firm:regional_food","buyer_site":"site:regional_food:paris","supplier":FIRM,"supplier_site":SITE,"good":"grain","quantity":80,"days":10,"premium":1,"competitor":COMPETITOR,"competitor_site":COMPETITOR_SITE,"competitor_target":12,"competitor_batch":3,"basis":"EXPLICIT_DEVELOPMENT_CITY_SUPPLY"}
	return cfg

static func opportunities_configuration() -> Dictionary:
	# Separate fourth slot: identical finite endowments, no saved-world migration.
	var cfg: Dictionary=supply_configuration()
	cfg["case_id"]="MERCHANT_OPPORTUNITIES_08"
	cfg["supply_opportunity_policies"]=[]
	for terms: Array in [["grain","firm:regional_food","site:regional_food:paris",5,8,6,240],["soap","firm:regional_textile","site:regional_textile:paris",2,5,5,120]]:
		cfg["supply_opportunity_policies"].append({"id":"procurement:"+terms[0],"buyer":terms[1],"buyer_site":terms[2],"supplier":FIRM,"supplier_site":SITE,"good":terms[0],"max_quantity":terms[3],"days":terms[4],"premium":1,"cooldown_days":terms[5],"notice_days":1,"max_publications":12,"max_commitment":terms[6],"basis":"EXPLICIT_DEVELOPMENT_PROCUREMENT_MANDATE"})
	# Existing integer tick quotation policy, limited to the competitor's own sales.
	cfg["local_quotation_experiment"]["npc_enabled"]=true
	cfg["local_quotation_experiment"]["rules"].append({"firm":COMPETITOR,"site":COMPETITOR_SITE,"good":"grain","period":3,"window":3,"tick":1,"tight":2,"volume":6,"idle_cover":2,"notice_days":1,"valid_days":30,"authority_basis":"DEVELOPMENT_FIRM_SALES_MANDATE"})
	return cfg

static func feedback_configuration() -> Dictionary:
	# Explicit opt-in candidate opening; no existing slot or saved configuration is migrated.
	# Aggregate workers remain actors in the original ledger/lots/employment model.
	var cfg: Dictionary=opportunities_configuration()
	cfg["case_id"]="MERCHANT_REGION_FEEDBACK_CANDIDATE"
	cfg["liquidity_policies"]=[]
	for firm: String in ["firm:regional_upstream","firm:regional_food","firm:regional_textile","firm:regional_household"]:
		cfg["liquidity_policies"].append({"firm":firm,"currency":FormalLedgerState.DENOMINATION,"cash_floor":5,"protect_due_wages":true,"finance_due_wages":false,"pause_after_days":3,"recover_cash":12,"wind_down_after_days":0,"pause_investment":true,"basis":"EXPLICIT_DEVELOPMENT_LIQUIDITY_POLICY"})
	cfg["labor_response_policies"]=[]
	for actor: Dictionary in cfg["actors"]:
		if actor["control"]=="automatic":
			cfg["labor_response_policies"].append({"actor":actor["id"],"arrears_days":3,"basis":"EXPLICIT_DEVELOPMENT_LABOR_RESPONSE"})
	# Deliberately bounded two-link pilot, not a replacement for all world prices.
	# Named people selected later retain their original policies; this opening covers
	# the four explicitly configured regional worker cohorts only.
	for source: Array in [["firm:regional_upstream","site:regional_upstream:lyon","grain"],["firm:regional_food","site:regional_food:paris","bread"]]:
		cfg["local_quotation_experiment"]["rules"].append({"firm":source[0],"site":source[1],"good":source[2],"period":3,"window":3,"tick":1,"tight":2,"volume":6,"idle_cover":2,"notice_days":1,"valid_days":30,"authority_basis":"DEVELOPMENT_FIRM_SALES_MANDATE"})
	return cfg

extends RefCounted
## Explicit research conditions. No new actors, cash, goods or transport.
const Base=preload("res://merchant/commercial_adaptation_opening.gd")
const Multi=preload("res://merchant/multisource_opening.gd")
const CASE="MERCHANT_CONSUMER_ACCESS"
const CHOICES=["choice_reference_sequential","choice_reference_window","choice_reference_buffer","choice_market_sequential","choice_market_window","choice_market_buffer"]
const TIME_CHOICES=["demand_late_legacy","demand_late_deadline","demand_late_bounded","demand_fast_legacy","demand_fast_deadline","demand_fast_bounded"]
const TURNOVER_CHOICES=["regional_turnover_reference","regional_turnover_adaptive"]
const PUBLICITY_CHOICES=["regional_publicity_reference","regional_publicity_work"]
const PUBLICITY_JOB="job:merchant_prototype:paris_notice"
const PUBLICITY_CHANNEL="channel:merchant_prototype:paris_board"
const CONDITIONS=["consumer_reference","consumer_enquiries","consumer_local_quotes","consumer_company_budget","consumer_market","consumer_combined","choice_reference_sequential","choice_reference_window","choice_reference_buffer","choice_market_sequential","choice_market_window","choice_market_buffer","demand_late_legacy","demand_late_deadline","demand_late_bounded","demand_fast_legacy","demand_fast_deadline","demand_fast_bounded","regional_turnover_reference","regional_turnover_adaptive","regional_publicity_reference","regional_publicity_work"]
static func configuration(condition: String) -> Dictionary:
	assert(condition in CONDITIONS)
	if condition in PUBLICITY_CHOICES:
		var common: Dictionary=configuration("regional_turnover_adaptive")
		# Both arms have the same unfilled fixed job and local board capability.
		# No worker, work record, supplier knowledge, cash or stock is inserted.
		common.jobs.append({"id":PUBLICITY_JOB,"employer":"firm:merchant_prototype","site_id":"site:merchant_prototype:paris","positions":1,"skill":1,"hours":1,"place":"place:paris","wage_per_hour":3,"wage_delay":1,"notice_delay":1})
		var audience: Array=[]
		for firm: Dictionary in common.firms:
			if firm.id=="firm:merchant_prototype":continue
			for site: Dictionary in firm.sites:
				if site.place_id=="place:paris":audience.append(site.id)
		common.commercial_information.channels.append({"id":PUBLICITY_CHANNEL,"kind":"SITE_BOARD","place_id":"place:paris","service_offer":"","recipients":audience,"recipient_limit":audience.size(),"delay_days":1,"cooldown_days":4,"window_days":7,"window_limit":2,"basis":"EXPLICIT_DEVELOPMENT_PUBLICATION_CHANNEL","audience_basis":"LOCAL_NAMED_PERSON_OR_POOLED_PURCHASING_DESK_NOT_MEMBER_KNOWLEDGE"})
		return common
	var cfg: Dictionary=Base.configuration("commercial_inventory")
	var initial: Dictionary=Multi.totals(cfg)
	cfg.case_id=CASE
	if condition.ends_with("_window") or condition.ends_with("_buffer"):
		cfg["household_choice"]={"mode":"buffer" if condition.ends_with("_buffer") else "window","horizon_days":7,"reserve_days":2,"uncertain_days":3,"max_reserve_percent":35,"basis":"DEVELOPMENT_ORIGINAL_HOUSEHOLD_TIMING_CHOICE"}
	if condition in ["consumer_enquiries","consumer_market","consumer_combined"] or condition.begins_with("choice_market_") or condition in TIME_CHOICES+TURNOVER_CHOICES:
		cfg["household_purchase_enquiries"]=true
		cfg.operating_inventory["enquiry_trial_by_buyer"]=true
	if condition in TIME_CHOICES+TURNOVER_CHOICES:
		if not condition.ends_with("_legacy"):
			cfg.operating_inventory["enquiry_response"]="bounded" if condition.ends_with("_bounded") else "deadline"
			cfg.operating_inventory["enquiry_response_goods"]=["soap"]
		# Controlled SAME existing route: only its admitted development travel time
		# differs. No stock, cash, price, buyer preference or information grant.
		if condition.begins_with("demand_fast_") or condition in TURNOVER_CHOICES:
			for route: Dictionary in cfg.routes:
				if route.id=="edge:regional:marseille:lyon":route.delay=1
	if condition in TURNOVER_CHOICES:
		# The EXISTING native cost observer, with no production/investment policy.
		# Both comparison arms have the same provenance and opening uncertainty.
		cfg["cost_accounting"]={"freight_treatment":"BUYER_ACQUISITION","joint_allocations":[],"npc_policies":[],"basis":"EXPLICIT_DEVELOPMENT_COST_POLICY"}
		if condition=="regional_turnover_adaptive":cfg.operating_inventory["turnover_adaptation"]=true
	if condition in ["consumer_company_budget","consumer_combined"]:
		cfg.operating_inventory["company_cash_window"]=true
		cfg.operating_inventory["stable_holding_age"]=true
		cfg.operating_inventory["durable_trial_limit"]=true
	if condition in ["consumer_local_quotes","consumer_market","consumer_combined"] or condition.begins_with("choice_market_"):
		# Existing seller mandate and quotation algorithm; a research extension
		# to an already known sales site, not a guaranteed profitable retail plan.
		cfg.local_quotation_experiment.rules.append({"firm":"firm:regional_textile","site":"site:regional_textile:marseille","good":"bread","period":3,"window":3,"tick":1,"tight":1,"volume":6,"idle_cover":2,"notice_days":2,"valid_days":30,"authority_basis":"DEVELOPMENT_FIRM_SALES_MANDATE","renew_same_terms":true})
	assert(Multi.totals(cfg)==initial)
	return cfg
static func build(condition: String) -> WorldBuildResult:
	return WorldBootstrap.new().build(null,[],[],FormalPersonalEconomyState.NO_FORMAL_EMPLOYMENT,false,{"format":"HOST_REGION_SELECTION","person_ids":[],"select_people_at_sites":true,"configuration":configuration(condition)})
static func apply_condition(world: WorldState,condition: String) -> Dictionary:
	if condition in PUBLICITY_CHOICES:return apply_condition(world,"regional_turnover_adaptive")
	if condition not in CONDITIONS or world.economy_r1==null or world.economy_r1.config.get("case_id")!=CASE:return {"accepted":false,"reason":"NOT_CONSUMER_ACCESS"}
	# Same formal transport actions as the commercial baseline.
	var e: EconomyR1Slice=world.economy_r1
	if condition in TIME_CHOICES+TURNOVER_CHOICES:
		var actor: String="cohort:regional:lyon_upstream"
		var offer: Dictionary=e._offer(actor,"firm:regional_food","soap","edge:regional_local:lyon","site:regional_food:lyon")
		var cmd: Dictionary=e._auto_command(actor,"buy",{"quote_id":offer.quote_id,"seller":offer.seller,"seller_site":offer.seller_site,"good":"soap","quantity":1,"denomination":offer.denomination,"max_price":offer.price,"path_id":offer.route_id,"need_category":"household","need_by_day":4},"CONTROLLED_FUTURE_DAY4_FUNDED_STOCK_ENQUIRY")
		# Only the initial NON-BINDING rejected attempt is controlled. Every later
		# purchase/dispatch/payment/consumption is the original autonomous path.
		if not e._commands.has(cmd.action_id) and e.day==0:
			var context: Dictionary=e.HouseholdTiming._context(e,actor)
			context.horizon=4
			var planned: Dictionary=e.HouseholdTiming._project(e,context,"RISK_HOLD")
			assert(planned.household.requirements[3].uncovered>0)
			assert(e._world.ledger_state.available_balance(e._account(actor))>=int(offer.price))
			var inquiry: Dictionary=e._accept(actor,cmd,true)
			assert(not inquiry.accepted and inquiry.reason=="NO_STOCK",str(inquiry))
	for terms: Array in [[Multi.EDGE,10],["edge:research:marseille:paris",0]]:
		if int(e._transport.edges[terms[0]].capacity)==int(terms[1]):continue
		var result: Dictionary=e.submit_internal("firm:merchant_prototype",e._auto_command("firm:merchant_prototype","set_edge_capacity",{"edge_id":terms[0],"capacity":terms[1]},"consumer_same_transport:"+str(terms[0])))
		if not result.get("accepted",false):return result
	return {"accepted":true,"reason":"SAME_EXISTING_TRANSPORT"}
static func subjects(world: WorldState) -> Array[Dictionary]:
	if world.economy_r1==null or world.economy_r1.config.get("case_id")!=CASE:return []
	var rows: Array[Dictionary]=[{"id":"","label":"本商号合法视图"}]
	var names: Dictionary={"firm:regional_food":"食品厂","firm:regional_upstream":"里昂上游","firm:regional_textile":"纺织企业","firm:regional_household":"马赛日用品厂"}
	for firm: Dictionary in world.economy_r1.config.firms:
		if firm.id!="firm:merchant_prototype":rows.append({"id":firm.id,"label":"研究观察："+str(names.get(firm.id,firm.id))})
	return rows
